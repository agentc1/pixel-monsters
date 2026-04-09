# Quickstart

## What this addon does

The addon imports a locally supplied **Pixel Art Top Down - Basic** pack into:
- external `TileSet` resources for `TileMapLayer`
- named prefab scenes reconstructed from Unity metadata when available
- fallback atlas-cell scenes only when you enable them
- player helper assets
- preview/catalog helper scenes
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
- `tilesets/`
- `scenes/`
- `reports/`

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

Use them to verify that textures, TileSets, and named prefab scenes imported correctly.

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

Testing tracks:
- synthetic track: run `./godot_project/tests/run_basic_regressions.sh` with no licensed content
- real-pack track: run `./godot_project/tests/run_basic_real_pack_acceptance.sh /absolute/path/to/basic.unitypackage`

## Reimport rule

Everything under `res://cainos_imports/basic/` is treated as generated output and may be replaced on reimport.

If you want to customize an imported asset:
1. duplicate it into your own folder outside `res://cainos_imports/basic/`
2. edit the duplicate there

## Source files and licensing

This repository is code-only. It does not ship the Cainos pack itself.

You must supply your own licensed Basic pack locally when you run the importer.
