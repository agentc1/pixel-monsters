extends Node2D

const GROUP_NAME := "cainos_top_down_player_controllers"
const MOVEMENT_MODE_DIRECT := "direct"
const MOVEMENT_MODE_EXTERNAL_BODY := "external_body"

@export var body_sprite_path: NodePath = ^"PF Player Sprite"
@export var shadow_sprite_path: NodePath = ^"Shadow/Shadow Sprite"
@export var actor_helper_path: NodePath = ^"CainosRuntimeActor2D"
@export var move_speed_px := 96.0
@export_enum("direct", "external_body") var movement_mode := MOVEMENT_MODE_DIRECT
@export var movement_bounds := Rect2()
@export var walkable_regions: Array[Rect2] = []
@export var south_rect := Rect2(6.0, 10.0, 21.0, 48.0)
@export var north_rect := Rect2(38.0, 10.0, 21.0, 48.0)
@export var side_rect := Rect2(69.0, 10.0, 21.0, 48.0)
@export var shadow_rect := Rect2(99.0, 32.0, 27.0, 28.0)
@export var direction_values := {
	"south": 0,
	"north": 1,
	"east": 2,
	"west": 3,
}

var _pressed_keys := {
	KEY_A: false,
	KEY_D: false,
	KEY_W: false,
	KEY_S: false,
	KEY_LEFT: false,
	KEY_RIGHT: false,
	KEY_UP: false,
	KEY_DOWN: false,
}

var _body_sprite: Sprite2D
var _shadow_sprite: Sprite2D
var _actor_helper: Node
var _current_direction := "south"
var _last_pressed_grid_direction := ""
var _queued_grid_direction_press := ""


func _ready() -> void:
	add_to_group(GROUP_NAME)
	set_process_input(true)
	set_physics_process(true)
	_resolve_runtime_nodes()
	_apply_shadow_rect()
	apply_facing(_current_direction, false)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.echo:
		return
	var keycode := int(key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode)
	if _pressed_keys.has(keycode):
		_pressed_keys[keycode] = key_event.pressed
		if key_event.pressed:
			var direction_name := _grid_direction_for_key(keycode)
			if not direction_name.is_empty():
				_last_pressed_grid_direction = direction_name
				_queued_grid_direction_press = direction_name


func _physics_process(delta: float) -> void:
	if movement_mode == MOVEMENT_MODE_EXTERNAL_BODY:
		return
	step_with_input(_movement_input(), delta)


func apply_facing(direction_name: String, moving: bool) -> void:
	_resolve_runtime_nodes()
	var normalized_direction := _normalize_direction(direction_name)
	_current_direction = normalized_direction
	if _body_sprite != null:
		_body_sprite.region_enabled = true
		match normalized_direction:
			"north":
				_body_sprite.region_rect = north_rect
				_body_sprite.flip_h = false
			"east":
				_body_sprite.region_rect = side_rect
				_body_sprite.flip_h = false
			"west":
				_body_sprite.region_rect = side_rect
				_body_sprite.flip_h = true
			_:
				_body_sprite.region_rect = south_rect
				_body_sprite.flip_h = false
	_update_runtime_state(normalized_direction, moving)


func step_with_input(input_vector: Vector2, delta: float) -> void:
	_resolve_runtime_nodes()
	var working_input := input_vector
	if working_input.length_squared() > 1.0:
		working_input = working_input.normalized()
	var moving := working_input.length_squared() > 0.0001
	if moving:
		apply_facing(_direction_from_input(working_input), true)
		var current_position := position
		var proposed_position := current_position + working_input * move_speed_px * delta
		if movement_bounds.size.x > 0.0 and movement_bounds.size.y > 0.0:
			proposed_position = Vector2(
				clampf(proposed_position.x, movement_bounds.position.x, movement_bounds.end.x),
				clampf(proposed_position.y, movement_bounds.position.y, movement_bounds.end.y)
			)
		position = _resolve_walkable_position(current_position, proposed_position)
	else:
		apply_facing(_current_direction, false)


func movement_input_vector() -> Vector2:
	return _movement_input()


func movement_grid_direction() -> String:
	if not _last_pressed_grid_direction.is_empty() and _is_grid_direction_pressed(_last_pressed_grid_direction):
		return _last_pressed_grid_direction
	var input_vector := _movement_input()
	if input_vector.length_squared() <= 0.0001:
		return ""
	var fallback_direction := _direction_from_input(input_vector)
	_last_pressed_grid_direction = fallback_direction
	return fallback_direction


func consume_grid_direction_press() -> String:
	var direction_name := _queued_grid_direction_press
	_queued_grid_direction_press = ""
	return direction_name


func clear_movement_input() -> void:
	for keycode in _pressed_keys.keys():
		_pressed_keys[keycode] = false
	_last_pressed_grid_direction = ""
	_queued_grid_direction_press = ""


func clear_grid_direction_press() -> void:
	_queued_grid_direction_press = ""


func desired_velocity_from_input(input_vector: Vector2) -> Vector2:
	var working_input := input_vector
	if working_input.length_squared() > 1.0:
		working_input = working_input.normalized()
	return working_input * move_speed_px


func step_external_body(input_vector: Vector2, _delta: float) -> void:
	_resolve_runtime_nodes()
	var working_input := input_vector
	if working_input.length_squared() > 1.0:
		working_input = working_input.normalized()
	var moving := working_input.length_squared() > 0.0001
	if moving:
		apply_facing(_direction_from_input(working_input), true)
	else:
		apply_facing(_current_direction, false)


func _movement_input() -> Vector2:
	var x := 0.0
	var y := 0.0
	if bool(_pressed_keys.get(KEY_A, false)) or bool(_pressed_keys.get(KEY_LEFT, false)):
		x -= 1.0
	if bool(_pressed_keys.get(KEY_D, false)) or bool(_pressed_keys.get(KEY_RIGHT, false)):
		x += 1.0
	if bool(_pressed_keys.get(KEY_W, false)) or bool(_pressed_keys.get(KEY_UP, false)):
		y -= 1.0
	if bool(_pressed_keys.get(KEY_S, false)) or bool(_pressed_keys.get(KEY_DOWN, false)):
		y += 1.0
	return Vector2(x, y)


func _grid_direction_for_key(keycode: int) -> String:
	match keycode:
		KEY_A, KEY_LEFT:
			return "west"
		KEY_D, KEY_RIGHT:
			return "east"
		KEY_W, KEY_UP:
			return "north"
		KEY_S, KEY_DOWN:
			return "south"
		_:
			return ""


func _is_grid_direction_pressed(direction_name: String) -> bool:
	match direction_name:
		"west":
			return bool(_pressed_keys.get(KEY_A, false)) or bool(_pressed_keys.get(KEY_LEFT, false))
		"east":
			return bool(_pressed_keys.get(KEY_D, false)) or bool(_pressed_keys.get(KEY_RIGHT, false))
		"north":
			return bool(_pressed_keys.get(KEY_W, false)) or bool(_pressed_keys.get(KEY_UP, false))
		"south":
			return bool(_pressed_keys.get(KEY_S, false)) or bool(_pressed_keys.get(KEY_DOWN, false))
		_:
			return false


func _direction_from_input(input_vector: Vector2) -> String:
	if absf(input_vector.x) > absf(input_vector.y):
		return "east" if input_vector.x > 0.0 else "west"
	if input_vector.y < 0.0:
		return "north"
	return "south"


func _normalize_direction(direction_name: String) -> String:
	match direction_name:
		"north", "south", "east", "west":
			return direction_name
		_:
			return "south"


func _resolve_walkable_position(current_position: Vector2, proposed_position: Vector2) -> Vector2:
	if walkable_regions.is_empty():
		return proposed_position
	if _is_walkable_point(proposed_position):
		return proposed_position
	var x_only := Vector2(proposed_position.x, current_position.y)
	if _is_walkable_point(x_only):
		return x_only
	var y_only := Vector2(current_position.x, proposed_position.y)
	if _is_walkable_point(y_only):
		return y_only
	return current_position


func _is_walkable_point(point: Vector2) -> bool:
	for region_variant in walkable_regions:
		var region: Rect2 = region_variant
		if region.has_point(point):
			return true
	return false


func _update_runtime_state(direction_name: String, moving: bool) -> void:
	set_meta("cainos_player_direction", direction_name)
	set_meta("cainos_player_direction_value", int(direction_values.get(direction_name, 0)))
	set_meta("cainos_player_moving", moving)


func _apply_shadow_rect() -> void:
	_resolve_runtime_nodes()
	if _shadow_sprite == null or shadow_rect.size.x <= 0.0 or shadow_rect.size.y <= 0.0:
		return
	_shadow_sprite.region_enabled = true
	_shadow_sprite.region_rect = shadow_rect


func _resolve_runtime_nodes() -> void:
	if _body_sprite == null:
		_body_sprite = get_node_or_null(body_sprite_path) as Sprite2D
	if _shadow_sprite == null:
		_shadow_sprite = get_node_or_null(shadow_sprite_path) as Sprite2D
	if _actor_helper == null:
		_actor_helper = get_node_or_null(actor_helper_path)
