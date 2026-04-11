#!/usr/bin/env python3
import argparse
import io
import json
import shutil
import struct
import tarfile
import tempfile
import zlib
from pathlib import Path


PACK_ROOT = "Assets/Cainos/Pixel Art Top Down - Basic"
TEXTURE_ROOT = f"{PACK_ROOT}/Texture"
PREFAB_ROOT = f"{PACK_ROOT}/Prefab"
SCRIPT_ROOT = f"{PACK_ROOT}/Script"

GUIDS = {
    "tileset_grass": "11111111111111111111111111111111",
    "tileset_stone_ground": "22222222222222222222222222222222",
    "tileset_wall": "33333333333333333333333333333333",
    "struct": "44444444444444444444444444444444",
    "props": "55555555555555555555555555555555",
    "plants": "66666666666666666666666666666666",
    "player": "77777777777777777777777777777777",
    "shadow_props": "88888888888888888888888888888888",
    "shadow_plants": "99999999999999999999999999999999",
    "stairs_script": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "color_script": "abababababababababababababababab",
    "altar_script": "acacacacacacacacacacacacacacacac",
    "controller_script": "adadadadadadadadadadadadadadadad",
    "prefab_bush": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "prefab_lantern": "cccccccccccccccccccccccccccccccc",
    "prefab_sorting_stack": "67676767676767676767676767676767",
    "prefab_edge": "dddddddddddddddddddddddddddddddd",
    "prefab_complex_edge": "abcdabcdabcdabcdabcdabcdabcdabcd",
    "prefab_stairs": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    "prefab_altar": "ababcdcdababcdcdababcdcdababcdcd",
    "prefab_rune": "cdcdababcdcdababcdcdababcdcdabab",
    "prefab_polygon_static": "ffffffffffffffffffffffffffffffff",
    "prefab_polygon_body": "12121212121212121212121212121212",
    "prefab_polygon_invalid": "34343434343434343434343434343434",
    "prefab_rigidbody_box": "45454545454545454545454545454545",
    "prefab_rigidbody_unsupported": "56565656565656565656565656565656",
    "prefab_broken": "12341234123412341234123412341234",
    "prefab_player": "56785678567856785678567856785678",
    "prefab_tile_palette": "99990000111122223333444455556666",
    "tile_asset_grass": "10101010101010101010101010101010",
    "scene_demo": "11112222333344445555666677778888",
    "scene_all_props": "88887777666655554444333322221111",
}

SPRITES = {
    "grass_tile": {"name": "TX Grass Tile 01", "file_id": "6100000000000000101", "rect": (0, 0, 32, 32), "pivot": (0.5, 0.5)},
    "wall_tile": {"name": "TX Wall Tile 01", "file_id": "6100000000000000103", "rect": (0, 0, 32, 32), "pivot": (0.5, 0.5)},
    "bush": {"name": "TX Bush T1", "file_id": "6100000000000000001", "rect": (0, 0, 22, 19), "pivot": (0.5, 0.5)},
    "shadow_tile": {"name": "TX Shadow Tile 01", "file_id": "6100000000000000102", "rect": (0, 0, 32, 32), "pivot": (0.5, 0.5)},
    "shadow_bush": {"name": "TX Shadow Bush T1", "file_id": "6100000000000000002", "rect": (0, 0, 22, 12), "pivot": (0.5, 0.5)},
    "lantern": {"name": "TX Stone Lantern", "file_id": "6100000000000000003", "rect": (0, 0, 20, 28), "pivot": (0.5, 0.5)},
    "shadow_lantern": {"name": "TX Shadow Lantern", "file_id": "6100000000000000004", "rect": (0, 0, 22, 10), "pivot": (0.5, 0.5)},
    "stairs": {"name": "TX Struct Stairs L", "file_id": "6100000000000000005", "rect": (0, 0, 32, 32), "pivot": (0.5, 0.5)},
    "edge": {"name": "TX Struct Edge", "file_id": "-6100000000000000006", "rect": (32, 0, 32, 16), "pivot": (0.5, 0.5)},
    "player": {"name": "TX Player F", "file_id": "6100000000000000007", "rect": (0, 24, 24, 32), "pivot": (0.5, 0.0)},
    "player_back": {"name": "TX Player B", "file_id": "6100000000000000013", "rect": (24, 24, 24, 32), "pivot": (0.5, 0.0)},
    "player_side": {"name": "TX Player S", "file_id": "6100000000000000014", "rect": (48, 24, 24, 32), "pivot": (0.5, 0.0)},
    "player_shadow": {"name": "TX Shadow Player", "file_id": "6100000000000000015", "rect": (72, 32, 24, 12), "pivot": (0.5, 0.5)},
    "polygon_prop": {"name": "TX Props Polygon", "file_id": "6100000000000000008", "rect": (32, 0, 24, 24), "pivot": (0.5, 0.5)},
    "altar": {"name": "TX Props Altar", "file_id": "6100000000000000009", "rect": (64, 0, 32, 32), "pivot": (0.5, 0.5)},
    "altar_rune": {"name": "TX Props Altar Rune", "file_id": "6100000000000000010", "rect": (96, 0, 8, 8), "pivot": (0.5, 0.5)},
    "rune_pillar": {"name": "TX Props Rune Pillar", "file_id": "6100000000000000011", "rect": (64, 32, 16, 32), "pivot": (0.5, 0.5)},
    "rune_glow": {"name": "TX Props Rune Glow", "file_id": "6100000000000000012", "rect": (80, 32, 8, 24), "pivot": (0.5, 0.5)},
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root")
    args = parser.parse_args()

    output_root = args.output_root or str(Path(tempfile.gettempdir()) / "cainos_basic_fixture")
    root = Path(output_root).resolve()
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True, exist_ok=True)

    extracted_a = root / "extracted_a"
    extracted_b = root / "extracted_b"
    package_path = root / "synthetic_basic.unitypackage"

    asset_map = build_asset_map()
    write_extracted_fixture(extracted_a, asset_map)
    shutil.copytree(extracted_a, extracted_b)
    write_unitypackage(package_path, asset_map)

    manifest = {
        "package_path": str(package_path),
        "extracted_a": str(extracted_a),
        "extracted_b": str(extracted_b),
        "expected": {
            "prefab_count": 15,
            "supported_static_prefabs": 11,
            "approximated_prefabs": 3,
            "manual_behavior_prefabs": 0,
            "unresolved_or_skipped_prefabs": 1,
            "editor_only_prefabs": 1,
            "imported_scenes": 2,
            "deferred_scenes": 0,
            "scene_tile_layers": 4,
            "scene_prefab_instances": 2,
            "scene_skipped_tile_cells": 1,
            "all_props_tile_layers": 2,
            "all_props_prefab_instances": 1,
            "all_props_skipped_tile_cells": 0,
            "sample_prefabs": {
                "bush": "PF Plant - Bush 01",
                "lantern": "PF Props - Stone Lantern 01",
                "sorting_stack": "PF Props - Z Sorting Stack 01",
                "stairs": "PF Struct - Stairs S 01 L",
                "altar": "PF Props - Altar 01",
                "rune": "PF Props - Rune Pillar X2",
                "player": "PF Player",
                "edge": "PF Struct - Z Edge 01",
                "complex_edge": "PF Struct - Z Edge Complex 01",
                "polygon_static": "PF Props - Z Polygon Static 01",
                "polygon_body": "PF Props - Z Polygon Body 01",
                "polygon_invalid": "PF Props - Z Polygon Invalid 01",
                "rigidbody_box": "PF Props - Z Box Body 01",
                "rigidbody_unsupported": "PF Props - Z Kinematic Body 01",
                "broken": "PF Props - Z Broken 01",
                "editor_only": "TP Grass",
            },
            "sample_scene": {
                "imported": "SC Demo",
                "runtime": "SC Demo Runtime",
                "player_instance": "PF Player",
                "tile_layers": ["Layer 1 - Grass", "Layer 1 - Wall", "Layer 1 - Wall Shadow", "Layer 2 - Wall"],
            },
            "sample_scene_all_props": {
                "imported": "SC All Props",
                "tile_layers": ["Layer 1 - Grass", "Layer 1 - Wall"],
                "prefab_instance": "PF Props - Stone Lantern 01",
            },
            "lantern_box_size": [16.0, 24.0],
            "edge_segment": {"a": [-16.0, 0.0], "b": [16.0, 0.0]},
            "bush_shadow_position": [8.0, 4.0],
            "rigidbody_box_physics": {
                "mass": 5.0,
                "linear_damp": 10.0,
                "angular_damp": 0.05,
                "gravity_scale": 0.0,
                "freeze_rotation": True,
            },
            "rigidbody_polygon_physics": {
                "mass": 2.0,
                "linear_damp": 10.0,
                "angular_damp": 0.05,
                "gravity_scale": 0.0,
                "freeze_rotation": True,
            },
            "player_rects": {
                "south": [0.0, 8.0, 24.0, 32.0],
                "north": [24.0, 8.0, 24.0, 32.0],
                "side": [48.0, 8.0, 24.0, 32.0],
                "shadow": [72.0, 20.0, 24.0, 12.0],
            },
        },
    }
    (root / "fixture_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(str(root))


def build_asset_map():
    assets = {}
    add_texture(
        assets,
        "tileset_grass",
        f"{TEXTURE_ROOT}/TX Tileset Grass.png",
        64,
        64,
        [
            (0, 0, 31, 31, (104, 179, 69, 255)),
            (32, 0, 63, 31, (94, 160, 60, 255)),
            (0, 32, 31, 63, (110, 186, 72, 255)),
            (32, 32, 63, 63, (98, 167, 62, 255)),
        ],
        [SPRITES["grass_tile"]],
    )
    add_texture(
        assets,
        "tileset_stone_ground",
        f"{TEXTURE_ROOT}/TX Tileset Stone Ground.png",
        64,
        64,
        [
            (0, 0, 31, 31, (166, 166, 166, 255)),
            (32, 0, 63, 31, (140, 140, 140, 255)),
            (0, 32, 31, 63, (174, 174, 174, 255)),
            (32, 32, 63, 63, (152, 152, 152, 255)),
        ],
        [],
    )
    add_texture(
        assets,
        "tileset_wall",
        f"{TEXTURE_ROOT}/TX Tileset Wall.png",
        64,
        64,
        [
            (0, 0, 31, 31, (122, 103, 84, 255)),
            (32, 0, 63, 31, (112, 95, 78, 255)),
            (0, 32, 31, 63, (132, 111, 90, 255)),
            (32, 32, 63, 63, (120, 102, 82, 255)),
        ],
        [SPRITES["wall_tile"]],
    )
    add_texture(
        assets,
        "struct",
        f"{TEXTURE_ROOT}/TX Struct.png",
        96,
        64,
        [
            (0, 0, 31, 31, (163, 140, 108, 255)),
            (32, 0, 63, 15, (132, 112, 86, 255)),
            (64, 0, 95, 31, (154, 130, 102, 255)),
            (0, 32, 31, 63, (120, 101, 76, 255)),
        ],
        [SPRITES["stairs"], SPRITES["edge"]],
    )
    add_texture(
        assets,
        "props",
        f"{TEXTURE_ROOT}/TX Props.png",
        128,
        64,
        [
            (0, 0, 19, 27, (195, 151, 85, 255)),
            (32, 0, 55, 23, (138, 101, 71, 255)),
            (64, 0, 79, 15, (176, 120, 72, 255)),
            (64, 16, 95, 47, (108, 82, 59, 255)),
            (96, 0, 103, 7, (69, 211, 255, 255)),
            (64, 32, 79, 63, (120, 90, 176, 255)),
            (80, 32, 87, 55, (122, 237, 255, 255)),
        ],
        [SPRITES["lantern"], SPRITES["polygon_prop"], SPRITES["altar"], SPRITES["altar_rune"], SPRITES["rune_pillar"], SPRITES["rune_glow"]],
    )
    add_texture(
        assets,
        "plants",
        f"{TEXTURE_ROOT}/TX Plant.png",
        64,
        64,
        [(0, 0, 21, 18, (82, 150, 67, 255))],
        [SPRITES["bush"]],
    )
    add_texture(
        assets,
        "player",
        f"{TEXTURE_ROOT}/TX Player.png",
        128,
        64,
        [
            (0, 8, 23, 39, (77, 120, 204, 255)),
            (24, 8, 47, 39, (64, 102, 176, 255)),
            (48, 8, 71, 39, (89, 136, 204, 255)),
            (72, 20, 95, 31, (32, 20, 16, 180)),
        ],
        [SPRITES["player"], SPRITES["player_back"], SPRITES["player_side"], SPRITES["player_shadow"]],
    )
    add_texture(
        assets,
        "shadow_props",
        f"{TEXTURE_ROOT}/TX Shadow.png",
        64,
        32,
        [(0, 0, 21, 9, (0, 0, 0, 180))],
        [SPRITES["shadow_lantern"], SPRITES["shadow_tile"]],
    )
    add_texture(
        assets,
        "shadow_plants",
        f"{TEXTURE_ROOT}/TX Shadow Plant.png",
        64,
        32,
        [(0, 0, 21, 11, (0, 0, 0, 180))],
        [SPRITES["shadow_bush"]],
    )

    add_text_asset(
        assets,
        GUIDS["stairs_script"],
        f"{SCRIPT_ROOT}/StairsLayerTrigger.cs",
        "public class StairsLayerTrigger {}\n",
        simple_meta(GUIDS["stairs_script"]),
    )
    add_text_asset(
        assets,
        GUIDS["color_script"],
        f"{SCRIPT_ROOT}/SpriteColorAnimation.cs",
        "public class SpriteColorAnimation {}\n",
        simple_meta(GUIDS["color_script"]),
    )
    add_text_asset(
        assets,
        GUIDS["altar_script"],
        f"{SCRIPT_ROOT}/PropsAltar.cs",
        "public class PropsAltar {}\n",
        simple_meta(GUIDS["altar_script"]),
    )
    add_text_asset(
        assets,
        GUIDS["controller_script"],
        f"{SCRIPT_ROOT}/TopDownCharacterController.cs",
        "public class TopDownCharacterController {}\n",
        simple_meta(GUIDS["controller_script"]),
    )

    add_prefab(assets, GUIDS["prefab_bush"], f"{PREFAB_ROOT}/Plant/PF Plant - Bush 01.prefab", bush_prefab())
    add_prefab(assets, GUIDS["prefab_lantern"], f"{PREFAB_ROOT}/Props/PF Props - Stone Lantern 01.prefab", lantern_prefab())
    add_prefab(assets, GUIDS["prefab_sorting_stack"], f"{PREFAB_ROOT}/Props/PF Props - Z Sorting Stack 01.prefab", sorting_stack_prefab())
    add_prefab(assets, GUIDS["prefab_edge"], f"{PREFAB_ROOT}/Struct/PF Struct - Z Edge 01.prefab", edge_prefab())
    add_prefab(assets, GUIDS["prefab_complex_edge"], f"{PREFAB_ROOT}/Struct/PF Struct - Z Edge Complex 01.prefab", complex_edge_prefab())
    add_prefab(assets, GUIDS["prefab_stairs"], f"{PREFAB_ROOT}/Struct/PF Struct - Stairs S 01 L.prefab", stairs_prefab())
    add_prefab(assets, GUIDS["prefab_altar"], f"{PREFAB_ROOT}/Props/PF Props - Altar 01.prefab", altar_prefab())
    add_prefab(assets, GUIDS["prefab_rune"], f"{PREFAB_ROOT}/Props/PF Props - Rune Pillar X2.prefab", rune_pillar_prefab())
    add_prefab(assets, GUIDS["prefab_polygon_static"], f"{PREFAB_ROOT}/Props/PF Props - Z Polygon Static 01.prefab", polygon_static_prefab())
    add_prefab(assets, GUIDS["prefab_polygon_body"], f"{PREFAB_ROOT}/Props/PF Props - Z Polygon Body 01.prefab", polygon_body_prefab())
    add_prefab(assets, GUIDS["prefab_polygon_invalid"], f"{PREFAB_ROOT}/Props/PF Props - Z Polygon Invalid 01.prefab", polygon_invalid_prefab())
    add_prefab(assets, GUIDS["prefab_rigidbody_box"], f"{PREFAB_ROOT}/Props/PF Props - Z Box Body 01.prefab", rigidbody_box_prefab())
    add_prefab(assets, GUIDS["prefab_rigidbody_unsupported"], f"{PREFAB_ROOT}/Props/PF Props - Z Kinematic Body 01.prefab", rigidbody_unsupported_prefab())
    add_prefab(assets, GUIDS["prefab_broken"], f"{PREFAB_ROOT}/Props/PF Props - Z Broken 01.prefab", broken_prefab())
    add_prefab(assets, GUIDS["prefab_player"], f"{PREFAB_ROOT}/Player/PF Player.prefab", player_prefab())
    add_prefab(assets, GUIDS["prefab_tile_palette"], f"{PACK_ROOT}/Tile Palette/TP Grass.prefab", tile_palette_prefab())
    add_tile_palette_asset(
        assets,
        GUIDS["tile_asset_grass"],
        f"{PACK_ROOT}/Tile Palette/TP Grass/TX Tileset Grass Demo.asset",
        "TX Tileset Grass Demo",
        GUIDS["tileset_grass"],
        SPRITES["grass_tile"]["file_id"],
    )
    add_scene(assets, GUIDS["scene_demo"], f"{PACK_ROOT}/Scene/SC Demo.unity", demo_scene())
    add_scene(assets, GUIDS["scene_all_props"], f"{PACK_ROOT}/Scene/SC All Props.unity", all_props_scene())
    return assets


def add_texture(assets, guid_key, asset_path, width, height, rects, sprites):
    pixels = blank_pixels(width, height)
    for x0, y0, x1, y1, color in rects:
        draw_rect(pixels, x0, y0, x1, y1, color)
    asset_bytes = encode_png(width, height, pixels)
    guid = GUIDS[guid_key]
    assets[guid] = {
        "pathname": asset_path,
        "asset_bytes": asset_bytes,
        "meta_text": texture_meta(guid, sprites),
    }


def add_text_asset(assets, guid, asset_path, text, meta_text):
    assets[guid] = {
        "pathname": asset_path,
        "asset_bytes": text.encode("utf-8"),
        "meta_text": meta_text,
    }


def add_prefab(assets, guid, asset_path, prefab_text):
    assets[guid] = {
        "pathname": asset_path,
        "asset_bytes": prefab_text.encode("utf-8"),
        "meta_text": simple_meta(guid),
    }


def add_scene(assets, guid, asset_path, scene_text):
    assets[guid] = {
        "pathname": asset_path,
        "asset_bytes": scene_text.encode("utf-8"),
        "meta_text": simple_meta(guid),
    }


def add_tile_palette_asset(assets, guid, asset_path, tile_name, sprite_guid, sprite_file_id):
    assets[guid] = {
        "pathname": asset_path,
        "asset_bytes": tile_palette_asset(tile_name, sprite_guid, sprite_file_id).encode("utf-8"),
        "meta_text": simple_meta(guid),
    }


def simple_meta(guid):
    return f"fileFormatVersion: 2\nguid: {guid}\n"


def texture_meta(guid, sprites):
    lines = [
        "fileFormatVersion: 2",
        f"guid: {guid}",
        "TextureImporter:",
        "  spritePixelsToUnits: 32",
        "  spriteSheet:",
        "    sprites:",
    ]
    for sprite in sprites:
        x, y, width, height = sprite["rect"]
        pivot_x, pivot_y = sprite["pivot"]
        lines.extend(
            [
                "    - serializedVersion: 2",
                f"      name: {sprite['name']}",
                "      rect:",
                "        serializedVersion: 2",
                f"        x: {x}",
                f"        y: {y}",
                f"        width: {width}",
                f"        height: {height}",
                "      alignment: 0",
                f"      pivot: {{x: {pivot_x}, y: {pivot_y}}}",
                f"      internalID: {sprite['file_id']}",
            ]
        )
    return "\n".join(lines) + "\n"


def bush_prefab():
    return "\n".join(
        [
            game_object_doc("100100", "PF Plant - Bush 01", ["100101", "100102"]),
            transform_doc("100101", "100100", "0", ["100111"], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("100102", "100100", GUIDS["plants"], SPRITES["bush"]["file_id"], sorting_order=2),
            game_object_doc("100110", "Shadow", ["100111", "100112"]),
            transform_doc("100111", "100110", "100101", [], (0.25, -0.125, 0.0)),
            sprite_renderer_doc("100112", "100110", GUIDS["shadow_plants"], SPRITES["shadow_bush"]["file_id"], sorting_order=2),
        ]
    ) + "\n"


def lantern_prefab():
    return "\n".join(
        [
            game_object_doc("200100", "PF Props - Stone Lantern 01", ["200101", "200102", "200103"]),
            transform_doc("200101", "200100", "0", ["200111"], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("200102", "200100", GUIDS["props"], SPRITES["lantern"]["file_id"], sorting_order=1),
            box_collider_doc("200103", "200100", (0.0, 0.0), (0.5, 0.75)),
            game_object_doc("200110", "Shadow", ["200111", "200112"]),
            transform_doc("200111", "200110", "200101", [], (0.125, -0.0625, 0.0)),
            sprite_renderer_doc("200112", "200110", GUIDS["shadow_props"], SPRITES["shadow_lantern"]["file_id"], sorting_order=0),
        ]
    ) + "\n"


def sorting_stack_prefab():
    return "\n".join(
        [
            game_object_doc("250100", "PF Props - Z Sorting Stack 01", ["250101"]),
            transform_doc("250101", "250100", "0", ["250111", "250121"], (0.0, 0.0, 0.0)),
            game_object_doc("250110", "Layer 1 Visual", ["250111", "250112"]),
            transform_doc("250111", "250110", "250101", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc(
                "250112",
                "250110",
                GUIDS["props"],
                SPRITES["lantern"]["file_id"],
                sorting_layer_id=-1869315837,
                sorting_order=2,
            ),
            game_object_doc("250120", "Upper", ["250121", "250122"]),
            transform_doc("250121", "250120", "250101", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc(
                "250122",
                "250120",
                GUIDS["props"],
                SPRITES["polygon_prop"]["file_id"],
                sorting_layer_id=-44025399,
                sorting_order=0,
            ),
        ]
    ) + "\n"


def edge_prefab():
    return "\n".join(
        [
            game_object_doc("300100", "PF Struct - Z Edge 01", ["300101", "300102", "300103"]),
            transform_doc("300101", "300100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("300102", "300100", GUIDS["struct"], SPRITES["edge"]["file_id"], sorting_order=0),
            edge_collider_doc("300103", "300100", (0.0, 0.0), [(-0.5, 0.0), (0.5, 0.0)]),
        ]
    ) + "\n"


def complex_edge_prefab():
    return "\n".join(
        [
            game_object_doc("350100", "PF Struct - Z Edge Complex 01", ["350101", "350102", "350103"]),
            transform_doc("350101", "350100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("350102", "350100", GUIDS["struct"], SPRITES["edge"]["file_id"], sorting_order=0),
            edge_collider_doc("350103", "350100", (0.0, 0.0), [(-0.5, 0.0), (0.0, 0.25), (0.5, 0.0)]),
        ]
    ) + "\n"


def stairs_prefab():
    return "\n".join(
        [
            game_object_doc("400100", "PF Struct - Stairs S 01 L", ["400101", "400102", "400103"]),
            transform_doc("400101", "400100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("400102", "400100", GUIDS["struct"], SPRITES["stairs"]["file_id"], sorting_order=1),
            mono_behaviour_doc(
                "400103",
                "400100",
                GUIDS["stairs_script"],
                [
                    "  direction: 1",
                    "  layerUpper: Layer 2",
                    "  sortingLayerUpper: Layer 2",
                    "  layerLower: Layer 1",
                    "  sortingLayerLower: Layer 1",
                ],
            ),
        ]
    ) + "\n"


def altar_prefab():
    return "\n".join(
        [
            game_object_doc("450100", "PF Props - Altar 01", ["450101", "450102", "450103", "450130"]),
            transform_doc("450101", "450100", "0", ["450111", "450121"], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("450102", "450100", GUIDS["props"], SPRITES["altar"]["file_id"], sorting_order=1),
            mono_behaviour_doc(
                "450103",
                "450100",
                GUIDS["altar_script"],
                [
                    "  runes:",
                    "  - {fileID: 450112}",
                    "  - {fileID: 450122}",
                    "  lerpSpeed: 3",
                ],
            ),
            game_object_doc("450110", "Rune A", ["450111", "450112"]),
            transform_doc("450111", "450110", "450101", [], (-0.25, 0.25, 0.0)),
            sprite_renderer_doc("450112", "450110", GUIDS["props"], SPRITES["altar_rune"]["file_id"], sorting_order=2, color=(0.0, 0.8, 1.0, 0.0)),
            game_object_doc("450120", "Rune B", ["450121", "450122"]),
            transform_doc("450121", "450120", "450101", [], (0.25, 0.25, 0.0)),
            sprite_renderer_doc("450122", "450120", GUIDS["props"], SPRITES["altar_rune"]["file_id"], sorting_order=2, color=(0.0, 0.8, 1.0, 0.0)),
            box_collider_doc("450130", "450100", (0.0, 0.0), (0.75, 0.5), is_trigger=True),
        ]
    ) + "\n"


def rune_pillar_prefab():
    return "\n".join(
        [
            game_object_doc("460100", "PF Props - Rune Pillar X2", ["460101", "460102", "460103"]),
            transform_doc("460101", "460100", "0", ["460111"], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("460102", "460100", GUIDS["props"], SPRITES["rune_pillar"]["file_id"], sorting_order=2),
            box_collider_doc("460103", "460100", (0.0, 0.0), (0.5, 1.0)),
            game_object_doc("460110", "Glow", ["460111", "460112", "460113"]),
            transform_doc("460111", "460110", "460101", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("460112", "460110", GUIDS["props"], SPRITES["rune_glow"]["file_id"], sorting_order=2),
            mono_behaviour_doc(
                "460113",
                "460110",
                GUIDS["color_script"],
                [
                    "  gradient:",
                    "    serializedVersion: 2",
                    "    key0: {r: 0, g: 0.8, b: 1, a: 1}",
                    "    key1: {r: 0, g: 0.8, b: 1, a: 0.5}",
                    "    key2: {r: 0, g: 0, b: 0, a: 0.2}",
                    "    ctime0: 0",
                    "    ctime1: 65535",
                    "    atime0: 0",
                    "    atime1: 32768",
                    "    atime2: 65535",
                    "    m_Mode: 0",
                    "    m_NumColorKeys: 2",
                    "    m_NumAlphaKeys: 3",
                    "  time: 2",
                ],
            ),
        ]
    ) + "\n"


def polygon_static_prefab():
    return "\n".join(
        [
            game_object_doc("500100", "PF Props - Z Polygon Static 01", ["500101", "500102", "500103"]),
            transform_doc("500101", "500100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("500102", "500100", GUIDS["props"], SPRITES["polygon_prop"]["file_id"], sorting_order=0),
            polygon_collider_doc("500103", "500100", [[(-0.5, -0.5), (0.5, -0.5), (0.6, 0.4), (-0.4, 0.6)]]),
        ]
    ) + "\n"


def polygon_body_prefab():
    return "\n".join(
        [
            game_object_doc("510100", "PF Props - Z Polygon Body 01", ["510101", "510102", "510103", "510104"]),
            transform_doc("510101", "510100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("510102", "510100", GUIDS["props"], SPRITES["polygon_prop"]["file_id"], sorting_order=0),
            polygon_collider_doc("510103", "510100", [[(-0.45, -0.45), (0.45, -0.45), (0.45, 0.45), (-0.45, 0.45)]]),
            rigidbody2d_doc("510104", "510100", mass=2.0),
        ]
    ) + "\n"


def polygon_invalid_prefab():
    return "\n".join(
        [
            game_object_doc("520100", "PF Props - Z Polygon Invalid 01", ["520101", "520102", "520103"]),
            transform_doc("520101", "520100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("520102", "520100", GUIDS["props"], SPRITES["polygon_prop"]["file_id"], sorting_order=0),
            polygon_collider_doc("520103", "520100", [[(-0.5, 0.0), (0.5, 0.0)]]),
        ]
    ) + "\n"


def rigidbody_box_prefab():
    return "\n".join(
        [
            game_object_doc("530100", "PF Props - Z Box Body 01", ["530101", "530102", "530103", "530104"]),
            transform_doc("530101", "530100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("530102", "530100", GUIDS["props"], SPRITES["lantern"]["file_id"], sorting_order=0),
            box_collider_doc("530103", "530100", (0.0, 0.0), (0.75, 0.5)),
            rigidbody2d_doc("530104", "530100", mass=5.0),
        ]
    ) + "\n"


def rigidbody_unsupported_prefab():
    return "\n".join(
        [
            game_object_doc("540100", "PF Props - Z Kinematic Body 01", ["540101", "540102", "540103", "540104"]),
            transform_doc("540101", "540100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("540102", "540100", GUIDS["props"], SPRITES["lantern"]["file_id"], sorting_order=0),
            box_collider_doc("540103", "540100", (0.0, 0.0), (0.75, 0.5)),
            rigidbody2d_doc("540104", "540100", body_type=1, mass=3.0),
        ]
    ) + "\n"


def broken_prefab():
    return "\n".join(
        [
            game_object_doc("600100", "PF Props - Z Broken 01", ["600101", "600102"]),
            transform_doc("600101", "600100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("600102", "600100", GUIDS["props"], "9999999999999999999", sorting_order=0),
        ]
    ) + "\n"


def player_prefab():
    return "\n".join(
        [
            game_object_doc("700100", "PF Player", ["700101", "700102", "700103", "700104", "700105", "700106"]),
            transform_doc("700101", "700100", "0", ["700111"], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("700102", "700100", GUIDS["player"], SPRITES["player"]["file_id"], sorting_order=0),
            box_collider_doc("700103", "700100", (0.0, -0.25), (0.5, 0.75)),
            rigidbody2d_doc("700104", "700100"),
            animator_doc("700105", "700100"),
            mono_behaviour_doc(
                "700106",
                "700100",
                GUIDS["controller_script"],
                [
                    "  speed: 3",
                ],
            ),
            game_object_doc("700110", "Shadow", ["700111", "700112"]),
            transform_doc("700111", "700110", "700101", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("700112", "700110", GUIDS["player"], SPRITES["player_shadow"]["file_id"], sorting_order=-1),
        ]
    ) + "\n"


def tile_palette_prefab():
    return "\n".join(
        [
            game_object_doc("800100", "TP Grass", ["800101", "800102"]),
            transform_doc("800101", "800100", "0", [], (0.0, 0.0, 0.0)),
            mono_behaviour_doc(
                "800102",
                "800100",
                "0000000000000000e000000000000000",
                [
                    "  cellSizing: 0",
                ],
            ),
        ]
    ) + "\n"


def tile_palette_asset(tile_name, sprite_guid, sprite_file_id):
    return "\n".join(
        [
            "--- !u!114 &11400000",
            "MonoBehaviour:",
            "  m_ObjectHideFlags: 0",
            "  m_CorrespondingSourceObject: {fileID: 0}",
            "  m_PrefabInstance: {fileID: 0}",
            "  m_PrefabAsset: {fileID: 0}",
            "  m_GameObject: {fileID: 0}",
            "  m_Enabled: 1",
            "  m_EditorHideFlags: 0",
            "  m_Script: {fileID: 13312, guid: 0000000000000000e000000000000000, type: 0}",
            f"  m_Name: {tile_name}",
            "  m_EditorClassIdentifier: ",
            f"  m_Sprite: {{fileID: {sprite_file_id}, guid: {sprite_guid}, type: 3}}",
            "  m_Color: {r: 1, g: 1, b: 1, a: 1}",
            "  m_Transform:",
            "    e00: 1",
            "    e01: 0",
            "    e02: 0",
            "    e03: 0",
            "    e10: 0",
            "    e11: 1",
            "    e12: 0",
            "    e13: 0",
            "    e20: 0",
            "    e21: 0",
            "    e22: 1",
            "    e23: 0",
            "    e30: 0",
            "    e31: 0",
            "    e32: 0",
            "    e33: 1",
            "  m_InstancedGameObject: {fileID: 0}",
            "  m_Flags: 1",
            "  m_ColliderType: 1",
        ]
    ) + "\n"


def demo_scene():
    return "\n".join(
        [
            game_object_doc("900100", "LAYER 1", ["900101"]),
            transform_doc("900101", "900100", "0", ["900111", "900121", "900151", "900131", "900141"], (0.0, 0.0, 0.0)),
            game_object_doc("900110", "Layer 1 - Grass", ["900111", "900112", "900113"]),
            transform_doc("900111", "900110", "900101", [], (0.0, 0.0, 0.0)),
            tilemap_doc(
                "900112",
                "900110",
                [
                    {"file_id": SPRITES["grass_tile"]["file_id"], "guid": GUIDS["tileset_grass"]},
                    {"file_id": "11400000", "guid": GUIDS["tile_asset_grass"]},
                ],
                [
                    {"coords": (0, 0, 0), "sprite_index": 0, "matrix_index": 0, "color_index": 0, "object_index": 65535},
                    {"coords": (1, 0, 0), "sprite_index": 1, "matrix_index": 0, "color_index": 0, "object_index": 65535},
                    {"coords": (2, 0, 0), "sprite_index": 0, "matrix_index": 0, "color_index": 0, "object_index": 1},
                ],
            ),
            tilemap_renderer_doc("900113", "900110", sorting_layer_id=-1869315837, sorting_order=0),
            game_object_doc("900150", "Layer 1 - Wall", ["900151", "900152", "900153", "900154", "900155"]),
            transform_doc("900151", "900150", "900101", [], (0.0, 0.0, 0.0)),
            tilemap_doc(
                "900152",
                "900150",
                [{"file_id": SPRITES["wall_tile"]["file_id"], "guid": GUIDS["tileset_wall"]}],
                [
                    {"coords": (0, 1, 0), "sprite_index": 0, "matrix_index": 0, "color_index": 0, "object_index": 65535},
                    {"coords": (1, 1, 0), "sprite_index": 0, "matrix_index": 0, "color_index": 0, "object_index": 65535},
                ],
            ),
            tilemap_renderer_doc("900153", "900150", sorting_layer_id=-1869315837, sorting_order=10),
            tilemap_collider2d_doc("900154", "900150", is_trigger=False, used_by_composite=False),
            rigidbody2d_doc("900155", "900150", body_type=2, gravity_scale=0.0),
            game_object_doc("900120", "Layer 1 - Wall Shadow", ["900121", "900122", "900123"]),
            transform_doc("900121", "900120", "900101", [], (0.0, 0.0, 0.0)),
            tilemap_doc(
                "900122",
                "900120",
                [{"file_id": SPRITES["shadow_tile"]["file_id"], "guid": GUIDS["shadow_props"]}],
                [{"coords": (0, 1, 0), "sprite_index": 0, "matrix_index": 0, "color_index": 0, "object_index": 65535}],
            ),
            tilemap_renderer_doc("900123", "900120", sorting_layer_id=-1869315837, sorting_order=5),
            game_object_doc("900130", "Actors", ["900131"]),
            transform_doc("900131", "900130", "900101", [], (0.0, 0.0, 0.0)),
            game_object_doc("900140", "Main Camera", ["900141", "900142"]),
            transform_doc("900141", "900140", "900101", [], (4.0, 3.0, -10.0)),
            camera_doc("900142", "900140", orthographic=True, orthographic_size=6.0),
            game_object_doc("900160", "LAYER 2", ["900161"]),
            transform_doc("900161", "900160", "0", ["900171"], (0.0, 0.0, 0.0)),
            game_object_doc("900170", "Layer 2 - Wall", ["900171", "900172", "900173", "900174", "900175", "900176"]),
            transform_doc("900171", "900170", "900161", [], (0.0, 0.0, 0.0)),
            tilemap_doc(
                "900172",
                "900170",
                [{"file_id": SPRITES["wall_tile"]["file_id"], "guid": GUIDS["tileset_wall"]}],
                [{"coords": (3, 2, 0), "sprite_index": 0, "matrix_index": 0, "color_index": 0, "object_index": 65535}],
            ),
            tilemap_renderer_doc("900173", "900170", sorting_layer_id=338507026, sorting_order=10),
            tilemap_collider2d_doc("900174", "900170", is_trigger=False, used_by_composite=True),
            composite_collider2d_doc("900175", "900170", [[(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]], is_trigger=False),
            rigidbody2d_doc("900176", "900170", body_type=2, gravity_scale=0.0),
            prefab_instance_doc(
                "900200",
                GUIDS["prefab_player"],
                "900131",
                [
                    ("700101", "m_RootOrder", "0"),
                    ("700101", "m_LocalPosition.x", "2"),
                    ("700101", "m_LocalPosition.y", "1"),
                    ("700102", "m_FlipX", "1"),
                ],
            ),
            prefab_instance_doc(
                "900210",
                GUIDS["prefab_sorting_stack"],
                "900131",
                [
                    ("250101", "m_RootOrder", "1"),
                    ("250101", "m_LocalPosition.x", "3"),
                    ("250101", "m_LocalPosition.y", "1"),
                    ("250112", "m_SortingLayerID", "-44025399"),
                    ("250122", "m_SortingOrder", "5"),
                ],
            ),
        ]
    ) + "\n"


def all_props_scene():
    return "\n".join(
        [
            game_object_doc("910100", "SCENE", ["910101"]),
            transform_doc("910101", "910100", "0", ["910111", "910121", "910131"], (0.0, 0.0, 0.0)),
            game_object_doc("910110", "LAYER 1", ["910111"]),
            transform_doc("910111", "910110", "910101", ["910141", "910151", "910161"], (0.0, 0.0, 0.0)),
            game_object_doc("910140", "Layer 1 - Grass", ["910141", "910142", "910143"]),
            transform_doc("910141", "910140", "910111", [], (0.0, 0.0, 0.0)),
            tilemap_doc(
                "910142",
                "910140",
                [{"file_id": SPRITES["grass_tile"]["file_id"], "guid": GUIDS["tileset_grass"]}],
                [
                    {"coords": (0, 0, 0), "sprite_index": 0, "matrix_index": 0, "color_index": 0, "object_index": 65535},
                    {"coords": (1, 0, 0), "sprite_index": 0, "matrix_index": 0, "color_index": 0, "object_index": 65535},
                ],
            ),
            tilemap_renderer_doc("910143", "910140", sorting_layer_id=-1869315837, sorting_order=0),
            game_object_doc("910150", "Layer 1 - Wall", ["910151", "910152", "910153"]),
            transform_doc("910151", "910150", "910111", [], (0.0, 0.0, 0.0)),
            tilemap_doc(
                "910152",
                "910150",
                [{"file_id": SPRITES["wall_tile"]["file_id"], "guid": GUIDS["tileset_wall"]}],
                [
                    {"coords": (0, 1, 0), "sprite_index": 0, "matrix_index": 0, "color_index": 0, "object_index": 65535},
                    {"coords": (1, 1, 0), "sprite_index": 0, "matrix_index": 0, "color_index": 0, "object_index": 65535},
                ],
            ),
            tilemap_renderer_doc("910153", "910150", sorting_layer_id=-1869315837, sorting_order=1),
            game_object_doc("910160", "Props", ["910161"]),
            transform_doc("910161", "910160", "910111", [], (0.0, 0.0, 0.0)),
            game_object_doc("910120", "RENDERING", ["910121"]),
            transform_doc("910121", "910120", "910101", ["910171"], (0.0, 0.0, 0.0)),
            game_object_doc("910170", "Main Camera", ["910171", "910172", "910173"]),
            transform_doc("910171", "910170", "910121", [], (3.0, 2.0, -10.0)),
            camera_doc("910172", "910170", orthographic=True, orthographic_size=5.0),
            mono_behaviour_doc(
                "910173",
                "910170",
                GUIDS["controller_script"],
                [
                    "  markerName: Camera Marker",
                ],
            ),
            game_object_doc("910130", "Markers", ["910131"]),
            transform_doc("910131", "910130", "910101", [], (0.0, 0.0, 0.0)),
            prefab_instance_doc(
                "910200",
                GUIDS["prefab_lantern"],
                "910161",
                [
                    ("200101", "m_RootOrder", "0"),
                    ("200101", "m_LocalPosition.x", "2"),
                    ("200101", "m_LocalPosition.y", "1"),
                ],
            ),
        ]
    ) + "\n"


def game_object_doc(object_id, name, component_ids):
    lines = [
        f"--- !u!1 &{object_id}",
        "GameObject:",
        "  m_ObjectHideFlags: 0",
        "  m_CorrespondingSourceObject: {fileID: 0}",
        "  m_PrefabInstance: {fileID: 0}",
        "  m_PrefabAsset: {fileID: 0}",
        "  serializedVersion: 6",
        "  m_Component:",
    ]
    for component_id in component_ids:
        lines.append(f"  - component: {{fileID: {component_id}}}")
    lines.extend(
        [
            "  m_Layer: 0",
            f"  m_Name: {name}",
            "  m_TagString: Untagged",
            "  m_Icon: {fileID: 0}",
            "  m_NavMeshLayer: 0",
            "  m_StaticEditorFlags: 0",
            "  m_IsActive: 1",
        ]
    )
    return "\n".join(lines)


def transform_doc(object_id, game_object_id, parent_transform_id, child_transform_ids, local_position):
    x, y, z = local_position
    lines = [
        f"--- !u!4 &{object_id}",
        "Transform:",
        "  m_ObjectHideFlags: 0",
        "  m_CorrespondingSourceObject: {fileID: 0}",
        "  m_PrefabInstance: {fileID: 0}",
        "  m_PrefabAsset: {fileID: 0}",
        f"  m_GameObject: {{fileID: {game_object_id}}}",
        "  serializedVersion: 2",
        f"  m_LocalPosition: {{x: {x}, y: {y}, z: {z}}}",
        "  m_LocalScale: {x: 1, y: 1, z: 1}",
        f"  m_Father: {{fileID: {parent_transform_id}}}",
        "  m_Children:",
    ]
    for child_id in child_transform_ids:
        lines.append(f"  - {{fileID: {child_id}}}")
    return "\n".join(lines)


def sprite_renderer_doc(object_id, game_object_id, sprite_guid, sprite_file_id, sorting_layer_id=0, sorting_order=0, color=(1.0, 1.0, 1.0, 1.0)):
    r, g, b, a = color
    return "\n".join(
        [
            f"--- !u!212 &{object_id}",
            "SpriteRenderer:",
            "  m_ObjectHideFlags: 0",
            "  m_CorrespondingSourceObject: {fileID: 0}",
            "  m_PrefabInstance: {fileID: 0}",
            "  m_PrefabAsset: {fileID: 0}",
            f"  m_GameObject: {{fileID: {game_object_id}}}",
            "  m_Enabled: 1",
            f"  m_Sprite: {{fileID: {sprite_file_id}, guid: {sprite_guid}, type: 3}}",
            f"  m_SortingLayerID: {sorting_layer_id}",
            f"  m_SortingOrder: {sorting_order}",
            f"  m_Color: {{r: {r}, g: {g}, b: {b}, a: {a}}}",
            "  m_FlipX: 0",
            "  m_FlipY: 0",
        ]
    )


def box_collider_doc(object_id, game_object_id, offset, size, is_trigger=False):
    ox, oy = offset
    sx, sy = size
    return "\n".join(
        [
            f"--- !u!61 &{object_id}",
            "BoxCollider2D:",
            "  m_ObjectHideFlags: 0",
            "  m_CorrespondingSourceObject: {fileID: 0}",
            "  m_PrefabInstance: {fileID: 0}",
            "  m_PrefabAsset: {fileID: 0}",
            f"  m_GameObject: {{fileID: {game_object_id}}}",
            "  m_Enabled: 1",
            f"  m_IsTrigger: {1 if is_trigger else 0}",
            f"  m_Offset: {{x: {ox}, y: {oy}}}",
            f"  m_Size: {{x: {sx}, y: {sy}}}",
        ]
    )


def edge_collider_doc(object_id, game_object_id, offset, points):
    ox, oy = offset
    lines = [
        f"--- !u!68 &{object_id}",
        "EdgeCollider2D:",
        "  m_ObjectHideFlags: 0",
        "  m_CorrespondingSourceObject: {fileID: 0}",
        "  m_PrefabInstance: {fileID: 0}",
        "  m_PrefabAsset: {fileID: 0}",
        f"  m_GameObject: {{fileID: {game_object_id}}}",
        "  m_Enabled: 1",
        "  m_IsTrigger: 0",
        f"  m_Offset: {{x: {ox}, y: {oy}}}",
        "  m_Points:",
    ]
    for px, py in points:
        lines.append(f"  - {{x: {px}, y: {py}}}")
    return "\n".join(lines)


def mono_behaviour_doc(object_id, game_object_id, script_guid, field_lines):
    lines = [
        f"--- !u!114 &{object_id}",
        "MonoBehaviour:",
        "  m_ObjectHideFlags: 0",
        "  m_CorrespondingSourceObject: {fileID: 0}",
        "  m_PrefabInstance: {fileID: 0}",
        "  m_PrefabAsset: {fileID: 0}",
        f"  m_GameObject: {{fileID: {game_object_id}}}",
        "  m_Enabled: 1",
        f"  m_Script: {{fileID: 11500000, guid: {script_guid}, type: 3}}",
        "  m_Name: ",
        "  m_EditorClassIdentifier: ",
    ]
    lines.extend(field_lines)
    return "\n".join(lines)


def polygon_collider_doc(object_id, game_object_id, paths, offset=(0.0, 0.0), is_trigger=False):
    ox, oy = offset
    lines = [
        f"--- !u!60 &{object_id}",
        "PolygonCollider2D:",
        "  m_ObjectHideFlags: 0",
        "  m_CorrespondingSourceObject: {fileID: 0}",
        "  m_PrefabInstance: {fileID: 0}",
        "  m_PrefabAsset: {fileID: 0}",
        f"  m_GameObject: {{fileID: {game_object_id}}}",
        "  m_Enabled: 1",
        f"  m_IsTrigger: {1 if is_trigger else 0}",
        f"  m_Offset: {{x: {ox}, y: {oy}}}",
        "  m_Points:",
        "    m_Paths:",
    ]
    for path in paths:
        if not path:
            continue
        first = True
        for px, py in path:
            prefix = "    - - " if first else "      - "
            lines.append(f"{prefix}{{x: {px}, y: {py}}}")
            first = False
    return "\n".join(lines)


def rigidbody2d_doc(
    object_id,
    game_object_id,
    body_type=0,
    simulated=True,
    use_auto_mass=False,
    mass=1.0,
    linear_drag=10.0,
    angular_drag=0.05,
    gravity_scale=0.0,
    constraints=4,
):
    return "\n".join(
        [
            f"--- !u!50 &{object_id}",
            "Rigidbody2D:",
            "  m_ObjectHideFlags: 0",
            "  m_CorrespondingSourceObject: {fileID: 0}",
            "  m_PrefabInstance: {fileID: 0}",
            "  m_PrefabAsset: {fileID: 0}",
            f"  m_GameObject: {{fileID: {game_object_id}}}",
            "  m_Enabled: 1",
            f"  m_BodyType: {body_type}",
            f"  m_Simulated: {1 if simulated else 0}",
            "  m_UseFullKinematicContacts: 0",
            f"  m_UseAutoMass: {1 if use_auto_mass else 0}",
            f"  m_Mass: {mass}",
            f"  m_LinearDrag: {linear_drag}",
            f"  m_AngularDrag: {angular_drag}",
            f"  m_GravityScale: {gravity_scale}",
            "  m_Material: {fileID: 0}",
            "  m_Interpolate: 0",
            "  m_SleepingMode: 1",
            "  m_CollisionDetection: 0",
            f"  m_Constraints: {constraints}",
        ]
    )


def tilemap_collider2d_doc(object_id, game_object_id, is_trigger=False, used_by_composite=False, offset=(0.0, 0.0)):
    ox, oy = offset
    return "\n".join(
        [
            f"--- !u!19719996 &{object_id}",
            "TilemapCollider2D:",
            "  m_ObjectHideFlags: 0",
            "  m_CorrespondingSourceObject: {fileID: 0}",
            "  m_PrefabInstance: {fileID: 0}",
            "  m_PrefabAsset: {fileID: 0}",
            f"  m_GameObject: {{fileID: {game_object_id}}}",
            "  m_Enabled: 1",
            f"  m_IsTrigger: {1 if is_trigger else 0}",
            f"  m_UsedByComposite: {1 if used_by_composite else 0}",
            f"  m_Offset: {{x: {ox}, y: {oy}}}",
        ]
    )


def composite_collider2d_doc(object_id, game_object_id, paths, offset=(0.0, 0.0), is_trigger=False):
    ox, oy = offset
    lines = [
        f"--- !u!66 &{object_id}",
        "CompositeCollider2D:",
        "  m_ObjectHideFlags: 0",
        "  m_CorrespondingSourceObject: {fileID: 0}",
        "  m_PrefabInstance: {fileID: 0}",
        "  m_PrefabAsset: {fileID: 0}",
        f"  m_GameObject: {{fileID: {game_object_id}}}",
        "  m_Enabled: 1",
        f"  m_IsTrigger: {1 if is_trigger else 0}",
        f"  m_Offset: {{x: {ox}, y: {oy}}}",
        "  m_Paths:",
    ]
    for path in paths:
        if not path:
            continue
        first = True
        for px, py in path:
            prefix = "    - - " if first else "      - "
            lines.append(f"{prefix}{{x: {px}, y: {py}}}")
            first = False
    return "\n".join(lines)


def animator_doc(object_id, game_object_id):
    return "\n".join(
        [
            f"--- !u!95 &{object_id}",
            "Animator:",
            "  m_ObjectHideFlags: 0",
            "  m_CorrespondingSourceObject: {fileID: 0}",
            "  m_PrefabInstance: {fileID: 0}",
            "  m_PrefabAsset: {fileID: 0}",
            f"  m_GameObject: {{fileID: {game_object_id}}}",
            "  m_Enabled: 1",
        ]
    )


def tilemap_doc(object_id, game_object_id, sprite_refs, cells):
    lines = [
        f"--- !u!1839735485 &{object_id}",
        "Tilemap:",
        "  m_ObjectHideFlags: 0",
        "  m_CorrespondingSourceObject: {fileID: 0}",
        "  m_PrefabInstance: {fileID: 0}",
        "  m_PrefabAsset: {fileID: 0}",
        f"  m_GameObject: {{fileID: {game_object_id}}}",
        "  m_TileSpriteArray:",
    ]
    for sprite_ref in sprite_refs:
        lines.append("  - m_RefCount: 1")
        lines.append(
            f"    m_Data: {{fileID: {sprite_ref['file_id']}, guid: {sprite_ref['guid']}, type: 3}}"
        )
    lines.extend(
        [
            "  m_TileMatrixArray:",
            "  - m_RefCount: 1",
            "    e00: 1",
            "    e01: 0",
            "    e02: 0",
            "    e03: 0",
            "    e10: 0",
            "    e11: 1",
            "    e12: 0",
            "    e13: 0",
            "    e20: 0",
            "    e21: 0",
            "    e22: 1",
            "    e23: 0",
            "    e30: 0",
            "    e31: 0",
            "    e32: 0",
            "    e33: 1",
            "  m_TileColorArray:",
            "  - m_RefCount: 1",
            "    m_Data: {r: 1, g: 1, b: 1, a: 1}",
            "  m_Tiles:",
        ]
    )
    for cell in cells:
        x, y, z = cell["coords"]
        lines.extend(
            [
                f"  - first: {{x: {x}, y: {y}, z: {z}}}",
                "    second:",
                "      m_TileIndex: 0",
                f"      m_TileSpriteIndex: {cell.get('sprite_index', 0)}",
                f"      m_TileMatrixIndex: {cell.get('matrix_index', 0)}",
                f"      m_TileColorIndex: {cell.get('color_index', 0)}",
                f"      m_TileObjectToInstantiateIndex: {cell.get('object_index', 65535)}",
            ]
        )
    return "\n".join(lines)


def tilemap_renderer_doc(object_id, game_object_id, sorting_layer_id=0, sorting_order=0):
    return "\n".join(
        [
            f"--- !u!483693784 &{object_id}",
            "TilemapRenderer:",
            "  m_ObjectHideFlags: 0",
            "  m_CorrespondingSourceObject: {fileID: 0}",
            "  m_PrefabInstance: {fileID: 0}",
            "  m_PrefabAsset: {fileID: 0}",
            f"  m_GameObject: {{fileID: {game_object_id}}}",
            f"  m_SortingLayerID: {sorting_layer_id}",
            f"  m_SortingOrder: {sorting_order}",
        ]
    )


def camera_doc(object_id, game_object_id, orthographic=True, orthographic_size=5.0):
    return "\n".join(
        [
            f"--- !u!20 &{object_id}",
            "Camera:",
            "  m_ObjectHideFlags: 0",
            "  m_CorrespondingSourceObject: {fileID: 0}",
            "  m_PrefabInstance: {fileID: 0}",
            "  m_PrefabAsset: {fileID: 0}",
            f"  m_GameObject: {{fileID: {game_object_id}}}",
            f"  orthographic: {1 if orthographic else 0}",
            f"  orthographic size: {orthographic_size}",
        ]
    )


def prefab_instance_doc(object_id, prefab_guid, parent_transform_id, modifications):
    lines = [
        f"--- !u!1001 &{object_id}",
        "PrefabInstance:",
        "  m_ObjectHideFlags: 0",
        "  serializedVersion: 2",
        "  m_Modification:",
        f"    m_TransformParent: {{fileID: {parent_transform_id}}}",
        "    m_Modifications:",
    ]
    for target_id, property_path, value in modifications:
        lines.extend(
            [
                f"    - target: {{fileID: {target_id}, guid: {prefab_guid},",
                "        type: 3}",
                f"      propertyPath: {property_path}",
                f"      value: {value}",
                "      objectReference: {fileID: 0}",
            ]
        )
    lines.extend(
        [
            "    m_RemovedComponents: []",
            "    m_RemovedGameObjects: []",
            "    m_AddedGameObjects: []",
            "    m_AddedComponents: []",
            f"  m_SourcePrefab: {{fileID: 100100000, guid: {prefab_guid}, type: 3}}",
        ]
    )
    return "\n".join(lines)


def write_extracted_fixture(root, assets):
    for guid, entry in assets.items():
        asset_path = root / entry["pathname"]
        asset_path.parent.mkdir(parents=True, exist_ok=True)
        asset_path.write_bytes(entry["asset_bytes"])
        meta_path = asset_path.with_name(asset_path.name + ".meta")
        meta_path.write_text(entry["meta_text"], encoding="utf-8")


def write_unitypackage(package_path, assets):
    with tarfile.open(package_path, "w:gz") as tar:
        for guid, entry in sorted(assets.items(), key=lambda item: item[1]["pathname"]):
            add_tar_text(tar, f"{guid}/pathname", entry["pathname"])
            add_tar_bytes(tar, f"{guid}/asset", entry["asset_bytes"])
            add_tar_text(tar, f"{guid}/asset.meta", entry["meta_text"])


def add_tar_text(tar, name, text):
    add_tar_bytes(tar, name, text.encode("utf-8"))


def add_tar_bytes(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    tar.addfile(info, io.BytesIO(data))


def blank_pixels(width, height):
    return [[(0, 0, 0, 0) for _ in range(width)] for _ in range(height)]


def draw_rect(pixels, x0, y0, x1, y1, color):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            pixels[y][x] = color


def encode_png(width, height, pixels):
    rows = []
    for row in pixels:
        raw = bytearray([0])
        for r, g, b, a in row:
            raw.extend((r, g, b, a))
        rows.append(bytes(raw))
    image_data = zlib.compress(b"".join(rows))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            png_chunk(b"IHDR", ihdr),
            png_chunk(b"IDAT", image_data),
            png_chunk(b"IEND", b""),
        ]
    )


def png_chunk(chunk_type, data):
    crc = zlib.crc32(chunk_type)
    crc = zlib.crc32(data, crc) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", crc)


if __name__ == "__main__":
    main()
