@tool
extends RefCounted

const UnityMetadataRegistry := preload("res://addons/cainos_basic_importer/unity_metadata_registry.gd")

const PACK_ID := "basic"
const IMPORTER_ID := "cainos_basic_importer"
const IMPORTER_VERSION := "0.3.0"
const REPORT_FORMAT_VERSION := 3
const DEFAULT_OUTPUT_ROOT := "res://cainos_imports/basic"
const TILE_SIZE := Vector2i(32, 32)
const DEFAULT_PPU := 32.0
const TEXTURE_FILTER_NEAREST := 1

const DEFAULT_GENERATION_PROFILE := {
	"output_root": DEFAULT_OUTPUT_ROOT,
	"prefer_semantic_prefabs": true,
	"generate_fallback_atlas_scenes": false,
	"generate_baked_shadow_helpers": false,
	"generate_preview_scene": true,
	"generate_player_helpers": true,
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
}

const TILESET_SPECS := [
	{"key": "tileset_grass", "name": "grass", "output": "tilesets/basic_grass_tileset.tres"},
	{"key": "tileset_stone_ground", "name": "stone_ground", "output": "tilesets/basic_stone_ground_tileset.tres"},
	{"key": "tileset_wall", "name": "wall", "output": "tilesets/basic_wall_tileset.tres"},
	{"key": "struct", "name": "struct", "output": "tilesets/basic_struct_tileset.tres"},
]

var _editor_interface
var _log: Callable
var _active_output_root := DEFAULT_OUTPUT_ROOT


func _init(editor_interface = null, logger: Callable = Callable()) -> void:
	_editor_interface = editor_interface
	_log = logger


func scan_source(source_path: String, profile: Dictionary = {}) -> Dictionary:
	var normalized_profile := _normalize_profile(profile)
	var probe := _probe_source(source_path)
	if not probe.get("ok", false):
		return probe

	var semantic_registry := {}
	var semantic_candidate := probe.get("semantic_source", {})
	if probe.get("source_kind", "") == "unitypackage" or (normalized_profile.get("prefer_semantic_prefabs", true) and not semantic_candidate.is_empty()):
		semantic_registry = _load_semantic_registry(probe)
		if not semantic_registry.get("ok", false):
			if probe.get("source_kind", "") == "unitypackage":
				return semantic_registry
			probe["semantic_error"] = semantic_registry.get("error", "")
			semantic_registry = {}

	var inventory := _build_inventory(probe, semantic_registry)
	var compatibility := _build_compatibility(inventory)
	var summary := {
		"pack_id": PACK_ID,
		"source_kind": probe.get("source_kind", "unknown"),
		"semantic_available": inventory.get("semantic_available", false),
		"tileset_atlases": inventory.get("tileset_atlases", 0),
		"tileset_tiles": inventory.get("tileset_tiles", 0),
		"supported_static_prefabs": inventory.get("supported_static_prefabs", 0),
		"approximated_prefabs": inventory.get("approximated_prefabs", 0),
		"manual_behavior_prefabs": inventory.get("manual_behavior_prefabs", 0),
		"unresolved_or_skipped_prefabs": inventory.get("unresolved_or_skipped_prefabs", 0),
		"editor_only_prefabs": inventory.get("editor_only_prefabs", 0),
		"fallback_prop_cells": inventory.get("plain_prop_cells", 0),
		"fallback_plant_cells": inventory.get("plain_plant_cells", 0),
	}
	return {
		"ok": true,
		"mode": "scan",
		"pack_id": PACK_ID,
		"profile": normalized_profile,
		"source": probe,
		"semantic_registry": semantic_registry,
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
	var semantic_registry: Dictionary = scan.get("semantic_registry", {})
	var inventory: Dictionary = scan.get("inventory", {})

	_log_message("Preparing output root: %s" % output_root)
	_remove_tree_absolute(output_root_abs)
	_ensure_dir(output_root_abs)

	var copied_sources := _copy_selected_sources(source_info, output_root, semantic_registry)
	if not copied_sources.get("ok", false):
		return copied_sources

	var copied_res_paths: Dictionary = copied_sources.get("copied", {})
	await _wait_for_import(copied_res_paths.values())

	var outputs := []
	var catalog := {
		"format_version": REPORT_FORMAT_VERSION,
		"pack_id": PACK_ID,
		"tilesets": [],
		"scene_collections": [],
		"helper_scenes": [],
		"prefabs": [],
		"fallback_collections": [],
	}
	var generated_tilesets := {}

	for spec_variant in TILESET_SPECS:
		var spec: Dictionary = spec_variant
		if not copied_res_paths.has(spec.get("key", "")):
			continue
		var tileset_result := _generate_tileset(spec, copied_res_paths)
		if not tileset_result.get("ok", false):
			return tileset_result
		outputs.append(tileset_result.get("path", ""))
		catalog["tilesets"].append(tileset_result.get("catalog_entry", {}))
		generated_tilesets[str(spec.get("key", ""))] = tileset_result.get("resource")

	var semantic_generated := {
		"tier_counts": {
			"supported_static": 0,
			"approximated": 0,
			"manual_behavior": 0,
			"unresolved_or_skipped": 0,
		},
		"family_to_paths": {
			"plants": [],
			"props": [],
			"struct": [],
			"player": [],
		},
		"prefab_entries": [],
		"editor_only_entries": [],
		"catalog_prefabs": [],
	}
	if normalized_profile.get("prefer_semantic_prefabs", true) and semantic_registry.get("ok", false):
		var semantic_result := _generate_semantic_prefab_collections(semantic_registry, copied_res_paths)
		if not semantic_result.get("ok", false):
			return semantic_result
		outputs.append_array(semantic_result.get("paths", []))
		semantic_generated = semantic_result
		for entry_variant in semantic_result.get("catalog_entries", []):
			catalog["scene_collections"].append(entry_variant)
		for prefab_entry_variant in semantic_result.get("catalog_prefabs", []):
			catalog["prefabs"].append(prefab_entry_variant)

	if normalized_profile.get("generate_fallback_atlas_scenes", false) or catalog["scene_collections"].is_empty():
		if copied_res_paths.has("props"):
			var props_plain := _generate_sprite_scene_collection("props_plain", copied_res_paths.get("props", ""), "scenes/fallback/props/plain", "prop")
			if not props_plain.get("ok", false):
				return props_plain
			outputs.append_array(props_plain.get("paths", []))
			var props_catalog_entry: Dictionary = props_plain.get("catalog_entry", {})
			catalog["scene_collections"].append(props_catalog_entry)
			if str(props_catalog_entry.get("origin", "")) == "fallback_atlas":
				catalog["fallback_collections"].append(props_catalog_entry)

		if copied_res_paths.has("plants"):
			var plants_plain := _generate_sprite_scene_collection("plants_plain", copied_res_paths.get("plants", ""), "scenes/fallback/plants/plain", "plant")
			if not plants_plain.get("ok", false):
				return plants_plain
			outputs.append_array(plants_plain.get("paths", []))
			var plants_catalog_entry: Dictionary = plants_plain.get("catalog_entry", {})
			catalog["scene_collections"].append(plants_catalog_entry)
			if str(plants_catalog_entry.get("origin", "")) == "fallback_atlas":
				catalog["fallback_collections"].append(plants_catalog_entry)

		if normalized_profile.get("generate_baked_shadow_helpers", false):
			if copied_res_paths.has("extra_props_shadow"):
				var props_shadow := _generate_sprite_scene_collection("props_shadow", copied_res_paths.get("extra_props_shadow", ""), "scenes/fallback/props/shadow_baked", "prop_shadow")
				if not props_shadow.get("ok", false):
					return props_shadow
				outputs.append_array(props_shadow.get("paths", []))
				var props_shadow_catalog: Dictionary = props_shadow.get("catalog_entry", {})
				catalog["scene_collections"].append(props_shadow_catalog)
				if str(props_shadow_catalog.get("origin", "")) == "fallback_atlas":
					catalog["fallback_collections"].append(props_shadow_catalog)

			if copied_res_paths.has("extra_plants_shadow"):
				var plants_shadow := _generate_sprite_scene_collection("plants_shadow", copied_res_paths.get("extra_plants_shadow", ""), "scenes/fallback/plants/shadow_baked", "plant_shadow")
				if not plants_shadow.get("ok", false):
					return plants_shadow
				outputs.append_array(plants_shadow.get("paths", []))
				var plants_shadow_catalog: Dictionary = plants_shadow.get("catalog_entry", {})
				catalog["scene_collections"].append(plants_shadow_catalog)
				if str(plants_shadow_catalog.get("origin", "")) == "fallback_atlas":
					catalog["fallback_collections"].append(plants_shadow_catalog)

	var player_helpers := {}
	if normalized_profile.get("generate_player_helpers", true) and copied_res_paths.has("player"):
		player_helpers = _generate_player_helper_assets(copied_res_paths.get("player", ""))
		if not player_helpers.get("ok", false):
			return player_helpers
		outputs.append_array(player_helpers.get("paths", []))
		catalog["scene_collections"].append(player_helpers.get("catalog_entry", {}))

	if normalized_profile.get("generate_preview_scene", true):
		var preview_result := _generate_preview_scene(generated_tilesets, copied_res_paths, semantic_registry, semantic_generated, player_helpers)
		if not preview_result.get("ok", false):
			return preview_result
		outputs.append_array(preview_result.get("paths", []))
		for entry_variant in preview_result.get("catalog_entries", []):
			catalog["helper_scenes"].append(entry_variant)

	var compatibility: Array = _build_compatibility(inventory, normalized_profile, semantic_generated)
	var manifest := {
		"format_version": REPORT_FORMAT_VERSION,
		"pack_id": PACK_ID,
		"importer": {
			"id": IMPORTER_ID,
			"version": IMPORTER_VERSION,
			"godot_version": Engine.get_version_info().get("string", ""),
		},
		"source": {
			"kind": source_info.get("source_kind", ""),
			"display_name": source_info.get("display_name", ""),
			"source_hash": source_info.get("source_hash", ""),
			"semantic_source_kind": _semantic_source_kind_label(source_info),
		},
		"profile": normalized_profile,
		"profile_hash": _sha256_text(JSON.stringify(normalized_profile, "", true)),
		"inventory": inventory,
		"semantic_summary": semantic_generated.get("tier_counts", {}),
		"semantic_prefabs": semantic_generated.get("prefab_entries", []),
		"editor_only_prefabs": semantic_generated.get("editor_only_entries", []),
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
		"generated_files": outputs.size() + int(reports.get("written_files", 0)),
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
			return _probe_unitypackage_source(absolute)
		if absolute.to_lower().ends_with(".zip"):
			return _probe_zip_source(absolute)
		return {
			"ok": false,
			"error": "Unsupported source file: %s" % absolute,
		}

	if DirAccess.dir_exists_absolute(absolute):
		return _probe_folder_source(absolute)

	return {
		"ok": false,
		"error": "Source path does not exist: %s" % absolute,
	}


func _probe_unitypackage_source(package_path: String) -> Dictionary:
	return {
		"ok": true,
		"source_kind": "unitypackage",
		"source_path": package_path,
		"display_name": package_path.get_file(),
		"resolved_paths": {},
		"source_hash": _sha256_file(package_path),
		"semantic_source": {
			"kind": "unitypackage_file",
			"path": package_path,
		},
	}


func _probe_folder_source(absolute_dir: String) -> Dictionary:
	var pack_root := absolute_dir
	var texture_root := absolute_dir.path_join("Texture")
	if not DirAccess.dir_exists_absolute(texture_root):
		if FileAccess.file_exists(absolute_dir.path_join("TX Tileset Grass.png")):
			pack_root = absolute_dir.get_base_dir()
			texture_root = absolute_dir
		else:
			pack_root = absolute_dir

	var resolved := {}
	for key in REQUIRED_SOURCE_FILES.keys():
		var rel_path: String = REQUIRED_SOURCE_FILES[key]
		var full_path := pack_root.path_join(rel_path)
		if FileAccess.file_exists(full_path):
			resolved[key] = full_path

	for optional_key in OPTIONAL_SOURCE_FILES.keys():
		var optional_rel: String = OPTIONAL_SOURCE_FILES[optional_key]
		var optional_path := pack_root.path_join(optional_rel)
		if FileAccess.file_exists(optional_path):
			resolved[optional_key] = optional_path

	var semantic_source := {}
	var unitypackage_path := _find_sidecar_unitypackage(pack_root)
	if not unitypackage_path.is_empty():
		semantic_source = {
			"kind": "unitypackage_file",
			"path": unitypackage_path,
		}
	elif _contains_extracted_metadata(pack_root):
		semantic_source = {
			"kind": "extracted_metadata",
			"root": pack_root,
		}

	if resolved.is_empty() and semantic_source.is_empty():
		return {
			"ok": false,
			"error": "Could not find Cainos Basic textures or Unity metadata under: %s" % absolute_dir,
		}

	return {
		"ok": true,
		"source_kind": "folder",
		"source_path": pack_root,
		"display_name": pack_root.get_file(),
		"resolved_paths": resolved,
		"source_hash": _sha256_folder_probe(resolved if not resolved.is_empty() else _metadata_files_for_hash(pack_root)),
		"semantic_source": semantic_source,
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
		if not entry.is_empty():
			resolved[key] = entry
	for optional_key in OPTIONAL_SOURCE_FILES.keys():
		var optional_entry := _find_zip_entry(files, OPTIONAL_SOURCE_FILES[optional_key])
		if not optional_entry.is_empty():
			resolved[optional_key] = optional_entry

	var semantic_source := {}
	var unitypackage_entry := _find_zip_unitypackage(files)
	if not unitypackage_entry.is_empty():
		semantic_source = {
			"kind": "unitypackage_zip_entry",
			"zip_path": zip_path,
			"entry": unitypackage_entry,
		}

	reader.close()
	if resolved.is_empty() and semantic_source.is_empty():
		return {
			"ok": false,
			"error": "Zip does not contain Cainos Basic textures or a .unitypackage payload: %s" % zip_path,
		}

	return {
		"ok": true,
		"source_kind": "zip",
		"source_path": zip_path,
		"display_name": zip_path.get_file(),
		"resolved_paths": resolved,
		"source_hash": _sha256_file(zip_path),
		"semantic_source": semantic_source,
	}


func _find_zip_entry(files: PackedStringArray, suffix: String) -> String:
	for file_path in files:
		if String(file_path).ends_with(suffix):
			return file_path
	return ""


func _find_zip_unitypackage(files: PackedStringArray) -> String:
	for file_path in files:
		if String(file_path).to_lower().ends_with(".unitypackage"):
			return file_path
	return ""


func _find_sidecar_unitypackage(root_path: String) -> String:
	var files := _list_files_recursive(root_path)
	for file_path in files:
		if file_path.to_lower().ends_with(".unitypackage"):
			return file_path
	return ""


func _contains_extracted_metadata(root_path: String) -> bool:
	var files := _list_files_recursive(root_path)
	var has_prefab := false
	var has_meta := false
	for file_path in files:
		if file_path.ends_with(".prefab"):
			has_prefab = true
		elif file_path.ends_with(".meta"):
			has_meta = true
		if has_prefab and has_meta:
			return true
	return false


func _load_semantic_registry(source_info: Dictionary) -> Dictionary:
	var semantic_source: Dictionary = source_info.get("semantic_source", {})
	if semantic_source.is_empty():
		return {
			"ok": false,
			"error": "No semantic source available.",
		}

	var registry = UnityMetadataRegistry.new()
	match str(semantic_source.get("kind", "")):
		"unitypackage_file":
			return registry.build_from_unitypackage(str(semantic_source.get("path", "")))
		"unitypackage_zip_entry":
			var reader := ZIPReader.new()
			var zip_path := str(semantic_source.get("zip_path", ""))
			var err := reader.open(zip_path)
			if err != OK:
				return {
					"ok": false,
					"error": "Could not open zip for semantic import: %s" % zip_path,
				}
			var bytes := reader.read_file(str(semantic_source.get("entry", "")))
			reader.close()
			return registry.build_from_package_bytes(bytes, str(semantic_source.get("entry", "")))
		"extracted_metadata":
			return registry.build_from_extracted_metadata(str(semantic_source.get("root", "")))
		_:
			return {
				"ok": false,
				"error": "Unsupported semantic source kind: %s" % str(semantic_source.get("kind", "")),
			}


func _build_inventory(probe: Dictionary, semantic_registry: Dictionary) -> Dictionary:
	var inventory := {
		"semantic_available": semantic_registry.get("ok", false),
		"tileset_atlases": 0,
		"tileset_tiles": 0,
		"plain_prop_cells": 0,
		"plain_plant_cells": 0,
		"shadow_prop_cells": 0,
		"shadow_plant_cells": 0,
		"supported_static_prefabs": 0,
		"approximated_prefabs": 0,
		"manual_behavior_prefabs": 0,
		"unresolved_or_skipped_prefabs": 0,
		"editor_only_prefabs": 0,
	}

	for key in TILESET_SPECS:
		var source_key := str(key.get("key", ""))
		var count := _count_non_empty_cells(probe, source_key, semantic_registry)
		if count > 0:
			inventory["tileset_atlases"] += 1
			inventory["tileset_tiles"] += count

	inventory["plain_prop_cells"] = _count_non_empty_cells(probe, "props", semantic_registry)
	inventory["plain_plant_cells"] = _count_non_empty_cells(probe, "plants", semantic_registry)
	inventory["shadow_prop_cells"] = _count_non_empty_cells(probe, "extra_props_shadow", semantic_registry)
	inventory["shadow_plant_cells"] = _count_non_empty_cells(probe, "extra_plants_shadow", semantic_registry)

	if semantic_registry.get("ok", false):
		var summary: Dictionary = semantic_registry.get("summary", {})
		inventory["supported_static_prefabs"] = summary.get("supported_static_prefabs", 0)
		inventory["approximated_prefabs"] = summary.get("approximated_prefabs", 0)
		inventory["manual_behavior_prefabs"] = summary.get("manual_behavior_prefabs", 0)
		inventory["unresolved_or_skipped_prefabs"] = summary.get("unresolved_or_skipped_prefabs", 0)
		inventory["editor_only_prefabs"] = summary.get("editor_only_prefabs", 0)

	return inventory


func _build_compatibility(inventory: Dictionary, profile: Dictionary = {}, semantic_generated: Dictionary = {}) -> Array:
	var compatibility := []
	var semantic_enabled := profile.get("prefer_semantic_prefabs", true)
	var generated_prefabs := len(semantic_generated.get("prefab_entries", []))
	if semantic_enabled and generated_prefabs == 0:
		generated_prefabs = int(inventory.get("supported_static_prefabs", 0)) + int(inventory.get("approximated_prefabs", 0)) + int(inventory.get("manual_behavior_prefabs", 0)) + int(inventory.get("unresolved_or_skipped_prefabs", 0))
	compatibility.append({
		"title": "TileSet atlases",
		"status": "supported",
		"detail": "Grass, stone ground, wall, and struct atlases import as external TileSet resources for TileMapLayer painting.",
		"next": "Add a TileMapLayer node, assign a generated TileSet, and paint in the TileMap bottom panel.",
	})

	if inventory.get("semantic_available", false) and semantic_enabled:
		compatibility.append({
			"title": "Named Unity prefabs",
			"status": "supported",
			"detail": "%s semantic prefabs were generated as named Godot scenes in this import run." % generated_prefabs,
			"next": "Use the generated prefab scene folders to place named plants, props, struct pieces, and player assets.",
		})
		compatibility.append({
			"title": "Approximated prefab collisions",
			"status": "approximated",
			"detail": "%s prefabs import with partial collision/physics fidelity; polygon colliders and rigidbodies are deferred." % inventory.get("approximated_prefabs", 0),
			"next": "Use the generated scene as a visual base, then add or refine collisions manually where needed.",
		})
		compatibility.append({
			"title": "Manual behavior prefabs",
			"status": "manual",
			"detail": "%s prefabs preserve trigger/script metadata but do not recreate Unity runtime behaviors." % inventory.get("manual_behavior_prefabs", 0),
			"next": "Read the compatibility report and use the preserved metadata when rebuilding stairs, player control, or animation logic in Godot.",
		})
	elif inventory.get("semantic_available", false):
		compatibility.append({
			"title": "Named Unity prefabs",
			"status": "manual",
			"detail": "Semantic prefab import is available for this source, but it was disabled in this run.",
			"next": "Enable named semantic prefab scenes if you want prefab-level Godot scenes instead of fallback atlas collections.",
		})
	else:
		compatibility.append({
			"title": "Named Unity prefabs",
			"status": "manual",
			"detail": "Semantic prefab import is unavailable without a .unitypackage or extracted Unity metadata source.",
			"next": "Supply the Basic .unitypackage or an extracted Unity project folder to import named prefab scenes.",
		})

	if int(inventory.get("editor_only_prefabs", 0)) > 0:
		compatibility.append({
			"title": "Unity editor-only prefabs",
			"status": "manual",
			"detail": "%s Unity editor-only prefabs were detected and excluded from semantic prefab scene generation." % inventory.get("editor_only_prefabs", 0),
			"next": "Ignore these Unity editor artifacts for normal map authoring and use the generated TileSets instead.",
		})

	compatibility.append({
		"title": "Fallback atlas scenes",
		"status": "approximated",
		"detail": "%s prop cells and %s plant cells remain available as fallback atlas-cell scenes." % [inventory.get("plain_prop_cells", 0), inventory.get("plain_plant_cells", 0)],
		"next": "Enable fallback atlas scenes in the importer only when semantic prefab output is unavailable or insufficient for your workflow.",
	})
	return compatibility


func _count_non_empty_cells(probe: Dictionary, key: String, semantic_registry: Dictionary) -> int:
	var image := _load_source_image(probe, key, semantic_registry)
	if image.is_empty():
		return 0
	return _non_empty_cells(image).size()


func _copy_selected_sources(source_info: Dictionary, output_root: String, semantic_registry: Dictionary) -> Dictionary:
	var copied := {}
	var textures_root := output_root.path_join("textures/source")
	_ensure_dir(ProjectSettings.globalize_path(textures_root))

	if semantic_registry.get("ok", false):
		var textures_by_key: Dictionary = semantic_registry.get("textures_by_key", {})
		for source_key in REQUIRED_SOURCE_FILES.keys():
			if textures_by_key.has(source_key):
				var texture_info: Dictionary = textures_by_key[source_key]
				var write_result := _write_texture_asset(textures_root, texture_info)
				if not write_result.get("ok", false):
					return write_result
				copied[source_key] = write_result.get("res_path", "")
		for optional_key in OPTIONAL_SOURCE_FILES.keys():
			if textures_by_key.has(optional_key):
				var optional_info: Dictionary = textures_by_key[optional_key]
				var optional_result := _write_texture_asset(textures_root, optional_info)
				if not optional_result.get("ok", false):
					return optional_result
				copied[optional_key] = optional_result.get("res_path", "")

	if copied.is_empty():
		var resolved: Dictionary = source_info.get("resolved_paths", {})
		if source_info.get("source_kind", "") == "zip":
			var reader := ZIPReader.new()
			var err := reader.open(str(source_info.get("source_path", "")))
			if err != OK:
				return {
					"ok": false,
					"error": "Could not open zip for texture copy.",
				}
			for key in resolved.keys():
				var zip_entry := str(resolved[key])
				var file_name := zip_entry.get_file()
				var dest_rel := textures_root.path_join(file_name)
				if zip_entry.contains("/Extra/"):
					dest_rel = textures_root.path_join("Extra").path_join(file_name)
				var dest_abs := ProjectSettings.globalize_path(dest_rel)
				_ensure_dir(dest_abs.get_base_dir())
				var file := FileAccess.open(dest_abs, FileAccess.WRITE)
				if file == null:
					reader.close()
					return {
						"ok": false,
						"error": "Could not write %s" % dest_rel,
					}
				file.store_buffer(reader.read_file(zip_entry))
				file.close()
				copied[key] = dest_rel
			reader.close()
		else:
			for key in resolved.keys():
				var source_abs := str(resolved[key])
				var dest_rel_folder := textures_root.path_join(source_abs.get_file())
				if source_abs.contains("/Extra/"):
					dest_rel_folder = textures_root.path_join("Extra").path_join(source_abs.get_file())
				var dest_abs_folder := ProjectSettings.globalize_path(dest_rel_folder)
				_ensure_dir(dest_abs_folder.get_base_dir())
				var copy_err := DirAccess.copy_absolute(source_abs, dest_abs_folder)
				if copy_err != OK:
					return {
						"ok": false,
						"error": "Could not copy %s" % source_abs,
					}
				copied[key] = dest_rel_folder

	return {
		"ok": true,
		"copied": copied,
	}


func _write_texture_asset(textures_root: String, texture_info: Dictionary) -> Dictionary:
	var bytes: PackedByteArray = texture_info.get("asset_bytes", PackedByteArray())
	if bytes.is_empty():
		return {
			"ok": false,
			"error": "Missing texture bytes for %s" % str(texture_info.get("asset_path", "")),
		}
	var source_key := str(texture_info.get("source_key", ""))
	var file_name := str(texture_info.get("asset_name", ""))
	var dest_rel := textures_root.path_join(file_name)
	if source_key.begins_with("extra_"):
		dest_rel = textures_root.path_join("Extra").path_join(file_name)
	var dest_abs := ProjectSettings.globalize_path(dest_rel)
	_ensure_dir(dest_abs.get_base_dir())
	var file := FileAccess.open(dest_abs, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"error": "Could not write texture asset: %s" % dest_rel,
		}
	file.store_buffer(bytes)
	file.close()
	return {
		"ok": true,
		"res_path": dest_rel,
	}


func _generate_tileset(spec: Dictionary, copied_res_paths: Dictionary) -> Dictionary:
	var source_key := str(spec.get("key", ""))
	var texture_res_path := str(copied_res_paths.get(source_key, ""))
	if texture_res_path.is_empty():
		return {"ok": false, "error": "Missing texture for tileset %s" % source_key}

	var texture := _external_texture_resource(texture_res_path)
	if texture == null:
		return {"ok": false, "error": "Could not load texture resource for %s" % texture_res_path}

	var image := Image.load_from_file(ProjectSettings.globalize_path(texture_res_path))
	if image.is_empty():
		return {"ok": false, "error": "Could not read image bytes for %s" % texture_res_path}

	var tileset := TileSet.new()
	tileset.tile_size = TILE_SIZE
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = texture
	atlas_source.texture_region_size = TILE_SIZE

	var image_size := image.get_size()
	for y in range(image_size.y / TILE_SIZE.y):
		for x in range(image_size.x / TILE_SIZE.x):
			if _cell_has_alpha(image, x, y):
				atlas_source.create_tile(Vector2i(x, y))
	tileset.add_source(atlas_source, 0)

	var output_path := _active_output_root.path_join(str(spec.get("output", "")))
	var save_err := _save_resource(tileset, output_path)
	if save_err != OK:
		return {"ok": false, "error": "Failed to save tileset: %s" % output_path}
	tileset.resource_path = output_path

	return {
		"ok": true,
		"path": output_path,
		"resource": tileset,
		"catalog_entry": {
			"name": str(spec.get("name", "")),
			"path": output_path,
			"tile_count": _non_empty_cells(image).size(),
		},
	}


func _generate_semantic_prefab_collections(semantic_registry: Dictionary, copied_res_paths: Dictionary) -> Dictionary:
	var paths := []
	var catalog_entries := []
	var catalog_prefabs := []
	var prefab_entries := []
	var editor_only_entries := []
	var family_to_paths := {
		"plants": [],
		"props": [],
		"struct": [],
		"player": [],
	}
	var tier_counts := {
		"supported_static": 0,
		"approximated": 0,
		"manual_behavior": 0,
		"unresolved_or_skipped": 0,
	}
	var sprites: Dictionary = semantic_registry.get("sprites", {})
	var textures_by_guid := semantic_registry.get("textures_by_guid", {})
	var texture_res_paths_by_guid := {}
	for guid_variant in textures_by_guid.keys():
		var guid := str(guid_variant)
		var texture_info: Dictionary = textures_by_guid[guid]
		var source_key := str(texture_info.get("source_key", ""))
		if copied_res_paths.has(source_key):
			texture_res_paths_by_guid[guid] = copied_res_paths[source_key]

	for prefab_variant in semantic_registry.get("prefabs", []):
		var prefab: Dictionary = prefab_variant
		var tier := str(prefab.get("support_tier", "unresolved_or_skipped"))
		var actual_tier := tier
		var scene_path = null
		var report_reasons: Array = Array(prefab.get("reason_tokens", [])).duplicate()
		var report_details: Dictionary = Dictionary(prefab.get("report_details", {})).duplicate(true)
		var next_step := str(prefab.get("next_step", ""))
		var family := str(prefab.get("family", "props"))
		if tier != "unresolved_or_skipped":
			var scene_result := _generate_semantic_prefab_scene(prefab, sprites, texture_res_paths_by_guid)
			if scene_result.get("ok", false):
				scene_path = scene_result.get("path", "")
				paths.append(scene_path)
				family_to_paths[family].append(scene_path)
				catalog_prefabs.append({
					"prefab_name": str(prefab.get("name", "")),
					"family": family,
					"origin": "semantic_prefab",
					"path": scene_path,
					"tier": actual_tier,
				})
			else:
				actual_tier = "unresolved_or_skipped"
				report_reasons.append("scene_generation_failed")
				report_details["scene_generation_error"] = str(scene_result.get("error", "Unknown semantic scene generation failure"))
				next_step = "Inspect the importer error and repair the semantic mapping or use fallback atlas scenes for this asset."
		if tier_counts.has(actual_tier):
			tier_counts[actual_tier] += 1
		else:
			tier_counts["unresolved_or_skipped"] += 1
		prefab_entries.append(_semantic_prefab_report_entry(prefab, actual_tier, scene_path, report_reasons, report_details, next_step))

	for prefab_variant in semantic_registry.get("editor_only_prefabs", []):
		var prefab: Dictionary = prefab_variant
		var report_reasons: Array = Array(prefab.get("reason_tokens", [])).duplicate()
		if not report_reasons.has("editor_only_unity_asset"):
			report_reasons.append("editor_only_unity_asset")
		editor_only_entries.append(_semantic_prefab_report_entry(
			prefab,
			"editor_only",
			null,
			report_reasons,
			Dictionary(prefab.get("report_details", {})).duplicate(true),
			"Ignore this Unity editor asset for normal map authoring and use the generated TileSets instead."
		))

	var families := ["plants", "props", "struct", "player"]
	for family in families:
		var family_paths: Array = family_to_paths.get(family, [])
		if family_paths.is_empty():
			continue
		catalog_entries.append({
			"name": family,
			"path": _active_output_root.path_join("scenes/prefabs/%s" % family),
			"count": family_paths.size(),
			"origin": "semantic_prefab",
		})

	return {
		"ok": true,
		"paths": paths,
		"catalog_entries": catalog_entries,
		"catalog_prefabs": catalog_prefabs,
		"family_to_paths": family_to_paths,
		"tier_counts": tier_counts,
		"prefab_entries": prefab_entries,
		"editor_only_entries": editor_only_entries,
	}


func _semantic_prefab_report_entry(prefab: Dictionary, actual_tier: String, scene_path, reasons: Array, details: Dictionary, next_step: String) -> Dictionary:
	return {
		"prefab_name": str(prefab.get("name", "")),
		"unity_asset_path": str(prefab.get("path", "")),
		"family": str(prefab.get("family", "props")),
		"tier": actual_tier,
		"scene_path": scene_path,
		"reasons": reasons,
		"details": details,
		"behavior_hints": prefab.get("behavior_hints", []),
		"next_step": next_step,
	}


func _generate_semantic_prefab_scene(prefab: Dictionary, sprites: Dictionary, texture_res_paths_by_guid: Dictionary) -> Dictionary:
	var family := str(prefab.get("family", "props"))
	var output_dir := _active_output_root.path_join("scenes/prefabs/%s" % family)
	_ensure_dir(ProjectSettings.globalize_path(output_dir))

	var root_node := _build_semantic_prefab_root(prefab, sprites, texture_res_paths_by_guid)
	if root_node == null:
		return {"ok": false, "error": "Prefab has no roots: %s" % str(prefab.get("name", ""))}

	_assign_scene_owner(root_node, root_node)

	var packed := PackedScene.new()
	var pack_err := packed.pack(root_node)
	if pack_err != OK:
		root_node.free()
		return {"ok": false, "error": "Could not pack semantic prefab %s" % str(prefab.get("name", ""))}

	var scene_path := output_dir.path_join("%s.tscn" % _sanitize_filename(str(prefab.get("name", "prefab"))))
	var save_err := _save_resource(packed, scene_path)
	if save_err != OK:
		root_node.free()
		return {"ok": false, "error": "Could not save semantic prefab %s" % scene_path}
	packed.resource_path = scene_path
	root_node.free()
	return {
		"ok": true,
		"path": scene_path,
	}


func _build_semantic_prefab_root(prefab: Dictionary, sprites: Dictionary, texture_res_paths_by_guid: Dictionary) -> Node2D:
	var root_ids: Array = prefab.get("root_ids", [])
	var nodes: Dictionary = prefab.get("nodes", {})
	if root_ids.is_empty() or nodes.is_empty():
		return null

	var root_node := Node2D.new()
	root_node.name = str(prefab.get("name", "Prefab"))
	root_node.set_meta("semantic_origin", "unity_prefab")
	root_node.set_meta("unity_path", str(prefab.get("path", "")))
	root_node.set_meta("support_tier", str(prefab.get("support_tier", "")))
	root_node.set_meta("unsupported_components", prefab.get("unsupported_components", []))

	if root_ids.size() == 1 and nodes.has(str(root_ids[0])):
		var root_desc: Dictionary = nodes[str(root_ids[0])]
		_apply_game_object_to_node(root_node, root_desc, root_node, sprites, texture_res_paths_by_guid, true)
		for child_id_variant in root_desc.get("children", []):
			var child_id := str(child_id_variant)
			if nodes.has(child_id):
				root_node.add_child(_build_game_object_subtree(nodes[child_id], nodes, sprites, texture_res_paths_by_guid))
	else:
		for root_id_variant in root_ids:
			var root_id := str(root_id_variant)
			if nodes.has(root_id):
				root_node.add_child(_build_game_object_subtree(nodes[root_id], nodes, sprites, texture_res_paths_by_guid))

	if not Array(prefab.get("behavior_hints", [])).is_empty():
		root_node.set_meta("cainos_behavior_hints", prefab.get("behavior_hints", []))

	return root_node


func _build_game_object_subtree(node_desc: Dictionary, all_nodes: Dictionary, sprites: Dictionary, texture_res_paths_by_guid: Dictionary) -> Node2D:
	var node := Node2D.new()
	node.name = str(node_desc.get("name", "Node"))
	_apply_game_object_to_node(node, node_desc, null, sprites, texture_res_paths_by_guid, false)
	for child_id_variant in node_desc.get("children", []):
		var child_id := str(child_id_variant)
		if all_nodes.has(child_id):
			node.add_child(_build_game_object_subtree(all_nodes[child_id], all_nodes, sprites, texture_res_paths_by_guid))
	return node


func _apply_game_object_to_node(node: Node2D, node_desc: Dictionary, scene_root: Node2D, sprites: Dictionary, texture_res_paths_by_guid: Dictionary, is_scene_root: bool) -> void:
	var ppu := _node_pixels_per_unit(node_desc, sprites)
	var local_position: Vector3 = node_desc.get("local_position", Vector3.ZERO)
	if not is_scene_root:
		node.position = Vector2(local_position.x * ppu, -local_position.y * ppu)

	for renderer_variant in node_desc.get("sprite_renderers", []):
		var renderer: Dictionary = renderer_variant
		var sprite_key := "%s:%s" % [str(renderer.get("sprite_guid", "")), str(renderer.get("sprite_file_id", ""))]
		if not sprites.has(sprite_key):
			continue
		var sprite_desc: Dictionary = sprites[sprite_key]
		var texture_guid := str(sprite_desc.get("texture_guid", ""))
		if not texture_res_paths_by_guid.has(texture_guid):
			continue
		var texture_res_path := str(texture_res_paths_by_guid.get(texture_guid, ""))
		var texture := _external_texture_resource(texture_res_path)
		if texture == null:
			continue
		var sprite_node := Sprite2D.new()
		sprite_node.name = "%s Sprite" % str(node_desc.get("name", "Visual"))
		sprite_node.texture = texture
		sprite_node.region_enabled = true
		sprite_node.region_rect = sprite_desc.get("rect", Rect2())
		sprite_node.centered = false
		sprite_node.position = _sprite_top_left_offset(sprite_desc)
		sprite_node.flip_h = bool(renderer.get("flip_x", false))
		sprite_node.flip_v = bool(renderer.get("flip_y", false))
		sprite_node.z_index = int(renderer.get("sorting_order", 0))
		sprite_node.texture_filter = TEXTURE_FILTER_NEAREST
		sprite_node.set_meta("sorting_layer_id", int(renderer.get("sorting_layer_id", 0)))
		sprite_node.set_meta("sprite_name", str(sprite_desc.get("name", "")))
		node.add_child(sprite_node)

	var collider_index := 0
	for collider_variant in node_desc.get("box_colliders", []):
		var collider: Dictionary = collider_variant
		var owner: Node2D = Area2D.new() if collider.get("is_trigger", false) else StaticBody2D.new()
		owner.name = "BoxCollider_%d" % collider_index
		owner.position = _unity_vector2_to_godot_px(collider.get("offset", Vector2.ZERO), ppu)
		var shape := RectangleShape2D.new()
		shape.size = collider.get("size", Vector2.ZERO) * ppu
		var shape_node := CollisionShape2D.new()
		shape_node.shape = shape
		owner.add_child(shape_node)
		node.add_child(owner)
		collider_index += 1

	for collider_variant in node_desc.get("edge_colliders", []):
		var collider: Dictionary = collider_variant
		var points: Array = collider.get("points", [])
		if points.size() != 2:
			continue
		var owner: Node2D = Area2D.new() if collider.get("is_trigger", false) else StaticBody2D.new()
		owner.name = "EdgeCollider_%d" % collider_index
		owner.position = _unity_vector2_to_godot_px(collider.get("offset", Vector2.ZERO), ppu)
		var shape := SegmentShape2D.new()
		shape.a = _unity_vector2_to_godot_px(points[0], ppu)
		shape.b = _unity_vector2_to_godot_px(points[1], ppu)
		var shape_node := CollisionShape2D.new()
		shape_node.shape = shape
		owner.add_child(shape_node)
		node.add_child(owner)
		collider_index += 1

	if not node_desc.get("mono_behaviours", []).is_empty():
		node.set_meta("unity_mono_behaviours", node_desc.get("mono_behaviours", []))
	if not node_desc.get("behavior_hints", []).is_empty():
		node.set_meta("cainos_behavior_hints", node_desc.get("behavior_hints", []))


func _node_pixels_per_unit(node_desc: Dictionary, sprites: Dictionary) -> float:
	for renderer_variant in node_desc.get("sprite_renderers", []):
		var renderer: Dictionary = renderer_variant
		var sprite_key := "%s:%s" % [str(renderer.get("sprite_guid", "")), str(renderer.get("sprite_file_id", ""))]
		if sprites.has(sprite_key):
			return float(sprites[sprite_key].get("pixels_per_unit", DEFAULT_PPU))
	return DEFAULT_PPU


func _sprite_top_left_offset(sprite_desc: Dictionary) -> Vector2:
	var rect: Rect2 = sprite_desc.get("rect", Rect2())
	var pivot: Vector2 = sprite_desc.get("pivot", Vector2(0.5, 0.5))
	var pivot_x := rect.size.x * pivot.x
	var pivot_y := rect.size.y * pivot.y
	return Vector2(-pivot_x, -(rect.size.y - pivot_y))


func _unity_vector2_to_godot_px(value: Vector2, ppu: float) -> Vector2:
	return Vector2(value.x * ppu, -value.y * ppu)


func _generate_sprite_scene_collection(collection_name: String, texture_res_path: String, output_dir_rel: String, prefix: String) -> Dictionary:
	if texture_res_path.is_empty():
		return {"ok": true, "paths": [], "catalog_entry": {"name": collection_name, "path": "", "count": 0, "origin": "fallback_atlas"}}

	var texture := _external_texture_resource(texture_res_path)
	if texture == null:
		return {"ok": false, "error": "Could not load texture for scene collection: %s" % texture_res_path}
	var image := Image.load_from_file(ProjectSettings.globalize_path(texture_res_path))
	if image.is_empty():
		return {"ok": false, "error": "Could not load image for scene collection: %s" % texture_res_path}

	var output_dir := _active_output_root.path_join(output_dir_rel)
	_ensure_dir(ProjectSettings.globalize_path(output_dir))

	var paths := []
	for coords in _non_empty_cells(image):
		var root := Node2D.new()
		root.name = "%s_%02d_%02d" % [prefix, coords.x, coords.y]
		root.set_meta("atlas_source", texture_res_path)
		root.set_meta("atlas_coords", coords)

		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.region_enabled = true
		sprite.region_rect = Rect2(coords * TILE_SIZE, TILE_SIZE)
		sprite.centered = false
		sprite.texture_filter = TEXTURE_FILTER_NEAREST
		root.add_child(sprite)
		_assign_scene_owner(root, root)

		var packed := PackedScene.new()
		var pack_err := packed.pack(root)
		if pack_err != OK:
			root.free()
			return {"ok": false, "error": "Could not pack scene collection %s" % collection_name}
		var scene_path := output_dir.path_join("%s_%02d_%02d.tscn" % [prefix, coords.x, coords.y])
		var save_err := _save_resource(packed, scene_path)
		if save_err != OK:
			root.free()
			return {"ok": false, "error": "Could not save scene %s" % scene_path}
		paths.append(scene_path)
		root.free()

	return {
		"ok": true,
		"paths": paths,
		"catalog_entry": {
			"name": collection_name,
			"path": output_dir,
			"count": paths.size(),
			"origin": "fallback_atlas",
		},
	}


func _generate_player_helper_assets(player_texture_res_path: String) -> Dictionary:
	var texture := _external_texture_resource(player_texture_res_path)
	if texture == null:
		return {"ok": false, "error": "Could not load player texture resource."}
	var image := Image.load_from_file(ProjectSettings.globalize_path(player_texture_res_path))
	if image.is_empty():
		return {"ok": false, "error": "Could not load player texture image."}

	var output_dir := _active_output_root.path_join("helpers/player")
	_ensure_dir(ProjectSettings.globalize_path(output_dir))

	var frames := SpriteFrames.new()
	var rows := _non_empty_cells_by_row(image)
	for row_key_variant in rows.keys():
		var row_key := int(row_key_variant)
		var animation_name := "sheet_row_%d" % row_key
		frames.add_animation(animation_name)
		for coords_variant in rows[row_key]:
			var coords: Vector2i = coords_variant
			var atlas_texture := AtlasTexture.new()
			atlas_texture.atlas = texture
			atlas_texture.region = Rect2(coords * TILE_SIZE, TILE_SIZE)
			frames.add_frame(animation_name, atlas_texture)
		frames.set_animation_loop(animation_name, true)
		frames.set_animation_speed(animation_name, 8.0)

	var frames_path := output_dir.path_join("basic_player_frames.tres")
	if _save_resource(frames, frames_path) != OK:
		return {"ok": false, "error": "Could not save player SpriteFrames."}
	frames.resource_path = frames_path

	var root := Node2D.new()
	root.name = "basic_player_helper"
	var animated := AnimatedSprite2D.new()
	animated.name = "AnimatedSprite2D"
	animated.sprite_frames = frames
	if frames.get_animation_names().size() > 0:
		animated.animation = frames.get_animation_names()[0]
	animated.texture_filter = TEXTURE_FILTER_NEAREST
	root.add_child(animated)
	_assign_scene_owner(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return {"ok": false, "error": "Could not pack player helper scene."}
	var scene_path := output_dir.path_join("basic_player_helper.tscn")
	if _save_resource(packed, scene_path) != OK:
		root.free()
		return {"ok": false, "error": "Could not save player helper scene."}
	packed.resource_path = scene_path
	root.free()

	return {
		"ok": true,
		"paths": [frames_path, scene_path],
		"packed_scene": packed,
		"frames": frames,
		"catalog_entry": {
			"name": "player_helpers",
			"path": output_dir,
			"count": 2,
			"origin": "helper",
		},
	}


func _generate_preview_scene(generated_tilesets: Dictionary, copied_res_paths: Dictionary, semantic_registry: Dictionary, semantic_generated: Dictionary, player_helpers: Dictionary) -> Dictionary:
	var helper_entries := []
	var helper_paths := []

	var preview := _build_preview_map_scene(generated_tilesets, copied_res_paths, semantic_registry, player_helpers)
	if not preview.get("ok", false):
		return preview
	helper_paths.append(preview.get("path", ""))
	helper_entries.append(preview.get("catalog_entry", {}))

	var catalog := _build_prefab_catalog_scene(semantic_registry, copied_res_paths)
	if not catalog.get("ok", false):
		return catalog
	helper_paths.append(catalog.get("path", ""))
	helper_entries.append(catalog.get("catalog_entry", {}))

	return {
		"ok": true,
		"paths": helper_paths,
		"catalog_entries": helper_entries,
	}


func _build_preview_map_scene(generated_tilesets: Dictionary, copied_res_paths: Dictionary, semantic_registry: Dictionary, player_helpers: Dictionary) -> Dictionary:
	var root := Node2D.new()
	root.name = "basic_preview_map"

	var grass_tileset := generated_tilesets.get("tileset_grass") as TileSet
	var stone_tileset := generated_tilesets.get("tileset_stone_ground") as TileSet
	var wall_tileset := generated_tilesets.get("tileset_wall") as TileSet
	var struct_tileset := generated_tilesets.get("struct") as TileSet
	if grass_tileset != null:
		var grass := _make_tile_layer("Grass", grass_tileset, 0)
		_fill_preview_layer(grass, 0)
		root.add_child(grass)
	if stone_tileset != null:
		var stone := _make_tile_layer("Stone", stone_tileset, 1)
		_fill_preview_layer(stone, 1)
		root.add_child(stone)
	if wall_tileset != null:
		var wall := _make_tile_layer("Wall", wall_tileset, 2)
		_fill_preview_layer(wall, 2)
		root.add_child(wall)
	if struct_tileset != null:
		var struct_layer := _make_tile_layer("Struct", struct_tileset, 3)
		_fill_preview_layer(struct_layer, 3)
		root.add_child(struct_layer)

	var semantic_preview := _build_semantic_preview_lookup(semantic_registry, copied_res_paths)
	_instantiate_first_semantic_prefab(root, semantic_preview, "props", Vector2(48, 64))
	_instantiate_first_semantic_prefab(root, semantic_preview, "plants", Vector2(112, 72))
	_instantiate_first_semantic_prefab(root, semantic_preview, "struct", Vector2(176, 96))
	if not _instantiate_first_semantic_prefab(root, semantic_preview, "player", Vector2(240, 80)):
		var player_scene := player_helpers.get("packed_scene") as PackedScene
		if player_scene != null:
			var player_instance := player_scene.instantiate()
			if player_instance is Node2D:
				player_instance.position = Vector2(240, 80)
			root.add_child(player_instance)

	var camera := Camera2D.new()
	camera.position = Vector2(128, 96)
	camera.zoom = Vector2(1.2, 1.2)
	root.add_child(camera)
	_assign_scene_owner(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return {"ok": false, "error": "Could not pack preview map scene."}
	var scene_path := _active_output_root.path_join("scenes/helpers/basic_preview_map.tscn")
	if _save_resource(packed, scene_path) != OK:
		root.free()
		return {"ok": false, "error": "Could not save preview map scene."}
	root.free()
	return {
		"ok": true,
		"path": scene_path,
		"catalog_entry": {
			"name": "basic_preview_map",
			"path": scene_path,
		},
	}


func _build_prefab_catalog_scene(semantic_registry: Dictionary, copied_res_paths: Dictionary) -> Dictionary:
	var root := Node2D.new()
	root.name = "basic_prefab_catalog"

	var semantic_preview := _build_semantic_preview_lookup(semantic_registry, copied_res_paths)
	var categories := [
		{"name": "plants", "family": "plants"},
		{"name": "props", "family": "props"},
		{"name": "struct", "family": "struct"},
	]
	var origin := Vector2(32, 48)
	for index in range(categories.size()):
		var category: Dictionary = categories[index]
		var family := str(category.get("family", ""))
		var prefabs: Array = semantic_preview.get(family, [])
		var row_y := origin.y + index * 96.0
		for path_index in range(min(prefabs.size(), 4)):
			var instance_position := Vector2(origin.x + path_index * 80.0, row_y)
			_instantiate_specific_semantic_prefab(root, semantic_preview, prefabs[path_index], instance_position)

	_assign_scene_owner(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return {"ok": false, "error": "Could not pack prefab catalog scene."}
	var scene_path := _active_output_root.path_join("scenes/helpers/basic_prefab_catalog.tscn")
	if _save_resource(packed, scene_path) != OK:
		root.free()
		return {"ok": false, "error": "Could not save prefab catalog scene."}
	root.free()
	return {
		"ok": true,
		"path": scene_path,
		"catalog_entry": {
			"name": "basic_prefab_catalog",
			"path": scene_path,
		},
	}


func _build_semantic_preview_lookup(semantic_registry: Dictionary, copied_res_paths: Dictionary) -> Dictionary:
	var preview := {
		"plants": [],
		"props": [],
		"struct": [],
		"player": [],
		"sprites": semantic_registry.get("sprites", {}),
		"texture_res_paths_by_guid": {},
	}
	if not semantic_registry.get("ok", false):
		return preview

	var textures_by_guid: Dictionary = semantic_registry.get("textures_by_guid", {})
	for guid_variant in textures_by_guid.keys():
		var guid := str(guid_variant)
		var texture_info: Dictionary = textures_by_guid[guid]
		var source_key := str(texture_info.get("source_key", ""))
		if copied_res_paths.has(source_key):
			preview["texture_res_paths_by_guid"][guid] = copied_res_paths[source_key]

	for prefab_variant in semantic_registry.get("prefabs", []):
		var prefab: Dictionary = prefab_variant
		var tier := str(prefab.get("support_tier", ""))
		if tier == "unresolved_or_skipped":
			continue
		var family := str(prefab.get("family", "props"))
		if preview.has(family):
			preview[family].append(prefab)

	return preview


func _instantiate_first_semantic_prefab(parent: Node, semantic_preview: Dictionary, family: String, position: Vector2) -> bool:
	var prefabs: Array = semantic_preview.get(family, [])
	if prefabs.is_empty():
		return false
	return _instantiate_specific_semantic_prefab(parent, semantic_preview, prefabs[0], position)


func _instantiate_specific_semantic_prefab(parent: Node, semantic_preview: Dictionary, prefab: Dictionary, position: Vector2) -> bool:
	var sprites: Dictionary = semantic_preview.get("sprites", {})
	var texture_res_paths_by_guid: Dictionary = semantic_preview.get("texture_res_paths_by_guid", {})
	var root := _build_semantic_prefab_root(prefab, sprites, texture_res_paths_by_guid)
	if root == null:
		return false
	root.position = position
	parent.add_child(root)
	return true


func _assign_scene_owner(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_assign_scene_owner(child, owner)


func _fill_preview_layer(layer: TileMapLayer, z_index: int) -> void:
	if layer.tile_set == null or layer.tile_set.get_source_count() == 0:
		return
	var source_id := layer.tile_set.get_source_id(0)
	for x in range(6):
		for y in range(4):
			layer.set_cell(Vector2i(x, y), source_id, Vector2i(0, 0))
	if z_index == 1:
		layer.set_cell(Vector2i(2, 2), source_id, Vector2i(1, 0))
		layer.set_cell(Vector2i(3, 2), source_id, Vector2i(2, 0))
	if z_index == 2:
		for x in range(6):
			layer.set_cell(Vector2i(x, 0), source_id, Vector2i(0, 0))
	if z_index == 3:
		layer.set_cell(Vector2i(4, 1), source_id, Vector2i(0, 0))


func _make_tile_layer(name: String, tileset: TileSet, z_index: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = name
	layer.tile_set = tileset
	layer.z_index = z_index
	layer.texture_filter = TEXTURE_FILTER_NEAREST
	return layer


func _write_reports(output_root: String, manifest: Dictionary, compatibility: Array, catalog: Dictionary) -> Dictionary:
	var reports_root := output_root.path_join("reports")
	_ensure_dir(ProjectSettings.globalize_path(reports_root))
	var compatibility_report := _compatibility_report_data(manifest, compatibility, catalog)

	var manifest_path := reports_root.path_join("import_manifest.json")
	if _write_text_file(manifest_path, JSON.stringify(manifest, "\t", true)) != OK:
		return {"ok": false, "error": "Could not write manifest."}

	var compatibility_json := reports_root.path_join("compatibility_report.json")
	if _write_text_file(compatibility_json, JSON.stringify(compatibility_report, "\t", true)) != OK:
		return {"ok": false, "error": "Could not write compatibility report JSON."}

	var compatibility_md := reports_root.path_join("compatibility_report.md")
	if _write_text_file(compatibility_md, _compatibility_markdown(compatibility_report)) != OK:
		return {"ok": false, "error": "Could not write compatibility report markdown."}

	var catalog_json := reports_root.path_join("asset_catalog.json")
	if _write_text_file(catalog_json, JSON.stringify(catalog, "\t", true)) != OK:
		return {"ok": false, "error": "Could not write asset catalog JSON."}

	var catalog_md := reports_root.path_join("asset_catalog.md")
	if _write_text_file(catalog_md, _catalog_markdown(catalog)) != OK:
		return {"ok": false, "error": "Could not write asset catalog markdown."}

	return {
		"ok": true,
		"manifest_path": manifest_path,
		"report_markdown_path": compatibility_md,
		"catalog_markdown_path": catalog_md,
		"written_files": 5,
	}


func _compatibility_report_data(manifest: Dictionary, legacy_summary: Array, catalog: Dictionary) -> Dictionary:
	var prefabs: Array = manifest.get("semantic_prefabs", [])
	var editor_only_prefabs: Array = manifest.get("editor_only_prefabs", [])
	var tiers := {
		"supported_static": [],
		"approximated": [],
		"manual_behavior": [],
		"unresolved_or_skipped": [],
	}
	for entry_variant in prefabs:
		var entry: Dictionary = entry_variant
		var tier := str(entry.get("tier", "unresolved_or_skipped"))
		if not tiers.has(tier):
			tier = "unresolved_or_skipped"
		var tier_entries: Array = tiers.get(tier, [])
		tier_entries.append(entry)
		tiers[tier] = tier_entries
	return {
		"format_version": REPORT_FORMAT_VERSION,
		"pack_id": manifest.get("pack_id", PACK_ID),
		"status_legend": {
			"supported": "imported directly into usable Godot assets",
			"approximated": "usable, but not a one-to-one Unity mapping",
			"manual": "requires user follow-up in Godot",
			"unsupported": "not converted in this milestone",
		},
		"summary": {
			"semantic_available": manifest.get("inventory", {}).get("semantic_available", false),
			"semantic_enabled": manifest.get("profile", {}).get("prefer_semantic_prefabs", true),
			"semantic_prefab_count": prefabs.size(),
			"supported_static_prefabs": manifest.get("semantic_summary", {}).get("supported_static", 0),
			"approximated_prefabs": manifest.get("semantic_summary", {}).get("approximated", 0),
			"manual_behavior_prefabs": manifest.get("semantic_summary", {}).get("manual_behavior", 0),
			"unresolved_or_skipped_prefabs": manifest.get("semantic_summary", {}).get("unresolved_or_skipped", 0),
			"editor_only_prefabs": editor_only_prefabs.size(),
			"fallback_collections": len(catalog.get("fallback_collections", [])),
		},
		"legacy_summary": legacy_summary,
		"tiers": tiers,
		"editor_only_prefabs": editor_only_prefabs,
		"fallback_collections": catalog.get("fallback_collections", []),
	}


func _compatibility_markdown(compatibility_report: Dictionary) -> String:
	var lines := [
		"# Cainos Basic Compatibility Report",
		"",
		"Generated by the Cainos Basic Importer. Status values:",
		"- supported: %s" % compatibility_report.get("status_legend", {}).get("supported", ""),
		"- approximated: %s" % compatibility_report.get("status_legend", {}).get("approximated", ""),
		"- manual: %s" % compatibility_report.get("status_legend", {}).get("manual", ""),
		"- unsupported: %s" % compatibility_report.get("status_legend", {}).get("unsupported", ""),
		"",
	]
	var summary: Dictionary = compatibility_report.get("summary", {})
	lines.append("## Summary")
	lines.append("- Semantic available: %s" % str(summary.get("semantic_available", false)))
	lines.append("- Semantic enabled in this run: %s" % str(summary.get("semantic_enabled", true)))
	lines.append("- Supported static prefabs: %s" % str(summary.get("supported_static_prefabs", 0)))
	lines.append("- Approximated prefabs: %s" % str(summary.get("approximated_prefabs", 0)))
	lines.append("- Manual behavior prefabs: %s" % str(summary.get("manual_behavior_prefabs", 0)))
	lines.append("- Unresolved or skipped prefabs: %s" % str(summary.get("unresolved_or_skipped_prefabs", 0)))
	lines.append("- Unity editor-only prefabs: %s" % str(summary.get("editor_only_prefabs", 0)))
	lines.append("- Fallback collections: %s" % str(summary.get("fallback_collections", 0)))
	lines.append("")
	lines.append("## Legacy Summary")
	for item_variant in compatibility_report.get("legacy_summary", []):
		var item: Dictionary = item_variant
		lines.append("### %s" % item.get("title", ""))
		lines.append("- Status: %s" % item.get("status", ""))
		lines.append("- Detail: %s" % item.get("detail", ""))
		lines.append("- Next: %s" % item.get("next", ""))
		lines.append("")
	var tier_titles := {
		"supported_static": "Supported Static Prefabs",
		"approximated": "Approximated Prefabs",
		"manual_behavior": "Manual Behavior Prefabs",
		"unresolved_or_skipped": "Unresolved Or Skipped Prefabs",
	}
	for tier_key in ["supported_static", "approximated", "manual_behavior", "unresolved_or_skipped"]:
		var tier_entries: Array = compatibility_report.get("tiers", {}).get(tier_key, [])
		lines.append("## %s (%d)" % [tier_titles.get(tier_key, tier_key), tier_entries.size()])
		if tier_entries.is_empty():
			lines.append("- None")
			lines.append("")
			continue
		for entry_variant in tier_entries:
			var entry: Dictionary = entry_variant
			var scene_path = entry.get("scene_path", null)
			var scene_path_text := "(no scene generated)" if scene_path == null else str(scene_path)
			var reasons_text := _join_reason_tokens(entry.get("reasons", []))
			var detail_text := _prefab_detail_summary(entry.get("details", {}))
			lines.append("- %s [%s] -> %s | reasons: %s | next: %s%s" % [
				entry.get("prefab_name", ""),
				entry.get("family", ""),
				scene_path_text,
				reasons_text,
				entry.get("next_step", ""),
				"" if detail_text.is_empty() else " | details: %s" % detail_text
			])
		lines.append("")
	var editor_only_prefabs: Array = compatibility_report.get("editor_only_prefabs", [])
	lines.append("## Unity Editor-Only Assets (%d)" % editor_only_prefabs.size())
	if editor_only_prefabs.is_empty():
		lines.append("- None")
	else:
		for entry_variant in editor_only_prefabs:
			var entry: Dictionary = entry_variant
			var reasons_text := _join_reason_tokens(entry.get("reasons", []))
			var detail_text := _prefab_detail_summary(entry.get("details", {}))
			lines.append("- %s -> %s | reasons: %s | next: %s%s" % [
				entry.get("prefab_name", ""),
				entry.get("unity_asset_path", ""),
				reasons_text,
				entry.get("next_step", ""),
				"" if detail_text.is_empty() else " | details: %s" % detail_text
			])
	lines.append("")
	var fallback_collections: Array = compatibility_report.get("fallback_collections", [])
	lines.append("## Fallback Collections (%d)" % fallback_collections.size())
	if fallback_collections.is_empty():
		lines.append("- None")
	else:
		for entry_variant in fallback_collections:
			var entry: Dictionary = entry_variant
			lines.append("- %s: %s (%s items)" % [entry.get("name", ""), entry.get("path", ""), entry.get("count", 0)])
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
		lines.append("- %s: %s (%s items, origin=%s)" % [collection.get("name", ""), collection.get("path", ""), collection.get("count", 0), collection.get("origin", "")])
	lines.append("")
	lines.append("## Prefabs")
	for prefab_variant in catalog.get("prefabs", []):
		var prefab: Dictionary = prefab_variant
		lines.append("- %s [%s, tier=%s, origin=%s]: %s" % [prefab.get("prefab_name", ""), prefab.get("family", ""), prefab.get("tier", ""), prefab.get("origin", ""), prefab.get("path", "")])
	lines.append("")
	lines.append("## Helper Scenes")
	for helper_variant in catalog.get("helper_scenes", []):
		var helper: Dictionary = helper_variant
		lines.append("- %s: %s" % [helper.get("name", ""), helper.get("path", "")])
	lines.append("")
	lines.append("## Fallback Collections")
	for collection_variant in catalog.get("fallback_collections", []):
		var collection: Dictionary = collection_variant
		lines.append("- %s: %s (%s items)" % [collection.get("name", ""), collection.get("path", ""), collection.get("count", 0)])
	return "\n".join(lines)


func _join_reason_tokens(tokens: Array) -> String:
	if tokens.is_empty():
		return "none"
	var pieces := []
	for token_variant in tokens:
		pieces.append(str(token_variant))
	return ", ".join(pieces)


func _prefab_detail_summary(details: Dictionary) -> String:
	var parts := []
	if details.has("unresolved_sprite_refs"):
		parts.append("missing sprites=%s" % ", ".join(details.get("unresolved_sprite_refs", [])))
	if details.has("behavior_kinds"):
		parts.append("behavior=%s" % ", ".join(details.get("behavior_kinds", [])))
	if details.has("complex_edge_collider_count"):
		parts.append("complex edge colliders=%s" % str(details.get("complex_edge_collider_count", 0)))
	if details.has("unsupported_components"):
		parts.append("unsupported=%s" % ", ".join(details.get("unsupported_components", [])))
	return "; ".join(parts)


func _wait_for_import(resource_paths: Array) -> void:
	if _editor_interface == null:
		return
	var filesystem = _editor_interface.get_resource_filesystem()
	filesystem.scan()
	for resource_path_variant in resource_paths:
		var resource_path := str(resource_path_variant)
		var attempts := 0
		while attempts < 120:
			if ResourceLoader.exists(resource_path):
				break
			await _editor_interface.get_tree().create_timer(0.1).timeout
			attempts += 1


func _external_texture_resource(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var imported_texture := load(res_path) as Texture2D
		if imported_texture != null:
			return imported_texture
	var image := Image.load_from_file(ProjectSettings.globalize_path(res_path))
	if image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	texture.resource_path = res_path
	return texture


func _load_source_image(probe: Dictionary, key: String, semantic_registry: Dictionary) -> Image:
	if semantic_registry.get("ok", false):
		var textures_by_key: Dictionary = semantic_registry.get("textures_by_key", {})
		if textures_by_key.has(key):
			var bytes: PackedByteArray = textures_by_key[key].get("asset_bytes", PackedByteArray())
			if not bytes.is_empty():
				var semantic_image := Image.new()
				if semantic_image.load_png_from_buffer(bytes) == OK:
					return semantic_image

	var resolved: Dictionary = probe.get("resolved_paths", {})
	if not resolved.has(key):
		return Image.new()

	if probe.get("source_kind", "") == "zip":
		var reader := ZIPReader.new()
		var err := reader.open(str(probe.get("source_path", "")))
		if err != OK:
			return Image.new()
		var bytes := reader.read_file(str(resolved[key]))
		reader.close()
		var image := Image.new()
		if image.load_png_from_buffer(bytes) == OK:
			return image
		return Image.new()

	return Image.load_from_file(str(resolved[key]))


func _non_empty_cells(image: Image) -> Array:
	var coords := []
	if image.is_empty():
		return coords
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
	return rows


func _cell_has_alpha(image: Image, tile_x: int, tile_y: int) -> bool:
	var origin := Vector2i(tile_x, tile_y) * TILE_SIZE
	for y in range(TILE_SIZE.y):
		for x in range(TILE_SIZE.x):
			if image.get_pixel(origin.x + x, origin.y + y).a > 0.01:
				return true
	return false


func _semantic_source_kind_label(source_info: Dictionary) -> String:
	var semantic_source: Dictionary = source_info.get("semantic_source", {})
	return str(semantic_source.get("kind", ""))


func _sanitize_filename(value: String) -> String:
	return value.replace("/", "-").replace("\\", "-").replace(":", "").replace("*", "").replace("?", "").replace("\"", "").replace("<", "").replace(">", "").replace("|", "")


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
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			while not file.eof_reached():
				ctx.update(file.get_buffer(65536))
			file.close()
	return ctx.finish().hex_encode()


func _metadata_files_for_hash(root_path: String) -> Dictionary:
	var files := {}
	for file_path in _list_files_recursive(root_path):
		if file_path.ends_with(".prefab") or file_path.ends_with(".meta") or file_path.ends_with(".png"):
			files[file_path.trim_prefix(root_path).trim_prefix("/")] = file_path
	return files


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
		return ERR_CANT_OPEN
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
	dir.include_hidden = true
	dir.include_navigational = false
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		var child := abs_path.path_join(name)
		if dir.current_is_dir():
			_remove_tree_absolute(child)
		else:
			DirAccess.remove_absolute(child)
	dir.list_dir_end()
	DirAccess.remove_absolute(abs_path)


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


func _log_message(message: String) -> void:
	if _log.is_valid():
		_log.call(message)
