extends Node2D

const DISPLAY_CELL := 96.0
const ASSET_PIXEL_SCALE := DISPLAY_CELL / 32.0
const FROM_CELL := Vector2i(0, 1)
const TO_CELL := Vector2i(-1, 0)
const STAIR_CELLS := [
	Vector2i(-1, 0),
	Vector2i(0, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]
const STEP_SECONDS := 2.4
const PAUSE_SECONDS := 0.55
const STAIR_TEXTURE_PATH := "res://cainos_imports/basic_real_acceptance/textures/source/TX Struct.png"
const STAIR_ASSET_NAME := "PF Struct - Stairs E 01"
const STAIR_UPPER_REGION := Rect2(184.0, 384.0, 88.0, 46.0)
const STAIR_LOWER_REGION := Rect2(184.0, 430.0, 88.0, 50.0)
const STAIR_UPPER_LOCAL := Vector2(-8.0, -32.0)
const STAIR_LOWER_LOCAL := Vector2(-8.0, 14.0)
const STAIR_LOCAL_BOUNDS := Rect2(Vector2(-8.0, -32.0), Vector2(88.0, 96.0))

const COLOR_BACKGROUND := Color(0.07, 0.085, 0.095, 1.0)
const COLOR_GRID := Color(0.62, 0.68, 0.72, 0.28)
const COLOR_STAIRS := Color(0.55, 0.47, 0.36, 0.72)
const COLOR_LAYER_1 := Color(1.0, 0.68, 0.10, 1.0)
const COLOR_LAYER_2 := Color(0.05, 0.82, 1.0, 1.0)
const COLOR_WAYPOINT := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_BAD_ROUTE := Color(1.0, 0.20, 0.16, 0.78)
const COLOR_GOOD_ROUTE := Color(1.0, 0.92, 0.28, 1.0)
const COLOR_TEXT := Color(0.91, 0.94, 0.95, 1.0)
const COLOR_MUTED_TEXT := Color(0.66, 0.72, 0.74, 1.0)

var _elapsed := 0.0
var _paused := false
var _reverse := false
var _labels := {}
var _stair_texture: Texture2D


func _ready() -> void:
	DisplayServer.window_set_title("East/West Stair Waypoint Demo")
	DisplayServer.window_set_size(Vector2i(1180, 720))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stair_texture = load(STAIR_TEXTURE_PATH) as Texture2D
	_create_labels()
	queue_redraw()


func _process(delta: float) -> void:
	if not _paused:
		_elapsed += maxf(delta, 0.0)
	_layout_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_SPACE:
			_elapsed = 0.0
			_reverse = false
		KEY_R:
			_elapsed = 0.0
			_reverse = not _reverse
		KEY_P:
			_paused = not _paused
		_:
			return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COLOR_BACKGROUND, true)
	_draw_grid()
	_draw_stair_asset()
	_draw_bad_route()
	_draw_good_route()
	_draw_player()


func _create_labels() -> void:
	_labels["title"] = _add_label("Title", "East/West Stair Waypoint Prototype", 26, COLOR_TEXT)
	_labels["summary"] = _add_label(
		"Summary",
		"PF Struct - Stairs E 01 ascends from east to west. Cardinal input still resolves to normal 32x32 grid cells, with a visual waypoint at the shared corner of the four stair tiles.",
		16,
		COLOR_MUTED_TEXT
	)
	_labels["controls"] = _add_label("Controls", "Space replay  |  R reverse  |  P pause", 15, COLOR_MUTED_TEXT)
	_labels["start"] = _add_label("StartLabel", "Layer 1 east-side start cell\npress West", 15, COLOR_LAYER_1)
	_labels["waypoint"] = _add_label("WaypointLabel", "stair center waypoint\nlayer switch here", 15, COLOR_WAYPOINT)
	_labels["end"] = _add_label("EndLabel", "Layer 2 end cell\nsnapped to center", 15, COLOR_LAYER_2)
	_labels["bad"] = _add_label("BadRouteLabel", "red: two normal NSEW steps miss the stair center", 15, COLOR_BAD_ROUTE)
	_labels["good"] = _add_label("GoodRouteLabel", "yellow: one stair transition, animated through the four-tile intersection", 15, COLOR_GOOD_ROUTE)
	_labels["asset"] = _add_label("AssetLabel", "actual asset: %s\n%s" % [STAIR_ASSET_NAME, STAIR_TEXTURE_PATH], 14, COLOR_MUTED_TEXT)


func _add_label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _layout_labels() -> void:
	var viewport_size := get_viewport_rect().size
	_set_label("title", Vector2(32.0, 24.0), Vector2(viewport_size.x - 64.0, 40.0))
	_set_label("summary", Vector2(32.0, 64.0), Vector2(viewport_size.x - 64.0, 54.0))
	_set_label("controls", Vector2(32.0, viewport_size.y - 52.0), Vector2(viewport_size.x - 64.0, 28.0))
	_set_label("start", _cell_position(FROM_CELL) + Vector2(-220.0, 30.0), Vector2(190.0, 52.0))
	_set_label("waypoint", _waypoint_position() + Vector2(26.0, -60.0), Vector2(210.0, 52.0))
	_set_label("end", _cell_position(TO_CELL) + Vector2(38.0, -82.0), Vector2(190.0, 52.0))
	_set_label("bad", Vector2(32.0, 126.0), Vector2(420.0, 28.0))
	_set_label("good", Vector2(32.0, 152.0), Vector2(520.0, 28.0))
	_set_label("asset", _waypoint_position() + Vector2(-170.0, 166.0), Vector2(390.0, 46.0))


func _set_label(key: String, label_position: Vector2, label_size: Vector2) -> void:
	var label: Label = _labels.get(key)
	if label == null:
		return
	label.position = label_position
	label.size = label_size


func _draw_grid() -> void:
	for x in range(-3, 4):
		var line_x := _origin().x + (float(x) - 0.5) * DISPLAY_CELL
		draw_line(Vector2(line_x, _origin().y - 2.5 * DISPLAY_CELL), Vector2(line_x, _origin().y + 2.5 * DISPLAY_CELL), COLOR_GRID, 1.0)
	for y in range(-2, 4):
		var line_y := _origin().y + (float(y) - 0.5) * DISPLAY_CELL
		draw_line(Vector2(_origin().x - 3.5 * DISPLAY_CELL, line_y), Vector2(_origin().x + 2.5 * DISPLAY_CELL, line_y), COLOR_GRID, 1.0)
	for cell_variant in [FROM_CELL, TO_CELL]:
		var cell: Vector2i = cell_variant
		var color := COLOR_LAYER_1 if cell == FROM_CELL else COLOR_LAYER_2
		draw_rect(_cell_rect(cell).grow(-4.0), Color(color.r, color.g, color.b, 0.20), true)
		draw_rect(_cell_rect(cell).grow(-4.0), color, false, 3.0)


func _draw_stair_asset() -> void:
	if _stair_texture is Texture2D:
		_draw_imported_stair_texture()
		_draw_waypoint_marker()
		return
	_draw_fallback_stair_block()
	_draw_waypoint_marker()


func _draw_imported_stair_texture() -> void:
	var asset_origin := _asset_root_position()
	_draw_stair_region(STAIR_LOWER_LOCAL, STAIR_LOWER_REGION, Color(1.0, 1.0, 1.0, 0.94))
	_draw_stair_region(STAIR_UPPER_LOCAL, STAIR_UPPER_REGION, Color(1.0, 1.0, 1.0, 1.0))
	var bounds := Rect2(
		asset_origin + STAIR_LOCAL_BOUNDS.position * ASSET_PIXEL_SCALE,
		STAIR_LOCAL_BOUNDS.size * ASSET_PIXEL_SCALE
	)
	draw_rect(bounds, Color(1.0, 1.0, 1.0, 0.30), false, 2.0)


func _draw_stair_region(local_position: Vector2, source_region: Rect2, color: Color) -> void:
	var destination := Rect2(
		_asset_root_position() + local_position * ASSET_PIXEL_SCALE,
		source_region.size * ASSET_PIXEL_SCALE
	)
	draw_texture_rect_region(_stair_texture, destination, source_region, color)


func _draw_fallback_stair_block() -> void:
	for cell_variant in STAIR_CELLS:
		var cell: Vector2i = cell_variant
		draw_rect(_cell_rect(cell).grow(-8.0), COLOR_STAIRS, true)
		draw_rect(_cell_rect(cell).grow(-8.0), Color(0.23, 0.18, 0.14, 0.88), false, 2.0)
		var rect := _cell_rect(cell).grow(-14.0)
		for index in range(4):
			var y := rect.position.y + float(index + 1) * rect.size.y / 5.0
			draw_line(Vector2(rect.position.x + 8.0, y), Vector2(rect.end.x - 8.0, y), Color(0.30, 0.25, 0.20, 0.8), 2.0)


func _draw_waypoint_marker() -> void:
	var waypoint := _waypoint_position()
	draw_circle(waypoint, 11.0, COLOR_WAYPOINT)
	draw_circle(waypoint, 18.0, Color(1.0, 1.0, 1.0, 0.17))


func _asset_root_position() -> Vector2:
	return _waypoint_position() - STAIR_LOCAL_BOUNDS.get_center() * ASSET_PIXEL_SCALE


func _draw_bad_route() -> void:
	var start := _cell_position(FROM_CELL)
	var wrong_corner := Vector2(_cell_position(TO_CELL).x, start.y)
	var end := _cell_position(TO_CELL)
	_draw_dashed_line(start, wrong_corner, COLOR_BAD_ROUTE, 4.0, 14.0, 8.0)
	_draw_dashed_line(wrong_corner, end, COLOR_BAD_ROUTE, 4.0, 14.0, 8.0)
	draw_circle(wrong_corner, 7.0, COLOR_BAD_ROUTE)


func _draw_good_route() -> void:
	var start := _cell_position(FROM_CELL)
	var waypoint := _waypoint_position()
	var end := _cell_position(TO_CELL)
	draw_line(start, waypoint, COLOR_GOOD_ROUTE, 7.0)
	draw_line(waypoint, end, COLOR_GOOD_ROUTE, 7.0)
	_draw_arrow_head(start, waypoint, COLOR_GOOD_ROUTE)
	_draw_arrow_head(waypoint, end, COLOR_GOOD_ROUTE)


func _draw_player() -> void:
	var progress := _animation_progress()
	var position := _path_position(progress)
	var on_upper_layer := progress >= 0.5
	var layer_color := COLOR_LAYER_2 if on_upper_layer else COLOR_LAYER_1
	var lower_body_size := Vector2(DISPLAY_CELL * 0.36, DISPLAY_CELL * 0.36)
	var lower_body_rect := Rect2(position - lower_body_size * 0.5, lower_body_size)
	draw_circle(position + Vector2(0.0, -28.0), 18.0, Color(0.92, 0.78, 0.56, 1.0))
	draw_rect(lower_body_rect, layer_color, true)
	draw_rect(lower_body_rect, Color(0.02, 0.02, 0.02, 1.0), false, 3.0)
	draw_line(position + Vector2(-24.0, -50.0), position + Vector2(24.0, -50.0), layer_color, 5.0)


func _animation_progress() -> float:
	var cycle_length := STEP_SECONDS + PAUSE_SECONDS
	var local_time := fposmod(_elapsed, cycle_length)
	var progress := clampf(local_time / STEP_SECONDS, 0.0, 1.0)
	if _reverse:
		return 1.0 - progress
	return progress


func _path_position(progress: float) -> Vector2:
	var start := _cell_position(FROM_CELL)
	var waypoint := _waypoint_position()
	var end := _cell_position(TO_CELL)
	if progress <= 0.5:
		return start.lerp(waypoint, progress / 0.5)
	return waypoint.lerp(end, (progress - 0.5) / 0.5)


func _waypoint_position() -> Vector2:
	return _cell_position(FROM_CELL).lerp(_cell_position(TO_CELL), 0.5)


func _cell_position(cell: Vector2i) -> Vector2:
	return _origin() + Vector2(cell) * DISPLAY_CELL


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_cell_position(cell) - Vector2(DISPLAY_CELL, DISPLAY_CELL) * 0.5, Vector2(DISPLAY_CELL, DISPLAY_CELL))


func _origin() -> Vector2:
	var viewport_size := get_viewport_rect().size
	return Vector2(viewport_size.x * 0.52, viewport_size.y * 0.52)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash_length: float, gap_length: float) -> void:
	var vector := to - from
	var distance := vector.length()
	if distance <= 0.001:
		return
	var direction := vector / distance
	var cursor := 0.0
	while cursor < distance:
		var segment_end := minf(cursor + dash_length, distance)
		draw_line(from + direction * cursor, from + direction * segment_end, color, width)
		cursor += dash_length + gap_length


func _draw_arrow_head(from: Vector2, to: Vector2, color: Color) -> void:
	var vector := to - from
	if vector.length_squared() <= 0.001:
		return
	var direction := vector.normalized()
	var normal := Vector2(-direction.y, direction.x)
	var tip := to - direction * 18.0
	var points := PackedVector2Array([
		tip,
		tip - direction * 18.0 + normal * 9.0,
		tip - direction * 18.0 - normal * 9.0,
	])
	draw_colored_polygon(points, color)
