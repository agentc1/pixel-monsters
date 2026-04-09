extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var fixture_root := str(args.get("fixture_root", ""))
	var output_root := str(args.get("output_root", "res://cainos_imports/basic_regression"))
	if fixture_root.is_empty():
		_fail("Missing --fixture-root")
		_finish()
		return

	var manifest_path := fixture_root.path_join("fixture_manifest.json")
	if not FileAccess.file_exists(manifest_path):
		_fail("Fixture manifest missing: %s" % manifest_path)
		_finish()
		return

	var fixture_manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (fixture_manifest is Dictionary):
		_fail("Fixture manifest is invalid JSON: %s" % manifest_path)
		_finish()
		return

	var expected: Dictionary = fixture_manifest.get("expected", {})
	var sample_prefabs: Dictionary = expected.get("sample_prefabs", {})

	_validate_tilesets(output_root)
	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_preview_map.tscn"), "basic_preview_map", true)
	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_prefab_catalog.tscn"), "basic_prefab_catalog", false)
	_validate_bush_prefab(output_root, str(sample_prefabs.get("bush", "")), expected)
	_validate_lantern_prefab(output_root, str(sample_prefabs.get("lantern", "")), expected)
	_validate_stairs_prefab(output_root, str(sample_prefabs.get("stairs", "")))
	_validate_altar_prefab(output_root, str(sample_prefabs.get("altar", "")))
	_validate_rune_prefab(output_root, str(sample_prefabs.get("rune", "")))
	_validate_edge_prefab(output_root, str(sample_prefabs.get("edge", "")), expected)
	_validate_polygon_prefab(output_root, str(sample_prefabs.get("polygon", "")))
	_validate_player_prefab(output_root, str(sample_prefabs.get("player", "")))
	_validate_broken_prefab_absent(output_root, str(sample_prefabs.get("broken", "")))
	_validate_editor_only_prefab_absent(output_root, str(sample_prefabs.get("editor_only", "")))

	_finish()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	var index := 0
	while index < args.size():
		var token := args[index]
		match token:
			"--fixture-root":
				if index + 1 < args.size():
					parsed["fixture_root"] = args[index + 1]
					index += 1
			"--output-root":
				if index + 1 < args.size():
					parsed["output_root"] = args[index + 1]
					index += 1
		index += 1
	return parsed


func _validate_tilesets(output_root: String) -> void:
	var tilesets := [
		output_root.path_join("tilesets/basic_grass_tileset.tres"),
		output_root.path_join("tilesets/basic_stone_ground_tileset.tres"),
		output_root.path_join("tilesets/basic_wall_tileset.tres"),
		output_root.path_join("tilesets/basic_struct_tileset.tres"),
	]
	for tileset_path in tilesets:
		var resource := load(tileset_path)
		_assert_true(resource is TileSet, "TileSet loads: %s" % tileset_path)
		if resource is TileSet:
			_assert_true(resource.get_source_count() > 0, "TileSet has atlas sources: %s" % tileset_path)


func _validate_helper_scene(scene_path: String, expected_name: String, expect_tile_layers: bool) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Helper scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Helper scene instantiates: %s" % scene_path)
	if instance == null:
		return
	_assert_eq(instance.name, expected_name, "Helper scene root name: %s" % expected_name)
	if expect_tile_layers:
		var tile_layers := _count_tile_map_layers(instance)
		_assert_true(tile_layers >= 1, "Preview scene includes TileMapLayer nodes")
	instance.free()


func _validate_bush_prefab(output_root: String, prefab_name: String, expected: Dictionary) -> void:
	var root := _instantiate_prefab(output_root, "plants", prefab_name)
	if root == null:
		return
	var shadow := root.find_child("Shadow", true, false)
	_assert_true(shadow is Node2D, "Bush prefab keeps Shadow child")
	if shadow is Node2D:
		var shadow_expected: Array = expected.get("bush_shadow_position", [8.0, 4.0]) as Array
		_assert_vector2_close(
			shadow.position,
			_vector2_from_array(shadow_expected, Vector2(8.0, 4.0)),
			"Bush shadow local position"
		)
	root.free()


func _validate_lantern_prefab(output_root: String, prefab_name: String, expected: Dictionary) -> void:
	var root := _instantiate_prefab(output_root, "props", prefab_name)
	if root == null:
		return
	var body := root.find_child("BoxCollider_0", true, false)
	_assert_true(body is StaticBody2D, "Lantern prefab has StaticBody2D box collider")
	if body is StaticBody2D:
		var shape_node := _first_collision_shape(body)
		_assert_true(shape_node != null, "Lantern box collider has CollisionShape2D")
		if shape_node != null and shape_node.shape is RectangleShape2D:
			var size_expected: Array = expected.get("lantern_box_size", [16.0, 24.0]) as Array
			_assert_vector2_close(
				shape_node.shape.size,
				_vector2_from_array(size_expected, Vector2(16.0, 24.0)),
				"Lantern rectangle collider size"
			)
		else:
			_fail("Lantern collider shape is not RectangleShape2D")
	root.free()


func _validate_stairs_prefab(output_root: String, prefab_name: String) -> void:
	var root := _instantiate_prefab(output_root, "struct", prefab_name)
	if root == null:
		return
	_assert_true(root.has_meta("cainos_behavior_hints"), "Stairs prefab preserves normalized behavior hints")
	var trigger_node: Node = root.find_child("Stairs Layer Trigger", true, false)
	if trigger_node == null:
		trigger_node = root
	_assert_true(trigger_node != null, "Stairs prefab includes a behavior metadata node")
	_assert_true(trigger_node.has_meta("unity_mono_behaviours"), "Stairs behavior node keeps legacy MonoBehaviour metadata")
	_assert_true(trigger_node.has_meta("cainos_behavior_hints"), "Stairs behavior node keeps node-local behavior hints")
	root.free()


func _validate_altar_prefab(output_root: String, prefab_name: String) -> void:
	var root := _instantiate_prefab(output_root, "props", prefab_name)
	if root == null:
		return
	var altar_hints := _behavior_hints_for(root, "altar_trigger")
	_assert_true(not altar_hints.is_empty(), "Altar prefab exposes altar_trigger behavior hint")
	if not altar_hints.is_empty():
		var data: Dictionary = altar_hints[0].get("data", {})
		_assert_true(Array(data.get("rune_node_paths", [])).size() >= 2, "Altar behavior hint preserves rune node paths")
	root.free()


func _validate_rune_prefab(output_root: String, prefab_name: String) -> void:
	var root := _instantiate_prefab(output_root, "props", prefab_name)
	if root == null:
		return
	var root_hints := _behavior_hints_for(root, "sprite_color_animation")
	_assert_true(not root_hints.is_empty(), "Rune prefab exposes sprite_color_animation behavior hint")
	var glow := root.find_child("Glow", true, false)
	_assert_true(glow is Node2D, "Rune prefab keeps Glow helper node")
	if glow is Node:
		var node_hints := _behavior_hints_for(glow, "sprite_color_animation")
		_assert_true(not node_hints.is_empty(), "Glow node keeps node-local sprite_color_animation hint")
	root.free()


func _validate_edge_prefab(output_root: String, prefab_name: String, expected: Dictionary) -> void:
	var root := _instantiate_prefab(output_root, "struct", prefab_name)
	if root == null:
		return
	var body := root.find_child("EdgeCollider_0", true, false)
	_assert_true(body is StaticBody2D, "Edge prefab has StaticBody2D segment collider")
	if body is StaticBody2D:
		var shape_node := _first_collision_shape(body)
		_assert_true(shape_node != null, "Edge prefab has CollisionShape2D")
		if shape_node != null and shape_node.shape is SegmentShape2D:
			var edge_expected: Dictionary = expected.get("edge_segment", {"a": [-16.0, 0.0], "b": [16.0, 0.0]}) as Dictionary
			_assert_vector2_close(
				shape_node.shape.a,
				_vector2_from_array(edge_expected.get("a", [0.0, 0.0]) as Array, Vector2.ZERO),
				"Edge collider point A"
			)
			_assert_vector2_close(
				shape_node.shape.b,
				_vector2_from_array(edge_expected.get("b", [0.0, 0.0]) as Array, Vector2.ZERO),
				"Edge collider point B"
			)
		else:
			_fail("Edge collider shape is not SegmentShape2D")
	root.free()


func _validate_polygon_prefab(output_root: String, prefab_name: String) -> void:
	var root := _instantiate_prefab(output_root, "props", prefab_name)
	if root == null:
		return
	_assert_true(root.has_meta("unsupported_components"), "Polygon prefab preserves unsupported_components metadata")
	if root.has_meta("unsupported_components"):
		var unsupported: Variant = root.get_meta("unsupported_components")
		_assert_true(unsupported is Array and unsupported.has("PolygonCollider2D"), "Polygon prefab metadata flags PolygonCollider2D")
	root.free()


func _validate_player_prefab(output_root: String, prefab_name: String) -> void:
	var root := _instantiate_prefab(output_root, "player", prefab_name)
	if root == null:
		return
	var sprite := _find_first_sprite(root)
	_assert_true(sprite != null, "Player prefab includes a Sprite2D descendant")
	var player_hints := _behavior_hints_for(root, "top_down_character_controller")
	_assert_true(not player_hints.is_empty(), "Player prefab exposes controller behavior hint")
	root.free()


func _validate_broken_prefab_absent(output_root: String, prefab_name: String) -> void:
	var scene_path := output_root.path_join("scenes/prefabs/props/%s.tscn" % _sanitize_filename(prefab_name))
	_assert_true(not FileAccess.file_exists(ProjectSettings.globalize_path(scene_path)), "Broken prefab scene remains absent")


func _validate_editor_only_prefab_absent(output_root: String, prefab_name: String) -> void:
	var scene_path := output_root.path_join("scenes/prefabs/editor_only/%s.tscn" % _sanitize_filename(prefab_name))
	_assert_true(not FileAccess.file_exists(ProjectSettings.globalize_path(scene_path)), "Editor-only prefab scene remains absent")


func _instantiate_prefab(output_root: String, family: String, prefab_name: String) -> Node:
	var scene_path := output_root.path_join("scenes/prefabs/%s/%s.tscn" % [family, _sanitize_filename(prefab_name)])
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Prefab scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return null
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Prefab scene instantiates: %s" % scene_path)
	return instance


func _first_collision_shape(node: Node) -> CollisionShape2D:
	for child in node.get_children():
		if child is CollisionShape2D:
			return child
	return null


func _find_first_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node
	for child in node.get_children():
		var sprite := _find_first_sprite(child)
		if sprite != null:
			return sprite
	return null


func _behavior_hints_for(node: Node, expected_kind: String) -> Array:
	if not node.has_meta("cainos_behavior_hints"):
		return []
	var hints: Variant = node.get_meta("cainos_behavior_hints")
	if not (hints is Array):
		return []
	var matches := []
	for hint_variant in hints:
		var hint: Dictionary = hint_variant
		if str(hint.get("kind", "")) == expected_kind:
			matches.append(hint)
	return matches


func _count_tile_map_layers(node: Node) -> int:
	var count := 0
	if node is TileMapLayer:
		count += 1
	for child in node.get_children():
		count += _count_tile_map_layers(child)
	return count


func _sanitize_filename(value: String) -> String:
	return value.replace("/", "-").replace("\\", "-").replace(":", "").replace("*", "").replace("?", "").replace("\"", "").replace("<", "").replace(">", "").replace("|", "")


func _vector2_from_array(value: Array, fallback: Vector2) -> Vector2:
	if value.size() < 2:
		return fallback
	return Vector2(float(value[0]), float(value[1]))


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_fail(message)


func _assert_eq(actual, expected, message: String) -> void:
	if actual == expected:
		print("PASS: %s" % message)
	else:
		_fail("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])


func _assert_vector2_close(actual: Vector2, expected: Vector2, message: String, epsilon := 0.01) -> void:
	if actual.distance_to(expected) <= epsilon:
		print("PASS: %s" % message)
	else:
		_fail("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])


func _fail(message: String) -> void:
	push_error(message)
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All generated output validation checks passed.")
		quit(0)
	else:
		print("Validation failures: %d" % _failures.size())
		for failure in _failures:
			print(" - %s" % failure)
		quit(1)
