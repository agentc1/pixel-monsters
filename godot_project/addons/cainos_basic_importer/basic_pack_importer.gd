@tool
extends RefCounted

const UnityMetadataRegistry := preload("res://addons/cainos_basic_importer/unity_metadata_registry.gd")
const CainosAltarTrigger2D := preload("res://addons/cainos_basic_importer/runtime/cainos_altar_trigger_2d.gd")
const CainosSpriteColorAnimation2D := preload("res://addons/cainos_basic_importer/runtime/cainos_sprite_color_animation_2d.gd")
const CainosRuntimeActor2D := preload("res://addons/cainos_basic_importer/runtime/cainos_runtime_actor_2d.gd")
const CainosTopDownPlayerController2D := preload("res://addons/cainos_basic_importer/runtime/cainos_top_down_player_controller_2d.gd")
const CainosRuntimePlayerBody2D := preload("res://addons/cainos_basic_importer/runtime/cainos_runtime_player_body_2d.gd")
const CainosImportedScenePreview := preload("res://addons/cainos_basic_importer/runtime/cainos_imported_scene_preview.gd")
const CainosStairsTrigger2D := preload("res://addons/cainos_basic_importer/runtime/cainos_stairs_trigger_2d.gd")

const PACK_ID := "basic"
const IMPORTER_ID := "cainos_basic_importer"
const IMPORTER_VERSION := "0.13.3"
const REPORT_FORMAT_VERSION := 12
const DEFAULT_OUTPUT_ROOT := "res://cainos_imports/basic"
const TILE_SIZE := Vector2i(32, 32)
const DEFAULT_PPU := 32.0
const TEXTURE_FILTER_NEAREST := 1
const STAIR_LOWER_Z_OFFSET := -1
const STAIR_UPPER_Z_OFFSET := 50
const FOREGROUND_OCCLUDER_Z_OFFSET := 50
const BRIDGE_UNDERPASS_CARVE_OFFSET := Vector2(-64.0, -96.0)
const BRIDGE_UNDERPASS_CARVE_SIZE := Vector2(128.0, 160.0)
const STAIR_RUNTIME_CARVE_WIDTH := 96.0
const STAIR_RUNTIME_CARVE_DEPTH := 128.0
const STAIR_RUNTIME_WALKABLE_WIDTH := 96.0
const STAIR_RUNTIME_WALKABLE_DEPTH := 224.0
const RUNTIME_PLAYER_FOOTPRINT_MAX_SIZE := Vector2(6.0, 6.0)
const RUNTIME_ACTOR_COLLISION_LAYER_BIT := 1
const RUNTIME_ELEVATION_COLLISION_BITS := {
	"Layer 1": 1,
	"Layer 2": 2,
	"Layer 3": 4,
}
const UNITY_SORTING_LAYER_BASE_Z := {
	"Layer 1": 0,
	"Layer 2": 100,
	"Layer 3": 200,
}
const UNITY_SORTING_LAYER_IDS := {
	-1869315837: "Layer 1",
	-44025399: "Layer 2",
	-105541197: "Layer 3",
	0: "Layer 1",
}

const DEFAULT_GENERATION_PROFILE := {
	"output_root": DEFAULT_OUTPUT_ROOT,
	"prefer_semantic_prefabs": true,
	"generate_fallback_atlas_scenes": false,
	"generate_baked_shadow_helpers": false,
	"generate_preview_scene": true,
	"generate_player_helpers": true,
	"generate_unity_scenes": true,
	"generate_unity_scene_runtime": true,
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
	{"key": "shadow_props", "name": "shadow", "output": "tilesets/basic_shadow_tileset.tres"},
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
		"unity_scene_candidates": inventory.get("unity_scene_candidates", 0),
		"unity_scene_deferred": inventory.get("unity_scene_deferred", 0),
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
		"imported_scenes": [],
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
		"scene_paths_by_guid": {},
	}
	var unity_scene_generated := {
		"paths": [],
		"entries": [],
		"catalog_entries": [],
		"summary": {
			"imported_scenes": 0,
			"deferred_scenes": 0,
		},
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
	if normalized_profile.get("generate_unity_scenes", true) and semantic_registry.get("ok", false):
		var unity_scene_result := _generate_unity_scenes(semantic_registry, generated_tilesets, semantic_generated, copied_res_paths, normalized_profile)
		if not unity_scene_result.get("ok", false):
			return unity_scene_result
		outputs.append_array(unity_scene_result.get("paths", []))
		unity_scene_generated = unity_scene_result
		for scene_entry_variant in unity_scene_result.get("catalog_entries", []):
			catalog["imported_scenes"].append(scene_entry_variant)

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

	var compatibility: Array = _build_compatibility(inventory, normalized_profile, semantic_generated, unity_scene_generated)
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
		"unity_scene_summary": unity_scene_generated.get("summary", {}),
		"unity_scenes": unity_scene_generated.get("entries", []),
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
		"imported_scenes": len(catalog.get("imported_scenes", [])),
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
		"unity_scene_candidates": 0,
		"unity_scene_deferred": 0,
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
		var scene_summary: Dictionary = semantic_registry.get("scene_summary", {})
		inventory["unity_scene_candidates"] = scene_summary.get("import_supported_scenes", 0)
		inventory["unity_scene_deferred"] = scene_summary.get("deferred_scenes", 0)

	return inventory


func _build_compatibility(inventory: Dictionary, profile: Dictionary = {}, semantic_generated: Dictionary = {}, unity_scene_generated: Dictionary = {}) -> Array:
	var compatibility := []
	var semantic_enabled := profile.get("prefer_semantic_prefabs", true)
	var unity_scene_enabled := profile.get("generate_unity_scenes", true)
	var generated_prefabs := len(semantic_generated.get("prefab_entries", []))
	var generated_scenes := int(unity_scene_generated.get("summary", {}).get("imported_scenes", 0))
	if semantic_enabled and generated_prefabs == 0:
		generated_prefabs = int(inventory.get("supported_static_prefabs", 0)) + int(inventory.get("approximated_prefabs", 0)) + int(inventory.get("manual_behavior_prefabs", 0)) + int(inventory.get("unresolved_or_skipped_prefabs", 0))
	compatibility.append({
		"title": "TileSet atlases",
		"status": "supported",
		"detail": "Grass, stone ground, wall, struct, and shadow atlases import as external TileSet resources for TileMapLayer painting.",
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
			"detail": "%s prefabs import with partial collision/physics fidelity; rigidbodies and any unsupported collider cases are still deferred." % inventory.get("approximated_prefabs", 0),
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

	if semantic_enabled and unity_scene_enabled and generated_scenes > 0:
		compatibility.append({
			"title": "Imported Unity scenes",
			"status": "supported",
			"detail": "%s Unity scene(s) were generated with raw authoring and framed preview outputs in this import run. Runtime wrappers are included where scene support exists." % generated_scenes,
			"next": "Use the generated imported-scene entries in the compatibility report to open each raw, preview, or runtime scene.",
		})
	elif inventory.get("semantic_available", false) and unity_scene_enabled and int(inventory.get("unity_scene_candidates", 0)) > 0:
		compatibility.append({
			"title": "Imported Unity scenes",
			"status": "manual",
			"detail": "Unity scene metadata was detected, but no importable scene was generated in this run.",
			"next": "Inspect the compatibility report for deferred scene features or scene-generation failures.",
		})
	elif inventory.get("semantic_available", false) and not unity_scene_enabled and int(inventory.get("unity_scene_candidates", 0)) > 0:
		compatibility.append({
			"title": "Imported Unity scenes",
			"status": "manual",
			"detail": "Unity scene import is available for this source, but it was disabled in this run.",
			"next": "Enable generate_unity_scenes if you want the shipped Unity scenes imported into Godot scenes.",
		})

	if int(inventory.get("unity_scene_deferred", 0)) > 0:
		compatibility.append({
			"title": "Deferred Unity scenes",
			"status": "manual",
			"detail": "%s Unity scene(s) were discovered but intentionally deferred in this milestone." % inventory.get("unity_scene_deferred", 0),
			"next": "Inspect the compatibility report for the remaining deferred scene names and next-step guidance.",
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
	var scene_paths_by_guid := {}
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
				scene_paths_by_guid[str(prefab.get("guid", ""))] = scene_path
				catalog_prefabs.append({
					"prefab_name": str(prefab.get("name", "")),
					"family": family,
					"origin": "semantic_prefab",
					"path": scene_path,
					"tier": actual_tier,
					"unity_asset_path": str(prefab.get("path", "")),
					"source_prefab_guid": str(prefab.get("guid", "")),
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
		"scene_paths_by_guid": scene_paths_by_guid,
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


func _generate_unity_scenes(semantic_registry: Dictionary, generated_tilesets: Dictionary, semantic_generated: Dictionary, copied_res_paths: Dictionary, profile: Dictionary) -> Dictionary:
	var scene_entries := []
	var catalog_entries := []
	var paths := []
	var summary := {
		"imported_scenes": 0,
		"deferred_scenes": 0,
	}
	var prefab_scene_paths_by_guid: Dictionary = semantic_generated.get("scene_paths_by_guid", {})
	var texture_res_paths_by_guid := _build_texture_res_paths_by_guid(semantic_registry, copied_res_paths)
	var prefabs_by_guid: Dictionary = semantic_registry.get("prefabs_by_guid", {})
	var sprites: Dictionary = semantic_registry.get("sprites", {})
	for scene_variant in semantic_registry.get("scenes", []):
		var scene: Dictionary = scene_variant
		var scene_result := _generate_unity_scene(scene, semantic_registry, generated_tilesets, prefab_scene_paths_by_guid, prefabs_by_guid, sprites, texture_res_paths_by_guid, profile)
		if not scene_result.get("ok", false):
			return scene_result
		var report_entry: Dictionary = scene_result.get("entry", {})
		scene_entries.append(report_entry)
		paths.append_array(scene_result.get("paths", [str(scene_result.get("path", ""))]))
		catalog_entries.append(scene_result.get("catalog_entry", {}))
		summary["imported_scenes"] += 1
	for scene_variant in semantic_registry.get("deferred_scenes", []):
		var scene: Dictionary = scene_variant
		scene_entries.append({
			"scene_name": str(scene.get("name", "")),
			"unity_asset_path": str(scene.get("path", "")),
			"status": "deferred",
			"output_scene_path": null,
			"raw_scene_path": null,
			"preview_scene_path": null,
			"runtime_scene_path": null,
			"reference_image_path": _local_reference_image_path(),
			"placed_prefab_count": 0,
			"tile_layer_count": 0,
			"skipped_tile_cell_count": 0,
			"deferred_features": [],
			"detail": str(scene.get("detail", "Deferred Unity scene.")),
			"next_step": str(scene.get("next_step", "")),
		})
		summary["deferred_scenes"] += 1
	return {
		"ok": true,
		"paths": paths,
		"entries": scene_entries,
		"catalog_entries": catalog_entries,
		"summary": summary,
	}


func _generate_unity_scene(scene: Dictionary, semantic_registry: Dictionary, generated_tilesets: Dictionary, prefab_scene_paths_by_guid: Dictionary, prefabs_by_guid: Dictionary, sprites: Dictionary, texture_res_paths_by_guid: Dictionary, profile: Dictionary) -> Dictionary:
	var output_dir := _active_output_root.path_join("scenes/unity")
	_ensure_dir(ProjectSettings.globalize_path(output_dir))
	var root := Node2D.new()
	root.name = str(scene.get("name", "SC Demo"))
	root.set_meta("unity_scene_origin", str(scene.get("path", "")))
	root.set_meta("unity_scene_level_mono_behaviours", scene.get("scene_level_mono_behaviours", []))
	root.set_meta("unity_deferred_feature_counts", scene.get("deferred_feature_counts", {}))
	var tilemaps_root := Node2D.new()
	tilemaps_root.name = "Tilemaps"
	root.add_child(tilemaps_root)
	var prefabs_root := Node2D.new()
	prefabs_root.name = "Prefabs"
	root.add_child(prefabs_root)
	var markers_root := Node2D.new()
	markers_root.name = "Markers"
	root.add_child(markers_root)

	var generated_tile_layers := 0
	var placed_prefab_count := 0
	var skipped_tile_cells := 0
	for tilemap_variant in scene.get("tilemaps", []):
		var tilemap: Dictionary = tilemap_variant
		skipped_tile_cells += int(tilemap.get("skipped_cell_count", 0))
		var grouped_cells := {}
		for cell_variant in tilemap.get("cells", []):
			var cell: Dictionary = cell_variant
			var source_key := str(cell.get("source_key", ""))
			if not grouped_cells.has(source_key):
				grouped_cells[source_key] = []
			var grouped: Array = grouped_cells[source_key]
			grouped.append(cell)
			grouped_cells[source_key] = grouped
		var source_keys := grouped_cells.keys()
		if source_keys.is_empty():
			var fallback_source_key := _unity_scene_tile_source_key_from_name(str(tilemap.get("name", "")))
			if not fallback_source_key.is_empty():
				source_keys.append(fallback_source_key)
		source_keys.sort()
		for source_key_variant in source_keys:
			var source_key := str(source_key_variant)
			if not generated_tilesets.has(source_key):
				continue
			var tile_set: TileSet = generated_tilesets[source_key]
			var layer_name := _unity_scene_tile_layer_display_name(tilemap, source_key)
			var z_index := _unity_scene_layer_base_z(str(tilemap.get("layer_name", "Layer 1"))) + int(tilemap.get("sorting_order", 0))
			var layer := _make_tile_layer(layer_name, tile_set, z_index)
			var tilemap_global_position: Vector3 = tilemap.get("global_position", Vector3.ZERO)
			layer.position = _unity_vector2_to_godot_px(Vector2(tilemap_global_position.x, tilemap_global_position.y), DEFAULT_PPU)
			layer.set_meta("unity_scene_node_path", str(tilemap.get("scene_node_path", "")))
			layer.set_meta("unity_layer_name", str(tilemap.get("layer_name", "")))
			layer.set_meta("unity_sorting_layer_id", int(tilemap.get("sorting_layer_id", 0)))
			layer.set_meta("unity_warning_counts", tilemap.get("warning_counts", {}))
			for cell_variant in grouped_cells.get(source_key, []):
				var cell: Dictionary = cell_variant
				var cell_coords: Vector2i = cell.get("coords", Vector2i.ZERO)
				var atlas_coords: Vector2i = cell.get("atlas_coords", Vector2i.ZERO)
				layer.set_cell(cell_coords, 0, atlas_coords)
			tilemaps_root.add_child(layer)
			generated_tile_layers += 1

	for camera_variant in scene.get("camera_markers", []):
		var camera: Dictionary = camera_variant
		var marker := Node2D.new()
		marker.name = "%s Marker" % str(camera.get("name", "Camera"))
		var position: Vector3 = camera.get("position", Vector3.ZERO)
		marker.position = _unity_vector2_to_godot_px(Vector2(position.x, position.y), DEFAULT_PPU)
		marker.set_meta("unity_scene_node_path", str(camera.get("scene_node_path", "")))
		marker.set_meta("unity_camera_orthographic", bool(camera.get("orthographic", true)))
		marker.set_meta("unity_camera_orthographic_size", float(camera.get("orthographic_size", 0.0)))
		marker.set_meta("unity_camera_scripts", camera.get("script_paths", []))
		markers_root.add_child(marker)

	for instance_variant in scene.get("prefab_instances", []):
		var instance_desc: Dictionary = instance_variant
		var prefab_guid := str(instance_desc.get("source_prefab_guid", ""))
		if prefab_guid.is_empty() or not prefabs_by_guid.has(prefab_guid):
			continue
		var instance_root := _instantiate_unity_scene_prefab(
			prefab_guid,
			prefab_scene_paths_by_guid,
			prefabs_by_guid,
			sprites,
			texture_res_paths_by_guid
		)
		if instance_root == null:
			continue
		var target_parent := _ensure_unity_prefab_container(prefabs_root, str(instance_desc.get("parent_scene_path", "")))
		var node_2d := instance_root
		var name_override := str(instance_desc.get("name_override", ""))
		if not name_override.is_empty():
			node_2d.name = name_override
		var local_position: Vector3 = instance_desc.get("local_position", Vector3.ZERO)
		node_2d.position = _unity_vector2_to_godot_px(Vector2(local_position.x, local_position.y), DEFAULT_PPU)
		var local_scale: Vector3 = instance_desc.get("local_scale", Vector3.ONE)
		node_2d.scale = Vector2(local_scale.x, local_scale.y)
		var scene_layer_name := str(instance_desc.get("layer_name", "Layer 1"))
		var scene_layer_base_z := _unity_scene_layer_base_z(scene_layer_name)
		node_2d.z_index = scene_layer_base_z + _unity_local_z_z_index_offset(local_position.z)
		node_2d.set_meta("unity_source_prefab", str(instance_desc.get("source_prefab_path", "")))
		node_2d.set_meta("unity_parent_scene_path", str(instance_desc.get("parent_scene_path", "")))
		node_2d.set_meta("unity_scene_layer_name", scene_layer_name)
		node_2d.set_meta("cainos_scene_layer_base_z", scene_layer_base_z)
		node_2d.set_meta("unity_scene_instance_overrides", {
			"renderer_overrides": instance_desc.get("renderer_overrides", {}),
			"mono_overrides": instance_desc.get("mono_overrides", {}),
			"game_object_overrides": instance_desc.get("game_object_overrides", {}),
			"unsupported_override_paths": instance_desc.get("unsupported_override_paths", []),
		})
		_apply_unity_scene_instance_overrides(node_2d, instance_desc, prefabs_by_guid.get(prefab_guid, {}))
		_apply_basic_foreground_occluder_conventions(node_2d)
		target_parent.add_child(node_2d)
		placed_prefab_count += 1

	_assign_scene_owner(root, root)
	var packed_scene := PackedScene.new()
	var pack_err := packed_scene.pack(root)
	if pack_err != OK:
		root.free()
		return {"ok": false, "error": "Could not pack imported Unity scene: %s" % str(scene.get("name", ""))}
	var scene_output_path := output_dir.path_join("%s.tscn" % str(scene.get("name", "SC Demo")))
	var save_err := _save_resource(packed_scene, scene_output_path)
	if save_err != OK:
		root.free()
		return {"ok": false, "error": "Could not save imported Unity scene: %s" % scene_output_path}
	root.free()
	var preview_result := _generate_unity_scene_preview(str(scene.get("name", "SC Demo")), scene_output_path)
	if not preview_result.get("ok", false):
		return preview_result
	var preview_scene_path := str(preview_result.get("path", ""))
	var runtime_scene_enabled := bool(profile.get("generate_unity_scene_runtime", true)) and bool(scene.get("runtime_supported", false))
	var runtime_scene_path = ""
	var runtime_scene_detail := ""
	if runtime_scene_enabled:
		var runtime_result := _generate_unity_scene_runtime(
			scene,
			scene_output_path,
			prefab_scene_paths_by_guid,
			prefabs_by_guid,
			sprites,
			texture_res_paths_by_guid
		)
		if not runtime_result.get("ok", false):
			return runtime_result
		runtime_scene_path = str(runtime_result.get("path", ""))
		runtime_scene_detail = str(runtime_result.get("detail", ""))
	var reference_image_path := _local_reference_image_path()
	var remaining_deferred_features := _remaining_unity_scene_deferred_features(scene)
	if not runtime_scene_path.is_empty():
		remaining_deferred_features.erase("runtime_wrapper_unavailable")
	elif runtime_scene_enabled:
		remaining_deferred_features["runtime_wrapper_unavailable"] = runtime_scene_detail if not runtime_scene_detail.is_empty() else "Runtime wrapper generation was skipped for this import."
	var scene_paths := [scene_output_path, preview_scene_path]
	if not runtime_scene_path.is_empty():
		scene_paths.append(runtime_scene_path)
	var detail := "Imported as a raw authoring scene plus a framed preview and a playable runtime wrapper scene."
	var next_step := "Use %s for playable validation, %s for framed comparison, and %s for raw authoring." % [runtime_scene_path if not runtime_scene_path.is_empty() else scene_output_path, preview_scene_path, scene_output_path]
	if runtime_scene_path.is_empty():
		detail = "Imported as a raw authoring scene plus a framed preview scene."
		next_step = "Use %s for framed comparison and %s for raw authoring." % [preview_scene_path, scene_output_path]
	return {
		"ok": true,
		"path": scene_output_path,
		"paths": scene_paths,
		"catalog_entry": {
			"name": str(scene.get("name", "")),
			"path": scene_output_path,
			"raw_scene_path": scene_output_path,
			"origin": "unity_scene",
			"preview_scene_path": preview_scene_path,
			"runtime_scene_path": runtime_scene_path,
			"reference_image_path": reference_image_path,
		},
		"entry": {
			"scene_name": str(scene.get("name", "")),
			"unity_asset_path": str(scene.get("path", "")),
			"status": "imported",
			"output_scene_path": scene_output_path,
			"raw_scene_path": scene_output_path,
			"preview_scene_path": preview_scene_path,
			"runtime_scene_path": runtime_scene_path,
			"reference_image_path": reference_image_path,
			"placed_prefab_count": placed_prefab_count,
			"tile_layer_count": generated_tile_layers,
			"skipped_tile_cell_count": skipped_tile_cells,
			"deferred_features": remaining_deferred_features,
			"detail": detail,
			"next_step": next_step,
		},
	}


func _generate_unity_scene_preview(scene_name: String, scene_output_path: String) -> Dictionary:
	var output_dir := _active_output_root.path_join("scenes/helpers")
	_ensure_dir(ProjectSettings.globalize_path(output_dir))
	var preview_slug := scene_name.to_lower().replace(" ", "_")
	var root := Node2D.new()
	root.name = "%s_preview" % preview_slug
	root.set_script(CainosImportedScenePreview)
	root.set("target_scene_path", scene_output_path)
	root.set("preview_window_size", Vector2i(1200, 1200))
	root.set("padding_pixels", 96.0)
	var scene_instance := Node2D.new()
	scene_instance.name = "SceneInstance"
	root.add_child(scene_instance)
	var camera := Camera2D.new()
	camera.name = "PreviewCamera2D"
	camera.enabled = true
	root.add_child(camera)
	_assign_scene_owner(root, root)
	var packed_scene := PackedScene.new()
	var pack_err := packed_scene.pack(root)
	if pack_err != OK:
		root.free()
		return {"ok": false, "error": "Could not pack imported scene preview: %s" % scene_name}
	var scene_path := output_dir.path_join("%s_preview.tscn" % preview_slug)
	var save_err := _save_resource(packed_scene, scene_path)
	if save_err != OK:
		root.free()
		return {"ok": false, "error": "Could not save imported scene preview: %s" % scene_path}
	root.free()
	return {
		"ok": true,
		"path": scene_path,
	}


func _generate_unity_scene_runtime(scene: Dictionary, raw_scene_path: String, prefab_scene_paths_by_guid: Dictionary, prefabs_by_guid: Dictionary, sprites: Dictionary, texture_res_paths_by_guid: Dictionary) -> Dictionary:
	var packed := load(raw_scene_path)
	if not (packed is PackedScene):
		return {"ok": false, "error": "Could not load raw Unity scene for runtime wrapper: %s" % raw_scene_path}
	var raw_instance := (packed as PackedScene).instantiate()
	if not (raw_instance is Node2D):
		if raw_instance != null:
			raw_instance.free()
		return {"ok": false, "error": "Raw Unity scene is not a Node2D: %s" % raw_scene_path}

	var runtime_player_result := _build_unity_scene_runtime_player(
		scene,
		raw_instance as Node2D,
		prefab_scene_paths_by_guid,
		prefabs_by_guid,
		sprites,
		texture_res_paths_by_guid
	)
	if bool(runtime_player_result.get("skipped", false)):
		raw_instance.free()
		return {
			"ok": true,
			"skipped": true,
			"path": "",
			"detail": str(runtime_player_result.get("detail", "Runtime scene generation skipped.")),
		}
	if not runtime_player_result.get("ok", false):
		raw_instance.free()
		return runtime_player_result
	_configure_unity_scene_runtime_collision_objects(raw_instance)

	var root := Node2D.new()
	root.name = "%s Runtime" % str(scene.get("name", "SC Demo"))
	root.set_meta("unity_scene_origin", str(scene.get("path", "")))
	root.set_meta("unity_scene_runtime_source", raw_scene_path)

	var scene_instance_root := Node2D.new()
	scene_instance_root.name = "SceneInstance"
	root.add_child(scene_instance_root)
	scene_instance_root.add_child(raw_instance)

	var collision_root := _build_unity_scene_collision_root(scene, _runtime_scene_carve_rects_by_layer(scene))
	root.add_child(collision_root)

	var runtime_player := runtime_player_result.get("node") as CharacterBody2D
	root.add_child(runtime_player)

	var scene_bounds := _compute_canvas_bounds(raw_instance)
	var camera_marker := _primary_scene_camera_marker(scene)
	_configure_unity_scene_runtime_camera(runtime_player, scene_bounds, camera_marker, Vector2(runtime_player_result.get("spawn_position", Vector2.ZERO)))

	_assign_scene_owner(root, root)
	var packed_scene := PackedScene.new()
	var pack_err := packed_scene.pack(root)
	if pack_err != OK:
		root.free()
		return {"ok": false, "error": "Could not pack Unity runtime scene: %s" % str(scene.get("name", ""))}
	var scene_path := _active_output_root.path_join("scenes/unity/%s Runtime.tscn" % str(scene.get("name", "SC Demo")))
	var save_err := _save_resource(packed_scene, scene_path)
	if save_err != OK:
		root.free()
		return {"ok": false, "error": "Could not save Unity runtime scene: %s" % scene_path}
	root.free()
	return {"ok": true, "path": scene_path}


func _build_unity_scene_runtime_player(scene: Dictionary, raw_scene_root: Node2D, prefab_scene_paths_by_guid: Dictionary, prefabs_by_guid: Dictionary, sprites: Dictionary, texture_res_paths_by_guid: Dictionary) -> Dictionary:
	var player_info := _unity_scene_player_instance_info(scene, prefab_scene_paths_by_guid)
	if player_info.is_empty():
		return {
			"ok": false,
			"skipped": true,
			"detail": "Runtime scene generation requires a PF Player instance in the imported Unity scene.",
		}
	_remove_unity_scene_placeholder_player(raw_scene_root)

	var player_scene_path := str(player_info.get("scene_path", ""))
	var prefab_guid := str(player_info.get("prefab_guid", ""))
	var player_instance: Node = null
	if not player_scene_path.is_empty():
		var player_packed := load(player_scene_path)
		if player_packed is PackedScene:
			player_instance = (player_packed as PackedScene).instantiate()
	if player_instance == null and not prefab_guid.is_empty():
		player_instance = _instantiate_unity_scene_prefab(prefab_guid, prefab_scene_paths_by_guid, prefabs_by_guid, sprites, texture_res_paths_by_guid)
	if player_instance == null:
		return {"ok": false, "error": "Could not build PF Player for Unity runtime wrapper."}
	if not (player_instance is Node2D):
		if player_instance != null:
			player_instance.free()
		return {"ok": false, "error": "PF Player scene did not instantiate as Node2D: %s" % player_scene_path}

	var runtime_player := CharacterBody2D.new()
	var player_layer_name := str(player_info.get("layer_name", "Layer 1"))
	runtime_player.name = "RuntimePlayer"
	runtime_player.position = Vector2(player_info.get("spawn_position", Vector2.ZERO))
	runtime_player.scale = Vector2(player_info.get("spawn_scale", Vector2.ONE))
	runtime_player.collision_layer = RUNTIME_ACTOR_COLLISION_LAYER_BIT
	runtime_player.collision_mask = _runtime_elevation_collision_bit(player_layer_name)
	runtime_player.set_script(CainosRuntimePlayerBody2D)
	runtime_player.set_meta("unity_runtime_player", true)
	runtime_player.set_meta("cainos_runtime_elevation_body", true)
	runtime_player.set_meta("cainos_runtime_collision_layer_name", player_layer_name)
	runtime_player.set_meta("cainos_runtime_collision_mask", int(runtime_player.collision_mask))
	runtime_player.set("walkable_regions_by_layer", _runtime_walkable_regions_by_layer(scene))

	var player_root := player_instance as Node2D
	player_root.position = Vector2.ZERO
	player_root.scale = Vector2.ONE
	runtime_player.add_child(player_root)

	var collision_result := _clone_player_collision_to_runtime_player(player_root, runtime_player)
	if not collision_result.get("ok", false):
		runtime_player.free()
		return collision_result

	var follow_camera := Camera2D.new()
	follow_camera.name = "FollowCamera2D"
	runtime_player.add_child(follow_camera)

	_configure_unity_scene_runtime_player_instance(player_root, player_layer_name)
	runtime_player.set("player_root_path", NodePath("PF Player"))
	runtime_player.set("controller_path", NodePath("PF Player"))
	runtime_player.set("follow_camera_path", NodePath("FollowCamera2D"))
	return {
		"ok": true,
		"node": runtime_player,
		"spawn_position": Vector2(player_info.get("spawn_position", Vector2.ZERO)),
	}


func _configure_unity_scene_runtime_player_instance(player_root: Node2D, layer_name: String) -> void:
	if player_root.has_method("set"):
		player_root.set("movement_mode", "external_body")
		player_root.set("movement_bounds", Rect2())
		player_root.set("walkable_regions", [])
	player_root.set_meta("cainos_runtime_scene_player", true)
	var actor_helper := player_root.get_node_or_null("CainosRuntimeActor2D")
	if actor_helper != null:
		actor_helper.set("base_layer_name", layer_name)
		actor_helper.set("base_sorting_layer_name", layer_name)


func _unity_scene_player_instance_info(scene: Dictionary, prefab_scene_paths_by_guid: Dictionary) -> Dictionary:
	for instance_variant in scene.get("prefab_instances", []):
		var instance: Dictionary = instance_variant
		var source_prefab_path := str(instance.get("source_prefab_path", ""))
		if not source_prefab_path.contains("/Prefab/Player/"):
			continue
		var prefab_guid := str(instance.get("source_prefab_guid", ""))
		if prefab_guid.is_empty():
			continue
		var local_position: Vector3 = instance.get("local_position", Vector3.ZERO)
		var local_scale: Vector3 = instance.get("local_scale", Vector3.ONE)
		return {
			"prefab_guid": prefab_guid,
			"scene_path": str(prefab_scene_paths_by_guid.get(prefab_guid, "")),
			"spawn_position": _unity_vector2_to_godot_px(Vector2(local_position.x, local_position.y), DEFAULT_PPU),
			"spawn_scale": Vector2(local_scale.x, local_scale.y),
			"layer_name": str(instance.get("layer_name", "Layer 1")),
		}
	return {}


func _remove_unity_scene_placeholder_player(raw_scene_root: Node2D) -> void:
	var player_placeholder := raw_scene_root.get_node_or_null("Prefabs/PF Player")
	if player_placeholder == null:
		player_placeholder = raw_scene_root.find_child("PF Player", true, false)
	if player_placeholder != null and player_placeholder.get_parent() != null:
		player_placeholder.get_parent().remove_child(player_placeholder)
		player_placeholder.free()


func _clone_player_collision_to_runtime_player(player_root: Node2D, runtime_player: CharacterBody2D) -> Dictionary:
	var source_owner := player_root.get_node_or_null("BoxCollider_0")
	if not (source_owner is Node2D):
		return {"ok": false, "error": "PF Player did not include BoxCollider_0 for runtime scene generation."}
	var source_shape_node := _first_collision_shape_descendant(source_owner)
	if source_shape_node == null or source_shape_node.shape == null:
		return {"ok": false, "error": "PF Player collider shape was missing for runtime scene generation."}
	var wrapper_shape := CollisionShape2D.new()
	wrapper_shape.name = "CollisionShape2D"
	wrapper_shape.position = (source_owner as Node2D).position + source_shape_node.position
	var duplicated_shape := source_shape_node.shape.duplicate(true)
	if duplicated_shape is RectangleShape2D:
		var rectangle_shape := duplicated_shape as RectangleShape2D
		rectangle_shape.size = Vector2(
			minf(rectangle_shape.size.x, RUNTIME_PLAYER_FOOTPRINT_MAX_SIZE.x),
			minf(rectangle_shape.size.y, RUNTIME_PLAYER_FOOTPRINT_MAX_SIZE.y)
		)
	wrapper_shape.shape = duplicated_shape
	wrapper_shape.set_meta("cainos_runtime_player_footprint", true)
	runtime_player.add_child(wrapper_shape)
	_disable_collision_object(source_owner)
	return {"ok": true}


func _first_collision_shape_descendant(node: Node) -> CollisionShape2D:
	if node is CollisionShape2D:
		return node as CollisionShape2D
	for child in node.get_children():
		var collision_shape := _first_collision_shape_descendant(child)
		if collision_shape != null:
			return collision_shape
	return null


func _disable_collision_object(node: Node) -> void:
	if node is CollisionObject2D:
		var collision_object := node as CollisionObject2D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if node is CollisionShape2D:
		(node as CollisionShape2D).disabled = true
	for child in node.get_children():
		_disable_collision_object(child)


func _configure_unity_scene_runtime_collision_objects(node: Node) -> void:
	if node is CollisionObject2D:
		var collision_object := node as CollisionObject2D
		if collision_object is Area2D:
			collision_object.collision_layer = RUNTIME_ACTOR_COLLISION_LAYER_BIT
			collision_object.collision_mask = RUNTIME_ACTOR_COLLISION_LAYER_BIT
			collision_object.set_meta("cainos_runtime_trigger_collision", true)
		else:
			var layer_name := _runtime_collision_layer_name_for_node(collision_object)
			collision_object.collision_layer = _runtime_elevation_collision_bit(layer_name)
			collision_object.collision_mask = RUNTIME_ACTOR_COLLISION_LAYER_BIT
			collision_object.set_meta("cainos_runtime_collision_layer_name", layer_name)
			collision_object.set_meta("cainos_runtime_collision_layer_bit", int(collision_object.collision_layer))
	for child in node.get_children():
		_configure_unity_scene_runtime_collision_objects(child)


func _runtime_collision_layer_name_for_node(node: Node) -> String:
	var base_layer_name := _runtime_base_layer_name_for_node(node)
	var source_prefab_path := _nearest_meta_string(node, "unity_source_prefab").to_lower()
	if source_prefab_path.contains("wooden gate"):
		return _next_runtime_layer_name(base_layer_name)
	var current := node
	while current != null:
		var label := str(current.name).to_lower()
		if label.contains("collider upper"):
			return _next_runtime_layer_name(base_layer_name)
		if label.contains("collider lower"):
			return base_layer_name
		if source_prefab_path.contains("gate") and label.contains("collider t"):
			return _next_runtime_layer_name(base_layer_name)
		current = current.get_parent()
	return base_layer_name


func _runtime_base_layer_name_for_node(node: Node) -> String:
	var meta_layer := _nearest_meta_string(node, "unity_scene_layer_name")
	if not meta_layer.is_empty():
		return meta_layer
	meta_layer = _nearest_meta_string(node, "cainos_effective_sorting_layer_name")
	if not meta_layer.is_empty():
		return meta_layer
	if node != null:
		var path_text := str(node.get_path()).to_lower()
		if path_text.contains("/layer 3/"):
			return "Layer 3"
		if path_text.contains("/layer 2/"):
			return "Layer 2"
	return "Layer 1"


func _nearest_meta_string(node: Node, meta_name: String) -> String:
	var current := node
	while current != null:
		if current.has_meta(meta_name):
			return str(current.get_meta(meta_name))
		current = current.get_parent()
	return ""


func _runtime_elevation_collision_bit(layer_name: String) -> int:
	return int(RUNTIME_ELEVATION_COLLISION_BITS.get(layer_name, RUNTIME_ELEVATION_COLLISION_BITS["Layer 1"]))


func _next_runtime_layer_name(layer_name: String) -> String:
	match layer_name:
		"Layer 1":
			return "Layer 2"
		"Layer 2":
			return "Layer 3"
		_:
			return "Layer 3"


func _build_unity_scene_collision_root(scene: Dictionary, carve_rects_by_layer := {}) -> Node2D:
	var root := Node2D.new()
	root.name = "SceneCollision"
	for tilemap_variant in scene.get("tilemaps", []):
		var tilemap: Dictionary = tilemap_variant
		var collision: Dictionary = tilemap.get("collision", {})
		if collision.is_empty() or not bool(collision.get("runtime_supported", false)):
			continue
		var body := StaticBody2D.new()
		body.name = "%s Collision" % str(tilemap.get("name", "Tilemap"))
		var layer_name := str(tilemap.get("layer_name", "Layer 1"))
		body.collision_layer = _runtime_elevation_collision_bit(layer_name)
		body.collision_mask = RUNTIME_ACTOR_COLLISION_LAYER_BIT
		var tilemap_global_position: Vector3 = tilemap.get("global_position", Vector3.ZERO)
		body.position = _unity_vector2_to_godot_px(Vector2(tilemap_global_position.x, tilemap_global_position.y), DEFAULT_PPU) + _unity_vector2_to_godot_px(collision.get("offset", Vector2.ZERO), DEFAULT_PPU)
		body.set_meta("unity_layer_name", layer_name)
		body.set_meta("cainos_runtime_collision_layer_name", layer_name)
		body.set_meta("cainos_runtime_collision_layer_bit", int(body.collision_layer))
		body.set_meta("unity_scene_node_path", str(tilemap.get("scene_node_path", "")))
		var local_carve_rects := _runtime_local_carve_rects_for_layer(layer_name, carve_rects_by_layer, body.position)
		if str(collision.get("geometry_mode", "")) == "composite_paths":
			var path_index := 0
			for path_variant in collision.get("composite_paths", []):
				var path: Array = path_variant
				if path.size() < 3:
					continue
				var polygon := PackedVector2Array()
				for point_variant in path:
					polygon.append(_unity_vector2_to_godot_px(point_variant, DEFAULT_PPU))
				var polygon_node := CollisionPolygon2D.new()
				polygon_node.name = "CollisionPolygon2D_%d" % path_index
				polygon_node.polygon = polygon
				body.add_child(polygon_node)
				path_index += 1
		else:
			for rect_variant in _tile_collision_rect_runs(tilemap.get("cells", []), local_carve_rects):
				var rect: Rect2 = rect_variant
				var shape_node := CollisionShape2D.new()
				shape_node.name = "CollisionShape2D"
				var shape := RectangleShape2D.new()
				shape.size = rect.size
				shape_node.position = rect.position + rect.size * 0.5
				shape_node.shape = shape
				body.add_child(shape_node)
		if body.get_child_count() > 0:
			root.add_child(body)
		else:
			body.free()
	return root


func _runtime_scene_carve_rects_by_layer(scene: Dictionary) -> Dictionary:
	var carve_rects_by_layer := {}
	_add_runtime_bridge_underpass_carve_rects(scene, carve_rects_by_layer)
	_add_runtime_stair_opening_carve_rects(scene, carve_rects_by_layer)
	return carve_rects_by_layer


func _add_runtime_bridge_underpass_carve_rects(scene: Dictionary, carve_rects_by_layer: Dictionary) -> void:
	for instance_variant in scene.get("prefab_instances", []):
		var instance: Dictionary = instance_variant
		var source_prefab_path := str(instance.get("source_prefab_path", "")).to_lower()
		if not source_prefab_path.contains("/pf struct - gate"):
			continue
		var layer_name := str(instance.get("layer_name", "Layer 1"))
		var local_position: Vector3 = instance.get("local_position", Vector3.ZERO)
		var root_position := _unity_vector2_to_godot_px(Vector2(local_position.x, local_position.y), DEFAULT_PPU)
		var carve_rect := Rect2(root_position + BRIDGE_UNDERPASS_CARVE_OFFSET, BRIDGE_UNDERPASS_CARVE_SIZE)
		var layer_rects: Array = carve_rects_by_layer.get(layer_name, [])
		layer_rects.append(carve_rect)
		carve_rects_by_layer[layer_name] = layer_rects


func _add_runtime_stair_opening_carve_rects(scene: Dictionary, carve_rects_by_layer: Dictionary) -> void:
	for instance_variant in scene.get("prefab_instances", []):
		var instance: Dictionary = instance_variant
		var source_prefab_path := str(instance.get("source_prefab_path", "")).to_lower()
		if not source_prefab_path.contains("/pf struct - stairs"):
			continue
		var base_layer_name := str(instance.get("layer_name", "Layer 1"))
		var upper_layer_name := _next_runtime_layer_name(base_layer_name)
		var local_position: Vector3 = instance.get("local_position", Vector3.ZERO)
		var root_position := _unity_vector2_to_godot_px(Vector2(local_position.x, local_position.y), DEFAULT_PPU)
		var carve_rect := _runtime_stair_opening_carve_rect(root_position, source_prefab_path)
		if carve_rect.size.x <= 0.0 or carve_rect.size.y <= 0.0:
			continue
		var layer_rects: Array = carve_rects_by_layer.get(upper_layer_name, [])
		layer_rects.append(carve_rect)
		carve_rects_by_layer[upper_layer_name] = layer_rects


func _runtime_stair_opening_carve_rect(root_position: Vector2, source_prefab_path: String) -> Rect2:
	var half_width := STAIR_RUNTIME_CARVE_WIDTH * 0.5
	if source_prefab_path.contains("stairs s"):
		return Rect2(root_position + Vector2(-half_width, -STAIR_RUNTIME_CARVE_DEPTH + 32.0), Vector2(STAIR_RUNTIME_CARVE_WIDTH, STAIR_RUNTIME_CARVE_DEPTH))
	if source_prefab_path.contains("stairs n"):
		return Rect2(root_position + Vector2(-half_width, -32.0), Vector2(STAIR_RUNTIME_CARVE_WIDTH, STAIR_RUNTIME_CARVE_DEPTH))
	if source_prefab_path.contains("stairs w"):
		return Rect2(root_position + Vector2(-32.0, -half_width), Vector2(STAIR_RUNTIME_CARVE_DEPTH, STAIR_RUNTIME_CARVE_WIDTH))
	if source_prefab_path.contains("stairs e"):
		return Rect2(root_position + Vector2(-STAIR_RUNTIME_CARVE_DEPTH + 32.0, -half_width), Vector2(STAIR_RUNTIME_CARVE_DEPTH, STAIR_RUNTIME_CARVE_WIDTH))
	return Rect2()


func _runtime_walkable_regions_by_layer(scene: Dictionary) -> Dictionary:
	var regions_by_layer := {}
	for tilemap_variant in scene.get("tilemaps", []):
		var tilemap: Dictionary = tilemap_variant
		var layer_name := str(tilemap.get("layer_name", "Layer 1"))
		if layer_name == "Layer 1" or not _tilemap_is_runtime_walkable_surface(tilemap):
			continue
		var tilemap_global_position: Vector3 = tilemap.get("global_position", Vector3.ZERO)
		var tilemap_origin := _unity_vector2_to_godot_px(Vector2(tilemap_global_position.x, tilemap_global_position.y), DEFAULT_PPU)
		var regions: Array = regions_by_layer.get(layer_name, [])
		for rect_variant in _tile_collision_rect_runs(tilemap.get("cells", [])):
			var rect: Rect2 = rect_variant
			regions.append(Rect2(tilemap_origin + rect.position, rect.size))
		regions_by_layer[layer_name] = regions
	_add_runtime_stair_walkable_regions(scene, regions_by_layer)
	return regions_by_layer


func _tilemap_is_runtime_walkable_surface(tilemap: Dictionary) -> bool:
	var name := str(tilemap.get("name", "")).to_lower()
	if name.contains("wall") or name.contains("shadow"):
		return false
	return name.contains("grass") or name.contains("stone ground")


func _add_runtime_stair_walkable_regions(scene: Dictionary, regions_by_layer: Dictionary) -> void:
	for instance_variant in scene.get("prefab_instances", []):
		var instance: Dictionary = instance_variant
		var source_prefab_path := str(instance.get("source_prefab_path", "")).to_lower()
		if not source_prefab_path.contains("/pf struct - stairs"):
			continue
		var base_layer_name := str(instance.get("layer_name", "Layer 1"))
		if base_layer_name == "Layer 3":
			continue
		var upper_layer_name := _next_runtime_layer_name(base_layer_name)
		var local_position: Vector3 = instance.get("local_position", Vector3.ZERO)
		var root_position := _unity_vector2_to_godot_px(Vector2(local_position.x, local_position.y), DEFAULT_PPU)
		var walkable_rect := _runtime_stair_walkable_rect(root_position, source_prefab_path)
		if walkable_rect.size.x <= 0.0 or walkable_rect.size.y <= 0.0:
			continue
		var regions: Array = regions_by_layer.get(upper_layer_name, [])
		regions.append(walkable_rect)
		regions_by_layer[upper_layer_name] = regions


func _runtime_stair_walkable_rect(root_position: Vector2, source_prefab_path: String) -> Rect2:
	var half_width := STAIR_RUNTIME_WALKABLE_WIDTH * 0.5
	var half_depth := STAIR_RUNTIME_WALKABLE_DEPTH * 0.5
	if source_prefab_path.contains("stairs s") or source_prefab_path.contains("stairs n"):
		return Rect2(root_position + Vector2(-half_width, -half_depth), Vector2(STAIR_RUNTIME_WALKABLE_WIDTH, STAIR_RUNTIME_WALKABLE_DEPTH))
	if source_prefab_path.contains("stairs w") or source_prefab_path.contains("stairs e"):
		return Rect2(root_position + Vector2(-half_depth, -half_width), Vector2(STAIR_RUNTIME_WALKABLE_DEPTH, STAIR_RUNTIME_WALKABLE_WIDTH))
	return Rect2()


func _runtime_local_carve_rects_for_layer(layer_name: String, carve_rects_by_layer: Dictionary, collision_body_position: Vector2) -> Array:
	var local_rects := []
	for rect_variant in carve_rects_by_layer.get(layer_name, []):
		var rect: Rect2 = rect_variant
		local_rects.append(Rect2(rect.position - collision_body_position, rect.size))
	return local_rects


func _tile_collision_rect_runs(cells_variant, carve_rects := []) -> Array:
	var rows := {}
	for cell_variant in cells_variant:
		var cell: Dictionary = cell_variant
		var coords: Vector2i = cell.get("coords", Vector2i.ZERO)
		var cell_rect := Rect2(Vector2(coords.x * TILE_SIZE.x, coords.y * TILE_SIZE.y), Vector2(TILE_SIZE))
		if _rect_intersects_any(cell_rect, carve_rects):
			continue
		var row: Array = rows.get(coords.y, [])
		if not row.has(coords.x):
			row.append(coords.x)
		rows[coords.y] = row
	var row_rects := []
	var row_keys := rows.keys()
	row_keys.sort()
	for y_variant in row_keys:
		var y := int(y_variant)
		var x_values: Array = rows.get(y, [])
		x_values.sort()
		if x_values.is_empty():
			continue
		var run_start := int(x_values[0])
		var previous := run_start
		for index in range(1, x_values.size()):
			var x := int(x_values[index])
			if x == previous + 1:
				previous = x
				continue
			row_rects.append(Rect2(Vector2(run_start * TILE_SIZE.x, y * TILE_SIZE.y), Vector2((previous - run_start + 1) * TILE_SIZE.x, TILE_SIZE.y)))
			run_start = x
			previous = x
		row_rects.append(Rect2(Vector2(run_start * TILE_SIZE.x, y * TILE_SIZE.y), Vector2((previous - run_start + 1) * TILE_SIZE.x, TILE_SIZE.y)))
	var merged := []
	for rect_variant in row_rects:
		var rect: Rect2 = rect_variant
		var merged_existing := false
		for index in range(merged.size()):
			var existing: Rect2 = merged[index]
			if is_equal_approx(existing.position.x, rect.position.x) and is_equal_approx(existing.size.x, rect.size.x) and is_equal_approx(existing.position.y + existing.size.y, rect.position.y):
				existing.size.y += rect.size.y
				merged[index] = existing
				merged_existing = true
				break
		if not merged_existing:
			merged.append(rect)
	return merged


func _rect_intersects_any(rect: Rect2, others: Array) -> bool:
	for other_variant in others:
		var other: Rect2 = other_variant
		if rect.intersects(other):
			return true
	return false


func _primary_scene_camera_marker(scene: Dictionary) -> Dictionary:
	var cameras: Array = scene.get("camera_markers", [])
	if cameras.is_empty():
		return {}
	return Dictionary(cameras[0])


func _configure_unity_scene_runtime_camera(runtime_player: CharacterBody2D, scene_bounds: Rect2, camera_marker: Dictionary, player_spawn_position: Vector2) -> void:
	var marker_position := Vector2.ZERO
	var orthographic_size := 5.0
	if not camera_marker.is_empty():
		var camera_position: Vector3 = camera_marker.get("position", Vector3.ZERO)
		marker_position = _unity_vector2_to_godot_px(Vector2(camera_position.x, camera_position.y), DEFAULT_PPU)
		orthographic_size = float(camera_marker.get("orthographic_size", 5.0))
	runtime_player.set("camera_limits", _camera_limits_rect(scene_bounds))
	runtime_player.set("camera_offset", marker_position - player_spawn_position)
	runtime_player.set("camera_unity_orthographic_size", orthographic_size)


func _camera_limits_rect(bounds: Rect2) -> Rect2i:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Rect2i()
	return Rect2i(
		floori(bounds.position.x),
		floori(bounds.position.y),
		ceili(bounds.size.x),
		ceili(bounds.size.y)
	)


func _compute_canvas_bounds(node: Node) -> Rect2:
	var accumulator := {
		"has_bounds": false,
		"min": Vector2.ZERO,
		"max": Vector2.ZERO,
	}
	_accumulate_canvas_bounds(node, accumulator)
	if not bool(accumulator.get("has_bounds", false)):
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var min_point: Vector2 = accumulator.get("min", Vector2.ZERO)
	var max_point: Vector2 = accumulator.get("max", Vector2.ZERO)
	return Rect2(min_point, max_point - min_point)


func _accumulate_canvas_bounds(node: Node, accumulator: Dictionary) -> void:
	if node is Sprite2D and (node as CanvasItem).visible:
		_accumulate_sprite_canvas_bounds(node as Sprite2D, accumulator)
	elif node is TileMapLayer and (node as CanvasItem).visible:
		_accumulate_tile_layer_canvas_bounds(node as TileMapLayer, accumulator)
	for child in node.get_children():
		_accumulate_canvas_bounds(child, accumulator)


func _accumulate_sprite_canvas_bounds(sprite: Sprite2D, accumulator: Dictionary) -> void:
	var size := Vector2.ZERO
	if sprite.region_enabled:
		size = sprite.region_rect.size
	elif sprite.texture != null:
		size = sprite.texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var origin := sprite.offset
	if sprite.centered:
		origin -= size * 0.5
	_expand_canvas_rect(accumulator, sprite.get_global_transform(), Rect2(origin, size))


func _accumulate_tile_layer_canvas_bounds(layer: TileMapLayer, accumulator: Dictionary) -> void:
	if not layer.has_method("get_used_cells"):
		return
	var used_cells_variant = layer.call("get_used_cells")
	if not (used_cells_variant is Array):
		return
	var used_cells: Array = used_cells_variant
	if used_cells.is_empty():
		return
	var min_cell := Vector2i(used_cells[0])
	var max_cell := min_cell
	for cell_variant in used_cells:
		var cell: Vector2i = cell_variant
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	var local_rect := Rect2(
		Vector2(min_cell) * Vector2(TILE_SIZE.x, TILE_SIZE.y),
		Vector2(max_cell - min_cell + Vector2i.ONE) * Vector2(TILE_SIZE.x, TILE_SIZE.y)
	)
	_expand_canvas_rect(accumulator, layer.get_global_transform(), local_rect)


func _expand_canvas_rect(accumulator: Dictionary, transform_2d: Transform2D, rect: Rect2) -> void:
	var corners := [
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + Vector2(0.0, rect.size.y),
		rect.position + rect.size,
	]
	for corner_variant in corners:
		var point: Vector2 = transform_2d * corner_variant
		_expand_canvas_point(accumulator, point)


func _expand_canvas_point(accumulator: Dictionary, point: Vector2) -> void:
	if not bool(accumulator.get("has_bounds", false)):
		accumulator["has_bounds"] = true
		accumulator["min"] = point
		accumulator["max"] = point
		return
	var min_point: Vector2 = accumulator.get("min", point)
	var max_point: Vector2 = accumulator.get("max", point)
	accumulator["min"] = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
	accumulator["max"] = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))


func _remaining_unity_scene_deferred_features(scene: Dictionary) -> Dictionary:
	var deferred := {}
	var scene_level_mono_behaviours: Array = scene.get("scene_level_mono_behaviours", [])
	if not scene_level_mono_behaviours.is_empty():
		deferred["scene_level_mono_behaviours"] = scene_level_mono_behaviours.size()
	var camera_scripts := 0
	for camera_variant in scene.get("camera_markers", []):
		var camera: Dictionary = camera_variant
		camera_scripts += Array(camera.get("script_paths", [])).size()
	if camera_scripts > 0:
		deferred["camera_scripts"] = camera_scripts
	return deferred


func _instantiate_unity_scene_prefab(prefab_guid: String, prefab_scene_paths_by_guid: Dictionary, prefabs_by_guid: Dictionary, sprites: Dictionary, texture_res_paths_by_guid: Dictionary) -> Node2D:
	if _editor_interface != null and prefab_scene_paths_by_guid.has(prefab_guid):
		var scene_path := str(prefab_scene_paths_by_guid.get(prefab_guid, ""))
		var packed := load(scene_path)
		if packed is PackedScene:
			var instantiated: Node = (packed as PackedScene).instantiate()
			if instantiated is Node2D:
				return instantiated as Node2D
			if instantiated != null:
				instantiated.free()
	var prefab_desc: Dictionary = prefabs_by_guid.get(prefab_guid, {})
	if prefab_desc.is_empty():
		return null
	return _build_semantic_prefab_root(prefab_desc, sprites, texture_res_paths_by_guid)


func _ensure_unity_prefab_container(root: Node, scene_path: String) -> Node2D:
	var container: Node = root
	var trimmed := scene_path
	if trimmed.begins_with("SCENE/"):
		trimmed = trimmed.trim_prefix("SCENE/")
	if trimmed.is_empty() or trimmed == ".":
		return root as Node2D
	for segment_variant in trimmed.split("/", false):
		var raw_segment := str(segment_variant)
		if raw_segment.is_empty() or raw_segment == "." or raw_segment == "Tilemap":
			continue
		var segment := raw_segment.replace("LAYER ", "Layer ")
		var next := container.get_node_or_null(segment)
		if next == null:
			var node := Node2D.new()
			node.name = segment
			container.add_child(node)
			next = node
		container = next
	return container as Node2D


func _apply_unity_scene_instance_overrides(instance_root: Node2D, instance_desc: Dictionary, prefab_desc: Dictionary) -> void:
	var renderer_paths: Dictionary = prefab_desc.get("renderer_sprite_paths", {})
	for renderer_id_variant in instance_desc.get("renderer_overrides", {}).keys():
		var renderer_id := str(renderer_id_variant)
		if not renderer_paths.has(renderer_id):
			continue
		var sprite_path := str(renderer_paths.get(renderer_id, ""))
		var sprite_node := instance_root.get_node_or_null(sprite_path)
		if not (sprite_node is Sprite2D):
			continue
		var sprite := sprite_node as Sprite2D
		var overrides: Dictionary = instance_desc.get("renderer_overrides", {}).get(renderer_id, {})
		if overrides.has("m_FlipX"):
			sprite.flip_h = bool(int(overrides.get("m_FlipX", 0)))
		if overrides.has("m_FlipY"):
			sprite.flip_v = bool(int(overrides.get("m_FlipY", 0)))
		if overrides.has("m_SortingOrder") or overrides.has("m_SortingLayerID"):
			var source_sorting_layer_id := int(sprite.get_meta("sorting_layer_id", 0))
			var source_sorting_order := int(sprite.get_meta("cainos_source_sorting_order", 0))
			var local_z_offset := int(sprite.get_meta("cainos_unity_local_z_offset", 0))
			var sorting_layer_id := int(overrides.get("m_SortingLayerID", source_sorting_layer_id))
			var sorting_order := int(overrides.get("m_SortingOrder", source_sorting_order))
			sprite.z_as_relative = false
			sprite.z_index = _unity_effective_sprite_z_from_parts(_unity_sorting_layer_name(sorting_layer_id), sorting_order, local_z_offset)
			_set_sprite_sorting_metadata(sprite, sorting_layer_id, sorting_order, local_z_offset)
			_refresh_basic_foreground_occluder(sprite)

	var game_object_paths: Dictionary = prefab_desc.get("game_object_paths", {})
	for game_object_id_variant in instance_desc.get("game_object_overrides", {}).keys():
		var game_object_id := str(game_object_id_variant)
		if not game_object_paths.has(game_object_id):
			continue
		var target_path := str(game_object_paths.get(game_object_id, ""))
		var target_node: Node = instance_root if target_path == "." else instance_root.get_node_or_null(target_path)
		if target_node == null:
			continue
		var overrides: Dictionary = instance_desc.get("game_object_overrides", {}).get(game_object_id, {})
		if overrides.has("m_IsActive") and target_node is CanvasItem:
			(target_node as CanvasItem).visible = bool(int(overrides.get("m_IsActive", 1)))
		if overrides.has("m_Layer"):
			target_node.set_meta("unity_scene_game_object_layer", int(overrides.get("m_Layer", 0)))

	var mono_paths: Dictionary = prefab_desc.get("mono_node_paths", {})
	for mono_id_variant in instance_desc.get("mono_overrides", {}).keys():
		var mono_id := str(mono_id_variant)
		if not mono_paths.has(mono_id):
			continue
		var target_path := str(mono_paths.get(mono_id, ""))
		var target_node: Node = instance_root if target_path == "." else instance_root.get_node_or_null(target_path)
		if target_node == null:
			continue
		var overrides: Dictionary = instance_desc.get("mono_overrides", {}).get(mono_id, {})
		if target_node.get_script() == CainosStairsTrigger2D:
			if overrides.has("layerUpper"):
				target_node.set("upper_layer", str(overrides.get("layerUpper", "")))
			if overrides.has("sortingLayerUpper"):
				target_node.set("upper_sorting_layer", str(overrides.get("sortingLayerUpper", "")))
			if overrides.has("layerLower"):
				target_node.set("lower_layer", str(overrides.get("layerLower", "")))
			if overrides.has("sortingLayerLower"):
				target_node.set("lower_sorting_layer", str(overrides.get("sortingLayerLower", "")))
		target_node.set_meta("unity_scene_mono_overrides", overrides)


func _build_semantic_prefab_root(prefab: Dictionary, sprites: Dictionary, texture_res_paths_by_guid: Dictionary) -> Node2D:
	var root_ids: Array = prefab.get("root_ids", [])
	var nodes: Dictionary = prefab.get("nodes", {})
	if root_ids.is_empty() or nodes.is_empty():
		return null

	var root_node: Node2D = Node2D.new()
	root_node.name = str(prefab.get("name", "Prefab"))
	root_node.set_meta("semantic_origin", "unity_prefab")
	root_node.set_meta("unity_path", str(prefab.get("path", "")))
	root_node.set_meta("support_tier", str(prefab.get("support_tier", "")))
	root_node.set_meta("unsupported_components", prefab.get("unsupported_components", []))

	if root_ids.size() == 1 and nodes.has(str(root_ids[0])):
		var root_desc: Dictionary = nodes[str(root_ids[0])]
		root_node.free()
		root_node = _make_prefab_runtime_node(root_desc)
		root_node.name = str(prefab.get("name", "Prefab"))
		root_node.set_meta("semantic_origin", "unity_prefab")
		root_node.set_meta("unity_path", str(prefab.get("path", "")))
		root_node.set_meta("support_tier", str(prefab.get("support_tier", "")))
		root_node.set_meta("unsupported_components", prefab.get("unsupported_components", []))
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
	_apply_runtime_prefab_conventions(root_node, prefab, sprites)

	return root_node


func _build_game_object_subtree(node_desc: Dictionary, all_nodes: Dictionary, sprites: Dictionary, texture_res_paths_by_guid: Dictionary) -> Node2D:
	var node := _make_prefab_runtime_node(node_desc)
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
		sprite_node.modulate = renderer.get("color", Color(1.0, 1.0, 1.0, 1.0))
		var sorting_layer_id := int(renderer.get("sorting_layer_id", 0))
		var sorting_order := int(renderer.get("sorting_order", 0))
		var local_z_offset := _unity_local_z_z_index_offset(local_position.z)
		sprite_node.z_as_relative = false
		sprite_node.z_index = _unity_effective_sprite_z(sorting_layer_id, sorting_order, local_position.z)
		sprite_node.texture_filter = TEXTURE_FILTER_NEAREST
		_set_sprite_sorting_metadata(sprite_node, sorting_layer_id, sorting_order, local_z_offset)
		sprite_node.set_meta("sprite_name", str(sprite_desc.get("name", "")))
		node.add_child(sprite_node)

	var collider_index := 0
	for collider_variant in node_desc.get("box_colliders", []):
		var collider: Dictionary = collider_variant
		var shape := RectangleShape2D.new()
		shape.size = collider.get("size", Vector2.ZERO) * ppu
		var collider_name := "BoxCollider_%d" % collider_index
		var owner := _collision_owner_for_node(node, bool(collider.get("is_trigger", false)), collider_name)
		if owner == node and node is CollisionObject2D:
			var shape_node := CollisionShape2D.new()
			shape_node.name = collider_name
			shape_node.position = _unity_vector2_to_godot_px(collider.get("offset", Vector2.ZERO), ppu)
			shape_node.shape = shape
			node.add_child(shape_node)
		else:
			owner.position = _unity_vector2_to_godot_px(collider.get("offset", Vector2.ZERO), ppu)
			var shape_node := CollisionShape2D.new()
			shape_node.shape = shape
			owner.add_child(shape_node)
		collider_index += 1

	for collider_variant in node_desc.get("edge_colliders", []):
		var collider: Dictionary = collider_variant
		var points: Array = collider.get("points", [])
		if points.size() != 2:
			continue
		var shape := SegmentShape2D.new()
		shape.a = _unity_vector2_to_godot_px(points[0], ppu)
		shape.b = _unity_vector2_to_godot_px(points[1], ppu)
		var collider_name := "EdgeCollider_%d" % collider_index
		var owner := _collision_owner_for_node(node, bool(collider.get("is_trigger", false)), collider_name)
		if owner == node and node is CollisionObject2D:
			var shape_node := CollisionShape2D.new()
			shape_node.name = collider_name
			shape_node.position = _unity_vector2_to_godot_px(collider.get("offset", Vector2.ZERO), ppu)
			shape_node.shape = shape
			node.add_child(shape_node)
		else:
			owner.position = _unity_vector2_to_godot_px(collider.get("offset", Vector2.ZERO), ppu)
			var shape_node := CollisionShape2D.new()
			shape_node.shape = shape
			owner.add_child(shape_node)
		collider_index += 1

	for collider_variant in node_desc.get("polygon_colliders", []):
		var collider: Dictionary = collider_variant
		var accepted_paths: Array = collider.get("accepted_paths", [])
		if accepted_paths.is_empty():
			continue
		var collider_name := "PolygonCollider_%d" % collider_index
		var owner := _collision_owner_for_node(node, bool(collider.get("is_trigger", false)), collider_name)
		var path_index := 0
		for path_variant in accepted_paths:
			var path: Array = path_variant
			if path.size() < 3:
				continue
			var polygon := PackedVector2Array()
			for point_variant in path:
				polygon.append(_unity_vector2_to_godot_px(point_variant, ppu))
			var polygon_node := CollisionPolygon2D.new()
			polygon_node.name = "%s_%d" % [collider_name, path_index] if owner == node and node is CollisionObject2D else "Polygon_%d" % path_index
			polygon_node.polygon = polygon
			if owner == node and node is CollisionObject2D:
				polygon_node.position = _unity_vector2_to_godot_px(collider.get("offset", Vector2.ZERO), ppu)
				node.add_child(polygon_node)
			else:
				owner.add_child(polygon_node)
			path_index += 1
		if owner != node or not (node is CollisionObject2D):
			if owner.get_child_count() > 0:
				owner.position = _unity_vector2_to_godot_px(collider.get("offset", Vector2.ZERO), ppu)
			else:
				owner.free()
				owner = null
		if owner != null and owner != node and owner.get_child_count() > 0:
			collider_index += 1
		elif owner == node and path_index > 0:
			collider_index += 1

	if not node_desc.get("mono_behaviours", []).is_empty():
		node.set_meta("unity_mono_behaviours", node_desc.get("mono_behaviours", []))
	if not node_desc.get("behavior_hints", []).is_empty():
		node.set_meta("cainos_behavior_hints", node_desc.get("behavior_hints", []))
	if not Dictionary(node_desc.get("supported_rigidbody", {})).is_empty():
		node.set_meta("cainos_rigidbody2d", node_desc.get("supported_rigidbody", {}))


func _make_prefab_runtime_node(node_desc: Dictionary) -> Node2D:
	var supported_rigidbody: Dictionary = node_desc.get("supported_rigidbody", {})
	if supported_rigidbody.is_empty():
		var node := Node2D.new()
		node.name = str(node_desc.get("name", "Node"))
		return node
	var body := RigidBody2D.new()
	body.name = str(node_desc.get("name", "Node"))
	body.set("mass", float(supported_rigidbody.get("mass", 1.0)))
	body.set("linear_damp", float(supported_rigidbody.get("linear_damp", 0.0)))
	body.set("angular_damp", float(supported_rigidbody.get("angular_damp", 0.05)))
	body.set("gravity_scale", float(supported_rigidbody.get("gravity_scale", 1.0)))
	body.set("lock_rotation", bool(supported_rigidbody.get("freeze_rotation", false)))
	body.set("freeze", not bool(supported_rigidbody.get("simulated", true)))
	return body


func _apply_runtime_prefab_conventions(root_node: Node2D, prefab: Dictionary, sprites: Dictionary) -> void:
	_apply_basic_foreground_occluder_conventions(root_node)
	if _prefab_requires_runtime_actor_helper(prefab, root_node):
		_attach_runtime_actor_helper(root_node)
	if _prefab_has_behavior_kind(prefab, "top_down_character_controller"):
		_attach_player_runtime(root_node, prefab, sprites)
	if _prefab_has_behavior_kind(prefab, "stairs_layer_trigger"):
		_attach_stairs_runtime(root_node, prefab)
	if _prefab_has_behavior_kind(prefab, "sprite_color_animation"):
		_attach_sprite_color_animation_runtime(root_node, prefab)
	if _prefab_has_behavior_kind(prefab, "altar_trigger"):
		_attach_altar_runtime(root_node, prefab)


func _prefab_requires_runtime_actor_helper(prefab: Dictionary, root_node: Node2D) -> bool:
	return str(prefab.get("family", "")) == "player" or root_node is RigidBody2D


func _prefab_has_behavior_kind(prefab: Dictionary, expected_kind: String) -> bool:
	for hint_variant in prefab.get("behavior_hints", []):
		var hint: Dictionary = hint_variant
		if str(hint.get("kind", "")) == expected_kind:
			return true
	return false


func _attach_runtime_actor_helper(root_node: Node2D) -> void:
	if root_node.has_node("CainosRuntimeActor2D"):
		return
	var helper := Node.new()
	helper.name = "CainosRuntimeActor2D"
	helper.set_script(CainosRuntimeActor2D)
	helper.set("actor_root_path", NodePath(".."))
	helper.set("base_layer_name", "Layer 1")
	helper.set("base_sorting_layer_name", "Layer 1")
	root_node.add_child(helper)
	root_node.set_meta("cainos_runtime_actor_helper", true)


func _attach_player_runtime(root_node: Node2D, prefab: Dictionary, sprites: Dictionary) -> void:
	var controller_hint := _first_behavior_hint(prefab, "top_down_character_controller")
	if controller_hint.is_empty():
		return
	var visual_config := _player_runtime_visual_config(root_node, prefab, sprites)
	if visual_config.is_empty():
		return
	root_node.set_script(CainosTopDownPlayerController2D)
	var controller_data: Dictionary = controller_hint.get("data", {})
	root_node.set("body_sprite_path", NodePath(str(visual_config.get("body_sprite_path", "PF Player Sprite"))))
	root_node.set("shadow_sprite_path", NodePath(str(visual_config.get("shadow_sprite_path", "Shadow/Shadow Sprite"))))
	root_node.set("actor_helper_path", NodePath("CainosRuntimeActor2D"))
	root_node.set("move_speed_px", float(controller_data.get("speed", 3.0)) * DEFAULT_PPU)
	root_node.set("south_rect", visual_config.get("south_rect", Rect2()))
	root_node.set("north_rect", visual_config.get("north_rect", Rect2()))
	root_node.set("side_rect", visual_config.get("side_rect", Rect2()))
	root_node.set("shadow_rect", visual_config.get("shadow_rect", Rect2()))
	root_node.set("direction_values", Dictionary(controller_data.get("direction_values", {
		"south": 0,
		"north": 1,
		"east": 2,
		"west": 3,
	})).duplicate(true))
	root_node.set_meta("cainos_player_runtime", true)


func _player_runtime_visual_config(root_node: Node2D, prefab: Dictionary, sprites: Dictionary) -> Dictionary:
	var body_sprite := root_node.get_node_or_null("PF Player Sprite") as Sprite2D
	if body_sprite == null:
		body_sprite = _first_sprite_descendant(root_node)
	if body_sprite == null:
		return {}
	var shadow_sprite := root_node.get_node_or_null("Shadow/Shadow Sprite") as Sprite2D
	var player_texture_guid := _player_texture_guid(prefab, sprites)
	var south_rect: Rect2 = body_sprite.region_rect
	var north_rect := south_rect
	var side_rect := south_rect
	if not player_texture_guid.is_empty():
		var north_desc := _player_texture_sprite_desc(sprites, player_texture_guid, ["player b", " player b", " back"])
		if not north_desc.is_empty():
			north_rect = north_desc.get("rect", south_rect)
		var side_desc := _player_texture_sprite_desc(sprites, player_texture_guid, ["player s", " player s", " side"])
		if not side_desc.is_empty():
			side_rect = side_desc.get("rect", south_rect)
	var shadow_rect := shadow_sprite.region_rect if shadow_sprite != null else Rect2()
	if shadow_rect.size == Vector2.ZERO and not player_texture_guid.is_empty():
		var shadow_desc := _player_texture_sprite_desc(sprites, player_texture_guid, ["shadow player", "player shadow"])
		if not shadow_desc.is_empty():
			shadow_rect = shadow_desc.get("rect", Rect2())
	return {
		"body_sprite_path": root_node.get_path_to(body_sprite),
		"shadow_sprite_path": root_node.get_path_to(shadow_sprite) if shadow_sprite != null else NodePath("Shadow/Shadow Sprite"),
		"south_rect": south_rect,
		"north_rect": north_rect,
		"side_rect": side_rect,
		"shadow_rect": shadow_rect,
	}


func _player_texture_guid(prefab: Dictionary, sprites: Dictionary) -> String:
	var nodes: Dictionary = prefab.get("nodes", {})
	for node_desc_variant in nodes.values():
		var node_desc: Dictionary = node_desc_variant
		for renderer_variant in node_desc.get("sprite_renderers", []):
			var renderer: Dictionary = renderer_variant
			var sprite_key := "%s:%s" % [str(renderer.get("sprite_guid", "")), str(renderer.get("sprite_file_id", ""))]
			if sprites.has(sprite_key):
				return str(Dictionary(sprites[sprite_key]).get("texture_guid", ""))
	return ""


func _player_texture_sprite_desc(sprites: Dictionary, texture_guid: String, name_markers: Array[String]) -> Dictionary:
	for sprite_variant in sprites.values():
		var sprite_desc: Dictionary = sprite_variant
		if str(sprite_desc.get("texture_guid", "")) != texture_guid:
			continue
		var sprite_name := str(sprite_desc.get("name", "")).to_lower()
		for marker_variant in name_markers:
			var marker := str(marker_variant)
			if sprite_name.contains(marker):
				return sprite_desc
	return {}


func _first_sprite_descendant(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node as Sprite2D
	for child in node.get_children():
		var sprite := _first_sprite_descendant(child)
		if sprite != null:
			return sprite
	return null


func _attach_stairs_runtime(root_node: Node2D, prefab: Dictionary) -> void:
	var stairs_hint := _first_behavior_hint(prefab, "stairs_layer_trigger")
	if stairs_hint.is_empty():
		return
	var scene_node_path := str(stairs_hint.get("scene_node_path", ""))
	var trigger_node := _resolve_scene_node_path(root_node, scene_node_path)
	if trigger_node == null:
		return
	trigger_node.set_script(CainosStairsTrigger2D)
	var data: Dictionary = stairs_hint.get("data", {})
	trigger_node.set("direction", str(data.get("direction", "south")))
	trigger_node.set("upper_layer", str(data.get("upper_layer", "Layer 2")))
	trigger_node.set("upper_sorting_layer", str(data.get("upper_sorting_layer", "Layer 2")))
	trigger_node.set("lower_layer", str(data.get("lower_layer", "Layer 1")))
	trigger_node.set("lower_sorting_layer", str(data.get("lower_sorting_layer", "Layer 1")))
	trigger_node.set_meta("cainos_stairs_runtime", true)
	root_node.set_meta("cainos_stairs_runtime", true)
	_apply_stairs_visual_strata(root_node, str(data.get("direction", "south")))


func _attach_sprite_color_animation_runtime(root_node: Node2D, prefab: Dictionary) -> void:
	for hint_variant in prefab.get("behavior_hints", []):
		var hint: Dictionary = hint_variant
		if str(hint.get("kind", "")) != "sprite_color_animation":
			continue
		var target_node := _resolve_scene_node_path(root_node, str(hint.get("scene_node_path", "")))
		if not (target_node is Node2D):
			continue
		var animation_node := target_node as Node2D
		animation_node.set_script(CainosSpriteColorAnimation2D)
		var data: Dictionary = hint.get("data", {})
		animation_node.set("duration_seconds", float(data.get("duration_seconds", 0.0)))
		animation_node.set("gradient_mode", str(data.get("gradient_mode", "blend")))
		animation_node.set("color_keys", Array(data.get("color_keys", [])))
		animation_node.set("alpha_keys", Array(data.get("alpha_keys", [])))
		animation_node.set_meta("cainos_sprite_color_animation_runtime", true)


func _attach_altar_runtime(root_node: Node2D, prefab: Dictionary) -> void:
	var altar_hint := _first_behavior_hint(prefab, "altar_trigger")
	if altar_hint.is_empty():
		return
	root_node.set_script(CainosAltarTrigger2D)
	var data: Dictionary = altar_hint.get("data", {})
	var rune_node_paths: Array[NodePath] = []
	for path_variant in data.get("rune_node_paths", []):
		rune_node_paths.append(NodePath(str(path_variant)))
	root_node.set("trigger_area_path", NodePath("BoxCollider_0"))
	root_node.set("rune_node_paths", rune_node_paths)
	root_node.set("lerp_speed", float(data.get("lerp_speed", 0.0)))
	root_node.set_meta("cainos_altar_runtime", true)


func _first_behavior_hint(prefab: Dictionary, expected_kind: String) -> Dictionary:
	for hint_variant in prefab.get("behavior_hints", []):
		var hint: Dictionary = hint_variant
		if str(hint.get("kind", "")) == expected_kind:
			return hint
	return {}


func _resolve_scene_node_path(root_node: Node, scene_node_path: String) -> Node:
	if scene_node_path.is_empty() or scene_node_path == ".":
		return root_node
	var parts := scene_node_path.split("/", false)
	var current: Node = root_node
	for part_variant in parts:
		var part := str(part_variant)
		if part == "." or part.is_empty():
			continue
		current = current.get_node_or_null(part)
		if current == null:
			return null
	return current


func _apply_stairs_visual_strata(root_node: Node2D, direction: String) -> void:
	match direction:
		"east", "west":
			var lower_node := root_node.get_node_or_null("Stairs L")
			if lower_node != null:
				_set_visual_stratum(lower_node, "lower", STAIR_LOWER_Z_OFFSET)
			var upper_node := root_node.get_node_or_null("Stairs U")
			if upper_node != null:
				_set_visual_stratum(upper_node, "upper", STAIR_UPPER_Z_OFFSET)
		_:
			for child in root_node.get_children():
				if child is Node and _has_descendant_sprite(child):
					_set_visual_stratum(child, "upper", STAIR_UPPER_Z_OFFSET)


func _set_visual_stratum(node: Node, stratum: String, z_offset: int) -> void:
	if node is Node2D:
		(node as Node2D).set_meta("cainos_visual_stratum", stratum)
		(node as Node2D).set_meta("cainos_visual_stratum_offset", z_offset)
	if node is Sprite2D:
		var sprite := node as Sprite2D
		if not sprite.has_meta("cainos_base_z_index"):
			sprite.set_meta("cainos_base_z_index", int(sprite.z_index))
		sprite.set_meta("cainos_visual_stratum", stratum)
		sprite.set_meta("cainos_visual_stratum_offset", z_offset)
		sprite.z_index = int(sprite.get_meta("cainos_base_z_index")) + z_offset
		sprite.set_meta("cainos_effective_z_index", int(sprite.z_index))
	for child in node.get_children():
		_set_visual_stratum(child, stratum, z_offset)


func _apply_basic_foreground_occluder_conventions(node: Node) -> void:
	if node is Sprite2D:
		_refresh_basic_foreground_occluder(node as Sprite2D)
	for child in node.get_children():
		_apply_basic_foreground_occluder_conventions(child)


func _refresh_basic_foreground_occluder(sprite: Sprite2D) -> void:
	if not _is_basic_foreground_occluder_sprite(sprite):
		if sprite.has_meta("cainos_foreground_occluder"):
			sprite.remove_meta("cainos_foreground_occluder")
		if sprite.has_meta("cainos_foreground_occluder_offset"):
			sprite.remove_meta("cainos_foreground_occluder_offset")
		return
	if not sprite.has_meta("cainos_base_z_index"):
		sprite.set_meta("cainos_base_z_index", int(sprite.z_index))
	var base_z := int(sprite.get_meta("cainos_base_z_index"))
	sprite.set_meta("cainos_foreground_occluder", true)
	sprite.set_meta("cainos_foreground_occluder_offset", FOREGROUND_OCCLUDER_Z_OFFSET)
	sprite.set_meta("cainos_visual_stratum", "foreground_occluder")
	sprite.set_meta("cainos_visual_stratum_offset", FOREGROUND_OCCLUDER_Z_OFFSET)
	sprite.z_index = base_z + FOREGROUND_OCCLUDER_Z_OFFSET
	sprite.set_meta("cainos_effective_z_index", int(sprite.z_index))


func _is_basic_foreground_occluder_sprite(sprite: Sprite2D) -> bool:
	var effective_layer := str(sprite.get_meta("cainos_effective_sorting_layer_name", ""))
	var source_prefab_path := _nearest_meta_string(sprite, "unity_source_prefab").to_lower()
	if source_prefab_path.is_empty():
		source_prefab_path = _nearest_meta_string(sprite, "unity_path").to_lower()
	var labels := [
		str(sprite.name).to_lower(),
		str(sprite.get_meta("sprite_name", "")).to_lower(),
	]
	if sprite.get_parent() != null:
		labels.append(str(sprite.get_parent().name).to_lower())
	for label_variant in labels:
		var label := str(label_variant)
		if effective_layer == "Layer 2" and label.contains("upper"):
			return true
		if effective_layer == "Layer 2" and (label.contains("bridge gate t") or label.contains("gate t")):
			return true
		if source_prefab_path.contains("struct - gate") and (label.contains("bridge gate b") or label.contains("gate b")):
			return true
		if source_prefab_path.contains("wooden gate"):
			return true
	return false


func _has_descendant_sprite(node: Node) -> bool:
	if node is Sprite2D:
		return true
	for child in node.get_children():
		if _has_descendant_sprite(child):
			return true
	return false


func _collision_owner_for_node(node: Node2D, is_trigger: bool, owner_name: String) -> Node2D:
	if not is_trigger and node is CollisionObject2D:
		return node
	var owner: Node2D = Area2D.new() if is_trigger else StaticBody2D.new()
	owner.name = owner_name
	node.add_child(owner)
	return owner


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


func _unity_local_z_z_index_offset(local_z: float) -> int:
	if local_z > 0.0001:
		return -1
	if local_z < -0.0001:
		return 1
	return 0


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

	var runtime_demo := _build_runtime_stairs_demo_scene(generated_tilesets, semantic_registry, copied_res_paths)
	if not runtime_demo.get("ok", false):
		return runtime_demo
	if runtime_demo.get("generated", false):
		helper_paths.append(runtime_demo.get("path", ""))
		helper_entries.append(runtime_demo.get("catalog_entry", {}))

	var altar_rune_demo := _build_runtime_altar_runes_demo_scene(generated_tilesets, semantic_registry, copied_res_paths)
	if not altar_rune_demo.get("ok", false):
		return altar_rune_demo
	if altar_rune_demo.get("generated", false):
		helper_paths.append(altar_rune_demo.get("path", ""))
		helper_entries.append(altar_rune_demo.get("catalog_entry", {}))

	var player_demo := _build_runtime_player_demo_scene(generated_tilesets, semantic_registry, copied_res_paths)
	if not player_demo.get("ok", false):
		return player_demo
	if player_demo.get("generated", false):
		helper_paths.append(player_demo.get("path", ""))
		helper_entries.append(player_demo.get("catalog_entry", {}))

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


func _build_runtime_stairs_demo_scene(generated_tilesets: Dictionary, semantic_registry: Dictionary, copied_res_paths: Dictionary) -> Dictionary:
	var semantic_preview := _build_semantic_preview_lookup(semantic_registry, copied_res_paths)
	var player_prefab := _find_semantic_prefab_by_name(semantic_preview, "player", "PF Player")
	if player_prefab.is_empty():
		return {"ok": true, "generated": false}
	var altar_prefab := _find_semantic_prefab_by_name(semantic_preview, "props", "PF Props - Altar 01")
	var south_stairs := _find_semantic_prefab_by_name(semantic_preview, "struct", "PF Struct - Stairs S 01 L")
	if south_stairs.is_empty():
		for prefab_variant in semantic_preview.get("struct", []):
			var candidate: Dictionary = prefab_variant
			if str(candidate.get("name", "")).find("Stairs S") >= 0:
				south_stairs = candidate
				break
	var lateral_stairs := _find_semantic_prefab_by_name(semantic_preview, "struct", "PF Struct - Stairs E 01")
	if lateral_stairs.is_empty():
		for prefab_variant in semantic_preview.get("struct", []):
			var candidate: Dictionary = prefab_variant
			var candidate_name := str(candidate.get("name", ""))
			if candidate_name.find("Stairs E") >= 0 or candidate_name.find("Stairs W") >= 0:
				lateral_stairs = candidate
				break
	if south_stairs.is_empty() and lateral_stairs.is_empty():
		return {"ok": true, "generated": false}

	var root := Node2D.new()
	root.name = "basic_runtime_stairs_demo"

	var grass_tileset := generated_tilesets.get("tileset_grass") as TileSet
	if grass_tileset != null:
		var grass := _make_tile_layer("Grass", grass_tileset, -2)
		_fill_runtime_demo_grass(grass)
		root.add_child(grass)
	var stone_tileset := generated_tilesets.get("tileset_stone_ground") as TileSet
	if stone_tileset != null:
		var stone := _make_tile_layer("StonePaths", stone_tileset, -1)
		_fill_runtime_demo_stone(stone)
		root.add_child(stone)
	var walkable_regions: Array[Rect2] = [
		Rect2(Vector2(96, 272), Vector2(152, 72)),
		Rect2(Vector2(236, 232), Vector2(44, 120)),
		Rect2(Vector2(224, 224), Vector2(296, 48)),
		Rect2(Vector2(500, 160), Vector2(80, 112)),
		Rect2(Vector2(580, 160), Vector2(60, 64)),
	]

	_instantiate_first_semantic_prefab(root, semantic_preview, "plants", Vector2(96, 176))
	if not altar_prefab.is_empty():
		_instantiate_specific_semantic_prefab(root, semantic_preview, altar_prefab, Vector2(608, 192))
	else:
		_instantiate_first_semantic_prefab(root, semantic_preview, "props", Vector2(608, 192))
	if not south_stairs.is_empty():
		_instantiate_specific_semantic_prefab(root, semantic_preview, south_stairs, Vector2(256, 224))
	if not lateral_stairs.is_empty():
		_instantiate_specific_semantic_prefab(root, semantic_preview, lateral_stairs, Vector2(496, 208))
	var player_instance := _instantiate_specific_semantic_prefab(root, semantic_preview, player_prefab, Vector2(144, 320))
	if not player_instance:
		root.free()
		return {"ok": false, "error": "Could not instantiate runtime stairs demo player."}
	var player_node := root.get_node_or_null("PF Player")
	if player_node != null:
		_configure_runtime_demo_player(
			player_node,
			Rect2(Vector2(80, 112), Vector2(528, 224)),
			walkable_regions,
			Rect2i(0, 0, 640, 384)
		)

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	root.add_child(hud)
	var help_label := Label.new()
	help_label.name = "Instructions"
	help_label.position = Vector2(16, 16)
	help_label.text = "Move: WASD or arrow keys\nUse the south stairs to reach the upper path.\nThen cross the east stairs and move up onto the altar side."
	hud.add_child(help_label)
	_assign_scene_owner(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return {"ok": false, "error": "Could not pack runtime stairs demo scene."}
	var scene_path := _active_output_root.path_join("scenes/helpers/basic_runtime_stairs_demo.tscn")
	if _save_resource(packed, scene_path) != OK:
		root.free()
		return {"ok": false, "error": "Could not save runtime stairs demo scene."}
	root.free()
	return {
		"ok": true,
		"generated": true,
		"path": scene_path,
		"catalog_entry": {
			"name": "basic_runtime_stairs_demo",
			"path": scene_path,
		},
}


func _build_runtime_altar_runes_demo_scene(generated_tilesets: Dictionary, semantic_registry: Dictionary, copied_res_paths: Dictionary) -> Dictionary:
	var semantic_preview := _build_semantic_preview_lookup(semantic_registry, copied_res_paths)
	var player_prefab := _find_semantic_prefab_by_name(semantic_preview, "player", "PF Player")
	var altar_prefab := _find_semantic_prefab_by_name(semantic_preview, "props", "PF Props - Altar 01")
	var rune_x2_prefab := _find_semantic_prefab_by_name(semantic_preview, "props", "PF Props - Rune Pillar X2")
	var rune_x3_prefab := _find_semantic_prefab_by_name(semantic_preview, "props", "PF Props - Rune Pillar X3")
	if player_prefab.is_empty() or altar_prefab.is_empty() or (rune_x2_prefab.is_empty() and rune_x3_prefab.is_empty()):
		return {"ok": true, "generated": false}

	var root := Node2D.new()
	root.name = "basic_runtime_altar_runes_demo"

	var grass_tileset := generated_tilesets.get("tileset_grass") as TileSet
	if grass_tileset != null:
		var grass := _make_tile_layer("Grass", grass_tileset, -2)
		_paint_tile_rect(grass, Rect2i(0, 0, 20, 12), Vector2i.ZERO)
		root.add_child(grass)
	var stone_tileset := generated_tilesets.get("tileset_stone_ground") as TileSet
	if stone_tileset != null:
		var stone := _make_tile_layer("StonePad", stone_tileset, -1)
		_paint_tile_rect(stone, Rect2i(7, 3, 6, 6), Vector2i.ZERO)
		_paint_tile_rect(stone, Rect2i(8, 2, 4, 1), Vector2i.ZERO)
		_paint_tile_rect(stone, Rect2i(8, 9, 4, 1), Vector2i.ZERO)
		root.add_child(stone)

	_instantiate_specific_semantic_prefab(root, semantic_preview, altar_prefab, Vector2(320, 208))
	if not rune_x2_prefab.is_empty():
		_instantiate_specific_semantic_prefab(root, semantic_preview, rune_x2_prefab, Vector2(248, 200))
	if not rune_x3_prefab.is_empty():
		_instantiate_specific_semantic_prefab(root, semantic_preview, rune_x3_prefab, Vector2(392, 200))
	var player_instance := _instantiate_specific_semantic_prefab(root, semantic_preview, player_prefab, Vector2(320, 320))
	if not player_instance:
		root.free()
		return {"ok": false, "error": "Could not instantiate altar/runes demo player."}
	var player_node := root.get_node_or_null("PF Player")
	if player_node != null:
		_configure_runtime_demo_player(
			player_node,
			Rect2(Vector2(80, 80), Vector2(480, 256)),
			[],
			Rect2i(0, 0, 640, 384)
		)

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	root.add_child(hud)
	var help_label := Label.new()
	help_label.name = "Instructions"
	help_label.position = Vector2(16, 16)
	help_label.text = "Move: WASD or arrow keys\nWalk into the altar to light the runes.\nRune pillars should animate continuously."
	hud.add_child(help_label)
	_assign_scene_owner(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return {"ok": false, "error": "Could not pack altar/runes runtime demo scene."}
	var scene_path := _active_output_root.path_join("scenes/helpers/basic_runtime_altar_runes_demo.tscn")
	if _save_resource(packed, scene_path) != OK:
		root.free()
		return {"ok": false, "error": "Could not save altar/runes runtime demo scene."}
	root.free()
	return {
		"ok": true,
		"generated": true,
		"path": scene_path,
		"catalog_entry": {
			"name": "basic_runtime_altar_runes_demo",
			"path": scene_path,
		},
	}


func _build_runtime_player_demo_scene(generated_tilesets: Dictionary, semantic_registry: Dictionary, copied_res_paths: Dictionary) -> Dictionary:
	var semantic_preview := _build_semantic_preview_lookup(semantic_registry, copied_res_paths)
	var player_prefab := _find_semantic_prefab_by_name(semantic_preview, "player", "PF Player")
	if player_prefab.is_empty():
		return {"ok": true, "generated": false}

	var root := Node2D.new()
	root.name = "basic_runtime_player_demo"

	var grass_tileset := generated_tilesets.get("tileset_grass") as TileSet
	if grass_tileset != null:
		var grass := _make_tile_layer("Grass", grass_tileset, -2)
		_paint_tile_rect(grass, Rect2i(0, 0, 18, 12), Vector2i.ZERO)
		root.add_child(grass)
	var stone_tileset := generated_tilesets.get("tileset_stone_ground") as TileSet
	if stone_tileset != null:
		var stone := _make_tile_layer("StonePath", stone_tileset, -1)
		_paint_tile_rect(stone, Rect2i(4, 5, 10, 2), Vector2i.ZERO)
		_paint_tile_rect(stone, Rect2i(8, 3, 2, 6), Vector2i.ZERO)
		root.add_child(stone)

	_instantiate_first_semantic_prefab(root, semantic_preview, "plants", Vector2(160, 176))
	_instantiate_first_semantic_prefab(root, semantic_preview, "props", Vector2(432, 176))
	var player_instance := _instantiate_specific_semantic_prefab(root, semantic_preview, player_prefab, Vector2(288, 224))
	if not player_instance:
		root.free()
		return {"ok": false, "error": "Could not instantiate runtime player demo player."}
	var player_node := root.get_node_or_null("PF Player")
	if player_node != null:
		_configure_runtime_demo_player(
			player_node,
			Rect2(Vector2(96, 96), Vector2(384, 192)),
			[],
			Rect2i(0, 0, 576, 384)
		)

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	root.add_child(hud)
	var help_label := Label.new()
	help_label.name = "Instructions"
	help_label.position = Vector2(16, 16)
	help_label.text = "Move: WASD or arrow keys\nThe player controller should update facing immediately.\nUse this scene to verify player movement and camera follow."
	hud.add_child(help_label)
	_assign_scene_owner(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return {"ok": false, "error": "Could not pack runtime player demo scene."}
	var scene_path := _active_output_root.path_join("scenes/helpers/basic_runtime_player_demo.tscn")
	if _save_resource(packed, scene_path) != OK:
		root.free()
		return {"ok": false, "error": "Could not save runtime player demo scene."}
	root.free()
	return {
		"ok": true,
		"generated": true,
		"path": scene_path,
		"catalog_entry": {
			"name": "basic_runtime_player_demo",
			"path": scene_path,
		},
	}


func _configure_runtime_demo_player(player_node: Node, movement_bounds: Rect2, walkable_regions: Array[Rect2], camera_limits: Rect2i, camera_offset: Vector2 = Vector2(0, -48)) -> void:
	if not (player_node is Node2D):
		return
	if _node_script_path(player_node).ends_with("cainos_top_down_player_controller_2d.gd"):
		player_node.set("movement_bounds", movement_bounds)
		player_node.set("walkable_regions", walkable_regions.duplicate())
		player_node.call("apply_facing", "south", false)
	var camera := player_node.get_node_or_null("FollowCamera2D") as Camera2D
	if camera == null:
		camera = Camera2D.new()
		camera.name = "FollowCamera2D"
		player_node.add_child(camera)
	camera.enabled = true
	camera.position = camera_offset
	camera.zoom = Vector2(1.0, 1.0)
	camera.limit_left = camera_limits.position.x
	camera.limit_top = camera_limits.position.y
	camera.limit_right = camera_limits.position.x + camera_limits.size.x
	camera.limit_bottom = camera_limits.position.y + camera_limits.size.y


func _node_script_path(node: Node) -> String:
	if node == null:
		return ""
	var script = node.get_script()
	if script == null:
		return ""
	return str(script.resource_path)


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

	preview["texture_res_paths_by_guid"] = _build_texture_res_paths_by_guid(semantic_registry, copied_res_paths)

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


func _find_semantic_prefab_by_name(semantic_preview: Dictionary, family: String, prefab_name: String) -> Dictionary:
	for prefab_variant in semantic_preview.get(family, []):
		var prefab: Dictionary = prefab_variant
		if str(prefab.get("name", "")) == prefab_name:
			return prefab
	return {}


func _build_texture_res_paths_by_guid(semantic_registry: Dictionary, copied_res_paths: Dictionary) -> Dictionary:
	var texture_res_paths_by_guid := {}
	var textures_by_guid: Dictionary = semantic_registry.get("textures_by_guid", {})
	for guid_variant in textures_by_guid.keys():
		var guid := str(guid_variant)
		var texture_info: Dictionary = textures_by_guid[guid]
		var source_key := str(texture_info.get("source_key", ""))
		if copied_res_paths.has(source_key):
			texture_res_paths_by_guid[guid] = copied_res_paths[source_key]
	return texture_res_paths_by_guid


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


func _fill_runtime_demo_grass(layer: TileMapLayer) -> void:
	_paint_tile_rect(layer, Rect2i(0, 0, 20, 12), Vector2i.ZERO)


func _fill_runtime_demo_stone(layer: TileMapLayer) -> void:
	_paint_tile_rect(layer, Rect2i(3, 8, 5, 3), Vector2i.ZERO)
	_paint_tile_rect(layer, Rect2i(7, 7, 2, 4), Vector2i.ZERO)
	_paint_tile_rect(layer, Rect2i(7, 7, 9, 2), Vector2i.ZERO)
	_paint_tile_rect(layer, Rect2i(15, 5, 3, 4), Vector2i.ZERO)
	_paint_tile_rect(layer, Rect2i(18, 5, 2, 2), Vector2i.ZERO)


func _paint_tile_rect(layer: TileMapLayer, rect: Rect2i, atlas_coords: Vector2i) -> void:
	if layer.tile_set == null or layer.tile_set.get_source_count() == 0:
		return
	var source_id := layer.tile_set.get_source_id(0)
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			layer.set_cell(Vector2i(x, y), source_id, atlas_coords)


func _make_tile_layer(name: String, tileset: TileSet, z_index: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = name
	layer.tile_set = tileset
	layer.z_index = z_index
	layer.texture_filter = TEXTURE_FILTER_NEAREST
	return layer


func _unity_scene_layer_base_z(layer_name: String) -> int:
	return int(UNITY_SORTING_LAYER_BASE_Z.get(layer_name, 0))


func _unity_sorting_layer_name(sorting_layer_id: int) -> String:
	return str(UNITY_SORTING_LAYER_IDS.get(sorting_layer_id, "Layer 1"))


func _unity_sorting_layer_base_z_from_id(sorting_layer_id: int) -> int:
	return _unity_scene_layer_base_z(_unity_sorting_layer_name(sorting_layer_id))


func _unity_effective_sprite_z(sorting_layer_id: int, sorting_order: int, local_z: float) -> int:
	return _unity_effective_sprite_z_from_parts(
		_unity_sorting_layer_name(sorting_layer_id),
		sorting_order,
		_unity_local_z_z_index_offset(local_z)
	)


func _unity_effective_sprite_z_from_parts(sorting_layer_name: String, sorting_order: int, local_z_offset: int) -> int:
	return _unity_scene_layer_base_z(sorting_layer_name) + sorting_order + local_z_offset


func _set_sprite_sorting_metadata(sprite: Sprite2D, sorting_layer_id: int, sorting_order: int, local_z_offset: int) -> void:
	var sorting_layer_name := _unity_sorting_layer_name(sorting_layer_id)
	var sorting_layer_base_z := _unity_scene_layer_base_z(sorting_layer_name)
	var effective_z := _unity_effective_sprite_z_from_parts(sorting_layer_name, sorting_order, local_z_offset)
	sprite.set_meta("sorting_layer_id", sorting_layer_id)
	sprite.set_meta("cainos_source_sorting_order", sorting_order)
	sprite.set_meta("cainos_unity_local_z_offset", local_z_offset)
	sprite.set_meta("cainos_base_z_index", effective_z)
	sprite.set_meta("cainos_effective_sorting_layer_name", sorting_layer_name)
	sprite.set_meta("cainos_effective_sorting_layer_base_z", sorting_layer_base_z)
	sprite.set_meta("cainos_effective_sorting_order", sorting_order)
	sprite.set_meta("cainos_effective_z_index", effective_z)


func _unity_scene_tile_layer_display_name(tilemap: Dictionary, source_key: String) -> String:
	var layer_prefix := str(tilemap.get("layer_name", "")).strip_edges()
	if layer_prefix.is_empty():
		layer_prefix = "Layer 1"
	var suffix := ""
	match source_key:
		"tileset_grass":
			suffix = "Grass"
		"tileset_stone_ground":
			suffix = "Stone Ground"
		"tileset_wall":
			suffix = "Wall"
		"shadow_props":
			suffix = "Wall Shadow"
		_:
			return str(tilemap.get("name", "Tilemap"))
	return "%s - %s" % [layer_prefix, suffix]


func _unity_scene_tile_source_key_from_name(tilemap_name: String) -> String:
	var normalized := tilemap_name.to_lower()
	if normalized.contains("stone ground"):
		return "tileset_stone_ground"
	if normalized.contains("wall shadow"):
		return "shadow_props"
	if normalized.contains("wall"):
		return "tileset_wall"
	if normalized.contains("grass"):
		return "tileset_grass"
	return ""


func _local_reference_image_path() -> String:
	var project_dir := ProjectSettings.globalize_path("res://project.godot").get_base_dir()
	var candidate_abs := project_dir.get_base_dir().path_join("local_inputs/basic_pack/scene-overview.png")
	if FileAccess.file_exists(candidate_abs):
		return "local_inputs/basic_pack/scene-overview.png"
	return ""


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
	var unity_scenes: Array = manifest.get("unity_scenes", [])
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
			"imported_unity_scenes": manifest.get("unity_scene_summary", {}).get("imported_scenes", 0),
			"deferred_unity_scenes": manifest.get("unity_scene_summary", {}).get("deferred_scenes", 0),
			"fallback_collections": len(catalog.get("fallback_collections", [])),
		},
		"legacy_summary": legacy_summary,
		"tiers": tiers,
		"editor_only_prefabs": editor_only_prefabs,
		"unity_scenes": unity_scenes,
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
	lines.append("- Imported Unity scenes: %s" % str(summary.get("imported_unity_scenes", 0)))
	lines.append("- Deferred Unity scenes: %s" % str(summary.get("deferred_unity_scenes", 0)))
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
	var unity_scenes: Array = compatibility_report.get("unity_scenes", [])
	lines.append("## Unity Scenes (%d)" % unity_scenes.size())
	if unity_scenes.is_empty():
		lines.append("- None")
	else:
		for entry_variant in unity_scenes:
			var entry: Dictionary = entry_variant
			var output_scene_path = entry.get("output_scene_path", null)
			var output_path_text := "(not generated)" if output_scene_path == null else str(output_scene_path)
			var preview_scene_path = entry.get("preview_scene_path", null)
			var preview_path_text := "(no preview)" if preview_scene_path == null else str(preview_scene_path)
			var runtime_scene_path = entry.get("runtime_scene_path", null)
			var runtime_path_text := "(no runtime scene)" if runtime_scene_path == null or str(runtime_scene_path).is_empty() else str(runtime_scene_path)
			var reference_image_path := str(entry.get("reference_image_path", ""))
			lines.append("- %s [%s] -> raw: %s | preview: %s | runtime: %s | prefabs: %s | tile layers: %s | skipped tile cells: %s%s | next: %s" % [
				entry.get("scene_name", ""),
				entry.get("status", ""),
				output_path_text,
				preview_path_text,
				runtime_path_text,
				entry.get("placed_prefab_count", 0),
				entry.get("tile_layer_count", 0),
				entry.get("skipped_tile_cell_count", 0),
				"" if reference_image_path.is_empty() else " | reference: %s" % reference_image_path,
				entry.get("next_step", ""),
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
	lines.append("## Imported Scenes")
	for scene_variant in catalog.get("imported_scenes", []):
		var scene: Dictionary = scene_variant
		var preview_scene_path := str(scene.get("preview_scene_path", ""))
		var runtime_scene_path := str(scene.get("runtime_scene_path", ""))
		var reference_image_path := str(scene.get("reference_image_path", ""))
		lines.append("- %s [%s]: raw=%s | preview=%s | runtime=%s%s" % [
			scene.get("name", ""),
			scene.get("origin", ""),
			scene.get("path", ""),
			"(none)" if preview_scene_path.is_empty() else preview_scene_path,
			"(none)" if runtime_scene_path.is_empty() else runtime_scene_path,
			"" if reference_image_path.is_empty() else " | reference=%s" % reference_image_path,
		])
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
	if details.has("polygon_collider_count"):
		parts.append("polygon colliders=%s" % str(details.get("polygon_collider_count", 0)))
	if details.has("polygon_paths_imported"):
		parts.append("polygon paths imported=%s" % str(details.get("polygon_paths_imported", 0)))
	if details.has("polygon_paths_deferred"):
		parts.append("polygon paths deferred=%s" % str(details.get("polygon_paths_deferred", 0)))
	if details.has("rigidbody_body_type"):
		parts.append("rigidbody=%s" % str(details.get("rigidbody_body_type", "")))
	if details.has("rigidbody_mass"):
		parts.append("rigidbody mass=%s" % str(details.get("rigidbody_mass", 0.0)))
	if details.has("rigidbody_linear_damp"):
		parts.append("rigidbody linear damp=%s" % str(details.get("rigidbody_linear_damp", 0.0)))
	if details.has("rigidbody_angular_damp"):
		parts.append("rigidbody angular damp=%s" % str(details.get("rigidbody_angular_damp", 0.0)))
	if details.has("rigidbody_gravity_scale"):
		parts.append("rigidbody gravity scale=%s" % str(details.get("rigidbody_gravity_scale", 0.0)))
	if details.has("rigidbody_freeze_rotation"):
		parts.append("rigidbody freeze rotation=%s" % str(details.get("rigidbody_freeze_rotation", false)))
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
