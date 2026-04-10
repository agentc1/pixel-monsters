#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


REPO_ROOT = Path(__file__).resolve().parents[2]
DEMO_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_stairs_demo.tscn"
IMPORTED_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo.tscn"
PREVIEW_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/helpers/sc_demo_preview.tscn"
PLAYER_PATH = "/root/GodotMcpRuntime/SceneHost/basic_runtime_stairs_demo/PF Player"
PLAYER_SPRITE_PATH = f"{PLAYER_PATH}/PF Player Sprite"
PLAYER_SHADOW_PATH = f"{PLAYER_PATH}/Shadow/Shadow Sprite"
IMPORTED_SCENE_ROOT = "/root/GodotMcpRuntime/SceneHost/SC Demo"
IMPORTED_PREFABS_PATH = f"{IMPORTED_SCENE_ROOT}/Prefabs"
IMPORTED_PLAYER_PATH = f"{IMPORTED_PREFABS_PATH}/PF Player"
IMPORTED_GRASS_LAYER_PATH = f"{IMPORTED_SCENE_ROOT}/Tilemaps/Layer 1 - Grass"
IMPORTED_CAMERA_MARKER_PATH = f"{IMPORTED_SCENE_ROOT}/Markers/Main Camera Marker"
PREVIEW_SCENE_ROOT = "/root/GodotMcpRuntime/SceneHost/sc_demo_preview"
PREVIEW_INSTANCE_ROOT = f"{PREVIEW_SCENE_ROOT}/SceneInstance/SC Demo"


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


def _tree_contains_name(tree: dict, target_name: str) -> bool:
    if str(tree.get("name", "")) == target_name:
        return True
    for child in tree.get("children", []):
        if _tree_contains_name(child, target_name):
            return True
    return False


async def main() -> None:
    params = _server_params()
    async with stdio_client(params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            play = _structured(await session.call_tool("godot_play_scene", {"scene_path": DEMO_SCENE}))
            assert play["ok"], play
            assert play["loaded_scene_path"] == DEMO_SCENE, play

            before = _structured(await session.call_tool("godot_node_info", {"node_path": PLAYER_PATH}))
            assert before["found"], before
            before_x = float(before["node"]["global_position"]["x"])
            current_camera_path = str(play.get("current_camera_path", ""))
            assert current_camera_path.endswith("/PF Player/FollowCamera2D"), play

            sprite_info = _structured(await session.call_tool("godot_node_info", {"node_path": PLAYER_SPRITE_PATH}))
            assert sprite_info["found"], sprite_info
            sprite_node = sprite_info["node"]
            assert sprite_node["region_enabled"] is True, sprite_info
            assert str(sprite_node["texture_path"]).endswith("/TX Player.png"), sprite_info
            sprite_region = sprite_node["region_rect"]
            assert sprite_region["position"] == {"x": 6.0, "y": 10.0}, sprite_info
            assert sprite_region["size"] == {"x": 21.0, "y": 48.0}, sprite_info

            shadow_info = _structured(await session.call_tool("godot_node_info", {"node_path": PLAYER_SHADOW_PATH}))
            assert shadow_info["found"], shadow_info
            assert int(shadow_info["node"]["z_index"]) < int(sprite_node["z_index"]), (sprite_info, shadow_info)
            shadow_region = shadow_info["node"]["region_rect"]
            assert shadow_region["position"] == {"x": 99.0, "y": 32.0}, shadow_info
            assert shadow_region["size"] == {"x": 27.0, "y": 28.0}, shadow_info

            capture_before = _structured(await session.call_tool("godot_capture_viewport", {"label": "stairs_before"}))
            assert capture_before["captured"], capture_before
            assert Path(capture_before["png_path"]).exists(), capture_before

            _structured(await session.call_tool("godot_press_keys", {"keys": ["D"], "hold_ms": 250, "frames_after": 4}))

            after = _structured(await session.call_tool("godot_node_info", {"node_path": PLAYER_PATH}))
            assert after["found"], after
            after_x = float(after["node"]["global_position"]["x"])
            assert after_x > before_x, (before, after)

            capture_after = _structured(await session.call_tool("godot_capture_viewport", {"label": "stairs_after"}))
            assert capture_after["captured"], capture_after
            assert Path(capture_after["png_path"]).exists(), capture_after

            imported = _structured(await session.call_tool("godot_play_scene", {"scene_path": IMPORTED_SCENE}))
            assert imported["ok"], imported
            assert imported["loaded_scene_path"] == IMPORTED_SCENE, imported

            imported_tree = _structured(
                await session.call_tool("godot_scene_tree", {"root_path": IMPORTED_SCENE_ROOT, "max_depth": 2})
            )
            assert imported_tree["found"], imported_tree
            assert _tree_contains_name(imported_tree["tree"], "Tilemaps"), imported_tree
            assert _tree_contains_name(imported_tree["tree"], "Prefabs"), imported_tree
            assert _tree_contains_name(imported_tree["tree"], "Markers"), imported_tree
            assert _tree_contains_name(imported_tree["tree"], "PF Player"), imported_tree

            imported_player = _structured(await session.call_tool("godot_node_info", {"node_path": IMPORTED_PLAYER_PATH}))
            assert imported_player["found"], imported_player
            player_node = imported_player["node"]
            assert player_node["type"] == "Node2D", imported_player
            assert player_node["parent_path"].endswith("/Prefabs"), imported_player

            imported_layer = _structured(await session.call_tool("godot_node_info", {"node_path": IMPORTED_GRASS_LAYER_PATH}))
            assert imported_layer["found"], imported_layer
            assert imported_layer["node"]["type"] == "TileMapLayer", imported_layer

            imported_camera = _structured(await session.call_tool("godot_node_info", {"node_path": IMPORTED_CAMERA_MARKER_PATH}))
            assert imported_camera["found"], imported_camera
            assert imported_camera["node"]["type"] == "Node2D", imported_camera

            imported_capture = _structured(await session.call_tool("godot_capture_viewport", {"label": "scene_demo"}))
            assert imported_capture["captured"], imported_capture
            assert Path(imported_capture["png_path"]).exists(), imported_capture

            _structured(await session.call_tool("godot_play_scene", {"scene_path": PREVIEW_SCENE}))
            preview = _structured(await session.call_tool("godot_advance_frames", {"frames": 3}))
            assert preview["ok"], preview
            assert preview["loaded_scene_path"] == PREVIEW_SCENE, preview
            assert preview["viewport_size"] == {"x": 1200.0, "y": 1200.0}, preview
            assert str(preview.get("current_camera_path", "")).endswith("/sc_demo_preview/PreviewCamera2D"), preview

            preview_tree = _structured(
                await session.call_tool("godot_scene_tree", {"root_path": PREVIEW_SCENE_ROOT, "max_depth": 3})
            )
            assert preview_tree["found"], preview_tree
            assert _tree_contains_name(preview_tree["tree"], "SceneInstance"), preview_tree
            assert _tree_contains_name(preview_tree["tree"], "SC Demo"), preview_tree

            preview_instance = _structured(await session.call_tool("godot_node_info", {"node_path": PREVIEW_INSTANCE_ROOT}))
            assert preview_instance["found"], preview_instance
            assert preview_instance["node"]["type"] == "Node2D", preview_instance

            preview_capture = _structured(await session.call_tool("godot_capture_viewport", {"label": "scene_demo_preview"}))
            assert preview_capture["captured"], preview_capture
            assert Path(preview_capture["png_path"]).exists(), preview_capture
            assert preview_capture["viewport_size"] == {"x": 1200, "y": 1200}, preview_capture

            stop = _structured(await session.call_tool("godot_stop", {}))
            assert stop["ok"], stop

    print("Godot MCP real-scene acceptance passed.")


if __name__ == "__main__":
    asyncio.run(main())
