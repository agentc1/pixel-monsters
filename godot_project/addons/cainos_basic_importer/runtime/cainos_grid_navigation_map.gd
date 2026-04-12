extends Resource

const DEFAULT_LAYER_NAMES: Array[String] = ["Layer 1", "Layer 2", "Layer 3"]
const DIRECTIONS: Array[String] = ["north", "south", "east", "west"]
const OVERRIDE_NONE := "none"
const OVERRIDE_FORCE_NAVIGABLE := "force_navigable"
const OVERRIDE_FORCE_BLOCKED := "force_blocked"

@export var grid_cell_size := 32.0
@export var grid_origin := Vector2.ZERO
@export var bounds := Rect2i()
@export var layer_names: Array[String] = DEFAULT_LAYER_NAMES.duplicate()
@export var walkable_cells_by_layer := {}
@export var blocked_cells_by_layer := {}
@export var blocked_edges_by_layer := {}
@export var transition_edges: Array = []
@export var navigation_overrides: Resource
@export var source_metadata := {}


func is_cell_walkable(cell: Vector2i, layer_name: String) -> bool:
	if _cell_override_state(layer_name, cell) == OVERRIDE_FORCE_NAVIGABLE:
		return true
	return _cell_key_array_has(walkable_cells_by_layer.get(layer_name, []), cell)


func is_cell_blocked(cell: Vector2i, layer_name: String) -> bool:
	var override_state := _cell_override_state(layer_name, cell)
	if override_state == OVERRIDE_FORCE_NAVIGABLE:
		return false
	if override_state == OVERRIDE_FORCE_BLOCKED:
		return true
	return _cell_key_array_has(blocked_cells_by_layer.get(layer_name, []), cell)


func is_cell_navigable(cell: Vector2i, layer_name: String) -> bool:
	return is_cell_walkable(cell, layer_name) and not is_cell_blocked(cell, layer_name)


func is_edge_blocked(layer_name: String, from_cell: Vector2i, direction_name: String) -> bool:
	var edge_key := _edge_key(from_cell, direction_name)
	return _string_array_has(blocked_edges_by_layer.get(layer_name, []), edge_key)


func grid_step_target(from_layer: String, from_cell: Vector2i, direction_name: String) -> Dictionary:
	var to_cell := from_cell + grid_direction_cell_delta(direction_name)
	var to_layer := from_layer
	var edge := transition_edge(from_layer, from_cell, direction_name)
	var uses_transition := not edge.is_empty()
	var waypoints := []
	var layer_switch_t := 0.0
	var movement_kind := ""
	if uses_transition:
		to_layer = str(edge.get("to_layer", to_layer))
		to_cell = variant_to_cell(edge.get("to_cell", to_cell))
		for waypoint_variant in Array(edge.get("waypoints", [])):
			waypoints.append(variant_to_position(waypoint_variant))
		layer_switch_t = clampf(float(edge.get("layer_switch_t", 0.0)), 0.0, 1.0)
		movement_kind = str(edge.get("movement_kind", ""))
	return {
		"from_layer": from_layer,
		"from_cell": from_cell,
		"direction": direction_name,
		"to_layer": to_layer,
		"to_cell": to_cell,
		"uses_transition": uses_transition,
		"waypoints": waypoints,
		"layer_switch_t": layer_switch_t,
		"movement_kind": movement_kind,
	}


func can_step(from_layer: String, from_cell: Vector2i, direction_name: String) -> Dictionary:
	var target := grid_step_target(from_layer, from_cell, direction_name)
	var to_layer := str(target.get("to_layer", from_layer))
	var to_cell := variant_to_cell(target.get("to_cell", from_cell))
	var has_direction := grid_direction_cell_delta(direction_name) != Vector2i.ZERO
	var from_supported := is_cell_walkable(from_cell, from_layer)
	var from_blocked := is_cell_blocked(from_cell, from_layer)
	var supported := is_cell_walkable(to_cell, to_layer)
	var blocked := is_cell_blocked(to_cell, to_layer)
	var edge_blocked := false
	var reason := ""
	var allowed := false

	if not has_direction and not bool(target.get("uses_transition", false)):
		reason = "invalid_direction"
	elif not from_supported:
		reason = "from_unsupported"
	elif from_blocked:
		reason = "from_blocked"
	elif not supported:
		reason = "unsupported"
	elif blocked:
		reason = "blocked_cell"
	else:
		edge_blocked = is_edge_blocked(from_layer, from_cell, direction_name)
		if edge_blocked:
			reason = "blocked_edge"
		else:
			allowed = true

	target["allowed"] = allowed
	target["reason"] = reason
	target["from_supported"] = from_supported
	target["from_blocked"] = from_blocked
	target["supported"] = supported
	target["blocked"] = blocked
	target["edge_blocked"] = edge_blocked
	target["collides"] = edge_blocked
	return target


func transition_edge(from_layer: String, from_cell: Vector2i, direction_name: String) -> Dictionary:
	for edge_variant in transition_edges:
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		if str(edge.get("from_layer", "")) != from_layer:
			continue
		if str(edge.get("direction", "")) != direction_name:
			continue
		if variant_to_cell(edge.get("from_cell", Vector2i.ZERO)) == from_cell:
			return edge
	return {}


func walkable_cells_for_layer(layer_name: String) -> Array:
	var cells := _cells_from_keys(walkable_cells_by_layer.get(layer_name, []))
	for cell_variant in forced_navigable_cells_for_layer(layer_name):
		var cell := variant_to_cell(cell_variant)
		if not _cell_array_has(cells, cell):
			cells.append(cell)
	cells.sort_custom(Callable(self, "_sort_cells_ascending"))
	return cells


func blocked_cells_for_layer(layer_name: String) -> Array:
	var cells := _cells_from_keys(blocked_cells_by_layer.get(layer_name, []))
	for cell_variant in forced_blocked_cells_for_layer(layer_name):
		var cell := variant_to_cell(cell_variant)
		if not _cell_array_has(cells, cell):
			cells.append(cell)
	for cell_variant in forced_navigable_cells_for_layer(layer_name):
		_remove_cell_from_array(cells, variant_to_cell(cell_variant))
	cells.sort_custom(Callable(self, "_sort_cells_ascending"))
	return cells


func navigable_cells_for_layer(layer_name: String) -> Array:
	var cells := []
	for cell_variant in walkable_cells_for_layer(layer_name):
		var cell := variant_to_cell(cell_variant)
		if not is_cell_blocked(cell, layer_name):
			cells.append(cell)
	return cells


func reachable_cells_from(start_layer: String, start_cell: Vector2i, max_cells := 20000) -> Dictionary:
	if not is_cell_navigable(start_cell, start_layer):
		return _sorted_cells_by_layer({})
	var reachable := {}
	var visited := {}
	var queue := []
	_enqueue_reachable_cell(queue, visited, reachable, start_cell, start_layer)
	var queue_index := 0
	while queue_index < queue.size() and visited.size() < max_cells:
		var current: Dictionary = queue[queue_index]
		queue_index += 1
		var from_layer := str(current.get("layer", ""))
		var from_cell: Vector2i = current.get("cell", Vector2i.ZERO)
		for direction_name in DIRECTIONS:
			var step := can_step(from_layer, from_cell, direction_name)
			if not bool(step.get("allowed", false)):
				continue
			var to_layer := str(step.get("to_layer", from_layer))
			var to_cell := variant_to_cell(step.get("to_cell", from_cell))
			if bounds.size.x > 0 and bounds.size.y > 0 and not bounds.has_point(to_cell):
				continue
			_enqueue_reachable_cell(queue, visited, reachable, to_cell, to_layer)
	return _sorted_cells_by_layer(reachable)


func navigation_debug_report(start_layer: String, start_cell: Vector2i, max_cells := 20000) -> Dictionary:
	var reachable := {}
	if not start_layer.is_empty() and is_cell_navigable(start_cell, start_layer):
		reachable = reachable_cells_from(start_layer, start_cell, max_cells)
	else:
		reachable = _sorted_cells_by_layer({})

	var layers := {}
	for layer_name in layer_names:
		var walkable_cells := walkable_cells_for_layer(layer_name)
		var blocked_cells := blocked_cells_for_layer(layer_name)
		var navigable_cells := navigable_cells_for_layer(layer_name)
		var reachable_cells: Array = reachable.get(layer_name, [])
		var unreachable_cells := _subtract_cell_arrays(navigable_cells, reachable_cells)
		var forced_navigable_cells := forced_navigable_cells_for_layer(layer_name)
		var forced_blocked_cells := forced_blocked_cells_for_layer(layer_name)
		layers[layer_name] = {
			"walkable_count": walkable_cells.size(),
			"blocked_count": blocked_cells.size(),
			"navigable_count": navigable_cells.size(),
			"reachable_count": reachable_cells.size(),
			"unreachable_count": unreachable_cells.size(),
			"override_counts": {
				OVERRIDE_FORCE_NAVIGABLE: forced_navigable_cells.size(),
				OVERRIDE_FORCE_BLOCKED: forced_blocked_cells.size(),
			},
			"walkable_cells": _cell_payloads(walkable_cells),
			"blocked_cells": _cell_payloads(blocked_cells),
			"navigable_cells": _cell_payloads(navigable_cells),
			"reachable_cells": _cell_payloads(reachable_cells),
			"unreachable_cells": _cell_payloads(unreachable_cells),
			"forced_navigable_cells": _cell_payloads(forced_navigable_cells),
			"forced_blocked_cells": _cell_payloads(forced_blocked_cells),
		}

	var transition_report := _transition_debug_report(reachable)
	return {
		"ok": true,
		"proof_scope": "Navigation inventory report generated from the saved navigation map. Reachability is computed from the supplied start layer/cell using the same can_step contract as runtime grid movement.",
		"bounds": _rect2i_payload(bounds),
		"start": {
			"layer": start_layer,
			"cell": _cell_payload(start_cell),
			"navigable": is_cell_navigable(start_cell, start_layer),
		},
		"layers": layers,
		"transition_edges": transition_report.get("edges", []),
		"transition_status_counts": transition_report.get("status_counts", {}),
		"transition_target_layer_counts": transition_report.get("target_layer_counts", {}),
		"override_counts_by_layer": override_counts_by_layer(),
		"override_cells_by_layer": override_cells_by_layer(),
		"override_resource_path": _override_resource_path(),
		"source_metadata": source_metadata.duplicate(true),
	}


func transition_cells_by_layer() -> Dictionary:
	var cells_by_layer := {}
	for edge_variant in transition_edges:
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		for endpoint_name in ["from", "to"]:
			var layer_name := str(edge.get("%s_layer" % endpoint_name, ""))
			var cell := variant_to_cell(edge.get("%s_cell" % endpoint_name, Vector2i.ZERO))
			if layer_name.is_empty():
				continue
			var cells: Array = cells_by_layer.get(layer_name, [])
			if not _cell_array_has(cells, cell):
				cells.append(cell)
			cells_by_layer[layer_name] = cells
	return _sorted_cells_by_layer(cells_by_layer)


func grid_position_for_cell(cell: Vector2i) -> Vector2:
	var safe_cell_size := maxf(grid_cell_size, 1.0)
	return grid_origin + Vector2(cell) * safe_cell_size


func grid_cell_for_position(point: Vector2) -> Vector2i:
	var safe_cell_size := maxf(grid_cell_size, 1.0)
	return Vector2i(
		roundi((point.x - grid_origin.x) / safe_cell_size),
		roundi((point.y - grid_origin.y) / safe_cell_size)
	)


func grid_direction_cell_delta(direction_name: String) -> Vector2i:
	match direction_name:
		"north":
			return Vector2i(0, -1)
		"south":
			return Vector2i(0, 1)
		"east":
			return Vector2i(1, 0)
		"west":
			return Vector2i(-1, 0)
		_:
			return Vector2i.ZERO


func set_walkable_cells(layer_name: String, cells: Array) -> void:
	walkable_cells_by_layer[layer_name] = _sorted_cell_keys(cells)


func set_blocked_cells(layer_name: String, cells: Array) -> void:
	blocked_cells_by_layer[layer_name] = _sorted_cell_keys(cells)


func set_blocked_edges(layer_name: String, edge_keys: Array) -> void:
	var keys: Array[String] = []
	for edge_key_variant in edge_keys:
		var edge_key := str(edge_key_variant)
		if not keys.has(edge_key):
			keys.append(edge_key)
	keys.sort()
	blocked_edges_by_layer[layer_name] = keys


func set_cell_override(layer_name: String, cell_variant, state: String) -> Dictionary:
	if not _has_override_resource():
		return {"ok": false, "error": "Navigation override resource is not attached."}
	var result: Dictionary = navigation_overrides.call("set_cell_override", layer_name, variant_to_cell(cell_variant), state)
	return result


func clear_cell_override(layer_name: String, cell_variant) -> Dictionary:
	if not _has_override_resource():
		return {"ok": false, "error": "Navigation override resource is not attached."}
	return Dictionary(navigation_overrides.call("clear_cell_override", layer_name, variant_to_cell(cell_variant)))


func cell_override_state(layer_name: String, cell_variant) -> String:
	return _cell_override_state(layer_name, variant_to_cell(cell_variant))


func forced_navigable_cells_for_layer(layer_name: String) -> Array:
	if not _has_override_resource():
		return []
	return Array(navigation_overrides.call("forced_navigable_cells_for_layer", layer_name))


func forced_blocked_cells_for_layer(layer_name: String) -> Array:
	if not _has_override_resource():
		return []
	return Array(navigation_overrides.call("forced_blocked_cells_for_layer", layer_name))


func override_counts_by_layer() -> Dictionary:
	if not _has_override_resource():
		var counts := {}
		for layer_name in layer_names:
			counts[layer_name] = {
				OVERRIDE_FORCE_NAVIGABLE: 0,
				OVERRIDE_FORCE_BLOCKED: 0,
			}
		return counts
	return Dictionary(navigation_overrides.call("override_counts_by_layer"))


func override_cells_by_layer() -> Dictionary:
	if not _has_override_resource():
		var cells := {}
		for layer_name in layer_names:
			cells[layer_name] = {
				OVERRIDE_FORCE_NAVIGABLE: [],
				OVERRIDE_FORCE_BLOCKED: [],
			}
		return cells
	return Dictionary(navigation_overrides.call("override_cells_by_layer"))


func save_navigation_overrides() -> Dictionary:
	if not _has_override_resource():
		return {"ok": false, "error": "Navigation override resource is not attached."}
	var path := _override_resource_path()
	if path.is_empty():
		return {"ok": false, "error": "Navigation override resource has no save path."}
	var err := ResourceSaver.save(navigation_overrides, path)
	return {
		"ok": err == OK,
		"error_code": err,
		"path": path,
	}


func bake_navigation_overrides(save_after := true, clear_after := true) -> Dictionary:
	if not _has_override_resource():
		return {"ok": false, "error": "Navigation override resource is not attached."}

	var counts := override_counts_by_layer()
	var force_navigable_count := 0
	var force_blocked_count := 0
	for layer_name in layer_names:
		var layer_counts: Dictionary = counts.get(layer_name, {})
		force_navigable_count += int(layer_counts.get(OVERRIDE_FORCE_NAVIGABLE, 0))
		force_blocked_count += int(layer_counts.get(OVERRIDE_FORCE_BLOCKED, 0))
	var total_count := force_navigable_count + force_blocked_count
	if total_count == 0:
		return {
			"ok": true,
			"baked": false,
			"message": "No navigation overrides to bake.",
			"counts_by_layer": counts,
			"force_navigable_count": 0,
			"force_blocked_count": 0,
		}

	for layer_name in layer_names:
		var walkable_cells := _cells_from_keys(walkable_cells_by_layer.get(layer_name, []))
		var blocked_cells := _cells_from_keys(blocked_cells_by_layer.get(layer_name, []))
		for cell_variant in forced_navigable_cells_for_layer(layer_name):
			var cell := variant_to_cell(cell_variant)
			_add_cell_to_array(walkable_cells, cell)
			_remove_cell_from_array(blocked_cells, cell)
		for cell_variant in forced_blocked_cells_for_layer(layer_name):
			var cell := variant_to_cell(cell_variant)
			_remove_cell_from_array(walkable_cells, cell)
			_add_cell_to_array(blocked_cells, cell)
		set_walkable_cells(layer_name, walkable_cells)
		set_blocked_cells(layer_name, blocked_cells)

	var clear_result := {"ok": true}
	if clear_after:
		if navigation_overrides.has_method("clear_all_overrides"):
			clear_result = Dictionary(navigation_overrides.call("clear_all_overrides"))
		else:
			clear_result = _clear_overrides_cell_by_cell()
		if not bool(clear_result.get("ok", false)):
			return {
				"ok": false,
				"error": "Failed to clear navigation overrides after baking.",
				"clear_result": clear_result,
			}

	var map_path := str(resource_path)
	var override_path := _override_resource_path()
	var map_error := OK
	var override_error := OK
	if save_after:
		if map_path.is_empty():
			return {"ok": false, "error": "Navigation map resource has no save path."}
		map_error = ResourceSaver.save(self, map_path)
		if clear_after and not override_path.is_empty():
			override_error = ResourceSaver.save(navigation_overrides, override_path)

	return {
		"ok": map_error == OK and override_error == OK,
		"baked": map_error == OK and override_error == OK,
		"map_error_code": map_error,
		"override_error_code": override_error,
		"map_path": map_path,
		"override_path": override_path,
		"cleared_overrides": clear_after,
		"counts_by_layer": counts,
		"force_navigable_count": force_navigable_count,
		"force_blocked_count": force_blocked_count,
	}


func edge_key(from_cell: Vector2i, direction_name: String) -> String:
	return _edge_key(from_cell, direction_name)


func cell_key(cell: Vector2i) -> String:
	return _cell_key(cell)


func variant_to_cell(value) -> Vector2i:
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


func variant_to_position(value) -> Vector2:
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
	if value is String:
		var parts := str(value).split(",", false)
		if parts.size() == 2:
			return Vector2(float(parts[0]), float(parts[1]))
	return Vector2.ZERO


func _enqueue_reachable_cell(queue: Array, visited: Dictionary, reachable: Dictionary, cell: Vector2i, layer_name: String) -> void:
	if bounds.size.x > 0 and bounds.size.y > 0 and not bounds.has_point(cell):
		return
	var key := "%s:%s" % [layer_name, _cell_key(cell)]
	if visited.has(key):
		return
	visited[key] = true
	queue.append({"layer": layer_name, "cell": cell})
	var cells: Array = reachable.get(layer_name, [])
	cells.append(cell)
	reachable[layer_name] = cells


func _sorted_cells_by_layer(cells_by_layer: Dictionary) -> Dictionary:
	var result := {}
	for layer_name in layer_names:
		var cells: Array = cells_by_layer.get(layer_name, [])
		cells.sort_custom(Callable(self, "_sort_cells_ascending"))
		result[layer_name] = cells
	return result


func _sort_cells_ascending(left, right) -> bool:
	var left_cell := variant_to_cell(left)
	var right_cell := variant_to_cell(right)
	if left_cell.y == right_cell.y:
		return left_cell.x < right_cell.x
	return left_cell.y < right_cell.y


func _sorted_cell_keys(cells: Array) -> Array[String]:
	var keys: Array[String] = []
	for cell_variant in cells:
		var key := _cell_key(variant_to_cell(cell_variant))
		if not keys.has(key):
			keys.append(key)
	keys.sort_custom(Callable(self, "_sort_cell_keys_ascending"))
	return keys


func _sort_cell_keys_ascending(left: String, right: String) -> bool:
	var left_cell := variant_to_cell(left)
	var right_cell := variant_to_cell(right)
	if left_cell.y == right_cell.y:
		return left_cell.x < right_cell.x
	return left_cell.y < right_cell.y


func _cells_from_keys(keys_variant) -> Array:
	var cells := []
	if not (keys_variant is Array):
		return cells
	for key_variant in keys_variant:
		cells.append(variant_to_cell(key_variant))
	return cells


func _cell_key_array_has(keys_variant, cell: Vector2i) -> bool:
	return _string_array_has(keys_variant, _cell_key(cell))


func _string_array_has(keys_variant, expected: String) -> bool:
	if not (keys_variant is Array):
		return false
	for key_variant in keys_variant:
		if str(key_variant) == expected:
			return true
	return false


func _cell_array_has(cells: Array, expected_cell: Vector2i) -> bool:
	for cell_variant in cells:
		if variant_to_cell(cell_variant) == expected_cell:
			return true
	return false


func _remove_cell_from_array(cells: Array, expected_cell: Vector2i) -> void:
	var index := cells.size() - 1
	while index >= 0:
		if variant_to_cell(cells[index]) == expected_cell:
			cells.remove_at(index)
		index -= 1


func _add_cell_to_array(cells: Array, cell: Vector2i) -> void:
	if not _cell_array_has(cells, cell):
		cells.append(cell)


func _subtract_cell_arrays(cells: Array, cells_to_remove: Array) -> Array:
	var result := []
	for cell_variant in cells:
		var cell := variant_to_cell(cell_variant)
		if not _cell_array_has(cells_to_remove, cell):
			result.append(cell)
	result.sort_custom(Callable(self, "_sort_cells_ascending"))
	return result


func _transition_debug_report(reachable: Dictionary) -> Dictionary:
	var edges := []
	var status_counts := {}
	var target_layer_counts := {}
	for index in range(transition_edges.size()):
		var edge_variant = transition_edges[index]
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var from_layer := str(edge.get("from_layer", ""))
		var to_layer := str(edge.get("to_layer", ""))
		var direction_name := str(edge.get("direction", ""))
		var from_cell := variant_to_cell(edge.get("from_cell", Vector2i.ZERO))
		var to_cell := variant_to_cell(edge.get("to_cell", Vector2i.ZERO))
		var step := can_step(from_layer, from_cell, direction_name)
		var from_reachable := _cell_array_has(Array(reachable.get(from_layer, [])), from_cell)
		var to_reachable := _cell_array_has(Array(reachable.get(to_layer, [])), to_cell)
		var from_navigable := is_cell_navigable(from_cell, from_layer)
		var to_navigable := is_cell_navigable(to_cell, to_layer)
		var status := _transition_debug_status(from_layer, to_layer, from_navigable, to_navigable, from_reachable, to_reachable, step)
		status_counts[status] = int(status_counts.get(status, 0)) + 1
		if not to_layer.is_empty():
			target_layer_counts[to_layer] = int(target_layer_counts.get(to_layer, 0)) + 1
		edges.append({
			"index": index,
			"kind": str(edge.get("kind", "")),
			"source_prefab_path": str(edge.get("source_prefab_path", "")),
			"direction": direction_name,
			"from_layer": from_layer,
			"from_cell": _cell_payload(from_cell),
			"to_layer": to_layer,
			"to_cell": _cell_payload(to_cell),
			"status": status,
			"from_walkable": is_cell_walkable(from_cell, from_layer),
			"from_blocked": is_cell_blocked(from_cell, from_layer),
			"from_navigable": from_navigable,
			"from_reachable": from_reachable,
			"to_walkable": is_cell_walkable(to_cell, to_layer),
			"to_blocked": is_cell_blocked(to_cell, to_layer),
			"to_navigable": to_navigable,
			"to_reachable": to_reachable,
			"step_allowed": bool(step.get("allowed", false)),
			"step_reason": str(step.get("reason", "")),
		})
	return {
		"edges": edges,
		"status_counts": status_counts,
		"target_layer_counts": target_layer_counts,
	}


func _transition_debug_status(from_layer: String, to_layer: String, from_navigable: bool, to_navigable: bool, from_reachable: bool, to_reachable: bool, step: Dictionary) -> String:
	if from_layer.is_empty() or to_layer.is_empty():
		return "invalid_endpoint"
	if not from_navigable:
		return "from_not_navigable"
	if not to_navigable:
		return "to_not_navigable"
	if not bool(step.get("allowed", false)):
		var reason := str(step.get("reason", "blocked"))
		return "step_blocked:%s" % reason
	if not from_reachable:
		return "source_unreachable"
	if not to_reachable:
		return "target_unreachable"
	return "reachable"


func _has_override_resource() -> bool:
	return navigation_overrides is Resource and navigation_overrides.has_method("cell_override_state")


func _clear_overrides_cell_by_cell() -> Dictionary:
	for layer_name in layer_names:
		var cells_to_clear := []
		for cell_variant in forced_navigable_cells_for_layer(layer_name):
			_add_cell_to_array(cells_to_clear, variant_to_cell(cell_variant))
		for cell_variant in forced_blocked_cells_for_layer(layer_name):
			_add_cell_to_array(cells_to_clear, variant_to_cell(cell_variant))
		for cell_variant in cells_to_clear:
			navigation_overrides.call("clear_cell_override", layer_name, variant_to_cell(cell_variant))
	return {"ok": true}


func _cell_override_state(layer_name: String, cell: Vector2i) -> String:
	if not _has_override_resource():
		return OVERRIDE_NONE
	return str(navigation_overrides.call("cell_override_state", layer_name, cell))


func _override_resource_path() -> String:
	if not _has_override_resource():
		return ""
	return str((navigation_overrides as Resource).resource_path)


func _cell_payloads(cells: Array) -> Array:
	var payloads := []
	for cell_variant in cells:
		payloads.append(_cell_payload(variant_to_cell(cell_variant)))
	return payloads


func _cell_payload(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


func _rect2i_payload(rect: Rect2i) -> Dictionary:
	return {
		"position": _cell_payload(rect.position),
		"size": _cell_payload(rect.size),
	}


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _edge_key(from_cell: Vector2i, direction_name: String) -> String:
	return "%s:%s" % [_cell_key(from_cell), direction_name]
