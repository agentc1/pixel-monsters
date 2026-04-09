extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var output_root := str(args.get("output_root", "res://cainos_imports/basic_real_acceptance"))

	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_preview_map.tscn"), "basic_preview_map", true)
	_validate_helper_scene(output_root.path_join("scenes/helpers/basic_prefab_catalog.tscn"), "basic_prefab_catalog", false)
	_validate_report_files(output_root)
	_validate_bush_prefab(output_root)
	_validate_lantern_prefab(output_root)
	_validate_polygon_prefabs(output_root)
	_validate_stairs_prefab(output_root)
	_validate_east_west_stairs_prefabs(output_root)
	_validate_altar_prefab(output_root)
	_validate_rune_prefab(output_root)
	_validate_player_prefab(output_root)

	_finish()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	var index := 0
	while index < args.size():
		var token := args[index]
		match token:
			"--output-root":
				if index + 1 < args.size():
					parsed["output_root"] = args[index + 1]
					index += 1
		index += 1
	return parsed


func _validate_helper_scene(scene_path: String, expected_name: String, expect_tile_layers: bool) -> void:
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Helper scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Helper scene instantiates: %s" % scene_path)
	if instance == null:
		return
	_assert_eq(instance.name, expected_name, "Helper scene root name: %s" % expected_name)
	if expect_tile_layers:
		_assert_true(_count_tile_map_layers(instance) >= 1, "Preview scene includes TileMapLayer nodes")
	instance.free()


func _validate_bush_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "plants", "PF Plant - Bush 01")
	if root == null:
		return
	var shadow := root.find_child("Shadow", true, false)
	_assert_true(shadow is Node2D, "Bush prefab keeps Shadow child")
	root.free()


func _validate_lantern_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "props", "PF Props - Stone Lantern 01")
	if root == null:
		return
	var body := root.find_child("BoxCollider_0", true, false)
	_assert_true(body is StaticBody2D, "Stone Lantern keeps StaticBody2D box collider")
	if body is StaticBody2D:
		var shape_node := _first_collision_shape(body)
		_assert_true(shape_node != null, "Stone Lantern box collider has CollisionShape2D")
		if shape_node != null:
			_assert_true(shape_node.shape is RectangleShape2D, "Stone Lantern collider shape is RectangleShape2D")
	root.free()


func _validate_polygon_prefabs(output_root: String) -> void:
	for prefab_name in [
		"PF Props - Statue 01",
		"PF Props - Stone 06",
		"PF Props - Stone 07",
		"PF Props - Well 01",
		"PF Props - Wooden Gate 01 Opened",
	]:
		_validate_polygon_prefab_collision(output_root, "props", prefab_name)
	_validate_polygon_prefab_collision(output_root, "struct", "PF Struct - Gate 02")
	for prefab_name in [
		"PF Props - Barrel 01",
		"PF Props - Pot 01",
		"PF Props - Pot 02",
		"PF Props - Pot 03",
	]:
		_validate_polygon_prefab_collision(output_root, "props", prefab_name)


func _validate_polygon_prefab_collision(output_root: String, family: String, prefab_name: String) -> void:
	var root := _instantiate_prefab(output_root, family, prefab_name)
	if root == null:
		return
	_assert_true(_count_collision_polygons(root) > 0, "%s imports CollisionPolygon2D" % prefab_name)
	root.free()


func _validate_stairs_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "struct", "PF Struct - Stairs S 01 L")
	if root == null:
		return
	_assert_true(not _behavior_hints_for(root, "stairs_layer_trigger").is_empty(), "Stairs prefab exposes stairs_layer_trigger behavior hint")
	var behaviour_node := root.find_child("Stairs Layer Trigger", true, false)
	_assert_true(behaviour_node != null, "Stairs prefab keeps trigger helper node")
	if behaviour_node != null:
		_assert_true(behaviour_node.has_meta("unity_mono_behaviours"), "Stairs prefab preserves deferred MonoBehaviour metadata")
		_assert_true(not _behavior_hints_for(behaviour_node, "stairs_layer_trigger").is_empty(), "Stairs trigger node keeps local behavior hint")
	root.free()


func _validate_east_west_stairs_prefabs(output_root: String) -> void:
	for prefab_name in [
		"PF Struct - Stairs E 01",
		"PF Struct - Stairs E 02",
		"PF Struct - Stairs W 01",
		"PF Struct - Stairs W 02",
	]:
		var root := _instantiate_prefab(output_root, "struct", prefab_name)
		if root == null:
			continue
		_assert_true(not _behavior_hints_for(root, "stairs_layer_trigger").is_empty(), "%s exposes stairs_layer_trigger behavior hint" % prefab_name)
		var behaviour_node: Node = root.find_child("Stairs Layer Trigger", true, false)
		_assert_true(behaviour_node != null, "%s keeps trigger helper node" % prefab_name)
		if behaviour_node != null:
			_assert_true(behaviour_node.has_meta("unity_mono_behaviours"), "%s preserves deferred MonoBehaviour metadata" % prefab_name)
			_assert_true(not _behavior_hints_for(behaviour_node, "stairs_layer_trigger").is_empty(), "%s trigger node keeps local behavior hint" % prefab_name)
		_assert_true(_find_first_sprite(root) != null, "%s includes visible sprite content" % prefab_name)
		_assert_true(_count_collision_shapes(root) + _count_collision_polygons(root) > 0, "%s keeps imported collision nodes" % prefab_name)
		root.free()


func _validate_altar_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "props", "PF Props - Altar 01")
	if root == null:
		return
	var hints := _behavior_hints_for(root, "altar_trigger")
	_assert_true(not hints.is_empty(), "Altar prefab exposes altar_trigger behavior hint")
	if not hints.is_empty():
		var data: Dictionary = hints[0].get("data", {})
		_assert_true(Array(data.get("rune_node_paths", [])).size() >= 1, "Altar behavior hint preserves rune node paths")
	root.free()


func _validate_rune_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "props", "PF Props - Rune Pillar X2")
	if root == null:
		return
	_assert_true(not _behavior_hints_for(root, "sprite_color_animation").is_empty(), "Rune pillar exposes sprite_color_animation behavior hint")
	var glow := root.find_child("Glow", true, false)
	_assert_true(glow != null, "Rune pillar keeps Glow node")
	if glow != null:
		_assert_true(not _behavior_hints_for(glow, "sprite_color_animation").is_empty(), "Glow node keeps local sprite_color_animation hint")
	root.free()


func _validate_player_prefab(output_root: String) -> void:
	var root := _instantiate_prefab(output_root, "player", "PF Player")
	if root == null:
		return
	_assert_true(_find_first_sprite(root) != null, "Player prefab includes a Sprite2D descendant")
	_assert_true(not _behavior_hints_for(root, "top_down_character_controller").is_empty(), "Player prefab exposes top_down_character_controller behavior hint")
	root.free()


func _validate_report_files(output_root: String) -> void:
	var compatibility_report = _load_json_file(output_root.path_join("reports/compatibility_report.json"))
	_assert_true(compatibility_report is Dictionary, "Compatibility report JSON loads")
	if compatibility_report is Dictionary:
		_assert_eq(int(compatibility_report.get("format_version", -1)), 4, "Compatibility report format_version")
		var summary: Dictionary = compatibility_report.get("summary", {})
		_assert_eq(int(summary.get("supported_static_prefabs", -1)), 57, "Compatibility report supported count")
		_assert_eq(int(summary.get("approximated_prefabs", -1)), 7, "Compatibility report approximated count")
		_assert_eq(int(summary.get("manual_behavior_prefabs", -1)), 14, "Compatibility report manual count")
		_assert_eq(int(summary.get("unresolved_or_skipped_prefabs", -1)), 0, "Compatibility report unresolved count")
		_assert_eq(int(summary.get("editor_only_prefabs", -1)), 3, "Compatibility report editor-only count")
		var stairs_entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), "PF Struct - Stairs S 01 L")
		_assert_true(not stairs_entry.is_empty(), "Compatibility report includes stairs entry")
		_assert_eq(str(stairs_entry.get("tier", "")), "manual_behavior", "Compatibility report stairs tier")
		_assert_true(Array(stairs_entry.get("reasons", [])).has("stairs_layer_trigger_hint"), "Compatibility report stairs reason")
		for prefab_name in [
			"PF Struct - Stairs E 01",
			"PF Struct - Stairs E 02",
			"PF Struct - Stairs W 01",
			"PF Struct - Stairs W 02",
		]:
			var ew_entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), prefab_name)
			_assert_true(not ew_entry.is_empty(), "Compatibility report includes east/west stairs entry: %s" % prefab_name)
			_assert_eq(str(ew_entry.get("tier", "")), "manual_behavior", "Compatibility report east/west stairs tier: %s" % prefab_name)
			var ew_reasons := Array(ew_entry.get("reasons", []))
			_assert_true(ew_reasons.has("stairs_layer_trigger_hint"), "Compatibility report east/west stairs reason: %s" % prefab_name)
			_assert_true(not ew_reasons.has("unresolved_sprite_reference"), "Compatibility report omits unresolved sprite reason for repaired stairs: %s" % prefab_name)
			_assert_true(ew_entry.get("scene_path", null) != null, "Compatibility report records scene path for repaired stairs: %s" % prefab_name)
		for prefab_name in [
			"PF Props - Statue 01",
			"PF Props - Stone 06",
			"PF Props - Stone 07",
			"PF Props - Well 01",
			"PF Props - Wooden Gate 01 Opened",
			"PF Struct - Gate 02",
		]:
			var entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), prefab_name)
			_assert_true(not entry.is_empty(), "Compatibility report includes supported polygon sample: %s" % prefab_name)
			_assert_eq(str(entry.get("tier", "")), "supported_static", "Compatibility report supported polygon tier: %s" % prefab_name)
			_assert_true(Array(entry.get("reasons", [])).has("polygon_collider_imported"), "Compatibility report polygon import reason: %s" % prefab_name)
		for prefab_name in [
			"PF Props - Barrel 01",
			"PF Props - Pot 01",
			"PF Props - Pot 02",
			"PF Props - Pot 03",
		]:
			var entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), prefab_name)
			_assert_true(not entry.is_empty(), "Compatibility report includes polygon+rigidbody sample: %s" % prefab_name)
			_assert_eq(str(entry.get("tier", "")), "approximated", "Compatibility report polygon+rigidbody tier: %s" % prefab_name)
			_assert_true(Array(entry.get("reasons", [])).has("polygon_collider_imported"), "Compatibility report polygon+rigidbody import reason: %s" % prefab_name)
			_assert_true(Array(entry.get("reasons", [])).has("rigidbody_deferred"), "Compatibility report polygon+rigidbody rigidbody reason: %s" % prefab_name)
		for prefab_name in [
			"PF Props - Crate 01",
			"PF Props - Crate 02",
			"PF Props - Stone Cube 01",
		]:
			var entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), prefab_name)
			_assert_true(not entry.is_empty(), "Compatibility report includes rigidbody-only approximation sample: %s" % prefab_name)
			_assert_eq(str(entry.get("tier", "")), "approximated", "Compatibility report rigidbody-only tier: %s" % prefab_name)
			_assert_true(Array(entry.get("reasons", [])).has("rigidbody_deferred"), "Compatibility report rigidbody-only reason: %s" % prefab_name)
			_assert_true(not Array(entry.get("reasons", [])).has("polygon_collider_imported"), "Compatibility report omits polygon import reason for rigidbody-only sample: %s" % prefab_name)
		var unresolved_entries: Array = compatibility_report.get("tiers", {}).get("unresolved_or_skipped", [])
		_assert_eq(unresolved_entries.size(), 0, "Compatibility report unresolved tier is empty")
		var editor_only_prefabs: Array = compatibility_report.get("editor_only_prefabs", [])
		_assert_true(not _find_catalog_prefab_entry(editor_only_prefabs, "TP Grass").is_empty(), "Compatibility report includes TP Grass as editor-only")
		_assert_true(_find_tier_prefab_entry(compatibility_report.get("tiers", {}), "TP Grass").is_empty(), "Editor-only tile palette is excluded from semantic tiers")

	var asset_catalog = _load_json_file(output_root.path_join("reports/asset_catalog.json"))
	_assert_true(asset_catalog is Dictionary, "Asset catalog JSON loads")
	if asset_catalog is Dictionary:
		_assert_eq(int(asset_catalog.get("format_version", -1)), 4, "Asset catalog format_version")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Plant - Bush 01").is_empty(), "Asset catalog includes Bush prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Stone Lantern 01").is_empty(), "Asset catalog includes Stone Lantern prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Well 01").is_empty(), "Asset catalog includes Well prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Gate 02").is_empty(), "Asset catalog includes Gate 02 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Stairs S 01 L").is_empty(), "Asset catalog includes Stairs prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Stairs E 01").is_empty(), "Asset catalog includes Stairs E 01 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Stairs E 02").is_empty(), "Asset catalog includes Stairs E 02 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Stairs W 01").is_empty(), "Asset catalog includes Stairs W 01 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Struct - Stairs W 02").is_empty(), "Asset catalog includes Stairs W 02 prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Altar 01").is_empty(), "Asset catalog includes Altar prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Props - Rune Pillar X2").is_empty(), "Asset catalog includes Rune Pillar prefab")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "PF Player").is_empty(), "Asset catalog includes Player prefab")
		_assert_true(_find_catalog_prefab_entry(asset_catalog.get("prefabs", []), "TP Grass").is_empty(), "Asset catalog omits editor-only tile palette prefab")


func _instantiate_prefab(output_root: String, family: String, prefab_name: String) -> Node:
	var scene_path := output_root.path_join("scenes/prefabs/%s/%s.tscn" % [family, _sanitize_filename(prefab_name)])
	var packed := load(scene_path)
	_assert_true(packed is PackedScene, "Prefab scene loads: %s" % scene_path)
	if not (packed is PackedScene):
		return null
	var instance: Node = packed.instantiate()
	_assert_true(instance != null, "Prefab scene instantiates: %s" % scene_path)
	return instance


func _first_collision_shape(node: Node) -> CollisionShape2D:
	for child in node.get_children():
		if child is CollisionShape2D:
			return child
	return null


func _count_collision_shapes(node: Node) -> int:
	var count := 0
	if node is CollisionShape2D:
		count += 1
	for child in node.get_children():
		count += _count_collision_shapes(child)
	return count


func _count_collision_polygons(node: Node) -> int:
	var count := 0
	if node is CollisionPolygon2D:
		count += 1
	for child in node.get_children():
		count += _count_collision_polygons(child)
	return count


func _find_first_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node
	for child in node.get_children():
		var sprite := _find_first_sprite(child)
		if sprite != null:
			return sprite
	return null


func _find_first_node_with_meta(node: Node, meta_key: String) -> Node:
	if node.has_meta(meta_key):
		return node
	for child in node.get_children():
		var found := _find_first_node_with_meta(child, meta_key)
		if found != null:
			return found
	return null


func _behavior_hints_for(node: Node, expected_kind: String) -> Array:
	if not node.has_meta("cainos_behavior_hints"):
		return []
	var hints: Variant = node.get_meta("cainos_behavior_hints")
	if not (hints is Array):
		return []
	var matches := []
	for hint_variant in hints:
		var hint: Dictionary = hint_variant
		if str(hint.get("kind", "")) == expected_kind:
			matches.append(hint)
	return matches


func _find_tier_prefab_entry(tiers: Dictionary, prefab_name: String) -> Dictionary:
	for tier_entries_variant in tiers.values():
		for entry_variant in tier_entries_variant:
			var entry: Dictionary = entry_variant
			if str(entry.get("prefab_name", "")) == prefab_name:
				return entry
	return {}


func _find_catalog_prefab_entry(entries: Array, prefab_name: String) -> Dictionary:
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if str(entry.get("prefab_name", "")) == prefab_name:
			return entry
	return {}


func _count_tile_map_layers(node: Node) -> int:
	var count := 0
	if node is TileMapLayer:
		count += 1
	for child in node.get_children():
		count += _count_tile_map_layers(child)
	return count


func _sanitize_filename(value: String) -> String:
	return value.replace("/", "-").replace("\\", "-").replace(":", "").replace("*", "").replace("?", "").replace("\"", "").replace("<", "").replace(">", "").replace("|", "")


func _load_json_file(res_path: String):
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(abs_path))


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_fail(message)


func _assert_eq(actual, expected, message: String) -> void:
	if actual == expected:
		print("PASS: %s" % message)
	else:
		_fail("%s (expected=%s actual=%s)" % [message, str(expected), str(actual)])


func _fail(message: String) -> void:
	push_error(message)
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All real-pack validation checks passed.")
		quit(0)
	else:
		print("Validation failures: %d" % _failures.size())
		for failure in _failures:
			print(" - %s" % failure)
		quit(1)
