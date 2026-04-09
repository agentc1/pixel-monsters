# Manual Test 01: Scan And Import

## Goal

Verify that a beginner can scan and import the real Basic pack and end up with generated assets under `res://cainos_imports/basic/`.

This is the **real-pack** track. If you do not have licensed pack content available, use the synthetic regression track described in [Quickstart.md](/home/parallels/src/github.com/agentc1/pixel-monsters/godot_project/docs/Quickstart.md) instead.

## Before you start

You need:
- Godot 4.6+
- your licensed Basic pack as either:
  - the original `.unitypackage`, or
  - an extracted Unity folder containing `.prefab` and `.meta`

In the steps below, replace `/ABSOLUTE/PATH/TO/BASIC.unitypackage` with your real path.

## Headless path

1. Open a terminal in the repository root.
2. Run scan-only:

```bash
godot --headless --path godot_project --script res://tools/headless_basic_import.gd -- --mode scan --source /ABSOLUTE/PATH/TO/BASIC.unitypackage
```

Expected result:
- the command exits successfully
- the summary reports semantic prefab import as available when `.unitypackage` or extracted metadata is present

3. Run import:

```bash
godot --headless --path godot_project --script res://tools/headless_basic_import.gd -- --mode import --source /ABSOLUTE/PATH/TO/BASIC.unitypackage
```

4. Finish Godot’s resource import step:

```bash
godot --headless --import --path godot_project
```

Expected generated paths:
- `res://cainos_imports/basic/tilesets/`
- `res://cainos_imports/basic/scenes/prefabs/`
- `res://cainos_imports/basic/scenes/helpers/`
- `res://cainos_imports/basic/reports/`

## Editor path

1. Open `godot_project/project.godot`.
2. Go to `Project -> Project Settings -> Plugins`.
3. Confirm `Cainos Basic Importer` is enabled.
4. Open the `Cainos Importer` dock on the right.
5. Paste your source path into `Source path`.
6. Leave semantic prefab import enabled.
7. Click `Scan Only`.
8. Review the result text in the dock.
9. Click `Import`.

Expected result:
- the dock finishes without an error banner
- generated assets appear under `FileSystem -> res://cainos_imports/basic/`

## Pass checklist

- Scan-only completes successfully
- Import completes successfully
- `import_manifest.json` exists in `res://cainos_imports/basic/reports/`
- `compatibility_report.md` exists in `res://cainos_imports/basic/reports/`
- `compatibility_report.md` lists prefab-level entries grouped by tier, not just pack-level counts
- `asset_catalog.md` lists generated named prefab scenes individually, not just collection folders
- `basic_preview_map.tscn` exists in `res://cainos_imports/basic/scenes/helpers/`

## If it fails

Capture:
- the full terminal output or dock error text
- `res://cainos_imports/basic/reports/import_manifest.json` if it exists
- `res://cainos_imports/basic/reports/compatibility_report.md` if it exists
