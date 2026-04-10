extends Node2D

@export var actor_path: NodePath = ^"ProbeActor"
@export var move_speed := 140.0

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
	var camera := get_node_or_null("ProbeActor/Camera2D")
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
	var move := Vector2.ZERO
	if bool(_pressed_keys.get(KEY_A, false)) or bool(_pressed_keys.get(KEY_LEFT, false)):
		move.x -= 1.0
	if bool(_pressed_keys.get(KEY_D, false)) or bool(_pressed_keys.get(KEY_RIGHT, false)):
		move.x += 1.0
	if bool(_pressed_keys.get(KEY_W, false)) or bool(_pressed_keys.get(KEY_UP, false)):
		move.y -= 1.0
	if bool(_pressed_keys.get(KEY_S, false)) or bool(_pressed_keys.get(KEY_DOWN, false)):
		move.y += 1.0
	if move == Vector2.ZERO:
		return
	var actor_node := actor as Node2D
	actor_node.position += move.normalized() * move_speed * delta
