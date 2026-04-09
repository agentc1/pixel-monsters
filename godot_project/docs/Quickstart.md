# Quickstart

## What this addon does

The addon imports the extracted **Pixel Art Top Down - Basic** pack into:
- external `TileSet` resources for `TileMapLayer`
- generic prop and plant scenes
- player preview assets
- a preview scene
- manifest, catalog, and compatibility reports

## First import

1. Open the Godot project in [project.godot](/home/parallels/src/github.com/agentc1/pixel-monsters/godot_project/project.godot).
2. Confirm the plugin is enabled in `Project -> Project Settings -> Plugins`.
3. Open the `Cainos Importer` dock on the right side of the editor.
4. Set `Source path` to either:
   - the extracted pack folder that contains `Texture/`
   - or the original zip that contains `Texture/`
5. Leave the default `Generated output root` unless you have a reason to change it.
6. Click `Scan Only` to preview what the importer found.
7. Click `Import`.

## What gets generated

Look under `res://cainos_imports/basic/`:
- `textures/source/`
- `tilesets/`
- `scenes/`
- `animations/`
- `reports/`

## How to paint a map

1. Create or open your own scene.
2. Add a child node: `TileMapLayer`.
3. In the Inspector, assign one of the generated TileSets from `res://cainos_imports/basic/tilesets/`.
4. Open the `TileMap` bottom panel.
5. Pick tiles and paint directly into the `TileMapLayer`.

## How to place props and plants

1. Open the generated scene folders under `res://cainos_imports/basic/scenes/`.
2. Drag a prop or plant scene into your map scene.
3. Duplicate, rename, or move copies into your own game folders if you want to customize them.

## Reimport rule

Everything under `res://cainos_imports/basic/` is treated as generated output and may be replaced on reimport.

If you want to customize an imported asset:
1. duplicate it into your own folder outside `res://cainos_imports/basic/`
2. edit the duplicate there

