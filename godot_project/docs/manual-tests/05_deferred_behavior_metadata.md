# Manual Test 05: Deferred Behavior Metadata

## Goal

Confirm that the remaining manual player prefab, plus the runtime stairs and altar/rune prefabs, expose normalized `cainos_behavior_hints` metadata in addition to the legacy raw Unity metadata where applicable.

These checks assume you have already imported the Basic pack.

## 1. Runtime stairs trigger metadata

Open:

`res://cainos_imports/basic/scenes/prefabs/struct/PF Struct - Stairs S 01 L.tscn`

Check:
- select the scene root and open `Metadata`
- confirm `cainos_behavior_hints` exists
- select `Stairs Layer Trigger`
- confirm `cainos_behavior_hints` exists there too
- confirm the hint includes a `kind` of `stairs_layer_trigger`
- confirm the hint data contains upper/lower layer and sorting-layer names
- confirm `unity_mono_behaviours` still exists on `Stairs Layer Trigger`

Expected result:
- the stairs scene is already runtime-enabled
- the normalized hint and legacy raw metadata are both still present for traceability

## 2. Altar trigger

Open:

`res://cainos_imports/basic/scenes/prefabs/props/PF Props - Altar 01.tscn`

Check:
- select the scene root and open `Metadata`
- confirm `cainos_behavior_hints` exists
- confirm one hint has `kind = altar_trigger`
- confirm the hint data includes:
  - `rune_node_paths`
  - `lerp_speed`
  - `trigger_mode`

Expected result:
- the altar scene is runtime-enabled, but the normalized hint remains present for traceability
- the rune-node paths point at the generated rune helper nodes in the scene

## 3. Rune pillar glow

Open:

`res://cainos_imports/basic/scenes/prefabs/props/PF Props - Rune Pillar X2.tscn`

Check:
- select the scene root and open `Metadata`
- confirm `cainos_behavior_hints` exists
- select the `Glow` node and confirm it also has `cainos_behavior_hints`
- confirm one hint has `kind = sprite_color_animation`
- confirm the hint data includes:
  - `duration_seconds`
  - `gradient_mode`
  - `color_keys`
  - `alpha_keys`

Expected result:
- the rune pillar scene is runtime-enabled
- the normalized glow-animation hint is still present on both the root and `Glow` node

## 4. Player controller

Open:

`res://cainos_imports/basic/scenes/prefabs/player/PF Player.tscn`

Check:
- select the scene root and open `Metadata`
- confirm `cainos_behavior_hints` exists
- confirm one hint has `kind = top_down_character_controller`
- confirm the hint data includes:
  - `speed`
  - `input_scheme`
  - `direction_parameter`
  - `moving_parameter`
  - `requires_animator`
  - `requires_rigidbody2d`

## 5. Editor-only Unity assets

Open:

`res://cainos_imports/basic/reports/compatibility_report.md`

Check:
- confirm `TP Grass`, `TP Stone Ground`, and `TP Wall` appear under `Unity Editor-Only Assets`
- confirm they do **not** appear under the semantic prefab tier sections

## Pass checklist

- Stairs expose normalized `stairs_layer_trigger` hints
- Altar exposes normalized `altar_trigger` hints with rune-node paths
- Rune Pillar exposes normalized `sprite_color_animation` hints
- Player exposes normalized `top_down_character_controller` hints
- Editor-only Unity tile-palette prefabs are reported separately from semantic prefab tiers
- runtime-enabled prefabs still keep their normalized hints for traceability

## If it fails

Capture:
- the exact scene or report path
- a screenshot of the relevant `Metadata` section
- a screenshot of the Scene dock if node paths look wrong
- any error text from the Output panel
