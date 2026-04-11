# Manual Test 08: Runtime Stairs Support

## Goal

Verify that the Basic stair prefabs now import with working runtime stairs triggers, actor-helper support, and a runnable demo scene.

## Before you start

Run the real-pack acceptance path first:

```bash
./godot_project/tests/run_basic_real_pack_acceptance.sh /absolute/path/to/basic.unitypackage
```

Open `godot_project/project.godot` in Godot after the command finishes.

## 1. Inspect the stair prefab

Open:

- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/struct/PF Struct - Stairs S 01 L.tscn`

Check in the Scene dock:
- a node named `Stairs Layer Trigger` exists
- the trigger node has a script attached
- the stair visual nodes carry `cainos_visual_stratum` metadata

Check in the Inspector:
- the root still has `cainos_behavior_hints`
- `Stairs Layer Trigger` still has both `cainos_behavior_hints` and `unity_mono_behaviours`

## 2. Inspect the player helper

Open:

- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/player/PF Player.tscn`

Check in the Scene dock:
- a child named `CainosRuntimeActor2D` exists

Check in the Inspector:
- the root still has `cainos_behavior_hints`
- the root script is `cainos_top_down_player_controller_2d.gd`
- the player scene carries both the imported controller and `CainosRuntimeActor2D`

## 3. Run the demo scene

Open:

- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_stairs_demo.tscn`

Press the Play Scene button.

Controls:
- use arrow keys or WASD to move

Expected result:
- the player is visible immediately when the scene starts
- the player can move through the demo scene
- when crossing the stairs trigger, the player visibly switches render order relative to the stair art
- no script errors appear in the Output panel

## 4. Report checks

Open:

- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`

Confirm:
- all south/east/west stair prefabs appear under `Supported Static Prefabs`
- stair entries include `stairs_runtime_imported`
- `PF Player` appears under `Supported Static Prefabs`
- `PF Player` includes both `player_controller_runtime_imported` and `runtime_actor_helper_attached`

## If it fails

Capture:
- the exact scene path
- a screenshot of the Scene tree and Inspector
- a screenshot or short recording of the demo scene while reproducing the problem
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- any Godot errors from the Output panel
