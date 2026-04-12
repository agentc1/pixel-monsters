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
PLAYER_PATH = f"{RUNTIME_ROOT}/RuntimePlayer"
OVERLAY_PATH = f"{RUNTIME_ROOT}/NavigationOverlay"
ARTIFACT_DIR = REPO_ROOT / "godot_project" / "tmp"
DEFAULT_OUTPUT = ARTIFACT_DIR / "navigation_override_acceptance.json"
BLOCK_CELL = {"x": 5, "y": -2}
ORIGIN_CELL = {"x": 6, "y": -2}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate runtime navigation override editing through MCP.")
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


def _cell_from_payload(value: Any) -> tuple[int, int]:
    if isinstance(value, dict):
        return (int(round(float(value.get("x", 0)))), int(round(float(value.get("y", 0)))))
    raise TypeError(f"Unsupported cell payload: {value!r}")


async def _call(session: ClientSession, tool_name: str, args: dict[str, Any]) -> dict[str, Any]:
    return _structured(await session.call_tool(tool_name, args))


async def _load_runtime(session: ClientSession, window_mode: str) -> None:
    play = await _call(session, "godot_play_scene", {"scene_path": RUNTIME_SCENE, "window_mode": window_mode})
    if play.get("loaded_scene_path") != RUNTIME_SCENE:
        raise AssertionError(play)
    rebuild = await _call(
        session,
        "godot_call_node_method",
        {"node_path": OVERLAY_PATH, "method_name": "rebuild_navigation_overlay", "frames_after": 2},
    )
    if not rebuild.get("called") or not rebuild.get("result", {}).get("ok"):
        raise AssertionError(rebuild)


async def _call_overlay(session: ClientSession, method_name: str, args: list[Any] | None = None) -> dict[str, Any]:
    result = await _call(
        session,
        "godot_call_node_method",
        {"node_path": OVERLAY_PATH, "method_name": method_name, "args": args or [], "frames_after": 2},
    )
    if not result.get("called"):
        raise AssertionError(result)
    return result


async def _call_player(session: ClientSession, method_name: str, args: list[Any] | None = None) -> dict[str, Any]:
    result = await _call(
        session,
        "godot_call_node_method",
        {"node_path": PLAYER_PATH, "method_name": method_name, "args": args or [], "frames_after": 1},
    )
    if not result.get("called"):
        raise AssertionError(result)
    return result


async def _player_state(session: ClientSession) -> tuple[str, tuple[int, int]]:
    info = await _call(session, "godot_node_info", {"node_path": PLAYER_PATH})
    node = info.get("node", {})
    layer = str(node.get("meta", {}).get("cainos_runtime_collision_layer_name", "Layer 1"))
    cell_result = await _call_player(session, "grid_cell_for_position", [node.get("global_position", {})])
    return (layer, _cell_from_payload(cell_result.get("result", {})))


async def _assert_override_cleared(session: ClientSession) -> None:
    await _call_overlay(session, "clear_cell_override", ["Layer 1", BLOCK_CELL])
    await _call_overlay(session, "save_navigation_overrides")


async def main() -> int:
    args = _parse_args()
    output_path = Path(str(args.output))
    if not output_path.is_absolute():
        output_path = REPO_ROOT / output_path
    artifact: dict[str, Any] = {
        "scene": RUNTIME_SCENE,
        "window_mode": str(args.window_mode),
        "block_cell": BLOCK_CELL,
        "origin_cell": ORIGIN_CELL,
        "checks": [],
    }
    exit_code = 0

    async with stdio_client(_server_params()) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            try:
                await _load_runtime(session, str(args.window_mode))
                before_step = await _call_player(session, "can_grid_step_from_cell", ["Layer 1", ORIGIN_CELL, "west"])
                artifact["checks"].append({"name": "west_step_allowed_before_override", "result": before_step.get("result", {})})
                if not before_step.get("result", {}).get("allowed"):
                    raise AssertionError(before_step)

                block = await _call_overlay(session, "set_cell_override", ["Layer 1", BLOCK_CELL, "force_blocked"])
                artifact["checks"].append({"name": "set_force_blocked", "result": block.get("result", {})})
                if not block.get("result", {}).get("ok"):
                    raise AssertionError(block)
                save = await _call_overlay(session, "save_navigation_overrides")
                artifact["checks"].append({"name": "save_force_blocked", "result": save.get("result", {})})
                if not save.get("result", {}).get("ok"):
                    raise AssertionError(save)

                pressed = await _call(
                    session,
                    "godot_press_keys",
                    {"keys": ["A"], "hold_ms": 80, "frames_after": 12},
                )
                if not pressed.get("ok", False):
                    raise AssertionError(pressed)
                state_after_blocked_move = await _player_state(session)
                artifact["checks"].append({
                    "name": "actual_wasd_blocked_by_override",
                    "state": {"layer": state_after_blocked_move[0], "cell": {"x": state_after_blocked_move[1][0], "y": state_after_blocked_move[1][1]}},
                })
                if state_after_blocked_move != ("Layer 1", (ORIGIN_CELL["x"], ORIGIN_CELL["y"])):
                    raise AssertionError(state_after_blocked_move)

                await _call(session, "godot_stop", {})
                await _load_runtime(session, str(args.window_mode))
                state = await _call_overlay(session, "cell_override_state", ["Layer 1", BLOCK_CELL])
                artifact["checks"].append({"name": "force_blocked_persisted_after_reload", "result": state.get("result")})
                if state.get("result") != "force_blocked":
                    raise AssertionError(state)

                await _assert_override_cleared(session)
                restored = await _call_player(session, "can_grid_step_from_cell", ["Layer 1", ORIGIN_CELL, "west"])
                artifact["checks"].append({"name": "west_step_restored_after_clear", "result": restored.get("result", {})})
                if not restored.get("result", {}).get("allowed"):
                    raise AssertionError(restored)
                artifact["ok"] = True
            except Exception as exc:
                artifact["ok"] = False
                artifact["error"] = str(exc)
                exit_code = 1
                try:
                    await _assert_override_cleared(session)
                except Exception as cleanup_exc:
                    artifact["cleanup_error"] = str(cleanup_exc)
            finally:
                output_path.parent.mkdir(parents=True, exist_ok=True)
                output_path.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
                print(json.dumps(artifact, indent=2))
                await session.call_tool("godot_stop", {})
    return exit_code


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
