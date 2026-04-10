# Manual Test 10: Imported Unity Scene Demo

## Goal

Verify that the importer now reconstructs `SC Demo.unity` into a usable Godot authoring scene, generates a separate framed preview scene, and reports `SC All Props.unity` as deferred.

These checks assume you have already run the real-pack acceptance path:

```bash
./godot_project/tests/run_basic_real_pack_acceptance.sh /absolute/path/to/basic.unitypackage
```

Open `godot_project/project.godot` in Godot after the command finishes.

## 1. Open the raw imported scene

Open:

`res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo.tscn`

Check in the Scene dock:
- the root is named `SC Demo`
- there are top-level children named `Tilemaps`, `Prefabs`, and `Markers`

## 2. Verify tilemap layers

Expand `Tilemaps`.

Confirm these layers exist:
- `Layer 1 - Grass`
- `Layer 1 - Stone Ground`
- `Layer 1 - Wall`
- `Layer 1 - Wall Shadow`
- `Layer 2 - Grass`
- `Layer 2 - Wall`
- `Layer 2 - Wall Shadow`
- `Layer 3 - Grass`
- `Layer 3 - Wall`

Expected result:
- the imported scene contains `10` `TileMapLayer` nodes in total
- the visible layer names above are present
- `Layer 1 - Stone Ground` may be empty, but it should still exist as an authoring layer

## 3. Verify placed prefab instances

Expand `Prefabs`.

Confirm the scene includes placed instances for:
- `PF Player`
- `PF Props - Altar 01`
- `PF Struct - Stairs S 01 L`

Expected result:
- the scene is visibly populated, not just a bare tilemap
- prefab instances appear under `Prefabs`, not flattened into loose sprites

## 4. Verify marker data

Expand `Markers`.

Confirm a camera marker exists.

Select it and inspect `Metadata`.

Expected result:
- the marker preserves imported Unity camera information as metadata
- this is a marker/import artifact, not a live gameplay camera

## 5. Run the framed preview

Open:

`res://cainos_imports/basic_real_acceptance/scenes/helpers/sc_demo_preview.tscn`

Run the scene.

Confirm:
- the map is centered instead of clipped into the northwest corner
- the window is square and the assets are visibly larger/readable than the raw scene launch
- if `local_inputs/basic_pack/scene-overview.png` exists locally, the preview composition is broadly comparable to it

## 6. Verify reports

Open:

- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- `res://cainos_imports/basic_real_acceptance/reports/asset_catalog.md`

Confirm:
- `SC Demo` appears under the imported Unity scenes section
- `SC All Props` appears as deferred
- `asset_catalog.md` lists `SC Demo.tscn` under imported scenes
- the `SC Demo` entry records `sc_demo_preview.tscn` as the preview path

## Pass checklist

- `SC Demo.tscn` opens and is structured under `Tilemaps`, `Prefabs`, and `Markers`
- the imported scene includes the expected tile layers
- the scene includes placed player, altar, and stair prefabs
- `sc_demo_preview.tscn` gives a centered, readable preview of the imported map
- the imported scene reports `SC Demo` as generated and `SC All Props` as deferred

## If it fails

Capture:
- a screenshot of the Scene dock for `SC Demo.tscn`
- a screenshot of the imported layer names under `Tilemaps`
- a screenshot of the running `sc_demo_preview.tscn` window
- `res://cainos_imports/basic_real_acceptance/reports/import_manifest.json`
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- any Godot errors shown in the Output panel
