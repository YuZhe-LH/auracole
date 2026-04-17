@tool
extends EditorScript

const TARGET_DIR := "res://resources/placement_logic/device_images"


func _run() -> void:
	var dir := DirAccess.open(TARGET_DIR)
	if dir == null:
		push_error("Cannot open directory: %s" % TARGET_DIR)
		return

	print("--- Device image scan start ---")
	dir.list_dir_begin()

	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		if not name.to_lower().ends_with(".png"):
			continue

		var path := "%s/%s" % [TARGET_DIR, name]
		_scan_file(path)

	dir.list_dir_end()
	print("--- Device image scan end ---")


func _scan_file(path: String) -> void:
	var exists_via_loader := ResourceLoader.exists(path)
	var exists_via_file := FileAccess.file_exists(path)
	var image_error := ERR_FILE_NOT_FOUND
	var resource_type := "<none>"
	var file_error := OK
	var header_hex := "<unreadable>"

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		file_error = FileAccess.get_open_error()
	else:
		header_hex = _bytes_to_hex(file.get_buffer(8))
		file.close()

	var image := Image.new()
	image_error = image.load(path)

	var res := ResourceLoader.load(path)
	if res != null:
		resource_type = res.get_class()

	print(
		"%s | ResourceLoader.exists=%s | FileAccess.file_exists=%s | open_error=%s | header=%s | Image.load=%s | loaded_type=%s"
		% [
			path,
			str(exists_via_loader),
			str(exists_via_file),
			error_string(file_error),
			header_hex,
			error_string(image_error),
			resource_type
		]
	)


func _bytes_to_hex(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return "<empty>"

	var parts: Array[String] = []
	for b in bytes:
		parts.append("%02X" % int(b))
	return " ".join(parts)
