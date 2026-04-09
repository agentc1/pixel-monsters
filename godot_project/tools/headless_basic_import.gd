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

	print(JSON.stringify(result, "\t", true))
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
			"--no-plain-scenes":
				var profile_plain: Dictionary = parsed.get("profile", {})
				profile_plain["generate_plain_scenes"] = false
				parsed["profile"] = profile_plain
			"--no-shadow-scenes":
				var profile_shadow: Dictionary = parsed.get("profile", {})
				profile_shadow["generate_shadow_scenes"] = false
				parsed["profile"] = profile_shadow
			"--no-preview":
				var profile_preview: Dictionary = parsed.get("profile", {})
				profile_preview["generate_preview_scene"] = false
				parsed["profile"] = profile_preview
			"--no-player":
				var profile_player: Dictionary = parsed.get("profile", {})
				profile_player["generate_player_assets"] = false
				parsed["profile"] = profile_player
		index += 1
	return parsed


func _log(message: String) -> void:
	print(message)
