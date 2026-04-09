# Known Differences From Unity

This importer is authoring-first. It does not attempt full Unity parity in v1.

## Imported directly

- atlas textures copied into the project
- paintable `TileSet` resources
- generic prop and plant scenes from atlas cells
- a player preview resource and scene

## Approximated

- baked-shadow helper scenes from the `Extra/` atlases
- player animations as row-based Godot `SpriteFrames`, not exact Unity controller behavior

## Manual in v1

- one-to-one reconstruction of named Unity prefabs
- rebuilding the Unity demo scenes
- exact sorting semantics from Unity layers and triggers

## Unsupported in v1

- Unity scripts and gameplay components
- Unity materials and shaders
- URP patch packages
- direct `.unitypackage` import without extracted textures

