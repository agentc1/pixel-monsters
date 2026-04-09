# Cainos Basic Importer

This repository contains a Godot 4.6+ addon that imports the **Pixel Art Top Down - Basic** pack into Godot-native authoring assets.

The repo is intentionally code-only. It does not include Cainos pack content or committed generated imports. You supply your own licensed Basic pack locally when using the addon.

Current project entrypoint:
- `godot_project/project.godot`

Main addon files:
- `godot_project/addons/cainos_basic_importer/plugin.cfg`
- `godot_project/addons/cainos_basic_importer/plugin.gd`
- `godot_project/addons/cainos_basic_importer/basic_pack_importer.gd`
- `godot_project/addons/cainos_basic_importer/importer_dock.gd`
- `godot_project/addons/cainos_basic_importer/unity_package_reader.gd`
- `godot_project/addons/cainos_basic_importer/unity_metadata_registry.gd`

Current v1 shape:
- recommended input: direct `.unitypackage` or extracted Unity metadata folder
- default output: named semantic prefab scenes plus paintable `TileSet` resources
- fallback output: atlas-cell scenes when semantic metadata is unavailable or disabled
- helper assets: preview map, prefab catalog, compatibility report, and import manifest

Use `godot_project/docs/Quickstart.md` for the beginner workflow and `godot_project/docs/KnownDifferences.md` for the v1 compatibility boundary.
