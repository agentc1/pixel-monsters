# Manual Test 11: Runtime Altar And Rune Support

## Goal

Verify that the altar and rune prefabs now import with working runtime trigger and glow-animation behavior, and that the Basic prefab set is fully runtime-ready.

## Before you start

Run the real-pack acceptance path first:

```bash
./godot_project/tests/run_basic_real_pack_acceptance.sh /absolute/path/to/basic.unitypackage
```

Open `godot_project/project.godot` in Godot after the command finishes.

## 1. Inspect the altar prefab

Open:

- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Altar 01.tscn`

Check in the Scene dock:
- the root has a script attached
- a trigger area node named `BoxCollider_0` exists
- the rune child nodes referenced by the hint are present

Check in the Inspector:
- the root still has `cainos_behavior_hints`
- one hint has `kind = altar_trigger`
- the root script is `cainos_altar_trigger_2d.gd`

## 2. Inspect the rune pillars

Open:

- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Rune Pillar X2.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Rune Pillar X3.tscn`

Check in the Scene dock:
- a node named `Glow` exists
- `Glow` has a script attached

Check in the Inspector:
- the root still has `cainos_behavior_hints`
- `Glow` still has `cainos_behavior_hints`
- the `Glow` script is `cainos_sprite_color_animation_2d.gd`

## 3. Run the altar/runes demo

Open:

- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_altar_runes_demo.tscn`

Press the Play Scene button.

Controls:
- use arrow keys or WASD to move

Expected result:
- the rune pillars visibly animate even before you move
- the altar runes start dim or hidden
- when the player enters the altar trigger, the altar runes fade in
- when the player exits the trigger, the altar runes fade back toward their imported base alpha
- no script errors appear in the Output panel

## 4. Report checks

Open:

- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`

Confirm:
- `PF Props - Altar 01` appears under `Supported Static Prefabs`
- `PF Props - Altar 01` includes `altar_runtime_imported`
- `PF Props - Rune Pillar X2` and `PF Props - Rune Pillar X3` appear under `Supported Static Prefabs`
- both rune pillar entries include `sprite_color_animation_runtime_imported`
- `PF Player` also appears under `Supported Static Prefabs`
- `Manual Behavior Prefabs` is empty for the real Basic pack

## If it fails

Capture:
- the exact scene path
- a screenshot of the Scene tree and Inspector
- a screenshot or short recording of the running demo while reproducing the problem
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- any Godot errors from the Output panel
