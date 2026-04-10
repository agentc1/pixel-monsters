extends Node

@export var actor_path: NodePath
@export var movement_speed := 120.0
@export var movement_bounds := Rect2(Vector2(64, 64), Vector2(512, 288))
@export var walkable_regions: Array[Rect2] = []

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


func _ready() -> void:
	var actor := get_node_or_null(actor_path)
	if actor is Node:
		var camera := (actor as Node).get_node_or_null("FollowCamera2D")
		if camera is Camera2D:
			(camera as Camera2D).enabled = true
			(camera as Camera2D).make_current()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.echo:
		return
	var keycode := int(key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode)
	if _pressed_keys.has(keycode):
		_pressed_keys[keycode] = key_event.pressed


func _physics_process(delta: float) -> void:
	var actor := get_node_or_null(actor_path)
	if not (actor is Node2D):
		return
	var input_vector := _movement_input()
	if input_vector == Vector2.ZERO:
		return
	var actor_node := actor as Node2D
	var current_position := actor_node.position
	var proposed_position := current_position + input_vector.normalized() * movement_speed * delta
	if movement_bounds.size.x > 0.0 and movement_bounds.size.y > 0.0:
		proposed_position = Vector2(
			clampf(proposed_position.x, movement_bounds.position.x, movement_bounds.end.x),
			clampf(proposed_position.y, movement_bounds.position.y, movement_bounds.end.y)
		)
	actor_node.position = _resolve_walkable_position(current_position, proposed_position)


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
