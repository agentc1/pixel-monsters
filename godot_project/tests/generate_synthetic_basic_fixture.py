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
    "prefab_bush": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "prefab_lantern": "cccccccccccccccccccccccccccccccc",
    "prefab_edge": "dddddddddddddddddddddddddddddddd",
    "prefab_stairs": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    "prefab_polygon": "ffffffffffffffffffffffffffffffff",
    "prefab_broken": "12341234123412341234123412341234",
    "prefab_player": "56785678567856785678567856785678",
}

SPRITES = {
    "bush": {"name": "TX Bush T1", "file_id": "6100000000000000001", "rect": (0, 0, 22, 19), "pivot": (0.5, 0.5)},
    "shadow_bush": {"name": "TX Shadow Bush T1", "file_id": "6100000000000000002", "rect": (0, 0, 22, 12), "pivot": (0.5, 0.5)},
    "lantern": {"name": "TX Stone Lantern", "file_id": "6100000000000000003", "rect": (0, 0, 20, 28), "pivot": (0.5, 0.5)},
    "shadow_lantern": {"name": "TX Shadow Lantern", "file_id": "6100000000000000004", "rect": (0, 0, 22, 10), "pivot": (0.5, 0.5)},
    "stairs": {"name": "TX Struct Stairs L", "file_id": "6100000000000000005", "rect": (0, 0, 32, 32), "pivot": (0.5, 0.5)},
    "edge": {"name": "TX Struct Edge", "file_id": "6100000000000000006", "rect": (32, 0, 32, 16), "pivot": (0.5, 0.5)},
    "player": {"name": "TX Player Idle", "file_id": "6100000000000000007", "rect": (0, 0, 24, 32), "pivot": (0.5, 0.0)},
    "polygon_prop": {"name": "TX Props Polygon", "file_id": "6100000000000000008", "rect": (32, 0, 24, 24), "pivot": (0.5, 0.5)},
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
            "prefab_count": 7,
            "supported_static_prefabs": 4,
            "approximated_prefabs": 1,
            "manual_behavior_prefabs": 1,
            "unresolved_or_skipped_prefabs": 1,
            "sample_prefabs": {
                "bush": "PF Plant - Bush 01",
                "lantern": "PF Props - Stone Lantern 01",
                "stairs": "PF Struct - Stairs S 01 L",
                "player": "PF Player",
                "edge": "PF Struct - Z Edge 01",
                "polygon": "PF Props - Z Polygon 01",
                "broken": "PF Props - Z Broken 01",
            },
            "lantern_box_size_px": [16.0, 24.0],
            "edge_segment_px": [[-16.0, 0.0], [16.0, 0.0]],
            "bush_shadow_position_px": [8.0, 4.0],
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
        [],
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
        [],
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
        96,
        64,
        [
            (0, 0, 19, 27, (195, 151, 85, 255)),
            (32, 0, 55, 23, (138, 101, 71, 255)),
            (64, 0, 79, 15, (176, 120, 72, 255)),
        ],
        [SPRITES["lantern"], SPRITES["polygon_prop"]],
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
        64,
        32,
        [(0, 0, 23, 31, (77, 120, 204, 255))],
        [SPRITES["player"]],
    )
    add_texture(
        assets,
        "shadow_props",
        f"{TEXTURE_ROOT}/TX Shadow.png",
        64,
        32,
        [(0, 0, 21, 9, (0, 0, 0, 180))],
        [SPRITES["shadow_lantern"]],
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

    add_prefab(assets, GUIDS["prefab_bush"], f"{PREFAB_ROOT}/Plant/PF Plant - Bush 01.prefab", bush_prefab())
    add_prefab(assets, GUIDS["prefab_lantern"], f"{PREFAB_ROOT}/Props/PF Props - Stone Lantern 01.prefab", lantern_prefab())
    add_prefab(assets, GUIDS["prefab_edge"], f"{PREFAB_ROOT}/Struct/PF Struct - Z Edge 01.prefab", edge_prefab())
    add_prefab(assets, GUIDS["prefab_stairs"], f"{PREFAB_ROOT}/Struct/PF Struct - Stairs S 01 L.prefab", stairs_prefab())
    add_prefab(assets, GUIDS["prefab_polygon"], f"{PREFAB_ROOT}/Props/PF Props - Z Polygon 01.prefab", polygon_prefab())
    add_prefab(assets, GUIDS["prefab_broken"], f"{PREFAB_ROOT}/Props/PF Props - Z Broken 01.prefab", broken_prefab())
    add_prefab(assets, GUIDS["prefab_player"], f"{PREFAB_ROOT}/Player/PF Player.prefab", player_prefab())
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


def edge_prefab():
    return "\n".join(
        [
            game_object_doc("300100", "PF Struct - Z Edge 01", ["300101", "300102", "300103"]),
            transform_doc("300101", "300100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("300102", "300100", GUIDS["struct"], SPRITES["edge"]["file_id"], sorting_order=0),
            edge_collider_doc("300103", "300100", (0.0, 0.0), [(-0.5, 0.0), (0.5, 0.0)]),
        ]
    ) + "\n"


def stairs_prefab():
    return "\n".join(
        [
            game_object_doc("400100", "PF Struct - Stairs S 01 L", ["400101", "400102", "400103"]),
            transform_doc("400101", "400100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("400102", "400100", GUIDS["struct"], SPRITES["stairs"]["file_id"], sorting_order=1),
            mono_behaviour_doc("400103", "400100", GUIDS["stairs_script"], {"lowerLayer": 1, "upperLayer": 2}),
        ]
    ) + "\n"


def polygon_prefab():
    return "\n".join(
        [
            game_object_doc("500100", "PF Props - Z Polygon 01", ["500101", "500102", "500103"]),
            transform_doc("500101", "500100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("500102", "500100", GUIDS["props"], SPRITES["polygon_prop"]["file_id"], sorting_order=0),
            polygon_collider_doc("500103", "500100"),
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
            game_object_doc("700100", "PF Player", ["700101", "700102"]),
            transform_doc("700101", "700100", "0", [], (0.0, 0.0, 0.0)),
            sprite_renderer_doc("700102", "700100", GUIDS["player"], SPRITES["player"]["file_id"], sorting_order=0),
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


def sprite_renderer_doc(object_id, game_object_id, sprite_guid, sprite_file_id, sorting_order=0):
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
            "  m_SortingLayerID: 0",
            f"  m_SortingOrder: {sorting_order}",
            "  m_FlipX: 0",
            "  m_FlipY: 0",
        ]
    )


def box_collider_doc(object_id, game_object_id, offset, size):
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
            "  m_IsTrigger: 0",
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


def mono_behaviour_doc(object_id, game_object_id, script_guid, fields):
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
    for key, value in fields.items():
        lines.append(f"  {key}: {value}")
    return "\n".join(lines)


def polygon_collider_doc(object_id, game_object_id):
    return "\n".join(
        [
            f"--- !u!60 &{object_id}",
            "PolygonCollider2D:",
            "  m_ObjectHideFlags: 0",
            "  m_CorrespondingSourceObject: {fileID: 0}",
            "  m_PrefabInstance: {fileID: 0}",
            "  m_PrefabAsset: {fileID: 0}",
            f"  m_GameObject: {{fileID: {game_object_id}}}",
            "  m_Enabled: 1",
        ]
    )


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
