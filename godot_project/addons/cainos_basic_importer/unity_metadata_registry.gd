@tool
extends RefCounted

const UnityPackageReader := preload("res://addons/cainos_basic_importer/unity_package_reader.gd")


func build_from_unitypackage(package_path: String) -> Dictionary:
	var reader = UnityPackageReader.new()
	var package_result = reader.read_file(package_path)
	if not package_result.get("ok", false):
		return package_result
	return _build_from_grouped_records(package_result.get("groups", {}), "unitypackage", package_path.get_file())


func build_from_package_bytes(package_bytes: PackedByteArray, label: String) -> Dictionary:
	var reader = UnityPackageReader.new()
	var package_result = reader.read_bytes(package_bytes, label)
	if not package_result.get("ok", false):
		return package_result
	return _build_from_grouped_records(package_result.get("groups", {}), "unitypackage_embedded", label)


func build_from_extracted_metadata(root_path: String) -> Dictionary:
	var files = _list_files_recursive(root_path)
	var grouped := {}
	for file_path in files:
		var relative_path = file_path.trim_prefix(root_path).trim_prefix("/")
		var guid := ""
		if relative_path.ends_with(".meta"):
			var meta_text = FileAccess.get_file_as_string(file_path)
			guid = _extract_guid(meta_text)
			if guid.is_empty():
				continue
			var group = grouped.get(guid, {"guid": guid})
			group["meta_text"] = meta_text
			var asset_relative = relative_path.substr(0, relative_path.length() - 5)
			group["pathname"] = asset_relative.replace("\\", "/")
			grouped[guid] = group
		else:
			continue

	for guid_variant in grouped.keys():
		var guid := str(guid_variant)
		var group = grouped[guid]
		var asset_relative = str(group.get("pathname", ""))
		if asset_relative.is_empty():
			continue
		var asset_abs = root_path.path_join(asset_relative)
		if not FileAccess.file_exists(asset_abs):
			continue
		group["asset_bytes"] = FileAccess.get_file_as_bytes(asset_abs)
		grouped[guid] = group

	return _build_from_grouped_records(grouped, "extracted_metadata", root_path.get_file())


func _build_from_grouped_records(groups: Dictionary, source_kind: String, source_label: String) -> Dictionary:
	var textures_by_guid = {}
	var textures_by_key = {}
	var sprites = {}
	var prefabs = []
	var asset_paths_by_guid = {}
	var script_guid_to_path = {}

	for guid_variant in groups.keys():
		var guid := str(guid_variant)
		var group: Dictionary = groups[guid]
		var asset_path := str(group.get("pathname", ""))
		if asset_path.is_empty():
			continue
		asset_paths_by_guid[guid] = asset_path
		if asset_path.ends_with(".cs"):
			script_guid_to_path[guid] = asset_path

	for guid_variant in groups.keys():
		var guid := str(guid_variant)
		var group: Dictionary = groups[guid]
		var asset_path := str(group.get("pathname", ""))
		if asset_path.is_empty():
			continue

		if asset_path.ends_with(".png"):
			var texture_result = _parse_texture_meta(asset_path, guid, str(group.get("meta_text", "")))
			if texture_result.get("ok", false):
				texture_result["asset_bytes"] = group.get("asset_bytes", PackedByteArray())
				textures_by_guid[guid] = texture_result
				var source_key = str(texture_result.get("source_key", ""))
				if not source_key.is_empty():
					textures_by_key[source_key] = texture_result
					for sprite_variant in texture_result.get("sprites", []):
						var sprite: Dictionary = sprite_variant
						var sprite_key = "%s:%s" % [guid, str(sprite.get("file_id", ""))]
						sprites[sprite_key] = sprite

	for guid_variant in groups.keys():
		var guid := str(guid_variant)
		var group: Dictionary = groups[guid]
		var asset_path := str(group.get("pathname", ""))
		if not asset_path.ends_with(".prefab"):
			continue
		var prefab_text = PackedByteArray(group.get("asset_bytes", PackedByteArray())).get_string_from_utf8()
		var prefab_result = _parse_prefab(asset_path, prefab_text, script_guid_to_path, sprites)
		if prefab_result.get("ok", false):
			prefabs.append(prefab_result)

	prefabs.sort_custom(_sort_prefab_paths)
	var summary = {
		"supported_static_prefabs": 0,
		"approximated_prefabs": 0,
		"manual_behavior_prefabs": 0,
		"unresolved_or_skipped_prefabs": 0,
		"total_prefabs": prefabs.size(),
	}
	for prefab_variant in prefabs:
		var tier = str(prefab_variant.get("support_tier", "unresolved_or_skipped"))
		match tier:
			"supported_static":
				summary["supported_static_prefabs"] += 1
			"approximated":
				summary["approximated_prefabs"] += 1
			"manual_behavior":
				summary["manual_behavior_prefabs"] += 1
			_:
				summary["unresolved_or_skipped_prefabs"] += 1

	return {
		"ok": true,
		"source_kind": source_kind,
		"source_label": source_label,
		"textures_by_guid": textures_by_guid,
		"textures_by_key": textures_by_key,
		"sprites": sprites,
		"prefabs": prefabs,
		"asset_paths_by_guid": asset_paths_by_guid,
		"script_guid_to_path": script_guid_to_path,
		"summary": summary,
	}


func _parse_texture_meta(asset_path: String, guid: String, meta_text: String) -> Dictionary:
	if meta_text.is_empty():
		return {"ok": false, "error": "Missing texture meta for %s" % asset_path}

	var normalized_text := meta_text.replace("\r\n", "\n")
	var lines = normalized_text.split("\n")
	var pixels_per_unit = 32.0
	var sprites = []
	var index = 0
	while index < lines.size():
		var raw_line = lines[index]
		var line = raw_line.strip_edges()
		if line.begins_with("spritePixelsToUnits:"):
			pixels_per_unit = float(_scalar_after_colon(line))
		elif raw_line == "    sprites:":
			index += 1
			while index < lines.size():
				if lines[index].begins_with("    - serializedVersion:"):
					var block = []
					while index < lines.size():
						var candidate = lines[index]
						if candidate.begins_with("    - serializedVersion:") and block.size() > 0:
							break
						if candidate.begins_with("  ") and not candidate.begins_with("    "):
							break
						block.append(candidate)
						index += 1
					var sprite = _parse_sprite_block("\n".join(block), guid, asset_path, pixels_per_unit)
					if not sprite.is_empty():
						sprites.append(sprite)
					continue
				if lines[index].begins_with("  ") and not lines[index].begins_with("    "):
					break
				index += 1
			continue
		index += 1

	return {
		"ok": true,
		"guid": guid,
		"asset_path": asset_path,
		"asset_name": asset_path.get_file(),
		"pixels_per_unit": pixels_per_unit,
		"source_key": _source_key_from_asset_path(asset_path),
		"sprites": sprites,
	}


func _parse_sprite_block(block_text: String, texture_guid: String, asset_path: String, pixels_per_unit: float) -> Dictionary:
	var name = _regex_capture(block_text, "(?m)^\\s+name: (.+)$")
	var internal_id = _regex_capture(block_text, "(?m)^\\s+internalID: (\\d+)$")
	var rect_match = _regex_search(block_text, "(?ms)\\s+rect:\\n(?:\\s+serializedVersion: \\d+\\n)?\\s+x: ([^\\n]+)\\n\\s+y: ([^\\n]+)\\n\\s+width: ([^\\n]+)\\n\\s+height: ([^\\n]+)")
	if name.is_empty() or internal_id.is_empty() or rect_match.is_empty():
		return {}
	var pivot_match = _regex_search(block_text, "(?m)^\\s+pivot: \\{x: ([^,]+), y: ([^\\}]+)\\}")
	var pivot = Vector2(0.5, 0.5)
	if pivot_match.size() >= 2:
		pivot = Vector2(float(pivot_match[0]), float(pivot_match[1]))
	return {
		"name": name,
		"file_id": internal_id,
		"texture_guid": texture_guid,
		"texture_path": asset_path,
		"pixels_per_unit": pixels_per_unit,
		"rect": Rect2(
			float(rect_match[0]),
			float(rect_match[1]),
			float(rect_match[2]),
			float(rect_match[3])
		),
		"pivot": pivot,
		"rotation": false,
		"source_key": _source_key_from_asset_path(asset_path),
	}


func _parse_prefab(asset_path: String, prefab_text: String, script_guid_to_path: Dictionary, sprites: Dictionary) -> Dictionary:
	var normalized_text := prefab_text.replace("\r\n", "\n")
	var documents := _split_unity_documents(normalized_text)
	if documents.is_empty():
		return {
			"ok": false,
			"path": asset_path,
			"error": "No prefab documents found.",
		}

	var game_objects := {}
	var transforms := {}
	var sprite_renderers := {}
	var box_colliders := {}
	var edge_colliders := {}
	var mono_behaviours := {}
	var unsupported_components := []

	for document in documents:
		var document_class_name := str(document.get("class_name", ""))
		var object_id := str(document.get("object_id", ""))
		var body := str(document.get("body", ""))
		match document_class_name:
			"GameObject":
				game_objects[object_id] = {
					"id": object_id,
					"name": _extract_string(body, "m_Name"),
					"layer": _extract_int(body, "m_Layer", 0),
					"component_ids": _extract_component_refs(body),
				}
			"Transform":
				transforms[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"parent_transform_id": _extract_ref_file_id(body, "m_Father"),
					"children_transform_ids": _extract_ref_list(body, "m_Children"),
					"local_position": _extract_vector3(body, "m_LocalPosition"),
					"local_scale": _extract_vector3(body, "m_LocalScale", Vector3.ONE),
				}
			"SpriteRenderer":
				sprite_renderers[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"sorting_layer_id": _extract_int(body, "m_SortingLayerID", 0),
					"sorting_order": _extract_int(body, "m_SortingOrder", 0),
					"sprite_guid": _extract_ref_guid(body, "m_Sprite"),
					"sprite_file_id": _extract_ref_file_id(body, "m_Sprite"),
					"flip_x": _extract_bool(body, "m_FlipX"),
					"flip_y": _extract_bool(body, "m_FlipY"),
				}
			"BoxCollider2D":
				box_colliders[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"is_trigger": _extract_bool(body, "m_IsTrigger"),
					"offset": _extract_vector2(body, "m_Offset"),
					"size": _extract_vector2(body, "m_Size"),
				}
			"EdgeCollider2D":
				edge_colliders[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"is_trigger": _extract_bool(body, "m_IsTrigger"),
					"offset": _extract_vector2(body, "m_Offset"),
					"points": _extract_point_list(body),
				}
			"MonoBehaviour":
				mono_behaviours[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"script_guid": _extract_ref_guid(body, "m_Script"),
					"script_path": script_guid_to_path.get(_extract_ref_guid(body, "m_Script"), ""),
					"fields": _extract_mono_fields(body),
					"raw_body": body,
				}
			"PolygonCollider2D", "Rigidbody2D", "Animator":
				unsupported_components.append(document_class_name)

	var transform_to_game_object := {}
	for transform_id_variant in transforms.keys():
		var transform_id := str(transform_id_variant)
		var transform_data: Dictionary = transforms[transform_id]
		transform_to_game_object[transform_id] = str(transform_data.get("game_object_id", "0"))

	var nodes := {}
	for game_object_id_variant in game_objects.keys():
		var game_object_id := str(game_object_id_variant)
		var game_object: Dictionary = game_objects[game_object_id]
		var transform_data := _find_transform_for_game_object(game_object_id, transforms)
		var parent_game_object_id := "0"
		if not transform_data.is_empty():
			var parent_transform_id := str(transform_data.get("parent_transform_id", "0"))
			parent_game_object_id = str(transform_to_game_object.get(parent_transform_id, "0"))
		nodes[game_object_id] = {
			"id": game_object_id,
			"name": str(game_object.get("name", "")),
			"layer": int(game_object.get("layer", 0)),
			"parent_id": parent_game_object_id,
			"local_position": transform_data.get("local_position", Vector3.ZERO),
			"local_scale": transform_data.get("local_scale", Vector3.ONE),
			"sprite_renderers": [],
			"box_colliders": [],
			"edge_colliders": [],
			"mono_behaviours": [],
			"children": [],
		}

	for node_id_variant in nodes.keys():
		var node_id := str(node_id_variant)
		var parent_id := str(nodes[node_id].get("parent_id", "0"))
		if nodes.has(parent_id):
			var children: Array = nodes[parent_id].get("children", [])
			children.append(node_id)
			nodes[parent_id]["children"] = children

	for renderer_variant in sprite_renderers.values():
		var renderer: Dictionary = renderer_variant
		var game_object_id := str(renderer.get("game_object_id", "0"))
		if nodes.has(game_object_id):
			var renderers: Array = nodes[game_object_id].get("sprite_renderers", [])
			renderers.append(renderer)
			nodes[game_object_id]["sprite_renderers"] = renderers

	for collider_variant in box_colliders.values():
		var collider: Dictionary = collider_variant
		var game_object_id := str(collider.get("game_object_id", "0"))
		if nodes.has(game_object_id):
			var colliders: Array = nodes[game_object_id].get("box_colliders", [])
			colliders.append(collider)
			nodes[game_object_id]["box_colliders"] = colliders

	for collider_variant in edge_colliders.values():
		var collider: Dictionary = collider_variant
		var game_object_id := str(collider.get("game_object_id", "0"))
		if nodes.has(game_object_id):
			var colliders: Array = nodes[game_object_id].get("edge_colliders", [])
			colliders.append(collider)
			nodes[game_object_id]["edge_colliders"] = colliders

	for mono_variant in mono_behaviours.values():
		var mono: Dictionary = mono_variant
		var game_object_id := str(mono.get("game_object_id", "0"))
		if nodes.has(game_object_id):
			var monos: Array = nodes[game_object_id].get("mono_behaviours", [])
			monos.append(mono)
			nodes[game_object_id]["mono_behaviours"] = monos

	var root_ids := []
	var unresolved_sprite_refs := []
	var has_mono := not mono_behaviours.is_empty()
	var has_polygon := unsupported_components.has("PolygonCollider2D")
	var has_rigidbody := unsupported_components.has("Rigidbody2D")
	var has_animator := unsupported_components.has("Animator")

	for node_id_variant in nodes.keys():
		var node_id := str(node_id_variant)
		var node: Dictionary = nodes[node_id]
		if str(node.get("parent_id", "0")) == "0":
			root_ids.append(node_id)
		for renderer_variant in node.get("sprite_renderers", []):
			var renderer: Dictionary = renderer_variant
			var sprite_key := "%s:%s" % [str(renderer.get("sprite_guid", "")), str(renderer.get("sprite_file_id", ""))]
			if not sprites.has(sprite_key):
				unresolved_sprite_refs.append(sprite_key)

	root_ids.sort()
	var support_tier := "supported_static"
	if not unresolved_sprite_refs.is_empty():
		support_tier = "unresolved_or_skipped"
	elif has_mono or has_animator:
		support_tier = "manual_behavior"
	elif has_polygon or has_rigidbody:
		support_tier = "approximated"

	var display_name := asset_path.get_file().trim_suffix(".prefab")
	return {
		"ok": true,
		"path": asset_path,
		"name": display_name,
		"family": _family_from_prefab_path(asset_path, display_name),
		"root_ids": root_ids,
		"nodes": nodes,
		"support_tier": support_tier,
		"unsupported_components": unsupported_components,
		"unresolved_sprite_refs": unresolved_sprite_refs,
	}


func _split_unity_documents(text: String) -> Array:
	var regex := RegEx.new()
	regex.compile("(?m)^--- !u!(\\d+) &([\\-0-9]+)\\n([A-Za-z0-9_]+):\\n")
	var matches := regex.search_all(text)
	var documents := []
	for index in range(matches.size()):
		var match: RegExMatch = matches[index]
		var start := match.get_end(0)
		var end := text.length()
		if index + 1 < matches.size():
			end = matches[index + 1].get_start(0)
		documents.append({
			"type_id": match.get_string(1),
			"object_id": match.get_string(2),
			"class_name": match.get_string(3),
			"body": text.substr(start, end - start),
		})
	return documents


func _find_transform_for_game_object(game_object_id: String, transforms: Dictionary) -> Dictionary:
	for transform_variant in transforms.values():
		var transform_data: Dictionary = transform_variant
		if str(transform_data.get("game_object_id", "")) == game_object_id:
			return transform_data
	return {}


func _extract_mono_fields(body: String) -> Dictionary:
	var fields := {}
	var lines := body.split("\n")
	var started := false
	for raw_line in lines:
		var line := raw_line.strip_edges()
		if line.begins_with("m_EditorClassIdentifier:"):
			started = true
			continue
		if not started:
			continue
		if line.is_empty():
			continue
		if line.begins_with("m_"):
			continue
		var colon := line.find(":")
		if colon <= 0:
			continue
		var key := line.substr(0, colon).strip_edges()
		var value := line.substr(colon + 1).strip_edges()
		fields[key] = _parse_scalar(value)
	return fields


func _extract_component_refs(body: String) -> Array:
	var refs := []
	var regex := RegEx.new()
	regex.compile("component: \\{fileID: ([\\-0-9]+)\\}")
	for match in regex.search_all(body):
		refs.append(match.get_string(1))
	return refs


func _extract_ref_list(body: String, key: String) -> Array:
	var result := []
	var lines := body.split("\n")
	var in_list := false
	for raw_line in lines:
		if raw_line.begins_with("  %s:" % key):
			in_list = true
			continue
		if not in_list:
			continue
		if raw_line.begins_with("  ") and not raw_line.begins_with("  -"):
			break
		var line := raw_line.strip_edges()
		if line.begins_with("- {fileID: "):
			var value := line.trim_prefix("- {fileID: ").trim_suffix("}")
			result.append(value)
	return result


func _extract_point_list(body: String) -> Array:
	var points := []
	var lines := body.split("\n")
	var in_points := false
	for raw_line in lines:
		if raw_line.begins_with("  m_Points:"):
			in_points = true
			continue
		if not in_points:
			continue
		if raw_line.begins_with("  ") and not raw_line.begins_with("  - "):
			break
		var line := raw_line.strip_edges()
		if line.begins_with("- {x: "):
			var match := _regex_search(line, "\\{x: ([^,]+), y: ([^\\}]+)\\}")
			if match.size() >= 2:
				points.append(Vector2(float(match[0]), float(match[1])))
	return points


func _extract_string(body: String, key: String) -> String:
	return _regex_capture(body, "(?m)^\\s*%s: (.+)$" % key)


func _extract_int(body: String, key: String, default_value: int = 0) -> int:
	var value := _regex_capture(body, "(?m)^\\s*%s: ([\\-0-9]+)$" % key)
	return default_value if value.is_empty() else int(value)


func _extract_bool(body: String, key: String) -> bool:
	return _extract_int(body, key, 0) != 0


func _extract_ref_file_id(body: String, key: String) -> String:
	return _regex_capture(body, "(?m)^\\s*%s: \\{fileID: ([\\-0-9]+)(?:, guid: [0-9a-f]+, type: \\d+)?\\}$" % key)


func _extract_ref_guid(body: String, key: String) -> String:
	return _regex_capture(body, "(?m)^\\s*%s: \\{fileID: [\\-0-9]+, guid: ([0-9a-f]+), type: \\d+\\}$" % key)


func _extract_vector2(body: String, key: String, default_value: Vector2 = Vector2.ZERO) -> Vector2:
	var match := _regex_search(body, "(?m)^\\s*%s: \\{x: ([^,]+), y: ([^\\}]+)\\}$" % key)
	if match.size() < 2:
		return default_value
	return Vector2(float(match[0]), float(match[1]))


func _extract_vector3(body: String, key: String, default_value: Vector3 = Vector3.ZERO) -> Vector3:
	var match := _regex_search(body, "(?m)^\\s*%s: \\{x: ([^,]+), y: ([^,]+), z: ([^\\}]+)\\}$" % key)
	if match.size() < 3:
		return default_value
	return Vector3(float(match[0]), float(match[1]), float(match[2]))


func _extract_guid(meta_text: String) -> String:
	return _regex_capture(meta_text, "(?m)^guid: ([0-9a-f]+)$")


func _regex_capture(text: String, pattern: String) -> String:
	var regex := RegEx.new()
	regex.compile(pattern)
	var match := regex.search(text)
	if match == null:
		return ""
	return match.get_string(1)


func _regex_search(text: String, pattern: String) -> Array:
	var regex := RegEx.new()
	regex.compile(pattern)
	var match := regex.search(text)
	if match == null:
		return []
	var results := []
	for index in range(1, match.get_group_count() + 1):
		results.append(match.get_string(index))
	return results


func _family_from_prefab_path(asset_path: String, display_name: String) -> String:
	if asset_path.contains("/Prefab/Plant/"):
		return "plants"
	if asset_path.contains("/Prefab/Player/"):
		return "player"
	if display_name.begins_with("PF Struct"):
		return "struct"
	return "props"


func _source_key_from_asset_path(asset_path: String) -> String:
	var file_name := asset_path.get_file()
	match file_name:
		"TX Tileset Grass.png":
			return "tileset_grass"
		"TX Tileset Stone Ground.png":
			return "tileset_stone_ground"
		"TX Tileset Wall.png":
			return "tileset_wall"
		"TX Struct.png":
			return "struct"
		"TX Props.png":
			return "props"
		"TX Plant.png":
			return "plants"
		"TX Player.png":
			return "player"
		"TX Shadow.png":
			return "shadow_props"
		"TX Shadow Plant.png":
			return "shadow_plants"
		"TX Props with Shadow.png":
			return "extra_props_shadow"
		"TX Plant with Shadow.png":
			return "extra_plants_shadow"
		_:
			return ""


func _scalar_after_colon(line: String) -> String:
	var colon := line.find(":")
	return "" if colon < 0 else line.substr(colon + 1).strip_edges()


func _parse_scalar(value: String):
	if value == "0":
		return 0
	if value == "1":
		return 1
	if value.is_valid_int():
		return int(value)
	if value.is_valid_float():
		return float(value)
	return value


func _list_files_recursive(root_path: String) -> Array:
	var files := []
	var dir := DirAccess.open(root_path)
	if dir == null:
		return files
	dir.include_hidden = false
	dir.include_navigational = false
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		var child := root_path.path_join(name)
		if dir.current_is_dir():
			files.append_array(_list_files_recursive(child))
		else:
			files.append(child)
	dir.list_dir_end()
	return files


func _sort_prefab_paths(a, b) -> bool:
	return str(a.get("path", "")) < str(b.get("path", ""))
