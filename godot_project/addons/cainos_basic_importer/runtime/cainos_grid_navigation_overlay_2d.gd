extends Node2D

const LAYER_NAMES := ["Layer 1", "Layer 2", "Layer 3"]
const DIRECTIONS := ["north", "south", "east", "west"]
const OVERRIDE_NONE := "none"
const OVERRIDE_FORCE_NAVIGABLE := "force_navigable"
const OVERRIDE_FORCE_BLOCKED := "force_blocked"

@export var player_path: NodePath = ^"../RuntimePlayer"
@export var navigation_map: Resource
@export var navigation_bounds := Rect2i()
@export var max_reachable_cells := 20000
@export var show_layer_1 := true
@export var show_layer_2 := true
@export var show_layer_3 := true
@export var layer_1_color := Color(1.0, 0.48, 0.0, 0.34)
@export var layer_2_color := Color(0.0, 0.72, 1.0, 0.34)
@export var layer_3_color := Color(1.0, 0.0, 0.85, 0.34)
@export var transition_outline_color := Color(1.0, 1.0, 1.0, 0.65)
@export var edit_mode_enabled := false
@export var edit_layer_name := "Layer 1"
@export var edit_cursor_cell := Vector2i.ZERO
@export var forced_navigable_color := Color(1.0, 0.92, 0.0, 0.38)
@export var forced_navigable_outline_color := Color(1.0, 0.95, 0.0, 0.9)
@export var forced_blocked_color := Color(1.0, 0.05, 0.0, 0.72)
@export var edit_cursor_color := Color(1.0, 0.48, 0.0, 1.0)

var _reachable_cells_by_layer := {}
var _map_cells_by_layer := {}
var _forced_navigable_cells_by_layer := {}
var _forced_blocked_cells_by_layer := {}
var _transition_cells_by_layer := {}
var _grid_origin := Vector2.ZERO
var _grid_cell_size := 32.0


func _ready() -> void:
	set_meta("cainos_grid_navigation_overlay", true)
	set_process_unhandled_input(true)
	z_as_relative = false
	z_index = 4096
	_publish_visibility_metadata()
	call_deferred("rebuild_navigation_overlay")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed:
		return
	var keycode := _keycode_for_event(key_event)
	if keycode == KEY_N:
		toggle_navigation_edit_mode()
		get_viewport().set_input_as_handled()
		return
	if edit_mode_enabled and _handle_edit_key(key_event):
		get_viewport().set_input_as_handled()
		return
	var layer_name := _layer_name_for_key_event(key_event)
	if layer_name.is_empty():
		return
	var result := toggle_layer_visibility(layer_name)
	if bool(result.get("ok", false)):
		get_viewport().set_input_as_handled()


func rebuild_navigation_overlay() -> Dictionary:
	var player := get_node_or_null(player_path)
	if player == null:
		_reachable_cells_by_layer = {}
		_map_cells_by_layer = {}
		_transition_cells_by_layer = {}
		_publish_overlay_metadata(Rect2i(), Vector2i.ZERO, "")
		queue_redraw()
		return _overlay_result(false, "Runtime player not found.")

	var active_map := _active_navigation_map(player)
	var has_active_map := _has_navigation_map(active_map)
	if has_active_map:
		_grid_origin = Vector2(active_map.get("grid_origin"))
		_grid_cell_size = maxf(float(active_map.get("grid_cell_size")), 1.0)
	else:
		_grid_origin = Vector2(player.get("grid_origin"))
		_grid_cell_size = maxf(float(player.get("grid_cell_size")), 1.0)
	var bounds := navigation_bounds
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		if has_active_map:
			bounds = Rect2i(active_map.get("bounds"))
		else:
			bounds = Rect2i(player.get("grid_navigation_bounds"))
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		bounds = _infer_bounds_from_player_data(player)

	var start_cell := Vector2i.ZERO
	if has_active_map:
		start_cell = active_map.call("grid_cell_for_position", (player as Node2D).global_position) as Vector2i
	else:
		start_cell = player.call("grid_cell_for_position", (player as Node2D).global_position) as Vector2i
	var start_layer := str(player.get("current_collision_layer_name"))
	if has_active_map:
		_map_cells_by_layer = _collect_map_cells(active_map, bounds)
		_forced_navigable_cells_by_layer = _collect_forced_cells(active_map, "forced_navigable_cells_for_layer")
		_forced_blocked_cells_by_layer = _collect_forced_cells(active_map, "forced_blocked_cells_for_layer")
		_reachable_cells_by_layer = Dictionary(active_map.call("reachable_cells_from", start_layer, start_cell, max_reachable_cells))
		_transition_cells_by_layer = Dictionary(active_map.call("transition_cells_by_layer"))
	else:
		_map_cells_by_layer = {}
		_forced_navigable_cells_by_layer = {}
		_forced_blocked_cells_by_layer = {}
		_reachable_cells_by_layer = _compute_reachable_cells(player, bounds, start_cell, start_layer)
		_transition_cells_by_layer = _collect_transition_cells(player, bounds)
	_publish_overlay_metadata(bounds, start_cell, start_layer)
	queue_redraw()
	return _overlay_result(true, "")


func is_cell_reachable(cell: Vector2i, layer_name: String) -> bool:
	for cell_variant in _reachable_cells_by_layer.get(layer_name, []):
		if _variant_to_cell(cell_variant) == cell:
			return true
	return false


func reachable_cells_for_layer(layer_name: String) -> Array:
	return Array(_reachable_cells_by_layer.get(layer_name, [])).duplicate()


func reachable_cell_counts_by_layer() -> Dictionary:
	return _reachable_cell_counts()


func map_cells_for_layer(layer_name: String) -> Array:
	return Array(_map_cells_by_layer.get(layer_name, [])).duplicate()


func map_cell_counts_by_layer() -> Dictionary:
	return _map_cell_counts()


func navigation_debug_report() -> Dictionary:
	var player := get_node_or_null(player_path)
	if player == null:
		return {
			"ok": false,
			"error": "Runtime player not found.",
		}
	var active_map := _active_navigation_map(player)
	if not _has_navigation_map(active_map):
		return {
			"ok": false,
			"error": "Runtime navigation map not found.",
		}
	var start_cell := active_map.call("grid_cell_for_position", (player as Node2D).global_position) as Vector2i
	var start_layer := str(player.get("current_collision_layer_name"))
	if active_map.has_method("navigation_debug_report"):
		return Dictionary(active_map.call("navigation_debug_report", start_layer, start_cell, max_reachable_cells))
	return {
		"ok": false,
		"error": "Runtime navigation map does not expose navigation_debug_report().",
	}


func toggle_navigation_edit_mode() -> Dictionary:
	return set_navigation_edit_mode(not edit_mode_enabled)


func set_navigation_edit_mode(is_enabled: bool) -> Dictionary:
	edit_mode_enabled = is_enabled
	_set_player_movement_input_suppressed(edit_mode_enabled)
	if edit_mode_enabled:
		snap_edit_cursor_to_player()
	_publish_edit_metadata()
	queue_redraw()
	return edit_state()


func edit_state() -> Dictionary:
	return {
		"ok": true,
		"edit_mode_enabled": edit_mode_enabled,
		"edit_layer_name": edit_layer_name,
		"edit_cursor_cell": _cell_payload(edit_cursor_cell),
		"cursor_override_state": cell_override_state(edit_layer_name, edit_cursor_cell),
		"cursor_override_states_by_layer": cell_override_states(edit_cursor_cell),
	}


func set_edit_layer(layer_name: String) -> Dictionary:
	var normalized := _normalize_layer_name(layer_name)
	if normalized.is_empty():
		return {"ok": false, "error": "Unknown navigation layer: %s" % layer_name}
	edit_layer_name = normalized
	_publish_edit_metadata()
	queue_redraw()
	return edit_state()


func set_edit_cursor_cell(cell_variant) -> Dictionary:
	edit_cursor_cell = _variant_to_cell(cell_variant)
	_publish_edit_metadata()
	queue_redraw()
	return edit_state()


func snap_edit_cursor_to_player() -> Dictionary:
	var player := get_node_or_null(player_path)
	if player == null:
		return {"ok": false, "error": "Runtime player not found."}
	var active_map := _active_navigation_map(player)
	if _has_navigation_map(active_map):
		edit_cursor_cell = active_map.call("grid_cell_for_position", (player as Node2D).global_position) as Vector2i
	else:
		edit_cursor_cell = player.call("grid_cell_for_position", (player as Node2D).global_position) as Vector2i
	edit_layer_name = str(player.get("current_collision_layer_name"))
	_publish_edit_metadata()
	queue_redraw()
	return edit_state()


func set_cell_override(layer_name: String, cell_variant, state: String) -> Dictionary:
	var active_map := _editable_navigation_map()
	if not _has_navigation_map(active_map):
		return {"ok": false, "error": "Runtime navigation map not found."}
	if not active_map.has_method("set_cell_override"):
		return {"ok": false, "error": "Runtime navigation map does not support overrides."}
	var result := Dictionary(active_map.call("set_cell_override", layer_name, _variant_to_cell(cell_variant), state))
	if bool(result.get("ok", false)):
		rebuild_navigation_overlay()
	return result


func clear_cell_override(layer_name: String, cell_variant) -> Dictionary:
	var active_map := _editable_navigation_map()
	if not _has_navigation_map(active_map):
		return {"ok": false, "error": "Runtime navigation map not found."}
	if not active_map.has_method("clear_cell_override"):
		return {"ok": false, "error": "Runtime navigation map does not support overrides."}
	var result := Dictionary(active_map.call("clear_cell_override", layer_name, _variant_to_cell(cell_variant)))
	if bool(result.get("ok", false)):
		rebuild_navigation_overlay()
	return result


func cell_override_state(layer_name: String, cell_variant) -> String:
	var active_map := _editable_navigation_map()
	if not _has_navigation_map(active_map) or not active_map.has_method("cell_override_state"):
		return OVERRIDE_NONE
	return str(active_map.call("cell_override_state", layer_name, _variant_to_cell(cell_variant)))


func cell_override_states(cell_variant) -> Dictionary:
	var states := {}
	for layer_name in LAYER_NAMES:
		states[layer_name] = cell_override_state(layer_name, cell_variant)
	return states


func save_navigation_overrides() -> Dictionary:
	var active_map := _editable_navigation_map()
	if not _has_navigation_map(active_map):
		return {"ok": false, "error": "Runtime navigation map not found."}
	if not active_map.has_method("save_navigation_overrides"):
		return {"ok": false, "error": "Runtime navigation map does not support override saving."}
	return Dictionary(active_map.call("save_navigation_overrides"))


func is_layer_visible(layer_name: String) -> bool:
	var normalized := _normalize_layer_name(layer_name)
	return not normalized.is_empty() and _is_layer_visible(normalized)


func set_layer_visible(layer_name: String, is_visible: bool) -> Dictionary:
	var normalized := _normalize_layer_name(layer_name)
	if normalized.is_empty():
		return {
			"ok": false,
			"error": "Unknown navigation layer: %s" % layer_name,
			"visible_layers_by_layer": _layer_visibility_by_layer(),
		}
	_set_normalized_layer_visible(normalized, is_visible)
	_publish_visibility_metadata()
	queue_redraw()
	return {
		"ok": true,
		"layer": normalized,
		"visible": is_visible,
		"visible_layers_by_layer": _layer_visibility_by_layer(),
	}


func toggle_layer_visibility(layer_name: String) -> Dictionary:
	var normalized := _normalize_layer_name(layer_name)
	if normalized.is_empty():
		return {
			"ok": false,
			"error": "Unknown navigation layer: %s" % layer_name,
			"visible_layers_by_layer": _layer_visibility_by_layer(),
		}
	return set_layer_visible(normalized, not _is_layer_visible(normalized))


func _draw() -> void:
	var cells_to_draw := _map_cells_by_layer if not _map_cells_by_layer.is_empty() else _reachable_cells_by_layer
	for layer_name in LAYER_NAMES:
		if not _is_layer_visible(layer_name):
			continue
		var color := _layer_color(layer_name)
		for cell_variant in cells_to_draw.get(layer_name, []):
			draw_rect(_cell_rect(_variant_to_cell(cell_variant)), color, true)
	for layer_name in LAYER_NAMES:
		if not _is_layer_visible(layer_name):
			continue
		for cell_variant in _transition_cells_by_layer.get(layer_name, []):
			draw_rect(_cell_rect(_variant_to_cell(cell_variant)).grow(-2.0), transition_outline_color, false, 2.0)
	for layer_name in LAYER_NAMES:
		if not _is_layer_visible(layer_name):
			continue
		for cell_variant in _forced_navigable_cells_by_layer.get(layer_name, []):
			var rect := _cell_rect(_variant_to_cell(cell_variant)).grow(-3.0)
			draw_rect(rect, forced_navigable_color, true)
			draw_rect(rect, forced_navigable_outline_color, false, 2.0)
		for cell_variant in _forced_blocked_cells_by_layer.get(layer_name, []):
			_draw_forced_blocked_cell(_variant_to_cell(cell_variant), layer_name)
	if edit_mode_enabled and _is_layer_visible(edit_layer_name):
		_draw_edit_cursor()


func _compute_reachable_cells(player: Node, bounds: Rect2i, start_cell: Vector2i, start_layer: String) -> Dictionary:
	var reachable := {}
	var visited := {}
	var queue := []
	_enqueue_reachable_cell(queue, visited, reachable, bounds, start_cell, start_layer)
	var queue_index := 0
	while queue_index < queue.size() and visited.size() < max_reachable_cells:
		var current: Dictionary = queue[queue_index]
		queue_index += 1
		var from_layer := str(current.get("layer", ""))
		var from_cell: Vector2i = current.get("cell", Vector2i.ZERO)
		for direction_name in DIRECTIONS:
			var target: Dictionary = player.call("can_grid_step_from_cell", from_layer, from_cell, direction_name)
			if not bool(target.get("allowed", false)):
				continue
			var to_layer := str(target.get("to_layer", from_layer))
			var to_cell := _variant_to_cell(target.get("to_cell", from_cell))
			if not bounds.has_point(to_cell):
				continue
			_enqueue_reachable_cell(queue, visited, reachable, bounds, to_cell, to_layer)
	return _sorted_cells_by_layer(reachable)


func _enqueue_reachable_cell(queue: Array, visited: Dictionary, reachable: Dictionary, bounds: Rect2i, cell: Vector2i, layer_name: String) -> void:
	if not bounds.has_point(cell):
		return
	var key := _cell_key(layer_name, cell)
	if visited.has(key):
		return
	visited[key] = true
	queue.append({"layer": layer_name, "cell": cell})
	var cells: Array = reachable.get(layer_name, [])
	cells.append(cell)
	reachable[layer_name] = cells


func _sorted_cells_by_layer(cells_by_layer: Dictionary) -> Dictionary:
	var result := {}
	for layer_name in LAYER_NAMES:
		var cells: Array = cells_by_layer.get(layer_name, [])
		cells.sort_custom(Callable(self, "_sort_cells_ascending"))
		result[layer_name] = cells
	return result


func _sort_cells_ascending(left, right) -> bool:
	var left_cell := _variant_to_cell(left)
	var right_cell := _variant_to_cell(right)
	if left_cell.y == right_cell.y:
		return left_cell.x < right_cell.x
	return left_cell.y < right_cell.y


func _collect_transition_cells(player: Node, bounds: Rect2i) -> Dictionary:
	var cells_by_layer := {}
	for edge_variant in Array(player.get("grid_transition_edges")):
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		for endpoint_name in ["from", "to"]:
			var layer_name := str(edge.get("%s_layer" % endpoint_name, ""))
			var cell := _variant_to_cell(edge.get("%s_cell" % endpoint_name, Vector2i.ZERO))
			if layer_name.is_empty() or not bounds.has_point(cell):
				continue
			var cells: Array = cells_by_layer.get(layer_name, [])
			if not _cell_array_has(cells, cell):
				cells.append(cell)
			cells_by_layer[layer_name] = cells
	return _sorted_cells_by_layer(cells_by_layer)


func _infer_bounds_from_player_data(player: Node) -> Rect2i:
	var has_bounds := false
	var min_cell := Vector2i.ZERO
	var max_cell := Vector2i.ZERO
	var active_map := _active_navigation_map(player)
	if _has_navigation_map(active_map):
		for layer_name in LAYER_NAMES:
			for cell_variant in Array(active_map.call("navigable_cells_for_layer", layer_name)):
				var cell := _variant_to_cell(cell_variant)
				if not has_bounds:
					min_cell = cell
					max_cell = cell
					has_bounds = true
				else:
					min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
					max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	for edge_variant in Array(player.get("grid_transition_edges")):
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		for cell_key in ["from_cell", "to_cell"]:
			var cell := _variant_to_cell(edge.get(cell_key, Vector2i.ZERO))
			if not has_bounds:
				min_cell = cell
				max_cell = cell
				has_bounds = true
			else:
				min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
				max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	for layer_name in LAYER_NAMES:
		for cell_variant in Array(Dictionary(player.get("grid_blocked_cells_by_layer")).get(layer_name, [])):
			var cell := _variant_to_cell(cell_variant)
			if not has_bounds:
				min_cell = cell
				max_cell = cell
				has_bounds = true
			else:
				min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
				max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	if not has_bounds:
		var start_cell := player.call("grid_cell_for_position", (player as Node2D).global_position) as Vector2i
		min_cell = start_cell - Vector2i(20, 20)
		max_cell = start_cell + Vector2i(20, 20)
	return Rect2i(min_cell - Vector2i.ONE, max_cell - min_cell + Vector2i(3, 3))


func _publish_overlay_metadata(bounds: Rect2i, start_cell: Vector2i, start_layer: String) -> void:
	set_meta("grid_navigation_bounds", _rect2i_payload(bounds))
	set_meta("grid_navigation_start_cell", start_cell)
	set_meta("grid_navigation_start_layer", start_layer)
	set_meta("navigation_map_cells_by_layer", _map_cells_by_layer)
	set_meta("navigation_map_cell_counts_by_layer", _map_cell_counts())
	set_meta("forced_navigable_cells_by_layer", _forced_navigable_cells_by_layer)
	set_meta("forced_blocked_cells_by_layer", _forced_blocked_cells_by_layer)
	set_meta("reachable_cells_by_layer", _reachable_cells_by_layer)
	set_meta("reachable_cell_counts_by_layer", _reachable_cell_counts())
	set_meta("transition_cells_by_layer", _transition_cells_by_layer)
	set_meta("navigation_overlay_colors", {
		"Layer 1": layer_1_color,
		"Layer 2": layer_2_color,
		"Layer 3": layer_3_color,
	})
	set_meta("forced_blocked_marker_colors", _forced_blocked_marker_colors())
	_publish_visibility_metadata()
	_publish_edit_metadata()


func _publish_visibility_metadata() -> void:
	set_meta("visible_layers_by_layer", _layer_visibility_by_layer())
	set_meta("visible_navigation_layers", _visible_layer_names())


func _reachable_cell_counts() -> Dictionary:
	var counts := {}
	for layer_name in LAYER_NAMES:
		counts[layer_name] = Array(_reachable_cells_by_layer.get(layer_name, [])).size()
	return counts


func _map_cell_counts() -> Dictionary:
	var counts := {}
	for layer_name in LAYER_NAMES:
		counts[layer_name] = Array(_map_cells_by_layer.get(layer_name, [])).size()
	return counts


func _overlay_result(ok: bool, error: String) -> Dictionary:
	var result := {
		"ok": ok,
		"navigation_map_cell_counts_by_layer": _map_cell_counts(),
		"reachable_cell_counts_by_layer": _reachable_cell_counts(),
		"edit_state": edit_state(),
	}
	if not error.is_empty():
		result["error"] = error
	return result


func _cell_rect(cell: Vector2i) -> Rect2:
	var center := _grid_origin + Vector2(cell) * _grid_cell_size
	var half_size := Vector2(_grid_cell_size, _grid_cell_size) * 0.5
	return Rect2(center - half_size, half_size * 2.0)


func _active_navigation_map(player: Node) -> Resource:
	if _has_navigation_map(navigation_map):
		return navigation_map
	var player_map = player.get("navigation_map")
	if player_map is Resource and _has_navigation_map(player_map):
		return player_map
	return null


func _editable_navigation_map() -> Resource:
	var player := get_node_or_null(player_path)
	if player == null:
		return navigation_map if _has_navigation_map(navigation_map) else null
	return _active_navigation_map(player)


func _has_navigation_map(candidate) -> bool:
	return candidate is Resource and candidate.has_method("can_step")


func _collect_map_cells(map_resource: Resource, bounds: Rect2i) -> Dictionary:
	var cells_by_layer := {}
	for layer_name in LAYER_NAMES:
		var cells := []
		for cell_variant in Array(map_resource.call("navigable_cells_for_layer", layer_name)):
			var cell := _variant_to_cell(cell_variant)
			if bounds.size.x > 0 and bounds.size.y > 0 and not bounds.has_point(cell):
				continue
			cells.append(cell)
		cells_by_layer[layer_name] = cells
	return _sorted_cells_by_layer(cells_by_layer)


func _collect_forced_cells(map_resource: Resource, method_name: String) -> Dictionary:
	var cells_by_layer := {}
	for layer_name in LAYER_NAMES:
		if map_resource.has_method(method_name):
			cells_by_layer[layer_name] = Array(map_resource.call(method_name, layer_name))
		else:
			cells_by_layer[layer_name] = []
	return _sorted_cells_by_layer(cells_by_layer)


func _handle_edit_key(key_event: InputEventKey) -> bool:
	var keycode := _keycode_for_event(key_event)
	var movement_delta := _edit_cursor_delta_for_keycode(keycode)
	if movement_delta != Vector2i.ZERO:
		_move_edit_cursor(movement_delta)
		return true
	match keycode:
		KEY_I:
			_move_edit_cursor(Vector2i(0, -1))
			return true
		KEY_K:
			_move_edit_cursor(Vector2i(0, 1))
			return true
		KEY_J:
			_move_edit_cursor(Vector2i(-1, 0))
			return true
		KEY_L:
			_move_edit_cursor(Vector2i(1, 0))
			return true
		KEY_Q:
			_cycle_edit_layer(-1)
			return true
		KEY_E:
			_cycle_edit_layer(1)
			return true
		KEY_F, KEY_INSERT:
			set_cell_override(edit_layer_name, edit_cursor_cell, OVERRIDE_FORCE_NAVIGABLE)
			return true
		KEY_B, KEY_DELETE:
			set_cell_override(edit_layer_name, edit_cursor_cell, OVERRIDE_FORCE_BLOCKED)
			return true
		KEY_C:
			clear_cell_override(edit_layer_name, edit_cursor_cell)
			return true
		KEY_V:
			save_navigation_overrides()
			return true
		KEY_G:
			snap_edit_cursor_to_player()
			return true
		_:
			return false


func _edit_cursor_delta_for_keycode(keycode: Key) -> Vector2i:
	match keycode:
		KEY_W, KEY_UP:
			return Vector2i(0, -1)
		KEY_S, KEY_DOWN:
			return Vector2i(0, 1)
		KEY_A, KEY_LEFT:
			return Vector2i(-1, 0)
		KEY_D, KEY_RIGHT:
			return Vector2i(1, 0)
		_:
			return Vector2i.ZERO


func _move_edit_cursor(delta: Vector2i) -> void:
	edit_cursor_cell += delta
	_publish_edit_metadata()
	queue_redraw()


func _cycle_edit_layer(delta: int) -> void:
	var index := LAYER_NAMES.find(edit_layer_name)
	if index < 0:
		index = 0
	index = posmod(index + delta, LAYER_NAMES.size())
	edit_layer_name = LAYER_NAMES[index]
	_publish_edit_metadata()
	queue_redraw()


func _draw_forced_blocked_cell(cell: Vector2i, layer_name: String) -> void:
	var rect := _cell_rect(cell).grow(-4.0)
	var marker_color := _opaque_layer_color(layer_name)
	var fill_color := marker_color
	fill_color.a = 0.16
	draw_rect(rect, fill_color, true)
	var offset := _forced_blocked_marker_offset(cell, layer_name)
	var shadow_color := Color(0.0, 0.0, 0.0, 0.92)
	draw_line(rect.position + offset, rect.end + offset, shadow_color, 6.0)
	draw_line(Vector2(rect.end.x, rect.position.y) + offset, Vector2(rect.position.x, rect.end.y) + offset, shadow_color, 6.0)
	draw_line(rect.position + offset, rect.end + offset, marker_color, 3.0)
	draw_line(Vector2(rect.end.x, rect.position.y) + offset, Vector2(rect.position.x, rect.end.y) + offset, marker_color, 3.0)


func _draw_edit_cursor() -> void:
	var rect := _cell_rect(edit_cursor_cell).grow(-1.0)
	var center := rect.get_center()
	var cursor_color := _edit_cursor_color()
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.88), false, 6.0)
	draw_rect(rect, cursor_color, false, 3.0)
	draw_line(Vector2(center.x, rect.position.y), Vector2(center.x, rect.end.y), Color(0.0, 0.0, 0.0, 0.88), 5.0)
	draw_line(Vector2(rect.position.x, center.y), Vector2(rect.end.x, center.y), Color(0.0, 0.0, 0.0, 0.88), 5.0)
	draw_line(Vector2(center.x, rect.position.y), Vector2(center.x, rect.end.y), cursor_color, 2.0)
	draw_line(Vector2(rect.position.x, center.y), Vector2(rect.end.x, center.y), cursor_color, 2.0)


func _is_layer_visible(layer_name: String) -> bool:
	match layer_name:
		"Layer 1":
			return show_layer_1
		"Layer 2":
			return show_layer_2
		"Layer 3":
			return show_layer_3
		_:
			return false


func _set_normalized_layer_visible(layer_name: String, is_visible: bool) -> void:
	match layer_name:
		"Layer 1":
			show_layer_1 = is_visible
		"Layer 2":
			show_layer_2 = is_visible
		"Layer 3":
			show_layer_3 = is_visible


func _layer_visibility_by_layer() -> Dictionary:
	var visibility := {}
	for layer_name in LAYER_NAMES:
		visibility[layer_name] = _is_layer_visible(layer_name)
	return visibility


func _visible_layer_names() -> Array[String]:
	var visible_layers: Array[String] = []
	for layer_name in LAYER_NAMES:
		if _is_layer_visible(layer_name):
			visible_layers.append(layer_name)
	return visible_layers


func _publish_edit_metadata() -> void:
	edit_cursor_color = _edit_cursor_color()
	set_meta("navigation_edit_mode_enabled", edit_mode_enabled)
	set_meta("navigation_edit_layer_name", edit_layer_name)
	set_meta("navigation_edit_cursor_cell", edit_cursor_cell)
	set_meta("navigation_edit_cursor_color", edit_cursor_color)
	set_meta("navigation_edit_cursor_override_state", cell_override_state(edit_layer_name, edit_cursor_cell))
	set_meta("navigation_edit_cursor_override_states_by_layer", cell_override_states(edit_cursor_cell))


func _set_player_movement_input_suppressed(is_suppressed: bool) -> void:
	var player := get_node_or_null(player_path)
	if player == null:
		return
	if player.has_method("set_movement_input_suppressed"):
		player.call("set_movement_input_suppressed", is_suppressed)
	else:
		player.set("movement_input_suppressed", is_suppressed)


func _layer_name_for_key_event(key_event: InputEventKey) -> String:
	var digit := _digit_for_key_event(key_event)
	if digit <= 0:
		return ""
	return _normalize_layer_name(str(digit))


func _digit_for_key_event(key_event: InputEventKey) -> int:
	var codepoint := int(key_event.unicode)
	if codepoint >= 49 and codepoint <= 57:
		return codepoint - 48
	var keycode := int(key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode)
	if keycode >= int(KEY_1) and keycode <= int(KEY_9):
		return keycode - int(KEY_0)
	return 0


func _keycode_for_event(key_event: InputEventKey) -> Key:
	return key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode


func _normalize_layer_name(layer_name: String) -> String:
	var trimmed := layer_name.strip_edges()
	if LAYER_NAMES.has(trimmed):
		return trimmed
	if trimmed.is_valid_int():
		var candidate := "Layer %d" % int(trimmed)
		if LAYER_NAMES.has(candidate):
			return candidate
	return ""


func _layer_color(layer_name: String) -> Color:
	match layer_name:
		"Layer 1":
			return layer_1_color
		"Layer 2":
			return layer_2_color
		"Layer 3":
			return layer_3_color
		_:
			return Color(1.0, 1.0, 1.0, 0.3)


func _opaque_layer_color(layer_name: String) -> Color:
	var color := _layer_color(layer_name)
	color.a = 1.0
	return color


func _edit_cursor_color() -> Color:
	return _opaque_layer_color(edit_layer_name)


func _forced_blocked_marker_colors() -> Dictionary:
	var colors := {}
	for layer_name in LAYER_NAMES:
		colors[layer_name] = _opaque_layer_color(layer_name)
	return colors


func _forced_blocked_marker_offset(cell: Vector2i, layer_name: String) -> Vector2:
	var visible_blocked_layers := _forced_blocked_visible_layers_for_cell(cell)
	if visible_blocked_layers.size() <= 1:
		return Vector2.ZERO
	var index := visible_blocked_layers.find(layer_name)
	if index < 0:
		return Vector2.ZERO
	var centered_index := float(index) - float(visible_blocked_layers.size() - 1) * 0.5
	return Vector2(centered_index * 4.0, 0.0)


func _forced_blocked_visible_layers_for_cell(cell: Vector2i) -> Array[String]:
	var layers: Array[String] = []
	for layer_name in LAYER_NAMES:
		if not _is_layer_visible(layer_name):
			continue
		if _cell_array_has(Array(_forced_blocked_cells_by_layer.get(layer_name, [])), cell):
			layers.append(layer_name)
	return layers


func _cell_array_has(cells: Array, expected_cell: Vector2i) -> bool:
	for cell_variant in cells:
		if _variant_to_cell(cell_variant) == expected_cell:
			return true
	return false


func _cell_payload(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


func _cell_key(layer_name: String, cell: Vector2i) -> String:
	return "%s:%d,%d" % [layer_name, cell.x, cell.y]


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


func _rect2i_payload(rect: Rect2i) -> Dictionary:
	return {
		"position": {"x": rect.position.x, "y": rect.position.y},
		"size": {"x": rect.size.x, "y": rect.size.y},
	}
