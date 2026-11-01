class_name SaveFile
extends RefCounted
## Saved games (GDD 05 §5.8): WorldState.to_dict() as JSON, written atomically (.tmp, then rename), with a version and
## chained migrations from day one. Scenarios are saved games too (data/scenarios/, tests/data/saves/).
## A broken file (empty, cut, garbage, newer version) never breaks the game: load_*() returns {"ok": false, "error": id}
## and the caller warns and offers another slot. It does not log errors itself (tests fail on any ERROR).


static func save(state: WorldState, path: String) -> Error:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var e := DirAccess.make_dir_recursive_absolute(dir)
		if e != OK:
			return e
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(state.to_dict(), "\t", true, true))
	f.close()
	return DirAccess.rename_absolute(tmp, path)


## {"ok": true, "state": WorldState} or {"ok": false, "error": "missing" | "bad_json" | "not_a_save" | "newer_version" | ...}
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "missing"}
	return from_text(FileAccess.get_file_as_string(path))


static func from_text(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {"ok": false, "error": "empty"}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "bad_json"}
	if not json.data is Dictionary or not (json.data as Dictionary).has("version"):
		return {"ok": false, "error": "not_a_save"}
	var m := migrate(json.data)
	if not m["ok"]:
		return m
	return {"ok": true, "state": WorldState.from_dict(m["data"])}


## Brings a saved dictionary up to WorldState.VERSION, one version at a time. Add a step to _step() for each new
## version and a test with a saved file of the old one (tests/data/saves/).
static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v > WorldState.VERSION:
		return {"ok": false, "error": "newer_version"}
	if v < 1:
		return {"ok": false, "error": "not_a_save"}
	var data := d.duplicate(true)
	while v < WorldState.VERSION:
		data = _step(v, data)
		v += 1
		data["version"] = v
	return {"ok": true, "data": data}


static func _step(_from_version: int, data: Dictionary) -> Dictionary:
	# match _from_version:
	#     1: data["new_field"] = default   # 1 -> 2
	return data


## The same text for the same content, whatever the number types: what hashes and comparisons use.
static func canonical(d: Variant) -> String:
	return JSON.stringify(intify(JSON.parse_string(JSON.stringify(d, "", true, true))), "", true, true)


## JSON brings every number back as float: turns the integral ones into int, at any depth.
static func intify(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and f == floorf(f) and absf(f) < 9.0e15:
				return int(f)
			return f
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for k: Variant in d.keys():
				d[k] = intify(d[k])
			return d
		TYPE_ARRAY:
			var a: Array = v
			for i: int in a.size():
				a[i] = intify(a[i])
			return a
	return v
