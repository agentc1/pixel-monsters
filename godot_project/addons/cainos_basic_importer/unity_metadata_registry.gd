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
	var editor_only_prefabs = []
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
			if str(prefab_result.get("asset_scope", "semantic_prefab")) == "editor_only_prefab":
				editor_only_prefabs.append(prefab_result)
			else:
				prefabs.append(prefab_result)

	prefabs.sort_custom(_sort_prefab_paths)
	editor_only_prefabs.sort_custom(_sort_prefab_paths)
	var summary = {
		"supported_static_prefabs": 0,
		"approximated_prefabs": 0,
		"manual_behavior_prefabs": 0,
		"unresolved_or_skipped_prefabs": 0,
		"editor_only_prefabs": editor_only_prefabs.size(),
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
		"editor_only_prefabs": editor_only_prefabs,
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
	var internal_id = _regex_capture(block_text, "(?m)^\\s+internalID: ([\\-0-9]+)$")
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
	var polygon_colliders := {}
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
			"MonoBehaviour":
				mono_behaviours[object_id] = {
					"id": object_id,
					"game_object_id": _extract_ref_file_id(body, "m_GameObject"),
					"script_guid": _extract_ref_guid(body, "m_Script"),
					"script_path": script_guid_to_path.get(_extract_ref_guid(body, "m_Script"), ""),
					"fields": _extract_mono_fields(body),
					"raw_body": body,
				}
			"Rigidbody2D", "Animator":
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
	var has_rigidbody := unsupported_components.has("Rigidbody2D")
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

	var support_tier := "supported_static"
	var has_complex_edge := complex_edge_collider_count > 0
	var has_deferred_polygon := polygon_paths_deferred > 0
	if not unresolved_sprite_refs.is_empty():
		support_tier = "unresolved_or_skipped"
	elif has_mono or has_animator:
		support_tier = "manual_behavior"
	elif has_deferred_polygon or has_rigidbody or has_complex_edge:
		support_tier = "approximated"

	var display_name := asset_path.get_file().trim_suffix(".prefab")
	var asset_scope := "semantic_prefab" if asset_path.contains("/Prefab/") else "editor_only_prefab"
	var behavior_kinds := _behavior_kinds_from_hints(behavior_hints)
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
		has_rigidbody
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
		behavior_kinds
	)
	return {
		"ok": true,
		"path": asset_path,
		"name": display_name,
		"family": _family_from_prefab_path(asset_path, display_name),
		"asset_scope": asset_scope,
		"root_ids": root_ids,
		"nodes": nodes,
		"support_tier": support_tier,
		"unsupported_components": unsupported_components,
		"unresolved_sprite_refs": unresolved_sprite_refs,
		"behavior_hints": behavior_hints,
		"reason_tokens": reason_tokens,
		"report_details": report_details,
		"next_step": _prefab_next_step(support_tier, reason_tokens, behavior_kinds),
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
	has_rigidbody: bool
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
	if has_mono:
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
	if has_rigidbody:
		reasons.append("rigidbody_deferred")
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
	behavior_kinds: Array
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
	return details


func _prefab_next_step(support_tier: String, reason_tokens: Array, behavior_kinds: Array = []) -> String:
	if reason_tokens.has("stairs_layer_trigger_hint"):
		if support_tier == "unresolved_or_skipped":
			return "Repair the unresolved stairs sprite mapping, then rebuild the layer/sorting trigger in Godot from the preserved stairs behavior hint."
		return "Use the generated stairs scene as a visual base and rebuild the layer/sorting trigger in Godot from the preserved stairs behavior hint."
	if reason_tokens.has("sprite_color_animation_hint"):
		return "Use the generated scene as a visual base and rebuild the rune glow/color animation from the preserved normalized gradient data."
	if reason_tokens.has("altar_trigger_hint"):
		return "Use the generated altar scene as a visual base and rebuild the trigger-driven rune glow using the preserved rune-node mapping and lerp settings."
	if reason_tokens.has("top_down_character_controller_hint"):
		return "Use the generated player scene as a visual base and rebuild movement, animator parameters, and rigidbody behavior from the preserved controller hint."
	match support_tier:
		"supported_static":
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
