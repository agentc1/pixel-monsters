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

## Runtime player demo workflow

1. Call:
   `godot_play_scene("res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_player_demo.tscn")`
2. Inspect:
   `godot_node_info("/root/GodotMcpRuntime/SceneHost/basic_runtime_player_demo/PF Player")`
3. Capture a screenshot before movement.
4. Move with:
   `godot_press_keys(["D"], hold_ms=250, frames_after=2)`
5. Inspect the body sprite:
   `godot_node_info("/root/GodotMcpRuntime/SceneHost/basic_runtime_player_demo/PF Player/PF Player Sprite")`
6. Move with:
   `godot_press_keys(["A"], hold_ms=250, frames_after=2)`
7. Capture another screenshot.

Expected result:
- the player root uses the imported player-controller script
- the player position changes after movement
- the body sprite switches to the side-facing region
- west-facing flips the side sprite
- the follow camera is current

## Runtime altar/runes demo workflow

1. Call:
   `godot_play_scene("res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_altar_runes_demo.tscn")`
2. Inspect the altar rune sprite:
   `godot_node_info("/root/GodotMcpRuntime/SceneHost/basic_runtime_altar_runes_demo/PF Props - Altar 01/Rune A/Rune A Sprite")`
3. Inspect the glow sprite:
   `godot_node_info("/root/GodotMcpRuntime/SceneHost/basic_runtime_altar_runes_demo/PF Props - Rune Pillar X2/Glow/Glow Sprite")`
4. Capture a screenshot before movement.
5. Move with:
   `godot_press_keys(["W"], hold_ms=450, frames_after=8)`
6. Capture another screenshot.

Expected result:
- the altar rune sprite starts with a low alpha value
- the glow sprite `modulate` changes over time
- moving into the altar trigger increases the altar rune alpha
- screenshots show the altar/rune runtime behavior live
