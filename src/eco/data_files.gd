class_name DataFiles
extends RefCounted
## Loads content from data/. JSON keeps it editable without opening code.


## Parses a JSON file. Returns null and reports an error if it can't be read.
static func load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Data file missing or empty: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("Data file is not valid JSON: %s" % path)
	return parsed


## Reads [x, z] from data as a ground position.
static func to_vec2(value: Variant) -> Vector2:
	var arr: Array = value
	return Vector2(float(arr[0]), float(arr[1]))
