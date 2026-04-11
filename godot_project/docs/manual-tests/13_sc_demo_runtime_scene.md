# Manual Test 13: SC Demo Runtime Scene

## Goal

Verify that the generated `SC Demo Runtime.tscn` is the playable validation surface for the imported Unity demo scene.

This scene should:
- instance the raw imported `SC Demo.tscn`
- replace the placeholder imported player with the runtime player wrapper
- add real scene wall collision
- use a live follow camera

These checks assume you have already run:

```bash
./godot_project/tests/run_basic_real_pack_acceptance.sh /absolute/path/to/basic.unitypackage
```

## 1. Open the runtime scene

Open:

`res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo Runtime.tscn`

Check in the Scene dock:
- the root is named `SC Demo Runtime`
- there are top-level children named `SceneInstance`, `SceneCollision`, and `RuntimePlayer`

## 2. Verify runtime player replacement

Expand `RuntimePlayer`.

Confirm:
- there is a child named `PF Player`
- there is a child named `FollowCamera2D`

Expand `SceneInstance/SC Demo/Prefabs`.

Confirm:
- there is no active placeholder `PF Player` left under the imported scene instance

Expected result:
- the runtime scene uses the collision-aware runtime player wrapper instead of the raw imported scene player placement

## 3. Verify scene collision

Expand `SceneCollision`.

Confirm collision bodies exist for:
- `Layer 1 - Wall Collision`
- `Layer 2 - Wall Collision`
- `Layer 3 - Wall Collision`

Expected result:
- wall collision is present in the runtime scene without changing the raw authoring import

## 4. Run the runtime scene

Run:

`res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo Runtime.tscn`

Controls:
- `WASD` or arrow keys

Confirm:
- the player is visible immediately
- the camera obviously follows the player
- the player cannot walk through wall layers
- the south bridge/tunnel can be entered from either side without the player drawing over the bridge/gate foreground
- holding movement into the crate just north of the south bridge pushes it instead of permanently trapping the player in the underpass
- stairs and altar/rune prefabs still exist in the map and can be approached during play

## 5. Verify reports

Open:

- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- `res://cainos_imports/basic_real_acceptance/reports/asset_catalog.md`

Confirm:
- `SC Demo` includes a `runtime_scene_path`
- `SC Demo Runtime.tscn` is the runtime path recorded for the imported scene

## Pass checklist

- `SC Demo Runtime.tscn` opens with `SceneInstance`, `SceneCollision`, and `RuntimePlayer`
- the runtime player wrapper replaces the placeholder imported player
- wall collision exists for the imported wall layers
- the scene is playable with visible camera follow
- the south bridge underpass has pass-through collision and foreground occlusion
- runtime Rigidbody2D props can be pushed by the player
- report/catalog output records the runtime scene path

## If it fails

Capture:
- a screenshot of the `SC Demo Runtime.tscn` Scene dock
- a screenshot of the running runtime scene
- `res://cainos_imports/basic_real_acceptance/reports/import_manifest.json`
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- any Godot errors shown in the Output panel
