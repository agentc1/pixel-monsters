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
	var sample_scene: Dictionary = expected.get("sample_scene", {})

	_validate_tilesets(output_root)
	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_preview_map.tscn"), "basic_preview_map", true)
	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_prefab_catalog.tscn"), "basic_prefab_catalog", false)
	_validate_runtime_demo_scene(output_root.path_join("scenes/helpers/basic_runtime_stairs_demo.tscn"))
	_validate_imported_scene(output_root, expected, sample_scene)
	_validate_imported_scene_preview(output_root, sample_scene)
	_validate_bush_prefab(output_root, str(sample_prefabs.get("bush", "")), expected)
	_validate_lantern_prefab(output_root, str(sample_prefabs.get("lantern", "")), expected)
	_validate_stairs_prefab(output_root, str(sample_prefabs.get("stairs", "")), str(sample_prefabs.get("lantern", "")))
	_validate_altar_prefab(output_root, str(sample_prefabs.get("altar", "")))
	_validate_rune_prefab(output_root, str(sample_prefabs.get("rune", "")))
	_validate_edge_prefab(output_root, str(sample_prefabs.get("edge", "")), expected)
	_validate_polygon_prefab(output_root, str(sample_prefabs.get("polygon_static", "")), true)
	_validate_runtime_rigidbody_prefab(output_root, str(sample_prefabs.get("polygon_body", "")), expected.get("rigidbody_polygon_physics", {}), true)
	_validate_polygon_prefab(output_root, str(sample_prefabs.get("polygon_invalid", "")), false)
	_validate_runtime_rigidbody_prefab(output_root, str(sample_prefabs.get("rigidbody_box", "")), expected.get("rigidbody_box_physics", {}), false)
	_validate_unsupported_rigidbody_prefab(output_root, str(sample_prefabs.get("rigidbody_unsupported", "")))
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
		output_root.path_join("tilesets/basic_shadow_tileset.tres"),
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


func _validate_imported_scene(output_root: String, expected: Dictionary, sample_scene: Dictionary) -> void:
	var scene_path := output_root.path_join("scenes/unity/%s.tscn" % str(sample_scene.get("imported", "SC Demo")))
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Imported SC Demo scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Imported SC Demo scene instantiates")
	if instance == null:
		return
	_assert_eq(instance.name, str(sample_scene.get("imported", "SC Demo")), "Imported SC Demo root name")
	var tilemaps_root := instance.get_node_or_null("Tilemaps")
	var prefabs_root := instance.get_node_or_null("Prefabs")
	var markers_root := instance.get_node_or_null("Markers")
	_assert_true(tilemaps_root is Node2D, "Imported SC Demo includes Tilemaps root")
	_assert_true(prefabs_root is Node2D, "Imported SC Demo includes Prefabs root")
	_assert_true(markers_root is Node2D, "Imported SC Demo includes Markers root")
	_assert_eq(_count_tile_map_layers(instance), int(expected.get("scene_tile_layers", -1)), "Imported SC Demo tile layer count")
	var layer_names: Array = sample_scene.get("tile_layers", [])
	for layer_name_variant in layer_names:
		var layer_name := str(layer_name_variant)
		_assert_true(instance.get_node_or_null("Tilemaps/%s" % layer_name) is TileMapLayer, "Imported SC Demo keeps TileMapLayer: %s" % layer_name)
	var grass_layer := instance.get_node_or_null("Tilemaps/%s" % str(layer_names[0] if layer_names.size() > 0 else ""))
	if grass_layer is TileMapLayer:
		var grass_tileset: TileSet = (grass_layer as TileMapLayer).tile_set
		_assert_true(grass_tileset != null and str(grass_tileset.resource_path).ends_with("basic_grass_tileset.tres"), "Imported SC Demo grass layer uses grass TileSet")
		_assert_eq(_used_tile_cell_count(grass_layer), 2, "Imported SC Demo grass layer imports direct and tile-asset cells")
	var shadow_layer := instance.get_node_or_null("Tilemaps/%s" % str(layer_names[1] if layer_names.size() > 1 else ""))
	if shadow_layer is TileMapLayer:
		var shadow_tileset: TileSet = (shadow_layer as TileMapLayer).tile_set
		_assert_true(shadow_tileset != null and str(shadow_tileset.resource_path).ends_with("basic_shadow_tileset.tres"), "Imported SC Demo shadow layer uses shadow TileSet")
	var player_instance := instance.find_child(str(sample_scene.get("player_instance", "PF Player")), true, false)
	_assert_true(player_instance != null, "Imported SC Demo includes placed player prefab instance")
	if player_instance != null:
		var player_sprite := player_instance.find_child("PF Player Sprite", true, false)
		_assert_true(player_sprite is Sprite2D, "Imported SC Demo keeps player sprite node")
		if player_sprite is Sprite2D:
			_assert_eq((player_sprite as Sprite2D).flip_h, true, "Imported SC Demo applies prefab instance flip override")
	var camera_marker := instance.get_node_or_null("Markers/Main Camera Marker")
	_assert_true(camera_marker is Node2D, "Imported SC Demo includes camera marker")
	instance.free()


func _validate_imported_scene_preview(output_root: String, sample_scene: Dictionary) -> void:
	var scene_name := str(sample_scene.get("imported", "SC Demo"))
	var preview_name := "%s_preview" % scene_name.to_lower().replace(" ", "_")
	var scene_path := output_root.path_join("scenes/helpers/%s.tscn" % preview_name)
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Imported SC Demo preview scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Imported SC Demo preview scene instantiates")
	if instance == null:
		return
	_assert_eq(instance.name, preview_name, "Imported SC Demo preview root name")
	_assert_true(instance.get_node_or_null("SceneInstance") is Node2D, "Imported SC Demo preview includes SceneInstance host")
	_assert_true(instance.get_node_or_null("PreviewCamera2D") is Camera2D, "Imported SC Demo preview includes PreviewCamera2D")
	_assert_true(_script_path(instance).ends_with("cainos_imported_scene_preview.gd"), "Imported SC Demo preview uses preview runtime script")
	_assert_true(str(instance.get("target_scene_path")).ends_with("scenes/unity/%s.tscn" % scene_name), "Imported SC Demo preview targets raw imported scene")
	_assert_eq(instance.get("preview_window_size"), Vector2i(1200, 1200), "Imported SC Demo preview window size")
	instance.free()


func _validate_runtime_demo_scene(scene_path: String) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Runtime stairs demo scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Runtime stairs demo scene instantiates: %s" % scene_path)
	if instance == null:
		return
	_assert_eq(instance.name, "basic_runtime_stairs_demo", "Runtime stairs demo root name")
	var controller := instance.get_node_or_null("DemoController")
	var player := instance.get_node_or_null("PF Player")
	var south_stairs := instance.get_node_or_null("PF Struct - Stairs S 01 L")
	var south_trigger := instance.get_node_or_null("PF Struct - Stairs S 01 L/Stairs Layer Trigger")
	if south_trigger == null and south_stairs != null and _script_path(south_stairs).ends_with("cainos_stairs_trigger_2d.gd"):
		south_trigger = south_stairs
	var east_lower := instance.get_node_or_null("PF Struct - Stairs E 01/Stairs L/Stairs L Sprite")
	var east_upper := instance.get_node_or_null("PF Struct - Stairs E 01/Stairs U/Stairs U Sprite")
	_assert_true(controller != null, "Runtime stairs demo includes DemoController")
	_assert_true(player != null, "Runtime stairs demo includes PF Player")
	_assert_true(south_trigger != null, "Runtime stairs demo includes reachable south stairs trigger")
	if east_lower != null or east_upper != null:
		_assert_true(east_lower is Sprite2D, "Runtime stairs demo includes east lower stratum sprite")
		_assert_true(east_upper is Sprite2D, "Runtime stairs demo includes east upper stratum sprite")
	if controller != null and player is Node2D and south_trigger is Node2D and south_stairs is Node2D:
		var movement_bounds: Rect2 = controller.get("movement_bounds")
		_assert_true(movement_bounds.has_point((player as Node2D).position), "Runtime stairs demo keeps player spawn inside movement bounds")
		var south_trigger_position := (south_stairs as Node2D).position + (south_trigger as Node2D).position if south_trigger != south_stairs else (south_stairs as Node2D).position
		_assert_true(movement_bounds.has_point(south_trigger_position), "Runtime stairs demo keeps south stairs trigger inside movement bounds")
	if east_lower is Sprite2D and east_upper is Sprite2D:
		_assert_true((east_lower as Sprite2D).z_index >= 0, "Runtime stairs demo keeps east lower stratum above floor layers")
		_assert_true((east_lower as Sprite2D).z_index < (east_upper as Sprite2D).z_index, "Runtime stairs demo keeps east lower stratum below east upper stratum")
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
	var body_sprite := _find_first_sprite(root)
	var shadow_node := root.find_child("Shadow", true, false)
	if shadow_node != null:
		var shadow_sprite := _find_first_sprite(shadow_node)
		if body_sprite != null and shadow_sprite != null:
			_assert_true(shadow_sprite.z_index < body_sprite.z_index, "Lantern shadow renders behind lantern body")
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


func _validate_stairs_prefab(output_root: String, prefab_name: String, lantern_prefab_name: String) -> void:
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
	_assert_true(_script_path(trigger_node).ends_with("cainos_stairs_trigger_2d.gd"), "Stairs behavior node uses runtime stairs script")
	_assert_true(_count_nodes_with_meta_value(root, "cainos_visual_stratum", "upper") > 0, "Stairs prefab assigns upper visual strata")
	var trigger_position := Vector2.ZERO
	if trigger_node is Node2D:
		trigger_position = (trigger_node as Node2D).global_position
	var player_root := _instantiate_prefab(output_root, "player", "PF Player")
	if player_root != null:
		var player_helper := _find_runtime_actor_helper(player_root)
		_assert_true(player_helper != null, "Player prefab includes runtime actor helper for stairs")
		var player_base_z := _first_sprite_base_z(player_root)
		player_root.position = trigger_position + Vector2(0, 16)
		trigger_node.call("apply_enter_for_actor", player_root)
		_assert_eq(str(player_root.get_meta("cainos_runtime_layer_name", "")), "Layer 2", "Stairs runtime enter promotes helper-backed actor to Layer 2")
		_assert_eq(_first_sprite_z(player_root), player_base_z + 100, "Stairs runtime enter raises helper-backed actor sprite z")
		player_root.position = trigger_position + Vector2(0, 16)
		trigger_node.call("apply_exit_for_actor", player_root)
		_assert_eq(str(player_root.get_meta("cainos_runtime_layer_name", "")), "Layer 1", "Stairs runtime exit restores helper-backed actor to Layer 1")
		_assert_eq(_first_sprite_z(player_root), player_base_z, "Stairs runtime exit restores helper-backed actor sprite z")
		player_root.free()
	var lantern_root := _instantiate_prefab(output_root, "props", lantern_prefab_name)
	if lantern_root != null:
		_assert_true(_find_runtime_actor_helper(lantern_root) == null, "Lantern prefab stays on direct-fallback path without runtime actor helper")
		var lantern_base_z := _first_sprite_base_z(lantern_root)
		lantern_root.position = trigger_position + Vector2(0, 16)
		trigger_node.call("apply_enter_for_actor", lantern_root)
		_assert_eq(_first_sprite_z(lantern_root), lantern_base_z + 100, "Stairs runtime enter raises direct-fallback actor sprite z")
		lantern_root.position = trigger_position + Vector2(0, 16)
		trigger_node.call("apply_exit_for_actor", lantern_root)
		_assert_eq(_first_sprite_z(lantern_root), lantern_base_z, "Stairs runtime exit restores direct-fallback actor sprite z")
		lantern_root.free()
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


func _validate_polygon_prefab(output_root: String, prefab_name: String, expect_polygon: bool) -> void:
	var root := _instantiate_prefab(output_root, "props", prefab_name)
	if root == null:
		return
	var polygon_count := _count_collision_polygons(root)
	if expect_polygon:
		_assert_true(polygon_count > 0, "Polygon prefab imports CollisionPolygon2D: %s" % prefab_name)
	else:
		_assert_eq(polygon_count, 0, "Invalid polygon prefab defers CollisionPolygon2D: %s" % prefab_name)
	root.free()


func _validate_runtime_rigidbody_prefab(output_root: String, prefab_name: String, expected_details: Dictionary, expect_polygon: bool) -> void:
	var root := _instantiate_prefab(output_root, "props", prefab_name)
	if root == null:
		return
	_assert_true(root is RigidBody2D, "Runtime rigidbody prefab uses RigidBody2D root: %s" % prefab_name)
	_assert_true(_find_runtime_actor_helper(root) != null, "Runtime rigidbody prefab includes runtime actor helper: %s" % prefab_name)
	if root is RigidBody2D:
		_assert_float_close(float(root.get("mass")), float(expected_details.get("mass", -1.0)), "Runtime rigidbody mass: %s" % prefab_name)
		_assert_float_close(float(root.get("linear_damp")), float(expected_details.get("linear_damp", -1.0)), "Runtime rigidbody linear damp: %s" % prefab_name)
		_assert_float_close(float(root.get("angular_damp")), float(expected_details.get("angular_damp", -1.0)), "Runtime rigidbody angular damp: %s" % prefab_name)
		_assert_float_close(float(root.get("gravity_scale")), float(expected_details.get("gravity_scale", -1.0)), "Runtime rigidbody gravity scale: %s" % prefab_name)
		_assert_eq(bool(root.get("lock_rotation")), bool(expected_details.get("freeze_rotation", false)), "Runtime rigidbody freeze rotation: %s" % prefab_name)
		if expect_polygon:
			_assert_true(_count_collision_polygons(root) > 0, "Runtime rigidbody keeps CollisionPolygon2D: %s" % prefab_name)
		else:
			_assert_true(_count_collision_shapes(root) > 0, "Runtime rigidbody keeps CollisionShape2D: %s" % prefab_name)
	root.free()


func _validate_unsupported_rigidbody_prefab(output_root: String, prefab_name: String) -> void:
	var root := _instantiate_prefab(output_root, "props", prefab_name)
	if root == null:
		return
	_assert_true(not (root is RigidBody2D), "Unsupported rigidbody prefab remains non-RigidBody2D: %s" % prefab_name)
	var body := root.find_child("BoxCollider_0", true, false)
	_assert_true(body is StaticBody2D, "Unsupported rigidbody prefab keeps static collision fallback: %s" % prefab_name)
	root.free()


func _validate_player_prefab(output_root: String, prefab_name: String) -> void:
	var root := _instantiate_prefab(output_root, "player", prefab_name)
	if root == null:
		return
	var sprite := _find_first_sprite(root)
	_assert_true(sprite != null, "Player prefab includes a Sprite2D descendant")
	if sprite != null:
		_assert_rect2_close(sprite.region_rect, Rect2(0.0, 8.0, 24.0, 32.0), "Player prefab uses top-origin converted region_rect")
		_assert_true(_sprite_region_has_visible_pixels(sprite), "Player prefab region samples visible texture pixels")
	var shadow_node := root.find_child("Shadow", true, false)
	if shadow_node != null:
		var shadow_sprite := _find_first_sprite(shadow_node)
		if sprite != null and shadow_sprite != null:
			_assert_true(shadow_sprite.z_index < sprite.z_index, "Player shadow renders behind player body")
	var player_hints := _behavior_hints_for(root, "top_down_character_controller")
	_assert_true(not player_hints.is_empty(), "Player prefab exposes controller behavior hint")
	_assert_true(_find_runtime_actor_helper(root) != null, "Player prefab includes runtime actor helper")
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


func _count_collision_polygons(node: Node) -> int:
	var count := 0
	if node is CollisionPolygon2D:
		count += 1
	for child in node.get_children():
		count += _count_collision_polygons(child)
	return count


func _count_collision_shapes(node: Node) -> int:
	var count := 0
	if node is CollisionShape2D:
		count += 1
	for child in node.get_children():
		count += _count_collision_shapes(child)
	return count


func _find_first_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node
	for child in node.get_children():
		var sprite := _find_first_sprite(child)
		if sprite != null:
			return sprite
	return null


func _sprite_region_has_visible_pixels(sprite: Sprite2D) -> bool:
	if sprite.texture == null:
		return false
	var texture_path := str(sprite.texture.resource_path)
	if texture_path.is_empty():
		return false
	var image := Image.load_from_file(ProjectSettings.globalize_path(texture_path))
	if image.is_empty():
		return false
	var rect := sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, Vector2(image.get_width(), image.get_height()))
	var start_x := maxi(0, int(floor(rect.position.x)))
	var start_y := maxi(0, int(floor(rect.position.y)))
	var end_x := mini(image.get_width(), int(ceil(rect.end.x)))
	var end_y := mini(image.get_height(), int(ceil(rect.end.y)))
	for y in range(start_y, end_y):
		for x in range(start_x, end_x):
			if image.get_pixel(x, y).a > 0.0:
				return true
	return false


func _find_runtime_actor_helper(node: Node) -> Node:
	if _script_path(node).ends_with("cainos_runtime_actor_2d.gd"):
		return node
	for child in node.get_children():
		var found := _find_runtime_actor_helper(child)
		if found != null:
			return found
	return null


func _script_path(node: Node) -> String:
	var script = node.get_script()
	if script == null:
		return ""
	return str(script.resource_path)


func _count_nodes_with_meta_value(node: Node, meta_key: String, expected_value) -> int:
	var count := 0
	if node.has_meta(meta_key) and node.get_meta(meta_key) == expected_value:
		count += 1
	for child in node.get_children():
		count += _count_nodes_with_meta_value(child, meta_key, expected_value)
	return count


func _first_sprite_base_z(node: Node) -> int:
	var sprite := _find_first_sprite(node)
	if sprite == null:
		return 0
	return int(sprite.get_meta("cainos_base_z_index"))


func _first_sprite_z(node: Node) -> int:
	var sprite := _find_first_sprite(node)
	if sprite == null:
		return 0
	return int(sprite.z_index)


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


func _used_tile_cell_count(node: Node) -> int:
	if node is TileMapLayer:
		return (node as TileMapLayer).get_used_cells().size()
	return 0


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


func _assert_float_close(actual: float, expected: float, message: String, tolerance: float = 0.0001) -> void:
	if abs(actual - expected) <= tolerance:
		print("PASS: %s" % message)
	else:
		_fail("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])


func _assert_vector2_close(actual: Vector2, expected: Vector2, message: String, epsilon := 0.01) -> void:
	if actual.distance_to(expected) <= epsilon:
		print("PASS: %s" % message)
	else:
		_fail("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])


func _assert_rect2_close(actual: Rect2, expected: Rect2, message: String, epsilon := 0.01) -> void:
	_assert_vector2_close(actual.position, expected.position, "%s position" % message, epsilon)
	_assert_vector2_close(actual.size, expected.size, "%s size" % message, epsilon)


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
