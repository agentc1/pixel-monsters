extends SceneTree

const GRID_CELL_SIZE := 32.0
const GRID_STEP_WAIT_FRAMES := 18
const PLAYER_LOWER_BODY_FOOTPRINT_SIZE := Vector2(30.0, 30.0)
const LAYER_NAMES := ["Layer 1", "Layer 2", "Layer 3"]
const GRID_DIRECTIONS := ["north", "south", "east", "west"]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var output_root := str(args.get("output_root", "res://cainos_imports/basic_real_acceptance"))
	var scene_path := output_root.path_join("scenes/unity/SC Demo Runtime.tscn")
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Runtime navigation scene loads")
	if not (packed is PackedScene):
		_finish()
		return

	var scene := (packed as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame

	var player := scene.get_node_or_null("RuntimePlayer") as CharacterBody2D
	var navigation_overlay := scene.get_node_or_null("NavigationOverlay") as Node2D
	_assert_true(player != null, "Runtime navigation scene has CharacterBody2D player")
	_assert_true(navigation_overlay != null, "Runtime navigation scene has grid navigation overlay")
	if player != null:
		_validate_grid_runtime_configuration(player)
		if navigation_overlay != null:
			await _validate_navigation_overlay(navigation_overlay, player)
		await _validate_grid_step_contract(player)
		await _validate_north_bridge_spawn_route(player)
		_validate_bridge_underpass_probe(player)
		await _validate_bridge_underpass_drive(player)
		await _validate_south_stairs_ascent(player)
		await _validate_east_west_stair_transition(player)
		await _validate_upper_platform_bounds(player)
		await _validate_upper_platform_obstacles(player)
	_validate_command_legend(scene)
	_validate_bridge_occluders(scene)

	scene.free()
	_finish()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	var index := 0
	while index < args.size():
		var token := args[index]
		if token == "--output-root" and index + 1 < args.size():
			parsed["output_root"] = args[index + 1]
			index += 1
		index += 1
	return parsed


func _validate_grid_runtime_configuration(player: CharacterBody2D) -> void:
	_assert_true(str(player.get("navigation_mode")) == "grid_cardinal", "Runtime player uses grid-cardinal navigation")
	_assert_true(is_equal_approx(float(player.get("grid_cell_size")), GRID_CELL_SIZE), "Runtime player uses 32px grid cells")
	_assert_true(Array(player.get("grid_transition_edges")).size() > 0, "Runtime player has grid transition edges")
	var navigation_map = player.get("navigation_map")
	_assert_true(navigation_map is Resource, "Runtime player uses generated navigation map resource")
	if navigation_map is Resource:
		_assert_true(str((navigation_map as Resource).resource_path).ends_with("navigation/SC Demo_navigation_map.tres"), "Runtime player navigation map is saved as an external resource")
		var navigation_overrides = (navigation_map as Resource).get("navigation_overrides")
		_assert_true(navigation_overrides is Resource, "Runtime player navigation map has an external override resource")
		if navigation_overrides is Resource:
			_assert_true(str((navigation_overrides as Resource).resource_path).ends_with("navigation/SC Demo_navigation_overrides.tres"), "Runtime player navigation overrides are saved separately from inferred map")
		_assert_true(bool((navigation_map as Resource).call("is_cell_navigable", Vector2i(6, -2), "Layer 1")), "Runtime navigation map includes the spawn cell")
		var reachable_from_spawn: Dictionary = (navigation_map as Resource).call("reachable_cells_from", "Layer 1", Vector2i(6, -2), 20000)
		_assert_true(not _cell_array_has_cell(reachable_from_spawn.get("Layer 1", []), Vector2i(1, -15)), "Runtime navigation map keeps unreachable Layer 1 island cells outside spawn reachability")
		_validate_transition_endpoint_exclusivity(navigation_map as Resource, Array(player.get("grid_transition_edges")))
	var blocked_cells_by_layer: Dictionary = player.get("grid_blocked_cells_by_layer")
	_assert_true(_cell_array_has_cell(blocked_cells_by_layer.get("Layer 2", []), Vector2i(9, -3)), "Runtime Layer 2 grid blockers include the bush north of the south stairs")
	_assert_true(_cell_array_has_cell(blocked_cells_by_layer.get("Layer 2", []), Vector2i(11, -2)), "Runtime Layer 2 grid blockers include upper-platform wall/ledge cells")
	_validate_player_lower_body_footprint(player)


func _validate_player_lower_body_footprint(player: CharacterBody2D) -> void:
	var shape_node := _runtime_player_footprint_shape(player)
	_assert_true(shape_node != null, "Runtime player exposes a lower-body collision footprint")
	if shape_node == null:
		return
	_assert_vector2_close(shape_node.position, Vector2.ZERO, "Runtime player lower-body footprint is centered on the occupied grid cell")
	var rectangle_shape := shape_node.shape as RectangleShape2D
	_assert_true(rectangle_shape != null, "Runtime player lower-body footprint is a rectangle")
	if rectangle_shape == null:
		return
	_assert_vector2_close(rectangle_shape.size, PLAYER_LOWER_BODY_FOOTPRINT_SIZE, "Runtime player lower-body footprint fits inside one 32px grid tile")


func _validate_command_legend(scene: Node) -> void:
	var command_legend := scene.get_node_or_null("CommandLegend") as Node2D
	_assert_true(command_legend != null, "Runtime scene includes command legend below the map")
	if command_legend == null:
		return
	_assert_true(bool(command_legend.get_meta("cainos_runtime_command_legend", false)), "Runtime command legend is tagged")
	var legend_rect: Rect2 = command_legend.get_meta("legend_world_rect", Rect2())
	_assert_true(legend_rect.size.x > 0.0 and legend_rect.size.y > 0.0, "Runtime command legend stores its world bounds")
	_assert_true(legend_rect.position.y > 0.0, "Runtime command legend is placed below the main map area")
	var instructions := command_legend.get_node_or_null("Instructions") as Label
	_assert_true(instructions != null, "Runtime command legend includes instructions label")
	if instructions == null:
		return
	var text := instructions.text
	_assert_true(text.contains("WASD"), "Runtime command legend documents movement")
	_assert_true(text.contains("1 / 2 / 3"), "Runtime command legend documents layer toggles")
	_assert_true(text.contains("N toggles editing"), "Runtime command legend documents edit mode")
	_assert_true(text.contains("WASD / arrow keys"), "Runtime command legend documents cursor movement")
	_assert_true(text.contains("Insert force-navigable"), "Runtime command legend documents Insert force-navigable override")
	_assert_true(text.contains("Delete force-blocked"), "Runtime command legend documents Delete force-blocked override")
	_assert_true(text.contains("Edits affect only the active layer"), "Runtime command legend documents active-layer-only overrides")
	_assert_true(text.contains("Switch layers with Q / E"), "Runtime command legend documents repeated stacked-cell edits")
	_assert_true(text.contains("V or Ctrl+S saves overrides"), "Runtime command legend documents saving overrides")
	_assert_true(text.contains("Ctrl+B bakes overrides"), "Runtime command legend documents baking overrides")
	var command_legend_hud := scene.get_node_or_null("CommandLegendHUD") as CanvasLayer
	_assert_true(command_legend_hud != null, "Runtime scene includes visible command legend HUD")
	if command_legend_hud == null:
		return
	_assert_true(bool(command_legend_hud.get_meta("cainos_runtime_command_legend_hud", false)), "Runtime command legend HUD is tagged")
	var hud_instructions := command_legend_hud.get_node_or_null("Instructions") as Label
	_assert_true(hud_instructions != null, "Runtime command legend HUD includes instructions label")
	if hud_instructions != null:
		_assert_true(hud_instructions.text.contains("WASD"), "Runtime command legend HUD documents movement")


func _validate_transition_endpoint_exclusivity(navigation_map: Resource, transition_edges: Array) -> void:
	var endpoint_layers_by_cell := {}
	for edge_variant in transition_edges:
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		_add_endpoint_owner(endpoint_layers_by_cell, str(edge.get("from_layer", "")), _variant_to_cell(edge.get("from_cell", Vector2i.ZERO)))
		_add_endpoint_owner(endpoint_layers_by_cell, str(edge.get("to_layer", "")), _variant_to_cell(edge.get("to_cell", Vector2i.ZERO)))
	var leaks := []
	for endpoint_variant in endpoint_layers_by_cell.values():
		var endpoint: Dictionary = endpoint_variant
		var cell := _variant_to_cell(endpoint.get("cell", Vector2i.ZERO))
		var owner_layers: Array = endpoint.get("layers", [])
		for layer_name in LAYER_NAMES:
			if owner_layers.has(layer_name):
				continue
			if bool(navigation_map.call("is_cell_navigable", cell, layer_name)):
				leaks.append("%s:%s" % [layer_name, str(cell)])
	_assert_true(leaks.is_empty(), "Runtime navigation map keeps stair transition endpoint cells navigable only on owner layers")


func _add_endpoint_owner(endpoint_layers_by_cell: Dictionary, layer_name: String, cell: Vector2i) -> void:
	if layer_name.is_empty():
		return
	var key := "%d,%d" % [cell.x, cell.y]
	var endpoint: Dictionary = endpoint_layers_by_cell.get(key, {"cell": cell, "layers": []})
	var layers: Array = endpoint.get("layers", [])
	if not layers.has(layer_name):
		layers.append(layer_name)
	endpoint["layers"] = layers
	endpoint_layers_by_cell[key] = endpoint


func _validate_navigation_overlay(navigation_overlay: Node2D, player: CharacterBody2D) -> void:
	_assert_true(_script_path(navigation_overlay).ends_with("cainos_grid_navigation_overlay_2d.gd"), "Runtime navigation overlay uses grid overlay script")
	_assert_true(navigation_overlay.get("navigation_map") is Resource, "Runtime navigation overlay uses generated navigation map resource")
	var result: Dictionary = navigation_overlay.call("rebuild_navigation_overlay")
	_assert_true(bool(result.get("ok", false)), "Runtime navigation overlay rebuilds from player grid data")
	_validate_navigation_overlay_palette(navigation_overlay)
	await _validate_navigation_overlay_layer_toggles(navigation_overlay)
	await _validate_navigation_edit_mode_input_transfer(navigation_overlay, player)
	var counts: Dictionary = navigation_overlay.get_meta("reachable_cell_counts_by_layer", {})
	var map_counts: Dictionary = navigation_overlay.get_meta("navigation_map_cell_counts_by_layer", {})
	_assert_true(int(counts.get("Layer 1", 0)) > 0, "Runtime navigation overlay marks reachable Layer 1 cells")
	_assert_true(int(counts.get("Layer 2", 0)) > 0, "Runtime navigation overlay marks reachable Layer 2 cells")
	_assert_true(int(map_counts.get("Layer 1", -1)) >= int(counts.get("Layer 1", 0)), "Runtime navigation overlay Layer 1 map cells include reachable source-of-truth cells")
	_assert_true(int(map_counts.get("Layer 2", -1)) >= int(counts.get("Layer 2", 0)), "Runtime navigation overlay Layer 2 map cells include reachable source-of-truth cells")
	_assert_true(bool(navigation_overlay.call("is_cell_reachable", Vector2i(4, 3), "Layer 1")), "Runtime navigation overlay includes the lower bridge underpass route")
	_assert_true(not bool(navigation_overlay.call("is_cell_reachable", Vector2i(9, -3), "Layer 2")), "Runtime navigation overlay excludes the blocked bush north of south stairs")
	_assert_true(not bool(navigation_overlay.call("is_cell_reachable", Vector2i(11, -2), "Layer 2")), "Runtime navigation overlay excludes upper-platform ledge blockers")
	_assert_true(not bool(navigation_overlay.call("is_cell_reachable", Vector2i(10, -5), "Layer 2")), "Runtime navigation overlay excludes the side-stair false upper corridor")
	var edge := _first_horizontal_stair_edge(player)
	if not edge.is_empty():
		var to_cell := _variant_to_cell(edge.get("to_cell", Vector2i.ZERO))
		var to_layer := str(edge.get("to_layer", ""))
		var transition_cells_by_layer: Dictionary = navigation_overlay.get_meta("transition_cells_by_layer", {})
		_assert_true(_cell_array_has_cell(transition_cells_by_layer.get(to_layer, []), to_cell), "Runtime navigation overlay marks horizontal stair transition landing")
	var debug_report: Dictionary = navigation_overlay.call("navigation_debug_report")
	_validate_navigation_debug_report(debug_report, counts, map_counts)
	await _validate_navigation_overrides(navigation_overlay, player)
	_validate_navigation_overlay_matches_player_probe(navigation_overlay, player)


func _validate_navigation_overlay_palette(navigation_overlay: Node2D) -> void:
	var colors: Dictionary = navigation_overlay.get_meta("navigation_overlay_colors", {})
	var layer_1_color: Color = colors.get("Layer 1", Color.GREEN)
	_assert_true(layer_1_color.g < 0.6, "Runtime navigation overlay Layer 1 does not use grass-green tint")
	var edit_state: Dictionary = navigation_overlay.call("set_navigation_edit_mode", true)
	_assert_true(bool(edit_state.get("edit_mode_enabled", false)), "Runtime navigation overlay edit mode exposes the cursor")
	_assert_cursor_matches_layer(navigation_overlay, colors, "Layer 1")
	navigation_overlay.call("set_edit_layer", "Layer 2")
	_assert_cursor_matches_layer(navigation_overlay, colors, "Layer 2")
	navigation_overlay.call("set_edit_layer", "Layer 3")
	_assert_cursor_matches_layer(navigation_overlay, colors, "Layer 3")
	_assert_forced_blocked_markers_match_layers(navigation_overlay, colors)
	navigation_overlay.call("set_navigation_edit_mode", false)


func _assert_cursor_matches_layer(navigation_overlay: Node2D, colors: Dictionary, layer_name: String) -> void:
	var expected_color: Color = colors.get(layer_name, Color.WHITE)
	expected_color.a = 1.0
	var cursor_color: Color = navigation_overlay.get("edit_cursor_color")
	_assert_true(
		_colors_equal_approx(cursor_color, expected_color),
		"Runtime navigation overlay edit cursor matches %s color at full opacity" % layer_name
	)
	var published_color: Color = navigation_overlay.get_meta("navigation_edit_cursor_color", Color.TRANSPARENT)
	_assert_true(
		_colors_equal_approx(published_color, expected_color),
		"Runtime navigation overlay publishes %s cursor color at full opacity" % layer_name
	)


func _assert_forced_blocked_markers_match_layers(navigation_overlay: Node2D, colors: Dictionary) -> void:
	var marker_colors: Dictionary = navigation_overlay.get_meta("forced_blocked_marker_colors", {})
	for layer_name in LAYER_NAMES:
		var expected_color: Color = colors.get(layer_name, Color.WHITE)
		expected_color.a = 1.0
		var marker_color: Color = marker_colors.get(layer_name, Color.TRANSPARENT)
		_assert_true(
			_colors_equal_approx(marker_color, expected_color),
			"Runtime navigation forced-blocked marker matches %s color at full opacity" % layer_name
		)


func _colors_equal_approx(left: Color, right: Color) -> bool:
	return (
		is_equal_approx(left.r, right.r)
		and is_equal_approx(left.g, right.g)
		and is_equal_approx(left.b, right.b)
		and is_equal_approx(left.a, right.a)
	)


func _validate_navigation_overrides(navigation_overlay: Node2D, player: CharacterBody2D) -> void:
	var navigation_map = player.get("navigation_map")
	_assert_true(navigation_map is Resource, "Runtime navigation override validation has a navigation map")
	if not (navigation_map is Resource):
		return
	var map_resource := navigation_map as Resource
	var override_resource = map_resource.get("navigation_overrides")
	_assert_true(override_resource is Resource, "Runtime navigation override validation has an override resource")
	if not (override_resource is Resource):
		return
	var override_path := str((override_resource as Resource).resource_path)
	var origin_cell := Vector2i(6, -2)
	var block_cell := Vector2i(5, -2)
	var before_step: Dictionary = player.call("can_grid_step_from_cell", "Layer 1", origin_cell, "west")
	_assert_true(bool(before_step.get("allowed", false)), "Runtime navigation allows west step before designer override")

	navigation_overlay.call("set_navigation_edit_mode", true)
	navigation_overlay.call("set_edit_layer", "Layer 1")
	navigation_overlay.call("set_edit_cursor_cell", block_cell)
	_send_key(KEY_BACKSPACE, true)
	await process_frame
	_send_key(KEY_BACKSPACE, false)
	await process_frame
	_assert_true(str(map_resource.call("cell_override_state", "Layer 1", block_cell)) == "none", "Runtime navigation Backspace does not force-block a cell")
	_send_key(KEY_DELETE, true)
	await process_frame
	_send_key(KEY_DELETE, false)
	await process_frame
	_assert_true(str(map_resource.call("cell_override_state", "Layer 1", block_cell)) == "force_blocked", "Runtime navigation map records force-blocked override")
	_assert_true(not bool(map_resource.call("is_cell_navigable", block_cell, "Layer 1")), "Runtime navigation force-blocked cell is no longer navigable")
	var blocked_step: Dictionary = player.call("can_grid_step_from_cell", "Layer 1", origin_cell, "west")
	_assert_true(not bool(blocked_step.get("allowed", true)), "Runtime navigation blocks movement into force-blocked cell")
	_assert_true(not bool(navigation_overlay.call("is_cell_reachable", block_cell, "Layer 1")), "Runtime navigation overlay removes force-blocked cell from reachability")
	var save_result: Dictionary = navigation_overlay.call("save_navigation_overrides")
	_assert_true(bool(save_result.get("ok", false)), "Runtime navigation overlay saves override resource")
	var reloaded = ResourceLoader.load(override_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_assert_true(reloaded is Resource, "Runtime navigation override resource reloads from disk")
	if reloaded is Resource:
		_assert_true(str((reloaded as Resource).call("cell_override_state", "Layer 1", block_cell)) == "force_blocked", "Runtime navigation force-blocked override persists to disk")

	var clear_result: Dictionary = navigation_overlay.call("clear_cell_override", "Layer 1", block_cell)
	_assert_true(bool(clear_result.get("ok", false)), "Runtime navigation overlay clears a cell override")
	_assert_true(str(map_resource.call("cell_override_state", "Layer 1", block_cell)) == "none", "Runtime navigation map clears override state")
	_assert_true(bool(map_resource.call("is_cell_navigable", block_cell, "Layer 1")), "Runtime navigation cleared cell returns to inferred navigable state")
	var restored_step: Dictionary = player.call("can_grid_step_from_cell", "Layer 1", origin_cell, "west")
	_assert_true(bool(restored_step.get("allowed", false)), "Runtime navigation restores movement after override clear")
	var clear_save_result: Dictionary = navigation_overlay.call("save_navigation_overrides")
	_assert_true(bool(clear_save_result.get("ok", false)), "Runtime navigation overlay saves cleared override resource")

	var layer_specific_block_cell := Vector2i(7, -2)
	navigation_overlay.call("set_edit_layer", "Layer 2")
	navigation_overlay.call("set_edit_cursor_cell", layer_specific_block_cell)
	_send_key(KEY_INSERT, true)
	await process_frame
	_send_key(KEY_INSERT, false)
	await process_frame
	var states_after_insert: Dictionary = navigation_overlay.call("cell_override_states", layer_specific_block_cell)
	_assert_true(str(states_after_insert.get("Layer 1", "")) == "none", "Runtime navigation Insert does not force-navigate Layer 1 when Layer 2 is active")
	_assert_true(str(states_after_insert.get("Layer 2", "")) == "force_navigable", "Runtime navigation Insert force-navigates only the active layer")
	_assert_true(str(states_after_insert.get("Layer 3", "")) == "none", "Runtime navigation Insert does not force-navigate Layer 3 when Layer 2 is active")
	_send_key(KEY_DELETE, true)
	await process_frame
	_send_key(KEY_DELETE, false)
	await process_frame
	var states_after_delete: Dictionary = navigation_overlay.call("cell_override_states", layer_specific_block_cell)
	_assert_true(str(states_after_delete.get("Layer 1", "")) == "none", "Runtime navigation Delete does not force-block Layer 1 when Layer 2 is active")
	_assert_true(str(states_after_delete.get("Layer 2", "")) == "force_blocked", "Runtime navigation Delete force-blocks only the active layer")
	_assert_true(str(states_after_delete.get("Layer 3", "")) == "none", "Runtime navigation Delete does not force-block Layer 3 when Layer 2 is active")
	_assert_true(str(map_resource.call("cell_override_state", "Layer 2", layer_specific_block_cell)) == "force_blocked", "Runtime navigation map records active-layer force-block")
	for layer_name in LAYER_NAMES:
		if layer_name == "Layer 2":
			continue
		_assert_true(str(map_resource.call("cell_override_state", layer_name, layer_specific_block_cell)) == "none", "Runtime navigation map leaves non-active layer unblocked: %s" % layer_name)
	_send_key(KEY_C, true, 99, true)
	await process_frame
	_send_key(KEY_C, false, 99, true)
	await process_frame
	var states_after_shift_c: Dictionary = navigation_overlay.call("cell_override_states", layer_specific_block_cell)
	for layer_name in LAYER_NAMES:
		_assert_true(str(states_after_shift_c.get(layer_name, "")) == "none", "Runtime navigation clear leaves no override on layer: %s" % layer_name)
		_assert_true(str(map_resource.call("cell_override_state", layer_name, layer_specific_block_cell)) == "none", "Runtime navigation map clears active-layer force-block without touching other layers: %s" % layer_name)
	navigation_overlay.call("set_navigation_edit_mode", false)
	var layer_specific_clear_save_result: Dictionary = navigation_overlay.call("save_navigation_overrides")
	_assert_true(bool(layer_specific_clear_save_result.get("ok", false)), "Runtime navigation overlay saves cleared active-layer override")


func _validate_navigation_debug_report(report: Dictionary, reachable_counts: Dictionary, map_counts: Dictionary) -> void:
	_assert_true(bool(report.get("ok", false)), "Runtime navigation overlay exposes a navigation debug report")
	if not bool(report.get("ok", false)):
		return
	var layers_variant = report.get("layers", {})
	_assert_true(layers_variant is Dictionary, "Runtime navigation debug report includes layer inventory")
	if not (layers_variant is Dictionary):
		return
	var layers: Dictionary = layers_variant
	for layer_name in LAYER_NAMES:
		var layer_report_variant = layers.get(layer_name, {})
		_assert_true(layer_report_variant is Dictionary, "Runtime navigation debug report includes %s inventory" % layer_name)
		if not (layer_report_variant is Dictionary):
			continue
		var layer_report: Dictionary = layer_report_variant
		_assert_true(
			int(layer_report.get("navigable_count", -1)) == int(map_counts.get(layer_name, -2)),
			"Runtime navigation debug report %s navigable count matches overlay map cells" % layer_name
		)
		_assert_true(
			int(layer_report.get("reachable_count", -1)) == int(reachable_counts.get(layer_name, -2)),
			"Runtime navigation debug report %s reachable count matches overlay reachable cells" % layer_name
		)
		_assert_true(layer_report.get("unreachable_cells", []) is Array, "Runtime navigation debug report lists %s unreachable cells" % layer_name)
	var layer3: Dictionary = layers.get("Layer 3", {})
	_assert_true(int(layer3.get("walkable_count", 0)) > 0, "Runtime navigation debug report distinguishes present Layer 3 walkable cells from origin reachability")
	if int(layer3.get("walkable_count", 0)) > 0 and int(layer3.get("reachable_count", 0)) == 0:
		_assert_true(
			_navigation_debug_report_has_transition_status(report, "source_unreachable", "Layer 3"),
			"Runtime navigation debug report explains unreachable Layer 3 through a source-unreachable transition"
		)


func _navigation_debug_report_has_transition_status(report: Dictionary, status: String, to_layer: String) -> bool:
	for edge_variant in Array(report.get("transition_edges", [])):
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		if str(edge.get("status", "")) == status and str(edge.get("to_layer", "")) == to_layer:
			return true
	return false


func _validate_navigation_overlay_layer_toggles(navigation_overlay: Node2D) -> void:
	_assert_true(bool(navigation_overlay.call("is_layer_visible", "Layer 1")), "Runtime navigation overlay starts with Layer 1 visible")
	_assert_true(bool(navigation_overlay.call("is_layer_visible", "Layer 2")), "Runtime navigation overlay starts with Layer 2 visible")
	var method_result: Dictionary = navigation_overlay.call("toggle_layer_visibility", "Layer 2")
	_assert_true(bool(method_result.get("ok", false)), "Runtime navigation overlay exposes method-based layer toggles")
	_assert_true(not bool(navigation_overlay.call("is_layer_visible", "Layer 2")), "Runtime navigation overlay method toggle hides Layer 2")
	var visibility_after_method: Dictionary = navigation_overlay.get_meta("visible_layers_by_layer", {})
	_assert_true(not bool(visibility_after_method.get("Layer 2", true)), "Runtime navigation overlay publishes hidden Layer 2 metadata")

	_send_key(KEY_2, true, 50)
	await process_frame
	_send_key(KEY_2, false, 50)
	await process_frame
	_assert_true(bool(navigation_overlay.call("is_layer_visible", "Layer 2")), "Runtime navigation overlay key 2 toggles Layer 2 back on through Godot input")
	var visibility_after_key: Dictionary = navigation_overlay.get_meta("visible_layers_by_layer", {})
	_assert_true(bool(visibility_after_key.get("Layer 2", false)), "Runtime navigation overlay publishes restored Layer 2 metadata")


func _validate_navigation_edit_mode_input_transfer(navigation_overlay: Node2D, player: CharacterBody2D) -> void:
	await _place_player(player, Vector2(128.0, 256.0), "Layer 1")
	var start_position := player.global_position
	var start_state: Dictionary = navigation_overlay.call("set_navigation_edit_mode", true)
	var start_cell := _variant_to_cell(start_state.get("edit_cursor_cell", Vector2i.ZERO))
	_send_key(KEY_W, true)
	await process_frame
	await physics_frame
	await physics_frame
	_send_key(KEY_W, false)
	await process_frame
	await physics_frame
	var after_w_state: Dictionary = navigation_overlay.call("edit_state")
	_assert_true(
		_variant_to_cell(after_w_state.get("edit_cursor_cell", Vector2i.ZERO)) == start_cell + Vector2i(0, -1),
		"Runtime navigation edit mode transfers WASD movement to the cursor"
	)
	_assert_vector2_close(player.global_position, start_position, "Runtime navigation edit mode prevents WASD from moving the player")

	_send_key(KEY_RIGHT, true)
	await process_frame
	await physics_frame
	_send_key(KEY_RIGHT, false)
	await process_frame
	await physics_frame
	var after_arrow_state: Dictionary = navigation_overlay.call("edit_state")
	_assert_true(
		_variant_to_cell(after_arrow_state.get("edit_cursor_cell", Vector2i.ZERO)) == start_cell + Vector2i(1, -1),
		"Runtime navigation edit mode transfers arrow-key movement to the cursor"
	)
	_assert_vector2_close(player.global_position, start_position, "Runtime navigation edit mode prevents arrow keys from moving the player")
	navigation_overlay.call("set_navigation_edit_mode", false)


func _validate_navigation_overlay_matches_player_probe(navigation_overlay: Node2D, player: CharacterBody2D) -> void:
	var bounds := _rect2i_from_variant(navigation_overlay.get("navigation_bounds"))
	var start_cell := _variant_to_cell(navigation_overlay.get_meta("grid_navigation_start_cell", Vector2i.ZERO))
	var start_layer := str(navigation_overlay.get_meta("grid_navigation_start_layer", "Layer 1"))
	var probed_cells_by_layer := _compute_player_probe_reachable_cells(player, bounds, start_cell, start_layer)
	var overlay_cells_by_layer: Dictionary = navigation_overlay.get_meta("reachable_cells_by_layer", {})
	var probed_keys := _state_keys(probed_cells_by_layer)
	var overlay_keys := _state_keys(overlay_cells_by_layer)
	var missing_from_overlay := _missing_state_keys(probed_keys, overlay_keys)
	var extra_in_overlay := _missing_state_keys(overlay_keys, probed_keys)
	if not missing_from_overlay.is_empty():
		_failures.append("Overlay is missing player-probed reachable cells: %s" % str(missing_from_overlay.slice(0, mini(8, missing_from_overlay.size()))))
	if not extra_in_overlay.is_empty():
		_failures.append("Overlay shows cells the player probe cannot reach: %s" % str(extra_in_overlay.slice(0, mini(8, extra_in_overlay.size()))))
	_assert_true(missing_from_overlay.is_empty() and extra_in_overlay.is_empty(), "Runtime navigation overlay reachable cells match player step probe tile-by-tile")


func _compute_player_probe_reachable_cells(player: CharacterBody2D, bounds: Rect2i, start_cell: Vector2i, start_layer: String) -> Dictionary:
	var reachable := {}
	var visited := {}
	var queue := []
	_enqueue_probe_cell(queue, visited, reachable, bounds, start_cell, start_layer)
	var queue_index := 0
	while queue_index < queue.size():
		var current: Dictionary = queue[queue_index]
		queue_index += 1
		var from_layer := str(current.get("layer", ""))
		var from_cell: Vector2i = current.get("cell", Vector2i.ZERO)
		for direction_name in GRID_DIRECTIONS:
			var probe: Dictionary = player.call("can_grid_step_from_cell", from_layer, from_cell, direction_name)
			if not bool(probe.get("allowed", false)):
				continue
			var to_layer := str(probe.get("to_layer", from_layer))
			var to_cell := _variant_to_cell(probe.get("to_cell", from_cell))
			_enqueue_probe_cell(queue, visited, reachable, bounds, to_cell, to_layer)
	return reachable


func _enqueue_probe_cell(queue: Array, visited: Dictionary, reachable: Dictionary, bounds: Rect2i, cell: Vector2i, layer_name: String) -> void:
	if not bounds.has_point(cell):
		return
	var key := _state_key(layer_name, cell)
	if visited.has(key):
		return
	visited[key] = true
	queue.append({"layer": layer_name, "cell": cell})
	var cells: Array = reachable.get(layer_name, [])
	cells.append(cell)
	reachable[layer_name] = cells


func _validate_grid_step_contract(player: CharacterBody2D) -> void:
	await _place_player(player, Vector2(128.0, 256.0), "Layer 1")
	var start_position := player.global_position
	await _tap_move(player, KEY_W)
	_assert_vector2_close(player.global_position, start_position + Vector2(0.0, -GRID_CELL_SIZE), "Runtime grid tap moves exactly one north cell")
	_assert_grid_center(player, "Runtime grid tap lands on cell center")

	await _place_player(player, Vector2(128.0, 256.0), "Layer 1")
	_send_key(KEY_W, true)
	for _index in range(GRID_STEP_WAIT_FRAMES * 2):
		await physics_frame
	_send_key(KEY_W, false)
	for _index in range(GRID_STEP_WAIT_FRAMES):
		await physics_frame
	_assert_true(player.global_position.y <= 192.0, "Runtime grid held-key input chains at least two north cells")
	_assert_grid_center(player, "Runtime grid held-key repeat still lands on a cell center")

	var turn_route := _first_two_step_route(player, "Layer 1", "north", "east")
	_assert_true(not turn_route.is_empty(), "Runtime grid validation finds a two-step turn-buffer route")
	if not turn_route.is_empty():
		var start_cell := _variant_to_cell(turn_route.get("start_cell", Vector2i.ZERO))
		var target_cell := _variant_to_cell(turn_route.get("target_cell", Vector2i.ZERO))
		await _place_player(player, _grid_position_for_cell(start_cell), str(turn_route.get("start_layer", "Layer 1")))
		_send_key(KEY_W, true)
		await process_frame
		await physics_frame
		_send_key(KEY_D, true)
		await process_frame
		await physics_frame
		_send_key(KEY_D, false)
		await process_frame
		_send_key(KEY_W, false)
		for _index in range(GRID_STEP_WAIT_FRAMES * 2):
			await physics_frame
		_assert_vector2_close(player.global_position, _grid_position_for_cell(target_cell), "Runtime grid buffers a new turn direction during the current step")
		_assert_grid_center(player, "Runtime grid buffered turn lands on a cell center")


func _first_two_step_route(player: CharacterBody2D, layer_name: String, first_direction: String, second_direction: String) -> Dictionary:
	var navigation_map = player.get("navigation_map")
	if not (navigation_map is Resource):
		return {}
	if not (navigation_map as Resource).has_method("navigable_cells_for_layer"):
		return {}
	for cell_variant in Array((navigation_map as Resource).call("navigable_cells_for_layer", layer_name)):
		var start_cell := _variant_to_cell(cell_variant)
		var first_step: Dictionary = player.call("can_grid_step_from_cell", layer_name, start_cell, first_direction)
		if not bool(first_step.get("allowed", false)):
			continue
		var middle_layer := str(first_step.get("to_layer", layer_name))
		var middle_cell := _variant_to_cell(first_step.get("to_cell", start_cell))
		var second_step: Dictionary = player.call("can_grid_step_from_cell", middle_layer, middle_cell, second_direction)
		if not bool(second_step.get("allowed", false)):
			continue
		return {
			"start_layer": layer_name,
			"start_cell": start_cell,
			"target_layer": str(second_step.get("to_layer", middle_layer)),
			"target_cell": _variant_to_cell(second_step.get("to_cell", middle_cell)),
		}
	return {}


func _validate_north_bridge_spawn_route(player: CharacterBody2D) -> void:
	await _place_player(player, Vector2(186.24, -73.92), "Layer 1")
	for _index in range(6):
		await _tap_move(player, KEY_W)
	_assert_true(player.global_position.y <= -192.0, "Runtime player can enter the north bridge route from the actual Unity spawn")


func _validate_bridge_underpass_probe(player: CharacterBody2D) -> void:
	for cell_y in [8, 7, 6, 5, 4]:
		var probe: Dictionary = player.call("can_grid_step_from_cell", "Layer 1", Vector2i(4, cell_y), "north")
		_assert_true(bool(probe.get("allowed", false)), "South bridge underpass accepts lower-body tile step north from cell y=%d" % cell_y)


func _validate_bridge_underpass_drive(player: CharacterBody2D) -> void:
	await _place_player(player, Vector2(128.0, 250.0), "Layer 1")
	for _index in range(5):
		await _tap_move(player, KEY_W)
	_assert_true(player.global_position.y < 100.0, "Runtime player can push through the south bridge underpass route")


func _validate_south_stairs_ascent(player: CharacterBody2D) -> void:
	await _place_player(player, Vector2(288.0, 64.0), "Layer 1")
	await _tap_move(player, KEY_W)
	for _index in range(4):
		await _tap_move(player, KEY_W)
	var layer_name := _player_runtime_layer(player)
	_assert_true(player.global_position.y <= -64.0, "Runtime player can ascend the south stairs onto the upper platform approach")
	_assert_true(layer_name == "Layer 2", "Runtime player remains on Layer 2 after south stairs ascent")
	_assert_true(player.collision_mask == 2, "Runtime player collides with Layer 2 geometry after south stairs ascent")


func _validate_east_west_stair_transition(player: CharacterBody2D) -> void:
	var edge := _first_horizontal_stair_edge(player)
	_assert_true(not edge.is_empty(), "Runtime player has an east/west stair grid transition edge")
	if edge.is_empty():
		return
	var from_cell := _variant_to_cell(edge.get("from_cell", Vector2i.ZERO))
	var to_cell := _variant_to_cell(edge.get("to_cell", Vector2i.ZERO))
	var direction_name := str(edge.get("direction", ""))
	var waypoints := Array(edge.get("waypoints", []))
	var expected_waypoint := _grid_position_for_cell(from_cell).lerp(_grid_position_for_cell(to_cell), 0.5)
	_assert_true(abs(from_cell.x - to_cell.x) == 1 and abs(from_cell.y - to_cell.y) == 1, "Runtime east/west stair transition connects diagonal grid cells")
	_assert_true(str(edge.get("movement_kind", "")) == "diagonal_stair_waypoint", "Runtime east/west stair transition uses waypoint movement")
	_assert_true(waypoints.size() == 1, "Runtime east/west stair transition stores one visual waypoint")
	if waypoints.size() == 1:
		_assert_vector2_close(_variant_to_position(waypoints[0]), expected_waypoint, "Runtime east/west stair waypoint is centered between the four stair cells")
	_assert_true(is_equal_approx(float(edge.get("layer_switch_t", 0.0)), 0.5), "Runtime east/west stair transition switches layers at the waypoint")
	var target: Dictionary = player.call("grid_step_target", str(edge.get("from_layer", "Layer 1")), from_cell, direction_name)
	_assert_true(Array(target.get("waypoints", [])).size() == 1, "Runtime player exposes stair waypoint through grid_step_target")
	_assert_true(str(target.get("movement_kind", "")) == "diagonal_stair_waypoint", "Runtime player exposes diagonal stair movement kind")
	await _place_player(player, _grid_position_for_cell(from_cell), str(edge.get("from_layer", "Layer 1")))
	_send_key(_key_for_direction(direction_name), true)
	await process_frame
	await physics_frame
	_send_key(_key_for_direction(direction_name), false)
	await process_frame
	var path_payloads := Array(player.get_meta("cainos_grid_step_path_positions", []))
	_assert_true(path_payloads.size() == 3, "Runtime player animates east/west stair step through start, waypoint, and end positions")
	if path_payloads.size() == 3:
		_assert_vector2_close(_variant_to_position(path_payloads[1]), expected_waypoint, "Runtime player path includes stair-center waypoint")
	_assert_true(is_equal_approx(float(player.get_meta("cainos_grid_step_layer_switch_t", 0.0)), 0.5), "Runtime player defers east/west stair layer switch to midpoint")
	for _index in range(GRID_STEP_WAIT_FRAMES):
		await physics_frame
	_assert_vector2_close(player.global_position, _grid_position_for_cell(to_cell), "Runtime player traverses east/west stair transition")
	_assert_true(_player_runtime_layer(player) == str(edge.get("to_layer", "")), "Runtime player changes elevation on east/west stair transition")


func _validate_upper_platform_bounds(player: CharacterBody2D) -> void:
	await _place_player(player, Vector2(288.0, -96.0), "Layer 2")
	for _index in range(6):
		await _tap_move(player, KEY_A)
	_assert_true(player.global_position.x > 220.0, "Runtime Layer 2 walkable region blocks westward off-platform drift")

	await _place_player(player, Vector2(288.0, -96.0), "Layer 2")
	for _index in range(6):
		await _tap_move(player, KEY_D)
	_assert_true(player.global_position.x < 410.0, "Runtime Layer 2 walkable region blocks eastward off-platform drift")
	_assert_grid_center(player, "Runtime upper platform blocker keeps player on cell center")


func _validate_upper_platform_obstacles(player: CharacterBody2D) -> void:
	await _place_player(player, Vector2(288.0, -64.0), "Layer 2")
	var blocked_position := player.global_position
	await _tap_move(player, KEY_W)
	_assert_vector2_close(player.global_position, blocked_position, "Runtime Layer 2 grid blockers prevent walking through the bush north of south stairs")

	await _place_player(player, Vector2(288.0, -64.0), "Layer 2")
	await _tap_move(player, KEY_D)
	var ledge_guard_position := player.global_position
	await _tap_move(player, KEY_D)
	_assert_vector2_close(player.global_position, ledge_guard_position, "Runtime Layer 2 grid blockers prevent walking through upper-platform ledges")

	await _place_player(player, Vector2(288.0, -160.0), "Layer 2")
	var stair_top_position := player.global_position
	await _tap_move(player, KEY_D)
	_assert_vector2_close(player.global_position, stair_top_position, "Runtime side-stair support does not create an upper ledge corridor")

	await _place_player(player, _grid_position_for_cell(Vector2i(5, -15)), "Layer 1")
	var lower_side_stair_position := player.global_position
	await _tap_move(player, KEY_A)
	_assert_vector2_close(player.global_position, lower_side_stair_position, "Runtime grid blocks lateral Layer 1 access onto upper stair landing")
	_assert_true(_player_runtime_layer(player) == "Layer 1", "Runtime legacy stair triggers do not override grid-map layer authority")

	var scene_root := player.get_parent()
	var lower_crate := scene_root.get_node_or_null("SceneInstance/SC Demo/Prefabs/Layer 1/Props/PF Props - Crate 01") as RigidBody2D
	_assert_true(lower_crate != null, "Runtime scene includes lower-elevation crate near south stairs")
	if lower_crate == null:
		return
	var crate_position := lower_crate.global_position
	await _place_player(player, Vector2(288.0, -128.0), "Layer 2")
	for _index in range(8):
		await physics_frame
	_assert_vector2_close(lower_crate.global_position, crate_position, "Runtime Layer 2 player does not physically push Layer 1 crate")


func _validate_bridge_occluders(scene: Node) -> void:
	for path in [
		"SceneInstance/SC Demo/Prefabs/Layer 1/Props/PF Struct - Gate 01/TX Struct Bridge Gate B/TX Struct Bridge Gate B Sprite",
		"SceneInstance/SC Demo/Prefabs/Layer 1/Props/PF Props - Wooden Gate 01/PF Props - Wooden Gate 01 Sprite",
	]:
		var sprite := scene.get_node_or_null(path) as Sprite2D
		_assert_true(sprite != null, "Runtime bridge occluder sprite exists: %s" % path)
		if sprite == null:
			continue
		_assert_true(bool(sprite.get_meta("cainos_foreground_occluder", false)), "Runtime bridge sprite is tagged as foreground occluder: %s" % path)
		_assert_true(sprite.z_index > 2, "Runtime bridge sprite renders above lower-elevation player: %s" % path)


func _send_key(keycode: Key, pressed: bool, unicode_codepoint := 0, shift_pressed := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.unicode = unicode_codepoint
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	Input.parse_input_event(event)


func _tap_move(player: CharacterBody2D, keycode: Key) -> void:
	_send_key(keycode, true)
	await process_frame
	await physics_frame
	await physics_frame
	_send_key(keycode, false)
	await process_frame
	for _index in range(GRID_STEP_WAIT_FRAMES):
		await physics_frame
	_assert_grid_center(player, "Runtime grid movement ends centered after key tap")


func _place_player(player: CharacterBody2D, position: Vector2, layer_name: String) -> void:
	_release_movement_keys()
	player.global_position = position
	player.velocity = Vector2.ZERO
	_apply_player_runtime_layer(player, layer_name)
	await physics_frame
	_release_movement_keys()
	await physics_frame


func _release_movement_keys() -> void:
	for keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
		_send_key(keycode, false)


func _apply_player_runtime_layer(player: CharacterBody2D, layer_name: String) -> void:
	var player_root := player.get_node_or_null("PF Player")
	if player_root == null:
		return
	var helper := player_root.get_node_or_null("CainosRuntimeActor2D")
	if helper != null and helper.has_method("apply_runtime_layer"):
		helper.call("apply_runtime_layer", layer_name, layer_name)


func _player_runtime_layer(player: CharacterBody2D) -> String:
	var player_root := player.get_node_or_null("PF Player")
	if player_root == null:
		return ""
	return str(player_root.get_meta("cainos_runtime_layer_name", ""))


func _first_horizontal_stair_edge(player: CharacterBody2D) -> Dictionary:
	for edge_variant in Array(player.get("grid_transition_edges")):
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var direction_name := str(edge.get("direction", ""))
		if (direction_name == "east" or direction_name == "west") and str(edge.get("movement_kind", "")) == "diagonal_stair_waypoint":
			return edge
	return {}


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
	return Vector2i.ZERO


func _variant_to_position(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		var vector_value: Vector2i = value
		return Vector2(vector_value)
	if value is Dictionary:
		var dict_value: Dictionary = value
		return Vector2(float(dict_value.get("x", 0.0)), float(dict_value.get("y", 0.0)))
	if value is Array:
		var array_value: Array = value
		if array_value.size() >= 2:
			return Vector2(float(array_value[0]), float(array_value[1]))
	return Vector2.ZERO


func _cell_array_has_cell(cells, expected_cell: Vector2i) -> bool:
	if not (cells is Array):
		return false
	for cell_variant in cells:
		if _variant_to_cell(cell_variant) == expected_cell:
			return true
	return false


func _runtime_player_footprint_shape(node: Node) -> CollisionShape2D:
	if node is CollisionShape2D and bool(node.get_meta("cainos_runtime_player_footprint", false)):
		return node as CollisionShape2D
	for child in node.get_children():
		var found := _runtime_player_footprint_shape(child)
		if found != null:
			return found
	return null


func _rect2i_from_variant(value) -> Rect2i:
	if value is Rect2i:
		return value
	if value is Rect2:
		var rect: Rect2 = value
		return Rect2i(roundi(rect.position.x), roundi(rect.position.y), roundi(rect.size.x), roundi(rect.size.y))
	if value is Dictionary:
		var dict_value: Dictionary = value
		var position := _variant_to_cell(dict_value.get("position", Vector2i.ZERO))
		var size := _variant_to_cell(dict_value.get("size", Vector2i.ZERO))
		return Rect2i(position, size)
	return Rect2i()


func _state_keys(cells_by_layer: Dictionary) -> Array:
	var keys := []
	for layer_name in LAYER_NAMES:
		for cell_variant in Array(cells_by_layer.get(layer_name, [])):
			keys.append(_state_key(layer_name, _variant_to_cell(cell_variant)))
	keys.sort()
	return keys


func _state_key(layer_name: String, cell: Vector2i) -> String:
	return "%s:%d,%d" % [layer_name, cell.x, cell.y]


func _missing_state_keys(expected: Array, actual: Array) -> Array:
	var actual_set := {}
	for key_variant in actual:
		actual_set[str(key_variant)] = true
	var missing := []
	for key_variant in expected:
		var key := str(key_variant)
		if not actual_set.has(key):
			missing.append(key)
	return missing


func _grid_position_for_cell(cell: Vector2i) -> Vector2:
	return Vector2(cell) * GRID_CELL_SIZE


func _key_for_direction(direction_name: String) -> Key:
	match direction_name:
		"north":
			return KEY_W
		"south":
			return KEY_S
		"east":
			return KEY_D
		"west":
			return KEY_A
		_:
			return KEY_W


func _script_path(node: Node) -> String:
	var script = node.get_script()
	if script == null:
		return ""
	return str(script.resource_path)


func _assert_grid_center(player: CharacterBody2D, message: String) -> void:
	var cell := Vector2i(roundi(player.global_position.x / GRID_CELL_SIZE), roundi(player.global_position.y / GRID_CELL_SIZE))
	_assert_vector2_close(player.global_position, _grid_position_for_cell(cell), message)


func _assert_true(value: bool, message: String) -> void:
	if value:
		print("PASS: %s" % message)
	else:
		print("FAIL: %s" % message)
		_failures.append(message)


func _assert_vector2_close(actual: Vector2, expected: Vector2, message: String, epsilon := 0.01) -> void:
	if actual.distance_to(expected) <= epsilon:
		print("PASS: %s" % message)
	else:
		print("FAIL: %s" % message)
		_failures.append("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("All real-pack runtime navigation checks passed.")
		quit(0)
	else:
		push_error("Real-pack runtime navigation validation failed with %d issue(s)." % _failures.size())
		for failure in _failures:
			push_error(" - %s" % failure)
		quit(1)
