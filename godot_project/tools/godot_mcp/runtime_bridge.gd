extends Node

const CAPTURE_ROOT := "user://godot_mcp_captures"
const DEFAULT_ROOT_PATH := "/root/GodotMcpRuntime/SceneHost"
const HOST_NODE_PATH := ^"SceneHost"

var _bridge_host := "127.0.0.1"
var _bridge_port := 0
var _peer := StreamPeerTCP.new()
var _was_connected := false
var _read_buffer := ""
var _request_queue: Array[Dictionary] = []
var _processing_request := false
var _loaded_scene_path := ""
var _frame_counter := 0

@onready var _scene_host: Node = get_node(HOST_NODE_PATH)


func _ready() -> void:
	var parsed := _parse_args(OS.get_cmdline_user_args())
	_bridge_host = str(parsed.get("bridge_host", "127.0.0.1"))
	_bridge_port = int(parsed.get("bridge_port", 0))
	if _bridge_port <= 0:
		push_error("Godot MCP bridge requires --bridge-port.")
		get_tree().quit(1)
		return
	var err := _peer.connect_to_host(_bridge_host, _bridge_port)
	if err != OK:
		push_error("Could not connect to MCP bridge host %s:%d" % [_bridge_host, _bridge_port])
		get_tree().quit(1)
		return
	set_process(true)
	set_physics_process(true)


func _process(_delta: float) -> void:
	_frame_counter += 1
	_peer.poll()
	var status := _peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED and not _was_connected:
		_was_connected = true
		_send_json({
			"event": "ready",
			"payload": {
				"bridge_root_path": "/root/GodotMcpRuntime",
				"scene_host_path": DEFAULT_ROOT_PATH,
			},
		})
	if status == StreamPeerTCP.STATUS_ERROR or (_was_connected and status == StreamPeerTCP.STATUS_NONE):
		get_tree().quit(0)
		return
	_read_incoming()
	if not _processing_request and not _request_queue.is_empty():
		_processing_request = true
		var request: Dictionary = _request_queue.pop_front()
		call_deferred("_process_request", request)


func _process_request(request: Dictionary) -> void:
	var response := await _handle_request(request)
	_send_json(response)
	_processing_request = false


func _physics_process(_delta: float) -> void:
	pass


func _handle_request(request: Dictionary) -> Dictionary:
	var request_id := int(request.get("id", 0))
	var method := str(request.get("method", ""))
	var params: Dictionary = request.get("params", {})
	match method:
		"load_scene":
			return _response_ok(request_id, await _load_scene(params))
		"get_status":
			return _response_ok(request_id, _status_payload())
		"scene_tree":
			return _response_ok(request_id, _scene_tree_payload(params))
		"node_info":
			return _response_ok(request_id, _node_info_payload(params))
		"capture_viewport":
			return _response_ok(request_id, await _capture_viewport_payload(params))
		"press_keys":
			return _response_ok(request_id, await _press_keys_payload(params))
		"advance_frames":
			return _response_ok(request_id, await _advance_frames_payload(params))
		"shutdown":
			call_deferred("_quit_cleanly")
			return _response_ok(request_id, {"stopping": true})
		_:
			return _response_error(request_id, "unknown_method", "Unknown bridge method: %s" % method)


func _quit_cleanly() -> void:
	get_tree().quit(0)


func _load_scene(params: Dictionary) -> Dictionary:
	var scene_path := str(params.get("scene_path", ""))
	if scene_path.is_empty():
		return {"loaded": false, "error": "scene_path is required"}
	var resource := load(scene_path)
	if not (resource is PackedScene):
		return {"loaded": false, "error": "Scene is not a PackedScene: %s" % scene_path}
	for child in _scene_host.get_children():
		child.queue_free()
	await _await_frames(1)
	var instance := (resource as PackedScene).instantiate()
	_scene_host.add_child(instance)
	_loaded_scene_path = scene_path
	await _await_frames(int(params.get("wait_frames", 2)))
	return _status_payload()


func _status_payload() -> Dictionary:
	return {
		"loaded_scene_path": _loaded_scene_path,
		"loaded_scene_root_path": _loaded_scene_root_path(),
		"current_camera_path": _current_camera_path(),
		"viewport_size": {
			"x": get_viewport().get_visible_rect().size.x,
			"y": get_viewport().get_visible_rect().size.y,
		},
		"frame": _frame_counter,
	}


func _scene_tree_payload(params: Dictionary) -> Dictionary:
	var root_path := str(params.get("root_path", DEFAULT_ROOT_PATH))
	var max_depth := int(params.get("max_depth", 3))
	var include_internal := bool(params.get("include_internal", false))
	var node := get_node_or_null(root_path)
	if node == null:
		return {
			"root_path": root_path,
			"found": false,
			"tree": {},
		}
	return {
		"root_path": root_path,
		"found": true,
		"tree": _serialize_tree(node, 0, max_depth, include_internal),
	}


func _node_info_payload(params: Dictionary) -> Dictionary:
	var node_path := str(params.get("node_path", ""))
	var node := get_node_or_null(node_path)
	if node == null:
		return {
			"found": false,
			"node_path": node_path,
		}
	return {
		"found": true,
		"node": _serialize_node(node),
	}


func _capture_viewport_payload(params: Dictionary) -> Dictionary:
	var label := str(params.get("label", "capture"))
	await _await_frames(2)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.is_empty():
		return {"captured": false, "error": "Viewport image is empty."}
	var safe_label := _sanitize_filename(label)
	var capture_dir := ProjectSettings.globalize_path(CAPTURE_ROOT)
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var rel_path := CAPTURE_ROOT.path_join("%s_%06d.png" % [safe_label, _frame_counter])
	var abs_path := ProjectSettings.globalize_path(rel_path)
	var err := image.save_png(abs_path)
	if err != OK:
		return {"captured": false, "error": "Could not save viewport PNG."}
	return {
		"captured": true,
		"png_path": abs_path,
		"loaded_scene_path": _loaded_scene_path,
		"loaded_scene_root_path": _loaded_scene_root_path(),
		"current_camera_path": _current_camera_path(),
		"viewport_size": {
			"x": image.get_width(),
			"y": image.get_height(),
		},
		"frame": _frame_counter,
	}


func _press_keys_payload(params: Dictionary) -> Dictionary:
	var keys: Array = params.get("keys", [])
	var hold_ms: int = max(1, int(params.get("hold_ms", 120)))
	var frames_after: int = max(0, int(params.get("frames_after", 2)))
	var pressed_codes: Array[int] = []
	for key_variant in keys:
		var key_code := _parse_key_spec(str(key_variant))
		if key_code == KEY_NONE:
			continue
		pressed_codes.append(key_code)
		_emit_key_event(key_code, true)
	var hold_frames: int = max(1, int(round(float(hold_ms) / 16.0)))
	await _await_frames(hold_frames)
	for key_code in pressed_codes:
		_emit_key_event(key_code, false)
	await _await_frames(max(1, frames_after))
	return _status_payload()


func _advance_frames_payload(params: Dictionary) -> Dictionary:
	var frames: int = max(1, int(params.get("frames", 1)))
	await _await_frames(frames)
	return _status_payload()


func _emit_key_event(key_code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key_code
	event.physical_keycode = key_code
	event.pressed = pressed
	event.echo = false
	Input.parse_input_event(event)


func _parse_key_spec(spec: String) -> int:
	var normalized := spec.strip_edges().to_upper()
	var aliases := {
		"LEFT": KEY_LEFT,
		"ARROWLEFT": KEY_LEFT,
		"RIGHT": KEY_RIGHT,
		"ARROWRIGHT": KEY_RIGHT,
		"UP": KEY_UP,
		"ARROWUP": KEY_UP,
		"DOWN": KEY_DOWN,
		"ARROWDOWN": KEY_DOWN,
		"SPACE": KEY_SPACE,
		"ENTER": KEY_ENTER,
		"ESC": KEY_ESCAPE,
		"ESCAPE": KEY_ESCAPE,
	}
	if aliases.has(normalized):
		return int(aliases[normalized])
	if normalized.begins_with("KEY_"):
		normalized = normalized.substr(4)
	if normalized.length() == 1:
		var char_code := normalized.unicode_at(0)
		if char_code >= 65 and char_code <= 90:
			return KEY_A + (char_code - 65)
		if char_code >= 48 and char_code <= 57:
			return KEY_0 + (char_code - 48)
	return KEY_NONE


func _await_frames(frame_count: int) -> void:
	for _frame in range(max(1, frame_count)):
		await get_tree().physics_frame
		await get_tree().process_frame


func _serialize_tree(node: Node, depth: int, max_depth: int, include_internal: bool) -> Dictionary:
	var payload := {
		"path": str(node.get_path()),
		"name": node.name,
		"type": node.get_class(),
		"visible": _node_visible(node),
		"script_path": _node_script_path(node),
		"child_count": node.get_child_count(include_internal),
		"children": [],
	}
	if depth >= max_depth:
		return payload
	var children: Array = []
	for child in node.get_children(include_internal):
		children.append(_serialize_tree(child, depth + 1, max_depth, include_internal))
	payload["children"] = children
	return payload


func _serialize_node(node: Node) -> Dictionary:
	var payload := {
		"path": str(node.get_path()),
		"name": node.name,
		"type": node.get_class(),
		"script_path": _node_script_path(node),
		"groups": Array(node.get_groups()),
		"meta": _serialize_meta(node),
	}
	if node.get_parent() != null:
		payload["parent_path"] = str(node.get_parent().get_path())
	if node is CanvasItem:
		var item := node as CanvasItem
		payload["visible"] = item.visible
	if node is Node2D:
		var node_2d := node as Node2D
		payload["position"] = _vector_payload(node_2d.position)
		payload["global_position"] = _vector_payload(node_2d.global_position)
		payload["rotation"] = node_2d.rotation
		payload["scale"] = _vector_payload(node_2d.scale)
	if node is Sprite2D:
		var sprite := node as Sprite2D
		payload["z_index"] = sprite.z_index
		payload["region_enabled"] = sprite.region_enabled
		payload["region_rect"] = _jsonify_variant(sprite.region_rect)
		payload["flip_h"] = sprite.flip_h
		payload["flip_v"] = sprite.flip_v
		payload["texture_path"] = "" if sprite.texture == null else str(sprite.texture.resource_path)
	if node is Camera2D:
		var camera := node as Camera2D
		payload["enabled"] = camera.enabled
		payload["zoom"] = _vector_payload(camera.zoom)
		payload["current"] = str(camera.get_viewport().get_camera_2d().get_path()) == str(camera.get_path()) if camera.get_viewport().get_camera_2d() != null else false
	return payload


func _serialize_meta(node: Node) -> Dictionary:
	var meta := {}
	for meta_name_variant in node.get_meta_list():
		var meta_name := str(meta_name_variant)
		meta[meta_name] = _jsonify_variant(node.get_meta(meta_name))
	return meta


func _jsonify_variant(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_VECTOR2:
			return _vector_payload(value)
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_RECT2:
			return {
				"position": _vector_payload(value.position),
				"size": _vector_payload(value.size),
			}
		TYPE_COLOR:
			return {
				"r": value.r,
				"g": value.g,
				"b": value.b,
				"a": value.a,
			}
		TYPE_ARRAY:
			var items: Array = []
			for item in value:
				items.append(_jsonify_variant(item))
			return items
		TYPE_DICTIONARY:
			var dictionary := {}
			for key_variant in value.keys():
				dictionary[str(key_variant)] = _jsonify_variant(value[key_variant])
			return dictionary
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var packed: Array = []
			for item in value:
				packed.append(item)
			return packed
		_:
			return str(value)


func _vector_payload(vector: Vector2) -> Dictionary:
	return {
		"x": vector.x,
		"y": vector.y,
	}


func _loaded_scene_root_path() -> String:
	if _scene_host.get_child_count() == 0:
		return ""
	return str(_scene_host.get_child(0).get_path())


func _current_camera_path() -> String:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return ""
	return str(camera.get_path())


func _node_script_path(node: Node) -> String:
	var script: Variant = node.get_script()
	if script is Script:
		return str((script as Script).resource_path)
	return ""


func _node_visible(node: Node) -> bool:
	if node is CanvasItem:
		return (node as CanvasItem).visible
	return true


func _response_ok(request_id: int, result: Dictionary) -> Dictionary:
	if result.has("error"):
		return _response_error(request_id, "bridge_error", str(result.get("error", "Unknown bridge error.")))
	return {
		"id": request_id,
		"ok": true,
		"result": result,
	}


func _response_error(request_id: int, code: String, message: String) -> Dictionary:
	return {
		"id": request_id,
		"ok": false,
		"error": {
			"code": code,
			"message": message,
		},
	}


func _send_json(payload: Dictionary) -> void:
	var bytes := (JSON.stringify(payload, "", false) + "\n").to_utf8_buffer()
	_peer.put_data(bytes)


func _read_incoming() -> void:
	var available := _peer.get_available_bytes()
	if available <= 0:
		return
	var packet := _peer.get_data(available)
	if int(packet[0]) != OK:
		return
	_read_buffer += (packet[1] as PackedByteArray).get_string_from_utf8()
	while true:
		var newline_index := _read_buffer.find("\n")
		if newline_index < 0:
			break
		var raw_line := _read_buffer.substr(0, newline_index)
		_read_buffer = _read_buffer.substr(newline_index + 1)
		if raw_line.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(raw_line)
		if parsed is Dictionary:
			_request_queue.append(parsed)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	var index := 0
	while index < args.size():
		var token := args[index]
		match token:
			"--bridge-host":
				if index + 1 < args.size():
					parsed["bridge_host"] = args[index + 1]
					index += 1
			"--bridge-port":
				if index + 1 < args.size():
					parsed["bridge_port"] = args[index + 1]
					index += 1
		index += 1
	return parsed


func _sanitize_filename(label: String) -> String:
	var sanitized := ""
	for index in range(label.length()):
		var character := label.substr(index, 1)
		var is_safe := (character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9") or character in ["_", "-", "."]
		sanitized += character if is_safe else "_"
	sanitized = sanitized.strip_edges()
	return sanitized if not sanitized.is_empty() else "capture"
