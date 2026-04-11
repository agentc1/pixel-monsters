extends Node2D

const RuntimePlayerBody := preload("res://addons/cainos_basic_importer/runtime/cainos_runtime_player_body_2d.gd")
const GridProbeController := preload("res://tests/mcp/grid_probe_controller.gd")

const CELL_SIZE := 32.0

var _player: CharacterBody2D


func _ready() -> void:
	_build_visual_grid()
	_build_runtime_player()
	set_physics_process(true)
	_update_probe_meta()


func _physics_process(_delta: float) -> void:
	_update_probe_meta()


func _build_visual_grid() -> void:
	_add_cell_rect(Vector2i(0, 1), Color(0.22, 0.30, 0.18), Vector2i(1, 1))
	_add_cell_rect(Vector2i(0, 0), Color(0.28, 0.52, 0.30), Vector2i(2, 1))
	_add_cell_rect(Vector2i(2, 0), Color(0.55, 0.18, 0.16), Vector2i(1, 1))
	_add_cell_rect(Vector2i(1, 1), Color(0.11, 0.11, 0.11), Vector2i(1, 1))
	_add_cell_outline(Vector2i(0, 1), Color(0.85, 0.78, 0.28))
	_add_cell_outline(Vector2i(0, 0), Color(0.85, 0.78, 0.28))
	_add_cell_outline(Vector2i(1, 0), Color(0.85, 0.78, 0.28))
	_add_cell_outline(Vector2i(2, 0), Color(1.0, 0.35, 0.30))
	_add_cell_outline(Vector2i(1, 1), Color(1.0, 0.35, 0.30))


func _build_runtime_player() -> void:
	_player = CharacterBody2D.new()
	_player.name = "RuntimePlayer"
	_player.position = Vector2(0.0, CELL_SIZE)
	_player.collision_layer = 9
	_player.collision_mask = 1
	_player.set_script(RuntimePlayerBody)
	_player.set_meta("cainos_runtime_elevation_body", true)
	_player.set_meta("cainos_runtime_collision_layer_name", "Layer 1")
	_player.set("player_root_path", NodePath("ProbeController"))
	_player.set("controller_path", NodePath("ProbeController"))
	_player.set("follow_camera_path", NodePath("FollowCamera2D"))
	_player.set("navigation_mode", "grid_cardinal")
	_player.set("grid_cell_size", CELL_SIZE)
	_player.set("grid_origin", Vector2.ZERO)
	_player.set("grid_step_duration_sec", 0.08)
	_player.set("walkable_regions_by_layer", {
		"Layer 2": [
			Rect2(Vector2(-16.0, -16.0), Vector2(96.0, 32.0)),
		],
	})
	_player.set("grid_transition_edges", [
		{
			"kind": "stairs",
			"from_layer": "Layer 1",
			"from_cell": Vector2i(0, 1),
			"direction": "north",
			"to_layer": "Layer 2",
			"to_cell": Vector2i(0, 0),
		},
		{
			"kind": "stairs",
			"from_layer": "Layer 2",
			"from_cell": Vector2i(0, 0),
			"direction": "south",
			"to_layer": "Layer 1",
			"to_cell": Vector2i(0, 1),
		},
	])
	_player.set("grid_blocked_cells_by_layer", {
		"Layer 2": [Vector2i(2, 0)],
	})
	add_child(_player)

	var shape_node := CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(30.0, 30.0)
	shape_node.shape = shape
	_player.add_child(shape_node)

	var controller := Node2D.new()
	controller.name = "ProbeController"
	controller.set_script(GridProbeController)
	_player.add_child(controller)

	var body := Polygon2D.new()
	body.name = "ProbeBody"
	body.color = Color(0.82, 0.34, 0.20)
	body.polygon = PackedVector2Array([
		Vector2(-8.0, -18.0),
		Vector2(8.0, -18.0),
		Vector2(8.0, 6.0),
		Vector2(-8.0, 6.0),
	])
	controller.add_child(body)

	var camera := Camera2D.new()
	camera.name = "FollowCamera2D"
	camera.position = Vector2(32.0, -32.0)
	camera.enabled = true
	_player.add_child(camera)


func _add_cell_rect(cell: Vector2i, color: Color, size_cells: Vector2i) -> void:
	var rect := Polygon2D.new()
	rect.color = color
	var origin := Vector2(cell) * CELL_SIZE - Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
	var size := Vector2(size_cells) * CELL_SIZE
	rect.polygon = PackedVector2Array([
		origin,
		origin + Vector2(size.x, 0.0),
		origin + size,
		origin + Vector2(0.0, size.y),
	])
	add_child(rect)


func _add_cell_outline(cell: Vector2i, color: Color) -> void:
	var outline := Line2D.new()
	outline.default_color = color
	outline.width = 1.0
	var origin := Vector2(cell) * CELL_SIZE - Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
	outline.points = PackedVector2Array([
		origin,
		origin + Vector2(CELL_SIZE, 0.0),
		origin + Vector2(CELL_SIZE, CELL_SIZE),
		origin + Vector2(0.0, CELL_SIZE),
		origin,
	])
	add_child(outline)


func _update_probe_meta() -> void:
	if _player == null:
		return
	var cell := Vector2i(roundi(_player.global_position.x / CELL_SIZE), roundi(_player.global_position.y / CELL_SIZE))
	var player_root := _player.get_node_or_null("ProbeController")
	var layer_name := "Layer 1"
	if player_root != null:
		layer_name = str(player_root.get_meta("cainos_runtime_layer_name", layer_name))
	set_meta("player_position", _player.global_position)
	set_meta("player_cell", cell)
	set_meta("player_layer", layer_name)
	set_meta("player_collision_layer", int(_player.collision_layer))
	set_meta("player_collision_mask", int(_player.collision_mask))
