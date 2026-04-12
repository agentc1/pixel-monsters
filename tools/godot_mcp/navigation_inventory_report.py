#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path
from typing import Any

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNTIME_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo Runtime.tscn"
RUNTIME_ROOT = "/root/GodotMcpRuntime/SceneHost/SC Demo Runtime"
OVERLAY_PATH = f"{RUNTIME_ROOT}/NavigationOverlay"
ARTIFACT_DIR = REPO_ROOT / "godot_project" / "tmp"
DEFAULT_OUTPUT = ARTIFACT_DIR / "navigation_inventory_report.json"


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write a live-scene navigation inventory report from the runtime navigation map."
    )
    parser.add_argument(
        "--window-mode",
        default="headless",
        choices=["headless", "windowed"],
        help="Run the Godot MCP scene headlessly or in a visible window.",
    )
    parser.add_argument(
        "--output",
        default=str(DEFAULT_OUTPUT),
        help="Path to write the JSON report artifact.",
    )
    parser.add_argument(
        "--hold-open-sec",
        type=float,
        default=0.0,
        help="Keep the visible Godot session open for this many seconds after the report is written.",
    )
    return parser.parse_args()


def _server_params() -> StdioServerParameters:
    return StdioServerParameters(
        command=sys.executable,
        args=["-m", "godot_mcp.server"],
        cwd=REPO_ROOT,
        env=dict(os.environ),
    )


def _structured(result) -> dict[str, Any]:
    if getattr(result, "isError", False):
        raise RuntimeError(f"Tool returned error: {result}")
    payload = getattr(result, "structuredContent", None)
    if payload is None:
        raise RuntimeError(f"Tool returned no structured content: {result}")
    if not payload.get("ok", True):
        raise RuntimeError(f"Tool returned failure: {payload}")
    return payload


async def _call(session: ClientSession, tool_name: str, args: dict[str, Any]) -> dict[str, Any]:
    return _structured(await session.call_tool(tool_name, args))


async def main() -> int:
    args = _parse_args()
    output_path = Path(str(args.output))
    if not output_path.is_absolute():
        output_path = REPO_ROOT / output_path

    async with stdio_client(_server_params()) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            try:
                play = await _call(
                    session,
                    "godot_play_scene",
                    {"scene_path": RUNTIME_SCENE, "window_mode": str(args.window_mode)},
                )
                if play.get("loaded_scene_path") != RUNTIME_SCENE:
                    raise AssertionError(play)
                rebuild = await _call(
                    session,
                    "godot_call_node_method",
                    {"node_path": OVERLAY_PATH, "method_name": "rebuild_navigation_overlay", "frames_after": 2},
                )
                if not rebuild.get("called") or not rebuild.get("result", {}).get("ok"):
                    raise AssertionError(rebuild)
                report_result = await _call(
                    session,
                    "godot_call_node_method",
                    {"node_path": OVERLAY_PATH, "method_name": "navigation_debug_report", "frames_after": 1},
                )
                if not report_result.get("called"):
                    raise AssertionError(report_result)
                report = dict(report_result.get("result", {}))
                artifact = {
                    "scene": RUNTIME_SCENE,
                    "window_mode": str(args.window_mode),
                    **report,
                }
                output_path.parent.mkdir(parents=True, exist_ok=True)
                output_path.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
                print(json.dumps(artifact, indent=2))
                if not bool(artifact.get("ok", False)):
                    return 1
                if float(args.hold_open_sec) > 0.0:
                    await asyncio.sleep(float(args.hold_open_sec))
            finally:
                await session.call_tool("godot_stop", {})
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
