# Manual Test 02: Preview And Catalog

## Goal

Verify that the generated helper scenes open correctly and give a beginner a usable visual sanity check.

## Open the preview scene

1. Open `godot_project/project.godot`.
2. In the `FileSystem` panel, open:

`res://cainos_imports/basic/scenes/helpers/basic_preview_map.tscn`

3. Switch to the `2D` workspace if you are not already there.
4. Press `F6` to run the current scene, or use `Scene -> Run Current Scene`.

Expected result:
- the scene opens without missing-resource errors
- you can see multiple `TileMapLayer` nodes in the Scene dock
- the scene shows a simple preview area with imported tiles and placed prefab examples

## Open the prefab catalog scene

1. In the `FileSystem` panel, open:

`res://cainos_imports/basic/scenes/helpers/basic_prefab_catalog.tscn`

2. Press `F6` again to run the current scene.

Expected result:
- the scene opens without missing-resource errors
- the scene shows several imported named prefabs arranged in rows
- the Scene dock root is named `basic_prefab_catalog`

## Pass checklist

- `basic_preview_map.tscn` opens cleanly
- `basic_preview_map.tscn` runs without missing dependencies
- `basic_prefab_catalog.tscn` opens cleanly
- `basic_prefab_catalog.tscn` runs without missing dependencies

## Failure symptoms to note

- pink checkerboards or blank sprites
- “resource failed to load” messages
- helper scenes open but appear empty
- helper scenes run but throw console/script errors

If any of these happen, capture the exact error text from the Godot Output panel.
