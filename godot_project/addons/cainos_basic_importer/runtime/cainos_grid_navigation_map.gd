extends Resource

const DEFAULT_LAYER_NAMES: Array[String] = ["Layer 1", "Layer 2", "Layer 3"]
const DIRECTIONS: Array[String] = ["north", "south", "east", "west"]

@export var grid_cell_size := 32.0
@export var grid_origin := Vector2.ZERO
@export var bounds := Rect2i()
@export var layer_names: Array[String] = DEFAULT_LAYER_NAMES.duplicate()
@export var walkable_cells_by_layer := {}
@export var blocked_cells_by_layer := {}
@export var blocked_edges_by_layer := {}
@export var transition_edges: Array = []
@export var source_metadata := {}


func is_cell_walkable(cell: Vector2i, layer_name: String) -> bool:
	return _cell_key_array_has(walkable_cells_by_layer.get(layer_name, []), cell)


func is_cell_blocked(cell: Vector2i, layer_name: String) -> bool:
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
	if uses_transition:
		to_layer = str(edge.get("to_layer", to_layer))
		to_cell = variant_to_cell(edge.get("to_cell", to_cell))
	return {
		"from_layer": from_layer,
		"from_cell": from_cell,
		"direction": direction_name,
		"to_layer": to_layer,
		"to_cell": to_cell,
		"uses_transition": uses_transition,
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
	return _cells_from_keys(walkable_cells_by_layer.get(layer_name, []))


func navigable_cells_for_layer(layer_name: String) -> Array:
	var cells := []
	for cell_variant in walkable_cells_for_layer(layer_name):
		var cell := variant_to_cell(cell_variant)
		if not is_cell_blocked(cell, layer_name):
			cells.append(cell)
	return cells


func reachable_cells_from(start_layer: String, start_cell: Vector2i, max_cells := 20000) -> Dictionary:
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


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _edge_key(from_cell: Vector2i, direction_name: String) -> String:
	return "%s:%s" % [_cell_key(from_cell), direction_name]
