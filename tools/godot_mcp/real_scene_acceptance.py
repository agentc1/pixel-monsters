#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


REPO_ROOT = Path(__file__).resolve().parents[2]
DEMO_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_stairs_demo.tscn"
ALTAR_DEMO_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_altar_runes_demo.tscn"
PLAYER_DEMO_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_player_demo.tscn"
IMPORTED_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo.tscn"
RUNTIME_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo Runtime.tscn"
PREVIEW_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/helpers/sc_demo_preview.tscn"
ALL_PROPS_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/unity/SC All Props.tscn"
ALL_PROPS_PREVIEW_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/helpers/sc_all_props_preview.tscn"
PLAYER_DEMO_ROOT = "/root/GodotMcpRuntime/SceneHost/basic_runtime_player_demo"
PLAYER_PATH = f"{PLAYER_DEMO_ROOT}/PF Player"
PLAYER_SPRITE_PATH = f"{PLAYER_PATH}/PF Player Sprite"
PLAYER_SHADOW_PATH = f"{PLAYER_PATH}/Shadow/Shadow Sprite"
STAIRS_DEMO_ROOT = "/root/GodotMcpRuntime/SceneHost/basic_runtime_stairs_demo"
STAIRS_PLAYER_PATH = f"{STAIRS_DEMO_ROOT}/PF Player"
ALTAR_DEMO_ROOT = "/root/GodotMcpRuntime/SceneHost/basic_runtime_altar_runes_demo"
ALTAR_PLAYER_PATH = f"{ALTAR_DEMO_ROOT}/PF Player"
ALTAR_RUNE_PATH = f"{ALTAR_DEMO_ROOT}/PF Props - Altar 01/Rune/1/1 Sprite"
RUNE_GLOW_PATH = f"{ALTAR_DEMO_ROOT}/PF Props - Rune Pillar X2/Glow/Glow Sprite"
IMPORTED_SCENE_ROOT = "/root/GodotMcpRuntime/SceneHost/SC Demo"
IMPORTED_PREFABS_PATH = f"{IMPORTED_SCENE_ROOT}/Prefabs"
IMPORTED_PLAYER_PATH = f"{IMPORTED_PREFABS_PATH}/PF Player"
IMPORTED_GRASS_LAYER_PATH = f"{IMPORTED_SCENE_ROOT}/Tilemaps/Layer 1 - Grass"
IMPORTED_CAMERA_MARKER_PATH = f"{IMPORTED_SCENE_ROOT}/Markers/Main Camera Marker"
RUNTIME_SCENE_ROOT = "/root/GodotMcpRuntime/SceneHost/SC Demo Runtime"
RUNTIME_INSTANCE_ROOT = f"{RUNTIME_SCENE_ROOT}/SceneInstance/SC Demo"
RUNTIME_COLLISION_ROOT = f"{RUNTIME_SCENE_ROOT}/SceneCollision"
RUNTIME_PLAYER_PATH = f"{RUNTIME_SCENE_ROOT}/RuntimePlayer"
RUNTIME_PLAYER_CHILD_PATH = f"{RUNTIME_PLAYER_PATH}/PF Player"
RUNTIME_CAMERA_PATH = f"{RUNTIME_PLAYER_PATH}/FollowCamera2D"
RUNTIME_NAVIGATION_OVERLAY_PATH = f"{RUNTIME_SCENE_ROOT}/NavigationOverlay"
PREVIEW_SCENE_ROOT = "/root/GodotMcpRuntime/SceneHost/sc_demo_preview"
PREVIEW_INSTANCE_ROOT = f"{PREVIEW_SCENE_ROOT}/SceneInstance/SC Demo"
ALL_PROPS_SCENE_ROOT = "/root/GodotMcpRuntime/SceneHost/SC All Props"
ALL_PROPS_PREFABS_PATH = f"{ALL_PROPS_SCENE_ROOT}/Prefabs"
ALL_PROPS_PREVIEW_ROOT = "/root/GodotMcpRuntime/SceneHost/sc_all_props_preview"
ALL_PROPS_PREVIEW_INSTANCE_ROOT = f"{ALL_PROPS_PREVIEW_ROOT}/SceneInstance/SC All Props"


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

            play = _structured(await session.call_tool("godot_play_scene", {"scene_path": PLAYER_DEMO_SCENE}))
            assert play["ok"], play
            assert play["loaded_scene_path"] == PLAYER_DEMO_SCENE, play

            before = _structured(await session.call_tool("godot_node_info", {"node_path": PLAYER_PATH}))
            assert before["found"], before
            before_x = float(before["node"]["global_position"]["x"])
            current_camera_path = str(play.get("current_camera_path", ""))
            assert current_camera_path.endswith("/PF Player/FollowCamera2D"), play
            assert str(before["node"]["script_path"]).endswith("cainos_top_down_player_controller_2d.gd"), before

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

            east_sprite = _structured(await session.call_tool("godot_node_info", {"node_path": PLAYER_SPRITE_PATH}))
            assert east_sprite["found"], east_sprite
            east_region = east_sprite["node"]["region_rect"]
            assert east_region["position"] == {"x": 69.0, "y": 10.0}, east_sprite
            assert east_sprite["node"]["flip_h"] is False, east_sprite

            _structured(await session.call_tool("godot_press_keys", {"keys": ["A"], "hold_ms": 250, "frames_after": 4}))
            west_sprite = _structured(await session.call_tool("godot_node_info", {"node_path": PLAYER_SPRITE_PATH}))
            assert west_sprite["found"], west_sprite
            west_region = west_sprite["node"]["region_rect"]
            assert west_region["position"] == {"x": 69.0, "y": 10.0}, west_sprite
            assert west_sprite["node"]["flip_h"] is True, west_sprite

            _structured(await session.call_tool("godot_press_keys", {"keys": ["W"], "hold_ms": 250, "frames_after": 4}))
            north_sprite = _structured(await session.call_tool("godot_node_info", {"node_path": PLAYER_SPRITE_PATH}))
            assert north_sprite["found"], north_sprite
            north_region = north_sprite["node"]["region_rect"]
            assert north_region["position"] == {"x": 38.0, "y": 10.0}, north_sprite

            capture_after = _structured(await session.call_tool("godot_capture_viewport", {"label": "stairs_after"}))
            assert capture_after["captured"], capture_after
            assert Path(capture_after["png_path"]).exists(), capture_after

            stairs_demo = _structured(await session.call_tool("godot_play_scene", {"scene_path": DEMO_SCENE}))
            assert stairs_demo["ok"], stairs_demo
            assert stairs_demo["loaded_scene_path"] == DEMO_SCENE, stairs_demo
            assert str(stairs_demo.get("current_camera_path", "")).endswith("/PF Player/FollowCamera2D"), stairs_demo

            stairs_before = _structured(await session.call_tool("godot_node_info", {"node_path": STAIRS_PLAYER_PATH}))
            assert stairs_before["found"], stairs_before
            stairs_before_x = float(stairs_before["node"]["global_position"]["x"])

            _structured(await session.call_tool("godot_press_keys", {"keys": ["D"], "hold_ms": 300, "frames_after": 4}))

            stairs_after = _structured(await session.call_tool("godot_node_info", {"node_path": STAIRS_PLAYER_PATH}))
            assert stairs_after["found"], stairs_after
            assert float(stairs_after["node"]["global_position"]["x"]) > stairs_before_x, (stairs_before, stairs_after)

            altar_demo = _structured(await session.call_tool("godot_play_scene", {"scene_path": ALTAR_DEMO_SCENE}))
            assert altar_demo["ok"], altar_demo
            assert altar_demo["loaded_scene_path"] == ALTAR_DEMO_SCENE, altar_demo
            assert str(altar_demo.get("current_camera_path", "")).endswith("/PF Player/FollowCamera2D"), altar_demo

            altar_rune_before = _structured(await session.call_tool("godot_node_info", {"node_path": ALTAR_RUNE_PATH}))
            assert altar_rune_before["found"], altar_rune_before
            rune_alpha_before = float(altar_rune_before["node"]["modulate"]["a"])
            assert rune_alpha_before < 0.1, altar_rune_before

            glow_before = _structured(await session.call_tool("godot_node_info", {"node_path": RUNE_GLOW_PATH}))
            assert glow_before["found"], glow_before
            glow_before_modulate = glow_before["node"]["modulate"]

            await session.call_tool("godot_advance_frames", {"frames": 6})

            glow_after = _structured(await session.call_tool("godot_node_info", {"node_path": RUNE_GLOW_PATH}))
            assert glow_after["found"], glow_after
            assert glow_after["node"]["modulate"] != glow_before_modulate, (glow_before, glow_after)

            altar_capture_before = _structured(await session.call_tool("godot_capture_viewport", {"label": "altar_before"}))
            assert altar_capture_before["captured"], altar_capture_before
            assert Path(altar_capture_before["png_path"]).exists(), altar_capture_before

            _structured(await session.call_tool("godot_press_keys", {"keys": ["W"], "hold_ms": 900, "frames_after": 8}))

            altar_player_after = _structured(await session.call_tool("godot_node_info", {"node_path": ALTAR_PLAYER_PATH}))
            assert altar_player_after["found"], altar_player_after

            altar_rune_after = _structured(await session.call_tool("godot_node_info", {"node_path": ALTAR_RUNE_PATH}))
            assert altar_rune_after["found"], altar_rune_after

            altar_capture_after = _structured(await session.call_tool("godot_capture_viewport", {"label": "altar_after"}))
            assert altar_capture_after["captured"], altar_capture_after
            assert Path(altar_capture_after["png_path"]).exists(), altar_capture_after

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

            runtime = _structured(await session.call_tool("godot_play_scene", {"scene_path": RUNTIME_SCENE}))
            assert runtime["ok"], runtime
            assert runtime["loaded_scene_path"] == RUNTIME_SCENE, runtime
            assert str(runtime.get("current_camera_path", "")).endswith("/RuntimePlayer/FollowCamera2D"), runtime

            runtime_root = _structured(await session.call_tool("godot_node_info", {"node_path": RUNTIME_SCENE_ROOT}))
            assert runtime_root["found"], runtime_root
            assert runtime_root["node"]["type"] == "Node2D", runtime_root

            runtime_overlay = _structured(await session.call_tool("godot_node_info", {"node_path": RUNTIME_NAVIGATION_OVERLAY_PATH}))
            assert runtime_overlay["found"], runtime_overlay
            assert runtime_overlay["node"]["type"] == "Node2D", runtime_overlay
            assert runtime_overlay["node"]["visible"] is True, runtime_overlay
            assert str(runtime_overlay["node"]["script_path"]).endswith("cainos_grid_navigation_overlay_2d.gd"), runtime_overlay
            overlay_rebuild = _structured(
                await session.call_tool(
                    "godot_call_node_method",
                    {
                        "node_path": RUNTIME_NAVIGATION_OVERLAY_PATH,
                        "method_name": "rebuild_navigation_overlay",
                        "frames_after": 2,
                    },
                )
            )
            assert overlay_rebuild["called"], overlay_rebuild
            assert overlay_rebuild["result"]["ok"] is True, overlay_rebuild
            overlay_counts = overlay_rebuild["result"]["reachable_cell_counts_by_layer"]
            assert int(overlay_counts["Layer 1"]) > 0, overlay_rebuild
            assert int(overlay_counts["Layer 2"]) > 0, overlay_rebuild

            runtime_scene_instance = _structured(
                await session.call_tool("godot_node_info", {"node_path": f"{RUNTIME_SCENE_ROOT}/SceneInstance"})
            )
            assert runtime_scene_instance["found"], runtime_scene_instance

            runtime_scene_collision = _structured(
                await session.call_tool("godot_node_info", {"node_path": RUNTIME_COLLISION_ROOT})
            )
            assert runtime_scene_collision["found"], runtime_scene_collision

            runtime_player_before = _structured(await session.call_tool("godot_node_info", {"node_path": RUNTIME_PLAYER_PATH}))
            assert runtime_player_before["found"], runtime_player_before
            assert runtime_player_before["node"]["type"] == "CharacterBody2D", runtime_player_before
            runtime_camera_before = _structured(await session.call_tool("godot_node_info", {"node_path": RUNTIME_CAMERA_PATH}))
            assert runtime_camera_before["found"], runtime_camera_before
            runtime_player_child = _structured(await session.call_tool("godot_node_info", {"node_path": RUNTIME_PLAYER_CHILD_PATH}))
            assert runtime_player_child["found"], runtime_player_child
            assert str(runtime_player_child["node"]["script_path"]).endswith("cainos_top_down_player_controller_2d.gd"), runtime_player_child

            placeholder_player = _structured(
                await session.call_tool("godot_node_info", {"node_path": f"{RUNTIME_INSTANCE_ROOT}/Prefabs/PF Player"})
            )
            assert placeholder_player["found"] is False, placeholder_player

            for collision_name in ["Layer 1 - Wall Collision", "Layer 2 - Wall Collision", "Layer 3 - Wall Collision"]:
                collision_info = _structured(
                    await session.call_tool("godot_node_info", {"node_path": f"{RUNTIME_COLLISION_ROOT}/{collision_name}"})
                )
                assert collision_info["found"], collision_info
                assert collision_info["node"]["type"] == "StaticBody2D", collision_info

            runtime_capture_before = _structured(await session.call_tool("godot_capture_viewport", {"label": "scene_demo_runtime_before"}))
            assert runtime_capture_before["captured"], runtime_capture_before
            assert Path(runtime_capture_before["png_path"]).exists(), runtime_capture_before

            before_player_y = float(runtime_player_before["node"]["global_position"]["y"])
            before_camera_y = float(runtime_camera_before["node"]["global_position"]["y"])
            _structured(await session.call_tool("godot_press_keys", {"keys": ["W"], "hold_ms": 250, "frames_after": 4}))

            runtime_player_after = _structured(await session.call_tool("godot_node_info", {"node_path": RUNTIME_PLAYER_PATH}))
            assert runtime_player_after["found"], runtime_player_after
            after_player_y = float(runtime_player_after["node"]["global_position"]["y"])
            assert after_player_y < before_player_y, (runtime_player_before, runtime_player_after)

            runtime_camera_after = _structured(await session.call_tool("godot_node_info", {"node_path": RUNTIME_CAMERA_PATH}))
            assert runtime_camera_after["found"], runtime_camera_after
            after_camera_y = float(runtime_camera_after["node"]["global_position"]["y"])
            assert after_camera_y < before_camera_y, (runtime_camera_before, runtime_camera_after)

            runtime_capture_after = _structured(await session.call_tool("godot_capture_viewport", {"label": "scene_demo_runtime_after"}))
            assert runtime_capture_after["captured"], runtime_capture_after
            assert Path(runtime_capture_after["png_path"]).exists(), runtime_capture_after

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

            imported_all_props = _structured(await session.call_tool("godot_play_scene", {"scene_path": ALL_PROPS_SCENE}))
            assert imported_all_props["ok"], imported_all_props
            assert imported_all_props["loaded_scene_path"] == ALL_PROPS_SCENE, imported_all_props

            all_props_tree = _structured(
                await session.call_tool("godot_scene_tree", {"root_path": ALL_PROPS_SCENE_ROOT, "max_depth": 3})
            )
            assert all_props_tree["found"], all_props_tree
            assert _tree_contains_name(all_props_tree["tree"], "Tilemaps"), all_props_tree
            assert _tree_contains_name(all_props_tree["tree"], "Prefabs"), all_props_tree
            assert _tree_contains_name(all_props_tree["tree"], "Markers"), all_props_tree
            assert _tree_contains_name(all_props_tree["tree"], "Layer 1"), all_props_tree

            for layer_name in ["Layer 1 - Grass", "Layer 1 - Wall"]:
                layer_info = _structured(
                    await session.call_tool("godot_node_info", {"node_path": f"{ALL_PROPS_SCENE_ROOT}/Tilemaps/{layer_name}"})
                )
                assert layer_info["found"], layer_info
                assert layer_info["node"]["type"] == "TileMapLayer", layer_info

            all_props_camera = _structured(
                await session.call_tool("godot_node_info", {"node_path": f"{ALL_PROPS_SCENE_ROOT}/Markers/Main Camera Marker"})
            )
            assert all_props_camera["found"], all_props_camera
            assert all_props_camera["node"]["type"] == "Node2D", all_props_camera

            all_props_prefabs = _structured(
                await session.call_tool("godot_node_info", {"node_path": ALL_PROPS_PREFABS_PATH})
            )
            assert all_props_prefabs["found"], all_props_prefabs
            assert all_props_prefabs["node"]["type"] == "Node2D", all_props_prefabs

            all_props_capture = _structured(await session.call_tool("godot_capture_viewport", {"label": "scene_all_props"}))
            assert all_props_capture["captured"], all_props_capture
            assert Path(all_props_capture["png_path"]).exists(), all_props_capture

            _structured(await session.call_tool("godot_play_scene", {"scene_path": ALL_PROPS_PREVIEW_SCENE}))
            all_props_preview = _structured(await session.call_tool("godot_advance_frames", {"frames": 3}))
            assert all_props_preview["ok"], all_props_preview
            assert all_props_preview["loaded_scene_path"] == ALL_PROPS_PREVIEW_SCENE, all_props_preview
            assert all_props_preview["viewport_size"] == {"x": 1200.0, "y": 1200.0}, all_props_preview
            assert str(all_props_preview.get("current_camera_path", "")).endswith("/sc_all_props_preview/PreviewCamera2D"), all_props_preview

            all_props_preview_tree = _structured(
                await session.call_tool("godot_scene_tree", {"root_path": ALL_PROPS_PREVIEW_ROOT, "max_depth": 3})
            )
            assert all_props_preview_tree["found"], all_props_preview_tree
            assert _tree_contains_name(all_props_preview_tree["tree"], "SceneInstance"), all_props_preview_tree
            assert _tree_contains_name(all_props_preview_tree["tree"], "SC All Props"), all_props_preview_tree

            all_props_preview_instance = _structured(
                await session.call_tool("godot_node_info", {"node_path": ALL_PROPS_PREVIEW_INSTANCE_ROOT})
            )
            assert all_props_preview_instance["found"], all_props_preview_instance
            assert all_props_preview_instance["node"]["type"] == "Node2D", all_props_preview_instance

            all_props_preview_capture = _structured(await session.call_tool("godot_capture_viewport", {"label": "scene_all_props_preview"}))
            assert all_props_preview_capture["captured"], all_props_preview_capture
            assert Path(all_props_preview_capture["png_path"]).exists(), all_props_preview_capture
            assert all_props_preview_capture["viewport_size"] == {"x": 1200, "y": 1200}, all_props_preview_capture

            stop = _structured(await session.call_tool("godot_stop", {}))
            assert stop["ok"], stop

    print("Godot MCP real-scene acceptance passed.")


if __name__ == "__main__":
    asyncio.run(main())
