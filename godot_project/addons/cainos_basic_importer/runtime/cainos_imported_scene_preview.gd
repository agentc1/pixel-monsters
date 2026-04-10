extends Node2D

@export_file("*.tscn") var target_scene_path := ""
@export var preview_window_size := Vector2i(1200, 1200)
@export var padding_pixels := 96.0

@onready var _scene_instance: Node2D = get_node("SceneInstance")
@onready var _camera: Camera2D = get_node("PreviewCamera2D")

const TILE_PIXELS := Vector2(32.0, 32.0)


func _ready() -> void:
	_apply_window_size()
	_load_target_scene()
	await _stabilize_preview()
	_fit_camera_to_scene()


func _apply_window_size() -> void:
	var window := get_window()
	if window == null:
		return
	window.mode = Window.MODE_WINDOWED
	window.size = preview_window_size


func _load_target_scene() -> void:
	for child in _scene_instance.get_children():
		child.queue_free()
	if target_scene_path.is_empty():
		push_warning("No target_scene_path configured for scene preview.")
		return
	var packed := load(target_scene_path)
	if not (packed is PackedScene):
		push_warning("Could not load preview target scene: %s" % target_scene_path)
		return
	var instance := (packed as PackedScene).instantiate()
	if instance == null:
		push_warning("Could not instantiate preview target scene: %s" % target_scene_path)
		return
	_scene_instance.add_child(instance)


func _stabilize_preview() -> void:
	_refresh_tile_layers(_scene_instance)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _refresh_tile_layers(node: Node) -> void:
	if node is TileMapLayer and node.has_method("update_internals"):
		node.call("update_internals")
	for child in node.get_children():
		_refresh_tile_layers(child)


func _fit_camera_to_scene() -> void:
	var bounds := _compute_scene_bounds(_scene_instance)
	_camera.enabled = true
	_camera.make_current()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		_camera.position = Vector2.ZERO
		_camera.zoom = Vector2.ONE
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(preview_window_size)
	var usable := Vector2(
		maxf(1.0, viewport_size.x - padding_pixels * 2.0),
		maxf(1.0, viewport_size.y - padding_pixels * 2.0)
	)
	var zoom_factor := maxf(bounds.size.x / usable.x, bounds.size.y / usable.y)
	zoom_factor = maxf(0.05, zoom_factor)
	_camera.position = bounds.get_center()
	_camera.zoom = Vector2(zoom_factor, zoom_factor)


func _compute_scene_bounds(node: Node) -> Rect2:
	var accumulator := {
		"has_bounds": false,
		"min": Vector2.ZERO,
		"max": Vector2.ZERO,
	}
	_accumulate_bounds(node, accumulator)
	if not bool(accumulator.get("has_bounds", false)):
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var min_point: Vector2 = accumulator.get("min", Vector2.ZERO)
	var max_point: Vector2 = accumulator.get("max", Vector2.ZERO)
	return Rect2(min_point, max_point - min_point)


func _accumulate_bounds(node: Node, accumulator: Dictionary) -> void:
	if node is Sprite2D and _canvas_item_visible(node as CanvasItem):
		_accumulate_sprite_bounds(node as Sprite2D, accumulator)
	elif node is TileMapLayer and _canvas_item_visible(node as CanvasItem):
		_accumulate_tile_layer_bounds(node as TileMapLayer, accumulator)
	for child in node.get_children():
		_accumulate_bounds(child, accumulator)


func _canvas_item_visible(item: CanvasItem) -> bool:
	return item.visible


func _accumulate_sprite_bounds(sprite: Sprite2D, accumulator: Dictionary) -> void:
	var size := Vector2.ZERO
	if sprite.region_enabled:
		size = sprite.region_rect.size
	elif sprite.texture != null:
		size = sprite.texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var origin := sprite.offset
	if sprite.centered:
		origin -= size * 0.5
	_expand_transformed_rect(accumulator, sprite.get_global_transform(), Rect2(origin, size))


func _accumulate_tile_layer_bounds(layer: TileMapLayer, accumulator: Dictionary) -> void:
	if not layer.has_method("get_used_cells"):
		return
	var used_cells_variant = layer.call("get_used_cells")
	if not (used_cells_variant is Array):
		return
	var used_cells: Array = used_cells_variant
	if used_cells.is_empty():
		return
	var min_cell := Vector2i(used_cells[0])
	var max_cell := min_cell
	for cell_variant in used_cells:
		var cell: Vector2i = cell_variant
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	var local_rect := Rect2(
		Vector2(min_cell) * TILE_PIXELS,
		Vector2(max_cell - min_cell + Vector2i.ONE) * TILE_PIXELS
	)
	_expand_transformed_rect(accumulator, layer.get_global_transform(), local_rect)


func _expand_transformed_rect(accumulator: Dictionary, transform_2d: Transform2D, rect: Rect2) -> void:
	var corners := [
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + Vector2(0.0, rect.size.y),
		rect.position + rect.size,
	]
	for corner in corners:
		_expand_point(accumulator, transform_2d * corner)


func _expand_point(accumulator: Dictionary, point: Vector2) -> void:
	if not bool(accumulator.get("has_bounds", false)):
		accumulator["has_bounds"] = true
		accumulator["min"] = point
		accumulator["max"] = point
		return
	var min_point: Vector2 = accumulator.get("min", point)
	var max_point: Vector2 = accumulator.get("max", point)
	accumulator["min"] = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
	accumulator["max"] = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))
