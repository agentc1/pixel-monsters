extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var output_root := str(args.get("output_root", "res://cainos_imports/basic_real_acceptance"))
	var scene_path := output_root.path_join("scenes/unity/SC Demo Runtime.tscn")
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Runtime navigation scene loads")
	if not (packed is PackedScene):
		_finish()
		return

	var scene := (packed as PackedScene).instantiate()
	root.add_child(scene)
	await physics_frame

	var player := scene.get_node_or_null("RuntimePlayer") as CharacterBody2D
	_assert_true(player != null, "Runtime navigation scene has CharacterBody2D player")
	if player != null:
		await _validate_north_bridge_spawn_route(player)
		_validate_bridge_underpass_probe(player)
		await _validate_bridge_underpass_drive(player)
		await _validate_south_stairs_ascent(player)
		await _validate_upper_platform_bounds(player)
	_validate_bridge_occluders(scene)

	scene.free()
	_finish()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	var index := 0
	while index < args.size():
		var token := args[index]
		if token == "--output-root" and index + 1 < args.size():
			parsed["output_root"] = args[index + 1]
			index += 1
		index += 1
	return parsed


func _validate_north_bridge_spawn_route(player: CharacterBody2D) -> void:
	player.global_position = Vector2(186.24, -73.92)
	player.velocity = Vector2.ZERO
	_send_key(KEY_W, true)
	for _index in range(150):
		await physics_frame
	_send_key(KEY_W, false)
	await physics_frame
	_assert_true(player.global_position.y < -220.0, "Runtime player can enter the north bridge route from the actual Unity spawn")


func _validate_bridge_underpass_probe(player: CharacterBody2D) -> void:
	player.global_position = Vector2(128.0, 250.0)
	player.velocity = Vector2.ZERO
	player.collision_mask = 1
	var south_entry_collision := player.move_and_collide(Vector2(0.0, -80.0), true)
	_assert_true(south_entry_collision == null, "South bridge underpass entry is clear on lower elevation")

	player.global_position = Vector2(128.0, 120.0)
	player.velocity = Vector2.ZERO
	player.collision_mask = 1
	var north_entry_collision := player.move_and_collide(Vector2(0.0, 80.0), true)
	_assert_true(north_entry_collision == null, "South bridge underpass exit is clear on lower elevation")


func _validate_bridge_underpass_drive(player: CharacterBody2D) -> void:
	player.global_position = Vector2(128.0, 250.0)
	player.velocity = Vector2.ZERO
	_apply_player_runtime_layer(player, "Layer 1")
	_send_key(KEY_W, true)
	for _index in range(150):
		await physics_frame
	_send_key(KEY_W, false)
	await physics_frame
	_assert_true(player.global_position.y < 100.0, "Runtime player can push through the south bridge underpass route")


func _validate_south_stairs_ascent(player: CharacterBody2D) -> void:
	player.global_position = Vector2(288.0, 52.0)
	player.velocity = Vector2.ZERO
	_apply_player_runtime_layer(player, "Layer 1")
	await physics_frame
	_send_key(KEY_W, true)
	for _index in range(150):
		await physics_frame
	_send_key(KEY_W, false)
	await physics_frame
	var player_root := player.get_node_or_null("PF Player")
	var layer_name := ""
	if player_root != null:
		layer_name = str(player_root.get_meta("cainos_runtime_layer_name", ""))
	_assert_true(player.global_position.y < -80.0, "Runtime player can ascend the south stairs onto the upper platform")
	_assert_true(layer_name == "Layer 2", "Runtime player remains on Layer 2 after south stairs ascent")
	_assert_true(player.collision_mask == 2, "Runtime player collides with Layer 2 geometry after south stairs ascent")


func _validate_upper_platform_bounds(player: CharacterBody2D) -> void:
	player.global_position = Vector2(288.0, -96.0)
	player.velocity = Vector2.ZERO
	_apply_player_runtime_layer(player, "Layer 2")
	await physics_frame
	_send_key(KEY_A, true)
	for _index in range(180):
		await physics_frame
	_send_key(KEY_A, false)
	await physics_frame
	_assert_true(player.global_position.x > 220.0, "Runtime Layer 2 walkable region blocks westward off-platform drift")

	player.global_position = Vector2(288.0, -96.0)
	player.velocity = Vector2.ZERO
	_apply_player_runtime_layer(player, "Layer 2")
	await physics_frame
	_send_key(KEY_D, true)
	for _index in range(180):
		await physics_frame
	_send_key(KEY_D, false)
	await physics_frame
	_assert_true(player.global_position.x < 410.0, "Runtime Layer 2 walkable region blocks eastward off-platform drift")


func _validate_bridge_occluders(scene: Node) -> void:
	for path in [
		"SceneInstance/SC Demo/Prefabs/Layer 1/Props/PF Struct - Gate 01/TX Struct Bridge Gate B/TX Struct Bridge Gate B Sprite",
		"SceneInstance/SC Demo/Prefabs/Layer 1/Props/PF Props - Wooden Gate 01/PF Props - Wooden Gate 01 Sprite",
	]:
		var sprite := scene.get_node_or_null(path) as Sprite2D
		_assert_true(sprite != null, "Runtime bridge occluder sprite exists: %s" % path)
		if sprite == null:
			continue
		_assert_true(bool(sprite.get_meta("cainos_foreground_occluder", false)), "Runtime bridge sprite is tagged as foreground occluder: %s" % path)
		_assert_true(sprite.z_index > 2, "Runtime bridge sprite renders above lower-elevation player: %s" % path)


func _send_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _apply_player_runtime_layer(player: CharacterBody2D, layer_name: String) -> void:
	var player_root := player.get_node_or_null("PF Player")
	if player_root == null:
		return
	var helper := player_root.get_node_or_null("CainosRuntimeActor2D")
	if helper != null and helper.has_method("apply_runtime_layer"):
		helper.call("apply_runtime_layer", layer_name, layer_name)


func _assert_true(value: bool, message: String) -> void:
	if value:
		print("PASS: %s" % message)
	else:
		print("FAIL: %s" % message)
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All real-pack runtime navigation checks passed.")
		quit(0)
	else:
		push_error("Real-pack runtime navigation validation failed with %d issue(s)." % _failures.size())
		for failure in _failures:
			push_error(" - %s" % failure)
		quit(1)
