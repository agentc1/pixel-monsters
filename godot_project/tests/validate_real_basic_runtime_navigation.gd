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
	_send_key(KEY_W, true)
	for _index in range(150):
		await physics_frame
	_send_key(KEY_W, false)
	await physics_frame
	_assert_true(player.global_position.y < 100.0, "Runtime player can push through the south bridge underpass route")


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
