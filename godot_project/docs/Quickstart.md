# Quickstart

## What this addon does

The addon imports a locally supplied **Pixel Art Top Down - Basic** pack into:
- external `TileSet` resources for `TileMapLayer`
- named prefab scenes reconstructed from Unity metadata when available
- imported authoring-first Godot scenes for `SC Demo.unity` and `SC All Props.unity`
- framed preview wrappers for both shipped Unity scenes so the imported maps are centered and readable at runtime
- a playable `SC Demo Runtime` wrapper with real scene collision and a live follow camera
- fallback atlas-cell scenes only when you enable them
- player helper assets
- preview/catalog helper scenes
- a runtime player demo scene
- a runtime stairs demo scene
- a runtime altar/runes demo scene
- manifest, catalog, and compatibility reports

## First import

1. Open `godot_project/project.godot`.
2. Confirm the plugin is enabled in `Project -> Project Settings -> Plugins`.
3. Open the `Cainos Importer` dock on the right side of the editor.
4. Set `Source path` to either:
   - the original Basic `.unitypackage` file
   - an extracted Unity project folder containing `.prefab` and `.meta`
   - or a texture-only zip/folder if you want fallback atlas import only
5. Leave the default `Generated output root` unless you have a reason to change it.
6. Click `Scan Only` to preview what the importer found.
7. Click `Import`.

## What gets generated

Look under `res://cainos_imports/basic/`:
- `textures/source/`
- `tilesets/` including grass, stone ground, wall, struct, and shadow TileSets
- `scenes/`
- `reports/`

Important generated scene paths:
- `res://cainos_imports/basic/scenes/helpers/basic_preview_map.tscn`
- `res://cainos_imports/basic/scenes/helpers/basic_prefab_catalog.tscn`
- `res://cainos_imports/basic/scenes/helpers/basic_runtime_player_demo.tscn`
- `res://cainos_imports/basic/scenes/helpers/basic_runtime_stairs_demo.tscn`
- `res://cainos_imports/basic/scenes/helpers/basic_runtime_altar_runes_demo.tscn`
- `res://cainos_imports/basic/scenes/unity/SC Demo.tscn`
- `res://cainos_imports/basic/scenes/unity/SC Demo Runtime.tscn`
- `res://cainos_imports/basic/scenes/helpers/sc_demo_preview.tscn`
- `res://cainos_imports/basic/scenes/unity/SC All Props.tscn`
- `res://cainos_imports/basic/scenes/helpers/sc_all_props_preview.tscn`

The importer currently generates `SC Demo.tscn` and `SC All Props.tscn` as raw authoring imports, `sc_demo_preview.tscn` and `sc_all_props_preview.tscn` as framed visual previews, and `SC Demo Runtime.tscn` as the playable wrapper for the shipped demo scene.

## How to paint a map

1. Create or open your own scene.
2. Add a child node: `TileMapLayer`.
3. In the Inspector, assign one of the generated TileSets from `res://cainos_imports/basic/tilesets/`.
4. Open the `TileMap` bottom panel.
5. Pick tiles and paint directly into the `TileMapLayer`.

## How to place named assets

1. Open the generated scene folders under `res://cainos_imports/basic/scenes/prefabs/`.
2. Drag plant, prop, struct, or player scenes into your map scene.
3. Duplicate, rename, or move copies into your own game folders if you want to customize them.

## Helper scenes

The importer also generates:
- `res://cainos_imports/basic/scenes/helpers/basic_preview_map.tscn`
- `res://cainos_imports/basic/scenes/helpers/basic_prefab_catalog.tscn`
- `res://cainos_imports/basic/scenes/helpers/basic_runtime_player_demo.tscn`
- `res://cainos_imports/basic/scenes/helpers/basic_runtime_stairs_demo.tscn`
- `res://cainos_imports/basic/scenes/helpers/basic_runtime_altar_runes_demo.tscn`
- `res://cainos_imports/basic/scenes/unity/SC Demo.tscn`
- `res://cainos_imports/basic/scenes/unity/SC Demo Runtime.tscn`
- `res://cainos_imports/basic/scenes/helpers/sc_demo_preview.tscn`
- `res://cainos_imports/basic/scenes/unity/SC All Props.tscn`
- `res://cainos_imports/basic/scenes/helpers/sc_all_props_preview.tscn`

Use `SC Demo.tscn` and `SC All Props.tscn` for raw structure/authoring checks, `sc_demo_preview.tscn` and `sc_all_props_preview.tscn` for framed visual comparison, and `SC Demo Runtime.tscn` for playable validation with the imported player, wall collision, and follow camera.

## Automated regression check

From the repository root, you can run the synthetic regression suite:

```bash
./godot_project/tests/run_basic_regressions.sh
```

This generates a small synthetic `.unitypackage`, runs the importer against it, forces Godot to finish importing copied resources, and validates the resulting helper scenes and sample prefabs.

Important note:
- this fixture is **importer-valid** for this addon’s parser and regression suite
- it is **not** intended to be treated as a Unity-authored package or a package Unity itself must import

## Manual QA scripts

Beginner-friendly manual checks are documented here:
- `godot_project/docs/manual-tests/01_scan_and_import.md`
- `godot_project/docs/manual-tests/02_preview_and_catalog.md`
- `godot_project/docs/manual-tests/03_sample_prefab_inspection.md`
- `godot_project/docs/manual-tests/04_real_pack_acceptance.md`
- `godot_project/docs/manual-tests/05_deferred_behavior_metadata.md`
- `godot_project/docs/manual-tests/06_polygon_collision_fidelity.md`
- `godot_project/docs/manual-tests/07_runtime_rigidbody_props.md`
- `godot_project/docs/manual-tests/08_runtime_stairs_support.md`
- `godot_project/docs/manual-tests/09_godot_mcp_bridge.md`
- `godot_project/docs/manual-tests/10_imported_unity_scene_demo.md`
- `godot_project/docs/manual-tests/11_runtime_altar_runes_support.md`
- `godot_project/docs/manual-tests/12_runtime_player_support.md`
- `godot_project/docs/manual-tests/13_sc_demo_runtime_scene.md`

Testing tracks:
- synthetic track: run `./godot_project/tests/run_basic_regressions.sh` with no licensed content
- real-pack track: run `./godot_project/tests/run_basic_real_pack_acceptance.sh /absolute/path/to/basic.unitypackage`

## Reimport rule

Everything under `res://cainos_imports/basic/` is treated as generated output and may be replaced on reimport.

If you want to customize an imported asset:
1. duplicate it into your own folder outside `res://cainos_imports/basic/`
2. edit the duplicate there

## Local cleanup

To remove generated imports and Godot editor cache state from your working tree:

```bash
./tools/cleanup_local_artifacts.sh
```

## Source files and licensing

This repository is code-only. It does not ship the Cainos pack itself.

You must supply your own licensed Basic pack locally when you run the importer.
