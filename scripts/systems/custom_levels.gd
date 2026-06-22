class_name CustomLevels
extends Object
## Persistence for editor-authored levels. A level is the same plain Dictionary
## `LevelBuilder` consumes; we serialize it with `var_to_str` / `str_to_var`,
## which round-trips Dictionary/Array/Vector2/Vector3/Color losslessly — so the
## file IS the def, no JSON type-codec needed.
##
## Files live in-repo at res://dev_levels/ (version-controlled, the dev workflow).
## res:// is read-only in an EXPORTED build, so saves fall back to user://.

const DIR := "res://dev_levels/"
const USER_DIR := "user://dev_levels/"
const EXT := ".lvl"
const FORMAT_VERSION := 1

static func _ensure(d: String) -> void:
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)

## Save `def` under `name` (no extension). Stamps world_scale=1.0 (editor works in
## final coords; the builder must not re-apply WORLD_SCALE) + a format version.
## Returns the path written, or "" on failure.
static func save_def(def: Dictionary, name: String) -> String:
	var d := def.duplicate(true)
	d["world_scale"] = 1.0
	d["format_version"] = FORMAT_VERSION
	var text := var_to_str(d)
	for base in [DIR, USER_DIR]:
		_ensure(base)
		var f := FileAccess.open(base + name + EXT, FileAccess.WRITE)
		if f:
			f.store_string(text)
			f.close()
			return base + name + EXT
	push_error("CustomLevels: could not write '%s'" % name)
	return ""

## Load a def from a full path (res:// or user://). Returns {} on failure.
static func load_def(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var v: Variant = str_to_var(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}

## Full paths of every saved level (both dirs).
static func list_paths() -> Array:
	var out: Array = []
	for base in [DIR, USER_DIR]:
		if DirAccess.dir_exists_absolute(base):
			for f in DirAccess.get_files_at(base):
				if f.ends_with(EXT):
					out.append(base + f)
	return out

## "res://dev_levels/foo.lvl" -> "foo".
static func name_of(path: String) -> String:
	return path.get_file().trim_suffix(EXT)
