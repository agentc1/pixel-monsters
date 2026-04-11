# Manual Test 12: Runtime Player Support

## Goal

Confirm that the imported `PF Player` prefab is now runtime-ready in Godot:
- movement works through the imported player controller
- facing switches between south, north, and side sprites
- west-facing flips the side sprite
- the follow camera stays attached in the helper demos

## Generated scenes to inspect

- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_player_demo.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_stairs_demo.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_altar_runes_demo.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/player/PF Player.tscn`

## Steps

1. Open `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_player_demo.tscn`.
2. Press Play Scene.
3. Confirm the player is visible immediately and the camera follows the player.
4. Press `D` or Right Arrow.
5. Confirm the player moves right and uses the side-facing body sprite.
6. Press `A` or Left Arrow.
7. Confirm the player moves left and the side-facing sprite flips horizontally.
8. Press `W` or Up Arrow.
9. Confirm the player moves up and switches to the north-facing sprite.
10. Stop the scene.

## Prefab inspection

1. Open `res://cainos_imports/basic_real_acceptance/scenes/prefabs/player/PF Player.tscn`.
2. Select the root node.
3. Confirm the root script is `cainos_top_down_player_controller_2d.gd`.
4. Confirm the root is still `Node2D`, not `RigidBody2D`.
5. Confirm these children exist:
   - `PF Player Sprite`
   - `Shadow`
   - `CainosRuntimeActor2D`
   - `CainosRuntimeSensor2D` after running the scene

## Runtime compatibility checks

1. Open `basic_runtime_stairs_demo.tscn`.
2. Play the scene and walk onto the south stairs.
3. Confirm the player still changes draw order correctly through the stairs trigger.
4. Open `basic_runtime_altar_runes_demo.tscn`.
5. Play the scene and walk into the altar trigger.
6. Confirm the altar runes still fade in while using the imported player controller.

## Expected result

- `PF Player` is listed under the supported-static tier in `compatibility_report.md`.
- The player report entry includes:
  - `player_controller_runtime_imported`
  - `player_directional_facing_imported`
  - `runtime_actor_helper_attached`
- `manual_behavior_prefabs` is `0` for the real Basic pack.

## If it fails

Capture:
- a screenshot or short description of the wrong facing or missing movement
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- `res://cainos_imports/basic_real_acceptance/reports/import_manifest.json`
- any Godot errors printed while the helper scenes are running
