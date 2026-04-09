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
	if FileAccess.file_exists(import_manifest_abs):
		var import_manifest = JSON.parse_string(FileAccess.get_file_as_string(import_manifest_abs))
		_assert_true(import_manifest is Dictionary, "Import manifest parses as JSON")
		if import_manifest is Dictionary:
			var source: Dictionary = import_manifest.get("source", {})
			_assert_true(not source.has("source_path"), "Persisted manifest omits absolute source_path")
			_assert_eq(source.get("kind", ""), "unitypackage", "Persisted manifest source kind")
			_assert_eq(source.get("semantic_source_kind", ""), "unitypackage_file", "Persisted manifest semantic source kind")
			var semantic_summary: Dictionary = import_manifest.get("semantic_summary", {})
			_assert_eq(int(semantic_summary.get("supported_static", -1)), int(expected.get("supported_static_prefabs", -2)), "Manifest supported_static count")
			_assert_eq(int(semantic_summary.get("approximated", -1)), int(expected.get("approximated_prefabs", -2)), "Manifest approximated count")
			_assert_eq(int(semantic_summary.get("manual_behavior", -1)), int(expected.get("manual_behavior_prefabs", -2)), "Manifest manual_behavior count")
			_assert_eq(int(semantic_summary.get("unresolved_or_skipped", -1)), int(expected.get("unresolved_or_skipped_prefabs", -2)), "Manifest unresolved count")

	var sample_prefabs: Dictionary = expected.get("sample_prefabs", {})
	_assert_generated_scene(output_root, "plants", str(sample_prefabs.get("bush", "")))
	_assert_generated_scene(output_root, "props", str(sample_prefabs.get("lantern", "")))
	_assert_generated_scene(output_root, "struct", str(sample_prefabs.get("stairs", "")))
	_assert_generated_scene(output_root, "struct", str(sample_prefabs.get("edge", "")))
	_assert_generated_scene(output_root, "props", str(sample_prefabs.get("polygon", "")))
	_assert_generated_scene(output_root, "player", str(sample_prefabs.get("player", "")))
	var broken_scene := output_root.path_join("scenes/prefabs/props/%s.tscn" % _sanitize_filename(str(sample_prefabs.get("broken", ""))))
	_assert_true(not FileAccess.file_exists(ProjectSettings.globalize_path(broken_scene)), "Unresolved prefab does not generate a scene")

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


func _assert_generated_scene(output_root: String, family: String, prefab_name: String) -> void:
	var scene_path := output_root.path_join("scenes/prefabs/%s/%s.tscn" % [family, _sanitize_filename(prefab_name)])
	_assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(scene_path)), "Generated scene exists: %s" % scene_path)


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
