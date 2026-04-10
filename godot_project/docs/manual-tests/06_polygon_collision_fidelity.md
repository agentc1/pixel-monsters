# Manual Test 06: Polygon Collision Fidelity

## Goal

Verify that supported `PolygonCollider2D` data now imports into real Godot `CollisionPolygon2D` nodes for both static and runtime-ready rigidbody props.

## Before you start

Run the real-pack acceptance path first:

```bash
./godot_project/tests/run_basic_real_pack_acceptance.sh /absolute/path/to/basic.unitypackage
```

Open `godot_project/project.godot` in Godot after the command finishes.

## Supported polygon samples

Open these scenes from the FileSystem panel:
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Well 01.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Statue 01.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/struct/PF Struct - Gate 02.tscn`

For each scene:
1. Open the Scene tree.
2. Expand the root until you find one or more `PolygonCollider_*` nodes.
3. Expand a `PolygonCollider_*` node and confirm it contains at least one `CollisionPolygon2D` child.

Expected result:
- the scene opens without errors
- at least one `CollisionPolygon2D` exists

## Runtime-ready polygon + rigidbody samples

Open these scenes:
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Barrel 01.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/prefabs/props/PF Props - Pot 01.tscn`

Expected result:
- the scene root is `RigidBody2D`
- the scene still contains `CollisionPolygon2D`
- the compatibility report lists the prefab under `Supported Static Prefabs`
- the report entry includes both `polygon_collider_imported` and `rigidbody_imported`

## Report checks

Open:
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`

Confirm:
- `PF Props - Well 01`, `PF Props - Statue 01`, and `PF Struct - Gate 02` appear under `Supported Static Prefabs`
- `PF Props - Barrel 01` and `PF Props - Pot 01` also appear under `Supported Static Prefabs`
- supported polygon entries mention `polygon_collider_imported`
- runtime-ready rigidbody entries include `rigidbody_imported`

For box-collider rigidbody props such as `PF Props - Crate 01`, use Manual Test 07.

## If it fails

Capture:
- the exact prefab scene path
- the relevant Scene tree screenshot
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- any Godot errors shown in the Output panel
