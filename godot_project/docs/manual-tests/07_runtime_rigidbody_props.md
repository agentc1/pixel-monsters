# Manual Test 07: Runtime-Ready Rigidbody Props

## Goal

Verify that the simple Basic prop physics family now imports as real Godot `RigidBody2D` scenes with preserved collision and mass/damping settings.

## Before you start

Run the real-pack acceptance path first:

```bash
./godot_project/tests/run_basic_real_pack_acceptance.sh /absolute/path/to/basic.unitypackage
```

Open `godot_project/project.godot` in Godot after the command finishes.

## Props to inspect

Open these scenes from the FileSystem panel:
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Barrel 01.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Crate 01.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Crate 02.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Pot 01.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Pot 02.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Pot 03.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Stone Cube 01.tscn`

## Scene checks

For each scene:
1. Select the root node in the Scene tree.
2. Confirm the root node type is `RigidBody2D`.
3. In the Inspector, confirm:
   - `Mass` is non-zero
   - `Gravity Scale` is `0`
   - `Lock Rotation` is enabled
4. Expand the root and confirm collision is still present:
   - `Barrel 01`, `Pot 01`, `Pot 02`, `Pot 03` should keep `CollisionPolygon2D`
   - `Crate 01`, `Crate 02`, and `Stone Cube 01` should keep box-style `CollisionShape2D`

Expected result:
- each scene opens without errors
- each root is a `RigidBody2D`
- collision is still attached to the runtime-ready prop

## Report checks

Open:
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`

Confirm:
- the seven props above appear under `Supported Static Prefabs`
- each report entry includes `rigidbody_imported`
- none of those seven entries include `rigidbody_deferred`
- `PF Player` also appears under `Supported Static Prefabs`
- `PF Player` includes `player_controller_runtime_imported` instead of `rigidbody_deferred`

## If it fails

Capture:
- the exact prefab scene path
- a screenshot of the Scene tree and Inspector for the root node
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- any Godot errors shown in the Output panel
