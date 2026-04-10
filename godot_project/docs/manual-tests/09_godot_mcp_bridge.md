# Manual Test 09: Godot MCP Bridge

This test validates the runtime-first Godot MCP bridge.

## Prerequisites

- Python dependencies installed for `tools/godot_mcp`
- Godot available as `godot` or via `GODOT_BIN`

## Synthetic probe workflow

1. Start the MCP server:
   `tools/godot_mcp/.venv/bin/godot-mcp`
2. In your MCP client, call:
   `godot_play_scene("res://tests/mcp/runtime_probe.tscn")`
3. Capture a screenshot:
   `godot_capture_viewport("probe-before")`
4. Inspect the actor:
   `godot_node_info("/root/GodotMcpRuntime/SceneHost/RuntimeProbe/ProbeActor")`
5. Tap movement:
   `godot_press_keys(["D"], hold_ms=250, frames_after=2)`
6. Capture again:
   `godot_capture_viewport("probe-after")`

Expected result:
- two screenshots exist on disk
- the actor node is present
- the actor position changes after movement
- the current camera is the actor camera

## Runtime stairs demo workflow

1. Call:
   `godot_play_scene("res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_stairs_demo.tscn")`
2. Capture a screenshot before movement.
3. Inspect:
   `godot_node_info("/root/GodotMcpRuntime/SceneHost/basic_runtime_stairs_demo/PF Player")`
4. Move with:
   `godot_press_keys(["D"], hold_ms=250, frames_after=2)`
5. Capture another screenshot.

Expected result:
- the player node is present in the live scene tree
- the player position changes after movement
- the follow camera is current
- screenshots show the runtime scene before and after movement
