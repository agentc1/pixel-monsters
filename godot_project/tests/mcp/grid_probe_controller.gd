extends Node2D

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
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.echo:
		return
	var keycode := int(key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode)
	if _pressed_keys.has(keycode):
		_pressed_keys[keycode] = key_event.pressed


func movement_input_vector() -> Vector2:
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


func desired_velocity_from_input(input_vector: Vector2) -> Vector2:
	return input_vector * 96.0


func apply_facing(direction_name: String, moving: bool) -> void:
	set_meta("probe_direction", direction_name)
	set_meta("probe_moving", moving)
