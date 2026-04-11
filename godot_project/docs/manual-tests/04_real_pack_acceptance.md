# Manual Test 04: Real Pack Acceptance

## Goal

Run a quick developer-local smoke test against a real Unity-produced Basic pack and confirm the importer still works beyond the synthetic fixture path.

This script requires licensed content and is not suitable for public CI.

## Command

From the repository root:

```bash
./godot_project/tests/run_basic_real_pack_acceptance.sh /absolute/path/to/basic.unitypackage
```

You can also set `BASIC_SOURCE` instead of passing a positional argument.

## What it does

1. runs `scan` against the real source
2. fails if semantic import is not active
3. runs `import`
4. runs `godot --headless --import --path godot_project`
5. validates the generated helper scenes and anchor prefabs under:

`res://cainos_imports/basic_real_acceptance/`

## Expected generated outputs

- `res://cainos_imports/basic_real_acceptance/reports/import_manifest.json`
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- `res://cainos_imports/basic_real_acceptance/reports/asset_catalog.md`
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_preview_map.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_prefab_catalog.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_player_demo.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_stairs_demo.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_runtime_altar_runes_demo.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/sc_demo_preview.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/sc_all_props_preview.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo Runtime.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/unity/SC All Props.tscn`

## Anchor checks

The smoke validator checks these real generated assets:
- `SC Demo.tscn`
- `SC Demo Runtime.tscn`
- `SC All Props.tscn`
- `PF Plant - Bush 01`
- `PF Props - Barrel 01`
- `PF Props - Crate 01`
- `PF Props - Crate 02`
- `PF Props - Pot 01`
- `PF Props - Pot 02`
- `PF Props - Pot 03`
- `PF Props - Stone Lantern 01`
- `PF Props - Stone Cube 01`
- `PF Struct - Stairs S 01 L`
- `PF Struct - Stairs E 01`
- `PF Struct - Stairs E 02`
- `PF Struct - Stairs W 01`
- `PF Struct - Stairs W 02`
- `PF Props - Altar 01`
- `PF Props - Rune Pillar X2`
- `PF Props - Rune Pillar X3`
- `PF Player`

Expected structure:
- Bush keeps a `Shadow` child
- Tree and gate prefabs preserve Unity Layer 1/Layer 2 internal visual ordering, with upper/tree-top or gate-top sprites rendering above lower sprites
- Barrel, crate, pot, and stone-cube props now use runtime-ready `RigidBody2D` roots with preserved collision
- Stone Lantern keeps a rectangle-style collision shape
- Stone Lantern and Player shadows render behind their body sprites
- South/east/west stairs preserve normalized `cainos_behavior_hints`, keep legacy MonoBehaviour metadata, and now attach runtime stairs scripts
- Altar preserves normalized trigger metadata with rune-node mappings and now attaches the altar runtime trigger
- Rune Pillars preserve normalized glow-animation metadata and now attach the runtime color-animation script
- Player includes visible sprite content, the runtime actor helper, and the shared runtime controller on the prefab root
- `SC Demo.tscn` opens with `Tilemaps`, `Prefabs`, and `Markers`
- `SC Demo.tscn` contains the imported tilemap layers and placed prefab instances from the Unity scene
- `SC Demo.tscn` keeps Layer 2 tilemap visuals above Layer 1 tilemap visuals, and Layer 3 above Layer 2
- `sc_demo_preview.tscn` opens with a live centered camera for visual inspection
- `SC Demo Runtime.tscn` opens with `SceneInstance`, `SceneCollision`, and `RuntimePlayer`
- `SC Demo Runtime.tscn` replaces the placeholder imported player with a collision-aware runtime wrapper and live follow camera
- `SC Demo Runtime.tscn` includes collision bodies for `Layer 1 - Wall`, `Layer 2 - Wall`, and `Layer 3 - Wall`
- `SC All Props.tscn` opens with `Tilemaps`, `Prefabs`, and `Markers`
- `SC All Props.tscn` contains `Layer 1 - Grass` and `Layer 1 - Wall` plus placed prefab instances
- `sc_all_props_preview.tscn` opens with a live centered camera for visual inspection

Expected report detail:
- `compatibility_report.md` includes prefab-level entries for the anchor prefabs
- `compatibility_report.md` includes a Unity scenes section where both `SC Demo` and `SC All Props` are imported
- the `SC Demo` scene entry includes a preview scene path
- the `SC Demo` scene entry includes a runtime scene path
- the `SC All Props` scene entry includes a preview scene path and no runtime scene path
- `PF Struct - Stairs S 01 L` is listed under the supported-static tier with `stairs_runtime_imported`
- `PF Struct - Stairs E 01`, `PF Struct - Stairs E 02`, `PF Struct - Stairs W 01`, and `PF Struct - Stairs W 02` are also listed under the supported-static tier with `stairs_runtime_imported`
- `PF Props - Well 01` is listed under the supported-static tier with `polygon_collider_imported`
- `PF Props - Barrel 01`, `PF Props - Crate 01`, `PF Props - Pot 01`, and `PF Props - Stone Cube 01` are listed under the supported-static tier with `rigidbody_imported`
- `PF Props - Altar 01` is listed under the supported-static tier with `altar_runtime_imported`
- `PF Props - Rune Pillar X2` and `PF Props - Rune Pillar X3` are listed under the supported-static tier with `sprite_color_animation_runtime_imported`
- `PF Player` is listed under the supported-static tier with `player_controller_runtime_imported`, `player_directional_facing_imported`, and `runtime_actor_helper_attached`
- the unresolved tier is empty
- the approximated tier is empty for the real Basic pack
- `TP Grass`, `TP Stone Ground`, and `TP Wall` are listed under the editor-only Unity assets section instead of the semantic prefab tiers
- `asset_catalog.md` lists named prefab scene paths for Bush, Stone Lantern, Stairs, Altar, Rune Pillars, and Player
- `asset_catalog.md` lists `basic_runtime_player_demo.tscn`, `basic_runtime_stairs_demo.tscn`, and `basic_runtime_altar_runes_demo.tscn` under helper scenes
- `asset_catalog.md` lists `SC Demo.tscn` under imported scenes
- `asset_catalog.md` records `sc_demo_preview.tscn` as the preview path for `SC Demo`
- `asset_catalog.md` records `SC Demo Runtime.tscn` as the runtime path for `SC Demo`
- `asset_catalog.md` lists `SC All Props.tscn` under imported scenes
- `asset_catalog.md` records `sc_all_props_preview.tscn` as the preview path for `SC All Props`

## If it fails

Capture:
- the full terminal output
- `res://cainos_imports/basic_real_acceptance/reports/import_manifest.json`
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- any helper-scene or prefab load errors printed by Godot
