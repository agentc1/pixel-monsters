# Manual Test 10: Imported Unity Scene Demo

## Goal

Verify that the importer now reconstructs both shipped Unity scenes into usable Godot authoring scenes, generates separate framed preview scenes for both, and generates a playable runtime wrapper for `SC Demo.unity`.

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
- Layer 2 visual content draws above Layer 1 content, and Layer 3 visual content draws above Layer 2 content

## 3. Verify placed prefab instances

Expand `Prefabs`.

Confirm the scene includes placed instances for:
- `PF Player`
- `PF Props - Altar 01`
- `PF Struct - Stairs S 01 L`

Expected result:
- the scene is visibly populated, not just a bare tilemap
- prefab instances appear under `Prefabs`, not flattened into loose sprites
- trees and gates with upper/lower parts keep their upper Layer 2 visuals in front of lower Layer 1 visuals
- shadows for the player, lanterns, bushes, trees, and similar props stay behind the body/top sprites

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
- tree tops, gate tops, shadows, and Layer 1/2/3 map strata read as layered rather than flattened
- if `local_inputs/basic_pack/scene-overview.png` exists locally, the preview composition is broadly comparable to it

## 6. Verify the runtime wrapper

Open:

`res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo Runtime.tscn`

Run the scene.

Confirm:
- the player is visible and controllable
- the camera follows the player
- the player cannot walk through wall layers
- the raw imported `PF Player` placeholder is no longer the active player in this scene

Expected result:
- the runtime scene is clearly separate from the raw authoring scene
- the scene is playable enough to validate imported layout, collision, stairs, and altar/rune behavior together

## 7. Verify reports

Open:

- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- `res://cainos_imports/basic_real_acceptance/reports/asset_catalog.md`

Confirm:
- `SC Demo` appears under the imported Unity scenes section
- `SC All Props` also appears under the imported Unity scenes section
- `asset_catalog.md` lists `SC Demo.tscn` under imported scenes
- the `SC Demo` entry records `sc_demo_preview.tscn` as the preview path
- the `SC Demo` entry records `SC Demo Runtime.tscn` as the runtime path
- `asset_catalog.md` lists `SC All Props.tscn` under imported scenes
- the `SC All Props` entry records `sc_all_props_preview.tscn` as the preview path
- the `SC All Props` entry leaves the runtime path empty

## 8. Verify SC All Props raw and preview scenes

Open:

`res://cainos_imports/basic_real_acceptance/scenes/unity/SC All Props.tscn`

Check in the Scene dock:
- the root is named `SC All Props`
- there are top-level children named `Tilemaps`, `Prefabs`, and `Markers`
- `Tilemaps` contains `Layer 1 - Grass` and `Layer 1 - Wall`
- `Prefabs` contains many placed prefab instances

Open:

`res://cainos_imports/basic_real_acceptance/scenes/helpers/sc_all_props_preview.tscn`

Run the scene.

Confirm:
- the map is centered in the window like the `SC Demo` preview
- the preview is readable without a gameplay wrapper
- tree/gate upper parts render above lower parts, and shadows stay behind prop bodies
- there is no expectation of a runtime/player wrapper for `SC All Props` in this slice

## Pass checklist

- `SC Demo.tscn` opens and is structured under `Tilemaps`, `Prefabs`, and `Markers`
- the imported scene includes the expected tile layers
- Layer 1/2/3 tile and prefab visual ordering is visibly preserved for Basic scenes
- the scene includes placed player, altar, and stair prefabs
- `sc_demo_preview.tscn` gives a centered, readable preview of the imported map
- `SC Demo Runtime.tscn` is playable with wall collision and a follow camera
- `SC All Props.tscn` opens and is structured under `Tilemaps`, `Prefabs`, and `Markers`
- `sc_all_props_preview.tscn` gives a centered, readable preview of the props scene
- the imported-scene reports list both `SC Demo` and `SC All Props` as generated

## If it fails

Capture:
- a screenshot of the Scene dock for `SC Demo.tscn`
- a screenshot of the Scene dock for `SC All Props.tscn`
- a screenshot of the imported layer names under `Tilemaps`
- a screenshot of the running `sc_demo_preview.tscn` window
- a screenshot of the running `sc_all_props_preview.tscn` window
- a screenshot of the running `SC Demo Runtime.tscn` window
- `res://cainos_imports/basic_real_acceptance/reports/import_manifest.json`
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- any Godot errors shown in the Output panel
