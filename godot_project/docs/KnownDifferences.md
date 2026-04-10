# Known Differences From Unity

This importer is authoring-first. It does not attempt full Unity parity in v1.

## Imported directly

- atlas textures copied into the project
- paintable `TileSet` resources
- named prefab scenes for the supported static Basic prefabs
- an authoring-first import of `SC Demo.unity` as `SC Demo.tscn`
- `BoxCollider2D`, 2-point `EdgeCollider2D`, and supported `PolygonCollider2D` mappings where they are straightforward
- runtime-ready rigidbody props and runtime stairs triggers for the supported Basic stair prefabs
- helper scenes for preview, prefab browsing, and runtime stairs validation

## Approximated

- fallback atlas-cell scenes when semantic prefab import is unavailable or disabled
- player helper animation assets, which are preview-oriented rather than a full Unity controller conversion

## Manual in v1

- altar and rune-prefab trigger/animation behavior
- `SC All Props.unity` scene import
- scene-level tilemap collider and composite-collider reconstruction from Unity scenes
- live runtime camera behavior from imported Unity scenes
- exact sorting semantics from Unity layers, sorting orders, and trigger conventions
- player/controller runtime behavior and animator parity

## Unsupported in v1

- Unity scripts as live runtime behavior
- Unity materials and shaders
- URP patch packages
- full Unity demo-scene parity
