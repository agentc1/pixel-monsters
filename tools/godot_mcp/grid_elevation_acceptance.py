#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


REPO_ROOT = Path(__file__).resolve().parents[2]
PROBE_SCENE = "res://tests/mcp/grid_elevation_probe.tscn"
REAL_RUNTIME_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo Runtime.tscn"
PROBE_ROOT = "/root/GodotMcpRuntime/SceneHost/GridElevationProbe"
PROBE_PLAYER = f"{PROBE_ROOT}/RuntimePlayer"
REAL_ROOT = "/root/GodotMcpRuntime/SceneHost/SC Demo Runtime"
REAL_PLAYER = f"{REAL_ROOT}/RuntimePlayer"
REAL_OVERLAY = f"{REAL_ROOT}/NavigationOverlay"


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


def _node_position(info: dict) -> tuple[float, float]:
    node = info["node"]
    position = node["global_position"]
    return (float(position["x"]), float(position["y"]))


def _probe_meta(info: dict) -> dict:
    return dict(info["node"].get("meta", {}))


def _assert_pos(info: dict, expected: tuple[float, float], label: str) -> None:
    actual = _node_position(info)
    assert abs(actual[0] - expected[0]) <= 0.01 and abs(actual[1] - expected[1]) <= 0.01, (
        label,
        expected,
        actual,
        info,
    )


async def _node_info(session: ClientSession, path: str) -> dict:
    info = _structured(await session.call_tool("godot_node_info", {"node_path": path}))
    assert info.get("ok", False), info
    assert info.get("found", False), info
    return info


async def _tap(session: ClientSession, key: str) -> None:
    pressed = _structured(await session.call_tool("godot_press_keys", {"keys": [key], "hold_ms": 80, "frames_after": 12}))
    assert pressed["ok"], pressed


async def _validate_probe_scene(session: ClientSession) -> None:
    play = _structured(await session.call_tool("godot_play_scene", {"scene_path": PROBE_SCENE}))
    assert play["ok"], play
    assert play["loaded_scene_path"] == PROBE_SCENE, play

    root = await _node_info(session, PROBE_ROOT)
    meta = _probe_meta(root)
    assert meta["player_layer"] == "Layer 1", meta
    assert meta["player_cell"] == {"x": 0, "y": 1}, meta

    await _tap(session, "W")
    root = await _node_info(session, PROBE_ROOT)
    meta = _probe_meta(root)
    assert meta["player_layer"] == "Layer 2", meta
    assert meta["player_cell"] == {"x": 0, "y": 0}, meta
    _assert_pos(await _node_info(session, PROBE_PLAYER), (0.0, 0.0), "probe stair transition")

    await _tap(session, "D")
    root = await _node_info(session, PROBE_ROOT)
    meta = _probe_meta(root)
    assert meta["player_cell"] == {"x": 1, "y": 0}, meta

    await _tap(session, "D")
    _assert_pos(await _node_info(session, PROBE_PLAYER), (32.0, 0.0), "probe blocks explicit ledge cell")

    await _tap(session, "S")
    _assert_pos(await _node_info(session, PROBE_PLAYER), (32.0, 0.0), "probe blocks unsupported lower-adjacent cell")

    await _tap(session, "A")
    await _tap(session, "S")
    root = await _node_info(session, PROBE_ROOT)
    meta = _probe_meta(root)
    assert meta["player_layer"] == "Layer 1", meta
    assert meta["player_cell"] == {"x": 0, "y": 1}, meta


async def _validate_real_scene_probe(session: ClientSession) -> None:
    play = _structured(await session.call_tool("godot_play_scene", {"scene_path": REAL_RUNTIME_SCENE}))
    assert play["ok"], play
    assert play["loaded_scene_path"] == REAL_RUNTIME_SCENE, play

    overlay = await _node_info(session, REAL_OVERLAY)
    assert overlay["node"]["visible"] is True, overlay
    assert str(overlay["node"]["script_path"]).endswith("cainos_grid_navigation_overlay_2d.gd"), overlay
    rebuild = _structured(
        await session.call_tool(
            "godot_call_node_method",
            {
                "node_path": REAL_OVERLAY,
                "method_name": "rebuild_navigation_overlay",
                "frames_after": 2,
            },
        )
    )
    assert rebuild["called"], rebuild
    assert rebuild["result"]["ok"] is True, rebuild
    counts = rebuild["result"]["reachable_cell_counts_by_layer"]
    assert int(counts["Layer 1"]) > 0, rebuild
    assert int(counts["Layer 2"]) > 0, rebuild
    bush_reachable = _structured(
        await session.call_tool(
            "godot_call_node_method",
            {
                "node_path": REAL_OVERLAY,
                "method_name": "is_cell_reachable",
                "args": [{"x": 9, "y": -3}, "Layer 2"],
            },
        )
    )
    assert bush_reachable["called"], bush_reachable
    assert bush_reachable["result"] is False, bush_reachable
    ledge_reachable = _structured(
        await session.call_tool(
            "godot_call_node_method",
            {
                "node_path": REAL_OVERLAY,
                "method_name": "is_cell_reachable",
                "args": [{"x": 10, "y": -5}, "Layer 2"],
            },
        )
    )
    assert ledge_reachable["called"], ledge_reachable
    assert ledge_reachable["result"] is False, ledge_reachable

    layer = _structured(
        await session.call_tool(
            "godot_call_node_method",
            {
                "node_path": REAL_PLAYER,
                "method_name": "_apply_runtime_layer_name",
                "args": ["Layer 2"],
                "frames_after": 2,
            },
        )
    )
    assert layer["called"], layer
    placed = _structured(
        await session.call_tool(
            "godot_set_node_property",
            {
                "node_path": REAL_PLAYER,
                "property_name": "global_position",
                "value": {"x": 288.0, "y": -160.0},
                "frames_after": 2,
            },
        )
    )
    assert placed["set"], placed
    before = await _node_info(session, REAL_PLAYER)
    _assert_pos(before, (288.0, -160.0), "real scene probe placement")

    await _tap(session, "D")
    after = await _node_info(session, REAL_PLAYER)
    _assert_pos(after, (288.0, -160.0), "real scene side stairs do not create broad Layer 2 ledge corridor")


async def main() -> None:
    params = _server_params()
    async with stdio_client(params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            try:
                await _validate_probe_scene(session)
                await _validate_real_scene_probe(session)
            finally:
                await session.call_tool("godot_stop", {})

    print("Godot MCP grid elevation acceptance passed.")


if __name__ == "__main__":
    asyncio.run(main())
