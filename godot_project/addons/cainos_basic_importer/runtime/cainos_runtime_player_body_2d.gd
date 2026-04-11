extends CharacterBody2D

const ACTOR_COLLISION_LAYER_BIT := 1
const LAYER_COLLISION_BITS := {
	"Layer 1": 1,
	"Layer 2": 2,
	"Layer 3": 4,
}

@export var player_root_path: NodePath = ^"PF Player"
@export var controller_path: NodePath = ^"PF Player"
@export var follow_camera_path: NodePath = ^"FollowCamera2D"
@export var camera_limits := Rect2i()
@export var camera_offset := Vector2.ZERO
@export var camera_unity_orthographic_size := 5.0
@export var current_collision_layer_name := "Layer 1"
@export var rigidbody_push_speed_px := 96.0
@export var rigidbody_push_acceleration_px := 960.0

var _player_root: Node2D
var _controller: Node
var _follow_camera: Camera2D


func _ready() -> void:
	set_meta("cainos_runtime_elevation_body", true)
	_resolve_runtime_nodes()
	_sync_runtime_collision_mask()
	_sync_player_root()
	_apply_follow_camera()


func _physics_process(delta: float) -> void:
	_resolve_runtime_nodes()
	_sync_runtime_collision_mask()
	if _controller == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var input_vector := _movement_input()
	velocity = _desired_velocity(input_vector)
	move_and_slide()
	_push_rigidbody_collisions(input_vector, delta)
	_controller.call("step_external_body", input_vector, delta)
	_sync_player_root()


func _movement_input() -> Vector2:
	if _controller != null and _controller.has_method("movement_input_vector"):
		return _controller.call("movement_input_vector")
	return Vector2.ZERO


func _desired_velocity(input_vector: Vector2) -> Vector2:
	if _controller != null and _controller.has_method("desired_velocity_from_input"):
		return _controller.call("desired_velocity_from_input", input_vector)
	return Vector2.ZERO


func _resolve_runtime_nodes() -> void:
	if _player_root == null:
		_player_root = get_node_or_null(player_root_path) as Node2D
	if _controller == null:
		_controller = get_node_or_null(controller_path)
	if _follow_camera == null:
		_follow_camera = get_node_or_null(follow_camera_path) as Camera2D


func _sync_player_root() -> void:
	if _player_root != null:
		_player_root.position = Vector2.ZERO


func _sync_runtime_collision_mask() -> void:
	current_collision_layer_name = _current_runtime_layer_name()
	collision_layer = ACTOR_COLLISION_LAYER_BIT
	collision_mask = _layer_collision_bit(current_collision_layer_name)
	set_meta("cainos_runtime_collision_layer_name", current_collision_layer_name)
	set_meta("cainos_runtime_collision_mask", int(collision_mask))


func _current_runtime_layer_name() -> String:
	if _player_root != null:
		return str(_player_root.get_meta("cainos_runtime_layer_name", current_collision_layer_name))
	return current_collision_layer_name


func _layer_collision_bit(layer_name: String) -> int:
	return int(LAYER_COLLISION_BITS.get(layer_name, LAYER_COLLISION_BITS["Layer 1"]))


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
	var zoom_factor := maxf((camera_unity_orthographic_size * 2.0 * 32.0) / viewport_height, 0.05)
	_follow_camera.zoom = Vector2(zoom_factor, zoom_factor)
	if camera_limits.size.x > 0 and camera_limits.size.y > 0:
		_follow_camera.limit_left = camera_limits.position.x
		_follow_camera.limit_top = camera_limits.position.y
		_follow_camera.limit_right = camera_limits.end.x
		_follow_camera.limit_bottom = camera_limits.end.y
