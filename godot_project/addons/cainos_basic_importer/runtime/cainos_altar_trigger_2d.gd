extends Node2D

const GROUP_NAME := "cainos_altar_trigger_nodes"
const SENSOR_INSTANCE_ID_META := "cainos_runtime_actor_instance_id"

@export var trigger_area_path: NodePath = ^"BoxCollider_0"
@export var rune_node_paths: Array[NodePath] = []
@export var lerp_speed := 3.0

var _trigger_area: Area2D
var _rune_sprites: Array[Sprite2D] = []
var _base_colors: Dictionary = {}
var _active_body_ids: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_trigger_area = get_node_or_null(trigger_area_path) as Area2D
	if _trigger_area != null:
		if not _trigger_area.body_entered.is_connected(_on_trigger_body_entered):
			_trigger_area.body_entered.connect(_on_trigger_body_entered)
		if not _trigger_area.body_exited.is_connected(_on_trigger_body_exited):
			_trigger_area.body_exited.connect(_on_trigger_body_exited)
		if not _trigger_area.area_entered.is_connected(_on_trigger_area_entered):
			_trigger_area.area_entered.connect(_on_trigger_area_entered)
		if not _trigger_area.area_exited.is_connected(_on_trigger_area_exited):
			_trigger_area.area_exited.connect(_on_trigger_area_exited)
	_rune_sprites = _resolve_rune_sprites()
	for sprite in _rune_sprites:
		if not is_instance_valid(sprite):
			continue
		_base_colors[str(sprite.get_instance_id())] = sprite.modulate
	if _rune_sprites.is_empty():
		set_process(false)


func _process(delta: float) -> void:
	var lerp_weight := clampf(lerp_speed * delta, 0.0, 1.0)
	for sprite in _rune_sprites:
		if not is_instance_valid(sprite):
			continue
		var base_color: Color = _base_colors.get(str(sprite.get_instance_id()), sprite.modulate)
		var target_color := Color(base_color.r, base_color.g, base_color.b, _target_alpha(base_color))
		sprite.modulate = sprite.modulate.lerp(target_color, lerp_weight)


func apply_enter_for_body(body: Node) -> void:
	_register_overlap(body, true)


func apply_exit_for_body(body: Node) -> void:
	_register_overlap(body, false)


func is_trigger_active() -> bool:
	return not _active_body_ids.is_empty()


func _on_trigger_body_entered(body: Node) -> void:
	_register_overlap(body, true)


func _on_trigger_body_exited(body: Node) -> void:
	_register_overlap(body, false)


func _on_trigger_area_entered(area: Area2D) -> void:
	_register_overlap(area, true)


func _on_trigger_area_exited(area: Area2D) -> void:
	_register_overlap(area, false)


func _resolve_rune_sprites() -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	for path_variant in rune_node_paths:
		var rune_node := get_node_or_null(path_variant)
		if rune_node == null:
			continue
		var sprite := _find_first_sprite(rune_node)
		if sprite != null:
			sprites.append(sprite)
	return sprites


func _find_first_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node as Sprite2D
	for child in node.get_children():
		var sprite := _find_first_sprite(child)
		if sprite != null:
			return sprite
	return null


func _target_alpha(base_color: Color) -> float:
	return 1.0 if is_trigger_active() else base_color.a


func _register_overlap(node: Node, entering: bool) -> void:
	var overlap_key := _overlap_key_for_node(node)
	if overlap_key.is_empty():
		return
	if entering:
		_active_body_ids[overlap_key] = true
	else:
		_active_body_ids.erase(overlap_key)


func _overlap_key_for_node(node: Node) -> String:
	if node == null:
		return ""
	if node is PhysicsBody2D:
		return "body:%s" % str(node.get_instance_id())
	if node is Area2D and node.has_meta(SENSOR_INSTANCE_ID_META):
		return "actor:%s" % str(node.get_meta(SENSOR_INSTANCE_ID_META))
	return ""
