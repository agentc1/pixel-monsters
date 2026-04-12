extends CharacterBody2D

signal grid_step_finished(from_cell: Vector2i, to_cell: Vector2i, from_layer: String, to_layer: String)

const ACTOR_COLLISION_LAYER_BIT := 8
const LAYER_COLLISION_BITS := {
	"Layer 1": 1,
	"Layer 2": 2,
	"Layer 3": 4,
}
const NAVIGATION_MODE_CONTINUOUS := "continuous"
const NAVIGATION_MODE_GRID_CARDINAL := "grid_cardinal"
const WALKABLE_FOOTPRINT_RADIUS := 6.0
const GRID_WALKABLE_FOOTPRINT_RADIUS := 15.0

@export var player_root_path: NodePath = ^"PF Player"
@export var controller_path: NodePath = ^"PF Player"
@export var follow_camera_path: NodePath = ^"FollowCamera2D"
@export var camera_limits := Rect2i()
@export var camera_offset := Vector2.ZERO
@export var camera_unity_orthographic_size := 5.0
@export var current_collision_layer_name := "Layer 1"
@export var rigidbody_push_speed_px := 96.0
@export var rigidbody_push_acceleration_px := 960.0
@export var walkable_regions_by_layer := {}
@export_enum("continuous", "grid_cardinal") var navigation_mode := NAVIGATION_MODE_CONTINUOUS
@export var grid_cell_size := 32.0
@export var grid_origin := Vector2.ZERO
@export var grid_step_duration_sec := 0.22
@export var grid_transition_edges: Array = []
@export var grid_collision_bypass_regions_by_layer := {}
@export var grid_blocked_cells_by_layer := {}
@export var grid_navigation_bounds := Rect2i()
@export var navigation_map: Resource
@export var movement_input_suppressed := false

var _player_root: Node2D
var _controller: Node
var _follow_camera: Camera2D
var _grid_is_moving := false
var _grid_waiting_for_release := false
var _grid_step_elapsed := 0.0
var _grid_start_position := Vector2.ZERO
var _grid_target_position := Vector2.ZERO
var _grid_start_cell := Vector2i.ZERO
var _grid_target_cell := Vector2i.ZERO
var _grid_start_layer := "Layer 1"
var _grid_target_layer := "Layer 1"
var _grid_step_direction_name := "south"
var _grid_path_positions := []
var _grid_layer_switch_t := 0.0
var _grid_layer_switched := true


func _ready() -> void:
	set_meta("cainos_runtime_elevation_body", true)
	_resolve_runtime_nodes()
	_sync_navigation_map_configuration()
	_sync_runtime_collision_mask()
	if navigation_mode == NAVIGATION_MODE_GRID_CARDINAL:
		_snap_to_grid_position()
	_sync_player_root()
	_connect_viewport_resize()
	_apply_follow_camera()


func _physics_process(delta: float) -> void:
	_resolve_runtime_nodes()
	_sync_navigation_map_configuration()
	_sync_runtime_collision_mask()
	if navigation_mode == NAVIGATION_MODE_GRID_CARDINAL:
		_physics_process_grid(delta)
		return
	if _controller == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var input_vector := _movement_input()
	velocity = _desired_velocity(input_vector)
	velocity = _constrain_velocity_to_walkable(velocity, delta)
	move_and_slide()
	_push_rigidbody_collisions(input_vector, delta)
	_controller.call("step_external_body", input_vector, delta)
	_sync_player_root()


func _physics_process_grid(delta: float) -> void:
	velocity = Vector2.ZERO
	if _grid_is_moving:
		_advance_grid_step(delta)
		return
	_snap_to_grid_position()
	var input_vector := _movement_input()
	var direction_name := _grid_direction_name_from_input(input_vector)
	if direction_name.is_empty():
		_grid_waiting_for_release = false
		_apply_controller_facing(_grid_step_direction_name, false)
		_sync_player_root()
		return
	if _grid_waiting_for_release:
		_apply_controller_facing(direction_name, false)
		_sync_player_root()
		return
	_attempt_grid_step(direction_name)
	_sync_player_root()


func _movement_input() -> Vector2:
	if movement_input_suppressed:
		return Vector2.ZERO
	if _controller != null and _controller.has_method("movement_input_vector"):
		return _controller.call("movement_input_vector")
	return Vector2.ZERO


func _desired_velocity(input_vector: Vector2) -> Vector2:
	if _controller != null and _controller.has_method("desired_velocity_from_input"):
		return _controller.call("desired_velocity_from_input", input_vector)
	return Vector2.ZERO


func _clear_controller_movement_input() -> void:
	_resolve_runtime_nodes()
	if _controller != null and _controller.has_method("clear_movement_input"):
		_controller.call("clear_movement_input")


func _resolve_runtime_nodes() -> void:
	if _player_root == null:
		_player_root = get_node_or_null(player_root_path) as Node2D
	if _controller == null:
		_controller = get_node_or_null(controller_path)
	if _follow_camera == null:
		_follow_camera = get_node_or_null(follow_camera_path) as Camera2D


func _connect_viewport_resize() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	if not viewport.size_changed.is_connected(_apply_follow_camera):
		viewport.size_changed.connect(_apply_follow_camera)


func _sync_player_root() -> void:
	if _player_root != null:
		_player_root.position = Vector2.ZERO


func _sync_runtime_collision_mask() -> void:
	current_collision_layer_name = _current_runtime_layer_name()
	collision_layer = ACTOR_COLLISION_LAYER_BIT | _layer_collision_bit(current_collision_layer_name)
	collision_mask = _layer_collision_bit(current_collision_layer_name)
	set_meta("cainos_runtime_collision_layer_name", current_collision_layer_name)
	set_meta("cainos_runtime_collision_mask", int(collision_mask))


func _current_runtime_layer_name() -> String:
	if _player_root != null:
		return str(_player_root.get_meta("cainos_runtime_layer_name", current_collision_layer_name))
	return current_collision_layer_name


func _layer_collision_bit(layer_name: String) -> int:
	return int(LAYER_COLLISION_BITS.get(layer_name, LAYER_COLLISION_BITS["Layer 1"]))


func _attempt_grid_step(direction_name: String) -> void:
	_grid_waiting_for_release = true
	_grid_step_direction_name = direction_name
	var from_layer := current_collision_layer_name
	var from_cell := _grid_cell_for_position(global_position)
	var step := can_grid_step_from_cell(from_layer, from_cell, direction_name)
	if not bool(step.get("allowed", false)):
		_apply_controller_facing(direction_name, false)
		return
	var to_layer := str(step.get("to_layer", from_layer))
	var to_cell := _grid_variant_to_cell(step.get("to_cell", from_cell))
	var to_position := _grid_position_for_cell(to_cell)
	_grid_layer_switch_t = clampf(float(step.get("layer_switch_t", 0.0)), 0.0, 1.0)
	_grid_path_positions = _grid_step_path_positions(global_position, to_position, step)
	_grid_layer_switched = to_layer == from_layer
	if not _grid_layer_switched and _grid_layer_switch_t <= 0.0:
		_apply_runtime_layer_name(to_layer)
		_grid_layer_switched = true
	_grid_is_moving = true
	_grid_step_elapsed = 0.0
	_grid_start_position = global_position
	_grid_target_position = to_position
	_grid_start_cell = from_cell
	_grid_target_cell = to_cell
	_grid_start_layer = from_layer
	_grid_target_layer = to_layer
	_apply_controller_facing(direction_name, true)


func _advance_grid_step(delta: float) -> void:
	_grid_step_elapsed += maxf(delta, 0.0)
	var duration := maxf(grid_step_duration_sec, 0.001)
	var t := clampf(_grid_step_elapsed / duration, 0.0, 1.0)
	if not _grid_layer_switched and t >= _grid_layer_switch_t:
		_apply_runtime_layer_name(_grid_target_layer)
		_grid_layer_switched = true
	global_position = _grid_position_on_active_path(t)
	if t < 1.0:
		_apply_controller_facing(_grid_step_direction_name, true)
		_sync_player_root()
		return
	if not _grid_layer_switched:
		_apply_runtime_layer_name(_grid_target_layer)
		_grid_layer_switched = true
	global_position = _grid_target_position
	_grid_is_moving = false
	_sync_player_root()
	_apply_controller_facing(_grid_step_direction_name, false)
	emit_signal("grid_step_finished", _grid_start_cell, _grid_target_cell, _grid_start_layer, _grid_target_layer)


func _grid_step_path_positions(from_position: Vector2, to_position: Vector2, step: Dictionary) -> Array:
	var path := [from_position]
	for waypoint_variant in Array(step.get("waypoints", [])):
		var waypoint := _grid_variant_to_position(waypoint_variant)
		if path.is_empty() or Vector2(path[path.size() - 1]).distance_squared_to(waypoint) > 0.0001:
			path.append(waypoint)
	if path.is_empty() or Vector2(path[path.size() - 1]).distance_squared_to(to_position) > 0.0001:
		path.append(to_position)
	set_meta("cainos_grid_step_path_positions", _grid_position_payloads(path))
	set_meta("cainos_grid_step_layer_switch_t", _grid_layer_switch_t)
	set_meta("cainos_grid_step_movement_kind", str(step.get("movement_kind", "")))
	return path


func _grid_position_on_active_path(t: float) -> Vector2:
	if _grid_path_positions.size() < 2:
		return _grid_start_position.lerp(_grid_target_position, t)
	var segment_lengths := []
	var total_length := 0.0
	for index in range(_grid_path_positions.size() - 1):
		var start := Vector2(_grid_path_positions[index])
		var end := Vector2(_grid_path_positions[index + 1])
		var length := start.distance_to(end)
		segment_lengths.append(length)
		total_length += length
	if total_length <= 0.0001:
		return _grid_target_position
	var target_distance := total_length * clampf(t, 0.0, 1.0)
	var walked := 0.0
	for index in range(segment_lengths.size()):
		var segment_length := float(segment_lengths[index])
		if target_distance > walked + segment_length and index < segment_lengths.size() - 1:
			walked += segment_length
			continue
		var segment_t := 1.0 if segment_length <= 0.0001 else clampf((target_distance - walked) / segment_length, 0.0, 1.0)
		return Vector2(_grid_path_positions[index]).lerp(Vector2(_grid_path_positions[index + 1]), segment_t)
	return _grid_target_position


func _snap_to_grid_position() -> void:
	var snapped_position := _grid_position_for_cell(_grid_cell_for_position(global_position))
	if global_position.distance_squared_to(snapped_position) > 0.0001:
		global_position = snapped_position


func grid_cell_for_position(point: Vector2) -> Vector2i:
	return _grid_cell_for_position(point)


func grid_position_for_cell(cell: Vector2i) -> Vector2:
	return _grid_position_for_cell(cell)


func set_movement_input_suppressed(is_suppressed: bool) -> void:
	movement_input_suppressed = is_suppressed
	_grid_waiting_for_release = false
	velocity = Vector2.ZERO
	_clear_controller_movement_input()
	if movement_input_suppressed:
		_apply_controller_facing(_grid_step_direction_name, false)


func grid_direction_cell_delta(direction_name: String) -> Vector2i:
	return _grid_direction_cell_delta(direction_name)


func grid_transition_edge(from_layer: String, from_cell: Vector2i, direction_name: String) -> Dictionary:
	return _grid_transition_edge(from_layer, from_cell, direction_name)


func grid_step_target(from_layer: String, from_cell: Vector2i, direction_name: String) -> Dictionary:
	if _has_navigation_map():
		return Dictionary(navigation_map.call("grid_step_target", from_layer, from_cell, direction_name))
	var to_cell := from_cell + _grid_direction_cell_delta(direction_name)
	var to_layer := from_layer
	var transition_edge := _grid_transition_edge(from_layer, from_cell, direction_name)
	var uses_transition := not transition_edge.is_empty()
	var waypoints := []
	var layer_switch_t := 0.0
	var movement_kind := ""
	if uses_transition:
		to_layer = str(transition_edge.get("to_layer", to_layer))
		to_cell = _grid_variant_to_cell(transition_edge.get("to_cell", to_cell))
		for waypoint_variant in Array(transition_edge.get("waypoints", [])):
			waypoints.append(_grid_variant_to_position(waypoint_variant))
		layer_switch_t = clampf(float(transition_edge.get("layer_switch_t", 0.0)), 0.0, 1.0)
		movement_kind = str(transition_edge.get("movement_kind", ""))
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


func is_grid_cell_supported(cell: Vector2i, layer_name: String) -> bool:
	if _has_navigation_map():
		return bool(navigation_map.call("is_cell_walkable", cell, layer_name))
	return _is_grid_position_supported(_grid_position_for_cell(cell), layer_name)


func is_grid_cell_blocked(cell: Vector2i, layer_name: String) -> bool:
	if _has_navigation_map():
		return bool(navigation_map.call("is_cell_blocked", cell, layer_name))
	return _is_grid_cell_blocked(cell, layer_name)


func is_grid_cell_navigable(cell: Vector2i, layer_name: String) -> bool:
	if _has_navigation_map():
		return bool(navigation_map.call("is_cell_navigable", cell, layer_name))
	return is_grid_cell_supported(cell, layer_name) and not is_grid_cell_blocked(cell, layer_name)


func can_grid_step_from_cell(from_layer: String, from_cell: Vector2i, direction_name: String) -> Dictionary:
	if _has_navigation_map():
		return Dictionary(navigation_map.call("can_step", from_layer, from_cell, direction_name))
	var original_position := global_position
	var original_velocity := velocity
	var original_layer_name := current_collision_layer_name
	var original_collision_layer := collision_layer
	var original_collision_mask := collision_mask
	var target := grid_step_target(from_layer, from_cell, direction_name)
	var to_layer := str(target.get("to_layer", from_layer))
	var to_cell := _grid_variant_to_cell(target.get("to_cell", from_cell))
	var reason := ""
	var supported := false
	var blocked := false
	var collides := false
	var allowed := false
	if _grid_direction_cell_delta(direction_name) == Vector2i.ZERO and not bool(target.get("uses_transition", false)):
		reason = "invalid_direction"
	else:
		global_position = _grid_position_for_cell(from_cell)
		velocity = Vector2.ZERO
		current_collision_layer_name = from_layer
		collision_layer = ACTOR_COLLISION_LAYER_BIT | _layer_collision_bit(from_layer)
		collision_mask = _layer_collision_bit(from_layer)
		var to_position := _grid_position_for_cell(to_cell)
		supported = _is_grid_position_supported(to_position, to_layer)
		if not supported:
			reason = "unsupported"
		else:
			blocked = _is_grid_cell_blocked(to_cell, to_layer)
			if blocked:
				reason = "blocked_cell"
			else:
				collides = _grid_target_collides(to_position, to_layer)
				if collides:
					reason = "collision"
				else:
					allowed = true
		global_position = original_position
		velocity = original_velocity
		current_collision_layer_name = original_layer_name
		collision_layer = original_collision_layer
		collision_mask = original_collision_mask
		set_meta("cainos_runtime_collision_layer_name", current_collision_layer_name)
		set_meta("cainos_runtime_collision_mask", int(collision_mask))
	target["allowed"] = allowed
	target["reason"] = reason
	target["supported"] = supported
	target["blocked"] = blocked
	target["collides"] = collides
	return target


func grid_variant_to_cell(value) -> Vector2i:
	return _grid_variant_to_cell(value)


func _grid_cell_for_position(point: Vector2) -> Vector2i:
	if _has_navigation_map():
		return navigation_map.call("grid_cell_for_position", point)
	var safe_cell_size := maxf(grid_cell_size, 1.0)
	return Vector2i(
		roundi((point.x - grid_origin.x) / safe_cell_size),
		roundi((point.y - grid_origin.y) / safe_cell_size)
	)


func _grid_position_for_cell(cell: Vector2i) -> Vector2:
	if _has_navigation_map():
		return navigation_map.call("grid_position_for_cell", cell)
	var safe_cell_size := maxf(grid_cell_size, 1.0)
	return grid_origin + Vector2(cell) * safe_cell_size


func _grid_direction_name_from_input(input_vector: Vector2) -> String:
	if input_vector.length_squared() <= 0.0001:
		return ""
	if absf(input_vector.x) > absf(input_vector.y):
		return "east" if input_vector.x > 0.0 else "west"
	return "north" if input_vector.y < 0.0 else "south"


func _grid_direction_cell_delta(direction_name: String) -> Vector2i:
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


func _grid_transition_edge(from_layer: String, from_cell: Vector2i, direction_name: String) -> Dictionary:
	if _has_navigation_map():
		return Dictionary(navigation_map.call("transition_edge", from_layer, from_cell, direction_name))
	for edge_variant in grid_transition_edges:
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		if str(edge.get("from_layer", "")) != from_layer:
			continue
		if str(edge.get("direction", "")) != direction_name:
			continue
		if _grid_variant_to_cell(edge.get("from_cell", Vector2i.ZERO)) == from_cell:
			return edge
	return {}


func _has_navigation_map() -> bool:
	return navigation_map != null and navigation_map.has_method("can_step")


func _sync_navigation_map_configuration() -> void:
	if not _has_navigation_map():
		return
	grid_cell_size = float(navigation_map.get("grid_cell_size"))
	grid_origin = Vector2(navigation_map.get("grid_origin"))
	grid_navigation_bounds = Rect2i(navigation_map.get("bounds"))
	grid_transition_edges = Array(navigation_map.get("transition_edges")).duplicate(true)
	grid_blocked_cells_by_layer = _cells_by_layer_from_navigation_map_property("blocked_cells_by_layer")
	set_meta("cainos_grid_navigation_map_path", navigation_map.resource_path)


func _cells_by_layer_from_navigation_map_property(property_name: String) -> Dictionary:
	var result := {}
	if navigation_map == null:
		return result
	var raw_by_layer := Dictionary(navigation_map.get(property_name))
	for layer_name_variant in raw_by_layer.keys():
		var layer_name := str(layer_name_variant)
		var cells := []
		for cell_variant in Array(raw_by_layer.get(layer_name, [])):
			cells.append(_grid_variant_to_cell(cell_variant))
		result[layer_name] = cells
	return result


func _grid_variant_to_cell(value) -> Vector2i:
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


func _grid_variant_to_position(value) -> Vector2:
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


func _grid_position_payloads(points: Array) -> Array:
	var payloads := []
	for point_variant in points:
		var point := _grid_variant_to_position(point_variant)
		payloads.append({"x": point.x, "y": point.y})
	return payloads


func _is_grid_position_supported(point: Vector2, layer_name: String) -> bool:
	var regions := walkable_regions_by_layer.get(layer_name, [])
	if not (regions is Array):
		return true
	var region_array: Array = regions
	if region_array.is_empty():
		return true
	return _is_walkable_position(point, region_array, GRID_WALKABLE_FOOTPRINT_RADIUS)


func _is_grid_cell_blocked(cell: Vector2i, layer_name: String) -> bool:
	var cells := grid_blocked_cells_by_layer.get(layer_name, [])
	if not (cells is Array):
		return false
	for cell_variant in cells:
		if _grid_variant_to_cell(cell_variant) == cell:
			return true
	return false


func _grid_target_collides(target_position: Vector2, layer_name: String) -> bool:
	if _is_grid_collision_bypassed(target_position, layer_name):
		return false
	var original_mask := collision_mask
	collision_mask = _layer_collision_bit(layer_name)
	var collision := move_and_collide(target_position - global_position, true)
	collision_mask = original_mask
	return collision != null


func _is_grid_collision_bypassed(point: Vector2, layer_name: String) -> bool:
	var regions := grid_collision_bypass_regions_by_layer.get(layer_name, [])
	if not (regions is Array):
		return false
	return _is_walkable_position(point, regions, GRID_WALKABLE_FOOTPRINT_RADIUS)


func _apply_runtime_layer_name(layer_name: String) -> void:
	if _player_root != null:
		var helper := _player_root.get_node_or_null("CainosRuntimeActor2D")
		if helper != null and helper.has_method("apply_runtime_layer"):
			helper.call("apply_runtime_layer", layer_name, layer_name)
		else:
			_player_root.set_meta("cainos_runtime_layer_name", layer_name)
			_player_root.set_meta("cainos_runtime_sorting_layer_name", layer_name)
	current_collision_layer_name = layer_name
	collision_layer = ACTOR_COLLISION_LAYER_BIT | _layer_collision_bit(current_collision_layer_name)
	collision_mask = _layer_collision_bit(layer_name)
	set_meta("cainos_runtime_collision_layer_name", current_collision_layer_name)
	set_meta("cainos_runtime_collision_mask", int(collision_mask))


func _apply_controller_facing(direction_name: String, moving: bool) -> void:
	if _controller == null:
		return
	if _controller.has_method("apply_facing"):
		_controller.call("apply_facing", direction_name, moving)


func _constrain_velocity_to_walkable(proposed_velocity: Vector2, delta: float) -> Vector2:
	if proposed_velocity.length_squared() <= 0.0001 or delta <= 0.0:
		return proposed_velocity
	var regions := _current_walkable_regions()
	if regions.is_empty():
		return proposed_velocity
	var current_position := global_position
	var proposed_position := current_position + proposed_velocity * delta
	if _is_walkable_position(proposed_position, regions):
		return proposed_velocity
	var x_only_position := Vector2(proposed_position.x, current_position.y)
	if _is_walkable_position(x_only_position, regions):
		return Vector2(proposed_velocity.x, 0.0)
	var y_only_position := Vector2(current_position.x, proposed_position.y)
	if _is_walkable_position(y_only_position, regions):
		return Vector2(0.0, proposed_velocity.y)
	return Vector2.ZERO


func _current_walkable_regions() -> Array:
	var regions := walkable_regions_by_layer.get(current_collision_layer_name, [])
	return regions if regions is Array else []


func _is_walkable_position(point: Vector2, regions: Array, footprint_radius := WALKABLE_FOOTPRINT_RADIUS) -> bool:
	for sample_point in [
		point,
		point + Vector2(footprint_radius, 0.0),
		point + Vector2(-footprint_radius, 0.0),
		point + Vector2(0.0, footprint_radius),
		point + Vector2(0.0, -footprint_radius),
	]:
		if not _is_walkable_point(sample_point, regions):
			return false
	return true


func _is_walkable_point(point: Vector2, regions: Array) -> bool:
	for region_variant in regions:
		var region: Rect2 = region_variant
		if region.has_point(point):
			return true
	return false


func _push_rigidbody_collisions(input_vector: Vector2, delta: float) -> void:
	if input_vector.length_squared() <= 0.0001:
		return
	var push_direction := input_vector.normalized()
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		if collision == null:
			continue
		var body := collision.get_collider() as RigidBody2D
		if body == null:
			continue
		body.linear_velocity = body.linear_velocity.move_toward(
			push_direction * rigidbody_push_speed_px,
			rigidbody_push_acceleration_px * delta
		)


func _apply_follow_camera() -> void:
	if _follow_camera == null:
		return
	_follow_camera.enabled = true
	_follow_camera.make_current()
	_follow_camera.position = camera_offset
	var viewport_height := get_viewport().get_visible_rect().size.y
	if viewport_height <= 0.0:
		viewport_height = 720.0
	var target_world_height := maxf(camera_unity_orthographic_size * 2.0 * 32.0, 1.0)
	var zoom_factor := maxf(viewport_height / target_world_height, 0.05)
	_follow_camera.zoom = Vector2(zoom_factor, zoom_factor)
	if camera_limits.size.x > 0 and camera_limits.size.y > 0:
		_follow_camera.limit_left = camera_limits.position.x
		_follow_camera.limit_top = camera_limits.position.y
		_follow_camera.limit_right = camera_limits.end.x
		_follow_camera.limit_bottom = camera_limits.end.y
