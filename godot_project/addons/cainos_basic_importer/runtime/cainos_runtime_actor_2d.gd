extends Node

const GROUP_NAME := "cainos_runtime_actor_helpers"
const LAYER_Z_OFFSETS := {
	"Layer 1": 0,
	"Layer 2": 100,
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


func _collect_sprite_nodes(node: Node) -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	if node is Sprite2D:
		sprites.append(node)
	for child in node.get_children():
		sprites.append_array(_collect_sprite_nodes(child))
	return sprites


func _layer_z_offset(layer_name: String) -> int:
	return int(LAYER_Z_OFFSETS.get(layer_name, 0))
