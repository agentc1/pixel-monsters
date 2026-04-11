# Known Differences From Unity

This importer is authoring-first. It does not attempt full Unity parity in v1.

## Imported directly

- atlas textures copied into the project
- paintable `TileSet` resources
- named prefab scenes for the supported static Basic prefabs
- authoring-first imports of `SC Demo.unity` and `SC All Props.unity`
- framed preview scenes for both shipped Unity scenes plus a playable `SC Demo Runtime` wrapper scene
- `BoxCollider2D`, 2-point `EdgeCollider2D`, and supported `PolygonCollider2D` mappings where they are straightforward
- runtime-ready rigidbody props, runtime stairs triggers, and altar/rune runtime behavior for the supported Basic prefabs
- scene-level wall collision and a live follow camera in `SC Demo Runtime.tscn`
- Basic sorting layers, sorting orders, and local-z tiebreaks for imported prefab sprites and scene tile layers
- helper scenes for preview, prefab browsing, and runtime validation

## Approximated

- fallback atlas-cell scenes when semantic prefab import is unavailable or disabled
- player helper animation assets, which are preview-oriented rather than a full Unity controller conversion

## Manual in v1

- exact Unity renderer parity in edge cases outside the Basic pack's Layer 1/2/3 sprite and tilemap usage
- scene-level MonoBehaviour/script parity in imported Unity scenes
- full player animator-graph parity beyond the imported Godot-native directional controller

## Unsupported in v1

- Unity scripts as live runtime behavior
- Unity materials and shaders
- URP patch packages
- full Unity demo-scene parity
