extends Node2D

const GROUP_NAME := "cainos_sprite_color_animation_nodes"

@export var sprite_path: NodePath
@export var duration_seconds := 1.0
@export var gradient_mode := "blend"
@export var color_keys: Array = []
@export var alpha_keys: Array = []
@export var phase_offset := -1.0

var _target_sprite: Sprite2D
var _elapsed := 0.0


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_target_sprite = _resolve_target_sprite()
	if _target_sprite == null:
		set_process(false)
		return
	if phase_offset < 0.0:
		phase_offset = _default_phase_offset()
	_elapsed = phase_offset * max(duration_seconds, 0.0001)
	_apply_current_color()


func _process(delta: float) -> void:
	if _target_sprite == null or duration_seconds <= 0.0:
		return
	_elapsed = fposmod(_elapsed + delta, duration_seconds)
	_apply_current_color()


func apply_animation_at_ratio(ratio: float) -> void:
	if _target_sprite == null:
		return
	var clamped_ratio := clampf(ratio, 0.0, 1.0)
	_target_sprite.modulate = _evaluate_gradient(clamped_ratio)


func _apply_current_color() -> void:
	if _target_sprite == null:
		return
	var ratio := 0.0
	if duration_seconds > 0.0:
		ratio = fposmod(_elapsed, duration_seconds) / duration_seconds
	_target_sprite.modulate = _evaluate_gradient(ratio)


func _resolve_target_sprite() -> Sprite2D:
	if not sprite_path.is_empty():
		var explicit_sprite := get_node_or_null(sprite_path)
		if explicit_sprite is Sprite2D:
			return explicit_sprite as Sprite2D
	return _find_first_sprite(self)


func _find_first_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node as Sprite2D
	for child in node.get_children():
		var sprite := _find_first_sprite(child)
		if sprite != null:
			return sprite
	return null


func _default_phase_offset() -> float:
	var stable_source := str(get_path()) if is_inside_tree() else name
	var hash_value := abs(stable_source.hash())
	return float(hash_value % 10000) / 10000.0


func _evaluate_gradient(ratio: float) -> Color:
	var rgb := _sample_color(ratio)
	rgb.a = _sample_alpha(ratio)
	return rgb


func _sample_color(ratio: float) -> Color:
	if color_keys.is_empty():
		return Color(1.0, 1.0, 1.0, 1.0)
	if color_keys.size() == 1:
		return _color_from_variant(color_keys[0])
	var lower_index := 0
	var upper_index := color_keys.size() - 1
	for index in range(color_keys.size() - 1):
		var current_time := _key_time(color_keys[index])
		var next_time := _key_time(color_keys[index + 1])
		if ratio >= current_time and ratio <= next_time:
			lower_index = index
			upper_index = index + 1
			break
		if ratio >= next_time:
			lower_index = index + 1
			upper_index = min(index + 2, color_keys.size() - 1)
	var lower_color := _color_from_variant(color_keys[lower_index])
	var upper_color := _color_from_variant(color_keys[upper_index])
	if lower_index == upper_index or gradient_mode == "fixed":
		return lower_color
	var lower_time := _key_time(color_keys[lower_index])
	var upper_time := _key_time(color_keys[upper_index])
	var span := max(upper_time - lower_time, 0.0001)
	var weight := clampf((ratio - lower_time) / span, 0.0, 1.0)
	return lower_color.lerp(upper_color, weight)


func _sample_alpha(ratio: float) -> float:
	if alpha_keys.is_empty():
		return 1.0
	if alpha_keys.size() == 1:
		return _alpha_from_variant(alpha_keys[0])
	var lower_index := 0
	var upper_index := alpha_keys.size() - 1
	for index in range(alpha_keys.size() - 1):
		var current_time := _key_time(alpha_keys[index])
		var next_time := _key_time(alpha_keys[index + 1])
		if ratio >= current_time and ratio <= next_time:
			lower_index = index
			upper_index = index + 1
			break
		if ratio >= next_time:
			lower_index = index + 1
			upper_index = min(index + 2, alpha_keys.size() - 1)
	var lower_alpha := _alpha_from_variant(alpha_keys[lower_index])
	var upper_alpha := _alpha_from_variant(alpha_keys[upper_index])
	if lower_index == upper_index or gradient_mode == "fixed":
		return lower_alpha
	var lower_time := _key_time(alpha_keys[lower_index])
	var upper_time := _key_time(alpha_keys[upper_index])
	var span := max(upper_time - lower_time, 0.0001)
	var weight := clampf((ratio - lower_time) / span, 0.0, 1.0)
	return lerpf(lower_alpha, upper_alpha, weight)


func _key_time(key_variant) -> float:
	var key: Dictionary = key_variant if key_variant is Dictionary else {}
	return clampf(float(key.get("time", 0.0)), 0.0, 1.0)


func _color_from_variant(key_variant) -> Color:
	var key: Dictionary = key_variant if key_variant is Dictionary else {}
	var color_variant = key.get("color", {})
	if color_variant is Color:
		return color_variant
	if color_variant is Dictionary:
		return Color(
			float(color_variant.get("r", 1.0)),
			float(color_variant.get("g", 1.0)),
			float(color_variant.get("b", 1.0)),
			float(color_variant.get("a", 1.0))
		)
	return Color(1.0, 1.0, 1.0, 1.0)


func _alpha_from_variant(key_variant) -> float:
	var key: Dictionary = key_variant if key_variant is Dictionary else {}
	return clampf(float(key.get("alpha", 1.0)), 0.0, 1.0)
