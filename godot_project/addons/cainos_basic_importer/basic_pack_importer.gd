@tool
extends RefCounted

const PACK_ID := "basic"
const IMPORTER_ID := "cainos_basic_importer"
const IMPORTER_VERSION := "0.1.0"
const DEFAULT_OUTPUT_ROOT := "res://cainos_imports/basic"
const TILE_SIZE := Vector2i(32, 32)
const DEFAULT_GENERATION_PROFILE := {
	"output_root": DEFAULT_OUTPUT_ROOT,
	"generate_plain_scenes": true,
	"generate_shadow_scenes": true,
	"generate_preview_scene": true,
	"generate_player_assets": true,
}

const REQUIRED_SOURCE_FILES := {
	"tileset_grass": "Texture/TX Tileset Grass.png",
	"tileset_stone_ground": "Texture/TX Tileset Stone Ground.png",
	"tileset_wall": "Texture/TX Tileset Wall.png",
	"struct": "Texture/TX Struct.png",
	"props": "Texture/TX Props.png",
	"plants": "Texture/TX Plant.png",
	"player": "Texture/TX Player.png",
	"shadow_props": "Texture/TX Shadow.png",
	"shadow_plants": "Texture/TX Shadow Plant.png",
}

const OPTIONAL_SOURCE_FILES := {
	"extra_props_shadow": "Texture/Extra/TX Props with Shadow.png",
	"extra_plants_shadow": "Texture/Extra/TX Plant with Shadow.png",
	"scene_overview_a": "Scene Overview.png",
	"scene_overview_b": "scene-overview.png",
	"unitypackage_a": "Pixel Art Top Down - Basic v1.2.3.unitypackage",
	"unitypackage_b": "pixel-art-top-down-basic-v1.2.3.unitypackage",
}

const TILESET_SPECS := [
	{"key": "tileset_grass", "name": "grass", "output": "tilesets/basic_grass_tileset.tres"},
	{"key": "tileset_stone_ground", "name": "stone_ground", "output": "tilesets/basic_stone_ground_tileset.tres"},
	{"key": "tileset_wall", "name": "wall", "output": "tilesets/basic_wall_tileset.tres"},
	{"key": "struct", "name": "struct", "output": "tilesets/basic_struct_tileset.tres"},
]

var _editor_interface: EditorInterface
var _log: Callable
var _active_output_root := DEFAULT_OUTPUT_ROOT


func _init(editor_interface: EditorInterface = null, logger: Callable = Callable()) -> void:
	_editor_interface = editor_interface
	_log = logger


func scan_source(source_path: String, profile: Dictionary = {}) -> Dictionary:
	var normalized_profile := _normalize_profile(profile)
	var probe := _probe_source(source_path)
	if not probe.get("ok", false):
		return probe

	var inventory := _build_inventory(probe)
	var compatibility := _build_compatibility(inventory)
	var summary := {
		"pack_id": PACK_ID,
		"source_kind": probe.get("source_kind", "unknown"),
		"tileset_atlases": inventory.get("tileset_atlases", 0),
		"tileset_tiles": inventory.get("tileset_tiles", 0),
		"plain_prop_scenes": inventory.get("plain_prop_cells", 0),
		"plain_plant_scenes": inventory.get("plain_plant_cells", 0),
		"shadow_prop_scenes": inventory.get("shadow_prop_cells", 0),
		"shadow_plant_scenes": inventory.get("shadow_plant_cells", 0),
		"player_cells": inventory.get("player_cells", 0),
	}
	return {
		"ok": true,
		"mode": "scan",
		"pack_id": PACK_ID,
		"profile": normalized_profile,
		"source": probe,
		"inventory": inventory,
		"compatibility": compatibility,
		"summary": summary,
	}


func import_source(source_path: String, profile: Dictionary = {}) -> Dictionary:
	var scan := scan_source(source_path, profile)
	if not scan.get("ok", false):
		return scan

	var normalized_profile := scan.get("profile", {})
	var output_root := str(normalized_profile.get("output_root", DEFAULT_OUTPUT_ROOT))
	_active_output_root = output_root
	var output_root_abs := ProjectSettings.globalize_path(output_root)
	var source_info: Dictionary = scan.get("source", {})
	var inventory: Dictionary = scan.get("inventory", {})
	var compatibility: Array = scan.get("compatibility", [])

	_log_message("Preparing output root: %s" % output_root)
	_remove_tree_absolute(output_root_abs)
	_ensure_dir(output_root_abs)

	var copied_sources := _copy_selected_sources(source_info, output_root)
	if not copied_sources.get("ok", false):
		return copied_sources

	var copied_res_paths: Dictionary = copied_sources.get("copied", {})
	await _wait_for_import(copied_res_paths.values())

	var outputs: Array[String] = []
	var catalog := {
		"pack_id": PACK_ID,
		"tilesets": [],
		"scene_collections": [],
		"helper_scenes": [],
	}

	for spec_variant in TILESET_SPECS:
		var spec: Dictionary = spec_variant
		var tileset_result := _generate_tileset(spec, copied_res_paths)
		if not tileset_result.get("ok", false):
			return tileset_result
		outputs.append(tileset_result.get("path", ""))
		catalog["tilesets"].append(tileset_result.get("catalog_entry", {}))

	var generated_scenes := {
		"plain_props": [],
		"plain_plants": [],
		"shadow_props": [],
		"shadow_plants": [],
	}

	if normalized_profile.get("generate_plain_scenes", true):
		var props_plain := _generate_sprite_scene_collection("props_plain", copied_res_paths.get("props", ""), "scenes/props/plain", "prop")
		if not props_plain.get("ok", false):
			return props_plain
		outputs.append_array(props_plain.get("paths", []))
		generated_scenes["plain_props"] = props_plain.get("paths", [])
		catalog["scene_collections"].append(props_plain.get("catalog_entry", {}))

		var plants_plain := _generate_sprite_scene_collection("plants_plain", copied_res_paths.get("plants", ""), "scenes/plants/plain", "plant")
		if not plants_plain.get("ok", false):
			return plants_plain
		outputs.append_array(plants_plain.get("paths", []))
		generated_scenes["plain_plants"] = plants_plain.get("paths", [])
		catalog["scene_collections"].append(plants_plain.get("catalog_entry", {}))

	if normalized_profile.get("generate_shadow_scenes", true):
		if copied_res_paths.has("extra_props_shadow"):
			var props_shadow := _generate_sprite_scene_collection("props_shadow", copied_res_paths.get("extra_props_shadow", ""), "scenes/props/shadow_baked", "prop_shadow")
			if not props_shadow.get("ok", false):
				return props_shadow
			outputs.append_array(props_shadow.get("paths", []))
			generated_scenes["shadow_props"] = props_shadow.get("paths", [])
			catalog["scene_collections"].append(props_shadow.get("catalog_entry", {}))

		if copied_res_paths.has("extra_plants_shadow"):
			var plants_shadow := _generate_sprite_scene_collection("plants_shadow", copied_res_paths.get("extra_plants_shadow", ""), "scenes/plants/shadow_baked", "plant_shadow")
			if not plants_shadow.get("ok", false):
				return plants_shadow
			outputs.append_array(plants_shadow.get("paths", []))
			generated_scenes["shadow_plants"] = plants_shadow.get("paths", [])
			catalog["scene_collections"].append(plants_shadow.get("catalog_entry", {}))

	var player_output := {}
	if normalized_profile.get("generate_player_assets", true):
		player_output = _generate_player_assets(copied_res_paths.get("player", ""))
		if not player_output.get("ok", false):
			return player_output
		outputs.append_array(player_output.get("paths", []))
		catalog["scene_collections"].append(player_output.get("catalog_entry", {}))

	if normalized_profile.get("generate_preview_scene", true):
		var preview_result := _generate_preview_scene(copied_res_paths, generated_scenes, player_output)
		if not preview_result.get("ok", false):
			return preview_result
		outputs.append(preview_result.get("path", ""))
		catalog["helper_scenes"].append(preview_result.get("catalog_entry", {}))

	var manifest := {
		"pack_id": PACK_ID,
		"importer": {
			"id": IMPORTER_ID,
			"version": IMPORTER_VERSION,
			"godot_version": Engine.get_version_info().get("string", ""),
		},
		"source": {
			"kind": source_info.get("source_kind", ""),
			"path": source_info.get("source_path", ""),
			"source_hash": source_info.get("source_hash", ""),
		},
		"profile": normalized_profile,
		"profile_hash": _sha256_text(JSON.stringify(normalized_profile, "", true)),
		"inventory": inventory,
		"outputs": outputs,
		"catalog": catalog,
	}

	var reports := _write_reports(output_root, manifest, compatibility, catalog)
	if not reports.get("ok", false):
		return reports

	var summary := {
		"tilesets": len(catalog.get("tilesets", [])),
		"scene_collections": len(catalog.get("scene_collections", [])),
		"helper_scenes": len(catalog.get("helper_scenes", [])),
		"generated_files": outputs.size() + reports.get("written_files", 0),
	}
	return {
		"ok": true,
		"mode": "import",
		"summary": summary,
		"manifest_path": reports.get("manifest_path", ""),
		"report_path": reports.get("report_markdown_path", ""),
		"catalog_path": reports.get("catalog_markdown_path", ""),
	}


func _normalize_profile(profile: Dictionary) -> Dictionary:
	var merged := DEFAULT_GENERATION_PROFILE.duplicate(true)
	for key in profile.keys():
		merged[key] = profile[key]
	if str(merged.get("output_root", "")).strip_edges().is_empty():
		merged["output_root"] = DEFAULT_OUTPUT_ROOT
	return merged


func _probe_source(source_path: String) -> Dictionary:
	var absolute := source_path
	if source_path.begins_with("res://"):
		absolute = ProjectSettings.globalize_path(source_path)
	absolute = absolute.simplify_path()

	if FileAccess.file_exists(absolute):
		if absolute.to_lower().ends_with(".unitypackage"):
			return {
				"ok": false,
				"error": "Direct .unitypackage import is not supported in v1. Point the importer at the extracted pack folder or the original zip that contains Texture/ files.",
			}
		if absolute.to_lower().ends_with(".zip"):
			return _probe_zip_source(absolute)
		return {
			"ok": false,
			"error": "Unsupported source file. Use the extracted pack folder or a zip containing the Texture/ directory.",
		}

	if DirAccess.dir_exists_absolute(absolute):
		return _probe_folder_source(absolute)

	return {
		"ok": false,
		"error": "Source path does not exist: %s" % absolute,
	}


func _probe_folder_source(absolute_dir: String) -> Dictionary:
	var pack_root := absolute_dir
	var texture_root := absolute_dir.path_join("Texture")
	if not DirAccess.dir_exists_absolute(texture_root):
		if FileAccess.file_exists(absolute_dir.path_join("TX Tileset Grass.png")):
			texture_root = absolute_dir
			pack_root = absolute_dir.get_base_dir()
		else:
			return {
				"ok": false,
				"error": "Could not find a Texture directory in %s" % absolute_dir,
			}

	var resolved := {}
	for key in REQUIRED_SOURCE_FILES.keys():
		var rel_path: String = REQUIRED_SOURCE_FILES[key]
		var full_path := pack_root.path_join(rel_path)
		if not FileAccess.file_exists(full_path):
			return {
				"ok": false,
				"error": "Missing required file: %s" % rel_path,
			}
		resolved[key] = full_path

	for optional_key in OPTIONAL_SOURCE_FILES.keys():
		var optional_rel: String = OPTIONAL_SOURCE_FILES[optional_key]
		var optional_path := pack_root.path_join(optional_rel)
		if FileAccess.file_exists(optional_path):
			resolved[optional_key] = optional_path

	return {
		"ok": true,
		"source_kind": "folder",
		"source_path": pack_root,
		"resolved_paths": resolved,
		"source_hash": _sha256_folder_probe(resolved),
	}


func _probe_zip_source(zip_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		return {
			"ok": false,
			"error": "Could not open zip: %s" % zip_path,
		}

	var files := reader.get_files()
	var resolved := {}
	for key in REQUIRED_SOURCE_FILES.keys():
		var suffix: String = REQUIRED_SOURCE_FILES[key]
		var entry := _find_zip_entry(files, suffix)
		if entry.is_empty():
			reader.close()
			return {
				"ok": false,
				"error": "Missing required zip entry: %s" % suffix,
			}
		resolved[key] = entry

	for optional_key in OPTIONAL_SOURCE_FILES.keys():
		var optional_entry := _find_zip_entry(files, OPTIONAL_SOURCE_FILES[optional_key])
		if not optional_entry.is_empty():
			resolved[optional_key] = optional_entry

	reader.close()
	return {
		"ok": true,
		"source_kind": "zip",
		"source_path": zip_path,
		"resolved_paths": resolved,
		"source_hash": _sha256_file(zip_path),
	}


func _find_zip_entry(files: PackedStringArray, suffix: String) -> String:
	for file_path in files:
		if String(file_path).ends_with(suffix):
			return file_path
	return ""


func _build_inventory(probe: Dictionary) -> Dictionary:
	var resolved: Dictionary = probe.get("resolved_paths", {})
	var inventory := {
		"tileset_atlases": 4,
		"tileset_tiles": 0,
		"plain_prop_cells": 0,
		"plain_plant_cells": 0,
		"shadow_prop_cells": 0,
		"shadow_plant_cells": 0,
		"player_cells": 0,
		"reference_scene_available": resolved.has("unitypackage_a") or resolved.has("unitypackage_b"),
	}

	inventory["tileset_tiles"] = _count_non_empty_cells_from_source(probe, "tileset_grass") \
		+ _count_non_empty_cells_from_source(probe, "tileset_stone_ground") \
		+ _count_non_empty_cells_from_source(probe, "tileset_wall") \
		+ _count_non_empty_cells_from_source(probe, "struct")
	inventory["plain_prop_cells"] = _count_non_empty_cells_from_source(probe, "props")
	inventory["plain_plant_cells"] = _count_non_empty_cells_from_source(probe, "plants")
	inventory["shadow_prop_cells"] = _count_non_empty_cells_from_source(probe, "extra_props_shadow")
	inventory["shadow_plant_cells"] = _count_non_empty_cells_from_source(probe, "extra_plants_shadow")
	inventory["player_cells"] = _count_non_empty_cells_from_source(probe, "player")
	return inventory


func _build_compatibility(inventory: Dictionary) -> Array:
	return [
		{
			"family": "TileSet atlases",
			"status": "supported",
			"detail": "Grass, stone ground, wall, and struct atlases import as external TileSet resources for TileMapLayer painting.",
			"next_action": "Add a TileMapLayer node, assign a generated TileSet, and paint in the TileMap bottom panel.",
		},
		{
			"family": "Generic prop scenes",
			"status": "supported",
			"detail": "%s generic prop cells can be generated as Godot scenes." % inventory.get("plain_prop_cells", 0),
			"next_action": "Place the generated prop scenes directly in your map scene.",
		},
		{
			"family": "Generic plant scenes",
			"status": "supported",
			"detail": "%s generic plant cells can be generated as Godot scenes." % inventory.get("plain_plant_cells", 0),
			"next_action": "Place the generated plant scenes directly in your map scene.",
		},
		{
			"family": "Baked-shadow helper scenes",
			"status": "approximated",
			"detail": "Extra shadow atlases are used to create convenience scenes with baked shadows for quick authoring.",
			"next_action": "Use the shadow-baked scenes when you want a fast drop-in look; switch to plain scenes if you need manual layering.",
		},
		{
			"family": "Player animations",
			"status": "approximated",
			"detail": "The player sheet imports as row-based animation resources, not exact Unity controller behavior.",
			"next_action": "Use the generated AnimatedSprite2D preview as a starting point and refine animations manually if needed.",
		},
		{
			"family": "Named Unity prefabs",
			"status": "manual",
			"detail": "V1 generates generic atlas-cell scenes instead of one-to-one prefab-named Godot scenes.",
			"next_action": "Use the catalog and preview scenes to pick assets, then rename or duplicate them into your own game folders.",
		},
		{
			"family": "Unity scenes, scripts, materials, shaders, and URP patches",
			"status": "unsupported",
			"detail": "Unity demo scenes, behaviors, materials, and patch packages are not converted in v1.",
			"next_action": "Use the generated report and preview scene as references while rebuilding gameplay or visual effects manually in Godot.",
		},
	]


func _count_non_empty_cells_from_source(probe: Dictionary, key: String) -> int:
	var resolved: Dictionary = probe.get("resolved_paths", {})
	if not resolved.has(key):
		return 0
	var image := _load_source_image(probe, key)
	if image == null or image.is_empty():
		return 0
	return _non_empty_cells(image).size()


func _copy_selected_sources(source_info: Dictionary, output_root: String) -> Dictionary:
	var copied := {}
	var textures_root := output_root.path_join("textures/source")
	var textures_root_abs := ProjectSettings.globalize_path(textures_root)
	_ensure_dir(textures_root_abs)

	var resolved: Dictionary = source_info.get("resolved_paths", {})
	if source_info.get("source_kind", "") == "folder":
		for key in resolved.keys():
			var source_abs := str(resolved[key])
			var dest_rel := textures_root.path_join(source_abs.get_file())
			if source_abs.contains("/Extra/"):
				dest_rel = textures_root.path_join("Extra").path_join(source_abs.get_file())
			var dest_abs := ProjectSettings.globalize_path(dest_rel)
			_ensure_dir(dest_abs.get_base_dir())
			var err := DirAccess.copy_absolute(source_abs, dest_abs)
			if err != OK:
				return {"ok": false, "error": "Failed to copy %s" % source_abs}
			copied[key] = dest_rel
	else:
		var reader := ZIPReader.new()
		var err := reader.open(str(source_info.get("source_path", "")))
		if err != OK:
			return {"ok": false, "error": "Could not open zip for extraction."}
		for key in resolved.keys():
			var zip_entry := str(resolved[key])
			var file_name := zip_entry.get_file()
			var dest_rel_zip := textures_root.path_join(file_name)
			if zip_entry.contains("/Extra/"):
				dest_rel_zip = textures_root.path_join("Extra").path_join(file_name)
			var dest_abs_zip := ProjectSettings.globalize_path(dest_rel_zip)
			_ensure_dir(dest_abs_zip.get_base_dir())
			var bytes := reader.read_file(zip_entry)
			var file := FileAccess.open(dest_abs_zip, FileAccess.WRITE)
			if file == null:
				reader.close()
				return {"ok": false, "error": "Could not write extracted file: %s" % dest_rel_zip}
			file.store_buffer(bytes)
			file.close()
			copied[key] = dest_rel_zip
		reader.close()

	return {"ok": true, "copied": copied}


func _generate_tileset(spec: Dictionary, copied_res_paths: Dictionary) -> Dictionary:
	var source_key := str(spec.get("key", ""))
	var texture_res_path := str(copied_res_paths.get(source_key, ""))
	var texture := _load_texture_resource(texture_res_path)
	if texture == null:
		return {"ok": false, "error": "Could not load copied texture for %s" % source_key}
	var image := Image.load_from_file(ProjectSettings.globalize_path(texture_res_path))
	if image == null or image.is_empty():
		return {"ok": false, "error": "Could not read image bytes for %s" % texture_res_path}

	var tileset := TileSet.new()
	tileset.tile_size = TILE_SIZE

	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = texture
	atlas_source.texture_region_size = TILE_SIZE
	atlas_source.use_texture_padding = false
	tileset.add_source(atlas_source)

	for coords in _non_empty_cells(image):
		atlas_source.create_tile(coords)

	var output_path := _active_output_root.path_join(str(spec.get("output", "")))
	var save_err := _save_resource(tileset, output_path)
	if save_err != OK:
		return {"ok": false, "error": "Failed to save tileset: %s" % output_path}

	return {
		"ok": true,
		"path": output_path,
		"catalog_entry": {
			"name": str(spec.get("name", "")),
			"path": output_path,
			"tile_count": _non_empty_cells(image).size(),
		},
	}


func _generate_sprite_scene_collection(collection_name: String, texture_res_path: String, output_dir_rel: String, prefix: String) -> Dictionary:
	if texture_res_path.is_empty():
		return {"ok": true, "paths": [], "catalog_entry": {"name": collection_name, "path": "", "count": 0}}

	var texture := _load_texture_resource(texture_res_path)
	if texture == null:
		return {"ok": false, "error": "Could not load texture for scene collection: %s" % texture_res_path}
	var image := Image.load_from_file(ProjectSettings.globalize_path(texture_res_path))
	if image == null or image.is_empty():
		return {"ok": false, "error": "Could not load image for scene collection: %s" % texture_res_path}

	var output_dir := _active_output_root.path_join(output_dir_rel)
	_ensure_dir(ProjectSettings.globalize_path(output_dir))

	var paths: Array[String] = []
	for coords in _non_empty_cells(image):
		var root := Node2D.new()
		root.name = "%s_%02d_%02d" % [prefix, coords.x, coords.y]
		root.set_meta("atlas_coords", coords)
		root.set_meta("atlas_source", texture_res_path)

		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = texture
		atlas_texture.region = Rect2(coords * TILE_SIZE, TILE_SIZE)
		sprite.texture = atlas_texture
		root.add_child(sprite)
		sprite.owner = root

		var packed := PackedScene.new()
		var pack_err := packed.pack(root)
		if pack_err != OK:
			return {"ok": false, "error": "Could not pack scene for %s" % root.name}
		var scene_path := output_dir.path_join("%s_%02d_%02d.tscn" % [prefix, coords.x, coords.y])
		var save_err := _save_resource(packed, scene_path)
		root.free()
		if save_err != OK:
			return {"ok": false, "error": "Could not save scene %s" % scene_path}
		paths.append(scene_path)

	return {
		"ok": true,
		"paths": paths,
		"catalog_entry": {
			"name": collection_name,
			"path": output_dir,
			"count": paths.size(),
		},
	}


func _generate_player_assets(player_texture_res_path: String) -> Dictionary:
	var texture := _load_texture_resource(player_texture_res_path)
	if texture == null:
		return {"ok": false, "error": "Could not load player texture."}
	var image := Image.load_from_file(ProjectSettings.globalize_path(player_texture_res_path))
	if image == null or image.is_empty():
		return {"ok": false, "error": "Could not read player image."}

	var output_dir := _active_output_root.path_join("animations/player")
	_ensure_dir(ProjectSettings.globalize_path(output_dir))

	var frames := SpriteFrames.new()
	var rows := _non_empty_cells_by_row(image)
	for row_key in rows.keys():
		var animation_name := "sheet_row_%d" % row_key
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, 6.0)
		for coords in rows[row_key]:
			var atlas_texture := AtlasTexture.new()
			atlas_texture.atlas = texture
			atlas_texture.region = Rect2(coords * TILE_SIZE, TILE_SIZE)
			frames.add_frame(animation_name, atlas_texture)

	var frames_path := output_dir.path_join("basic_player_frames.tres")
	var frames_save_err := _save_resource(frames, frames_path)
	if frames_save_err != OK:
		return {"ok": false, "error": "Could not save player SpriteFrames resource."}

	var root := Node2D.new()
	root.name = "BasicPlayerPreview"

	var animated := AnimatedSprite2D.new()
	animated.name = "AnimatedSprite2D"
	animated.sprite_frames = frames
	animated.animation = "sheet_row_1" if rows.has(1) else "sheet_row_0"
	animated.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(animated)
	animated.owner = root

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		return {"ok": false, "error": "Could not pack player preview scene."}
	var scene_path := output_dir.path_join("basic_player_preview.tscn")
	var scene_save_err := _save_resource(packed, scene_path)
	root.free()
	if scene_save_err != OK:
		return {"ok": false, "error": "Could not save player preview scene."}

	return {
		"ok": true,
		"paths": [frames_path, scene_path],
		"catalog_entry": {
			"name": "player_assets",
			"path": output_dir,
			"count": 2,
		},
	}


func _generate_preview_scene(copied_res_paths: Dictionary, generated_scenes: Dictionary, player_output: Dictionary) -> Dictionary:
	var root := Node2D.new()
	root.name = "BasicPackPreview"

	var grass_tileset := load(_active_output_root.path_join("tilesets/basic_grass_tileset.tres")) as TileSet
	var stone_tileset := load(_active_output_root.path_join("tilesets/basic_stone_ground_tileset.tres")) as TileSet
	var wall_tileset := load(_active_output_root.path_join("tilesets/basic_wall_tileset.tres")) as TileSet
	var struct_tileset := load(_active_output_root.path_join("tilesets/basic_struct_tileset.tres")) as TileSet
	if grass_tileset == null or stone_tileset == null or wall_tileset == null or struct_tileset == null:
		return {"ok": false, "error": "Could not reload generated tilesets for preview scene."}

	var grass := _make_tile_layer("Grass", grass_tileset, 0)
	var stone := _make_tile_layer("Stone", stone_tileset, 1)
	var wall := _make_tile_layer("Wall", wall_tileset, 2)
	var struct_layer := _make_tile_layer("Struct", struct_tileset, 3)
	for node in [grass, stone, wall, struct_layer]:
		root.add_child(node)
		node.owner = root

	for x in range(10):
		for y in range(7):
			grass.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))

	for x in range(2, 8):
		stone.set_cell(Vector2i(x, 4), 0, Vector2i(0, 0))
	for x in range(0, 10):
		wall.set_cell(Vector2i(x, 0), 0, Vector2i(0, 0))
	struct_layer.set_cell(Vector2i(4, 2), 0, Vector2i(0, 0))
	struct_layer.set_cell(Vector2i(5, 2), 0, Vector2i(1, 0))

	var prop_paths: Array = generated_scenes.get("shadow_props", [])
	if prop_paths.is_empty():
		prop_paths = generated_scenes.get("plain_props", [])
	if not prop_paths.is_empty():
		var prop_scene := load(prop_paths[0]) as PackedScene
		if prop_scene != null:
			var prop_instance := prop_scene.instantiate()
			prop_instance.position = Vector2(96, 96)
			root.add_child(prop_instance)
			prop_instance.owner = root

	var plant_paths: Array = generated_scenes.get("shadow_plants", [])
	if plant_paths.is_empty():
		plant_paths = generated_scenes.get("plain_plants", [])
	if not plant_paths.is_empty():
		var plant_scene := load(plant_paths[0]) as PackedScene
		if plant_scene != null:
			var plant_instance := plant_scene.instantiate()
			plant_instance.position = Vector2(224, 128)
			root.add_child(plant_instance)
			plant_instance.owner = root

	var player_paths: Array = player_output.get("paths", [])
	if player_paths.size() > 1:
		var player_scene := load(player_paths[1]) as PackedScene
		if player_scene != null:
			var player_instance := player_scene.instantiate()
			player_instance.position = Vector2(160, 160)
			root.add_child(player_instance)
			player_instance.owner = root

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.enabled = true
	camera.position = Vector2(160, 112)
	root.add_child(camera)
	camera.owner = root

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		return {"ok": false, "error": "Could not pack preview scene."}
	var scene_path := _active_output_root.path_join("scenes/helpers/basic_preview_map.tscn")
	var save_err := _save_resource(packed, scene_path)
	root.free()
	if save_err != OK:
		return {"ok": false, "error": "Could not save preview scene."}
	return {
		"ok": true,
		"path": scene_path,
		"catalog_entry": {
			"name": "basic_preview_map",
			"path": scene_path,
		},
	}


func _make_tile_layer(name: String, tileset: TileSet, z_index: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = name
	layer.tile_set = tileset
	layer.z_index = z_index
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return layer


func _write_reports(output_root: String, manifest: Dictionary, compatibility: Array, catalog: Dictionary) -> Dictionary:
	var reports_root := output_root.path_join("reports")
	var reports_root_abs := ProjectSettings.globalize_path(reports_root)
	_ensure_dir(reports_root_abs)

	var manifest_path := reports_root.path_join("import_manifest.json")
	var manifest_err := _write_text_file(manifest_path, JSON.stringify(manifest, "\t", true))
	if manifest_err != OK:
		return {"ok": false, "error": "Could not write manifest."}

	var compatibility_json := reports_root.path_join("compatibility_report.json")
	var compatibility_err := _write_text_file(compatibility_json, JSON.stringify(compatibility, "\t", true))
	if compatibility_err != OK:
		return {"ok": false, "error": "Could not write compatibility JSON."}

	var compatibility_md := reports_root.path_join("compatibility_report.md")
	var compatibility_md_err := _write_text_file(compatibility_md, _compatibility_markdown(compatibility))
	if compatibility_md_err != OK:
		return {"ok": false, "error": "Could not write compatibility markdown."}

	var catalog_json := reports_root.path_join("asset_catalog.json")
	var catalog_json_err := _write_text_file(catalog_json, JSON.stringify(catalog, "\t", true))
	if catalog_json_err != OK:
		return {"ok": false, "error": "Could not write asset catalog JSON."}

	var catalog_md := reports_root.path_join("asset_catalog.md")
	var catalog_md_err := _write_text_file(catalog_md, _catalog_markdown(catalog))
	if catalog_md_err != OK:
		return {"ok": false, "error": "Could not write asset catalog markdown."}

	return {
		"ok": true,
		"manifest_path": manifest_path,
		"report_markdown_path": compatibility_md,
		"catalog_markdown_path": catalog_md,
		"written_files": 5,
	}


func _compatibility_markdown(compatibility: Array) -> String:
	var lines := [
		"# Cainos Basic Compatibility Report",
		"",
		"Generated by the Cainos Basic Importer. Status values:",
		"- supported: imported directly into usable Godot assets",
		"- approximated: usable, but not a one-to-one Unity mapping",
		"- manual: requires user follow-up in Godot",
		"- unsupported: not converted in v1",
		"",
	]
	for item_variant in compatibility:
		var item: Dictionary = item_variant
		lines.append("## %s" % item.get("family", "Unknown"))
		lines.append("- Status: %s" % item.get("status", "unknown"))
		lines.append("- Detail: %s" % item.get("detail", ""))
		lines.append("- Next: %s" % item.get("next_action", ""))
		lines.append("")
	return "\n".join(lines)


func _catalog_markdown(catalog: Dictionary) -> String:
	var lines := [
		"# Cainos Basic Asset Catalog",
		"",
		"## TileSets",
	]
	for item_variant in catalog.get("tilesets", []):
		var item: Dictionary = item_variant
		lines.append("- %s: %s (%s tiles)" % [item.get("name", ""), item.get("path", ""), item.get("tile_count", 0)])

	lines.append("")
	lines.append("## Scene Collections")
	for collection_variant in catalog.get("scene_collections", []):
		var collection: Dictionary = collection_variant
		lines.append("- %s: %s (%s items)" % [collection.get("name", ""), collection.get("path", ""), collection.get("count", 0)])

	lines.append("")
	lines.append("## Helper Scenes")
	for helper_variant in catalog.get("helper_scenes", []):
		var helper: Dictionary = helper_variant
		lines.append("- %s: %s" % [helper.get("name", ""), helper.get("path", "")])
	return "\n".join(lines)


func _wait_for_import(resource_paths: Array) -> void:
	if _editor_interface == null:
		return
	var filesystem := _editor_interface.get_resource_filesystem()
	if filesystem == null:
		return
	filesystem.scan()
	await filesystem.filesystem_changed
	for resource_path_variant in resource_paths:
		var resource_path := str(resource_path_variant)
		var attempts := 0
		while attempts < 60:
			if ResourceLoader.exists(resource_path):
				break
			attempts += 1
			await _editor_interface.get_base_control().get_tree().process_frame


func _load_texture_resource(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var texture := load(res_path) as Texture2D
		if texture != null:
			return texture
	var image := Image.load_from_file(ProjectSettings.globalize_path(res_path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _non_empty_cells(image: Image) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	var width := image.get_width() / TILE_SIZE.x
	var height := image.get_height() / TILE_SIZE.y
	for y in range(height):
		for x in range(width):
			if _cell_has_alpha(image, x, y):
				coords.append(Vector2i(x, y))
	return coords


func _non_empty_cells_by_row(image: Image) -> Dictionary:
	var rows := {}
	for coords in _non_empty_cells(image):
		if not rows.has(coords.y):
			rows[coords.y] = []
		rows[coords.y].append(coords)
	for row_key in rows.keys():
		rows[row_key].sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x)
	return rows


func _cell_has_alpha(image: Image, tile_x: int, tile_y: int) -> bool:
	var origin := Vector2i(tile_x, tile_y) * TILE_SIZE
	for y in range(TILE_SIZE.y):
		for x in range(TILE_SIZE.x):
			if image.get_pixel(origin.x + x, origin.y + y).a > 0.0:
				return true
	return false


func _load_source_image(probe: Dictionary, key: String) -> Image:
	var resolved: Dictionary = probe.get("resolved_paths", {})
	if not resolved.has(key):
		return null
	if probe.get("source_kind", "") == "folder":
		return Image.load_from_file(str(resolved[key]))

	var reader := ZIPReader.new()
	var err := reader.open(str(probe.get("source_path", "")))
	if err != OK:
		return null
	var bytes := reader.read_file(str(resolved[key]))
	reader.close()
	if bytes.is_empty():
		return null
	var image := Image.new()
	var load_err := image.load_png_from_buffer(bytes)
	if load_err != OK:
		return null
	return image


func _sha256_file(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	while not file.eof_reached():
		ctx.update(file.get_buffer(65536))
	file.close()
	return ctx.finish().hex_encode()


func _sha256_folder_probe(resolved_paths: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var keys := resolved_paths.keys()
	keys.sort()
	for key_variant in keys:
		var key := str(key_variant)
		var path := str(resolved_paths[key])
		ctx.update(key.to_utf8_buffer())
		ctx.update(path.to_utf8_buffer())
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			while not file.eof_reached():
				ctx.update(file.get_buffer(65536))
			file.close()
	return ctx.finish().hex_encode()


func _sha256_text(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _save_resource(resource: Resource, res_path: String) -> int:
	_ensure_dir(ProjectSettings.globalize_path(res_path).get_base_dir())
	return ResourceSaver.save(resource, res_path)


func _write_text_file(res_path: String, content: String) -> int:
	var abs_path := ProjectSettings.globalize_path(res_path)
	_ensure_dir(abs_path.get_base_dir())
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		return ERR_CANT_CREATE
	file.store_string(content)
	file.close()
	return OK


func _ensure_dir(abs_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(abs_path)


func _remove_tree_absolute(abs_path: String) -> void:
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
		return
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name == "." or name == "..":
			continue
		var child := abs_path.path_join(name)
		if dir.current_is_dir():
			_remove_tree_absolute(child)
		else:
			DirAccess.remove_absolute(child)
	dir.list_dir_end()
	DirAccess.remove_absolute(abs_path)


func _log_message(message: String) -> void:
	if _log.is_valid():
		_log.call(message)
