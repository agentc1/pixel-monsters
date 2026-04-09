@tool
extends VBoxContainer

const BasicPackImporter := preload("res://addons/cainos_basic_importer/basic_pack_importer.gd")

var _editor_interface
var _source_path_edit: LineEdit
var _output_root_edit: LineEdit
var _prefer_semantic_prefabs: CheckBox
var _generate_fallback_atlas_scenes: CheckBox
var _generate_baked_shadow_helpers: CheckBox
var _generate_preview_scene: CheckBox
var _generate_player_helpers: CheckBox
var _log_output: TextEdit
var _dir_dialog: FileDialog
var _file_dialog: FileDialog


func setup(editor_interface) -> void:
	_editor_interface = editor_interface
	if get_child_count() == 0:
		_build_ui()
	_suggest_default_source()
	_output_root_edit.text = BasicPackImporter.DEFAULT_OUTPUT_ROOT


func _build_ui() -> void:
	size_flags_vertical = SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Cainos Basic Importer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var description := RichTextLabel.new()
	description.fit_content = true
	description.scroll_active = false
	description.bbcode_enabled = true
	description.text = "Import the licensed [b]Pixel Art Top Down - Basic[/b] pack into paintable [b]TileSet[/b] resources and named Godot prefab scenes. The recommended source is the original [b].unitypackage[/b] or an extracted Unity project folder."
	add_child(description)

	var source_label := Label.new()
	source_label.text = "Source path"
	add_child(source_label)

	var source_row := HBoxContainer.new()
	add_child(source_row)

	_source_path_edit = LineEdit.new()
	_source_path_edit.placeholder_text = "/path/to/basic.unitypackage, extracted Unity project, or texture zip/folder"
	_source_path_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	source_row.add_child(_source_path_edit)

	var browse_folder := Button.new()
	browse_folder.text = "Browse Folder"
	browse_folder.pressed.connect(_on_browse_folder_pressed)
	source_row.add_child(browse_folder)

	var browse_file := Button.new()
	browse_file.text = "Browse File"
	browse_file.pressed.connect(_on_browse_file_pressed)
	source_row.add_child(browse_file)

	var output_label := Label.new()
	output_label.text = "Generated output root"
	add_child(output_label)

	_output_root_edit = LineEdit.new()
	add_child(_output_root_edit)

	_prefer_semantic_prefabs = CheckBox.new()
	_prefer_semantic_prefabs.text = "Prefer named semantic prefab scenes"
	_prefer_semantic_prefabs.button_pressed = true
	add_child(_prefer_semantic_prefabs)

	_generate_fallback_atlas_scenes = CheckBox.new()
	_generate_fallback_atlas_scenes.text = "Generate fallback atlas-cell scenes"
	_generate_fallback_atlas_scenes.button_pressed = false
	add_child(_generate_fallback_atlas_scenes)

	_generate_baked_shadow_helpers = CheckBox.new()
	_generate_baked_shadow_helpers.text = "Generate baked-shadow fallback helpers"
	_generate_baked_shadow_helpers.button_pressed = false
	add_child(_generate_baked_shadow_helpers)

	_generate_preview_scene = CheckBox.new()
	_generate_preview_scene.text = "Generate helper preview scenes"
	_generate_preview_scene.button_pressed = true
	add_child(_generate_preview_scene)

	_generate_player_helpers = CheckBox.new()
	_generate_player_helpers.text = "Generate player helper assets"
	_generate_player_helpers.button_pressed = true
	add_child(_generate_player_helpers)

	var actions := HBoxContainer.new()
	add_child(actions)

	var scan_button := Button.new()
	scan_button.text = "Scan Only"
	scan_button.pressed.connect(_on_scan_pressed)
	actions.add_child(scan_button)

	var import_button := Button.new()
	import_button.text = "Import"
	import_button.pressed.connect(_on_import_pressed)
	actions.add_child(import_button)

	var open_output_button := Button.new()
	open_output_button.text = "Open Output Folder"
	open_output_button.pressed.connect(_on_open_output_pressed)
	actions.add_child(open_output_button)

	var notes := RichTextLabel.new()
	notes.fit_content = true
	notes.scroll_active = false
	notes.bbcode_enabled = true
	notes.text = "Beginner workflow after import: [b]Add Child Node -> TileMapLayer[/b], assign a generated TileSet, then place named prefab scenes from [b]res://cainos_imports/basic/scenes/prefabs/[/b]. Atlas fallback scenes are optional."
	add_child(notes)

	_log_output = TextEdit.new()
	_log_output.editable = false
	_log_output.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_log_output)

	_dir_dialog = FileDialog.new()
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.dir_selected.connect(_on_dir_selected)
	add_child(_dir_dialog)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.unitypackage ; Unity package", "*.zip ; Zip archive"])
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)


func _suggest_default_source() -> void:
	var project_dir := ProjectSettings.globalize_path("res://")
	var repo_root := project_dir.get_base_dir()
	var local_pack := repo_root.path_join("local_inputs/basic_pack")
	if DirAccess.dir_exists_absolute(local_pack):
		_source_path_edit.text = local_pack


func _profile() -> Dictionary:
	return {
		"output_root": _output_root_edit.text.strip_edges(),
		"prefer_semantic_prefabs": _prefer_semantic_prefabs.button_pressed,
		"generate_fallback_atlas_scenes": _generate_fallback_atlas_scenes.button_pressed,
		"generate_baked_shadow_helpers": _generate_baked_shadow_helpers.button_pressed,
		"generate_preview_scene": _generate_preview_scene.button_pressed,
		"generate_player_helpers": _generate_player_helpers.button_pressed,
	}


func _append_log(message: String) -> void:
	if _log_output.text.length() > 0:
		_log_output.text += "\n"
	_log_output.text += message
	_log_output.scroll_vertical = _log_output.get_line_count()


func _on_browse_folder_pressed() -> void:
	_dir_dialog.popup_centered_ratio(0.7)


func _on_browse_file_pressed() -> void:
	_file_dialog.popup_centered_ratio(0.7)


func _on_dir_selected(path: String) -> void:
	_source_path_edit.text = path


func _on_file_selected(path: String) -> void:
	_source_path_edit.text = path


func _on_scan_pressed() -> void:
	_run("scan")


func _on_import_pressed() -> void:
	_run("import")


func _on_open_output_pressed() -> void:
	var output_root := _output_root_edit.text.strip_edges()
	if output_root.is_empty():
		_append_log("Output root is empty.")
		return
	OS.shell_open(ProjectSettings.globalize_path(output_root))


func _run(mode: String) -> void:
	var source_path := _source_path_edit.text.strip_edges()
	if source_path.is_empty():
		_append_log("Choose a source folder or file first.")
		return

	_append_log("--- %s started ---" % mode.capitalize())
	var importer := BasicPackImporter.new(_editor_interface, Callable(self, "_append_log"))
	var result: Dictionary
	if mode == "scan":
		result = importer.scan_source(source_path, _profile())
	else:
		result = await importer.import_source(source_path, _profile())

	if not result.get("ok", false):
		_append_log("Failed: %s" % str(result.get("error", "Unknown error")))
		return

	var summary := result.get("summary", {})
	if summary is Dictionary:
		for key in summary.keys():
			_append_log("%s: %s" % [str(key), str(summary[key])])

	var manifest_path := str(result.get("manifest_path", ""))
	if not manifest_path.is_empty():
		_append_log("Manifest: %s" % manifest_path)
	var report_path := str(result.get("report_path", ""))
	if not report_path.is_empty():
		_append_log("Report: %s" % report_path)
	var catalog_path := str(result.get("catalog_path", ""))
	if not catalog_path.is_empty():
		_append_log("Catalog: %s" % catalog_path)
	_append_log("--- %s complete ---" % mode.capitalize())
