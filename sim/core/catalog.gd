class_name Catalog
extends RefCounted
## The content of data/ (GDD 06): one JSON file per thing, in a folder per kind. Files and folders whose name starts
## with "_" (templates, notes) are not loaded. tools/validate_content.py is the full validator; validate() here is the
## part the game checks at start-up in debug builds (GDD 02, L9: data that points at missing things stops the game).

const KINDS: Array[String] = ["items", "recipes", "buildings", "maps"]
## H3 folders (docs/contratos/h3_mercado.md): loaded into `tables` too; not every one has a name_key.
const H3_KINDS: Array[String] = ["ai_profiles", "starts", "objectives", "contracts"]
## H7 folders (docs/contratos/h7_ciudad.md): the microevents of GDD 4.20, one file each.
const H7_KINDS: Array[String] = ["microevents"]
## H9 folders (docs/contratos/h9_titulos.md): the social titles of GDD 4.12.2, one file each.
const H9_KINDS: Array[String] = ["titles"]
## H10 folders (docs/contratos/h10_cargos.md): the public offices of GDD 4.12.3, one file each.
const H10_KINDS: Array[String] = ["offices"]
## H12 folders: the professions of each class (GDD 4.2.1), one file each: workshop, tool, start and contract table.
const H12_KINDS: Array[String] = ["professions"]
## H10: the office ranks, from the lowest (the title that opens them: unlocks.office_rank) to the mayor.
const OFFICE_RANKS: Array[String] = ["minor", "middle", "major", "mayor"]
## H10: the passive effects and the active powers an office may have (data/offices/*.json).
const OFFICE_PASSIVES: Array[String] = ["class_reputation", "tax_commission", "reputation_per_day", "sees_reports",
	"votes_ordinances"]
const OFFICE_POWERS: Array[String] = ["regulate_price", "fine_merchant", "set_tax", "seize_building", "arrest",
	"investigate", "preside_trial", "pardon", "propose_ordinance", "veto", "legislate", "declare_event", "name_title",
	"organize_festival"]
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
var upgrade_rules: Dictionary = {}  # data/upgrade_rules.json: branches, effect kinds, titles, inspections (H5)
var upgrade_trees: Dictionary = {}  # tree -> [upgrade ids] sorted (data/upgrades/<tree>/*.json; the upgrades: tables.upgrades)
var family: Dictionary = {}      # data/family.json: life cycle, courtship, children, routine, succession (H8)
var score: Dictionary = {}       # data/score.json: dynasty score by chronicle fact (H8, GDD 4.17)
var goals: Dictionary = {}       # data/goals.json: dynasty goals (H8, GDD 4.17)
var town: Dictionary = {}        # data/town.json: townsfolk routine, activities, emotions, NPC actions, counter, microevents, population (H7)
var social_phrases: Dictionary = {}  # data/social_phrases.json: phrase keys by activity, phase and profession (H7, GDD 4.11.3)
var justice: Dictionary = {}     # data/justice.json: charges, sentences, facts, trials, witnesses (H11, GDD 4.12.5)
var politics: Dictionary = {}    # data/politics.json: reputation rules and classes, the title ceremony (H9, GDD 4.12)
var seasons: Dictionary = {}     # data/seasons.json: goods groups, price and production by season (H13, GDD 4.5.3, 4.13)
var events: Dictionary = {}      # data/events.json: the global events (H13, GDD 4.13): rules and events by id
var cast: Dictionary = {}        # data/cast.json: the generated cast of a new game (names, surnames, ages, look, portraits)
var region: Dictionary = {}      # data/world/region.json: the settlements and routes of the region (09b)
var trade: Dictionary = {}       # data/world/trade.json: travel, city markets, caravans, treaties, regional events (09b)
var festivals: Dictionary = {}   # data/festivals.json: the festival calendar (4.25, docs/gdd/04f_vida_y_fiestas.md)
var festival_contracts: Dictionary = {}  # data/contracts/festivals.json (kind festival): taken out of contracts() (4.25.4)
var combat: Dictionary = {}      # data/combat.json: the duel «a tres tiempos» (draft, 04e; nothing in the sim uses it yet)
var games: Dictionary = {}       # data/games.json: the games and competitions of the fiestas and the tavern (04f §4.26)
var life_tables: Dictionary = {}  # vida (04f 4.24): data/life/<file>.json by file name: life, activities, rumors, incidents
## Población: data/portraits.json, the ids of the portrait pool (exported from assets/art/portraits/index.json by
## tools/art/portraits_catalog.py; the sim depends on data/ only): {by: {"sex|age|type": [ids sorted]}, fallback: {type:
## {age: type}}, ages, types, count}. Empty without it: nobody gets a portrait id (the view keeps the greybox).
var portrait_pool: Dictionary = {}
## Posada (docs/gdd/04f_vida_y_fiestas.md §4.27): data/inn/inn.json (rules), menu.json (the dishes) and clientele.json
## (the groups of customers); data/services.json, the demand of services of 4.22.3.2 (tavern and inn, for now).
var inn: Dictionary = {}
var services: Dictionary = {}
var errors: PackedStringArray = []  # files that could not be read
var _goods_index: Dictionary = {}  # H13: item -> [goods groups] (goods_of)
var _goods_built: bool = false


static func load_from(root_dir: String = "res://data", dev_time: bool = false) -> Catalog:
	var c := Catalog.new()
	c.root = root_dir
	for kind: String in KINDS + H3_KINDS + H7_KINDS + H9_KINDS + H10_KINDS + H12_KINDS:
		c.tables[kind] = c._load_folder(root_dir.path_join(kind))
	c.time = c._load_json(root_dir.path_join("time.json"))
	c.tiles = c._load_json(root_dir.path_join("tiles.json")).get("tiles", {})
	c.production = c._load_json(root_dir.path_join("production.json"))
	c.market = c._load_json(root_dir.path_join("market.json"))
	c.difficulty = c._load_json(root_dir.path_join("difficulty.json"))
	c.accounts = c._load_json(root_dir.path_join("accounts.json"))
	c.employees = c._load_json(root_dir.path_join("employees.json"))
	c.upgrade_rules = c._load_json(root_dir.path_join("upgrade_rules.json"))
	c._load_upgrades(root_dir.path_join("upgrades"))
	c.family = c._load_json(root_dir.path_join("family.json"))
	c.score = c._load_json(root_dir.path_join("score.json"))
	c.goals = c._load_json(root_dir.path_join("goals.json"))
	c.town = c._load_json(root_dir.path_join("town.json"))
	c.social_phrases = c._load_json(root_dir.path_join("social_phrases.json"))
	c.politics = c._load_json(root_dir.path_join("politics.json"))
	c.justice = c._load_json(root_dir.path_join("justice.json"))
	c.seasons = c._load_json(root_dir.path_join("seasons.json"))
	c.events = c._load_json(root_dir.path_join("events.json"))
	c.cast = c._load_json(root_dir.path_join("cast.json"))
	c.combat = c._load_json(root_dir.path_join("combat.json"))
	c.games = c._load_json(root_dir.path_join("games.json"))
	c.games["_combat"] = c.combat  # the tournament's bouts are duels (sim/games/tourney.gd): the games see the duel's table
	c.region = c._load_json(root_dir.path_join("world/region.json"))
	c.trade = c._load_json(root_dir.path_join("world/trade.json"))
	c.portrait_pool = c._load_json(root_dir.path_join("portraits.json"))
	c.festivals = c._load_json(root_dir.path_join("festivals.json"))
	for id: String in (c.tables.get("contracts", {}) as Dictionary).keys():  # 4.25.4: not a table of the daily board
		if str(c.tables["contracts"][id].get("kind", "")) == "festival":
			c.festival_contracts = c.tables["contracts"][id]
			c.tables["contracts"].erase(id)
	for f: String in ["life", "activities", "rumors", "incidents"]:  # vida (04f 4.24): data/life/
		c.life_tables[f] = c._load_json(root_dir.path_join("life/%s.json" % f))
	c.inn = {"rules": c._load_json(root_dir.path_join("inn/inn.json")),  # posada (04f §4.27)
		"menu": c._load_json(root_dir.path_join("inn/menu.json")),
		"clientele": c._load_json(root_dir.path_join("inn/clientele.json"))}
	c.services = c._load_json(root_dir.path_join("services.json"))
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


## H12: the professions of data/professions/ (GDD 4.2.1), by id.
func professions() -> Dictionary:
	return tables.get("professions", {})


## H12: the profession ids of `char_class` in their "order".
func professions_of(char_class: String) -> Array:
	var out: Array = []
	for id: String in professions():
		if str(professions()[id].get("class", "")) == char_class:
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var oa := int(professions()[a].get("order", 0))
		var ob := int(professions()[b].get("order", 0))
		return oa < ob or (oa == ob and a < b))
	return out


## H7: the microevents of data/microevents/ (GDD 4.20), by id.
func microevents() -> Dictionary:
	return tables.get("microevents", {})


## H13: the groups of data/seasons.json goods that `item` belongs to, sorted ([] if none). Built once per catalog
## (call goods_reset() after changing seasons.goods at run time, as sim_runner --set does).
func goods_of(item: String) -> Array:
	if _goods_index.is_empty() and not _goods_built:
		_goods_built = true
		var groups: Dictionary = seasons.get("goods", {})
		var names: Array = groups.keys()
		names.sort()
		for g: Variant in names:
			for it: Variant in groups[g]:
				if not _goods_index.has(str(it)):
					_goods_index[str(it)] = []
				(_goods_index[str(it)] as Array).append(str(g))
	return _goods_index.get(item, [])


func goods_reset() -> void:
	_goods_index = {}
	_goods_built = false


## H13: the global events of data/events.json, by id (enabled or not).
func world_events() -> Dictionary:
	return events.get("events", {})


## H9: the social titles of data/titles/ (GDD 4.12.2), by id.
func titles() -> Dictionary:
	return tables.get("titles", {})


## H9: the title ids from the lowest rank to the highest.
func title_ladder() -> Array:
	var ids: Array = titles().keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return int(titles()[a].get("rank", 0)) < int(titles()[b].get("rank", 0)))
	return ids


## H10: the public offices of data/offices/ (GDD 4.12.3), by id.
func offices() -> Dictionary:
	return tables.get("offices", {})


## H10: the office ids in the order of the chart (order 0 = the top: the mayor), then id.
func office_chart() -> Array:
	var ids: Array = offices().keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var oa := int(offices()[a].get("order", 0))
		var ob := int(offices()[b].get("order", 0))
		return oa < ob if oa != ob else str(a) < str(b))
	return ids


## The levers of a difficulty level (data/difficulty.json), {} if unknown.
func difficulty_levels(level: String) -> Dictionary:
	return difficulty.get("levels", {}).get(level, {})


## The rank definition of data/employees.json (wage, efficiency, speed, promotion...), {} if unknown or "".
func rank(id: String) -> Dictionary:
	return employees.get("ranks", {}).get(id, {})


## H5: every upgrade of every tree, by id (data/upgrades/<tree>/<id>.json).
func upgrades() -> Dictionary:
	return tables.get("upgrades", {})


## An upgrade definition, {} if unknown.
func upgrade(id: String) -> Dictionary:
	return upgrades().get(id, {})


## The upgrade ids of a tree (sorted), [] if unknown.
func upgrade_tree(tree: String) -> Array:
	return upgrade_trees.get(tree, [])


## The definition of an effect kind (data/upgrade_rules.json effect_kinds), {} if unknown.
func effect_kind(kind: String) -> Dictionary:
	return upgrade_rules.get("effect_kinds", {}).get(kind, {})


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
		for cp: Dictionary in s.get("competitors", []):  # H12
			if not ai_profiles().has(str(cp.get("profile", ""))):
				out.append("starts/%s: competitor: unknown ai profile %s" % [id, cp.get("profile", "")])
	for id: String in professions():  # H12
		var pf: Dictionary = professions()[id]
		if not buildings().has(str(pf.get("building", ""))):
			out.append("professions/%s: unknown building %s" % [id, pf.get("building", "")])
		if not starts().has(str(pf.get("start", ""))):
			out.append("professions/%s: unknown start %s" % [id, pf.get("start", "")])
	# H4: the employees' table (tools/validate_content.py checks the rest).
	for r: String in employees.get("rank_order", []):
		if rank(r).is_empty():
			out.append("employees.json: rank_order names unknown rank %s" % r)
		elif str(rank(r).get("next", "")) != "" and rank(str(rank(r)["next"])).is_empty():
			out.append("employees.json: rank %s: unknown next rank %s" % [r, rank(r)["next"]])
	if not (employees.get("roles", {}) as Dictionary).has(str(employees.get("default_role", ""))):
		out.append("employees.json: default_role is not a role")
	out.append_array(_validate_upgrades())
	out.append_array(_validate_family())
	out.append_array(_validate_town())
	out.append_array(_validate_titles())
	out.append_array(_validate_offices())
	out.append_array(_validate_justice())
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


## H8: the family tables (tools/validate_content.py check_h8 checks the rest and the texts).
func _validate_family() -> PackedStringArray:
	var out: PackedStringArray = []
	var life: Dictionary = family.get("life", {})
	for k: String in ["school_age", "apprentice_age", "majority_age", "death"]:
		if not life.has(k):
			out.append("family.json: life.%s missing" % k)
	if int(family.get("group", {}).get("max", 0)) < 1:
		out.append("family.json: group.max must be >= 1")
	for k: String in ["male", "female"]:
		if (family.get("names", {}).get(k, []) as Array).is_empty():
			out.append("family.json: names.%s empty" % k)
	var acts: Array = family.get("routine", {}).get("actions", [])
	for ph: String in family.get("routine", {}).get("default", {}):
		if not ph in Clock.PHASES or not str(family["routine"]["default"][ph].get("action", "")) in acts:
			out.append("family.json: routine.default.%s is not a phase with a known action" % ph)
	for g: Dictionary in goals.get("goals", []):
		if not str(g.get("kind", "")) in ["generation", "wealth", "office"]:
			out.append("goals.json: %s: unknown kind %s" % [g.get("id", "?"), g.get("kind")])
	if score.get("points", {}).is_empty():
		out.append("score.json: points missing")
	return out


## H7: the town tables and the microevents (tools/validate_content.py check_h7 checks the rest and the texts).
const MEV_EFFECTS: Array[String] = ["sell", "skill_check", "leave", "emotion", "relation", "pay", "loyalty", "absent",
	"refund_wage", "steal", "nothing", "reputation"]


func _validate_town() -> PackedStringArray:
	var out: PackedStringArray = []
	for k: String in ["routine", "activities", "personality", "emotions", "actions", "skill_check", "counter",
			"microevents", "population"]:
		if not town.has(k):
			out.append("town.json: %s missing" % k)
	for e: String in town.get("emotions", {}):
		var d: Array = town["emotions"][e].get("duration_days", [])
		if d.size() != 2 or float(d[0]) <= 0.0 or float(d[0]) > float(d[1]):
			out.append("town.json: emotions.%s.duration_days must be [min, max] > 0" % e)
	for id: String in microevents():
		var m: Dictionary = microevents()[id]
		var ids: Array = []
		for c: Dictionary in m.get("choices", []):
			ids.append(str(c.get("id", "")))
			out.append_array(_check_effects("microevents/%s/%s" % [id, c.get("id", "")], c.get("effects", [])))
		if not str(m.get("default_choice", "")) in ids:
			out.append("microevents/%s: default_choice %s is not a choice" % [id, m.get("default_choice")])
		if not str(m.get("trigger", {}).get("phase", "")) in Clock.PHASES:
			out.append("microevents/%s: trigger.phase must be a phase of the day" % id)
	out.append_array(_check_h13())
	return out


## H13: seasons.json and events.json point at known items, seasons, groups and effect kinds.
func _check_h13() -> PackedStringArray:
	var out: PackedStringArray = []
	var groups: Dictionary = seasons.get("goods", {})
	for g: String in groups:
		for it: Variant in groups[g]:
			if item(str(it)).is_empty():
				out.append("seasons.json: goods.%s: unknown item %s" % [g, it])
	for table: String in ["price", "production"]:
		for s: String in seasons.get(table, {}):
			if not s in (time.get("seasons", []) as Array):
				out.append("seasons.json: %s.%s: unknown season" % [table, s])
				continue
			for g: String in seasons[table][s]:
				if not groups.has(g) or float(seasons[table][s][g]) <= 0.0:
					out.append("seasons.json: %s.%s.%s: unknown group or mult <= 0" % [table, s, g])
	for id: String in world_events():
		var ev: Dictionary = world_events()[id]
		if not str(ev.get("scope", "")) in WorldEvents.SCOPES:
			out.append("events.json: %s: scope must be season or local" % id)
		for x: Variant in ev.get("excludes", []):
			if not world_events().has(str(x)):
				out.append("events.json: %s: excludes unknown event %s" % [id, x])
		for e: Dictionary in ev.get("effects", []):
			var k := str(e.get("kind", ""))
			if not k in WorldEvents.EFFECTS:
				out.append("events.json: %s: unknown effect %s" % [id, k])
			elif k in WorldEvents.GROUP_EFFECTS and not groups.has(str(e.get("group", ""))):
				out.append("events.json: %s: effect %s on unknown group %s" % [id, k, e.get("group")])
	return out


func _check_effects(where: String, effects: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for e: Dictionary in effects:
		if not str(e.get("kind", "")) in MEV_EFFECTS:
			out.append("%s: unknown effect %s" % [where, e.get("kind")])
		out.append_array(_check_effects(where, e.get("success", [])))
		out.append_array(_check_effects(where, e.get("fail", [])))
	return out


## H9: the title ladder is the one of data/upgrade_rules.json (ranks 0..n-1 in that order) and politics.json has its
## tables (tools/validate_content.py check_h9 checks the rest and the texts).
func _validate_titles() -> PackedStringArray:
	var out: PackedStringArray = []
	var ladder: Array = upgrade_rules.get("titles", [])
	if title_ladder() != ladder:
		out.append("titles/: the ranks give %s, upgrade_rules.titles says %s" % [title_ladder(), ladder])
	for i: int in ladder.size():
		if int(titles().get(str(ladder[i]), {}).get("rank", -1)) != i:
			out.append("titles/%s: rank must be %d" % [ladder[i], i])
	for k: String in ["reputation", "ceremony"]:
		if not politics.has(k):
			out.append("politics.json: %s missing" % k)
	return out


## H10: each office has a known rank and minimum title, a salary, a term of years and seats >= 1, known passives
## and powers; politics.json has the H10 tables (tools/validate_content.py check_h10 checks the rest and the texts).
func _validate_offices() -> PackedStringArray:
	var out: PackedStringArray = []
	for id: String in offices():
		var o: Dictionary = offices()[id]
		if not str(o.get("rank", "")) in OFFICE_RANKS:
			out.append("offices/%s: unknown rank %s" % [id, o.get("rank", "")])
		if not titles().has(str(o.get("min_title", ""))):
			out.append("offices/%s: unknown min_title %s" % [id, o.get("min_title", "")])
		for k: String in ["salary", "term_years", "seats"]:
			if int(o.get(k, 0)) < (0 if k == "salary" else 1):
				out.append("offices/%s: bad %s" % [id, k])
		for p: Dictionary in o.get("passive", []):
			if not str(p.get("kind", "")) in OFFICE_PASSIVES:
				out.append("offices/%s: unknown passive %s" % [id, p.get("kind", "")])
		for p: Dictionary in o.get("powers", []):
			if not str(p.get("id", "")) in OFFICE_POWERS:
				out.append("offices/%s: unknown power %s" % [id, p.get("id", "")])
	if not offices().is_empty():
		for k: String in ["government", "elections", "taxes", "regulation"]:
			if not politics.has(k):
				out.append("politics.json: %s missing" % k)
	return out


## H11: every charge has a known severity with its sentence, every fact kind a known charge (tools/validate_content.py
## check_h11 checks the rest and the texts).
func _validate_justice() -> PackedStringArray:
	var out: PackedStringArray = []
	if justice.is_empty():
		return out
	var sev: Array = justice.get("severities", [])
	for c: String in justice.get("charges", {}):
		if not str(justice["charges"][c].get("severity", "")) in sev:
			out.append("justice.json: charge %s: unknown severity" % c)
	for s: Variant in sev:
		if not (justice.get("sentences", {}) as Dictionary).has(str(s)):
			out.append("justice.json: no sentence for %s" % s)
	for f: String in justice.get("facts", {}):
		if not (justice.get("charges", {}) as Dictionary).has(str(justice["facts"][f])):
			out.append("justice.json: fact %s: unknown charge" % f)
	return out


## H5: the upgrade trees (GDD 4.8): ids and files, tree = folder, branch and level known, one upgrade per branch and
## level, requirements that exist in the same tree (level N needs N-1 of its branch), no cycles, known effect kinds
## with their value, cost items and stats that exist, titles of the ladder, and every building's upgrade_tree exists.
## tools/validate_content.py checks the same and the text keys.
func _validate_upgrades() -> PackedStringArray:
	var out: PackedStringArray = []
	var branches: Array = upgrade_rules.get("branches", [])
	var levels := int(upgrade_rules.get("levels", 0))
	var titles: Array = upgrade_rules.get("titles", [])
	if branches.is_empty() or levels < 1:
		out.append("upgrade_rules.json: missing branches or levels")
	var slot := {}  # "tree|branch|level" -> id
	for id: String in upgrades():
		var u: Dictionary = upgrades()[id]
		var w := "upgrades/%s/%s" % [u.get("tree", "?"), id]
		var tree := str(u.get("tree", ""))
		var branch := str(u.get("branch", ""))
		var level := int(u.get("level", 0))
		if not branch in branches:
			out.append("%s: unknown branch %s" % [w, branch])
		if level < 1 or level > levels:
			out.append("%s: level %d out of 1..%d" % [w, level, levels])
		var key := "%s|%s|%d" % [tree, branch, level]
		if slot.has(key):
			out.append("%s: same branch and level as %s" % [w, slot[key]])
		slot[key] = id
		var cost: Dictionary = u.get("cost", {})
		if int(cost.get("gold", -1)) < 0:
			out.append("%s: cost.gold must be >= 0" % w)
		for c: Dictionary in cost.get("items", []):
			if not items().has(str(c.get("item", ""))) or int(c.get("qty", 0)) < 1:
				out.append("%s: bad cost item %s" % [w, c])
		if float(u.get("build_days", 0.0)) <= 0.0:
			out.append("%s: build_days must be > 0" % w)
		var req: Dictionary = u.get("requires", {})
		var ups: Array = req.get("upgrades", [])
		for r: Variant in ups:
			var rd := upgrade(str(r))
			if rd.is_empty():
				out.append("%s: requires unknown upgrade %s" % [w, r])
			elif str(rd.get("tree", "")) != tree:
				out.append("%s: requires %s of another tree" % [w, r])
		if level > 1:
			var prev := ""
			for r: Variant in ups:
				var rd := upgrade(str(r))
				if str(rd.get("branch", "")) == branch and int(rd.get("level", 0)) == level - 1:
					prev = str(r)
			if prev == "":
				out.append("%s: level %d must require level %d of its branch" % [w, level, level - 1])
		var stat: Variant = req.get("stat", null)
		if stat is Dictionary:
			var sid := str((stat as Dictionary).get("id", ""))
			if not sid in ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial",
					"constitution", "rhetoric", "stealth"] or int((stat as Dictionary).get("min", 0)) < 1:
				out.append("%s: bad requires.stat %s" % [w, stat])
		elif stat != null:
			out.append("%s: requires.stat must be {id, min} or null" % w)
		var title: Variant = req.get("title", null)
		if title != null and not str(title) in titles:
			out.append("%s: unknown title %s" % [w, title])
		for e: Dictionary in u.get("effects", []):
			var kind := str(e.get("kind", ""))
			var ek := effect_kind(kind)
			if ek.is_empty():
				out.append("%s: unknown effect kind %s" % [w, kind])
				continue
			var value := str(ek.get("value", ""))
			if value != "flag" and not e.has(value):
				out.append("%s: effect %s needs %s" % [w, kind, value])
			elif value == "recipe" and not recipes().has(str(e[value])):
				out.append("%s: effect %s: unknown recipe %s" % [w, kind, e[value]])
			elif value == "rank" and rank(str(e[value])).is_empty():
				out.append("%s: effect %s: unknown rank %s" % [w, kind, e[value]])
	# No cycles in the requirements (the same-tree and level rules already forbid most; cross links could loop).
	for id: String in upgrades():
		if _upgrade_cycle(id, {}, 0):
			out.append("upgrades/%s: requirements loop back to it" % id)
	for b: String in buildings():
		var t: Variant = buildings()[b].get("upgrade_tree", null)
		if t != null and str(t) != "" and not upgrade_trees.has(str(t)):
			out.append("buildings/%s: unknown upgrade_tree %s" % [b, t])
	return out


func _upgrade_cycle(id: String, seen: Dictionary, depth: int) -> bool:
	if seen.has(id) or depth > upgrades().size():
		return true
	var next := seen.duplicate()
	next[id] = true
	for r: Variant in upgrade(id).get("requires", {}).get("upgrades", []):
		if upgrades().has(str(r)) and _upgrade_cycle(str(r), next, depth + 1):
			return true
	return false


## data/upgrades/<tree>/<id>.json: one folder per tree; the folder name is the tree and must match each file's tree.
func _load_upgrades(dir_path: String) -> void:
	tables["upgrades"] = {}
	upgrade_trees = {}
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var trees := DirAccess.get_directories_at(dir_path)
	trees.sort()
	for tree: String in trees:
		if tree.begins_with("_"):
			continue
		var folder := _load_folder(dir_path.path_join(tree))
		var ids: Array = []
		for id: String in folder:
			if str(folder[id].get("tree", "")) != tree:
				errors.append("%s: tree %s does not match its folder" % [dir_path.path_join(tree).path_join(id + ".json"),
					folder[id].get("tree")])
				continue
			if (tables["upgrades"] as Dictionary).has(id):
				errors.append("%s: upgrade id %s repeated in another tree" % [dir_path.path_join(tree), id])
				continue
			tables["upgrades"][id] = folder[id]
			ids.append(id)
		ids.sort()
		upgrade_trees[tree] = ids


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
