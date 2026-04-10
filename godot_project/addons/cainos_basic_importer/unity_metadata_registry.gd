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
	var tile_palette_tiles = {}
	var prefabs = []
	var prefabs_by_guid = {}
	var editor_only_prefabs = []
	var scenes = []
	var deferred_scenes = []
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
			var texture_result = _parse_texture_meta(
				asset_path,
				guid,
				str(group.get("meta_text", "")),
				PackedByteArray(group.get("asset_bytes", PackedByteArray()))
			)
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
		if not asset_path.ends_with(".asset") or not asset_path.contains("/Tile Palette/"):
			continue
		var tile_text := PackedByteArray(group.get("asset_bytes", PackedByteArray())).get_string_from_utf8()
		var tile_result := _parse_tile_palette_asset(asset_path, guid, tile_text)
		if tile_result.get("ok", false):
			tile_palette_tiles["%s:%s" % [guid, str(tile_result.get("file_id", "11400000"))]] = tile_result

	for guid_variant in groups.keys():
		var guid := str(guid_variant)
		var group: Dictionary = groups[guid]
		var asset_path := str(group.get("pathname", ""))
		if not asset_path.ends_with(".prefab"):
			continue
		var prefab_text = PackedByteArray(group.get("asset_bytes", PackedByteArray())).get_string_from_utf8()
		var prefab_result = _parse_prefab(asset_path, prefab_text, script_guid_to_path, sprites)
		if prefab_result.get("ok", false):
			prefab_result["guid"] = guid
			if str(prefab_result.get("asset_scope", "semantic_prefab")) == "editor_only_prefab":
				editor_only_prefabs.append(prefab_result)
			else:
				prefabs.append(prefab_result)
				prefabs_by_guid[guid] = prefab_result

	for guid_variant in groups.keys():
		var guid := str(guid_variant)
		var group: Dictionary = groups[guid]
		var asset_path := str(group.get("pathname", ""))
		if not asset_path.ends_with(".unity"):
			continue
		var scene_text = PackedByteArray(group.get("asset_bytes", PackedByteArray())).get_string_from_utf8()
		var scene_result = _parse_scene(asset_path, scene_text, script_guid_to_path, sprites, tile_palette_tiles, asset_paths_by_guid, prefabs_by_guid)
		if scene_result.get("ok", false):
			scene_result["guid"] = guid
			if bool(scene_result.get("import_supported", false)):
				scenes.append(scene_result)
			else:
				deferred_scenes.append(scene_result)

	prefabs.sort_custom(_sort_prefab_paths)
	editor_only_prefabs.sort_custom(_sort_prefab_paths)
	scenes.sort_custom(_sort_scene_paths)
	deferred_scenes.sort_custom(_sort_scene_paths)
	var summary = {
		"supported_static_prefabs": 0,
		"approximated_prefabs": 0,
		"manual_behavior_prefabs": 0,
		"unresolved_or_skipped_prefabs": 0,
		"editor_only_prefabs": editor_only_prefabs.size(),
		"total_prefabs": prefabs.size(),
	}
	var scene_summary = {
		"import_supported_scenes": scenes.size(),
		"deferred_scenes": deferred_scenes.size(),
		"total_scenes": scenes.size() + deferred_scenes.size(),
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
		"tile_palette_tiles": tile_palette_tiles,
		"prefabs": prefabs,
		"prefabs_by_guid": prefabs_by_guid,
		"editor_only_prefabs": editor_only_prefabs,
		"scenes": scenes,
		"deferred_scenes": deferred_scenes,
		"asset_paths_by_guid": asset_paths_by_guid,
		"script_guid_to_path": script_guid_to_path,
		"summary": summary,
		"scene_summary": scene_summary,
	}


func _parse_texture_meta(asset_path: String, guid: String, meta_text: String, asset_bytes: PackedByteArray) -> Dictionary:
	if meta_text.is_empty():
		return {"ok": false, "error": "Missing texture meta for %s" % asset_path}
	var texture_size := _decode_texture_size(asset_bytes)
	if texture_size == Vector2i.ZERO:
		return {"ok": false, "error": "Could not decode texture size for %s" % asset_path}

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
					var sprite = _parse_sprite_block("\n".join(block), guid, asset_path, pixels_per_unit, texture_size.y)
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
		"texture_size": texture_size,
		"sprites": sprites,
	}


func _parse_sprite_block(block_text: String, texture_guid: String, asset_path: String, pixels_per_unit: float, texture_height: int) -> Dictionary:
	var name = _regex_capture(block_text, "(?m)^\\s+name: (.+)$")
	var internal_id = _regex_capture(block_text, "(?m)^\\s+internalID: ([\\-0-9]+)$")
	var rect_match = _regex_search(block_text, "(?ms)\\s+rect:\\n(?:\\s+serializedVersion: \\d+\\n)?\\s+x: ([^\\n]+)\\n\\s+y: ([^\\n]+)\\n\\s+width: ([^\\n]+)\\n\\s+height: ([^\\n]+)")
	if name.is_empty() or internal_id.is_empty() or rect_match.is_empty():
		return {}
	var unity_rect := Rect2(
		float(rect_match[0]),
		float(rect_match[1]),
		float(rect_match[2]),
		float(rect_match[3])
	)
	var rect := Rect2(
		unity_rect.position.x,
		float(texture_height) - unity_rect.position.y - unity_rect.size.y,
		unity_rect.size.x,
		unity_rect.size.y
	)
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
		"rect": rect,
		"unity_rect": unity_rect,
		"pivot": pivot,
		"rotation": false,
		"source_key": _source_key_from_asset_path(asset_path),
	}


func _parse_tile_palette_asset(asset_path: String, guid: String, asset_text: String) -> Dictionary:
	var documents := _split_unity_documents(asset_text.replace("\r\n", "\n"))
	for document_variant in documents:
		var document: Dictionary = document_variant
		if str(document.get("class_name", "")) != "MonoBehaviour":
			continue
		var body := str(document.get("body", ""))
		var sprite_guid := _extract_ref_guid(body, "m_Sprite")
		var sprite_file_id := _extract_ref_file_id(body, "m_Sprite")
		if sprite_guid.is_empty() or sprite_file_id.is_empty():
			continue
		return {
			"ok": true,
			"guid": guid,
			"path": asset_path,
			"name": _extract_string(body, "m_Name"),
			"file_id": str(document.get("object_id", "11400000")),
			"sprite_guid": sprite_guid,
			"sprite_file_id": sprite_file_id,
		}
	return {
		"ok": false,
		"path": asset_path,
		"error": "Tile palette asset did not contain a sprite reference.",
	}


func _decode_texture_size(asset_bytes: PackedByteArray) -> Vector2i:
	if asset_bytes.is_empty():
		return Vector2i.ZERO
	var image := Image.new()
	var err := image.load_png_from_buffer(asset_bytes)
	if err != OK:
		return Vector2i.ZERO
	return Vector2i(image.get_width(), image.get_height())


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
	var polygon_colliders := {}
	var rigidbodies := {}
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
			"PolygonCollider2D":
				polygon_colliders[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"is_trigger": _extract_bool(body, "m_IsTrigger"),
					"offset": _extract_vector2(body, "m_Offset"),
					"paths": _extract_polygon_paths(body),
				}
			"Rigidbody2D":
				var constraints := _extract_int(body, "m_Constraints", 0)
				rigidbodies[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"body_type": _extract_int(body, "m_BodyType", 0),
					"simulated": _extract_bool_default(body, "m_Simulated", true),
					"use_auto_mass": _extract_bool_default(body, "m_UseAutoMass", false),
					"mass": _extract_float(body, "m_Mass", 1.0),
					"linear_damp": _extract_float(body, "m_LinearDrag", 0.0),
					"angular_damp": _extract_float(body, "m_AngularDrag", 0.05),
					"gravity_scale": _extract_float(body, "m_GravityScale", 1.0),
					"constraints": constraints,
					"freeze_rotation": (constraints & 4) != 0,
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
			"Animator":
				if not unsupported_components.has(document_class_name):
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
			"polygon_colliders": [],
			"rigidbodies": [],
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

	for collider_id_variant in polygon_colliders.keys():
		var collider_id := str(collider_id_variant)
		var collider: Dictionary = polygon_colliders[collider_id]
		var paths: Array = collider.get("paths", [])
		var accepted_paths := []
		var deferred_paths := []
		if paths.is_empty():
			deferred_paths.append([])
		else:
			for path_variant in paths:
				var path: Array = path_variant
				if path.size() >= 3:
					accepted_paths.append(path)
				else:
					deferred_paths.append(path)
		collider["accepted_paths"] = accepted_paths
		collider["deferred_paths"] = deferred_paths
		polygon_colliders[collider_id] = collider
		var game_object_id := str(collider.get("game_object_id", "0"))
		if nodes.has(game_object_id):
			var colliders: Array = nodes[game_object_id].get("polygon_colliders", [])
			colliders.append(collider)
			nodes[game_object_id]["polygon_colliders"] = colliders

	for rigidbody_variant in rigidbodies.values():
		var rigidbody: Dictionary = rigidbody_variant
		var game_object_id := str(rigidbody.get("game_object_id", "0"))
		if nodes.has(game_object_id):
			var node_rigidbodies: Array = nodes[game_object_id].get("rigidbodies", [])
			node_rigidbodies.append(rigidbody)
			nodes[game_object_id]["rigidbodies"] = node_rigidbodies

	for mono_variant in mono_behaviours.values():
		var mono: Dictionary = mono_variant
		var game_object_id := str(mono.get("game_object_id", "0"))
		if nodes.has(game_object_id):
			var monos: Array = nodes[game_object_id].get("mono_behaviours", [])
			monos.append(mono)
			nodes[game_object_id]["mono_behaviours"] = monos

	var root_ids := []
	var unresolved_sprite_refs := []
	var simple_edge_collider_count := 0
	var complex_edge_collider_count := 0
	var polygon_collider_count := polygon_colliders.size()
	var polygon_paths_imported := 0
	var polygon_paths_deferred := 0
	var has_mono := not mono_behaviours.is_empty()
	var has_animator := unsupported_components.has("Animator")
	var has_box_collider := not box_colliders.is_empty()

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

	for edge_variant in edge_colliders.values():
		var edge: Dictionary = edge_variant
		var points: Array = edge.get("points", [])
		if points.size() == 2:
			simple_edge_collider_count += 1
		else:
			complex_edge_collider_count += 1

	for collider_variant in polygon_colliders.values():
		var collider: Dictionary = collider_variant
		polygon_paths_imported += Array(collider.get("accepted_paths", [])).size()
		polygon_paths_deferred += Array(collider.get("deferred_paths", [])).size()

	root_ids.sort()
	var display_name := asset_path.get_file().trim_suffix(".prefab")
	var family := _family_from_prefab_path(asset_path, display_name)
	var asset_scope := "semantic_prefab" if asset_path.contains("/Prefab/") else "editor_only_prefab"
	var rigidbody_count := rigidbodies.size()
	var imported_rigidbody_count := 0
	var deferred_rigidbody_count := 0
	var has_rigidbody := rigidbody_count > 0
	var rigidbody_report_source := {}
	var single_root_id := str(root_ids[0]) if root_ids.size() == 1 else ""
	var sorted_rigidbody_ids := rigidbodies.keys()
	sorted_rigidbody_ids.sort()
	for rigidbody_id_variant in sorted_rigidbody_ids:
		var rigidbody_id := str(rigidbody_id_variant)
		var rigidbody: Dictionary = rigidbodies[rigidbody_id]
		var game_object_id := str(rigidbody.get("game_object_id", "0"))
		var config_supported := _rigidbody_config_supported(rigidbody)
		var import_supported := (
			asset_scope == "semantic_prefab"
			and family == "props"
			and not has_mono
			and not has_animator
			and rigidbody_count == 1
			and root_ids.size() == 1
			and game_object_id == single_root_id
			and config_supported
		)
		rigidbody["body_type_name"] = _rigidbody_body_type_name(int(rigidbody.get("body_type", 0)))
		rigidbody["config_supported"] = config_supported
		rigidbody["import_supported"] = import_supported
		rigidbodies[rigidbody_id] = rigidbody
		if nodes.has(game_object_id):
			var node_rigidbodies: Array = nodes[game_object_id].get("rigidbodies", [])
			for index in range(node_rigidbodies.size()):
				var node_rigidbody: Dictionary = node_rigidbodies[index]
				if str(node_rigidbody.get("id", "")) == rigidbody_id:
					node_rigidbodies[index] = rigidbody
			nodes[game_object_id]["rigidbodies"] = node_rigidbodies
			if import_supported:
				nodes[game_object_id]["supported_rigidbody"] = rigidbody
		if import_supported:
			imported_rigidbody_count += 1
		elif has_rigidbody:
			deferred_rigidbody_count += 1
		if rigidbody_report_source.is_empty():
			rigidbody_report_source = rigidbody
	var scene_node_paths := _scene_node_paths_for_prefab(root_ids, nodes)
	var renderer_node_paths := {}
	var sorted_node_ids := nodes.keys()
	sorted_node_ids.sort()
	for node_id_variant in sorted_node_ids:
		var node_id := str(node_id_variant)
		var node_path := str(scene_node_paths.get(node_id, "."))
		for renderer_variant in nodes[node_id].get("sprite_renderers", []):
			var renderer: Dictionary = renderer_variant
			renderer_node_paths[str(renderer.get("id", ""))] = node_path

	var behavior_hints := []
	for node_id_variant in sorted_node_ids:
		var node_id := str(node_id_variant)
		var node: Dictionary = nodes[node_id]
		var node_hints := []
		for mono_variant in node.get("mono_behaviours", []):
			var mono: Dictionary = mono_variant
			var hint := _normalize_behavior_hint(mono, str(scene_node_paths.get(node_id, ".")), renderer_node_paths)
			if not hint.is_empty():
				node_hints.append(hint)
				behavior_hints.append(hint)
		if not node_hints.is_empty():
			node["behavior_hints"] = node_hints
		nodes[node_id] = node

	var behavior_kinds := _behavior_kinds_from_hints(behavior_hints)
	var stairs_runtime_supported := _behavior_kinds_are_stairs_only(behavior_kinds) and not has_animator
	var runtime_actor_helper_attached := imported_rigidbody_count > 0 or behavior_kinds.has("top_down_character_controller")
	var renderer_sprite_paths := {}
	var mono_node_paths := {}
	var root_transform_source_id := ""
	var root_game_object_source_id := ""
	if root_ids.size() == 1:
		root_game_object_source_id = str(root_ids[0])
		var root_transform := _find_transform_for_game_object(root_game_object_source_id, transforms)
		root_transform_source_id = str(root_transform.get("id", ""))
	for node_id_variant in sorted_node_ids:
		var node_id := str(node_id_variant)
		var node: Dictionary = nodes[node_id]
		var node_path := str(scene_node_paths.get(node_id, "."))
		var sprite_node_base := "%s Sprite" % str(node.get("name", "Visual"))
		var sprite_node_path := sprite_node_base if node_path == "." else "%s/%s" % [node_path, sprite_node_base]
		for renderer_variant in node.get("sprite_renderers", []):
			var renderer: Dictionary = renderer_variant
			renderer_sprite_paths[str(renderer.get("id", ""))] = sprite_node_path
		for mono_variant in node.get("mono_behaviours", []):
			var mono: Dictionary = mono_variant
			mono_node_paths[str(mono.get("id", ""))] = node_path
	var support_tier := "supported_static"
	var has_complex_edge := complex_edge_collider_count > 0
	var has_deferred_polygon := polygon_paths_deferred > 0
	if not unresolved_sprite_refs.is_empty():
		support_tier = "unresolved_or_skipped"
	elif (has_mono or has_animator) and not stairs_runtime_supported:
		support_tier = "manual_behavior"
	elif has_deferred_polygon or deferred_rigidbody_count > 0 or has_complex_edge:
		support_tier = "approximated"

	var reason_tokens := _prefab_reason_tokens(
		has_box_collider,
		simple_edge_collider_count,
		complex_edge_collider_count,
		polygon_paths_imported,
		polygon_paths_deferred,
		unresolved_sprite_refs,
		behavior_kinds,
		has_mono,
		has_animator,
		has_rigidbody,
		imported_rigidbody_count > 0,
		deferred_rigidbody_count > 0,
		stairs_runtime_supported,
		runtime_actor_helper_attached
	)
	var report_details := _prefab_report_details(
		unresolved_sprite_refs,
		unsupported_components,
		box_colliders.size(),
		simple_edge_collider_count,
		complex_edge_collider_count,
		polygon_collider_count,
		polygon_paths_imported,
		polygon_paths_deferred,
		behavior_kinds,
		rigidbody_count,
		rigidbody_report_source
	)
	return {
		"ok": true,
		"path": asset_path,
		"name": display_name,
		"source_root_transform_id": root_transform_source_id,
		"source_root_game_object_id": root_game_object_source_id,
		"family": _family_from_prefab_path(asset_path, display_name),
		"asset_scope": asset_scope,
		"root_ids": root_ids,
		"nodes": nodes,
		"game_object_paths": scene_node_paths,
		"renderer_sprite_paths": renderer_sprite_paths,
		"mono_node_paths": mono_node_paths,
		"support_tier": support_tier,
		"unsupported_components": unsupported_components,
		"unresolved_sprite_refs": unresolved_sprite_refs,
		"behavior_hints": behavior_hints,
		"reason_tokens": reason_tokens,
		"report_details": report_details,
		"next_step": _prefab_next_step(support_tier, reason_tokens, behavior_kinds),
	}


func _parse_scene(asset_path: String, scene_text: String, script_guid_to_path: Dictionary, sprites: Dictionary, tile_palette_tiles: Dictionary, asset_paths_by_guid: Dictionary, prefabs_by_guid: Dictionary) -> Dictionary:
	var scene_name := asset_path.get_file().trim_suffix(".unity")
	if scene_name != "SC Demo":
		return {
			"ok": true,
			"path": asset_path,
			"name": scene_name,
			"import_supported": false,
			"status": "deferred",
			"detail": "Scene import is deferred in this milestone.",
			"next_step": "Import SC Demo first; SC All Props can be added as a follow-up scene-import slice.",
		}

	var normalized_text := scene_text.replace("\r\n", "\n")
	var documents := _split_unity_documents(normalized_text)
	if documents.is_empty():
		return {
			"ok": false,
			"path": asset_path,
			"error": "No scene documents found.",
		}

	var game_objects := {}
	var transforms := {}
	var tilemaps := {}
	var tilemap_renderers := {}
	var cameras := {}
	var mono_behaviours := {}
	var prefab_instances := []
	var deferred_feature_counts := {
		"tilemap_colliders": 0,
		"composite_colliders": 0,
		"scene_rigidbodies": 0,
	}

	for document in documents:
		var document_class_name := str(document.get("class_name", ""))
		var object_id := str(document.get("object_id", ""))
		var body := str(document.get("body", ""))
		match document_class_name:
			"GameObject":
				game_objects[object_id] = {
					"id": object_id,
					"name": _extract_string(body, "m_Name"),
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
			"Tilemap":
				tilemaps[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"tile_asset_array": _extract_tile_ref_array(body, "m_TileAssetArray"),
					"tile_sprite_array": _extract_tile_ref_array(body, "m_TileSpriteArray"),
					"tile_matrix_array": _extract_tile_matrix_array(body),
					"tile_color_array": _extract_tile_color_array(body),
					"tiles": _extract_tile_cells(body),
				}
			"TilemapRenderer":
				tilemap_renderers[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"sorting_layer_id": _extract_int(body, "m_SortingLayerID", 0),
					"sorting_order": _extract_int(body, "m_SortingOrder", 0),
				}
			"Camera":
				cameras[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"orthographic": _extract_bool_default(body, "orthographic", true),
					"orthographic_size": _extract_float(body, "orthographic size", 0.0),
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
			"PrefabInstance":
				prefab_instances.append(_parse_scene_prefab_instance(body, asset_paths_by_guid, prefabs_by_guid))
			"TilemapCollider2D":
				deferred_feature_counts["tilemap_colliders"] += 1
			"CompositeCollider2D":
				deferred_feature_counts["composite_colliders"] += 1
			"Rigidbody2D":
				deferred_feature_counts["scene_rigidbodies"] += 1

	var transform_to_game_object := {}
	for transform_id_variant in transforms.keys():
		var transform_id := str(transform_id_variant)
		var transform_data: Dictionary = transforms[transform_id]
		transform_to_game_object[transform_id] = str(transform_data.get("game_object_id", "0"))

	var scene_nodes := {}
	for game_object_id_variant in game_objects.keys():
		var game_object_id := str(game_object_id_variant)
		var game_object: Dictionary = game_objects[game_object_id]
		var transform_data := _find_transform_for_game_object(game_object_id, transforms)
		var parent_game_object_id := "0"
		if not transform_data.is_empty():
			var parent_transform_id := str(transform_data.get("parent_transform_id", "0"))
			parent_game_object_id = str(transform_to_game_object.get(parent_transform_id, "0"))
		scene_nodes[game_object_id] = {
			"id": game_object_id,
			"name": str(game_object.get("name", "")),
			"parent_id": parent_game_object_id,
			"children": [],
			"local_position": transform_data.get("local_position", Vector3.ZERO),
			"local_scale": transform_data.get("local_scale", Vector3.ONE),
		}

	for node_id_variant in scene_nodes.keys():
		var node_id := str(node_id_variant)
		var parent_id := str(scene_nodes[node_id].get("parent_id", "0"))
		if scene_nodes.has(parent_id):
			var children: Array = scene_nodes[parent_id].get("children", [])
			children.append(node_id)
			scene_nodes[parent_id]["children"] = children

	var scene_root_ids := []
	for node_id_variant in scene_nodes.keys():
		var node_id := str(node_id_variant)
		if str(scene_nodes[node_id].get("parent_id", "0")) == "0":
			scene_root_ids.append(node_id)
	scene_root_ids.sort()
	var scene_node_paths := _scene_node_paths_for_prefab(scene_root_ids, scene_nodes)

	var tilemap_renderers_by_go := {}
	for renderer_variant in tilemap_renderers.values():
		var renderer: Dictionary = renderer_variant
		tilemap_renderers_by_go[str(renderer.get("game_object_id", "0"))] = renderer

	var tilemap_descriptors := []
	var total_skipped_cells := 0
	for tilemap_variant in tilemaps.values():
		var tilemap: Dictionary = tilemap_variant
		var tilemap_game_object_id := str(tilemap.get("game_object_id", "0"))
		var renderer: Dictionary = tilemap_renderers_by_go.get(tilemap_game_object_id, {})
		var warning_counts := {
			"unresolved_sprite_reference": 0,
			"unsupported_tile_texture": 0,
			"unsupported_tile_alignment": 0,
			"non_identity_tile_matrix": 0,
			"non_default_tile_color": 0,
			"tile_object_to_instantiate": 0,
		}
		var accepted_cells := []
		var source_keys := []
		var tile_asset_array: Array = tilemap.get("tile_asset_array", [])
		var tile_sprite_array: Array = tilemap.get("tile_sprite_array", [])
		var tile_matrix_array: Array = tilemap.get("tile_matrix_array", [])
		var tile_color_array: Array = tilemap.get("tile_color_array", [])
		for cell_variant in tilemap.get("tiles", []):
			var cell: Dictionary = cell_variant
			var sprite_index := int(cell.get("tile_sprite_index", -1))
			var matrix_index := int(cell.get("tile_matrix_index", 0))
			var color_index := int(cell.get("tile_color_index", 0))
			var object_index := int(cell.get("tile_object_index", 65535))
			if object_index != 65535:
				warning_counts["tile_object_to_instantiate"] += 1
				continue
			if sprite_index < 0 or sprite_index >= tile_sprite_array.size():
				warning_counts["unresolved_sprite_reference"] += 1
				continue
			if matrix_index < 0 or matrix_index >= tile_matrix_array.size() or not bool(tile_matrix_array[matrix_index].get("is_identity", false)):
				warning_counts["non_identity_tile_matrix"] += 1
				continue
			if color_index < 0 or color_index >= tile_color_array.size() or not bool(tile_color_array[color_index].get("is_default", false)):
				warning_counts["non_default_tile_color"] += 1
				continue
			var sprite_ref: Dictionary = tile_sprite_array[sprite_index]
			var tile_asset_ref: Dictionary = tile_asset_array[sprite_index] if sprite_index >= 0 and sprite_index < tile_asset_array.size() else {}
			var sprite_desc := _resolve_scene_tile_sprite_desc(sprite_ref, tile_asset_ref, sprites, tile_palette_tiles)
			if sprite_desc.is_empty():
				warning_counts["unresolved_sprite_reference"] += 1
				continue
			var source_key := str(sprite_desc.get("source_key", ""))
			if not ["tileset_grass", "tileset_stone_ground", "tileset_wall", "shadow_props"].has(source_key):
				warning_counts["unsupported_tile_texture"] += 1
				continue
			var rect: Rect2 = sprite_desc.get("rect", Rect2())
			if int(rect.size.x) != 32 or int(rect.size.y) != 32 or int(rect.position.x) % 32 != 0 or int(rect.position.y) % 32 != 0:
				warning_counts["unsupported_tile_alignment"] += 1
				continue
			var atlas_coords := Vector2i(int(rect.position.x) / 32, int(rect.position.y) / 32)
			var cell_coords: Vector3 = cell.get("coords", Vector3.ZERO)
			accepted_cells.append({
				"coords": Vector2i(int(cell_coords.x), -int(cell_coords.y) - 1),
				"atlas_coords": atlas_coords,
				"source_key": source_key,
				"texture_guid": str(sprite_desc.get("texture_guid", "")),
				"sprite_name": str(sprite_desc.get("name", "")),
			})
			if not source_keys.has(source_key):
				source_keys.append(source_key)
		var skipped_cells := 0
		for warning_count_variant in warning_counts.values():
			skipped_cells += int(warning_count_variant)
		total_skipped_cells += skipped_cells
		tilemap_descriptors.append({
			"name": str(scene_nodes.get(tilemap_game_object_id, {}).get("name", "Tilemap")),
			"game_object_id": tilemap_game_object_id,
			"scene_node_path": str(scene_node_paths.get(tilemap_game_object_id, "")),
			"layer_name": _scene_layer_name_for_game_object(tilemap_game_object_id, scene_nodes),
			"sorting_layer_id": int(renderer.get("sorting_layer_id", 0)),
			"sorting_order": int(renderer.get("sorting_order", 0)),
			"global_position": _scene_global_position_for_game_object(tilemap_game_object_id, scene_nodes),
			"cells": accepted_cells,
			"source_keys": source_keys,
			"total_cell_count": Array(tilemap.get("tiles", [])).size(),
			"imported_cell_count": accepted_cells.size(),
			"skipped_cell_count": skipped_cells,
			"warning_counts": warning_counts,
		})

	var prefab_instance_descriptors := []
	for instance_variant in prefab_instances:
		var instance: Dictionary = instance_variant
		var parent_transform_id := str(instance.get("parent_transform_id", "0"))
		var parent_game_object_id := str(transform_to_game_object.get(parent_transform_id, "0"))
		instance["parent_game_object_id"] = parent_game_object_id
		instance["parent_scene_path"] = str(scene_node_paths.get(parent_game_object_id, ""))
		instance["layer_name"] = _scene_layer_name_for_game_object(parent_game_object_id, scene_nodes)
		prefab_instance_descriptors.append(instance)
	prefab_instance_descriptors.sort_custom(_sort_scene_prefab_instances)

	var camera_descriptors := []
	for camera_variant in cameras.values():
		var camera: Dictionary = camera_variant
		var game_object_id := str(camera.get("game_object_id", "0"))
		var scripts := []
		for mono_variant in mono_behaviours.values():
			var mono: Dictionary = mono_variant
			if str(mono.get("game_object_id", "0")) == game_object_id:
				var script_path := str(mono.get("script_path", ""))
				if not script_path.is_empty():
					scripts.append(script_path)
		camera_descriptors.append({
			"name": str(scene_nodes.get(game_object_id, {}).get("name", "Camera")),
			"scene_node_path": str(scene_node_paths.get(game_object_id, "")),
			"position": _scene_global_position_for_game_object(game_object_id, scene_nodes),
			"orthographic": bool(camera.get("orthographic", true)),
			"orthographic_size": float(camera.get("orthographic_size", 0.0)),
			"script_paths": scripts,
		})

	var scene_level_monos := []
	for mono_variant in mono_behaviours.values():
		var mono: Dictionary = mono_variant
		var script_path := str(mono.get("script_path", ""))
		if not script_path.is_empty():
			scene_level_monos.append({
				"script_path": script_path,
				"scene_node_path": str(scene_node_paths.get(str(mono.get("game_object_id", "0")), "")),
				"fields": Dictionary(mono.get("fields", {})).duplicate(true),
			})

	return {
		"ok": true,
		"path": asset_path,
		"name": scene_name,
		"import_supported": true,
		"tilemaps": tilemap_descriptors,
		"prefab_instances": prefab_instance_descriptors,
		"camera_markers": camera_descriptors,
		"scene_level_mono_behaviours": scene_level_monos,
		"deferred_feature_counts": deferred_feature_counts,
		"placed_prefab_count": prefab_instance_descriptors.size(),
		"tile_layer_count": tilemap_descriptors.size(),
		"skipped_tile_cell_count": total_skipped_cells,
		"next_step": "Open the generated SC Demo scene in Godot and use it as an authoring-first reference map; scene-level colliders and runtime scripts are still deferred.",
	}


func _resolve_scene_tile_sprite_desc(sprite_ref: Dictionary, tile_asset_ref: Dictionary, sprites: Dictionary, tile_palette_tiles: Dictionary) -> Dictionary:
	for ref_variant in [sprite_ref, tile_asset_ref]:
		var ref: Dictionary = ref_variant
		if ref.is_empty():
			continue
		var guid := str(ref.get("guid", ""))
		var file_id := str(ref.get("file_id", ""))
		if guid.is_empty() or file_id.is_empty() or file_id == "0":
			continue
		var sprite_key := "%s:%s" % [guid, file_id]
		if sprites.has(sprite_key):
			return Dictionary(sprites[sprite_key])
		if tile_palette_tiles.has(sprite_key):
			var tile_asset: Dictionary = tile_palette_tiles[sprite_key]
			var tile_sprite_key := "%s:%s" % [str(tile_asset.get("sprite_guid", "")), str(tile_asset.get("sprite_file_id", ""))]
			if sprites.has(tile_sprite_key):
				return Dictionary(sprites[tile_sprite_key])
	return {}


func _parse_scene_prefab_instance(body: String, asset_paths_by_guid: Dictionary, prefabs_by_guid: Dictionary) -> Dictionary:
	var source_prefab_guid := _extract_ref_guid(body, "m_SourcePrefab")
	var modifications := _extract_prefab_modifications(body)
	var transform_overrides := {}
	var renderer_overrides := {}
	var mono_overrides := {}
	var game_object_overrides := {}
	var unsupported_overrides := []
	var source_prefab: Dictionary = prefabs_by_guid.get(source_prefab_guid, {})
	var root_transform_source_id := str(source_prefab.get("source_root_transform_id", ""))
	var root_game_object_source_id := str(source_prefab.get("source_root_game_object_id", ""))
	var renderer_sprite_paths: Dictionary = source_prefab.get("renderer_sprite_paths", {})
	var mono_node_paths: Dictionary = source_prefab.get("mono_node_paths", {})
	var game_object_paths: Dictionary = source_prefab.get("game_object_paths", {})
	for modification_variant in modifications:
		var modification: Dictionary = modification_variant
		var target_id := str(modification.get("target_id", ""))
		var property_path := str(modification.get("property_path", ""))
		var value = modification.get("value")
		if target_id == root_transform_source_id:
			transform_overrides[property_path] = value
			continue
		if renderer_sprite_paths.has(target_id):
			var renderer_override: Dictionary = renderer_overrides.get(target_id, {})
			renderer_override[property_path] = value
			renderer_overrides[target_id] = renderer_override
			continue
		if mono_node_paths.has(target_id):
			var mono_override: Dictionary = mono_overrides.get(target_id, {})
			mono_override[property_path] = value
			mono_overrides[target_id] = mono_override
			continue
		if game_object_paths.has(target_id) or target_id == root_game_object_source_id:
			var game_object_override: Dictionary = game_object_overrides.get(target_id, {})
			game_object_override[property_path] = value
			game_object_overrides[target_id] = game_object_override
			continue
		unsupported_overrides.append(property_path)
	return {
		"source_prefab_guid": source_prefab_guid,
		"source_prefab_path": str(asset_paths_by_guid.get(source_prefab_guid, "")),
		"parent_transform_id": _extract_ref_file_id(body, "m_TransformParent"),
		"modifications": modifications,
		"root_order": int(transform_overrides.get("m_RootOrder", 0)),
		"local_position": Vector3(
			float(transform_overrides.get("m_LocalPosition.x", 0.0)),
			float(transform_overrides.get("m_LocalPosition.y", 0.0)),
			float(transform_overrides.get("m_LocalPosition.z", 0.0))
		),
		"local_scale": Vector3(
			float(transform_overrides.get("m_LocalScale.x", 1.0)),
			float(transform_overrides.get("m_LocalScale.y", 1.0)),
			float(transform_overrides.get("m_LocalScale.z", 1.0))
		),
		"name_override": str(game_object_overrides.get(root_game_object_source_id, {}).get("m_Name", "")),
		"renderer_overrides": renderer_overrides,
		"mono_overrides": mono_overrides,
		"game_object_overrides": game_object_overrides,
		"unsupported_override_paths": unsupported_overrides,
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


func _scene_node_paths_for_prefab(root_ids: Array, nodes: Dictionary) -> Dictionary:
	var paths := {}
	if root_ids.size() == 1 and nodes.has(str(root_ids[0])):
		var root_id := str(root_ids[0])
		paths[root_id] = "."
		for child_id_variant in nodes[root_id].get("children", []):
			_assign_scene_node_paths(str(child_id_variant), "", nodes, paths)
	else:
		for root_id_variant in root_ids:
			_assign_scene_node_paths(str(root_id_variant), "", nodes, paths)
	return paths


func _assign_scene_node_paths(node_id: String, parent_path: String, nodes: Dictionary, paths: Dictionary) -> void:
	if not nodes.has(node_id):
		return
	var node: Dictionary = nodes[node_id]
	var name := str(node.get("name", "Node"))
	var path := name if parent_path.is_empty() else "%s/%s" % [parent_path, name]
	paths[node_id] = path
	for child_id_variant in node.get("children", []):
		_assign_scene_node_paths(str(child_id_variant), path, nodes, paths)


func _normalize_behavior_hint(mono: Dictionary, scene_node_path: String, renderer_node_paths: Dictionary) -> Dictionary:
	var script_path := str(mono.get("script_path", ""))
	var script_name := script_path.get_file().trim_suffix(".cs")
	if script_name.is_empty():
		return {}
	var base_hint := {
		"script_path": script_path,
		"script_name": script_name,
		"scene_node_path": scene_node_path,
		"deferred_runtime": true,
	}
	match script_name:
		"StairsLayerTrigger":
			base_hint["kind"] = "stairs_layer_trigger"
			base_hint["data"] = _stairs_behavior_data(mono)
			return base_hint
		"SpriteColorAnimation":
			base_hint["kind"] = "sprite_color_animation"
			base_hint["data"] = _sprite_color_animation_data(mono)
			return base_hint
		"PropsAltar":
			base_hint["kind"] = "altar_trigger"
			base_hint["data"] = _altar_behavior_data(mono, renderer_node_paths)
			return base_hint
		"TopDownCharacterController":
			base_hint["kind"] = "top_down_character_controller"
			base_hint["data"] = _top_down_controller_data(mono)
			return base_hint
		_:
			return {}


func _stairs_behavior_data(mono: Dictionary) -> Dictionary:
	var fields: Dictionary = mono.get("fields", {})
	return {
		"direction": _stairs_direction_name(fields.get("direction", 0)),
		"upper_layer": str(fields.get("layerUpper", "")),
		"upper_sorting_layer": str(fields.get("sortingLayerUpper", "")),
		"lower_layer": str(fields.get("layerLower", "")),
		"lower_sorting_layer": str(fields.get("sortingLayerLower", "")),
	}


func _sprite_color_animation_data(mono: Dictionary) -> Dictionary:
	var fields: Dictionary = mono.get("fields", {})
	var gradient := _extract_gradient_data(str(mono.get("raw_body", "")))
	return {
		"duration_seconds": float(fields.get("time", 0.0)),
		"gradient_mode": gradient.get("gradient_mode", "blend"),
		"color_keys": gradient.get("color_keys", []),
		"alpha_keys": gradient.get("alpha_keys", []),
	}


func _altar_behavior_data(mono: Dictionary, renderer_node_paths: Dictionary) -> Dictionary:
	var fields: Dictionary = mono.get("fields", {})
	var rune_node_paths := []
	for renderer_id_variant in _extract_list_file_ids(str(mono.get("raw_body", "")), "runes"):
		var renderer_id := str(renderer_id_variant)
		if renderer_node_paths.has(renderer_id):
			rune_node_paths.append(renderer_node_paths[renderer_id])
	return {
		"rune_node_paths": rune_node_paths,
		"lerp_speed": float(fields.get("lerpSpeed", 0.0)),
		"trigger_mode": "alpha_lerp_on_trigger",
	}


func _top_down_controller_data(mono: Dictionary) -> Dictionary:
	var fields: Dictionary = mono.get("fields", {})
	return {
		"speed": float(fields.get("speed", 0.0)),
		"input_scheme": "wasd_4dir",
		"direction_parameter": "Direction",
		"moving_parameter": "IsMoving",
		"direction_values": {
			"south": 0,
			"north": 1,
			"east": 2,
			"west": 3,
		},
		"requires_animator": true,
		"requires_rigidbody2d": true,
	}


func _extract_list_file_ids(body: String, key: String) -> Array:
	var ids := []
	var lines := body.split("\n")
	var in_list := false
	for raw_line_variant in lines:
		var raw_line: String = str(raw_line_variant)
		if raw_line.begins_with("  %s:" % key):
			in_list = true
			continue
		if not in_list:
			continue
		if raw_line.begins_with("  ") and not raw_line.begins_with("  -"):
			break
		var line: String = raw_line.strip_edges()
		if line.begins_with("- {fileID: "):
			ids.append(line.trim_prefix("- {fileID: ").trim_suffix("}"))
	return ids


func _extract_gradient_data(body: String) -> Dictionary:
	var values := {}
	for raw_line in _extract_nested_block_lines(body, "gradient"):
		var line: String = str(raw_line).strip_edges()
		var colon: int = line.find(":")
		if colon <= 0:
			continue
		var nested_key: String = line.substr(0, colon).strip_edges()
		var nested_value: String = line.substr(colon + 1).strip_edges()
		values[nested_key] = nested_value
	var gradient_mode_raw = values.get("m_Mode", values.get("mode", "0"))
	var color_key_count := int(_parse_scalar(str(values.get("m_NumColorKeys", "0"))))
	var alpha_key_count := int(_parse_scalar(str(values.get("m_NumAlphaKeys", "0"))))
	var color_keys := []
	for index in range(color_key_count):
		var color := _parse_color_literal(str(values.get("key%d" % index, "")))
		if color.is_empty():
			continue
		color_keys.append({
			"time": _gradient_time_to_ratio(_parse_scalar(str(values.get("ctime%d" % index, "0")))),
			"color": color,
		})
	var alpha_keys := []
	for index in range(alpha_key_count):
		var alpha_color := _parse_color_literal(str(values.get("key%d" % index, "")))
		if alpha_color.is_empty():
			continue
		alpha_keys.append({
			"time": _gradient_time_to_ratio(_parse_scalar(str(values.get("atime%d" % index, "0")))),
			"alpha": float(alpha_color.get("a", 0.0)),
		})
	return {
		"gradient_mode": _gradient_mode_name(gradient_mode_raw),
		"color_keys": color_keys,
		"alpha_keys": alpha_keys,
	}


func _extract_nested_block_lines(body: String, key: String) -> Array:
	var lines := body.split("\n")
	var nested := []
	var in_block := false
	for raw_line in lines:
		if raw_line.begins_with("  %s:" % key):
			in_block = true
			continue
		if not in_block:
			continue
		if not raw_line.begins_with("    "):
			break
		nested.append(raw_line.substr(4))
	return nested


func _parse_color_literal(value: String) -> Dictionary:
	var match := _regex_search(value, "\\{r: ([^,]+), g: ([^,]+), b: ([^,]+), a: ([^\\}]+)\\}")
	if match.size() < 4:
		return {}
	return {
		"r": float(match[0]),
		"g": float(match[1]),
		"b": float(match[2]),
		"a": float(match[3]),
	}


func _gradient_time_to_ratio(value) -> float:
	return clamp(float(value) / 65535.0, 0.0, 1.0)


func _gradient_mode_name(value) -> String:
	var mode_int := int(_parse_scalar(str(value)))
	match mode_int:
		1:
			return "fixed"
		_:
			return "blend"


func _stairs_direction_name(value) -> String:
	match int(_parse_scalar(str(value))):
		0:
			return "north"
		2:
			return "west"
		3:
			return "east"
		_:
			return "south"


func _behavior_kinds_from_hints(behavior_hints: Array) -> Array:
	var kinds := []
	for hint_variant in behavior_hints:
		var hint: Dictionary = hint_variant
		var kind := str(hint.get("kind", ""))
		if not kind.is_empty() and not kinds.has(kind):
			kinds.append(kind)
	return kinds


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


func _extract_polygon_paths(body: String) -> Array:
	var paths := []
	var lines := body.split("\n")
	var in_paths := false
	var current_path := []
	for raw_line_variant in lines:
		var raw_line := str(raw_line_variant)
		if raw_line.begins_with("    m_Paths:"):
			in_paths = true
			continue
		if not in_paths:
			continue
		if raw_line.begins_with("  ") and not raw_line.begins_with("    "):
			break
		var line := raw_line.strip_edges()
		if line.begins_with("- - {x: "):
			if not current_path.is_empty():
				paths.append(current_path)
			current_path = []
			var first_match := _regex_search(line, "\\{x: ([^,]+), y: ([^\\}]+)\\}")
			if first_match.size() >= 2:
				current_path.append(Vector2(float(first_match[0]), float(first_match[1])))
		elif line.begins_with("- {x: "):
			var point_match := _regex_search(line, "\\{x: ([^,]+), y: ([^\\}]+)\\}")
			if point_match.size() >= 2:
				current_path.append(Vector2(float(point_match[0]), float(point_match[1])))
	if not current_path.is_empty():
		paths.append(current_path)
	return paths


func _extract_tile_ref_array(body: String, key: String) -> Array:
	var values := []
	var block := _extract_named_block(body, key)
	if block.is_empty():
		return values
	var lines := block.split("\n")
	var index := 0
	while index < lines.size():
		var line := str(lines[index]).strip_edges()
		if not line.begins_with("- m_RefCount:"):
			index += 1
			continue
		var ref_count := int(_safe_float(_scalar_after_colon(line)))
		var data_line := str(lines[index + 1]).strip_edges() if index + 1 < lines.size() else ""
		var data_match := _regex_search(data_line, "m_Data: \\{fileID: ([\\-0-9]+)(?:, guid: ([0-9a-f]+), type: (\\d+))?\\}")
		var entry := {
			"ref_count": ref_count,
			"file_id": "0",
			"guid": "",
			"type": 0,
		}
		if data_match.size() >= 1:
			entry["file_id"] = str(data_match[0])
		if data_match.size() >= 2:
			entry["guid"] = str(data_match[1])
		if data_match.size() >= 3:
			entry["type"] = int(_safe_float(data_match[2]))
		values.append(entry)
		index += 2
	return values


func _extract_tile_matrix_array(body: String) -> Array:
	var entries := []
	var block := _extract_named_block(body, "m_TileMatrixArray")
	if block.is_empty():
		return entries
	var current := {"ref_count": 0, "values": {}, "is_identity": false}
	for raw_line_variant in block.split("\n"):
		var raw_line := str(raw_line_variant)
		if raw_line.begins_with("  - m_RefCount:"):
			if current.get("values", {}).size() > 0 or int(current.get("ref_count", 0)) > 0:
				current["is_identity"] = _matrix_is_identity(current.get("values", {}))
				entries.append(current)
			current = {"ref_count": int(_scalar_after_colon(raw_line.strip_edges())), "values": {}, "is_identity": false}
			continue
		var line := raw_line.strip_edges()
		var colon := line.find(":")
		if colon <= 0:
			continue
		var value_key := line.substr(0, colon)
		if not value_key.begins_with("e"):
			continue
		current["values"][value_key] = float(line.substr(colon + 1).strip_edges())
	if current.get("values", {}).size() > 0 or int(current.get("ref_count", 0)) > 0:
		current["is_identity"] = _matrix_is_identity(current.get("values", {}))
		entries.append(current)
	return entries


func _extract_tile_color_array(body: String) -> Array:
	var entries := []
	var block := _extract_named_block(body, "m_TileColorArray")
	if block.is_empty():
		return entries
	for match_variant in _regex_search_all(block, "- m_RefCount: ([0-9]+)\\n\\s+m_Data: \\{r: ([^,]+), g: ([^,]+), b: ([^,]+), a: ([^\\}]+)\\}"):
		var match: Array = match_variant
		var color := {
			"r": _safe_float(match[1]),
			"g": _safe_float(match[2]),
			"b": _safe_float(match[3]),
			"a": _safe_float(match[4]),
		}
		entries.append({
			"ref_count": int(match[0]),
			"color": color,
			"is_default": _tile_color_is_default(color),
		})
	return entries


func _extract_tile_cells(body: String) -> Array:
	var cells := []
	var block := _extract_named_block(body, "m_Tiles")
	if block.is_empty():
		return cells
	var current := {}
	for raw_line_variant in block.split("\n"):
		var line := str(raw_line_variant).strip_edges()
		if line.begins_with("- first: {x: "):
			if not current.is_empty():
				cells.append(current)
			var coords_match := _regex_search(line, "\\{x: ([^,]+), y: ([^,]+), z: ([^\\}]+)\\}")
			if coords_match.size() >= 3:
				current = {
					"coords": Vector3(_safe_float(coords_match[0]), _safe_float(coords_match[1]), _safe_float(coords_match[2])),
					"tile_index": 0,
					"tile_sprite_index": 0,
					"tile_matrix_index": 0,
					"tile_color_index": 0,
					"tile_object_index": 65535,
				}
			else:
				current = {}
			continue
		if current.is_empty():
			continue
		if line.begins_with("m_TileIndex:"):
			current["tile_index"] = int(_safe_float(_scalar_after_colon(line)))
		elif line.begins_with("m_TileSpriteIndex:"):
			current["tile_sprite_index"] = int(_safe_float(_scalar_after_colon(line)))
		elif line.begins_with("m_TileMatrixIndex:"):
			current["tile_matrix_index"] = int(_safe_float(_scalar_after_colon(line)))
		elif line.begins_with("m_TileColorIndex:"):
			current["tile_color_index"] = int(_safe_float(_scalar_after_colon(line)))
		elif line.begins_with("m_TileObjectToInstantiateIndex:"):
			current["tile_object_index"] = int(_safe_float(_scalar_after_colon(line)))
	if not current.is_empty():
		cells.append(current)
	return cells


func _extract_prefab_modifications(body: String) -> Array:
	var modifications := []
	var lines := body.split("\n")
	var index := 0
	while index < lines.size():
		var line := str(lines[index]).strip_edges()
		if not line.begins_with("- target: {fileID: "):
			index += 1
			continue
		var target_match := _regex_search(line, "\\{fileID: ([\\-0-9]+), guid: ([0-9a-f]+),")
		var property_line := str(lines[index + 2]).strip_edges() if index + 2 < lines.size() else ""
		var value_line := str(lines[index + 3]).strip_edges() if index + 3 < lines.size() else ""
		var object_line := str(lines[index + 4]).strip_edges() if index + 4 < lines.size() else ""
		if target_match.size() >= 2 and property_line.begins_with("propertyPath:") and value_line.begins_with("value:") and object_line.begins_with("objectReference:"):
			modifications.append({
				"target_id": str(target_match[0]),
				"target_guid": str(target_match[1]),
				"property_path": _scalar_after_colon(property_line),
				"value": _parse_scalar(_scalar_after_colon(value_line)),
				"object_reference_file_id": _regex_capture(object_line, "objectReference: \\{fileID: ([\\-0-9]+)\\}"),
			})
		index += 1
	return modifications


func _extract_named_block(body: String, key: String) -> String:
	var lines := body.split("\n")
	var block_lines := []
	var in_block := false
	for raw_line_variant in lines:
		var raw_line := str(raw_line_variant)
		if raw_line.begins_with("  %s:" % key):
			in_block = true
			continue
		if not in_block:
			continue
		if raw_line.begins_with("  ") and not raw_line.begins_with("    ") and not raw_line.begins_with("  - "):
			break
		block_lines.append(raw_line)
	return "\n".join(block_lines)


func _matrix_is_identity(values: Dictionary) -> bool:
	var identity := {
		"e00": 1.0,
		"e11": 1.0,
		"e22": 1.0,
		"e33": 1.0,
		"e01": 0.0,
		"e02": 0.0,
		"e03": 0.0,
		"e10": 0.0,
		"e12": 0.0,
		"e13": 0.0,
		"e20": 0.0,
		"e21": 0.0,
		"e23": 0.0,
		"e30": 0.0,
		"e31": 0.0,
		"e32": 0.0,
	}
	for key_variant in identity.keys():
		var value_key := str(key_variant)
		var expected := float(identity[value_key])
		if abs(float(values.get(value_key, 0.0)) - expected) > 0.0001:
			return false
	return true


func _tile_color_is_default(color: Dictionary) -> bool:
	return _safe_float(color.get("r", 0.0)) == 1.0 and _safe_float(color.get("g", 0.0)) == 1.0 and _safe_float(color.get("b", 0.0)) == 1.0 and _safe_float(color.get("a", 0.0)) == 1.0


func _safe_float(value) -> float:
	var text := str(value).strip_edges()
	if text == "NaN":
		return 0.0
	return float(text)


func _extract_string(body: String, key: String) -> String:
	return _regex_capture(body, "(?m)^\\s*%s: (.+)$" % key)


func _extract_int(body: String, key: String, default_value: int = 0) -> int:
	var value := _regex_capture(body, "(?m)^\\s*%s: ([\\-0-9]+)$" % key)
	return default_value if value.is_empty() else int(value)


func _extract_bool(body: String, key: String) -> bool:
	return _extract_int(body, key, 0) != 0


func _extract_bool_default(body: String, key: String, default_value: bool) -> bool:
	return _extract_int(body, key, 1 if default_value else 0) != 0


func _extract_float(body: String, key: String, default_value: float = 0.0) -> float:
	var value := _regex_capture(body, "(?m)^\\s*%s: ([\\-0-9\\.]+)$" % key)
	return default_value if value.is_empty() else float(value)


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


func _scene_global_position_for_game_object(game_object_id: String, nodes: Dictionary) -> Vector3:
	if not nodes.has(game_object_id):
		return Vector3.ZERO
	var position := Vector3.ZERO
	var current_id := game_object_id
	while nodes.has(current_id):
		var node: Dictionary = nodes[current_id]
		position += Vector3(node.get("local_position", Vector3.ZERO))
		current_id = str(node.get("parent_id", "0"))
		if current_id == "0":
			break
	return position


func _scene_layer_name_for_game_object(game_object_id: String, nodes: Dictionary) -> String:
	var current_id := game_object_id
	while nodes.has(current_id):
		var node: Dictionary = nodes[current_id]
		var name := str(node.get("name", ""))
		if name.begins_with("LAYER "):
			return _normalize_scene_layer_name(name)
		current_id = str(node.get("parent_id", "0"))
		if current_id == "0":
			break
	return "Layer 1"


func _normalize_scene_layer_name(value: String) -> String:
	return value.replace("LAYER ", "Layer ")


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


func _regex_search_all(text: String, pattern: String) -> Array:
	var regex := RegEx.new()
	regex.compile(pattern)
	var matches := []
	for match_variant in regex.search_all(text):
		var match: RegExMatch = match_variant
		var result := []
		for index in range(1, match.get_group_count() + 1):
			result.append(match.get_string(index))
		matches.append(result)
	return matches


func _family_from_prefab_path(asset_path: String, display_name: String) -> String:
	if not asset_path.contains("/Prefab/"):
		return "editor_only"
	if asset_path.contains("/Prefab/Plant/"):
		return "plants"
	if asset_path.contains("/Prefab/Player/"):
		return "player"
	if display_name.begins_with("PF Struct"):
		return "struct"
	return "props"


func _prefab_reason_tokens(
	has_box_collider: bool,
	simple_edge_collider_count: int,
	complex_edge_collider_count: int,
	polygon_paths_imported: int,
	polygon_paths_deferred: int,
	unresolved_sprite_refs: Array,
	behavior_kinds: Array,
	has_mono: bool,
	has_animator: bool,
	has_rigidbody: bool,
	has_imported_rigidbody: bool,
	has_deferred_rigidbody: bool,
	stairs_runtime_supported: bool,
	runtime_actor_helper_attached: bool
) -> Array:
	var reasons := []
	if has_box_collider:
		reasons.append("box_collider_imported")
	if simple_edge_collider_count > 0:
		reasons.append("edge_collider_imported")
	if complex_edge_collider_count > 0:
		reasons.append("edge_collider_deferred_complex")
	if polygon_paths_imported > 0:
		reasons.append("polygon_collider_imported")
	if polygon_paths_deferred > 0:
		reasons.append("polygon_collider_deferred")
		reasons.append("polygon_collider_deferred_complex")
	if not unresolved_sprite_refs.is_empty():
		reasons.append("unresolved_sprite_reference")
	if has_mono and not stairs_runtime_supported:
		reasons.append("mono_behaviour_present")
	for behavior_kind_variant in behavior_kinds:
		match str(behavior_kind_variant):
			"stairs_layer_trigger":
				reasons.append("stairs_layer_trigger_hint")
			"sprite_color_animation":
				reasons.append("sprite_color_animation_hint")
			"altar_trigger":
				reasons.append("altar_trigger_hint")
			"top_down_character_controller":
				reasons.append("top_down_character_controller_hint")
	if has_animator:
		reasons.append("animator_present")
	if has_imported_rigidbody:
		reasons.append("rigidbody_imported")
	if has_rigidbody and has_deferred_rigidbody:
		reasons.append("rigidbody_deferred")
	if stairs_runtime_supported:
		reasons.append("stairs_runtime_imported")
	if runtime_actor_helper_attached:
		reasons.append("runtime_actor_helper_attached")
	return reasons


func _prefab_report_details(
	unresolved_sprite_refs: Array,
	unsupported_components: Array,
	box_collider_count: int,
	simple_edge_collider_count: int,
	complex_edge_collider_count: int,
	polygon_collider_count: int,
	polygon_paths_imported: int,
	polygon_paths_deferred: int,
	behavior_kinds: Array,
	rigidbody_count: int,
	rigidbody_report_source: Dictionary
) -> Dictionary:
	var details := {}
	if not unresolved_sprite_refs.is_empty():
		details["unresolved_sprite_refs"] = unresolved_sprite_refs.duplicate()
	if not unsupported_components.is_empty():
		details["unsupported_components"] = unsupported_components.duplicate()
	if not behavior_kinds.is_empty():
		details["behavior_kinds"] = behavior_kinds.duplicate()
	if box_collider_count > 0:
		details["box_collider_count"] = box_collider_count
	if simple_edge_collider_count > 0:
		details["simple_edge_collider_count"] = simple_edge_collider_count
	if complex_edge_collider_count > 0:
		details["complex_edge_collider_count"] = complex_edge_collider_count
	if polygon_collider_count > 0:
		details["polygon_collider_count"] = polygon_collider_count
	if polygon_paths_imported > 0:
		details["polygon_paths_imported"] = polygon_paths_imported
	if polygon_paths_deferred > 0:
		details["polygon_paths_deferred"] = polygon_paths_deferred
	if rigidbody_count > 0:
		details["rigidbody_count"] = rigidbody_count
		details["rigidbody_body_type"] = str(rigidbody_report_source.get("body_type_name", "dynamic"))
		details["rigidbody_mass"] = float(rigidbody_report_source.get("mass", 1.0))
		details["rigidbody_linear_damp"] = float(rigidbody_report_source.get("linear_damp", 0.0))
		details["rigidbody_angular_damp"] = float(rigidbody_report_source.get("angular_damp", 0.05))
		details["rigidbody_gravity_scale"] = float(rigidbody_report_source.get("gravity_scale", 1.0))
		details["rigidbody_freeze_rotation"] = bool(rigidbody_report_source.get("freeze_rotation", false))
	return details


func _prefab_next_step(support_tier: String, reason_tokens: Array, behavior_kinds: Array = []) -> String:
	if reason_tokens.has("stairs_runtime_imported") and support_tier == "supported_static":
		return "Place the generated stairs scene directly in Godot; the directional render-layer trigger is already configured."
	if reason_tokens.has("stairs_layer_trigger_hint"):
		if support_tier == "unresolved_or_skipped":
			return "Repair the unresolved stairs sprite mapping, then rebuild the layer/sorting trigger in Godot from the preserved stairs behavior hint."
		return "Use the generated stairs scene as a visual base and rebuild the layer/sorting trigger in Godot from the preserved stairs behavior hint."
	if reason_tokens.has("sprite_color_animation_hint"):
		return "Use the generated scene as a visual base and rebuild the rune glow/color animation from the preserved normalized gradient data."
	if reason_tokens.has("altar_trigger_hint"):
		return "Use the generated altar scene as a visual base and rebuild the trigger-driven rune glow using the preserved rune-node mapping and lerp settings."
	if reason_tokens.has("top_down_character_controller_hint"):
		if reason_tokens.has("runtime_actor_helper_attached"):
			return "Use the generated player scene as a visual base; the stair/runtime actor helper is already attached, but movement, animator parameters, and gameplay behavior still need a Godot controller."
		return "Use the generated player scene as a visual base and rebuild movement, animator parameters, and rigidbody behavior from the preserved controller hint."
	match support_tier:
		"supported_static":
			if reason_tokens.has("rigidbody_imported") and reason_tokens.has("runtime_actor_helper_attached"):
				return "Place the generated scene directly in Godot; runtime-ready rigidbody settings, collisions, and stair actor support are preserved."
			if reason_tokens.has("rigidbody_imported"):
				return "Place the generated scene directly in Godot; runtime-ready rigidbody settings and collisions are preserved."
			return "Place the generated scene directly in Godot and add gameplay logic only if your project needs it."
		"approximated":
			if reason_tokens.has("polygon_collider_deferred") or reason_tokens.has("edge_collider_deferred_complex"):
				return "Use the generated scene as a visual base, then rebuild or refine collision/physics behavior manually in Godot."
			if reason_tokens.has("rigidbody_deferred"):
				return "Use the generated scene as a visual and collision base, then rebuild rigidbody-driven physics behavior manually in Godot."
			return "Use the generated scene as a visual base and inspect the preserved metadata before relying on runtime behavior."
		"manual_behavior":
			return "Use the generated scene as a visual base and rebuild the deferred Unity behavior in Godot using the preserved metadata."
		_:
			return "Inspect the unresolved references and either repair the importer mapping or use fallback atlas scenes for this asset."


func _behavior_kinds_are_stairs_only(behavior_kinds: Array) -> bool:
	if behavior_kinds.is_empty():
		return false
	for behavior_kind_variant in behavior_kinds:
		if str(behavior_kind_variant) != "stairs_layer_trigger":
			return false
	return true


func _rigidbody_config_supported(rigidbody: Dictionary) -> bool:
	var body_type := int(rigidbody.get("body_type", 0))
	var use_auto_mass := bool(rigidbody.get("use_auto_mass", false))
	var constraints := int(rigidbody.get("constraints", 0))
	return body_type == 0 and not use_auto_mass and (constraints & ~4) == 0


func _rigidbody_body_type_name(body_type: int) -> String:
	match body_type:
		0:
			return "dynamic"
		1:
			return "kinematic"
		2:
			return "static"
		_:
			return "unknown"


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


func _sort_scene_paths(a, b) -> bool:
	return str(a.get("path", "")) < str(b.get("path", ""))


func _sort_scene_prefab_instances(a, b) -> bool:
	var layer_a := str(a.get("layer_name", ""))
	var layer_b := str(b.get("layer_name", ""))
	if layer_a != layer_b:
		return layer_a < layer_b
	var parent_a := str(a.get("parent_scene_path", ""))
	var parent_b := str(b.get("parent_scene_path", ""))
	if parent_a != parent_b:
		return parent_a < parent_b
	var order_a := int(a.get("root_order", 0))
	var order_b := int(b.get("root_order", 0))
	if order_a != order_b:
		return order_a < order_b
	return str(a.get("source_prefab_path", "")) < str(b.get("source_prefab_path", ""))
