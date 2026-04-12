extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var output_root := str(args.get("output_root", "res://cainos_imports/basic_real_acceptance"))

	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_preview_map.tscn"), "basic_preview_map", true)
	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_prefab_catalog.tscn"), "basic_prefab_catalog", false)
	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_runtime_stairs_demo.tscn"), "basic_runtime_stairs_demo", false)
	_validate_runtime_demo_scene(output_root.path_join("scenes/helpers/basic_runtime_stairs_demo.tscn"))
	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_runtime_altar_runes_demo.tscn"), "basic_runtime_altar_runes_demo", false)
	_validate_altar_runes_demo_scene(output_root.path_join("scenes/helpers/basic_runtime_altar_runes_demo.tscn"))
	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_runtime_player_demo.tscn"), "basic_runtime_player_demo", false)
	_validate_player_demo_scene(output_root.path_join("scenes/helpers/basic_runtime_player_demo.tscn"))
	_validate_imported_unity_scene(output_root.path_join("scenes/unity/SC Demo.tscn"))
	_validate_imported_unity_scene_preview(output_root.path_join("scenes/helpers/sc_demo_preview.tscn"))
	_validate_imported_unity_scene_runtime(output_root.path_join("scenes/unity/SC Demo Runtime.tscn"))
	_validate_imported_all_props_scene(output_root.path_join("scenes/unity/SC All Props.tscn"))
	_validate_imported_all_props_scene_preview(output_root.path_join("scenes/helpers/sc_all_props_preview.tscn"))
	_validate_report_files(output_root)
	_validate_bush_prefab(output_root)
	_validate_lantern_prefab(output_root)
	_validate_sorting_layered_prefabs(output_root)
	_validate_polygon_prefabs(output_root)
	_validate_runtime_rigidbody_prefabs(output_root)
	_validate_stairs_prefab(output_root)
	_validate_east_west_stairs_prefabs(output_root)
	_validate_altar_prefab(output_root)
	_validate_rune_prefab(output_root)
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


func _validate_imported_unity_scene(scene_path: String) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Imported SC Demo scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Imported SC Demo scene instantiates")
	if instance == null:
		return
	_assert_eq(instance.name, "SC Demo", "Imported SC Demo root name")
	_assert_eq(_count_tile_map_layers(instance), 10, "Imported SC Demo tile layer count")
	for layer_name in [
		"Layer 1 - Grass",
		"Layer 1 - Stone Ground",
		"Layer 1 - Wall",
		"Layer 1 - Wall Shadow",
		"Layer 2 - Grass",
		"Layer 2 - Wall",
		"Layer 2 - Wall Shadow",
		"Layer 3 - Grass",
		"Layer 3 - Wall",
	]:
		_assert_true(instance.get_node_or_null("Tilemaps/%s" % layer_name) is TileMapLayer, "Imported SC Demo keeps TileMapLayer: %s" % layer_name)
	var expected_populated_layers := [
		"Layer 1 - Grass",
		"Layer 1 - Stone Ground",
		"Layer 1 - Wall",
		"Layer 1 - Wall Shadow",
		"Layer 2 - Grass",
		"Layer 2 - Wall",
		"Layer 2 - Wall Shadow",
		"Layer 3 - Grass",
		"Layer 3 - Wall",
	]
	for layer_name_variant in expected_populated_layers:
		var layer_name := str(layer_name_variant)
		var layer := instance.get_node_or_null("Tilemaps/%s" % layer_name)
		if layer is TileMapLayer:
			_assert_true(_used_tile_cell_count(layer) > 0, "Imported SC Demo layer has visible tile content: %s" % layer_name)
			var warning_counts: Dictionary = layer.get_meta("unity_warning_counts", {})
			_assert_eq(int(warning_counts.get("unresolved_sprite_reference", -1)), 0, "Imported SC Demo layer resolves tile sprite refs: %s" % layer_name)
	var layer1_grass := instance.get_node_or_null("Tilemaps/Layer 1 - Grass")
	var layer1_wall := instance.get_node_or_null("Tilemaps/Layer 1 - Wall")
	var layer2_wall := instance.get_node_or_null("Tilemaps/Layer 2 - Wall")
	var layer3_wall := instance.get_node_or_null("Tilemaps/Layer 3 - Wall")
	if layer1_grass is TileMapLayer and layer1_wall is TileMapLayer:
		_assert_true((layer1_wall as TileMapLayer).z_index >= (layer1_grass as TileMapLayer).z_index, "Imported SC Demo keeps Layer 1 wall at or above grass z")
	if layer1_wall is TileMapLayer and layer2_wall is TileMapLayer:
		_assert_true((layer2_wall as TileMapLayer).z_index > (layer1_wall as TileMapLayer).z_index, "Imported SC Demo Layer 2 wall renders above Layer 1 wall")
	if layer2_wall is TileMapLayer and layer3_wall is TileMapLayer:
		_assert_true((layer3_wall as TileMapLayer).z_index > (layer2_wall as TileMapLayer).z_index, "Imported SC Demo Layer 3 wall renders above Layer 2 wall")
	var player_instance := instance.find_child("PF Player", true, false)
	_assert_true(player_instance != null, "Imported SC Demo includes placed PF Player instance")
	_assert_true(instance.find_child("PF Props - Altar 01", true, false) != null, "Imported SC Demo includes placed altar instance")
	_assert_true(instance.find_child("PF Struct - Stairs S 01 L", true, false) != null, "Imported SC Demo includes placed south stairs instance")
	var camera_marker := instance.get_node_or_null("Markers/Main Camera Marker")
	_assert_true(camera_marker is Node2D, "Imported SC Demo includes main camera marker")
	instance.free()


func _validate_imported_unity_scene_preview(scene_path: String) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Imported SC Demo preview scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Imported SC Demo preview scene instantiates")
	if instance == null:
		return
	_assert_eq(instance.name, "sc_demo_preview", "Imported SC Demo preview root name")
	_assert_true(instance.get_node_or_null("SceneInstance") is Node2D, "Imported SC Demo preview includes SceneInstance host")
	_assert_true(instance.get_node_or_null("PreviewCamera2D") is Camera2D, "Imported SC Demo preview includes PreviewCamera2D")
	_assert_true(_script_path(instance).ends_with("cainos_imported_scene_preview.gd"), "Imported SC Demo preview uses preview runtime script")
	_assert_true(str(instance.get("target_scene_path")).ends_with("scenes/unity/SC Demo.tscn"), "Imported SC Demo preview targets raw imported scene")
	_assert_eq(instance.get("preview_window_size"), Vector2i(1200, 1200), "Imported SC Demo preview window size")
	instance.free()


func _validate_imported_unity_scene_runtime(scene_path: String) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Imported SC Demo runtime scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Imported SC Demo runtime scene instantiates")
	if instance == null:
		return
	_assert_eq(instance.name, "SC Demo Runtime", "Imported SC Demo runtime root name")
	var scene_instance := instance.get_node_or_null("SceneInstance")
	var scene_collision := instance.get_node_or_null("SceneCollision")
	var runtime_player := instance.get_node_or_null("RuntimePlayer")
	var navigation_overlay := instance.get_node_or_null("NavigationOverlay")
	var command_legend := instance.get_node_or_null("CommandLegend")
	var command_legend_hud := instance.get_node_or_null("CommandLegendHUD")
	_assert_true(scene_instance is Node2D, "Imported SC Demo runtime includes SceneInstance")
	_assert_true(scene_collision is Node2D, "Imported SC Demo runtime includes SceneCollision")
	_assert_true(runtime_player is CharacterBody2D, "Imported SC Demo runtime includes CharacterBody2D RuntimePlayer")
	_assert_true(navigation_overlay is Node2D, "Imported SC Demo runtime includes grid navigation overlay")
	_assert_true(command_legend is Node2D, "Imported SC Demo runtime includes command legend below the map")
	_assert_true(command_legend_hud is CanvasLayer, "Imported SC Demo runtime includes visible command legend HUD")
	if command_legend is Node2D:
		_assert_true(bool(command_legend.get_meta("cainos_runtime_command_legend", false)), "Imported SC Demo runtime command legend is tagged")
		var legend_label := (command_legend as Node).get_node_or_null("Instructions")
		_assert_true(legend_label is Label, "Imported SC Demo runtime command legend includes instructions")
		if legend_label is Label:
			var legend_text := (legend_label as Label).text
			_assert_true(legend_text.contains("WASD"), "Imported SC Demo runtime command legend documents movement")
			_assert_true(legend_text.contains("1 / 2 / 3"), "Imported SC Demo runtime command legend documents overlay toggles")
			_assert_true(legend_text.contains("N toggles editing"), "Imported SC Demo runtime command legend documents edit mode")
			_assert_true(legend_text.contains("WASD / arrow keys"), "Imported SC Demo runtime command legend documents cursor movement")
			_assert_true(legend_text.contains("Insert force-navigable"), "Imported SC Demo runtime command legend documents Insert force-navigable override")
			_assert_true(legend_text.contains("Delete force-blocked"), "Imported SC Demo runtime command legend documents Delete force-blocked override")
			_assert_true(legend_text.contains("Edits affect only the active layer"), "Imported SC Demo runtime command legend documents active-layer-only overrides")
			_assert_true(legend_text.contains("Switch layers with Q / E"), "Imported SC Demo runtime command legend documents repeated stacked-cell edits")
			_assert_true(legend_text.contains("V saves overrides"), "Imported SC Demo runtime command legend documents saving overrides")
	if command_legend_hud is CanvasLayer:
		_assert_true(bool(command_legend_hud.get_meta("cainos_runtime_command_legend_hud", false)), "Imported SC Demo runtime command legend HUD is tagged")
		var hud_label := (command_legend_hud as Node).get_node_or_null("Instructions")
		_assert_true(hud_label is Label, "Imported SC Demo runtime command legend HUD includes instructions")
		if hud_label is Label:
			_assert_true((hud_label as Label).text.contains("WASD"), "Imported SC Demo runtime command legend HUD documents movement")
	if navigation_overlay is Node2D:
		_assert_true(_script_path(navigation_overlay).ends_with("cainos_grid_navigation_overlay_2d.gd"), "Imported SC Demo runtime navigation overlay uses debug overlay script")
		_assert_true(navigation_overlay.get("navigation_bounds") is Rect2i, "Imported SC Demo runtime navigation overlay stores grid bounds")
		var overlay_navigation_map = navigation_overlay.get("navigation_map")
		_assert_true(overlay_navigation_map is Resource, "Imported SC Demo runtime navigation overlay references generated navigation map resource")
		if overlay_navigation_map is Resource:
			_assert_true(str((overlay_navigation_map as Resource).resource_path).ends_with("navigation/SC Demo_navigation_map.tres"), "Imported SC Demo runtime navigation overlay uses external navigation map resource")
		_assert_true((navigation_overlay as CanvasItem).visible, "Imported SC Demo runtime navigation overlay is visible by default")
	if scene_instance is Node:
		_assert_true(scene_instance.get_node_or_null("SC Demo") is Node2D, "Imported SC Demo runtime instances raw SC Demo scene")
		_assert_true(scene_instance.get_node_or_null("SC Demo/Prefabs/PF Player") == null, "Imported SC Demo runtime removes placeholder PF Player")
		if scene_collision is Node:
			var expected_collision_layers := {
				"Layer 1 - Wall Collision": 1,
				"Layer 2 - Wall Collision": 2,
				"Layer 3 - Wall Collision": 4,
			}
			for collision_name in expected_collision_layers.keys():
				var collision_body := scene_collision.get_node_or_null(str(collision_name))
				_assert_true(collision_body is StaticBody2D, "Imported SC Demo runtime includes collision body: %s" % collision_name)
				if collision_body is StaticBody2D:
					_assert_eq((collision_body as StaticBody2D).collision_layer, int(expected_collision_layers[collision_name]), "Imported SC Demo runtime collision body uses elevation physics bit: %s" % collision_name)
			_assert_true(_count_collision_shapes(scene_collision) + _count_collision_polygons(scene_collision) > 0, "Imported SC Demo runtime includes collision geometry")
		if runtime_player is CharacterBody2D:
			_assert_true(_script_path(runtime_player).ends_with("cainos_runtime_player_body_2d.gd"), "Imported SC Demo runtime uses runtime player body script")
			_assert_vector2_close((runtime_player as CharacterBody2D).position, Vector2(186.24, -73.92), "Imported SC Demo runtime player spawn position")
			_assert_eq(str(runtime_player.get("navigation_mode")), "grid_cardinal", "Imported SC Demo runtime enables grid-cardinal navigation")
			_assert_float_close(float(runtime_player.get("grid_cell_size")), 32.0, "Imported SC Demo runtime uses 32px grid cells")
			_assert_true(Array(runtime_player.get("grid_transition_edges")).size() > 0, "Imported SC Demo runtime includes grid transition edges")
			_assert_true(runtime_player.get("grid_navigation_bounds") is Rect2i, "Imported SC Demo runtime exposes grid navigation bounds")
			var navigation_map = runtime_player.get("navigation_map")
			_assert_true(navigation_map is Resource, "Imported SC Demo runtime player references generated navigation map resource")
			if navigation_map is Resource:
				_assert_true(str((navigation_map as Resource).resource_path).ends_with("navigation/SC Demo_navigation_map.tres"), "Imported SC Demo runtime player uses external navigation map resource")
				_assert_true(bool((navigation_map as Resource).call("is_cell_navigable", Vector2i(6, -2), "Layer 1")), "Imported SC Demo navigation map includes player spawn cell")
				var reachable_from_spawn: Dictionary = (navigation_map as Resource).call("reachable_cells_from", "Layer 1", Vector2i(6, -2), 20000)
				_assert_true(not _cell_array_has_cell(reachable_from_spawn.get("Layer 1", []), Vector2i(1, -15)), "Imported SC Demo navigation map keeps unreachable Layer 1 island cells outside spawn reachability")
			_assert_eq((runtime_player as CharacterBody2D).collision_layer, 9, "Imported SC Demo runtime player remains trigger-detectable on Layer 1")
			_assert_eq((runtime_player as CharacterBody2D).collision_mask, 1, "Imported SC Demo runtime player starts colliding with Layer 1 geometry")
			_assert_true(Dictionary(runtime_player.get("grid_blocked_cells_by_layer")).has("Layer 2"), "Imported SC Demo runtime exposes Layer 2 grid blockers")
			_assert_true(runtime_player.get_node_or_null("PF Player") is Node2D, "Imported SC Demo runtime keeps imported PF Player child")
			_assert_true(runtime_player.get_node_or_null("FollowCamera2D") is Camera2D, "Imported SC Demo runtime includes live follow camera")
			var player_root := runtime_player.get_node_or_null("PF Player")
			if player_root is Node:
				_assert_true(_script_path(player_root).ends_with("cainos_top_down_player_controller_2d.gd"), "Imported SC Demo runtime child player uses runtime controller")
				_assert_eq(str(player_root.get("movement_mode")), "external_body", "Imported SC Demo runtime child player uses external_body movement")
				var helper := player_root.get_node_or_null("CainosRuntimeActor2D")
				if helper != null and helper.has_method("apply_runtime_layer"):
					helper.call("apply_runtime_layer", "Layer 2", "Layer 2")
					_assert_eq((runtime_player as CharacterBody2D).collision_layer, 10, "Imported SC Demo runtime player remains trigger-detectable on Layer 2")
					_assert_eq((runtime_player as CharacterBody2D).collision_mask, 2, "Imported SC Demo runtime player switches to Layer 2 geometry with runtime layer")
			var wrapper_collision := _first_collision_shape(runtime_player)
			_assert_true(wrapper_collision != null, "Imported SC Demo runtime wrapper clones player collision shape")
		if scene_instance is Node:
			_assert_collision_layer_if_present(scene_instance, "SC Demo/Prefabs/Layer 1/Props/PF Struct - Gate 01/Collider T/BoxCollider_0", 2, "Gate 01 top collider is upper-elevation only")
			_assert_collision_layer_if_present(scene_instance, "SC Demo/Prefabs/Layer 1/Props/PF Struct - Gate 01/Collider L/BoxCollider_0", 1, "Gate 01 side collider stays lower-elevation")
			_assert_collision_layer_if_present(scene_instance, "SC Demo/Prefabs/Layer 1/Props/PF Struct - Gate 02/Collider T/BoxCollider_0", 2, "Gate 02 top collider is upper-elevation only")
			_assert_collision_layer_if_present(scene_instance, "SC Demo/Prefabs/Layer 1/Props/PF Struct - Stairs E 02/Collider Upper/PolygonCollider_0", 2, "East stairs upper collider is upper-elevation")
			_assert_collision_layer_if_present(scene_instance, "SC Demo/Prefabs/Layer 1/Props/PF Struct - Stairs E 02/Collider Lower/BoxCollider_0", 1, "East stairs lower collider stays lower-elevation")
		instance.free()


func _validate_imported_all_props_scene(scene_path: String) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Imported SC All Props scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Imported SC All Props scene instantiates")
	if instance == null:
		return
	_assert_eq(instance.name, "SC All Props", "Imported SC All Props root name")
	_assert_true(instance.get_node_or_null("Tilemaps") is Node2D, "Imported SC All Props includes Tilemaps")
	_assert_true(instance.get_node_or_null("Prefabs") is Node2D, "Imported SC All Props includes Prefabs")
	_assert_true(instance.get_node_or_null("Markers") is Node2D, "Imported SC All Props includes Markers")
	_assert_eq(_count_tile_map_layers(instance), 2, "Imported SC All Props tile layer count")
	for layer_name in ["Layer 1 - Grass", "Layer 1 - Wall"]:
		var layer := instance.get_node_or_null("Tilemaps/%s" % layer_name)
		_assert_true(layer is TileMapLayer, "Imported SC All Props keeps TileMapLayer: %s" % layer_name)
		if layer is TileMapLayer:
			_assert_true(_used_tile_cell_count(layer) > 0, "Imported SC All Props layer has visible tile content: %s" % layer_name)
	_assert_true(instance.get_node_or_null("Markers/Main Camera Marker") is Node2D, "Imported SC All Props includes main camera marker")
	var prefabs_root := instance.get_node_or_null("Prefabs")
	_assert_true(prefabs_root is Node, "Imported SC All Props includes Prefabs root node")
	if prefabs_root is Node:
		_assert_true(prefabs_root.get_child_count() > 0, "Imported SC All Props includes placed prefab instances")
	instance.free()


func _validate_imported_all_props_scene_preview(scene_path: String) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Imported SC All Props preview scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Imported SC All Props preview scene instantiates")
	if instance == null:
		return
	_assert_eq(instance.name, "sc_all_props_preview", "Imported SC All Props preview root name")
	_assert_true(instance.get_node_or_null("SceneInstance") is Node2D, "Imported SC All Props preview includes SceneInstance host")
	_assert_true(instance.get_node_or_null("PreviewCamera2D") is Camera2D, "Imported SC All Props preview includes PreviewCamera2D")
	_assert_true(_script_path(instance).ends_with("cainos_imported_scene_preview.gd"), "Imported SC All Props preview uses preview runtime script")
	_assert_true(str(instance.get("target_scene_path")).ends_with("scenes/unity/SC All Props.tscn"), "Imported SC All Props preview targets raw imported scene")
	_assert_eq(instance.get("preview_window_size"), Vector2i(1200, 1200), "Imported SC All Props preview window size")
	instance.free()


func _validate_bush_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "plants", "PF Plant - Bush 01")
	if root == null:
		return
	var body_sprite := _find_first_sprite(root)
	var shadow := root.find_child("Shadow", true, false)
	_assert_true(shadow is Node2D, "Bush prefab keeps Shadow child")
	if shadow is Node:
		var shadow_sprite := _find_first_sprite(shadow)
		if body_sprite != null and shadow_sprite != null:
			_assert_true(shadow_sprite.z_index < body_sprite.z_index, "Bush shadow renders behind bush body")
	root.free()


func _validate_lantern_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "props", "PF Props - Stone Lantern 01")
	if root == null:
		return
	var sprite := _find_sprite_by_name(root, "PF Props - Stone Lantern 01 Sprite")
	_assert_true(sprite != null, "Stone Lantern keeps primary sprite node")
	if sprite != null:
		_assert_rect2_close(sprite.region_rect, Rect2(453.0, 118.0, 22.0, 38.0), "Stone Lantern primary sprite region")
		_assert_true(_sprite_region_has_visible_pixels(sprite), "Stone Lantern primary sprite samples visible pixels")
	var shadow_sprite := _find_sprite_by_name(root, "Shadow Sprite")
	_assert_true(shadow_sprite != null, "Stone Lantern keeps shadow sprite node")
	if shadow_sprite != null:
		_assert_rect2_close(shadow_sprite.region_rect, Rect2(453.0, 129.0, 28.0, 26.0), "Stone Lantern shadow sprite region")
		_assert_true(_sprite_region_has_visible_pixels(shadow_sprite), "Stone Lantern shadow sprite samples visible pixels")
		_assert_eq(shadow_sprite.z_as_relative, false, "Stone Lantern shadow sprite uses absolute z")
		if sprite != null:
			_assert_true(shadow_sprite.z_index < sprite.z_index, "Stone Lantern shadow renders behind lantern body")
	var body := root.find_child("BoxCollider_0", true, false)
	_assert_true(body is StaticBody2D, "Stone Lantern keeps StaticBody2D box collider")
	if body is StaticBody2D:
		var shape_node := _first_collision_shape(body)
		_assert_true(shape_node != null, "Stone Lantern box collider has CollisionShape2D")
		if shape_node != null:
			_assert_true(shape_node.shape is RectangleShape2D, "Stone Lantern collider shape is RectangleShape2D")
	root.free()


func _validate_sorting_layered_prefabs(output_root: String) -> void:
	for spec in [
		{"family": "plants", "name": "PF Plant - Tree 01"},
		{"family": "plants", "name": "PF Plant - Tree 02"},
		{"family": "plants", "name": "PF Plant - Tree 03"},
		{"family": "struct", "name": "PF Struct - Gate 01"},
		{"family": "struct", "name": "PF Struct - Gate 02"},
	]:
		var root := _instantiate_prefab(output_root, str(spec.get("family", "")), str(spec.get("name", "")))
		if root == null:
			continue
		var layer1_sprites := _sprites_by_effective_layer(root, "Layer 1")
		var layer2_sprites := _sprites_by_effective_layer(root, "Layer 2")
		_assert_true(not layer1_sprites.is_empty(), "%s keeps Layer 1 visual sprites" % str(spec.get("name", "")))
		_assert_true(not layer2_sprites.is_empty(), "%s keeps Layer 2 visual sprites" % str(spec.get("name", "")))
		for sprite_variant in layer1_sprites + layer2_sprites:
			var sprite := sprite_variant as Sprite2D
			_assert_eq(sprite.z_as_relative, false, "%s sprite uses absolute z: %s" % [str(spec.get("name", "")), sprite.name])
			_assert_eq(int(sprite.get_meta("cainos_effective_z_index", -99999)), sprite.z_index, "%s sprite effective z metadata matches z_index: %s" % [str(spec.get("name", "")), sprite.name])
		for sprite_variant in layer2_sprites:
			var sprite := sprite_variant as Sprite2D
			_assert_eq(bool(sprite.get_meta("cainos_foreground_occluder", false)), true, "%s Layer 2 top sprite is tagged as foreground occluder: %s" % [str(spec.get("name", "")), sprite.name])
			_assert_eq(int(sprite.get_meta("cainos_foreground_occluder_offset", 0)), 50, "%s Layer 2 top sprite records foreground occluder offset: %s" % [str(spec.get("name", "")), sprite.name])
		if not layer1_sprites.is_empty() and not layer2_sprites.is_empty():
			_assert_true(_min_sprite_z(layer2_sprites) > _max_sprite_z(layer1_sprites), "%s Layer 2 visuals render above Layer 1 visuals" % str(spec.get("name", "")))
			_assert_true(_min_sprite_z(layer2_sprites) > 102, "%s Layer 2 foreground visuals occlude a Layer 2 runtime player" % str(spec.get("name", "")))
		root.free()


func _validate_polygon_prefabs(output_root: String) -> void:
	for prefab_name in [
		"PF Props - Statue 01",
		"PF Props - Stone 06",
		"PF Props - Stone 07",
		"PF Props - Well 01",
		"PF Props - Wooden Gate 01 Opened",
	]:
		_validate_polygon_prefab_collision(output_root, "props", prefab_name)
	_validate_polygon_prefab_collision(output_root, "struct", "PF Struct - Gate 02")
	for prefab_name in [
		"PF Props - Barrel 01",
		"PF Props - Pot 01",
		"PF Props - Pot 02",
		"PF Props - Pot 03",
	]:
		_validate_polygon_prefab_collision(output_root, "props", prefab_name)


func _validate_polygon_prefab_collision(output_root: String, family: String, prefab_name: String) -> void:
	var root := _instantiate_prefab(output_root, family, prefab_name)
	if root == null:
		return
	_assert_true(_count_collision_polygons(root) > 0, "%s imports CollisionPolygon2D" % prefab_name)
	root.free()


func _validate_runtime_rigidbody_prefabs(output_root: String) -> void:
	var expected_masses := {
		"PF Props - Barrel 01": 1.0,
		"PF Props - Crate 01": 10.0,
		"PF Props - Crate 02": 5.0,
		"PF Props - Pot 01": 1.0,
		"PF Props - Pot 02": 1.0,
		"PF Props - Pot 03": 1.0,
		"PF Props - Stone Cube 01": 30.0,
	}
	for prefab_name_variant in expected_masses.keys():
		var prefab_name := str(prefab_name_variant)
		var root := _instantiate_prefab(output_root, "props", prefab_name)
		if root == null:
			continue
		_assert_true(root is RigidBody2D, "%s uses RigidBody2D root" % prefab_name)
		_assert_true(_find_runtime_actor_helper(root) != null, "%s includes runtime actor helper" % prefab_name)
		if root is RigidBody2D:
			_assert_float_close(float(root.get("mass")), float(expected_masses[prefab_name]), "%s mass" % prefab_name)
			_assert_float_close(float(root.get("linear_damp")), 10.0, "%s linear damp" % prefab_name)
			_assert_float_close(float(root.get("angular_damp")), 0.05, "%s angular damp" % prefab_name)
			_assert_float_close(float(root.get("gravity_scale")), 0.0, "%s gravity scale" % prefab_name)
			_assert_eq(bool(root.get("lock_rotation")), true, "%s freeze rotation" % prefab_name)
			var collision_count := _count_collision_shapes(root) + _count_collision_polygons(root)
			_assert_true(collision_count > 0, "%s keeps imported collision nodes under rigidbody root" % prefab_name)
		root.free()


func _validate_stairs_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "struct", "PF Struct - Stairs S 01 L")
	if root == null:
		return
	for sprite_name in ["M Sprite", "L Sprite", "R Sprite"]:
		var stair_sprite := _find_sprite_by_name(root, sprite_name)
		_assert_true(stair_sprite != null, "Stairs prefab keeps sprite node: %s" % sprite_name)
		if stair_sprite != null:
			_assert_eq(int(stair_sprite.region_rect.position.y), 32, "Stairs sprite normalized top-origin y: %s" % sprite_name)
			_assert_true(_sprite_region_has_visible_pixels(stair_sprite), "Stairs sprite samples visible pixels: %s" % sprite_name)
	_assert_true(not _behavior_hints_for(root, "stairs_layer_trigger").is_empty(), "Stairs prefab exposes stairs_layer_trigger behavior hint")
	var behaviour_node := root.find_child("Stairs Layer Trigger", true, false)
	_assert_true(behaviour_node != null, "Stairs prefab keeps trigger helper node")
	if behaviour_node != null:
		_assert_true(behaviour_node.has_meta("unity_mono_behaviours"), "Stairs prefab preserves deferred MonoBehaviour metadata")
		_assert_true(not _behavior_hints_for(behaviour_node, "stairs_layer_trigger").is_empty(), "Stairs trigger node keeps local behavior hint")
		_assert_true(_script_path(behaviour_node).ends_with("cainos_stairs_trigger_2d.gd"), "Stairs trigger node uses runtime stairs script")
		_assert_true(_count_nodes_with_meta_value(root, "cainos_visual_stratum", "lower") > 0, "South stairs assign lower visual strata")
		_assert_eq(_count_nodes_with_meta_value(root, "cainos_visual_stratum", "upper"), 0, "South stairs do not foreground-occlude the lower approach")
		var trigger_position := Vector2.ZERO
		if behaviour_node is Node2D:
			trigger_position = (behaviour_node as Node2D).global_position
		var player_root := _instantiate_prefab(output_root, "player", "PF Player")
		if player_root != null:
			_assert_true(_find_runtime_actor_helper(player_root) != null, "PF Player includes runtime actor helper")
			var base_z := _first_sprite_base_z(player_root)
			player_root.position = trigger_position + Vector2(0, 16)
			behaviour_node.call("apply_enter_for_actor", player_root)
			_assert_eq(str(player_root.get_meta("cainos_runtime_layer_name", "")), "Layer 2", "South stairs runtime enter promotes PF Player to Layer 2")
			_assert_eq(_first_sprite_z(player_root), base_z + 100, "South stairs runtime enter raises PF Player z")
			player_root.position = trigger_position + Vector2(0, -16)
			behaviour_node.call("apply_exit_for_actor", player_root)
			_assert_eq(str(player_root.get_meta("cainos_runtime_layer_name", "")), "Layer 2", "South stairs runtime exit keeps PF Player on Layer 2 after crossing")
			player_root.position = trigger_position + Vector2(0, 16)
			behaviour_node.call("apply_exit_for_actor", player_root)
			_assert_eq(str(player_root.get_meta("cainos_runtime_layer_name", "")), "Layer 1", "South stairs runtime exit restores PF Player to Layer 1 from lower side")
			_assert_eq(_first_sprite_z(player_root), base_z, "South stairs runtime exit restores PF Player z from lower side")
			player_root.position = trigger_position + Vector2(0, -16)
			behaviour_node.call("apply_enter_for_actor", player_root)
			_assert_eq(str(player_root.get_meta("cainos_runtime_layer_name", "")), "Layer 1", "South stairs runtime enter keeps PF Player on Layer 1 from upper side")
			behaviour_node.call("apply_exit_for_actor", player_root)
			_assert_eq(str(player_root.get_meta("cainos_runtime_layer_name", "")), "Layer 1", "South stairs runtime exit keeps PF Player on Layer 1 from upper side")
			player_root.free()
	root.free()


func _validate_east_west_stairs_prefabs(output_root: String) -> void:
	for prefab_name in [
		"PF Struct - Stairs E 01",
		"PF Struct - Stairs E 02",
		"PF Struct - Stairs W 01",
		"PF Struct - Stairs W 02",
	]:
		var root := _instantiate_prefab(output_root, "struct", prefab_name)
		if root == null:
			continue
		_assert_true(not _behavior_hints_for(root, "stairs_layer_trigger").is_empty(), "%s exposes stairs_layer_trigger behavior hint" % prefab_name)
		var behaviour_node: Node = root.find_child("Stairs Layer Trigger", true, false)
		_assert_true(behaviour_node != null, "%s keeps trigger helper node" % prefab_name)
		if behaviour_node != null:
			_assert_true(behaviour_node.has_meta("unity_mono_behaviours"), "%s preserves deferred MonoBehaviour metadata" % prefab_name)
			_assert_true(not _behavior_hints_for(behaviour_node, "stairs_layer_trigger").is_empty(), "%s trigger node keeps local behavior hint" % prefab_name)
			_assert_true(_script_path(behaviour_node).ends_with("cainos_stairs_trigger_2d.gd"), "%s uses runtime stairs script" % prefab_name)
		_assert_true(_find_first_sprite(root) != null, "%s includes visible sprite content" % prefab_name)
		_assert_true(_count_collision_shapes(root) + _count_collision_polygons(root) > 0, "%s keeps imported collision nodes" % prefab_name)
		_assert_true(_count_nodes_with_meta_value(root, "cainos_visual_stratum", "lower") > 0, "%s assigns lower visual strata" % prefab_name)
		_assert_true(_count_nodes_with_meta_value(root, "cainos_visual_stratum", "upper") > 0, "%s assigns upper visual strata" % prefab_name)
		var lower_sprite := _find_sprite_by_name(root, "Stairs L Sprite")
		var upper_sprite := _find_sprite_by_name(root, "Stairs U Sprite")
		_assert_true(lower_sprite != null, "%s keeps lower stratum sprite" % prefab_name)
		_assert_true(upper_sprite != null, "%s keeps upper stratum sprite" % prefab_name)
		if lower_sprite != null and upper_sprite != null:
			_assert_true(lower_sprite.z_index >= 0, "%s keeps lower stratum visible above floor layers" % prefab_name)
			_assert_true(lower_sprite.z_index < upper_sprite.z_index, "%s keeps lower stratum below upper stratum" % prefab_name)
		root.free()


func _validate_runtime_demo_scene(scene_path: String) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Runtime stairs demo scene loads for layout validation")
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Runtime stairs demo scene instantiates for layout validation")
	if instance == null:
		return
	var player := instance.get_node_or_null("PF Player")
	var south_stairs := instance.get_node_or_null("PF Struct - Stairs S 01 L")
	var south_trigger := instance.get_node_or_null("PF Struct - Stairs S 01 L/Stairs Layer Trigger")
	var east_lower := instance.get_node_or_null("PF Struct - Stairs E 01/Stairs L/Stairs L Sprite")
	var east_upper := instance.get_node_or_null("PF Struct - Stairs E 01/Stairs U/Stairs U Sprite")
	_assert_true(player is Node2D, "Runtime stairs demo includes player for layout validation")
	_assert_true(player != null and _script_path(player).ends_with("cainos_top_down_player_controller_2d.gd"), "Runtime stairs demo uses imported player controller")
	_assert_true(instance.get_node_or_null("PF Player/FollowCamera2D") is Camera2D, "Runtime stairs demo includes player follow camera")
	_assert_true(south_stairs is Node2D, "Runtime stairs demo includes south stairs for layout validation")
	_assert_true(south_trigger is Node2D, "Runtime stairs demo includes south trigger for layout validation")
	if player is Node2D and south_stairs is Node2D and south_trigger is Node2D:
		var movement_bounds: Rect2 = player.get("movement_bounds")
		_assert_true(movement_bounds.has_point((player as Node2D).position), "Runtime stairs demo player spawn stays inside movement bounds")
		var south_trigger_position := (south_stairs as Node2D).position + (south_trigger as Node2D).position
		_assert_true(movement_bounds.has_point(south_trigger_position), "Runtime stairs demo south trigger stays inside movement bounds")
	if east_lower is Sprite2D and east_upper is Sprite2D:
		_assert_true((east_lower as Sprite2D).z_index >= 0, "Runtime stairs demo east lower stratum stays visible above floor layers")
		_assert_true((east_lower as Sprite2D).z_index < (east_upper as Sprite2D).z_index, "Runtime stairs demo east lower stratum stays below upper stratum")
	instance.free()


func _validate_altar_runes_demo_scene(scene_path: String) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Runtime altar/runes demo scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Runtime altar/runes demo scene instantiates: %s" % scene_path)
	if instance == null:
		return
	_assert_eq(instance.name, "basic_runtime_altar_runes_demo", "Runtime altar/runes demo root name")
	_assert_true(instance.get_node_or_null("PF Props - Altar 01") != null, "Runtime altar/runes demo includes altar instance")
	_assert_true(instance.get_node_or_null("PF Props - Rune Pillar X2") != null, "Runtime altar/runes demo includes rune pillar X2 instance")
	_assert_true(instance.get_node_or_null("PF Props - Rune Pillar X3") != null, "Runtime altar/runes demo includes rune pillar X3 instance")
	_assert_true(instance.get_node_or_null("PF Player") != null and _script_path(instance.get_node_or_null("PF Player")).ends_with("cainos_top_down_player_controller_2d.gd"), "Runtime altar/runes demo uses imported player controller")
	_assert_true(instance.get_node_or_null("PF Player/FollowCamera2D") is Camera2D, "Runtime altar/runes demo includes player follow camera")
	instance.free()


func _validate_player_demo_scene(scene_path: String) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Runtime player demo scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Runtime player demo scene instantiates: %s" % scene_path)
	if instance == null:
		return
	_assert_eq(instance.name, "basic_runtime_player_demo", "Runtime player demo root name")
	var player := instance.get_node_or_null("PF Player")
	_assert_true(player is Node2D, "Runtime player demo includes PF Player")
	_assert_true(player != null and _script_path(player).ends_with("cainos_top_down_player_controller_2d.gd"), "Runtime player demo uses imported player controller")
	_assert_true(instance.get_node_or_null("PF Player/FollowCamera2D") is Camera2D, "Runtime player demo includes player follow camera")
	instance.free()


func _validate_altar_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "props", "PF Props - Altar 01")
	if root == null:
		return
	var hints := _behavior_hints_for(root, "altar_trigger")
	_assert_true(not hints.is_empty(), "Altar prefab exposes altar_trigger behavior hint")
	_assert_true(_script_path(root).ends_with("cainos_altar_trigger_2d.gd"), "Altar prefab uses altar runtime script")
	root.call("_ready")
	if not hints.is_empty():
		var data: Dictionary = hints[0].get("data", {})
		_assert_true(Array(data.get("rune_node_paths", [])).size() >= 1, "Altar behavior hint preserves rune node paths")
	var trigger := root.get_node_or_null("BoxCollider_0")
	_assert_true(trigger is Area2D, "Altar prefab keeps trigger Area2D")
	var rune_sprites := [
		root.get_node_or_null("Rune/1/1 Sprite"),
		root.get_node_or_null("Rune/2/2 Sprite"),
		root.get_node_or_null("Rune/3/3 Sprite"),
		root.get_node_or_null("Rune/4/4 Sprite"),
	]
	for rune_sprite_variant in rune_sprites:
		_assert_true(rune_sprite_variant is Sprite2D, "Altar prefab keeps rune sprite node")
		if rune_sprite_variant is Sprite2D:
			var rune_sprite := rune_sprite_variant as Sprite2D
			_assert_float_close(rune_sprite.modulate.a, 0.0, "Altar rune starts hidden")
			_assert_true(rune_sprite.modulate.g > 0.9 and rune_sprite.modulate.b >= 1.0, "Altar rune keeps imported cyan tint")
	if trigger is Area2D:
		var body := StaticBody2D.new()
		root.call("apply_enter_for_body", body)
		root.call("_process", 1.0)
		for rune_sprite_variant in rune_sprites:
			if rune_sprite_variant is Sprite2D:
				_assert_true((rune_sprite_variant as Sprite2D).modulate.a > 0.0, "Altar runtime enter raises rune alpha")
		root.call("apply_exit_for_body", body)
		root.call("_process", 1.0)
		for rune_sprite_variant in rune_sprites:
			if rune_sprite_variant is Sprite2D:
				_assert_true((rune_sprite_variant as Sprite2D).modulate.a < 0.5, "Altar runtime exit lowers rune alpha")
		body.free()
	root.free()


func _validate_rune_prefab(output_root: String) -> void:
	for prefab_name in ["PF Props - Rune Pillar X2", "PF Props - Rune Pillar X3"]:
		var root := _instantiate_prefab(output_root, "props", prefab_name)
		if root == null:
			continue
		_assert_true(not _behavior_hints_for(root, "sprite_color_animation").is_empty(), "Rune pillar exposes sprite_color_animation behavior hint: %s" % prefab_name)
		var glow := root.find_child("Glow", true, false)
		_assert_true(glow != null, "Rune pillar keeps Glow node: %s" % prefab_name)
		if glow != null:
			_assert_true(not _behavior_hints_for(glow, "sprite_color_animation").is_empty(), "Glow node keeps local sprite_color_animation hint: %s" % prefab_name)
			_assert_true(_script_path(glow).ends_with("cainos_sprite_color_animation_2d.gd"), "Glow node uses runtime color animation script: %s" % prefab_name)
			glow.call("_ready")
			var glow_sprite := glow.get_node_or_null("Glow Sprite")
			_assert_true(glow_sprite is Sprite2D, "Rune pillar keeps Glow Sprite: %s" % prefab_name)
			if glow_sprite is Sprite2D:
				glow.call("apply_animation_at_ratio", 0.0)
				var before_color := (glow_sprite as Sprite2D).modulate
				glow.call("apply_animation_at_ratio", 0.5)
				var after_color := (glow_sprite as Sprite2D).modulate
				_assert_true(before_color != after_color, "Rune runtime animation updates Glow Sprite modulate: %s" % prefab_name)
		root.free()


func _validate_player_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "player", "PF Player")
	if root == null:
		return
	_assert_true(root is Node2D and not (root is RigidBody2D), "Player prefab root remains Node2D")
	_assert_true(_script_path(root).ends_with("cainos_top_down_player_controller_2d.gd"), "Player prefab root uses runtime controller script")
	_assert_true(_find_first_sprite(root) != null, "Player prefab includes a Sprite2D descendant")
	var player_sprite := _find_sprite_by_name(root, "PF Player Sprite")
	_assert_true(player_sprite != null, "Player prefab keeps PF Player Sprite node")
	if player_sprite != null:
		_assert_rect2_close(player_sprite.region_rect, Rect2(6.0, 10.0, 21.0, 48.0), "Player primary sprite region")
		_assert_true(_sprite_region_has_visible_pixels(player_sprite), "Player primary sprite samples visible pixels")
	var shadow_sprite := _find_sprite_by_name(root, "Shadow Sprite")
	_assert_true(shadow_sprite != null, "Player prefab keeps Shadow Sprite node")
	if shadow_sprite != null:
		_assert_rect2_close(shadow_sprite.region_rect, Rect2(99.0, 32.0, 27.0, 28.0), "Player shadow sprite region")
		_assert_true(_sprite_region_has_visible_pixels(shadow_sprite), "Player shadow sprite samples visible pixels")
		_assert_eq(shadow_sprite.z_as_relative, false, "Player shadow sprite uses absolute z")
		if player_sprite != null:
			_assert_true(shadow_sprite.z_index < player_sprite.z_index, "Player shadow renders behind player body")
	_assert_true(not _behavior_hints_for(root, "top_down_character_controller").is_empty(), "Player prefab exposes top_down_character_controller behavior hint")
	_assert_float_close(float(root.get("move_speed_px")), 96.0, "Player controller speed converts Unity hint to pixels per second")
	root.call("apply_facing", "north", false)
	if player_sprite != null:
		_assert_rect2_close(player_sprite.region_rect, Rect2(38.0, 10.0, 21.0, 48.0), "Player north-facing sprite region")
	root.call("apply_facing", "east", true)
	if player_sprite != null:
		_assert_rect2_close(player_sprite.region_rect, Rect2(69.0, 10.0, 21.0, 48.0), "Player east-facing sprite region")
		_assert_eq(player_sprite.flip_h, false, "Player east-facing side sprite is unflipped")
	root.call("apply_facing", "west", true)
	if player_sprite != null:
		_assert_rect2_close(player_sprite.region_rect, Rect2(69.0, 10.0, 21.0, 48.0), "Player west-facing sprite region")
		_assert_eq(player_sprite.flip_h, true, "Player west-facing side sprite is flipped")
	var initial_position: Vector2 = root.position
	root.call("step_with_input", Vector2.RIGHT, 1.0)
	_assert_true(root.position.x > initial_position.x, "Player controller step_with_input advances position")
	_assert_eq(str(root.get_meta("cainos_player_direction", "")), "east", "Player controller stores runtime direction metadata")
	_assert_eq(int(root.get_meta("cainos_player_direction_value", -1)), 2, "Player controller stores runtime direction value metadata")
	_assert_eq(bool(root.get_meta("cainos_player_moving", false)), true, "Player controller stores moving metadata")
	var helper := _find_runtime_actor_helper(root)
	_assert_true(helper != null, "Player prefab includes runtime actor helper")
	if helper != null:
		helper.call("_ready")
		helper.call("_ensure_runtime_sensor")
		_assert_true(root.get_node_or_null("CainosRuntimeSensor2D") is Area2D, "Player runtime actor helper creates trigger sensor")
	root.free()


func _validate_report_files(output_root: String) -> void:
	var compatibility_report = _load_json_file(output_root.path_join("reports/compatibility_report.json"))
	_assert_true(compatibility_report is Dictionary, "Compatibility report JSON loads")
	if compatibility_report is Dictionary:
		_assert_eq(int(compatibility_report.get("format_version", -1)), 12, "Compatibility report format_version")
		var summary: Dictionary = compatibility_report.get("summary", {})
		_assert_eq(int(summary.get("supported_static_prefabs", -1)), 78, "Compatibility report supported count")
		_assert_eq(int(summary.get("approximated_prefabs", -1)), 0, "Compatibility report approximated count")
		_assert_eq(int(summary.get("manual_behavior_prefabs", -1)), 0, "Compatibility report manual count")
		_assert_eq(int(summary.get("unresolved_or_skipped_prefabs", -1)), 0, "Compatibility report unresolved count")
		_assert_eq(int(summary.get("editor_only_prefabs", -1)), 3, "Compatibility report editor-only count")
		var stairs_entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), "PF Struct - Stairs S 01 L")
		_assert_true(not stairs_entry.is_empty(), "Compatibility report includes stairs entry")
		_assert_eq(str(stairs_entry.get("tier", "")), "supported_static", "Compatibility report stairs tier")
		_assert_true(Array(stairs_entry.get("reasons", [])).has("stairs_runtime_imported"), "Compatibility report stairs runtime reason")
		_assert_true(Array(stairs_entry.get("reasons", [])).has("stairs_layer_trigger_hint"), "Compatibility report stairs hint reason")
		for prefab_name in [
			"PF Struct - Stairs E 01",
			"PF Struct - Stairs E 02",
			"PF Struct - Stairs W 01",
			"PF Struct - Stairs W 02",
		]:
			var ew_entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), prefab_name)
			_assert_true(not ew_entry.is_empty(), "Compatibility report includes east/west stairs entry: %s" % prefab_name)
			_assert_eq(str(ew_entry.get("tier", "")), "supported_static", "Compatibility report east/west stairs tier: %s" % prefab_name)
			var ew_reasons := Array(ew_entry.get("reasons", []))
			_assert_true(ew_reasons.has("stairs_layer_trigger_hint"), "Compatibility report east/west stairs reason: %s" % prefab_name)
			_assert_true(ew_reasons.has("stairs_runtime_imported"), "Compatibility report east/west stairs runtime reason: %s" % prefab_name)
			_assert_true(not ew_reasons.has("unresolved_sprite_reference"), "Compatibility report omits unresolved sprite reason for repaired stairs: %s" % prefab_name)
			_assert_true(ew_entry.get("scene_path", null) != null, "Compatibility report records scene path for repaired stairs: %s" % prefab_name)
		var unity_scenes: Array = compatibility_report.get("unity_scenes", [])
		var scene_entry := _find_unity_scene_entry(unity_scenes, "SC Demo")
		_assert_true(not scene_entry.is_empty(), "Compatibility report includes SC Demo scene entry")
		if not scene_entry.is_empty():
			_assert_eq(str(scene_entry.get("status", "")), "imported", "Compatibility report SC Demo status")
			_assert_eq(int(scene_entry.get("tile_layer_count", -1)), 10, "Compatibility report SC Demo tile layer count")
			_assert_eq(int(scene_entry.get("placed_prefab_count", -1)), 264, "Compatibility report SC Demo prefab count")
			_assert_true(not str(scene_entry.get("preview_scene_path", "")).is_empty(), "Compatibility report SC Demo preview path")
			_assert_true(not str(scene_entry.get("runtime_scene_path", "")).is_empty(), "Compatibility report SC Demo runtime path")
		var all_props_scene_entry := _find_unity_scene_entry(unity_scenes, "SC All Props")
		_assert_true(not all_props_scene_entry.is_empty(), "Compatibility report includes SC All Props scene entry")
		if not all_props_scene_entry.is_empty():
			_assert_eq(str(all_props_scene_entry.get("status", "")), "imported", "Compatibility report SC All Props status")
			_assert_eq(int(all_props_scene_entry.get("tile_layer_count", -1)), 2, "Compatibility report SC All Props tile layer count")
			_assert_eq(int(all_props_scene_entry.get("placed_prefab_count", -1)), 118, "Compatibility report SC All Props prefab count")
			_assert_true(not str(all_props_scene_entry.get("preview_scene_path", "")).is_empty(), "Compatibility report SC All Props preview path")
			_assert_true(str(all_props_scene_entry.get("runtime_scene_path", "")).is_empty(), "Compatibility report SC All Props omits runtime path")
		for prefab_name in [
			"PF Props - Statue 01",
			"PF Props - Stone 06",
			"PF Props - Stone 07",
			"PF Props - Well 01",
			"PF Props - Wooden Gate 01 Opened",
			"PF Struct - Gate 02",
		]:
			var entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), prefab_name)
			_assert_true(not entry.is_empty(), "Compatibility report includes supported polygon sample: %s" % prefab_name)
			_assert_eq(str(entry.get("tier", "")), "supported_static", "Compatibility report supported polygon tier: %s" % prefab_name)
			_assert_true(Array(entry.get("reasons", [])).has("polygon_collider_imported"), "Compatibility report polygon import reason: %s" % prefab_name)
		for prefab_name in [
			"PF Props - Barrel 01",
			"PF Props - Pot 01",
			"PF Props - Pot 02",
			"PF Props - Pot 03",
			"PF Props - Crate 01",
			"PF Props - Crate 02",
			"PF Props - Stone Cube 01",
		]:
			var entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), prefab_name)
			_assert_true(not entry.is_empty(), "Compatibility report includes runtime rigidbody sample: %s" % prefab_name)
			_assert_eq(str(entry.get("tier", "")), "supported_static", "Compatibility report runtime rigidbody tier: %s" % prefab_name)
			_assert_true(Array(entry.get("reasons", [])).has("rigidbody_imported"), "Compatibility report runtime rigidbody import reason: %s" % prefab_name)
			_assert_true(not Array(entry.get("reasons", [])).has("rigidbody_deferred"), "Compatibility report omits deferred rigidbody reason for imported sample: %s" % prefab_name)
		var player_entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), "PF Player")
		_assert_true(not player_entry.is_empty(), "Compatibility report includes PF Player entry")
		_assert_eq(str(player_entry.get("tier", "")), "supported_static", "Compatibility report PF Player tier")
		_assert_true(Array(player_entry.get("reasons", [])).has("player_controller_runtime_imported"), "Compatibility report PF Player includes controller runtime reason")
		_assert_true(Array(player_entry.get("reasons", [])).has("player_directional_facing_imported"), "Compatibility report PF Player includes directional facing reason")
		_assert_true(Array(player_entry.get("reasons", [])).has("runtime_actor_helper_attached"), "Compatibility report PF Player includes runtime actor helper reason")
		_assert_true(not Array(player_entry.get("reasons", [])).has("rigidbody_deferred"), "Compatibility report PF Player omits deferred rigidbody reason")
		for prefab_name in ["PF Props - Altar 01", "PF Props - Rune Pillar X2", "PF Props - Rune Pillar X3"]:
			var runtime_entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), prefab_name)
			_assert_true(not runtime_entry.is_empty(), "Compatibility report includes altar/rune runtime prefab: %s" % prefab_name)
			_assert_eq(str(runtime_entry.get("tier", "")), "supported_static", "Compatibility report altar/rune runtime tier: %s" % prefab_name)
			var runtime_reasons := Array(runtime_entry.get("reasons", []))
			if prefab_name == "PF Props - Altar 01":
				_assert_true(runtime_reasons.has("altar_runtime_imported"), "Compatibility report altar runtime reason")
				_assert_true(runtime_reasons.has("altar_trigger_hint"), "Compatibility report altar hint reason")
			else:
				_assert_true(runtime_reasons.has("sprite_color_animation_runtime_imported"), "Compatibility report rune runtime reason: %s" % prefab_name)
				_assert_true(runtime_reasons.has("sprite_color_animation_hint"), "Compatibility report rune hint reason: %s" % prefab_name)
			_assert_true(not runtime_reasons.has("mono_behaviour_present"), "Compatibility report omits blocking mono reason for runtime-imported prefab: %s" % prefab_name)
		var unresolved_entries: Array = compatibility_report.get("tiers", {}).get("unresolved_or_skipped", [])
		_assert_eq(unresolved_entries.size(), 0, "Compatibility report unresolved tier is empty")
		var editor_only_prefabs: Array = compatibility_report.get("editor_only_prefabs", [])
		_assert_true(not _find_catalog_prefab_entry(editor_only_prefabs, "TP Grass").is_empty(), "Compatibility report includes TP Grass as editor-only")
		_assert_true(_find_tier_prefab_entry(compatibility_report.get("tiers", {}), "TP Grass").is_empty(), "Editor-only tile palette is excluded from semantic tiers")

	var asset_catalog = _load_json_file(output_root.path_join("reports/asset_catalog.json"))
	_assert_true(asset_catalog is Dictionary, "Asset catalog JSON loads")
	if asset_catalog is Dictionary:
		_assert_eq(int(asset_catalog.get("format_version", -1)), 12, "Asset catalog format_version")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Plant - Bush 01").is_empty(), "Asset catalog includes Bush prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Stone Lantern 01").is_empty(), "Asset catalog includes Stone Lantern prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Well 01").is_empty(), "Asset catalog includes Well prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Barrel 01").is_empty(), "Asset catalog includes Barrel prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Crate 01").is_empty(), "Asset catalog includes Crate 01 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Crate 02").is_empty(), "Asset catalog includes Crate 02 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Pot 01").is_empty(), "Asset catalog includes Pot 01 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Pot 02").is_empty(), "Asset catalog includes Pot 02 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Pot 03").is_empty(), "Asset catalog includes Pot 03 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Stone Cube 01").is_empty(), "Asset catalog includes Stone Cube prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Gate 02").is_empty(), "Asset catalog includes Gate 02 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Stairs S 01 L").is_empty(), "Asset catalog includes Stairs prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Stairs E 01").is_empty(), "Asset catalog includes Stairs E 01 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Stairs E 02").is_empty(), "Asset catalog includes Stairs E 02 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Stairs W 01").is_empty(), "Asset catalog includes Stairs W 01 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Stairs W 02").is_empty(), "Asset catalog includes Stairs W 02 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Altar 01").is_empty(), "Asset catalog includes Altar prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Rune Pillar X2").is_empty(), "Asset catalog includes Rune Pillar prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Rune Pillar X3").is_empty(), "Asset catalog includes Rune Pillar X3 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Player").is_empty(), "Asset catalog includes Player prefab")
		_assert_true(_find_helper_scene_entry(asset_catalog.get("helper_scenes", []), "basic_runtime_stairs_demo") != null, "Asset catalog includes runtime stairs demo helper scene")
		_assert_true(_find_helper_scene_entry(asset_catalog.get("helper_scenes", []), "basic_runtime_altar_runes_demo") != null, "Asset catalog includes runtime altar/runes demo helper scene")
		_assert_true(_find_helper_scene_entry(asset_catalog.get("helper_scenes", []), "basic_runtime_player_demo") != null, "Asset catalog includes runtime player demo helper scene")
		var imported_scene_entry := _find_unity_scene_entry(asset_catalog.get("imported_scenes", []), "SC Demo")
		_assert_true(not imported_scene_entry.is_empty(), "Asset catalog includes imported SC Demo scene")
		if not imported_scene_entry.is_empty():
			_assert_true(not str(imported_scene_entry.get("preview_scene_path", "")).is_empty(), "Asset catalog includes imported SC Demo preview path")
			_assert_true(not str(imported_scene_entry.get("runtime_scene_path", "")).is_empty(), "Asset catalog includes imported SC Demo runtime path")
		var all_props_catalog_entry := _find_unity_scene_entry(asset_catalog.get("imported_scenes", []), "SC All Props")
		_assert_true(not all_props_catalog_entry.is_empty(), "Asset catalog includes imported SC All Props scene")
		if not all_props_catalog_entry.is_empty():
			_assert_true(not str(all_props_catalog_entry.get("preview_scene_path", "")).is_empty(), "Asset catalog includes imported SC All Props preview path")
			_assert_true(str(all_props_catalog_entry.get("runtime_scene_path", "")).is_empty(), "Asset catalog omits runtime path for SC All Props")
		_assert_true(_find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "TP Grass").is_empty(), "Asset catalog omits editor-only tile palette prefab")


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


func _count_collision_shapes(node: Node) -> int:
	var count := 0
	if node is CollisionShape2D:
		count += 1
	for child in node.get_children():
		count += _count_collision_shapes(child)
	return count


func _count_collision_polygons(node: Node) -> int:
	var count := 0
	if node is CollisionPolygon2D:
		count += 1
	for child in node.get_children():
		count += _count_collision_polygons(child)
	return count


func _find_first_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node
	for child in node.get_children():
		var sprite := _find_first_sprite(child)
		if sprite != null:
			return sprite
	return null


func _find_sprite_by_name(node: Node, expected_name: String) -> Sprite2D:
	if node is Sprite2D and node.name == expected_name:
		return node
	for child in node.get_children():
		var sprite := _find_sprite_by_name(child, expected_name)
		if sprite != null:
			return sprite
	return null


func _find_runtime_actor_helper(node: Node) -> Node:
	if _script_path(node).ends_with("cainos_runtime_actor_2d.gd"):
		return node
	for child in node.get_children():
		var found := _find_runtime_actor_helper(child)
		if found != null:
			return found
	return null


func _sprites_by_effective_layer(node: Node, layer_name: String) -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	if node is Sprite2D and str(node.get_meta("cainos_effective_sorting_layer_name", "")) == layer_name:
		sprites.append(node as Sprite2D)
	for child in node.get_children():
		sprites.append_array(_sprites_by_effective_layer(child, layer_name))
	return sprites


func _min_sprite_z(sprites: Array[Sprite2D]) -> int:
	var value := 0
	var initialized := false
	for sprite in sprites:
		if not initialized:
			value = sprite.z_index
			initialized = true
		else:
			value = mini(value, sprite.z_index)
	return value


func _max_sprite_z(sprites: Array[Sprite2D]) -> int:
	var value := 0
	var initialized := false
	for sprite in sprites:
		if not initialized:
			value = sprite.z_index
			initialized = true
		else:
			value = maxi(value, sprite.z_index)
	return value


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


func _find_first_node_with_meta(node: Node, meta_key: String) -> Node:
	if node.has_meta(meta_key):
		return node
	for child in node.get_children():
		var found := _find_first_node_with_meta(child, meta_key)
		if found != null:
			return found
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


func _find_tier_prefab_entry(tiers: Dictionary, prefab_name: String) -> Dictionary:
	for tier_entries_variant in tiers.values():
		for entry_variant in tier_entries_variant:
			var entry: Dictionary = entry_variant
			if str(entry.get("prefab_name", "")) == prefab_name:
				return entry
	return {}


func _find_catalog_prefab_entry(entries: Array, prefab_name: String) -> Dictionary:
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if str(entry.get("prefab_name", "")) == prefab_name:
			return entry
	return {}


func _find_helper_scene_entry(entries: Array, helper_name: String):
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if str(entry.get("name", "")) == helper_name:
			return entry
	return null


func _find_unity_scene_entry(entries: Array, scene_name: String) -> Dictionary:
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if str(entry.get("scene_name", entry.get("name", ""))) == scene_name:
			return entry
	return {}


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


func _load_json_file(res_path: String):
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(abs_path))


func _assert_collision_layer_if_present(root: Node, node_path: String, expected_layer: int, message: String) -> void:
	var node := root.get_node_or_null(node_path)
	if node == null:
		return
	_assert_true(node is CollisionObject2D, "%s node is collision object" % message)
	if node is CollisionObject2D:
		_assert_eq((node as CollisionObject2D).collision_layer, expected_layer, message)


func _cell_array_has_cell(cells, expected_cell: Vector2i) -> bool:
	if not (cells is Array):
		return false
	for cell_variant in cells:
		if _variant_to_cell(cell_variant) == expected_cell:
			return true
	return false


func _variant_to_cell(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		var vector_value: Vector2 = value
		return Vector2i(roundi(vector_value.x), roundi(vector_value.y))
	if value is Dictionary:
		var dict_value: Dictionary = value
		return Vector2i(int(dict_value.get("x", 0)), int(dict_value.get("y", 0)))
	if value is Array:
		var array_value: Array = value
		if array_value.size() >= 2:
			return Vector2i(int(array_value[0]), int(array_value[1]))
	if value is String:
		var parts := str(value).split(",", false)
		if parts.size() == 2:
			return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


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
		print("All real-pack validation checks passed.")
		quit(0)
	else:
		print("Validation failures: %d" % _failures.size())
		for failure in _failures:
			print(" - %s" % failure)
		quit(1)
