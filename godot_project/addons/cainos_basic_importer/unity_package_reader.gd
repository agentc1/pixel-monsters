@tool
extends RefCounted

const COMPRESSION_GZIP := 3
const TAR_BLOCK_SIZE := 512


func read_file(package_path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(package_path)
	if bytes.is_empty():
		return {
			"ok": false,
			"error": "Could not read unitypackage bytes: %s" % package_path,
		}
	return read_bytes(bytes, package_path.get_file())


func read_bytes(package_bytes: PackedByteArray, source_name: String = "package.unitypackage") -> Dictionary:
	if package_bytes.is_empty():
		return {
			"ok": false,
			"error": "Unitypackage payload is empty: %s" % source_name,
		}

	var tar_bytes := package_bytes.decompress_dynamic(-1, COMPRESSION_GZIP)
	if tar_bytes.is_empty():
		return {
			"ok": false,
			"error": "Failed to decompress unitypackage: %s" % source_name,
		}

	var tar_result := _read_tar_entries(tar_bytes)
	if not tar_result.get("ok", false):
		return tar_result

	return {
		"ok": true,
		"source_name": source_name,
		"groups": _group_entries(tar_result.get("entries", {})),
	}


func _read_tar_entries(tar_bytes: PackedByteArray) -> Dictionary:
	var entries := {}
	var offset := 0
	while offset + TAR_BLOCK_SIZE <= tar_bytes.size():
		var header := tar_bytes.slice(offset, offset + TAR_BLOCK_SIZE)
		if _header_is_empty(header):
			break

		var name := _read_header_string(header, 0, 100)
		var size := _read_header_octal(header, 124, 12)
		if name.is_empty():
			offset += TAR_BLOCK_SIZE
			continue

		var data_start := offset + TAR_BLOCK_SIZE
		var data_end := data_start + size
		if data_end > tar_bytes.size():
			return {
				"ok": false,
				"error": "Malformed tar entry %s in unitypackage." % name,
			}

		entries[name] = tar_bytes.slice(data_start, data_end)
		offset = data_start + int(ceil(float(size) / TAR_BLOCK_SIZE)) * TAR_BLOCK_SIZE
	return {
		"ok": true,
		"entries": entries,
	}


func _group_entries(entries: Dictionary) -> Dictionary:
	var grouped := {}
	for tar_path_variant in entries.keys():
		var tar_path := str(tar_path_variant)
		var parts := tar_path.split("/", false)
		if parts.size() < 2:
			continue

		var guid := parts[0]
		var child := parts[1]
		var group := grouped.get(guid, {
			"guid": guid,
		})
		var bytes: PackedByteArray = entries[tar_path]
		match child:
			"pathname":
				group["pathname"] = bytes.get_string_from_utf8().strip_edges()
			"asset":
				group["asset_bytes"] = bytes
			"asset.meta":
				group["meta_text"] = bytes.get_string_from_utf8()
		grouped[guid] = group
	return grouped


func _header_is_empty(header: PackedByteArray) -> bool:
	for value in header:
		if int(value) != 0:
			return false
	return true


func _read_header_string(header: PackedByteArray, start: int, length: int) -> String:
	var chars := PackedByteArray()
	var limit := min(start + length, header.size())
	for index in range(start, limit):
		var value := int(header[index])
		if value == 0:
			break
		chars.append(value)
	return chars.get_string_from_utf8().strip_edges()


func _read_header_octal(header: PackedByteArray, start: int, length: int) -> int:
	var raw := _read_header_string(header, start, length)
	if raw.is_empty():
		return 0
	var digits := ""
	for character in raw:
		if character >= "0" and character <= "7":
			digits += character
	if digits.is_empty():
		return 0
	var value := 0
	for digit in digits:
		value = value * 8 + int(digit)
	return value
