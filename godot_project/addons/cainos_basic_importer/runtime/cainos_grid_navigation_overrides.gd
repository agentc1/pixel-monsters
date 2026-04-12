extends Resource

const STATE_NONE := "none"
const STATE_FORCE_NAVIGABLE := "force_navigable"
const STATE_FORCE_BLOCKED := "force_blocked"
const DEFAULT_LAYER_NAMES: Array[String] = ["Layer 1", "Layer 2", "Layer 3"]

@export var layer_names: Array[String] = DEFAULT_LAYER_NAMES.duplicate()
@export var cells_by_layer := {}
@export var source_metadata := {}


func set_cell_override(layer_name: String, cell_variant, state: String) -> Dictionary:
	var normalized_layer := _normalize_layer_name(layer_name)
	if normalized_layer.is_empty():
		return {"ok": false, "error": "Unknown navigation layer: %s" % layer_name}
	var normalized_state := _normalize_state(state)
	if normalized_state == STATE_NONE:
		return clear_cell_override(normalized_layer, cell_variant)
	var cell := variant_to_cell(cell_variant)
	_ensure_layer(normalized_layer)
	_remove_cell_from_state(normalized_layer, cell, STATE_FORCE_NAVIGABLE)
	_remove_cell_from_state(normalized_layer, cell, STATE_FORCE_BLOCKED)
	_add_cell_to_state(normalized_layer, cell, normalized_state)
	_sort_layer(normalized_layer)
	return {
		"ok": true,
		"layer": normalized_layer,
		"cell": _cell_payload(cell),
		"state": normalized_state,
	}


func clear_cell_override(layer_name: String, cell_variant) -> Dictionary:
	var normalized_layer := _normalize_layer_name(layer_name)
	if normalized_layer.is_empty():
		return {"ok": false, "error": "Unknown navigation layer: %s" % layer_name}
	var cell := variant_to_cell(cell_variant)
	_ensure_layer(normalized_layer)
	_remove_cell_from_state(normalized_layer, cell, STATE_FORCE_NAVIGABLE)
	_remove_cell_from_state(normalized_layer, cell, STATE_FORCE_BLOCKED)
	return {
		"ok": true,
		"layer": normalized_layer,
		"cell": _cell_payload(cell),
		"state": STATE_NONE,
	}


func cell_override_state(layer_name: String, cell_variant) -> String:
	var normalized_layer := _normalize_layer_name(layer_name)
	if normalized_layer.is_empty():
		return STATE_NONE
	var cell := variant_to_cell(cell_variant)
	var layer_data: Dictionary = cells_by_layer.get(normalized_layer, {})
	if _string_array_has(layer_data.get(STATE_FORCE_NAVIGABLE, []), _cell_key(cell)):
		return STATE_FORCE_NAVIGABLE
	if _string_array_has(layer_data.get(STATE_FORCE_BLOCKED, []), _cell_key(cell)):
		return STATE_FORCE_BLOCKED
	return STATE_NONE


func forced_navigable_cells_for_layer(layer_name: String) -> Array:
	return _cells_for_state(layer_name, STATE_FORCE_NAVIGABLE)


func forced_blocked_cells_for_layer(layer_name: String) -> Array:
	return _cells_for_state(layer_name, STATE_FORCE_BLOCKED)


func override_counts_by_layer() -> Dictionary:
	var counts := {}
	for layer_name in layer_names:
		counts[layer_name] = {
			STATE_FORCE_NAVIGABLE: forced_navigable_cells_for_layer(layer_name).size(),
			STATE_FORCE_BLOCKED: forced_blocked_cells_for_layer(layer_name).size(),
		}
	return counts


func override_cells_by_layer() -> Dictionary:
	var result := {}
	for layer_name in layer_names:
		result[layer_name] = {
			STATE_FORCE_NAVIGABLE: _cell_payloads(forced_navigable_cells_for_layer(layer_name)),
			STATE_FORCE_BLOCKED: _cell_payloads(forced_blocked_cells_for_layer(layer_name)),
		}
	return result


func has_overrides() -> bool:
	for layer_name in layer_names:
		if not forced_navigable_cells_for_layer(layer_name).is_empty():
			return true
		if not forced_blocked_cells_for_layer(layer_name).is_empty():
			return true
	return false


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


func _cells_for_state(layer_name: String, state: String) -> Array:
	var normalized_layer := _normalize_layer_name(layer_name)
	if normalized_layer.is_empty():
		return []
	var layer_data: Dictionary = cells_by_layer.get(normalized_layer, {})
	var cells := []
	for key_variant in Array(layer_data.get(state, [])):
		cells.append(variant_to_cell(str(key_variant)))
	cells.sort_custom(Callable(self, "_sort_cells_ascending"))
	return cells


func _ensure_layer(layer_name: String) -> void:
	var layer_data: Dictionary = cells_by_layer.get(layer_name, {})
	if not layer_data.has(STATE_FORCE_NAVIGABLE):
		layer_data[STATE_FORCE_NAVIGABLE] = []
	if not layer_data.has(STATE_FORCE_BLOCKED):
		layer_data[STATE_FORCE_BLOCKED] = []
	cells_by_layer[layer_name] = layer_data


func _add_cell_to_state(layer_name: String, cell: Vector2i, state: String) -> void:
	var layer_data: Dictionary = cells_by_layer.get(layer_name, {})
	var keys: Array = Array(layer_data.get(state, []))
	var key := _cell_key(cell)
	if not keys.has(key):
		keys.append(key)
	layer_data[state] = keys
	cells_by_layer[layer_name] = layer_data


func _remove_cell_from_state(layer_name: String, cell: Vector2i, state: String) -> void:
	var layer_data: Dictionary = cells_by_layer.get(layer_name, {})
	var keys: Array = Array(layer_data.get(state, []))
	keys.erase(_cell_key(cell))
	layer_data[state] = keys
	cells_by_layer[layer_name] = layer_data


func _sort_layer(layer_name: String) -> void:
	var layer_data: Dictionary = cells_by_layer.get(layer_name, {})
	for state in [STATE_FORCE_NAVIGABLE, STATE_FORCE_BLOCKED]:
		var keys: Array = Array(layer_data.get(state, []))
		keys.sort_custom(Callable(self, "_sort_cell_keys_ascending"))
		layer_data[state] = keys
	cells_by_layer[layer_name] = layer_data


func _sort_cells_ascending(left, right) -> bool:
	var left_cell := variant_to_cell(left)
	var right_cell := variant_to_cell(right)
	if left_cell.y == right_cell.y:
		return left_cell.x < right_cell.x
	return left_cell.y < right_cell.y


func _sort_cell_keys_ascending(left: String, right: String) -> bool:
	var left_cell := variant_to_cell(left)
	var right_cell := variant_to_cell(right)
	if left_cell.y == right_cell.y:
		return left_cell.x < right_cell.x
	return left_cell.y < right_cell.y


func _string_array_has(keys_variant, expected: String) -> bool:
	if not (keys_variant is Array):
		return false
	for key_variant in keys_variant:
		if str(key_variant) == expected:
			return true
	return false


func _normalize_layer_name(layer_name: String) -> String:
	var trimmed := layer_name.strip_edges()
	if layer_names.has(trimmed):
		return trimmed
	if trimmed.is_valid_int():
		var candidate := "Layer %d" % int(trimmed)
		if layer_names.has(candidate):
			return candidate
	return ""


func _normalize_state(state: String) -> String:
	match state:
		STATE_FORCE_NAVIGABLE, STATE_FORCE_BLOCKED:
			return state
		_:
			return STATE_NONE


func _cell_payloads(cells: Array) -> Array:
	var payloads := []
	for cell_variant in cells:
		payloads.append(_cell_payload(variant_to_cell(cell_variant)))
	return payloads


func _cell_payload(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]
