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
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_preview_map.tscn`
- `res://cainos_imports/basic_real_acceptance/scenes/helpers/basic_prefab_catalog.tscn`

## Anchor checks

The smoke validator checks these real generated assets:
- `PF Plant - Bush 01`
- `PF Props - Stone Lantern 01`
- `PF Struct - Stairs S 01 L`
- `PF Props - Altar 01`
- `PF Props - Rune Pillar X2`
- `PF Player`

Expected structure:
- Bush keeps a `Shadow` child
- Stone Lantern keeps a rectangle-style collision shape
- Stairs preserve normalized `cainos_behavior_hints` and deferred MonoBehaviour metadata
- Altar preserves normalized trigger metadata with rune-node mappings
- Rune Pillar preserves normalized glow-animation metadata
- Player includes visible sprite content

Expected report detail:
- `compatibility_report.md` includes prefab-level entries for the anchor prefabs
- `PF Struct - Stairs S 01 L` is listed under the manual-behavior tier
- `PF Props - Well 01` is listed under the approximated tier
- `TP Grass`, `TP Stone Ground`, and `TP Wall` are listed under the editor-only Unity assets section instead of the semantic prefab tiers
- `asset_catalog.md` lists named prefab scene paths for Bush, Stone Lantern, Stairs, Altar, Rune Pillar, and Player

## If it fails

Capture:
- the full terminal output
- `res://cainos_imports/basic_real_acceptance/reports/import_manifest.json`
- `res://cainos_imports/basic_real_acceptance/reports/compatibility_report.md`
- any helper-scene or prefab load errors printed by Godot
