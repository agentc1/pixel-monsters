extends SceneTree

const BasicPackImporter := preload("res://addons/cainos_basic_importer/basic_pack_importer.gd")


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var mode := str(args.get("mode", "scan"))
	var source := str(args.get("source", ""))
	if source.is_empty():
		push_error("Missing required --source argument.")
		quit(1)
		return

	var importer := BasicPackImporter.new(null, Callable(self, "_log"))
	var result: Dictionary
	if mode == "scan":
		result = importer.scan_source(source, args.get("profile", {}))
	else:
		result = await importer.import_source(source, args.get("profile", {}))

	print(JSON.stringify(_sanitize_result_for_output(result), "\t", true))
	quit(0 if result.get("ok", false) else 1)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {
		"mode": "scan",
		"profile": {},
	}
	var index := 0
	while index < args.size():
		var token := args[index]
		match token:
			"--mode":
				if index + 1 < args.size():
					parsed["mode"] = args[index + 1]
					index += 1
			"--source":
				if index + 1 < args.size():
					parsed["source"] = args[index + 1]
					index += 1
			"--output-root":
				if index + 1 < args.size():
					var profile: Dictionary = parsed.get("profile", {})
					profile["output_root"] = args[index + 1]
					parsed["profile"] = profile
					index += 1
			"--no-semantic-prefabs":
				var profile_semantic: Dictionary = parsed.get("profile", {})
				profile_semantic["prefer_semantic_prefabs"] = false
				parsed["profile"] = profile_semantic
			"--fallback-atlas-scenes":
				var profile_fallback: Dictionary = parsed.get("profile", {})
				profile_fallback["generate_fallback_atlas_scenes"] = true
				parsed["profile"] = profile_fallback
			"--shadow-helpers":
				var profile_shadow: Dictionary = parsed.get("profile", {})
				profile_shadow["generate_baked_shadow_helpers"] = true
				parsed["profile"] = profile_shadow
			"--no-preview":
				var profile_preview: Dictionary = parsed.get("profile", {})
				profile_preview["generate_preview_scene"] = false
				parsed["profile"] = profile_preview
			"--no-player":
				var profile_player: Dictionary = parsed.get("profile", {})
				profile_player["generate_player_helpers"] = false
				parsed["profile"] = profile_player
		index += 1
	return parsed


func _log(message: String) -> void:
	print(message)


func _sanitize_result_for_output(result: Dictionary) -> Dictionary:
	var sanitized := result.duplicate(true)
	if sanitized.has("semantic_registry"):
		var semantic_registry: Dictionary = sanitized.get("semantic_registry", {})
		sanitized["semantic_registry"] = {
			"ok": semantic_registry.get("ok", false),
			"source_kind": semantic_registry.get("source_kind", ""),
			"source_label": semantic_registry.get("source_label", ""),
			"summary": semantic_registry.get("summary", {}),
			"prefab_count": len(semantic_registry.get("prefabs", [])),
			"sprite_count": semantic_registry.get("sprites", {}).size(),
			"texture_count": semantic_registry.get("textures_by_guid", {}).size(),
		}
	if sanitized.has("source"):
		var source: Dictionary = sanitized.get("source", {}).duplicate(true)
		source.erase("source_path")
		source.erase("resolved_paths")
		if source.has("semantic_source"):
			var semantic_source: Dictionary = source.get("semantic_source", {}).duplicate(true)
			semantic_source.erase("path")
			semantic_source.erase("root")
			semantic_source.erase("zip_path")
			source["semantic_source"] = semantic_source
		sanitized["source"] = source
	return sanitized
