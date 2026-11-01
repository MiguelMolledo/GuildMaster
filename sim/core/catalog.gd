class_name Catalog
extends RefCounted
## The content of data/ (GDD 06): one JSON file per thing, in a folder per kind. Files and folders whose name starts
## with "_" (templates, notes) are not loaded. tools/validate_content.py is the full validator; validate() here is the
## part the game checks at start-up in debug builds (GDD 02, L9: data that points at missing things stops the game).

const KINDS: Array[String] = ["items", "recipes", "buildings", "maps"]
## H3 folders (docs/contratos/h3_mercado.md): loaded into `tables` too; not every one has a name_key.
const H3_KINDS: Array[String] = ["ai_profiles", "starts", "objectives", "contracts"]
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]
const ITEM_CATEGORIES: Array[String] = ["raw", "material", "product", "tool", "equipment", "consumable", "special"]

var root: String = "res://data"
var tables: Dictionary = {}  # kind -> {id -> Dictionary}
var time: Dictionary = {}    # data/time.json, with the dev variant applied when asked
var tiles: Dictionary = {}   # data/tiles.json "tiles": kind -> {char, walk_cost (null = blocked), color}
var production: Dictionary = {}  # data/production.json: quality table, work modes, master touch, tool bonus
var market: Dictionary = {}      # data/market.json: stalls, opening phases, demand, sell ratio, quality, errands, board
var difficulty: Dictionary = {}  # data/difficulty.json: "levels" {easy|normal|hard -> levers} (GDD 4.23)
var accounts: Dictionary = {}    # data/accounts.json: ledger and notices retention, loan warnings, unpaid upkeep (H3)
var employees: Dictionary = {}   # data/employees.json: ranks, roles, loyalty, bands, wages, theft, hiring, schedule (H4)
var errors: PackedStringArray = []  # files that could not be read


static func load_from(root_dir: String = "res://data", dev_time: bool = false) -> Catalog:
	var c := Catalog.new()
	c.root = root_dir
	for kind: String in KINDS + H3_KINDS:
		c.tables[kind] = c._load_folder(root_dir.path_join(kind))
	c.time = c._load_json(root_dir.path_join("time.json"))
	c.tiles = c._load_json(root_dir.path_join("tiles.json")).get("tiles", {})
	c.production = c._load_json(root_dir.path_join("production.json"))
	c.market = c._load_json(root_dir.path_join("market.json"))
	c.difficulty = c._load_json(root_dir.path_join("difficulty.json"))
	c.accounts = c._load_json(root_dir.path_join("accounts.json"))
	c.employees = c._load_json(root_dir.path_join("employees.json"))
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


func maps() -> Dictionary:
	return tables.get("maps", {})


func ai_profiles() -> Dictionary:
	return tables.get("ai_profiles", {})


func starts() -> Dictionary:
	return tables.get("starts", {})


func objectives() -> Dictionary:
	return tables.get("objectives", {})


func contracts() -> Dictionary:
	return tables.get("contracts", {})


## The levers of a difficulty level (data/difficulty.json), {} if unknown.
func difficulty_levels(level: String) -> Dictionary:
	return difficulty.get("levels", {}).get(level, {})


## The rank definition of data/employees.json (wage, efficiency, speed, promotion...), {} if unknown or "".
func rank(id: String) -> Dictionary:
	return employees.get("ranks", {}).get(id, {})


## Tile kind by its 1-char map code ("=" -> "street"), "" if unknown.
func tile_kind_of_char(ch: String) -> String:
	for kind: String in tiles:
		if str(tiles[kind].get("char", "")) == ch:
			return kind
	return ""


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
	for lvl: String in DIFFICULTIES:
		if difficulty_levels(lvl).is_empty():
			out.append("difficulty.json: missing level %s" % lvl)
	for st: String in market.get("stalls", {}):
		var def: Dictionary = market["stalls"][st]
		if def.has("building") and not buildings().has(str(def["building"])):
			out.append("market.json: stall %s: unknown building %s" % [st, def["building"]])
	for id: String in starts():
		var s: Dictionary = starts()[id]
		for o: String in s.get("objectives", []):
			if not objectives().has(o):
				out.append("starts/%s: unknown objective %s" % [id, o])
		var rival_profile := str(s.get("rival", {}).get("profile", ""))
		if rival_profile != "" and not ai_profiles().has(rival_profile):
			out.append("starts/%s: unknown ai profile %s" % [id, rival_profile])
	# H4: the employees' table (tools/validate_content.py checks the rest).
	for r: String in employees.get("rank_order", []):
		if rank(r).is_empty():
			out.append("employees.json: rank_order names unknown rank %s" % r)
		elif str(rank(r).get("next", "")) != "" and rank(str(rank(r)["next"])).is_empty():
			out.append("employees.json: rank %s: unknown next rank %s" % [r, rank(r)["next"]])
	if not (employees.get("roles", {}) as Dictionary).has(str(employees.get("default_role", ""))):
		out.append("employees.json: default_role is not a role")
	for id: String in maps():
		var m: Dictionary = maps()[id]
		var size: Array = m.get("size", [0, 0])
		var rows: Array = m.get("rows", [])
		if rows.size() != int(size[1]):
			out.append("maps/%s: %d rows, size says %d" % [id, rows.size(), int(size[1])])
		for r in rows.size():
			var row := str(rows[r])
			if row.length() != int(size[0]):
				out.append("maps/%s: row %d has %d tiles, size says %d" % [id, r, row.length(), int(size[0])])
			for ch in row:
				if tile_kind_of_char(ch) == "":
					out.append("maps/%s: row %d uses unknown tile code '%s'" % [id, r, ch])
					break
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
