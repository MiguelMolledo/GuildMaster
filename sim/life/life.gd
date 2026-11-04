class_name Life
extends RefCounted
## The living town II (docs/gdd/04f_vida_y_fiestas.md §4.24; contract docs/contratos/vida.md): the townsfolk's agenda
## (Agenda), the meeting points and rumours (Rumors), the visitors (Visitors), the town watch (Watch) and the incidents
## (Incidents). Figures: data/life/*.json (Catalog.life_tables). One switch for all of it, data/life/life.json
## "enabled": off, the town is H7's as it was (the targets fixed before 4.24 run so: data/targets.json _no_life).
##
## State (save v17, SaveFile._to_v17): state.town.life {spectacles, cries}, state.town.visitors {alive, day, planned,
## alms}, state.town.watch {guards, dispatch}, state.town.rumors {heard, told}, state.town.incidents {active, closed,
## nests, last, warned, mult}; characters: town.needs / town.needs_at (the townsfolk), visitor {kind, city, ...},
## guard {role}, bandit {incident}, offstage (not on the map: off duty, not arrived, gone), captive (kidnapped).
## Randomness: Kin.roll with keys "life|..." / "events_city|..." (never state.rng): the rolls of today do not move.

const FAMILY_WATCH: String = "fam_watch"
const FAMILY_VISITORS: String = "fam_visitors"
const FAMILY_BANDITS: String = "fam_bandits"
## Families of the town's services: not households (no hiring, no weddings), not players, not rivals.
const SERVICE_CONTROL: String = "town"


static func cfg(c: Catalog) -> Dictionary:
	return c.life_tables.get("life", {})


## Whether the living town II runs: data/life/life.json enabled and a map to live on.
static func on(sim: Sim) -> bool:
	return bool(cfg(sim.catalog).get("enabled", false)) and sim.state.map_id != ""


## The state blocks of v17 (created empty when missing: a game from before, a scenario).
static func ensure(st: WorldState) -> void:
	var t: Dictionary = st.town
	if t.has("incidents") and (t["incidents"] as Dictionary).has("planned"):
		return  # already shaped (the first step after a load or a new game shapes it)
	for k: String in ["life", "visitors", "watch", "rumors", "incidents"]:
		if not t.get(k) is Dictionary:
			t[k] = {}
	var l: Dictionary = t["life"]
	if not l.get("spectacles") is Array:
		l["spectacles"] = []
	if not l.get("cries") is Array:
		l["cries"] = []
	var v: Dictionary = t["visitors"]
	if not v.get("alive") is Array:
		v["alive"] = []
	if not v.get("planned") is Array:
		v["planned"] = []
	if not v.get("alms") is Dictionary:
		v["alms"] = {}
	var w: Dictionary = t["watch"]
	if not w.get("guards") is Dictionary:
		w["guards"] = {}
	if not w.get("dispatch") is Dictionary:
		w["dispatch"] = {}
	var r: Dictionary = t["rumors"]
	if not r.get("heard") is Array:
		r["heard"] = []
	if not r.get("told") is Dictionary:
		r["told"] = {}
	var i: Dictionary = t["incidents"]
	for k: String in ["active", "closed", "planned"]:
		if not i.get(k) is Array:
			i[k] = []
	for k: String in ["nests", "last", "warned"]:
		if not i.get(k) is Dictionary:
			i[k] = {}


## Once per minute, after TownLife (the townsfolk already chose what they do this minute).
static func step(sim: Sim) -> void:
	if not on(sim):
		return
	ensure(sim.state)
	Visitors.step(sim)
	Incidents.step(sim)
	Watch.step(sim)
	Rumors.step(sim)
	_end_spectacles(sim)


## Whether `chr` is off the map for the view and the town (a guard off duty, a visitor or a bandit not there yet or
## gone, a captive): the view hides it; nobody picks it.
static func offstage(st: WorldState, chr: String) -> bool:
	var ch: Dictionary = st.characters.get(chr, {})
	return bool(ch.get("offstage", false)) or str(ch.get("captive", "")) != ""


## Whether `chr` is held by the bandits (a kidnapping in course, Incidents).
static func is_captive(st: WorldState, chr: String) -> bool:
	return str(st.characters.get(chr, {}).get("captive", "")) != ""


## A service family of the town (watch, visitors, bandits), made the first time it is needed.
static func service_family(st: WorldState, fam: String, name_key: String, colors: Dictionary) -> Dictionary:
	if not st.families.has(fam):
		st.families[fam] = {"id": fam, "name": "", "name_key": name_key, "controlled_by": SERVICE_CONTROL,
			"members": [], "colors": colors.duplicate(), "gold": 0, "reputation": 0, "ai_profile": "", "ai_state": {},
			"service": true, "head": "", "heir": "", "founder": "", "generation": 1, "regent": "", "class": "",
			"goals_done": [], "title": "common", "class_reputation": {}, "reputation_log": [], "reputation_caps": {},
			"attitudes": {"honesty": 0, "generosity": 0, "diplomacy": 0}}
		if OS.is_debug_build():
			print("[Life] familia de servicio %s creada" % fam)
	return st.families[fam]


## Whether `fam` is one of the town's service families.
static func is_service(st: WorldState, fam: String) -> bool:
	return bool(st.families.get(fam, {}).get("service", false))


## A temporary character of a service family (a guard, a visitor, a bandit): off the map until put on it.
static func add_person(sim: Sim, fam: String, name: String, female: bool, age: int, stats: Dictionary,
		equipment: Dictionary, tile: Array, extra: Dictionary) -> String:
	var st := sim.state
	var id := Ids.next(st, "chr")
	var eq := {"tool": null, "clothes": null, "accessory": null}
	for slot: String in equipment:
		eq[slot] = {"item": str(equipment[slot]), "quality": 0}
	var full := {"charisma": 4, "empathy": 4, "negotiation": 4, "arcane": 1, "dexterity": 4, "craft": 3, "martial": 4,
		"constitution": 4, "rhetoric": 4, "stealth": 3}
	full.merge(stats, true)
	var n := id.get_slice("_", 1).to_int()
	st.characters[id] = {"id": id, "name": name, "female": female, "family": fam, "controlled_by": SERVICE_CONTROL,
		"alive": true, "position": [int(tile[0]), int(tile[1])], "path": [], "move_progress": 0, "stats": full,
		"inventory": Inventory.create("weight", 20.0), "equipment": eq, "location": "", "station": "", "order_queue": [],
		"home": "", "rank": "", "job": null, "hire_bans": {}, "routine": {}, "occupation": "", "town": {},
		"banished_until": -1, "ai": {}, "needs": {}, "offstage": true}
	st.characters[id].merge(Kin.character_fields(Kin.birth_day_for(age, int(st.clock["minute"]), sim.catalog.time),
		"", "", n % 6, n % 4, []), true)
	st.characters[id].merge(extra, true)
	(st.families[fam]["members"] as Array).append(id)
	return id


## Takes a temporary character out of the game (a visitor that leaves, a bandit that flees).
static func remove_person(sim: Sim, chr: String) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters.get(chr, {})
	if ch.is_empty():
		return
	var fam := str(ch.get("family", ""))
	if st.families.has(fam):
		(st.families[fam]["members"] as Array).erase(chr)
	OrderQueue.clear_for(sim, chr)
	st.characters.erase(chr)
	st.emotions.erase(chr)


## Puts `chr` on the map at `tile` (visible from now).
static func put_on(sim: Sim, chr: String, tile: Array) -> void:
	var ch: Dictionary = sim.state.characters[chr]
	ch["offstage"] = false
	ch["location"] = ""
	ch["position"] = [int(tile[0]), int(tile[1])]
	ch["path"] = []
	ch["move_progress"] = 0


## Takes `chr` off the map (hidden; it keeps its place in the state).
static func take_off(sim: Sim, chr: String) -> void:
	var ch: Dictionary = sim.state.characters[chr]
	ch["offstage"] = true
	ch["location"] = ""
	ch["path"] = []
	OrderQueue.clear_for(sim, chr)


# --- The map --------------------------------------------------------------------------------------------------------

static func map(sim: Sim) -> Dictionary:
	return sim.catalog.maps().get(sim.state.map_id, {})


static var _gates_key: String = ""
static var _gates: Dictionary = {}


## The map's gate tiles {name: [c, r]} (spawns *_gate), by name (static map data: kept per catalog and map).
static func gates(sim: Sim) -> Dictionary:
	var gk := "%d|%s" % [sim.catalog.get_instance_id(), sim.state.map_id]
	if gk == _gates_key:
		return _gates
	var out := {}
	var sp: Dictionary = map(sim).get("spawns", {})
	for k: String in sp:
		if k.ends_with("_gate"):
			out[k] = (sp[k] as Array).duplicate()
	_gates_key = gk
	_gates = out
	return out


## The social points of the map of any of `kinds`.
static func points(sim: Sim, kinds: Array) -> Array:
	var out: Array = []
	for p: Dictionary in map(sim).get("social_points", []):
		if str(p.get("kind", "")) in kinds:
			out.append(p)
	return out


## The centre of the plaza: the market spawn (else the player's).
static func plaza(sim: Sim) -> Array:
	var sp: Dictionary = map(sim).get("spawns", {})
	return (sp.get("market", sp.get("player", [0, 0])) as Array).duplicate()


static func dist(a: Array, b: Array) -> int:
	if a.size() < 2 or b.size() < 2:
		return 999
	return maxi(absi(int(a[0]) - int(b[0])), absi(int(a[1]) - int(b[1])))


## Where `chr` stands (its building's door when inside).
static func tile_of(st: WorldState, chr: String) -> Array:
	var ch: Dictionary = st.characters.get(chr, {})
	var loc := str(ch.get("location", ""))
	if loc != "" and st.buildings.has(loc):
		return (st.buildings[loc].get("door", ch.get("position", [0, 0])) as Array).duplicate()
	return (ch.get("position", [0, 0]) as Array).duplicate()


## The players' families (human), by id.
static func humans(st: WorldState) -> Array:
	var out: Array = []
	for f: Variant in st.families:
		if str(st.families[f].get("controlled_by", "")) == "human":
			out.append(str(f))
	out.sort()
	return out


## The player's family (the first human one), "" if none.
static func player_family(st: WorldState) -> String:
	var h := humans(st)
	return "" if h.is_empty() else str(h[0])


# --- Spectacles (a minstrel in the plaza; the festivals of 4.25 add theirs) -----------------------------------------

## A spectacle at `tile` until minute `until`: townsfolk may go and look (activity watch_show).
static func add_spectacle(sim: Sim, id: String, tile: Array, until: int, by: String = "") -> void:
	ensure(sim.state)
	(sim.state.town["life"]["spectacles"] as Array).append({"id": id, "tile": tile.duplicate(), "until": until, "by": by})
	sim.events.append({"type": "spectacle_started", "spectacle": id, "tile": tile.duplicate(), "by": by})
	if OS.is_debug_build():
		print("[Life] espectáculo %s en %s hasta el minuto %d (por %s)" % [id, tile, until, by])


static func spectacles(st: WorldState) -> Array:
	var l: Variant = st.town.get("life")
	return (l as Dictionary).get("spectacles", []) if l is Dictionary else []


static func _end_spectacles(sim: Sim) -> void:
	var now := int(sim.state.clock["minute"])
	var keep: Array = []
	for s: Dictionary in spectacles(sim.state):
		if now < int(s.get("until", 0)):
			keep.append(s)
	if keep.size() != spectacles(sim.state).size():
		sim.state.town["life"]["spectacles"] = keep


# --- Event multipliers (the festivals of 4.25 set them through data/events.json effects) ----------------------------

static var _ev_key: String = ""
static var _ev_cache: Dictionary = {}


## The product of the active global events' effects of `kind` ("routine", "incident", "visitors") for `id`.
static func event_mult(sim: Sim, kind: String, id: String = "") -> float:
	if sim.state.events_active.is_empty():  # fiestas (04f 4.25.3): the festival of the day (1 when none)
		return Festivals.today_mult(sim, kind) if kind == "visitors" else Festivals.hook_mult(sim, kind, id)
	var ck := "%d|%d" % [sim.state.get_instance_id(), int(sim.state.clock["minute"])]
	if ck != _ev_key:
		_ev_key = ck
		_ev_cache = {}
	var mk := kind + "|" + id
	if _ev_cache.has(mk):
		return float(_ev_cache[mk])
	var m := 1.0
	for e: Dictionary in sim.state.events_active:
		var def: Dictionary = sim.catalog.world_events().get(str(e.get("def", "")), {})
		for fx: Dictionary in def.get("effects", []):
			if str(fx.get("kind", "")) != kind:
				continue
			var target := str(fx.get("activity", fx.get("id", "")))
			if target == "" or target == id:
				m *= float(fx.get("mult", 1.0))
	m *= Festivals.today_mult(sim, kind) if kind == "visitors" else Festivals.hook_mult(sim, kind, id)  # fiestas
	_ev_cache[mk] = m
	return m


## Whether today is a day of rest (an active event with a holy_day effect).
static func holy_day(sim: Sim) -> bool:
	if Festivals._holy_now(sim):  # fiestas (04f 4.25.1): the holy morning of Holy Week, All Saints, Christmas
		return true
	if sim.state.events_active.is_empty():
		return false
	for e: Dictionary in sim.state.events_active:
		var def: Dictionary = sim.catalog.world_events().get(str(e.get("def", "")), {})
		for fx: Dictionary in def.get("effects", []):
			if str(fx.get("kind", "")) == "holy_day":
				return true
	return false


## Whether a festival is on (an event of the "festival" group or with the festival flag): visitors ×, the plaza guard.
static func festival(sim: Sim) -> bool:
	if Festivals.on_today(sim):  # fiestas (04f 4.25): a feast of the calendar today
		return true
	if sim.state.events_active.is_empty():
		return false
	for e: Dictionary in sim.state.events_active:
		var id := str(e.get("def", ""))
		var def: Dictionary = sim.catalog.world_events().get(id, {})
		if id == "festival" or bool(def.get("festival", false)):
			return true
	return false
