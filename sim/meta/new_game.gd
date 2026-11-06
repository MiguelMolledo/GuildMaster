class_name NewGame
extends RefCounted
## Starting a game: a fresh state, or a scenario (a saved game in data/scenarios/<id>.json) loaded as is.
## A real game starts from a start (data/starts/<id>.json, GDD 4.16): from_start (subgrim «cuentas», H3).

const SCENARIOS_DIR: String = "res://data/scenarios"


static func fresh(catalog: Catalog, world_seed: int) -> WorldState:
	var s := WorldState.new()
	s.seed_rng(world_seed)
	s.clock["minute"] = int(catalog.time.get("start_minute", 0))
	s.meta = {"title": "new_game"}
	return s


## {"ok": true, "state": WorldState} or {"ok": false, "error": ...}; `world_seed` >= 0 replaces the scenario's seed.
static func from_scenario(id: String, world_seed: int = -1) -> Dictionary:
	var r := SaveFile.load_file(SCENARIOS_DIR.path_join(id + ".json"))
	if r["ok"] and world_seed >= 0:
		(r["state"] as WorldState).seed_rng(world_seed)
	return r


## A new game from a start (GDD 4.16): the map and its public buildings, the protagonist (choices: name, female,
## free points, colours), the family purse, the forge with its stock, the debt by `difficulty`, the rival family,
## the scripted contracts and the objective chain. {"ok": true, "state": WorldState} or {"ok": false, "error": ...}.
## Owner: subgrim «cuentas». Contract: docs/contratos/h3_mercado.md.
## Plantillas: choices.city = the settlement of data/world/region.json to start in (its map replaces the start's; the
## rest of the start is the same); without it, the start's own town (town_e). Refused: unknown_city, city_lacks_site.
## choices = {name, female, family_name, colors {primary, secondary}, stats_add {stat: points}, cast, cast_seed}; a
## missing choice takes the cast's proposal (Cast.proposal: with cast "fixed", the start's "defaults"). cast: "random"
## (default) or "fixed" (today's names, ages and tones of data/starts and data/maps: tests, scenarios, targets);
## cast_seed: the cast's seed (default Cast.sub_seed(world_seed); the new-game screen's «Otra familia» changes it). stats_add: whole points >= 0 on known stats, at most free_points in total, each
## stat ending in [stat_min, stat_max]; otherwise {"ok": false, "error": "bad_choices"}.
## Ids: the player family fam_0001, the protagonist chr_0001, the player building bld_0001; the rival after them;
## then the public buildings of the map (sorted by site name); then (H4) the townsfolk of the map's "population", in
## its order: per household a family, its house and its members (at home, inside the house); the loan lon_0001; the
## scripted contracts ctr_0001...
static func from_start(catalog: Catalog, start_id: String, difficulty: String, choices: Dictionary,
		world_seed: int) -> Dictionary:
	var start: Dictionary = catalog.starts().get(start_id, {})
	if start.is_empty():
		return {"ok": false, "error": "unknown_start"}
	if choices.has("city"):  # plantillas: where the game starts (a settlement of data/world/region.json)
		var why := city_problem(catalog, start_id, str(choices["city"]))
		if why != "":
			return {"ok": false, "error": why}
		start = start_in(catalog, start_id, str(choices["city"]), world_seed)
	var levers := catalog.difficulty_levels(difficulty)
	if levers.is_empty():
		return {"ok": false, "error": "unknown_difficulty"}
	var map: Dictionary = catalog.maps().get(str(start.get("map", "")), {})
	if map.is_empty():
		return {"ok": false, "error": "unknown_map"}
	# Población: the cast (sim/meta/cast.gd). "fixed" keeps the names, ages and tones of the data (tests, scenarios,
	# targets); "random" (the default, a player's new game) deals them with the cast seed (a sub-seed of the world's).
	var mode: Variant = choices.get("cast", Cast.RANDOM)
	var cast_seed: Variant = choices.get("cast_seed", Cast.sub_seed(world_seed))
	if not str(mode) in Cast.MODES or not (typeof(cast_seed) in [TYPE_INT, TYPE_FLOAT]):
		return {"ok": false, "error": "bad_choices"}
	var pro := Cast.proposal(catalog, start, str(mode), int(cast_seed))
	var c := _choices(start, choices, pro)
	if c.is_empty():
		return {"ok": false, "error": "bad_choices"}
	var cast := Cast.generate(catalog, start, map, str(mode), int(cast_seed), str(c["colors"]["primary"]))
	var applied := Cast.apply(start, map, cast)
	start = applied["start"]
	map = applied["map"]
	var s := fresh(catalog, world_seed)
	s.cast = {"mode": str(mode), "seed": int(cast_seed), "map": str(start["map"])}
	s.map_id = str(start["map"])
	s.difficulty = difficulty
	s.meta = {"title": "new_game", "start": start_id}
	if choices.has("city"):
		s.meta["city"] = str(choices["city"])
	var st: Dictionary = start.get("start", {})
	var day0 := int(st.get("day", 0))
	var season := Clock.season(day0 * Clock.MINUTES_PER_DAY, catalog.time)
	s.clock["minute"] = day0 * Clock.MINUTES_PER_DAY + int(catalog.time["phase_starts"][season][str(st.get("phase", "dawn"))])
	var sites: Dictionary = map.get("buildings", {})
	# The player's family, protagonist and building.
	var pr: Dictionary = start["protagonist"]
	var fam := _add_family(s, str(c["family_name"]), "human", c["colors"], int(start.get("family", {}).get("gold", 0)),
		int(start.get("family", {}).get("reputation", 0)), "")
	var spawn: Array = map.get("spawns", {}).get(str(pr.get("spawn", "player")), [0, 0])
	var hero := _add_character(s, catalog, fam, str(c["name"]), bool(c["female"]), "human", c["stats"], spawn,
		float(pr.get("carry_weight", 30.0)), pr.get("equipment", {}))
	# H8: age, class, trade and the palette tones (GDD 4.10.9) of the protagonist; the family's head and founder.
	_set_kin(s, catalog, hero, int(pr.get("age", 20)), str(start.get("class", "artisan")),
		str(start.get("profession", "")), c["visual"])
	s.families[fam]["class"] = str(start.get("class", "artisan"))
	var b: Dictionary = start["building"]
	var forge := _add_building(s, catalog, sites, str(b["site"]), fam, b.get("inventory", []))
	# The rival family (GDD 4.5.5): its craft comes from the difficulty.
	var rv: Dictionary = start.get("rival", {})
	if not rv.is_empty():
		var rc: Dictionary = rv["character"]
		var rstats: Dictionary = (rc["stats"] as Dictionary).duplicate()
		if levers.has("rival_craft"):
			rstats["craft"] = int(levers["rival_craft"])
		var rfam := _add_family(s, str(rv.get("family_name", "")), "ai", rv.get("colors", {}), int(rv.get("gold", 0)),
			0, str(rv.get("profile", "")))
		var att: Dictionary = catalog.ai_profiles().get(str(rv.get("profile", "")), {}).get("initial_attitudes", {})
		for k: String in att:  # H11: the rival's attitudes from its profile (04c, provisional)
			s.families[rfam]["attitudes"][k] = int(att[k])
		var rb: Dictionary = rv["building"]
		var rsite: Dictionary = sites[str(rb["site"])]
		var rchr := _add_character(s, catalog, rfam, str(rc.get("name", "")), bool(rc.get("female", false)), "ai",
			rstats, rsite["door"], float(pr.get("carry_weight", 30.0)), {})
		_set_kin(s, catalog, rchr, int(rc.get("age", 30)), str(start.get("class", "artisan")),
			str(rv.get("profession", start.get("profession", ""))), rc.get("visual", {}))
		var rbld := _add_building(s, catalog, sites, str(rb["site"]), rfam, rb.get("inventory", []))
		s.characters[rchr]["location"] = rbld
		var r0 := int(start.get("rival_to_player", 0))  # H13: a city's rival starts with an eye on the newcomer
		if r0 > 0:
			Hostility.book(s)["values"][rfam + "|" + fam] = r0
	# The public buildings of the map (owner "" in the map), sorted by site.
	var names: Array = sites.keys()
	names.sort()
	for n: String in names:
		if sites[n].has("owner") and str(sites[n]["owner"]) == "":
			_add_building(s, catalog, sites, n, "", [])
	# H4: the townsfolk (GDD 4.11.1): unemployed adults at home, the candidates to hire (docs/contratos/h4_empleados.md).
	add_population(s, catalog, map)
	# H10: the procedural government (GDD 4.12.3): household titles and the offices handed out.
	if Offices.has_town_hall(s, catalog) and not catalog.offices().is_empty():
		Offices.setup(s, catalog)
	# H12: the competitor workshops of the other trades (GDD 4.5.5 style): after everything else, so the ids of the
	# families, characters and buildings of before do not move.
	for cp: Dictionary in start.get("competitors", []):
		_add_competitor(s, catalog, sites, start, cp, float(pr.get("carry_weight", 30.0)), levers)
	# Posada (04f §4.27, O-V7 a): the buildings for sale of the map ("for_sale": the Taberna-Posada), empty and without
	# owner until a family buys them (buy_building). After everything else, so the ids of before do not move.
	for n: String in names:
		if bool(sites[n].get("for_sale", false)):
			var sale := _add_building(s, catalog, sites, n, "", [])
			s.buildings[sale]["for_sale"] = true
	# The loan that paid the forge (no gold comes in), due at the end of day start.day + term_days - 1.
	var ln: Dictionary = start.get("loan", {})
	var debt := int(levers.get("start_debt", 0))
	if debt > 0 and not ln.is_empty():
		Loans.create(s, fam, ln, debt, (day0 + int(ln.get("term_days", 8))) * Clock.MINUTES_PER_DAY, forge)
	# The scripted contracts on the board (the shape of docs/contratos/h3_mercado.md; pay fixed when posted).
	var sim := Sim.new(s, catalog)
	var premium := float(_contract_table(catalog, str(start.get("profession", ""))).get("premium", 0.0))
	for sc: Dictionary in start.get("contracts", []):
		var item := str(sc["item"])
		var q := int(sc.get("min_quality", 0))
		var qty := int(sc.get("qty", 1))
		(s.contracts["board"] as Array).append({"id": Ids.next(s, "ctr"), "client": str(sc["client"]), "item": item,
			"qty": qty, "min_quality": q, "deadline_days": int(sc.get("deadline_days", 1)),
			"pay": roundi(qty * Market.price(sim, item, q, "sell") * (1.0 + premium)), "posted": day0,
			"script": str(sc.get("script", "")), "family": "", "actor": "", "accepted": -1, "due": -1})
	Objectives.start(s, catalog, fam, start.get("objectives", []))
	if OS.is_debug_build():
		print("[NewGame] partida nueva %s (%s, semilla %d): %s «%s» de la familia %s, deuda %d, %d encargos" % [start_id,
			difficulty, world_seed, hero, c["name"], c["family_name"], debt, (s.contracts["board"] as Array).size()])
	# The same numbers a loaded game has (integral floats become int, SaveFile.intify): a new game and its save play
	# the same.
	return {"ok": true, "state": WorldState.from_dict(s.to_dict())}


## Plantillas (where you start): the settlements of the region a game can start in, in the order of
## data/world/region.json (the home town first); each one plays the start on its map.
static func cities(catalog: Catalog) -> Array:
	var out: Array = []
	for st: Dictionary in catalog.region.get("settlements", []):
		if catalog.maps().has(str(st.get("map", ""))):
			out.append(str(st["id"]))
	return out


## The settlement of the region with this id ({} if there is none).
static func city(catalog: Catalog, id: String) -> Dictionary:
	for st: Dictionary in catalog.region.get("settlements", []):
		if str(st.get("id", "")) == id:
			return st
	return {}


## The settlement whose map is the start's own (the town a start plays when no city is chosen; "" if none).
static func start_city(catalog: Catalog, start_id: String) -> String:
	var m := str(catalog.starts().get(start_id, {}).get("map", ""))
	for st: Dictionary in catalog.region.get("settlements", []):
		if str(st.get("map", "")) == m:
			return str(st["id"])
	return ""


## H13 · O-R1 (proposal, waiting for the owner): the town the new game screen offers first. data/world/region.json
## "default_city" ("" = off: the start's own town, Vilarrasa, as always); a city where the start cannot be played falls
## back to the start's own. Only the screen reads it: NewGame.from_start without a city still plays the start's map.
static func default_city(catalog: Catalog, start_id: String) -> String:
	var c := str(catalog.region.get("default_city", ""))
	if c != "" and city_problem(catalog, start_id, c) == "":
		return c
	return start_city(catalog, start_id)


## Why the start cannot be played in this city ("" = it can): unknown_city, or city_lacks_site when its map has no
## site the start places (the player's, the rival's and the competitors' buildings).
static func city_problem(catalog: Catalog, start_id: String, id: String) -> String:
	var c := city(catalog, id)
	var map: Dictionary = catalog.maps().get(str(c.get("map", "")), {})
	if c.is_empty() or map.is_empty():
		return "unknown_city"
	var start: Dictionary = catalog.starts().get(start_id, {})
	var sites: Dictionary = map.get("buildings", {})
	var need: Array = [str(start.get("building", {}).get("site", ""))]
	if start.get("rival") is Dictionary and not (start["rival"] as Dictionary).is_empty():
		need.append(str(start["rival"].get("building", {}).get("site", "")))
	for cp: Dictionary in start.get("competitors", []):
		need.append(str(cp.get("building", {}).get("site", "")))
	for n: String in need:
		if n != "" and not sites.has(n):
			return "city_lacks_site"
	return ""


## A copy of the start that plays on the map of `city` (the start as it is for "" or its own town).
static func start_in(catalog: Catalog, start_id: String, id: String, world_seed: int = 0) -> Dictionary:
	var start: Dictionary = catalog.starts().get(start_id, {})
	var c := city(catalog, id)
	if id == "" or c.is_empty() or str(c.get("map", "")) == str(start.get("map", "")):
		return start
	var out := start.duplicate()
	out["map"] = str(c["map"])
	var af: Dictionary = c.get("ai_families", {})
	if not af.is_empty():
		_city_rivals(catalog, out, af, world_seed)
	return out


## H13 (04c 4.21.7.2, Q3): the AI families of a city with "ai_families" (Bellcaire): the start's rival keeps its
## profile (fixed); its competitors and the city's extra families (the ones whose site is on the map) get, in that
## order, draw_count profiles of draw, taken by the world seed (a hash per profile: the same seed, the same families).
static func _city_rivals(catalog: Catalog, out: Dictionary, af: Dictionary, world_seed: int) -> void:
	var map: Dictionary = catalog.maps().get(str(out["map"]), {})
	var sites: Dictionary = map.get("buildings", {})
	var mine := str(out.get("building", {}).get("site", ""))
	var comps: Array = []
	for cp: Dictionary in out.get("competitors", []):
		comps.append(cp.duplicate(true))
	for ex: Dictionary in af.get("extra", []):
		var site := str(ex.get("building", {}).get("site", ""))
		if sites.has(site) and site != mine:
			comps.append(ex.duplicate(true))
	var pool: Array = (af.get("draw", []) as Array).duplicate()
	pool.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ha := ("%d|%s" % [world_seed, a]).hash()
		var hb := ("%d|%s" % [world_seed, b]).hash()
		return ha < hb or (ha == hb and str(a) < str(b)))
	var n := mini(int(af.get("draw_count", pool.size())), pool.size())
	for i: int in comps.size():
		if i < n:
			comps[i]["profile"] = str(pool[i])
	out["competitors"] = comps
	if int(af.get("rival_to_player", 0)) > 0:
		out["rival_to_player"] = int(af["rival_to_player"])
	if out.get("rival") is Dictionary and str(af.get("fixed", "")) != "":
		var rv: Dictionary = (out["rival"] as Dictionary).duplicate(true)
		rv["profile"] = str(af["fixed"])
		out["rival"] = rv
	if OS.is_debug_build():
		print("[NewGame] familias IA de %s (semilla %d): %s" % [out["map"], world_seed,
			comps.map(func(cp: Dictionary) -> String: return "%s=%s" % [cp.get("family_name", ""), cp.get("profile", "")])])


## The validated choices with the defaults filled in, or {} if something is wrong.
## H12: one competitor of a start ("competitors"): an AI family with its ai_profile (RivalAI plays it like the rival
## smith), its artisan of the given profession and its workshop on its map site with its stock. Its craft comes from
## the difficulty like the rival smith's (GDD 4.23).
static func _add_competitor(s: WorldState, catalog: Catalog, sites: Dictionary, start: Dictionary, cp: Dictionary,
		carry: float, levers: Dictionary) -> void:
	var cc: Dictionary = cp["character"]
	var stats: Dictionary = (cc.get("stats", {}) as Dictionary).duplicate()
	if levers.has("rival_craft"):
		stats["craft"] = int(levers["rival_craft"])
	var fam := _add_family(s, str(cp.get("family_name", "")), "ai", cp.get("colors", {}), int(cp.get("gold", 0)), 0,
		str(cp.get("profile", "")))
	var att: Dictionary = catalog.ai_profiles().get(str(cp.get("profile", "")), {}).get("initial_attitudes", {})
	for k: String in att:
		s.families[fam]["attitudes"][k] = int(att[k])
	var cb: Dictionary = cp["building"]
	var site: Dictionary = sites[str(cb["site"])]
	var chr := _add_character(s, catalog, fam, str(cc.get("name", "")), bool(cc.get("female", false)), "ai",
		stats, site["door"], carry, {})
	_set_kin(s, catalog, chr, int(cc.get("age", 30)), str(start.get("class", "artisan")), str(cp.get("profession", "")),
		cc.get("visual", {}))
	var bld := _add_building(s, catalog, sites, str(cb["site"]), fam, cb.get("inventory", []))
	s.characters[chr]["location"] = bld
	var sp: Dictionary = cp.get("spouse", {})
	if not sp.is_empty():  # married from the start: a married head does not court (FamilyAI)
		var mate := _add_character(s, catalog, fam, str(sp.get("name", "")), bool(sp.get("female", false)), "ai",
			sp.get("stats", cc.get("stats", {})), site["door"], carry, {})
		_set_kin(s, catalog, mate, int(sp.get("age", 30)), str(start.get("class", "artisan")), "", sp.get("visual", {}))
		s.characters[mate]["location"] = bld
		s.characters[chr]["spouse"] = mate
		s.characters[mate]["spouse"] = chr
		var wife: Dictionary = s.characters[mate] if bool(sp.get("female", false)) else s.characters[chr]
		if not wife.get("life") is Dictionary:
			wife["life"] = {}
		wife["life"]["wedding_day"] = Clock.day(int(s.clock["minute"])) - int(catalog.time.get("days_per_season", 2)) * 4
	if OS.is_debug_build():
		print("[NewGame] competidor %s (%s, %s) en %s" % [fam, cp.get("family_name", ""), cp.get("profession", ""), bld])


## pro: the cast's proposal for the protagonist (Cast.proposal): the name of the chosen sex, the family name and the
## tones a missing choice takes (with the fixed cast, the start's defaults).
static func _choices(start: Dictionary, choices: Dictionary, pro: Dictionary) -> Dictionary:
	var d: Dictionary = start.get("defaults", {})
	var pr: Dictionary = start.get("protagonist", {})
	var female := bool(choices.get("female", d.get("female", false)))
	var name := str(choices.get("name", pro.get("name_f" if female else "name_m", d.get("name", "")))).strip_edges()
	var family_name := str(choices.get("family_name", pro.get("family_name", d.get("family_name", "")))).strip_edges()
	if name == "" or family_name == "":
		return {}
	var colors: Variant = choices.get("colors", d.get("colors", {}))
	if not colors is Dictionary:
		return {}
	for k: String in ["primary", "secondary"]:
		if not (colors as Dictionary).has(k) or not Color.html_is_valid(str(colors[k])):
			return {}
	var add: Variant = choices.get("stats_add", {})
	if not add is Dictionary:
		return {}
	var stats: Dictionary = (pr.get("stats", {}) as Dictionary).duplicate()
	var spent := 0
	for k: Variant in add:
		var v: Variant = add[k]
		if not stats.has(str(k)) or not (typeof(v) in [TYPE_INT, TYPE_FLOAT]) or float(v) != floorf(float(v)) or int(v) < 0:
			return {}
		stats[str(k)] = int(stats[str(k)]) + int(v)
		spent += int(v)
	if spent > int(pr.get("free_points", 0)):
		return {}
	for k: String in stats:
		if int(stats[k]) < int(pr.get("stat_min", 1)) or int(stats[k]) > int(pr.get("stat_max", 10)):
			return {}
	var pv: Dictionary = pro.get("visual", d.get("visual", {}))
	var visual: Variant = choices.get("visual", pv)
	if not visual is Dictionary:
		return {}
	for k: String in ["hair", "skin"]:
		var v: Variant = (visual as Dictionary).get(k, 0)
		if not (typeof(v) in [TYPE_INT, TYPE_FLOAT]) or int(v) < 0:
			return {}
	var vis := {"hair": int(visual.get("hair", 0)), "skin": int(visual.get("skin", 0))}
	var pk := "portrait_f" if female else "portrait_m"
	if pv.get(pk) is Dictionary:  # población: the proposal has one portrait per sex
		vis["portrait"] = (pv[pk] as Dictionary).duplicate()
	return {"name": name, "female": female, "family_name": family_name,
		"colors": {"primary": str(colors["primary"]), "secondary": str(colors["secondary"])}, "stats": stats,
		"visual": vis}


## The map's "population" (H4): per household, in order, a family (controlled_by "ai", no ai_profile), its house (the
## map site `home`, owned by the family) and its members inside it (location = home = the house, position = its door),
## with their trade rank. Returns the new character ids.
static func add_population(s: WorldState, catalog: Catalog, map: Dictionary) -> Array:
	var sites: Dictionary = map.get("buildings", {})
	var out: Array = []
	for hh: Dictionary in map.get("population", []):
		var site := str(hh["home"])
		var fam := _add_family(s, str(hh.get("family_name", "")), "ai", hh.get("colors", {}), int(hh.get("gold", 0)), 0, "")
		var house := _add_building(s, catalog, sites, site, fam, [])
		for p: Dictionary in hh.get("members", []):
			var id := _add_character(s, catalog, fam, str(p["name"]), bool(p.get("female", false)), "ai", p["stats"],
				sites[site]["door"], 30.0, {})
			var ch: Dictionary = s.characters[id]
			ch["location"] = house
			ch["home"] = house
			ch["rank"] = str(p.get("rank", ""))
			_set_kin(s, catalog, id, int(p.get("age", SaveFile.MIGRATION_AGE)), "artisan",
				"blacksmith" if str(p.get("rank", "")) != "" else "", p.get("visual", {}))
			if p.has("birth_offset"):  # población: a day inside the birth year keeps the data's order of age (Cast)
				ch["birth_day"] = int(ch["birth_day"]) + int(p["birth_offset"])
			out.append(id)
	# H7: each adult townsperson gets its trade (a workplace of the map, docs/contratos/h7_ciudad.md).
	TownLife.assign_occupations(s, catalog)
	if OS.is_debug_build() and not out.is_empty():
		print("[NewGame] población: %d vecinos en %d casas" % [out.size(), (map.get("population", []) as Array).size()])
	return out


static func _add_family(s: WorldState, name: String, ctrl: String, colors: Dictionary, gold: int, reputation: int,
		profile: String) -> String:
	var id := Ids.next(s, "fam")
	s.families[id] = {"id": id, "name": name, "controlled_by": ctrl, "members": [], "colors": colors.duplicate(),
		"gold": gold, "reputation": reputation, "ai_profile": profile, "ai_state": {}}
	s.families[id].merge(Kin.family_fields("", "artisan"))  # H8: the head and founder is its first member
	s.families[id].merge(Reputation.family_fields())  # H9: the common title, no class modifiers, an empty log
	s.families[id]["attitudes"] = {"honesty": 0, "generosity": 0, "diplomacy": 0}  # H11 (GDD 4.2.3)
	return id


static func _add_character(s: WorldState, catalog: Catalog, fam: String, name: String, female: bool, ctrl: String,
		stats: Dictionary, pos: Array, carry: float, equipment: Dictionary) -> String:
	var id := Ids.next(s, "chr")
	var eq := {"tool": null, "clothes": null, "accessory": null}
	var worn := 0.0
	for slot: String in equipment:
		var e: Dictionary = equipment[slot]
		eq[slot] = {"item": str(e["item"]), "quality": int(e.get("quality", 0))}
		worn += float(catalog.item(str(e["item"])).get("weight", 0.0))
	s.characters[id] = {"id": id, "name": name, "female": female, "family": fam, "controlled_by": ctrl, "alive": true,
		"position": [int(pos[0]), int(pos[1])], "path": [], "move_progress": 0, "stats": stats.duplicate(),
		"inventory": Inventory.create("weight", carry - worn), "equipment": eq, "location": "", "station": "",
		"order_queue": [], "home": "", "rank": "", "job": null, "hire_bans": {}, "routine": {}, "occupation": "",
		"town": {}, "banished_until": -1, "ai": {}, "needs": {}}
	var start := int(catalog.family.get("needs", {}).get("start", 80))  # H14 (GDD 4.2.6)
	for k: Variant in catalog.family.get("needs", {}).get("ids", ["hunger", "rest", "social", "fun"]):
		s.characters[id]["needs"][str(k)] = start
	var n := id.get_slice("_", 1).to_int()  # H8: tones and age until _set_kin gives the real ones
	s.characters[id].merge(Kin.character_fields(Kin.birth_day_for(SaveFile.MIGRATION_AGE, int(s.clock["minute"]),
		catalog.time), "artisan", "", n % int(catalog.family.get("visual", {}).get("hair_tones", 6)),
		n % int(catalog.family.get("visual", {}).get("skin_tones", 4)), catalog.family.get("directives", {}).get("default", ["work"])))
	(s.families[fam]["members"] as Array).append(id)
	if str(s.families[fam].get("head", "")) == "":
		s.families[fam]["head"] = id
		s.families[fam]["founder"] = id
	return id


## H8: the age (born at the start of a calendar year), class, trade and palette tones of a new character; tones not
## given keep the ones from its id.
static func _set_kin(s: WorldState, catalog: Catalog, chr: String, age: int, char_class: String, profession: String,
		visual: Dictionary) -> void:
	var ch: Dictionary = s.characters[chr]
	ch["birth_day"] = Kin.birth_day_for(age, int(s.clock["minute"]), catalog.time)
	ch["class"] = char_class
	ch["profession"] = profession
	for k: String in ["hair", "skin"]:
		if visual.has(k):
			ch["visual"][k] = int(visual[k])
	if visual.get("portrait") is Dictionary:  # población: the base portrait {type, variant} (Cast)
		ch["visual"]["portrait"] = (visual["portrait"] as Dictionary).duplicate()


static func _add_building(s: WorldState, catalog: Catalog, sites: Dictionary, site: String, owner: String,
		items: Array) -> String:
	var id := Ids.next(s, "bld")
	var m: Dictionary = sites[site]
	var def: Dictionary = catalog.buildings().get(str(m["type"]), {})
	var zones := {}
	for z: Dictionary in def.get("zones", []):
		zones[str(z["id"])] = {"occupant": "", "job": null}
	var inv := Inventory.create("stacks", float(def.get("storage_stacks", 0)))
	for it: Dictionary in items:
		Inventory.add(inv, catalog, str(it["item"]), int(it.get("quality", 0)), int(it.get("qty", 0)))
	s.buildings[id] = {"id": id, "type": str(m["type"]), "owner": owner, "origin": (m["origin"] as Array).duplicate(),
		"footprint": (def.get("footprint", [1, 1]) as Array).duplicate(), "door": (m["door"] as Array).duplicate(),
		"state": "normal", "inventory": inv, "zones": zones, "upkeep_debt": 0, "upkeep_unpaid_since": -1,
		"employee_slots": int(def.get("base_employees", 0)), "queue": {"entries": [], "loop": false, "paused": false},
		"upgrades": [], "upgrade_work": null, "inspection": Upgrades.new_inspection()}
	return id


static func _contract_table(catalog: Catalog, profession: String) -> Dictionary:
	for id: String in catalog.contracts():
		if str(catalog.contracts()[id].get("profession", "")) == profession:
			return catalog.contracts()[id]
	return {}


static func scenario_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for f: String in DirAccess.get_files_at(SCENARIOS_DIR):
		if f.ends_with(".json") and not f.begins_with("_"):
			out.append(f.get_basename())
	out.sort()
	return out
