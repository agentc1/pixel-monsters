# Known Differences From Unity

This importer is authoring-first. It does not attempt full Unity parity in v1.

## Imported directly

- atlas textures copied into the project
- paintable `TileSet` resources
- named prefab scenes for the supported static Basic prefabs
- `BoxCollider2D`, 2-point `EdgeCollider2D`, and supported `PolygonCollider2D` mappings where they are straightforward
- helper scenes for preview and prefab browsing

## Approximated

- prefabs with partial collision fidelity where Unity uses unsupported collider/runtime features
- fallback atlas-cell scenes when semantic prefab import is unavailable or disabled
- player helper animation assets, which are preview-oriented rather than a full Unity controller conversion

## Manual in v1

- prefabs with MonoBehaviour-driven behavior such as stairs or trigger logic
- rebuilding the Unity demo scenes
- exact sorting semantics from Unity layers, sorting orders, and trigger conventions
- rigidbody behavior and any remaining unsupported collider cases

## Unsupported in v1

- Unity scripts as live runtime behavior
- Unity materials and shaders
- URP patch packages
- full Unity demo-scene parity
