# Manual Test 03: Sample Prefab Inspection

## Goal

Inspect anchor prefabs and confirm the importer preserved the important structure for each one.

These checks assume you have already imported the Basic pack.

## 1. Bush prefab

Open:

`res://cainos_imports/basic/scenes/prefabs/plants/PF Plant - Bush 01.tscn`

Check in the Scene dock:
- root node exists
- a child named `Shadow` exists

Check in the 2D view:
- the bush appears with a separate shadow element

## 2. Stone Lantern prefab

Open:

`res://cainos_imports/basic/scenes/prefabs/props/PF Props - Stone Lantern 01.tscn`

Check in the Scene dock:
- root node exists
- a child named `BoxCollider_0` exists
- `BoxCollider_0` contains `CollisionShape2D`

Check in the Inspector:
- select `CollisionShape2D`
- confirm the shape is a rectangle

## 3. Stairs prefab

Open:

`res://cainos_imports/basic/scenes/prefabs/struct/PF Struct - Stairs S 01 L.tscn`

Check in the Scene dock:
- the scene opens and contains visible stair art

Check in the Inspector:
- inspect the stairs nodes, especially `Stairs Layer Trigger`
- open the `Metadata` section on the root and confirm `cainos_behavior_hints` exists
- open the `Metadata` section on `Stairs Layer Trigger`
- confirm both `cainos_behavior_hints` and `unity_mono_behaviours` exist there

Expected result:
- the prefab is visually imported
- runtime behavior is not implemented here, but the deferred Unity behavior is recorded both as normalized `cainos_behavior_hints` and the legacy raw `unity_mono_behaviours` payload

## 3b. East/West stairs prefabs

Open each of these scenes:

- `res://cainos_imports/basic/scenes/prefabs/struct/PF Struct - Stairs E 01.tscn`
- `res://cainos_imports/basic/scenes/prefabs/struct/PF Struct - Stairs E 02.tscn`
- `res://cainos_imports/basic/scenes/prefabs/struct/PF Struct - Stairs W 01.tscn`
- `res://cainos_imports/basic/scenes/prefabs/struct/PF Struct - Stairs W 02.tscn`

Check in the Scene dock:
- the scene opens and contains visible stair art
- a node named `Stairs Layer Trigger` exists

Check in the Inspector:
- on the root node, confirm `cainos_behavior_hints` exists in `Metadata`
- on `Stairs Layer Trigger`, confirm both `cainos_behavior_hints` and `unity_mono_behaviours` exist

Expected result:
- the east/west stairs are now generated as scenes instead of remaining unresolved
- they are still deferred-behavior prefabs, not runnable stairs logic

## 4. Player prefab

Open:

`res://cainos_imports/basic/scenes/prefabs/player/PF Player.tscn`

Check in the Scene dock:
- root node exists
- at least one sprite child exists

Check in the 2D view:
- the player art is visible and crisp, not blurry

## Pass checklist

- Bush keeps a separate `Shadow` child
- Stone Lantern keeps a rectangle collision child
- Stairs preserve deferred Unity behavior metadata
- East/west stairs now open as generated prefab scenes
- Player scene opens and shows visible sprite art

## If it fails

Capture:
- the exact prefab path
- a screenshot of the Scene dock
- a screenshot of the Inspector metadata or collision shape when relevant
- any error text from the Output panel
