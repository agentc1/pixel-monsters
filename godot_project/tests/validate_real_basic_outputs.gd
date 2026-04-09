extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var output_root := str(args.get("output_root", "res://cainos_imports/basic_real_acceptance"))

	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_preview_map.tscn"), "basic_preview_map", true)
	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_prefab_catalog.tscn"), "basic_prefab_catalog", false)
	_validate_bush_prefab(output_root)
	_validate_lantern_prefab(output_root)
	_validate_stairs_prefab(output_root)
	_validate_player_prefab(output_root)

	_finish()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	var index := 0
	while index < args.size():
		var token := args[index]
		match token:
			"--output-root":
				if index + 1 < args.size():
					parsed["output_root"] = args[index + 1]
					index += 1
		index += 1
	return parsed


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
		_assert_true(_count_tile_map_layers(instance) >= 1, "Preview scene includes TileMapLayer nodes")
	instance.free()


func _validate_bush_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "plants", "PF Plant - Bush 01")
	if root == null:
		return
	var shadow := root.find_child("Shadow", true, false)
	_assert_true(shadow is Node2D, "Bush prefab keeps Shadow child")
	root.free()


func _validate_lantern_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "props", "PF Props - Stone Lantern 01")
	if root == null:
		return
	var body := root.find_child("BoxCollider_0", true, false)
	_assert_true(body is StaticBody2D, "Stone Lantern keeps StaticBody2D box collider")
	if body is StaticBody2D:
		var shape_node := _first_collision_shape(body)
		_assert_true(shape_node != null, "Stone Lantern box collider has CollisionShape2D")
		if shape_node != null:
			_assert_true(shape_node.shape is RectangleShape2D, "Stone Lantern collider shape is RectangleShape2D")
	root.free()


func _validate_stairs_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "struct", "PF Struct - Stairs S 01 L")
	if root == null:
		return
	var behaviour_node := _find_first_node_with_meta(root, "unity_mono_behaviours")
	_assert_true(behaviour_node != null, "Stairs prefab preserves deferred MonoBehaviour metadata")
	if behaviour_node != null:
		var behaviours: Variant = behaviour_node.get_meta("unity_mono_behaviours")
		_assert_true(behaviours is Array and not behaviours.is_empty(), "Stairs MonoBehaviour metadata is non-empty")
	root.free()


func _validate_player_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "player", "PF Player")
	if root == null:
		return
	_assert_true(_find_first_sprite(root) != null, "Player prefab includes a Sprite2D descendant")
	root.free()


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


func _find_first_node_with_meta(node: Node, meta_key: String) -> Node:
	if node.has_meta(meta_key):
		return node
	for child in node.get_children():
		var found := _find_first_node_with_meta(child, meta_key)
		if found != null:
			return found
	return null


func _count_tile_map_layers(node: Node) -> int:
	var count := 0
	if node is TileMapLayer:
		count += 1
	for child in node.get_children():
		count += _count_tile_map_layers(child)
	return count


func _sanitize_filename(value: String) -> String:
	return value.replace("/", "-").replace("\\", "-").replace(":", "").replace("*", "").replace("?", "").replace("\"", "").replace("<", "").replace(">", "").replace("|", "")


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


func _fail(message: String) -> void:
	push_error(message)
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All real-pack validation checks passed.")
		quit(0)
	else:
		print("Validation failures: %d" % _failures.size())
		for failure in _failures:
			print(" - %s" % failure)
		quit(1)
