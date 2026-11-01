class_name Catalog
extends RefCounted
## The content of data/ (GDD 06): one JSON file per thing, in a folder per kind. Files and folders whose name starts
## with "_" (templates, notes) are not loaded. tools/validate_content.py is the full validator; validate() here is the
## part the game checks at start-up in debug builds (GDD 02, L9: data that points at missing things stops the game).

const KINDS: Array[String] = ["items", "recipes", "buildings"]
const ITEM_CATEGORIES: Array[String] = ["raw", "material", "product", "tool", "equipment", "consumable", "special"]

var root: String = "res://data"
var tables: Dictionary = {}  # kind -> {id -> Dictionary}
var time: Dictionary = {}    # data/time.json, with the dev variant applied when asked
var errors: PackedStringArray = []  # files that could not be read


static func load_from(root_dir: String = "res://data", dev_time: bool = false) -> Catalog:
	var c := Catalog.new()
	c.root = root_dir
	for kind: String in KINDS:
		c.tables[kind] = c._load_folder(root_dir.path_join(kind))
	c.time = c._load_json(root_dir.path_join("time.json"))
	if dev_time and c.time.has("dev"):
		for k: String in c.time["dev"]:
			c.time[k] = c.time["dev"][k]
	return c


func items() -> Dictionary:
	return tables.get("items", {})


func recipes() -> Dictionary:
	return tables.get("recipes", {})


func buildings() -> Dictionary:
	return tables.get("buildings", {})


func item(id: String) -> Dictionary:
	return items().get(id, {})


## Cross references between catalogs. Returns readable messages; empty means sound.
func validate() -> PackedStringArray:
	var out := errors.duplicate()
	for t: String in ["seasons", "days_per_season", "real_seconds_per_day", "phase_starts", "start_minute"]:
		if not time.has(t):
			out.append("time.json: missing %s" % t)
	for id: String in items():
		var it: Dictionary = items()[id]
		if not str(it.get("category", "")) in ITEM_CATEGORIES:
			out.append("items/%s: unknown category %s" % [id, it.get("category")])
		if float(it.get("base_price", 0)) <= 0.0:
			out.append("items/%s: base_price must be > 0" % id)
		if int(it.get("max_stack", 0)) < 1:
			out.append("items/%s: max_stack must be >= 1" % id)
	for id: String in recipes():
		var r: Dictionary = recipes()[id]
		if not buildings().has(str(r.get("building", ""))):
			out.append("recipes/%s: unknown building %s" % [id, r.get("building")])
		else:
			var zones: Array = buildings()[str(r["building"])].get("zones", []).map(func(z: Dictionary) -> String: return str(z["id"]))
			if not str(r.get("zone", "")) in zones:
				out.append("recipes/%s: building %s has no zone %s" % [id, r["building"], r.get("zone")])
		for inp: Dictionary in r.get("inputs", []):
			if not items().has(str(inp.get("item", ""))):
				out.append("recipes/%s: unknown input item %s" % [id, inp.get("item")])
		if not items().has(str(r.get("output", {}).get("item", ""))):
			out.append("recipes/%s: unknown output item %s" % [id, r.get("output", {}).get("item")])
	return out


func _load_folder(dir_path: String) -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var files := DirAccess.get_files_at(dir_path)
	files.sort()
	for f: String in files:
		if f.begins_with("_") or not f.ends_with(".json"):
			continue
		var d := _load_json(dir_path.path_join(f))
		if d.is_empty():
			continue
		var id := str(d.get("id", ""))
		if id != f.get_basename():
			errors.append("%s: id %s does not match the file name" % [dir_path.path_join(f), id])
			continue
		out[id] = d
	return out


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("%s: missing" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		errors.append("%s: bad JSON (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	var d: Dictionary = SaveFile.intify(json.data)
	for k: String in d.keys():
		if k.begins_with("_"):
			d.erase(k)
	return d
