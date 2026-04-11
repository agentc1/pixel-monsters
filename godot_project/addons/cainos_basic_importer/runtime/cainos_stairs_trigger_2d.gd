extends Node2D

const CainosRuntimeActor2D := preload("res://addons/cainos_basic_importer/runtime/cainos_runtime_actor_2d.gd")
const GROUP_NAME := "cainos_stairs_triggers"
const TRIGGER_THICKNESS := 8.0

@export var direction := "south"
@export var upper_layer := "Layer 2"
@export var upper_sorting_layer := "Layer 2"
@export var lower_layer := "Layer 1"
@export var lower_sorting_layer := "Layer 1"

var _segment_shapes: Array[Dictionary] = []
var _actor_inside_state: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_collect_trigger_segments(self)
	_connect_trigger_areas(self)


func _physics_process(_delta: float) -> void:
	if get_tree() == null:
		return
	var active_ids := {}
	for helper_variant in get_tree().get_nodes_in_group(CainosRuntimeActor2D.GROUP_NAME):
		var helper := helper_variant as CainosRuntimeActor2D
		if helper == null:
			continue
		var actor_root := helper.get_actor_root()
		if actor_root == null or not is_instance_valid(actor_root):
			continue
		var actor_id := str(actor_root.get_instance_id())
		active_ids[actor_id] = true
		if _actor_uses_grid_navigation_map(actor_root):
			_actor_inside_state.erase(actor_id)
			continue
		var is_inside := _actor_is_inside_trigger_region(helper.get_runtime_anchor_global_position())
		var was_inside := bool(_actor_inside_state.get(actor_id, false))
		if is_inside and not was_inside:
			_apply_actor_enter_layer(actor_root)
		elif not is_inside and was_inside:
			_apply_actor_exit_layer(actor_root)
		_actor_inside_state[actor_id] = is_inside
	var stale_ids: Array = []
	for actor_id_variant in _actor_inside_state.keys():
		var actor_id := str(actor_id_variant)
		if not active_ids.has(actor_id):
			stale_ids.append(actor_id)
	for actor_id_variant in stale_ids:
		_actor_inside_state.erase(actor_id_variant)


func apply_enter_for_actor(actor_root: Node) -> void:
	if not (actor_root is Node2D):
		return
	if _actor_uses_grid_navigation_map(actor_root as Node2D):
		return
	_apply_actor_enter_layer(actor_root as Node2D)


func apply_exit_for_actor(actor_root: Node) -> void:
	if not (actor_root is Node2D):
		return
	if _actor_uses_grid_navigation_map(actor_root as Node2D):
		return
	_apply_actor_exit_layer(actor_root as Node2D)


func _connect_trigger_areas(node: Node) -> void:
	if node is Area2D:
		var area := node as Area2D
		if not area.body_entered.is_connected(_on_trigger_body_entered):
			area.body_entered.connect(_on_trigger_body_entered)
		if not area.body_exited.is_connected(_on_trigger_body_exited):
			area.body_exited.connect(_on_trigger_body_exited)
	for child in node.get_children():
		_connect_trigger_areas(child)


func _collect_trigger_segments(node: Node) -> void:
	if node is CollisionShape2D:
		var collision_shape := node as CollisionShape2D
		if collision_shape.shape is SegmentShape2D:
			var shape := collision_shape.shape as SegmentShape2D
			_segment_shapes.append({
				"node": collision_shape,
				"a": collision_shape.to_global(shape.a),
				"b": collision_shape.to_global(shape.b),
			})
	for child in node.get_children():
		_collect_trigger_segments(child)


func _on_trigger_body_entered(body: Node) -> void:
	var actor_root := _resolve_actor_root_from_node(body)
	if actor_root != null:
		if _actor_uses_grid_navigation_map(actor_root):
			_actor_inside_state.erase(str(actor_root.get_instance_id()))
			return
		_actor_inside_state[str(actor_root.get_instance_id())] = true
		_apply_actor_enter_layer(actor_root)


func _on_trigger_body_exited(body: Node) -> void:
	var actor_root := _resolve_actor_root_from_node(body)
	if actor_root != null:
		if _actor_uses_grid_navigation_map(actor_root):
			_actor_inside_state.erase(str(actor_root.get_instance_id()))
			return
		_actor_inside_state[str(actor_root.get_instance_id())] = false
		_apply_actor_exit_layer(actor_root)


func _resolve_actor_root_from_node(node: Node) -> Node2D:
	if node == null:
		return null
	var direct_helper := _find_runtime_actor_helper(node)
	if direct_helper != null:
		return direct_helper.get_actor_root()
	var current := node
	while current != null:
		var helper := _find_runtime_actor_helper(current)
		if helper != null:
			return helper.get_actor_root()
		if current is Node2D and current.has_meta("semantic_origin"):
			return current as Node2D
		current = current.get_parent()
	return null


func _find_runtime_actor_helper(node: Node) -> CainosRuntimeActor2D:
	if node is CainosRuntimeActor2D:
		return node as CainosRuntimeActor2D
	for child in node.get_children():
		var helper := _find_runtime_actor_helper(child)
		if helper != null:
			return helper
	return null


func _actor_uses_grid_navigation_map(actor_root: Node2D) -> bool:
	var current: Node = actor_root
	while current != null:
		if current.has_method("can_grid_step_from_cell"):
			var navigation_mode := str(current.get("navigation_mode"))
			var navigation_map = current.get("navigation_map")
			if navigation_mode == "grid_cardinal" and navigation_map != null:
				return true
		current = current.get_parent()
	return false


func _matches_lower_side_condition(actor_root: Node2D) -> bool:
	match direction:
		"south":
			return actor_root.global_position.y > global_position.y
		"west":
			return actor_root.global_position.x < global_position.x
		"east":
			return actor_root.global_position.x > global_position.x
		"north":
			return actor_root.global_position.y < global_position.y
		_:
			return false


func _apply_actor_enter_layer(actor_root: Node2D) -> void:
	if _matches_lower_side_condition(actor_root):
		_apply_actor_layer(actor_root, upper_layer, upper_sorting_layer)


func _apply_actor_exit_layer(actor_root: Node2D) -> void:
	if _matches_lower_side_condition(actor_root):
		_apply_actor_layer(actor_root, lower_layer, lower_sorting_layer)


func _actor_is_inside_trigger_region(global_point: Vector2) -> bool:
	for segment_variant in _segment_shapes:
		var a: Vector2 = segment_variant.get("a", Vector2.ZERO)
		var b: Vector2 = segment_variant.get("b", Vector2.ZERO)
		if _point_in_segment_band(global_point, a, b):
			return true
	return false


func _point_in_segment_band(point: Vector2, a: Vector2, b: Vector2) -> bool:
	if abs(a.x - b.x) >= abs(a.y - b.y):
		var min_x := minf(a.x, b.x) - TRIGGER_THICKNESS
		var max_x := maxf(a.x, b.x) + TRIGGER_THICKNESS
		return point.x >= min_x and point.x <= max_x and abs(point.y - a.y) <= TRIGGER_THICKNESS
	var min_y := minf(a.y, b.y) - TRIGGER_THICKNESS
	var max_y := maxf(a.y, b.y) + TRIGGER_THICKNESS
	return point.y >= min_y and point.y <= max_y and abs(point.x - a.x) <= TRIGGER_THICKNESS


func _apply_actor_layer(actor_root: Node2D, layer_name: String, sorting_layer_name: String) -> void:
	var helper := _find_runtime_actor_helper(actor_root)
	if helper != null:
		helper.apply_runtime_layer(layer_name, sorting_layer_name)
		return
	_apply_direct_sprite_mutation(actor_root, layer_name, sorting_layer_name)


func _apply_direct_sprite_mutation(actor_root: Node2D, layer_name: String, sorting_layer_name: String) -> void:
	if not actor_root.has_meta("cainos_runtime_base_layer_name"):
		actor_root.set_meta("cainos_runtime_base_layer_name", str(actor_root.get_meta("cainos_runtime_layer_name", lower_layer)))
	var base_layer_name := str(actor_root.get_meta("cainos_runtime_base_layer_name", lower_layer))
	var offset := int(CainosRuntimeActor2D.LAYER_BASE_Z.get(layer_name, 0)) - int(CainosRuntimeActor2D.LAYER_BASE_Z.get(base_layer_name, 0))
	for sprite in _collect_sprites(actor_root):
		if not sprite.has_meta("cainos_base_z_index"):
			sprite.set_meta("cainos_base_z_index", int(sprite.z_index))
		sprite.z_index = int(sprite.get_meta("cainos_base_z_index")) + int(offset)
	actor_root.set_meta("cainos_runtime_layer_name", layer_name)
	actor_root.set_meta("cainos_runtime_sorting_layer_name", sorting_layer_name)
	actor_root.set_meta("cainos_runtime_z_offset", int(offset))


func _collect_sprites(node: Node) -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	if node is Sprite2D:
		sprites.append(node)
	for child in node.get_children():
		sprites.append_array(_collect_sprites(child))
	return sprites
