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


## v6 -> v7: the age of everybody who had none (H8, docs/contratos/h8_familia.md) [provisional].
const MIGRATION_AGE: int = 25


static func _step(from_version: int, data: Dictionary) -> Dictionary:
	match from_version:
		1:  # 1 -> 2 (H1): the town map the game runs on
			data["map_id"] = ""
		2:  # 2 -> 3 (H2): characters get stats, gold, inventory, equipment, location and an order queue
			for c: Dictionary in (data.get("characters", {}) as Dictionary).values():
				if not c.has("stats"):
					var stats := {}
					for k: String in ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial",
							"constitution", "rhetoric", "stealth"]:
						stats[k] = 3
					c["stats"] = stats
				if not c.has("gold"):
					c["gold"] = 0
				if not c.has("inventory"):
					c["inventory"] = {"limit_kind": "weight", "limit": 30.0, "stacks": []}
				if not c.has("equipment"):
					c["equipment"] = {"tool": null, "clothes": null, "accessory": null}
				for k: String in ["location", "station"]:
					if not c.has(k):
						c[k] = ""
				if not c.has("order_queue"):
					c["order_queue"] = []
		3:  # 3 -> 4 (H3): one gold purse per family (the sum of its characters' gold), reputation, ledger, notices,
			# loans, contracts, errands, difficulty, objectives, ending; buildings get their unpaid upkeep (D15)
			var families: Dictionary = data.get("families", {})
			for f: Dictionary in families.values():
				if not f.has("gold"):
					f["gold"] = 0
				if not f.has("reputation"):
					f["reputation"] = 0
				if not f.has("ai_profile"):
					f["ai_profile"] = ""
				if not f.has("ai_state"):
					f["ai_state"] = {}
			for c: Dictionary in (data.get("characters", {}) as Dictionary).values():
				if not c.has("gold"):
					continue
				var fam := str(c.get("family", ""))
				if families.has(fam):
					families[fam]["gold"] = int(families[fam]["gold"]) + int(c["gold"])
				c.erase("gold")  # a character without family loses it: there were none when v4 came
			for b: Dictionary in (data.get("buildings", {}) as Dictionary).values():
				if not b.has("upkeep_debt"):
					b["upkeep_debt"] = 0
				if not b.has("upkeep_unpaid_since"):
					b["upkeep_unpaid_since"] = -1
			var empty := {"ledger": {"entries": [], "summaries": {}}, "notices": [], "loans": {},
				"contracts": {"board": [], "accepted": [], "cooldowns": {}, "relations": {}}, "deliveries": [],
				"difficulty": "normal", "objectives": {}, "ending": {}}
			for k: String in empty:
				if not data.has(k):
					data[k] = empty[k]
		4:  # 4 -> 5 (H4): employees (docs/contratos/h4_empleados.md). Characters: home (their house), rank (their trade
			# rank, "" if none), job (null = unemployed), hire_bans {fam: until_day} and routine {} (Routines' memory).
			# Buildings: employee_slots (v4 only knew the forge, base_employees 1, and the public armory, 0) and the
			# production queue.
			for c: Dictionary in (data.get("characters", {}) as Dictionary).values():
				var add := {"home": "", "rank": "", "job": null, "hire_bans": {}, "routine": {}}
				for k: String in add:
					if not c.has(k):
						c[k] = add[k]
			for b: Dictionary in (data.get("buildings", {}) as Dictionary).values():
				if not b.has("employee_slots"):
					b["employee_slots"] = 1 if str(b.get("type", "")) == "forge" else 0
				if not b.has("queue"):
					b["queue"] = {"entries": [], "loop": false, "paused": false}
		5:  # 5 -> 6 (H5): upgrades (docs/contratos/h5_mejoras.md). Buildings: upgrades (finished upgrade ids, in the order
			# they were finished), upgrade_work (null = no works; else the works in progress) and inspection (the Secrets
			# inspections' memory). v5 had no upgrades: everything starts empty.
			for b: Dictionary in (data.get("buildings", {}) as Dictionary).values():
				if not b.has("upgrades"):
					b["upgrades"] = []
				if not b.has("upgrade_work"):
					b["upgrade_work"] = null
				if not b.has("inspection"):
					b["inspection"] = Upgrades.new_inspection()
		6:  # 6 -> 7 (H8): family and inheritance (docs/contratos/h8_familia.md). v6 had no ages nor kin: everybody
			# gets MIGRATION_AGE years at the current day (born at the start of a year: ages change at year_changed),
			# no spouse, parents nor children, the artisan class, the blacksmith trade if they work a forge (a rank
			# or a family that plays), the work directive, no routine, palette tones from the id number and an empty
			# life memory. Families: the first living member is the head, founder of generation 1, no designated heir.
			var minute := int(data.get("clock", {}).get("minute", 0))
			var year := floori(float(Clock.day(minute)) / 8.0)  # D1(b): 8 days per year (the save has no catalog)
			var birth := (year - MIGRATION_AGE) * 8
			var families: Dictionary = data.get("families", {})
			for c: Dictionary in (data.get("characters", {}) as Dictionary).values():
				var n := str(c.get("id", "chr_0")).get_slice("_", 1).to_int()
				var fam: Dictionary = families.get(str(c.get("family", "")), {})
				var plays := str(fam.get("controlled_by", "")) == "human" or str(fam.get("ai_profile", "")) != ""
				var add := {"birth_day": birth, "death_day": -1 if bool(c.get("alive", true)) else Clock.day(minute),
					"class": "artisan", "profession": "blacksmith" if plays or str(c.get("rank", "")) != "" else "",
					"spouse": "", "parents": [], "children": [], "assigned": "", "directives": ["work"],
					"schedule": null, "visual": {"hair": n % 6, "skin": n % 4}, "life": {}}
				for k: String in add:
					if not c.has(k):
						c[k] = add[k]
			for f: Dictionary in families.values():
				var head := ""
				for m: Variant in f.get("members", []):
					if bool((data.get("characters", {}) as Dictionary).get(str(m), {}).get("alive", true)):
						head = str(m)
						break
				var addf := {"head": head, "heir": "", "founder": head, "generation": 1, "regent": "", "class": "artisan",
					"goals_done": []}
				for k: String in addf:
					if not f.has(k):
						f[k] = addf[k]
		7:  # 7 -> 8 (H7): the living town (docs/contratos/h7_ciudad.md). Characters: occupation (the townsperson's trade,
			# a workplace of the map; "" here: TownLife.assign_occupations gives one to the adult townsfolk the first time
			# it runs, the same hand-out as a new game) and town (TownLife's memory). Root: microevents (GDD 4.20: active,
			# pending, cooldowns, last_day) and town (the shop counters). v7 had none: everything starts empty.
			for c: Dictionary in (data.get("characters", {}) as Dictionary).values():
				if not c.has("occupation"):
					c["occupation"] = ""
				if not c.has("town"):
					c["town"] = {}
			if not data.has("microevents"):
				data["microevents"] = {"active": [], "pending": [], "cooldowns": {}, "last_day": {}}
			if not data.has("town"):
				data["town"] = {"counters": {}}
		8:  # 8 -> 9 (H9): reputation and titles (docs/contratos/h9_titulos.md). Families: title (v8 had none: the common
			# title of everybody), class_reputation (the class modifier of GDD 4.12.1, all 0), reputation_log (the last
			# changes, empty) and reputation_caps (the rules' counters, empty). reputation stays as it was.
			for f: Dictionary in (data.get("families", {}) as Dictionary).values():
				var addf := Reputation.family_fields()
				for k: String in addf:
					if not f.has(k):
						f[k] = addf[k]
				if not f.has("reputation"):
					f["reputation"] = 0
		9:  # 9 -> 10 (H10): offices and elections (docs/contratos/h10_cargos.md). The root fields offices, elections and
			# market.regulations already were (always empty until H10): whatever has not the H10 shape starts empty. An
			# empty offices is handed out by Offices.step the first time it runs (the save has no catalog).
			var offices: Variant = data.get("offices", {})
			var shaped := offices is Dictionary
			if shaped:
				for o: Variant in (offices as Dictionary).values():
					if not o is Dictionary or not (o as Dictionary).get("seats") is Array:
						shaped = false
			if not shaped:
				data["offices"] = {}
			if not data.get("elections") is Array:
				data["elections"] = []
			var market: Variant = data.get("market", {})
			if not market is Dictionary:
				market = {"demand": {}}
				data["market"] = market
			if not (market as Dictionary).get("regulations") is Array:
				market["regulations"] = []
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
