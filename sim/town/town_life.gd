class_name TownLife
extends RefCounted
## The living town (GDD 4.11.1-4.11.3): the townsfolk's day. Contract: docs/contratos/h7_ciudad.md.
## Figures: data/town.json "routine", "activities", "personality". The map: data/maps/<map>.json "workplaces" and
## "social_points".
##
## A townsperson is a living character with a house (`home`) of a household family (AI without ai_profile: not the
## player's, not a rival's). Its trade (`occupation`) is a workplace of the map: where it spends the day. Its memory
## lives in character.town (JSON only).


## Whether `fam` is a household family (the townsfolk: AI without ai_profile).
static func is_household(st: WorldState, fam: String) -> bool:
	var f: Dictionary = st.families.get(fam, {})
	return not f.is_empty() and str(f.get("controlled_by", "")) == "ai" and str(f.get("ai_profile", "")) == ""


## Whether `chr` is a townsperson: alive, with a house that exists, of a household family.
static func is_townsperson(st: WorldState, chr: String) -> bool:
	var ch: Dictionary = st.characters.get(chr, {})
	if ch.is_empty() or not bool(ch.get("alive", true)):
		return false
	var home := str(ch.get("home", ""))
	if home == "" or not st.buildings.has(home):
		return false
	return is_household(st, str(ch.get("family", "")))


## Whether `chr` is a grown-up (majority age of data/family.json).
static func is_adult(st: WorldState, catalog: Catalog, chr: String) -> bool:
	var ch: Dictionary = st.characters.get(chr, {})
	var age := Clock.age_years(int(ch.get("birth_day", 0)), int(st.clock["minute"]), catalog.time)
	return age >= int(catalog.family.get("life", {}).get("majority_age", 16))


## The workplaces of the state's map, in hand-out order ([] without a map).
static func workplaces(st: WorldState, catalog: Catalog) -> Array:
	return catalog.maps().get(st.map_id, {}).get("workplaces", [])


## A workplace of the map by id ({} if none).
static func workplace(st: WorldState, catalog: Catalog, id: String) -> Dictionary:
	for w: Dictionary in workplaces(st, catalog):
		if str(w.get("id", "")) == id:
			return w
	return {}


## The townsperson whose trade is the market stall `stall` (its keeper; "" if nobody alive holds it).
static func stall_keeper(st: WorldState, catalog: Catalog, stall: String) -> String:
	var wp := ""
	for w: Dictionary in workplaces(st, catalog):
		if str(w.get("stall", "")) == stall:
			wp = str(w["id"])
			break
	if wp == "":
		return ""
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		if str(st.characters[id].get("occupation", "")) == wp and is_townsperson(st, id):
			return id
	return ""


## Gives a trade to every adult townsperson that has none: by id, each takes the workplace with the fewest living
## holders (ties: map order). A new game hands them out in map order; a migrated v7 save gets the same.
static func assign_occupations(st: WorldState, catalog: Catalog) -> void:
	var wps := workplaces(st, catalog)
	if wps.is_empty():
		return
	var holders := {}
	for w: Dictionary in wps:
		holders[str(w["id"])] = 0
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		var occ := str(st.characters[id].get("occupation", ""))
		if occ != "" and holders.has(occ) and is_townsperson(st, id):
			holders[occ] = int(holders[occ]) + 1
	for id: String in ids:
		var ch: Dictionary = st.characters[id]
		if str(ch.get("occupation", "")) != "" or not is_townsperson(st, id) or not is_adult(st, catalog, id):
			continue
		var best := ""
		for w: Dictionary in wps:
			var wid := str(w["id"])
			if best == "" or int(holders[wid]) < int(holders[best]):
				best = wid
		ch["occupation"] = best
		holders[best] = int(holders[best]) + 1
		if OS.is_debug_build():
			print("[TownLife] %s «%s» tiene oficio: %s" % [id, ch.get("name", ""), best])

