extends Node2D

const CainosGridNavigationMap := preload("res://addons/cainos_basic_importer/runtime/cainos_grid_navigation_map.gd")
const CainosGridNavigationOverlay2D := preload("res://addons/cainos_basic_importer/runtime/cainos_grid_navigation_overlay_2d.gd")
const CainosRuntimePlayerBody2D := preload("res://addons/cainos_basic_importer/runtime/cainos_runtime_player_body_2d.gd")

const GRID_CELL_SIZE := 32.0
const GRID_ORIGIN := Vector2(520.0, 328.0)
const PLAYER_SCENE_PATH := "res://cainos_imports/basic_real_acceptance/scenes/prefabs/player/PF Player.tscn"
const STAIRS_SCENE_PATH := "res://cainos_imports/basic_real_acceptance/scenes/prefabs/struct/PF Struct - Stairs E 01.tscn"
const STAIR_LOCAL_BOUNDS := Rect2(Vector2(-8.0, -32.0), Vector2(88.0, 96.0))
const FROM_CELL := Vector2i(1, 1)
const TO_CELL := Vector2i(0, 0)
const START_CELL := Vector2i(2, 1)
const WAYPOINT := GRID_ORIGIN + Vector2(16.0, 16.0)

const LAYER_1_CELLS := [
	Vector2i(1, 1),
	Vector2i(2, 1),
	Vector2i(3, 1),
	Vector2i(1, 2),
	Vector2i(2, 2),
	Vector2i(3, 2),
]
const LAYER_2_CELLS := [
	Vector2i(-2, -1),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(-2, 0),
	Vector2i(-1, 0),
	Vector2i(0, 0),
	Vector2i(-2, 1),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]
const STAIR_FOUR_CELLS := [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(1, 1),
]

const COLOR_BACKGROUND := Color(0.075, 0.085, 0.09, 1.0)
const COLOR_LAYER_1 := Color(0.76, 0.48, 0.16, 0.92)
const COLOR_LAYER_2 := Color(0.28, 0.55, 0.64, 0.92)
const COLOR_GRID := Color(1.0, 1.0, 1.0, 0.18)
const COLOR_PATH := Color(1.0, 0.88, 0.2, 1.0)
const COLOR_TEXT := Color(0.92, 0.94, 0.95, 1.0)
const COLOR_MUTED_TEXT := Color(0.68, 0.73, 0.75, 1.0)

var _navigation_map: Resource


func _ready() -> void:
	DisplayServer.window_set_title("Cainos East/West Stair Runtime Demo")
	DisplayServer.window_set_size(Vector2i(1180, 720))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_navigation_map = _build_navigation_map()
	_build_visual_scene()
	_build_runtime_player()
	_build_navigation_overlay()
	_build_camera()
	_build_legend()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COLOR_BACKGROUND, true)
	_draw_floor_cells()
	_draw_grid_lines()
	_draw_transition_path()


func _build_visual_scene() -> void:
	var stair_scene := load(STAIRS_SCENE_PATH) as PackedScene
	if stair_scene != null:
		var stairs := stair_scene.instantiate() as Node2D
		stairs.name = "Actual PF Struct - Stairs E 01"
		stairs.position = WAYPOINT - STAIR_LOCAL_BOUNDS.get_center()
		stairs.z_as_relative = false
		stairs.z_index = 20
		_disable_collision_objects(stairs)
		add_child(stairs)
	else:
		push_warning("Missing generated stair asset: %s" % STAIRS_SCENE_PATH)
		_build_stair_placeholder()


func _build_runtime_player() -> void:
	var player_scene := load(PLAYER_SCENE_PATH) as PackedScene
	var player_root: Node2D
	if player_scene != null:
		player_root = player_scene.instantiate() as Node2D
	else:
		push_warning("Missing generated player asset: %s" % PLAYER_SCENE_PATH)
		player_root = _build_player_placeholder()
	player_root.name = "PF Player"
	player_root.position = Vector2.ZERO
	player_root.scale = Vector2.ONE
	if player_root.has_method("set"):
		player_root.set("movement_mode", "external_body")
		player_root.set("movement_bounds", Rect2())
		player_root.set("walkable_regions", [])

	var actor_helper := player_root.get_node_or_null("CainosRuntimeActor2D")
	if actor_helper != null:
		actor_helper.set("base_layer_name", "Layer 1")
		actor_helper.set("base_sorting_layer_name", "Layer 1")
	_disable_collision_objects(player_root)

	var runtime_player := CharacterBody2D.new()
	runtime_player.name = "RuntimePlayer"
	runtime_player.position = _grid_position_for_cell(START_CELL)
	runtime_player.collision_layer = 9
	runtime_player.collision_mask = 1
	runtime_player.set_script(CainosRuntimePlayerBody2D)
	runtime_player.set("navigation_mode", "grid_cardinal")
	runtime_player.set("grid_cell_size", GRID_CELL_SIZE)
	runtime_player.set("grid_origin", GRID_ORIGIN)
	runtime_player.set("grid_step_duration_sec", 0.62)
	runtime_player.set("current_collision_layer_name", "Layer 1")
	runtime_player.set("navigation_map", _navigation_map)
	runtime_player.set_meta("cainos_runtime_elevation_body", true)
	runtime_player.add_child(player_root)

	var shape_node := CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(30.0, 30.0)
	shape_node.shape = shape
	shape_node.set_meta("cainos_runtime_player_footprint", true)
	runtime_player.add_child(shape_node)

	var camera := Camera2D.new()
	camera.name = "FollowCamera2D"
	runtime_player.add_child(camera)
	runtime_player.set("player_root_path", NodePath("PF Player"))
	runtime_player.set("controller_path", NodePath("PF Player"))
	runtime_player.set("follow_camera_path", NodePath("FollowCamera2D"))
	add_child(runtime_player)


func _build_navigation_overlay() -> void:
	var overlay := Node2D.new()
	overlay.name = "NavigationOverlay"
	overlay.set_script(CainosGridNavigationOverlay2D)
	overlay.set("player_path", NodePath("../RuntimePlayer"))
	overlay.set("navigation_map", _navigation_map)
	overlay.set("navigation_bounds", Rect2i(-3, -2, 8, 6))
	overlay.set("show_layer_1", true)
	overlay.set("show_layer_2", true)
	overlay.set("show_layer_3", false)
	add_child(overlay)


func _build_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "DemoCamera"
	camera.enabled = true
	camera.position = GRID_ORIGIN + Vector2(16.0, 28.0)
	camera.zoom = Vector2(2.35, 2.35)
	add_child(camera)
	camera.make_current()


func _build_legend() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "CommandLegendHUD"
	var label := Label.new()
	label.name = "Instructions"
	label.text = "\n".join([
		"East/West Stair Runtime Demo",
		"Start on Layer 1 at the east approach. Press A / Left twice: first step reaches the stair, second step ascends diagonally west/north through the center waypoint.",
		"At the upper cell, press D / Right to descend through the same waypoint. Movement uses the real runtime player body and navigation map.",
		"Overlay: 1 toggles Layer 1 amber, 2 toggles Layer 2 cyan. White boxes mark stair transition endpoints.",
	])
	label.position = Vector2(18.0, 16.0)
	label.size = Vector2(1080.0, 120.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	canvas.add_child(label)
	add_child(canvas)


func _build_navigation_map() -> Resource:
	var map := CainosGridNavigationMap.new()
	map.set("grid_cell_size", GRID_CELL_SIZE)
	map.set("grid_origin", GRID_ORIGIN)
	map.set("bounds", Rect2i(-3, -2, 8, 6))
	map.set("layer_names", ["Layer 1", "Layer 2", "Layer 3"])
	map.call("set_walkable_cells", "Layer 1", LAYER_1_CELLS)
	map.call("set_walkable_cells", "Layer 2", LAYER_2_CELLS)
	map.call("set_walkable_cells", "Layer 3", [])
	map.call("set_blocked_cells", "Layer 1", [])
	map.call("set_blocked_cells", "Layer 2", [])
	map.call("set_blocked_cells", "Layer 3", [])
	map.call("set_blocked_edges", "Layer 1", [])
	map.call("set_blocked_edges", "Layer 2", [])
	map.call("set_blocked_edges", "Layer 3", [])
	map.set("transition_edges", [
		{
			"kind": "stairs",
			"source_prefab_path": "Assets/Cainos/Pixel Art Top Down - Basic/Prefab/Props/PF Struct - Stairs E 01.prefab",
			"from_layer": "Layer 1",
			"from_cell": FROM_CELL,
			"direction": "west",
			"to_layer": "Layer 2",
			"to_cell": TO_CELL,
			"movement_kind": "diagonal_stair_waypoint",
			"waypoints": [WAYPOINT],
			"layer_switch_t": 0.5,
		},
		{
			"kind": "stairs",
			"source_prefab_path": "Assets/Cainos/Pixel Art Top Down - Basic/Prefab/Props/PF Struct - Stairs E 01.prefab",
			"from_layer": "Layer 2",
			"from_cell": TO_CELL,
			"direction": "east",
			"to_layer": "Layer 1",
			"to_cell": FROM_CELL,
			"movement_kind": "diagonal_stair_waypoint",
			"waypoints": [WAYPOINT],
			"layer_switch_t": 0.5,
		},
	])
	map.set("source_metadata", {
		"kind": "synthetic_diagonal_stair_runtime_demo",
		"description": "Hand-authored fixture for PF Struct - Stairs E 01 waypoint movement.",
		"from_cell": FROM_CELL,
		"to_cell": TO_CELL,
		"waypoint": WAYPOINT,
	})
	return map


func _draw_floor_cells() -> void:
	for cell_variant in LAYER_1_CELLS:
		var cell: Vector2i = cell_variant
		draw_rect(_cell_rect(cell).grow(-1.0), COLOR_LAYER_1, true)
	for cell_variant in LAYER_2_CELLS:
		var cell: Vector2i = cell_variant
		draw_rect(_cell_rect(cell).grow(-1.0), COLOR_LAYER_2, true)
	for cell_variant in STAIR_FOUR_CELLS:
		var cell: Vector2i = cell_variant
		draw_rect(_cell_rect(cell).grow(-2.0), Color(1.0, 1.0, 1.0, 0.18), false, 2.0)


func _draw_grid_lines() -> void:
	for x in range(-3, 6):
		var line_x := GRID_ORIGIN.x + (float(x) - 0.5) * GRID_CELL_SIZE
		draw_line(Vector2(line_x, GRID_ORIGIN.y - 2.5 * GRID_CELL_SIZE), Vector2(line_x, GRID_ORIGIN.y + 4.0 * GRID_CELL_SIZE), COLOR_GRID, 1.0)
	for y in range(-2, 5):
		var line_y := GRID_ORIGIN.y + (float(y) - 0.5) * GRID_CELL_SIZE
		draw_line(Vector2(GRID_ORIGIN.x - 3.5 * GRID_CELL_SIZE, line_y), Vector2(GRID_ORIGIN.x + 5.0 * GRID_CELL_SIZE, line_y), COLOR_GRID, 1.0)


func _draw_transition_path() -> void:
	var from_position := _grid_position_for_cell(FROM_CELL)
	var to_position := _grid_position_for_cell(TO_CELL)
	draw_line(from_position, WAYPOINT, COLOR_PATH, 3.0)
	draw_line(WAYPOINT, to_position, COLOR_PATH, 3.0)
	draw_circle(WAYPOINT, 4.5, Color(1.0, 1.0, 1.0, 1.0))


func _build_stair_placeholder() -> void:
	for cell_variant in STAIR_FOUR_CELLS:
		var rect := ColorRect.new()
		rect.name = "MissingStairAssetCell"
		rect.color = Color(0.48, 0.39, 0.28, 1.0)
		rect.position = _cell_rect(cell_variant).position
		rect.size = Vector2(GRID_CELL_SIZE, GRID_CELL_SIZE)
		add_child(rect)


func _build_player_placeholder() -> Node2D:
	var player_root := Node2D.new()
	var body := ColorRect.new()
	body.name = "PF Player Sprite"
	body.color = Color(0.88, 0.72, 0.48, 1.0)
	body.position = Vector2(-8.0, -38.0)
	body.size = Vector2(16.0, 38.0)
	player_root.add_child(body)
	return player_root


func _disable_collision_objects(node: Node) -> void:
	if node is CollisionObject2D:
		var collision_object := node as CollisionObject2D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if node is CollisionShape2D:
		(node as CollisionShape2D).disabled = true
	for child in node.get_children():
		_disable_collision_objects(child)


func _grid_position_for_cell(cell: Vector2i) -> Vector2:
	return GRID_ORIGIN + Vector2(cell) * GRID_CELL_SIZE


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_grid_position_for_cell(cell) - Vector2(GRID_CELL_SIZE, GRID_CELL_SIZE) * 0.5, Vector2(GRID_CELL_SIZE, GRID_CELL_SIZE))
