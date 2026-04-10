#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


REPO_ROOT = Path(__file__).resolve().parents[2]


def _server_params() -> StdioServerParameters:
    env = dict(**{key: value for key, value in __import__("os").environ.items()})
    return StdioServerParameters(
        command=sys.executable,
        args=["-m", "godot_mcp.server"],
        cwd=REPO_ROOT,
        env=env,
    )


def _structured(result) -> dict:
    if getattr(result, "isError", False):
        raise RuntimeError(f"Tool returned error: {result}")
    payload = getattr(result, "structuredContent", None)
    if payload is None:
        raise RuntimeError(f"Tool returned no structured content: {result}")
    return payload


async def main() -> None:
    params = _server_params()
    async with stdio_client(params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            play = _structured(await session.call_tool("godot_play_scene", {"scene_path": "res://tests/mcp/runtime_probe.tscn"}))
            assert play["ok"], play
            assert play["loaded_scene_path"] == "res://tests/mcp/runtime_probe.tscn", play
            assert play["current_camera_path"].endswith("/ProbeActor/Camera2D"), play

            tree = _structured(await session.call_tool("godot_scene_tree", {"max_depth": 3}))
            assert tree["found"], tree

            before = _structured(
                await session.call_tool(
                    "godot_node_info",
                    {"node_path": "/root/GodotMcpRuntime/SceneHost/RuntimeProbe/ProbeActor"},
                )
            )
            assert before["found"], before
            before_x = float(before["node"]["global_position"]["x"])

            capture_before = _structured(await session.call_tool("godot_capture_viewport", {"label": "probe_before"}))
            assert capture_before["captured"], capture_before
            assert Path(capture_before["png_path"]).exists(), capture_before

            move = _structured(await session.call_tool("godot_press_keys", {"keys": ["D"], "hold_ms": 250, "frames_after": 3}))
            assert move["ok"], move

            after = _structured(
                await session.call_tool(
                    "godot_node_info",
                    {"node_path": "/root/GodotMcpRuntime/SceneHost/RuntimeProbe/ProbeActor"},
                )
            )
            assert after["found"], after
            after_x = float(after["node"]["global_position"]["x"])
            assert after_x > before_x, (before, after)

            capture_after = _structured(await session.call_tool("godot_capture_viewport", {"label": "probe_after"}))
            assert capture_after["captured"], capture_after
            assert Path(capture_after["png_path"]).exists(), capture_after

            logs = _structured(await session.call_tool("godot_logs", {"limit": 20}))
            assert logs["ok"], logs

            stop = _structured(await session.call_tool("godot_stop", {}))
            assert stop["ok"], stop

    print("Godot MCP synthetic smoke test passed.")


if __name__ == "__main__":
    asyncio.run(main())
