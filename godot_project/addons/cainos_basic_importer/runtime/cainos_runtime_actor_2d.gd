extends Node

const GROUP_NAME := "cainos_runtime_actor_helpers"
const SENSOR_NAME := "CainosRuntimeSensor2D"
const SENSOR_INSTANCE_ID_META := "cainos_runtime_actor_instance_id"
const ACTOR_COLLISION_LAYER_BIT := 8
const LAYER_BASE_Z := {
	"Layer 1": 0,
	"Layer 2": 100,
	"Layer 3": 200,
}
const LAYER_COLLISION_BITS := {
	"Layer 1": 1,
	"Layer 2": 2,
	"Layer 3": 4,
}

@export var actor_root_path: NodePath = ^".."
@export var base_layer_name := "Layer 1"
@export var base_sorting_layer_name := "Layer 1"

var current_layer_name := "Layer 1"
var current_sorting_layer_name := "Layer 1"

var _sprite_nodes: Array[Sprite2D] = []
var _sprite_base_z: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP_NAME)
	current_layer_name = base_layer_name
	current_sorting_layer_name = base_sorting_layer_name
	_refresh_sprite_cache()
	call_deferred("_ensure_runtime_sensor")
	reset_runtime_layer()


func get_actor_root() -> Node2D:
	var node := get_node_or_null(actor_root_path)
	if node is Node2D:
		return node
	if get_parent() is Node2D:
		return get_parent() as Node2D
	return null


func get_runtime_anchor_global_position() -> Vector2:
	var actor_root := get_actor_root()
	if actor_root == null:
		return Vector2.ZERO
	return actor_root.global_position


func apply_runtime_layer(layer_name: String, sorting_layer_name: String) -> void:
	var actor_root := get_actor_root()
	if actor_root == null:
		return
	_refresh_sprite_cache()
	current_layer_name = layer_name
	current_sorting_layer_name = sorting_layer_name
	var offset := _layer_z_offset(layer_name)
	for sprite in _sprite_nodes:
		if not is_instance_valid(sprite):
			continue
		var sprite_key := str(sprite.get_instance_id())
		var base_z := int(_sprite_base_z.get(sprite_key, int(sprite.z_index)))
		sprite.z_index = base_z + offset
	actor_root.set_meta("cainos_runtime_layer_name", current_layer_name)
	actor_root.set_meta("cainos_runtime_sorting_layer_name", current_sorting_layer_name)
	actor_root.set_meta("cainos_runtime_z_offset", offset)
	_apply_runtime_physics_layer(actor_root, current_layer_name)


func reset_runtime_layer() -> void:
	apply_runtime_layer(base_layer_name, base_sorting_layer_name)


func _refresh_sprite_cache() -> void:
	var actor_root := get_actor_root()
	if actor_root == null:
		_sprite_nodes.clear()
		_sprite_base_z.clear()
		return
	_sprite_nodes = _collect_sprite_nodes(actor_root)
	for sprite in _sprite_nodes:
		if not is_instance_valid(sprite):
			continue
		if not sprite.has_meta("cainos_base_z_index"):
			sprite.set_meta("cainos_base_z_index", int(sprite.z_index))
		_sprite_base_z[str(sprite.get_instance_id())] = int(sprite.get_meta("cainos_base_z_index"))


func _ensure_runtime_sensor() -> void:
	var actor_root := get_actor_root()
	if actor_root == null or actor_root is PhysicsBody2D:
		return
	var sensor := actor_root.get_node_or_null(SENSOR_NAME) as Area2D
	if sensor == null:
		sensor = Area2D.new()
		sensor.name = SENSOR_NAME
		sensor.monitoring = true
		sensor.monitorable = true
		sensor.collision_layer = ACTOR_COLLISION_LAYER_BIT
		sensor.collision_mask = ACTOR_COLLISION_LAYER_BIT
		actor_root.add_child(sensor)
	var shape_node := sensor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		sensor.add_child(shape_node)
	var bounds := _sprite_bounds_rect()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		bounds = Rect2(Vector2(-8.0, -8.0), Vector2(16.0, 16.0))
	sensor.position = bounds.position + bounds.size * 0.5
	if not (shape_node.shape is RectangleShape2D):
		shape_node.shape = RectangleShape2D.new()
	var shape := shape_node.shape as RectangleShape2D
	shape.size = Vector2(maxf(bounds.size.x, 1.0), maxf(bounds.size.y, 1.0))
	sensor.set_meta(SENSOR_INSTANCE_ID_META, str(actor_root.get_instance_id()))


func _sprite_bounds_rect() -> Rect2:
	var has_rect := false
	var merged := Rect2()
	for sprite in _sprite_nodes:
		if not is_instance_valid(sprite):
			continue
		var size := Vector2.ZERO
		if sprite.region_enabled:
			size = sprite.region_rect.size
		elif sprite.texture != null:
			size = sprite.texture.get_size()
		if size.x <= 0.0 or size.y <= 0.0:
			continue
		var sprite_rect := Rect2(sprite.position, size)
		if not has_rect:
			merged = sprite_rect
			has_rect = true
		else:
			merged = merged.merge(sprite_rect)
	return merged if has_rect else Rect2()


func _collect_sprite_nodes(node: Node) -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	if node is Sprite2D:
		sprites.append(node)
	for child in node.get_children():
		sprites.append_array(_collect_sprite_nodes(child))
	return sprites


func _layer_z_offset(layer_name: String) -> int:
	return _layer_base_z(layer_name) - _layer_base_z(base_layer_name)


func _layer_base_z(layer_name: String) -> int:
	return int(LAYER_BASE_Z.get(layer_name, 0))


func _apply_runtime_physics_layer(actor_root: Node2D, layer_name: String) -> void:
	var body := _find_runtime_elevation_body(actor_root)
	if body == null:
		return
	body.collision_layer = ACTOR_COLLISION_LAYER_BIT | _layer_collision_bit(layer_name)
	body.collision_mask = _layer_collision_bit(layer_name)
	body.set_meta("cainos_runtime_collision_layer_name", layer_name)
	body.set_meta("cainos_runtime_collision_mask", int(body.collision_mask))


func _find_runtime_elevation_body(actor_root: Node) -> PhysicsBody2D:
	var current := actor_root
	while current != null:
		if current is PhysicsBody2D and _supports_runtime_elevation_physics(current):
			return current as PhysicsBody2D
		current = current.get_parent()
	return null


func _supports_runtime_elevation_physics(node: Node) -> bool:
	if node.has_meta("cainos_runtime_elevation_body"):
		return true
	var script = node.get_script()
	return script != null and str(script.resource_path).ends_with("cainos_runtime_player_body_2d.gd")


func _layer_collision_bit(layer_name: String) -> int:
	return int(LAYER_COLLISION_BITS.get(layer_name, LAYER_COLLISION_BITS["Layer 1"]))
