extends SceneTree

const BasicPackImporter := preload("res://addons/cainos_basic_importer/basic_pack_importer.gd")

var _failures: Array[String] = []


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var fixture_root := str(args.get("fixture_root", ""))
	var output_root := str(args.get("output_root", "res://cainos_imports/basic_regression"))
	if fixture_root.is_empty():
		_fail("Missing --fixture-root")
		_finish()
		return

	var manifest_path := fixture_root.path_join("fixture_manifest.json")
	if not FileAccess.file_exists(manifest_path):
		_fail("Fixture manifest missing: %s" % manifest_path)
		_finish()
		return

	var fixture_manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (fixture_manifest is Dictionary):
		_fail("Fixture manifest is invalid JSON: %s" % manifest_path)
		_finish()
		return

	var expected: Dictionary = fixture_manifest.get("expected", {})
	var importer := BasicPackImporter.new(null, Callable(self, "_log"))

	var package_scan := importer.scan_source(str(fixture_manifest.get("package_path", "")), {})
	_assert_true(package_scan.get("ok", false), "Direct .unitypackage scan succeeds")
	_assert_eq(package_scan.get("source", {}).get("source_kind", ""), "unitypackage", "Direct scan source kind")
	_assert_eq(package_scan.get("source", {}).get("semantic_source", {}).get("kind", ""), "unitypackage_file", "Direct scan semantic source kind")
	_assert_summary_counts(package_scan, expected, "direct package scan")

	var folder_scan_a := importer.scan_source(str(fixture_manifest.get("extracted_a", "")), {})
	var folder_scan_b := importer.scan_source(str(fixture_manifest.get("extracted_b", "")), {})
	_assert_true(folder_scan_a.get("ok", false), "Extracted metadata scan A succeeds")
	_assert_true(folder_scan_b.get("ok", false), "Extracted metadata scan B succeeds")
	_assert_eq(folder_scan_a.get("source", {}).get("semantic_source", {}).get("kind", ""), "extracted_metadata", "Extracted scan semantic source kind")
	_assert_eq(folder_scan_a.get("source", {}).get("source_hash", ""), folder_scan_b.get("source", {}).get("source_hash", ""), "Folder source hash is path-independent")
	_assert_summary_counts(folder_scan_a, expected, "extracted metadata scan")

	var import_profile := {
		"output_root": output_root,
		"prefer_semantic_prefabs": true,
		"generate_fallback_atlas_scenes": false,
		"generate_baked_shadow_helpers": false,
		"generate_preview_scene": true,
		"generate_player_helpers": true,
	}
	var import_result := await importer.import_source(str(fixture_manifest.get("package_path", "")), import_profile)
	_assert_true(import_result.get("ok", false), "Direct .unitypackage import succeeds")

	var import_manifest_res := output_root.path_join("reports/import_manifest.json")
	var import_manifest_abs := ProjectSettings.globalize_path(import_manifest_res)
	_assert_true(FileAccess.file_exists(import_manifest_abs), "Import manifest written")
	var semantic_prefabs: Array = []
	var sample_prefabs: Dictionary = expected.get("sample_prefabs", {})
	if FileAccess.file_exists(import_manifest_abs):
		var import_manifest = JSON.parse_string(FileAccess.get_file_as_string(import_manifest_abs))
		_assert_true(import_manifest is Dictionary, "Import manifest parses as JSON")
		if import_manifest is Dictionary:
			_assert_eq(int(import_manifest.get("format_version", -1)), 3, "Manifest format_version")
			var source: Dictionary = import_manifest.get("source", {})
			_assert_true(not source.has("source_path"), "Persisted manifest omits absolute source_path")
			_assert_eq(source.get("kind", ""), "unitypackage", "Persisted manifest source kind")
			_assert_eq(source.get("semantic_source_kind", ""), "unitypackage_file", "Persisted manifest semantic source kind")
			var semantic_summary: Dictionary = import_manifest.get("semantic_summary", {})
			_assert_eq(int(semantic_summary.get("supported_static", -1)), int(expected.get("supported_static_prefabs", -2)), "Manifest supported_static count")
			_assert_eq(int(semantic_summary.get("approximated", -1)), int(expected.get("approximated_prefabs", -2)), "Manifest approximated count")
			_assert_eq(int(semantic_summary.get("manual_behavior", -1)), int(expected.get("manual_behavior_prefabs", -2)), "Manifest manual_behavior count")
			_assert_eq(int(semantic_summary.get("unresolved_or_skipped", -1)), int(expected.get("unresolved_or_skipped_prefabs", -2)), "Manifest unresolved count")
			_assert_eq(int(import_manifest.get("inventory", {}).get("editor_only_prefabs", -1)), int(expected.get("editor_only_prefabs", -2)), "Manifest editor-only prefab count")
			semantic_prefabs = import_manifest.get("semantic_prefabs", [])
			_assert_eq(semantic_prefabs.size(), int(expected.get("prefab_count", -1)), "Manifest semantic_prefabs count")
			var editor_only_prefabs: Array = import_manifest.get("editor_only_prefabs", [])
			_assert_eq(editor_only_prefabs.size(), int(expected.get("editor_only_prefabs", -1)), "Manifest editor_only_prefabs count")
			_assert_prefab_report_entry(editor_only_prefabs, str(sample_prefabs.get("editor_only", "")), "editor_only", "editor_only_unity_asset", false)

	_assert_generated_scene(output_root, "plants", str(sample_prefabs.get("bush", "")))
	_assert_generated_scene(output_root, "props", str(sample_prefabs.get("lantern", "")))
	_assert_generated_scene(output_root, "struct", str(sample_prefabs.get("stairs", "")))
	_assert_generated_scene(output_root, "props", str(sample_prefabs.get("altar", "")))
	_assert_generated_scene(output_root, "props", str(sample_prefabs.get("rune", "")))
	_assert_generated_scene(output_root, "struct", str(sample_prefabs.get("edge", "")))
	_assert_generated_scene(output_root, "struct", str(sample_prefabs.get("complex_edge", "")))
	_assert_generated_scene(output_root, "props", str(sample_prefabs.get("polygon", "")))
	_assert_generated_scene(output_root, "player", str(sample_prefabs.get("player", "")))
	var broken_scene := output_root.path_join("scenes/prefabs/props/%s.tscn" % _sanitize_filename(str(sample_prefabs.get("broken", ""))))
	_assert_true(not FileAccess.file_exists(ProjectSettings.globalize_path(broken_scene)), "Unresolved prefab does not generate a scene")

	_assert_prefab_report_entry(semantic_prefabs, str(sample_prefabs.get("stairs", "")), "manual_behavior", "stairs_layer_trigger_hint", true)
	_assert_prefab_report_entry(semantic_prefabs, str(sample_prefabs.get("altar", "")), "manual_behavior", "altar_trigger_hint", true)
	_assert_prefab_report_entry(semantic_prefabs, str(sample_prefabs.get("rune", "")), "manual_behavior", "sprite_color_animation_hint", true)
	_assert_prefab_report_entry(semantic_prefabs, str(sample_prefabs.get("player", "")), "manual_behavior", "top_down_character_controller_hint", true)
	_assert_prefab_report_entry(semantic_prefabs, str(sample_prefabs.get("broken", "")), "unresolved_or_skipped", "unresolved_sprite_reference", false)
	_assert_prefab_report_entry(semantic_prefabs, str(sample_prefabs.get("complex_edge", "")), "approximated", "edge_collider_deferred_complex", true)
	var stairs_hint := _assert_behavior_hint_entry(semantic_prefabs, str(sample_prefabs.get("stairs", "")), "stairs_layer_trigger")
	if not stairs_hint.is_empty():
		var stairs_data: Dictionary = stairs_hint.get("data", {})
		_assert_eq(str(stairs_data.get("direction", "")), "south", "Stairs hint direction")
		_assert_eq(str(stairs_data.get("upper_layer", "")), "Layer 2", "Stairs hint upper layer")
		_assert_eq(str(stairs_data.get("lower_layer", "")), "Layer 1", "Stairs hint lower layer")
	var altar_hint := _assert_behavior_hint_entry(semantic_prefabs, str(sample_prefabs.get("altar", "")), "altar_trigger")
	if not altar_hint.is_empty():
		var altar_data: Dictionary = altar_hint.get("data", {})
		_assert_eq(int(altar_data.get("rune_node_paths", []).size()), 2, "Altar hint rune node paths")
		_assert_eq(float(altar_data.get("lerp_speed", -1.0)), 3.0, "Altar hint lerp speed")
	var rune_hint := _assert_behavior_hint_entry(semantic_prefabs, str(sample_prefabs.get("rune", "")), "sprite_color_animation")
	if not rune_hint.is_empty():
		var rune_data: Dictionary = rune_hint.get("data", {})
		_assert_eq(float(rune_data.get("duration_seconds", -1.0)), 2.0, "Rune hint duration")
		_assert_true(Array(rune_data.get("color_keys", [])).size() >= 2, "Rune hint color keys")
		_assert_true(Array(rune_data.get("alpha_keys", [])).size() >= 3, "Rune hint alpha keys")
	var player_hint := _assert_behavior_hint_entry(semantic_prefabs, str(sample_prefabs.get("player", "")), "top_down_character_controller")
	if not player_hint.is_empty():
		var player_data: Dictionary = player_hint.get("data", {})
		_assert_eq(float(player_data.get("speed", -1.0)), 3.0, "Player hint speed")
		_assert_eq(str(player_data.get("input_scheme", "")), "wasd_4dir", "Player hint input scheme")
		_assert_eq(str(player_data.get("direction_parameter", "")), "Direction", "Player hint direction parameter")
		_assert_true(bool(player_data.get("requires_animator", false)), "Player hint requires animator")
		_assert_true(bool(player_data.get("requires_rigidbody2d", false)), "Player hint requires rigidbody2d")

	var compatibility_report = _load_json_file(output_root.path_join("reports/compatibility_report.json"))
	_assert_true(compatibility_report is Dictionary, "Compatibility report parses as JSON")
	if compatibility_report is Dictionary:
		_assert_eq(int(compatibility_report.get("format_version", -1)), 3, "Compatibility report format_version")
		var stairs_entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), str(sample_prefabs.get("stairs", "")))
		_assert_true(not stairs_entry.is_empty(), "Compatibility report includes stairs prefab entry")
		_assert_eq(str(stairs_entry.get("tier", "")), "manual_behavior", "Compatibility report stairs tier")
		_assert_true(Array(stairs_entry.get("reasons", [])).has("stairs_layer_trigger_hint"), "Compatibility report stairs reason")
		var complex_edge_entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), str(sample_prefabs.get("complex_edge", "")))
		_assert_true(not complex_edge_entry.is_empty(), "Compatibility report includes complex-edge prefab entry")
		_assert_eq(str(complex_edge_entry.get("tier", "")), "approximated", "Compatibility report complex-edge tier")
		_assert_true(Array(complex_edge_entry.get("reasons", [])).has("edge_collider_deferred_complex"), "Compatibility report complex-edge reason")
		var broken_entry := _find_tier_prefab_entry(compatibility_report.get("tiers", {}), str(sample_prefabs.get("broken", "")))
		_assert_true(not broken_entry.is_empty(), "Compatibility report includes unresolved prefab entry")
		_assert_true(Array(broken_entry.get("reasons", [])).has("unresolved_sprite_reference"), "Compatibility report unresolved reason")
		var editor_only_entries: Array = compatibility_report.get("editor_only_prefabs", [])
		_assert_true(not _find_catalog_prefab_entry(editor_only_entries, str(sample_prefabs.get("editor_only", ""))).is_empty(), "Compatibility report includes editor-only prefab entry")
		_assert_true(_find_tier_prefab_entry(compatibility_report.get("tiers", {}), str(sample_prefabs.get("editor_only", ""))).is_empty(), "Editor-only prefab is excluded from semantic tiers")

	var asset_catalog = _load_json_file(output_root.path_join("reports/asset_catalog.json"))
	_assert_true(asset_catalog is Dictionary, "Asset catalog parses as JSON")
	if asset_catalog is Dictionary:
		_assert_eq(int(asset_catalog.get("format_version", -1)), 3, "Asset catalog format_version")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), str(sample_prefabs.get("bush", ""))).is_empty(), "Asset catalog includes bush prefab entry")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), str(sample_prefabs.get("stairs", ""))).is_empty(), "Asset catalog includes stairs prefab entry")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), str(sample_prefabs.get("altar", ""))).is_empty(), "Asset catalog includes altar prefab entry")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), str(sample_prefabs.get("rune", ""))).is_empty(), "Asset catalog includes rune prefab entry")
		_assert_true(not _find_catalog_prefab_entry(asset_catalog.get("prefabs", []), str(sample_prefabs.get("player", ""))).is_empty(), "Asset catalog includes player prefab entry")
		_assert_true(_find_catalog_prefab_entry(asset_catalog.get("prefabs", []), str(sample_prefabs.get("broken", ""))).is_empty(), "Asset catalog omits unresolved prefab entry")
		_assert_true(_find_catalog_prefab_entry(asset_catalog.get("prefabs", []), str(sample_prefabs.get("editor_only", ""))).is_empty(), "Asset catalog omits editor-only prefab entry")

	var fallback_output_root := "%s_fallback" % output_root
	var fallback_result := await importer.import_source(str(fixture_manifest.get("package_path", "")), {
		"output_root": fallback_output_root,
		"prefer_semantic_prefabs": false,
		"generate_fallback_atlas_scenes": true,
		"generate_baked_shadow_helpers": false,
		"generate_preview_scene": false,
		"generate_player_helpers": false,
	})
	_assert_true(fallback_result.get("ok", false), "Fallback-only import succeeds")
	var fallback_report = _load_json_file(fallback_output_root.path_join("reports/compatibility_report.json"))
	_assert_true(fallback_report is Dictionary, "Fallback compatibility report parses as JSON")
	if fallback_report is Dictionary:
		var fallback_summary: Dictionary = fallback_report.get("summary", {})
		_assert_true(not bool(fallback_summary.get("semantic_enabled", true)), "Fallback report records semantic import disabled")
		_assert_true(int(fallback_summary.get("fallback_collections", 0)) > 0, "Fallback report records fallback collections")
	var fallback_catalog = _load_json_file(fallback_output_root.path_join("reports/asset_catalog.json"))
	_assert_true(fallback_catalog is Dictionary, "Fallback asset catalog parses as JSON")
	if fallback_catalog is Dictionary:
		_assert_eq(Array(fallback_catalog.get("prefabs", [])).size(), 0, "Fallback asset catalog omits semantic prefab entries")
		_assert_true(Array(fallback_catalog.get("fallback_collections", [])).size() > 0, "Fallback asset catalog includes fallback collections")

	_finish()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	var index := 0
	while index < args.size():
		var token := args[index]
		match token:
			"--fixture-root":
				if index + 1 < args.size():
					parsed["fixture_root"] = args[index + 1]
					index += 1
			"--output-root":
				if index + 1 < args.size():
					parsed["output_root"] = args[index + 1]
					index += 1
		index += 1
	return parsed


func _assert_summary_counts(result: Dictionary, expected: Dictionary, label: String) -> void:
	var summary: Dictionary = result.get("summary", {})
	_assert_eq(int(summary.get("supported_static_prefabs", -1)), int(expected.get("supported_static_prefabs", -2)), "%s supported_static count" % label)
	_assert_eq(int(summary.get("approximated_prefabs", -1)), int(expected.get("approximated_prefabs", -2)), "%s approximated count" % label)
	_assert_eq(int(summary.get("manual_behavior_prefabs", -1)), int(expected.get("manual_behavior_prefabs", -2)), "%s manual_behavior count" % label)
	_assert_eq(int(summary.get("unresolved_or_skipped_prefabs", -1)), int(expected.get("unresolved_or_skipped_prefabs", -2)), "%s unresolved count" % label)
	_assert_eq(int(summary.get("editor_only_prefabs", -1)), int(expected.get("editor_only_prefabs", -2)), "%s editor-only count" % label)


func _assert_generated_scene(output_root: String, family: String, prefab_name: String) -> void:
	var scene_path := output_root.path_join("scenes/prefabs/%s/%s.tscn" % [family, _sanitize_filename(prefab_name)])
	_assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(scene_path)), "Generated scene exists: %s" % scene_path)


func _assert_prefab_report_entry(entries: Array, prefab_name: String, expected_tier: String, expected_reason: String, expect_scene_path: bool) -> void:
	var entry := _find_catalog_prefab_entry(entries, prefab_name)
	_assert_true(not entry.is_empty(), "Manifest semantic_prefabs includes %s" % prefab_name)
	if entry.is_empty():
		return
	_assert_eq(str(entry.get("tier", "")), expected_tier, "Manifest tier for %s" % prefab_name)
	_assert_true(Array(entry.get("reasons", [])).has(expected_reason), "Manifest reasons include %s for %s" % [expected_reason, prefab_name])
	var scene_path = entry.get("scene_path", null)
	if expect_scene_path:
		_assert_true(scene_path != null and not str(scene_path).is_empty(), "Manifest scene path recorded for %s" % prefab_name)
	else:
		_assert_true(scene_path == null, "Manifest scene path omitted for %s" % prefab_name)


func _assert_behavior_hint_entry(entries: Array, prefab_name: String, expected_kind: String) -> Dictionary:
	var entry := _find_catalog_prefab_entry(entries, prefab_name)
	_assert_true(not entry.is_empty(), "Manifest semantic_prefabs includes behavior hint source %s" % prefab_name)
	if entry.is_empty():
		return {}
	var behavior_hints: Array = entry.get("behavior_hints", [])
	_assert_true(not behavior_hints.is_empty(), "Behavior hints present for %s" % prefab_name)
	if behavior_hints.is_empty():
		return {}
	var found := false
	var found_hint := {}
	for hint_variant in behavior_hints:
		var hint: Dictionary = hint_variant
		if str(hint.get("kind", "")) == expected_kind:
			found = true
			found_hint = hint
			break
	_assert_true(found, "Behavior hint kind %s present for %s" % [expected_kind, prefab_name])
	return found_hint


func _load_json_file(res_path: String):
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(abs_path))


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


func _sanitize_filename(value: String) -> String:
	return value.replace("/", "-").replace("\\", "-").replace(":", "").replace("*", "").replace("?", "").replace("\"", "").replace("<", "").replace(">", "").replace("|", "")


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


func _log(message: String) -> void:
	print(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All regression pre-import checks passed.")
		quit(0)
	else:
		print("Regression failures: %d" % _failures.size())
		for failure in _failures:
			print(" - %s" % failure)
		quit(1)
