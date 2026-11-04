class_name Unlocks
extends RefCounted
## The unlocks of 03b §3b.4 (O-D2 a): each mechanic arrives when the player needs it, by a milestone of the player
## (gold, title, employees, age, an event) or by the calendar, with its card, its HUD mark, its tutorial chapter and
## an open goal. Figures and triggers in data/unlocks.json (Catalog.unlocks). Only the families the human controls.
## What an unlock opens is UI access (the buttons of `ui`), never a rule of the sim: Unlocks.step reads the state and
## the events of the step and writes only state.unlocks; it draws no randomness.
##
## state.unlocks[fam] = {id: {minute, seen: bool (the card was closed), used: bool (the marked button was pressed)},
##                       "_count": {unlock id: [events counted per trigger leaf]}, "_all": {...} (a game from before
##                       v20: everything open, SaveFile._to_v20)}
## state.unlocks["_day_sales"] = {fam: units sold at the market today} (outsold_rival, reset each day).
## Events: unlocked {family, unlock, minute}; rival_outsold {family, rival, mine, theirs, day}.

const ALL: String = "_all"


static func defs(sim: Sim) -> Array:
	return sim.catalog.unlocks.get("unlocks", [])


static func def(sim: Sim, id: String) -> Dictionary:
	for d: Dictionary in defs(sim):
		if str(d.get("id", "")) == id:
			return d
	return {}


## Whether the system an unlock waits for exists (its hook): data/<requires>.json or data/<requires>/ (Catalog keeps
## the answer in unlocks._ready at load).
static func ready(sim: Sim, d: Dictionary) -> bool:
	var req := str(d.get("requires", ""))
	if req == "":
		return true
	if not bool((sim.catalog.unlocks.get("_ready", {}) as Dictionary).get(req, false)):
		return false
	return not req.begins_with("life/") or Life.on(sim)  # vida: its rumours and incidents only with the town alive


## Whether `id` is open for `fam` (a family that is not the human's, or a game from before v20, has everything open).
static func is_open(state: WorldState, fam: String, id: String) -> bool:
	var u: Variant = state.unlocks.get(fam)
	if not u is Dictionary:
		return true
	return (u as Dictionary).has(ALL) or (u as Dictionary).has(id)


## Whether a UI element (data/unlocks.json `ui`, e.g. "staff") is open for `fam`: no unlock names it, or one that
## names it is open.
static func ui_open(sim: Sim, fam: String, ui: String) -> bool:
	for d: Dictionary in defs(sim):
		if ui in (d.get("ui", []) as Array) and not is_open(sim.state, fam, str(d["id"])):
			return false
	return true


static func step(sim: Sim) -> void:
	var st := sim.state
	if defs(sim).is_empty():
		return
	var fams := _human_families(st)
	if fams.is_empty():
		return
	_count_sales(sim)
	for fam: String in fams:
		if not st.unlocks.get(fam) is Dictionary:
			st.unlocks[fam] = {}
		var u: Dictionary = st.unlocks[fam]
		if u.has(ALL):
			continue
		for d: Dictionary in defs(sim):
			var id := str(d.get("id", ""))
			if u.has(id) or not ready(sim, d):
				continue
			if _holds(sim, fam, id, d.get("trigger", {}), [0]):
				_open(sim, fam, id)


## {"type": "unlock_seen", "actor", "unlock", "what": "card" | "mark"}: the card was closed / the marked button used.
## {"type": "unlock_seen", "actor", "unlock", "what": "now"}: opens it now (a tutorial chapter asked by the player,
## «nada se esconde para siempre»).
static func order_seen(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	if not sim.state.characters.has(actor):
		return Orders.fail("unknown_actor")
	var fam := str(sim.state.characters[actor].get("family", ""))
	var id := str(o.get("unlock", ""))
	if def(sim, id).is_empty():
		return Orders.fail("unknown_unlock")
	if not sim.state.unlocks.get(fam) is Dictionary:
		sim.state.unlocks[fam] = {}
	var u: Dictionary = sim.state.unlocks[fam]
	var what := str(o.get("what", "card"))
	if what == "now":
		if not u.has(id) and not u.has(ALL):
			_open(sim, fam, id)
		return Orders.ok()
	if not u.get(id) is Dictionary:
		return Orders.fail("not_unlocked")
	match what:
		"card":
			u[id]["seen"] = true
		"mark":
			u[id]["used"] = true
			u[id]["seen"] = true
		_:
			return Orders.fail("unknown_choice")
	return Orders.ok()


static func _open(sim: Sim, fam: String, id: String) -> void:
	var now := int(sim.state.clock["minute"])
	sim.state.unlocks[fam][id] = {"minute": now, "seen": false, "used": false}
	sim.events.append({"type": "unlocked", "family": fam, "unlock": id, "minute": now})
	if not bool(def(sim, id).get("card", true)):
		sim.state.unlocks[fam][id]["seen"] = true  # no card: nothing to read (the start's own mechanics)
	Notices.add(sim, fam, Notices.INFO, "notice.unlocked", {"unlock": id,
		"what": str(def(sim, id).get("name_key", ""))})
	if OS.is_debug_build():
		print("[Unlocks] %s desbloquea %s (día=%d, min=%d)" % [fam, id, Clock.day(now), now])


## Whether trigger `t` holds now for `fam`. `leaf` numbers the event leaves of the unlock (their counters).
static func _holds(sim: Sim, fam: String, id: String, t: Dictionary, leaf: Array) -> bool:
	var st := sim.state
	match str(t.get("kind", "")):
		"start":
			return true
		"calendar":
			return Clock.day(int(st.clock["minute"])) >= int(t.get("day", 0))
		"gold":
			return int(st.families.get(fam, {}).get("gold", 0)) >= int(t.get("min", 0))
		"title":
			return _title_rank(sim, str(st.families.get(fam, {}).get("title", "common"))) >= _title_rank(sim,
				str(t.get("min", "")))
		"employees":
			return _employees(st, fam) >= int(t.get("min", 1))
		"age":
			var head := str(st.families.get(fam, {}).get("head", ""))
			return st.characters.has(head) and Kin.age(sim, head) >= int(t.get("min", 0))
		"event":
			var i: int = leaf[0]
			leaf[0] = i + 1
			return _count_event(sim, fam, id, i, t)
		"outsold_rival":
			for e: Dictionary in sim.events:
				if str(e.get("type", "")) == "rival_outsold" and str(e.get("family", "")) == fam:
					return true
			return false
		"any":
			var any := false
			for sub: Dictionary in t.get("of", []):
				any = _holds(sim, fam, id, sub, leaf) or any  # every leaf counts its events, even after one holds
			return any
		"all":
			var all := true
			for sub: Dictionary in t.get("of", []):
				all = _holds(sim, fam, id, sub, leaf) and all
			return all
	return false


## Counts this step's events of `fam` that match an event leaf; true once its count is reached.
static func _count_event(sim: Sim, fam: String, id: String, i: int, t: Dictionary) -> bool:
	var u: Dictionary = sim.state.unlocks[fam]
	if not u.get("_count") is Dictionary:
		u["_count"] = {}
	var counts: Dictionary = u["_count"]
	if not counts.get(id) is Array:
		counts[id] = []
	var c: Array = counts[id]
	while c.size() <= i:
		c.append(0)
	var want := str(t.get("event", ""))
	var m: Dictionary = t.get("match", {}) if t.get("match") is Dictionary else {}
	for e: Dictionary in sim.events:
		if str(e.get("type", "")) != want or _family_of(sim.state, e) != fam:
			continue
		if not m.is_empty() and not Objectives._matches(e, m):
			continue
		c[i] = int(c[i]) + 1
	return int(c[i]) >= int(t.get("count", 1))


## Units sold at the market today by each family; at the day change, a human family that sold more than the rival
## smith's family (the AI family with profile rival_smith) gets rival_outsold.
static func _count_sales(sim: Sim) -> void:
	var st := sim.state
	if not st.unlocks.get("_day_sales") is Dictionary:
		st.unlocks["_day_sales"] = {}
	var sales: Dictionary = st.unlocks["_day_sales"]
	var new_day := false
	for e: Dictionary in sim.events:
		match str(e.get("type", "")):
			"market_sold":
				var f := str(e.get("family", ""))
				sales[f] = int(sales.get(f, 0)) + int(e.get("qty", 1))
			"day_started":
				new_day = true
	if not new_day:
		return
	var rival := ""
	for f: String in _sorted(st.families.keys()):
		if str(st.families[f].get("ai_profile", "")) == "rival_smith":
			rival = f
			break
	if rival != "":
		var theirs := int(sales.get(rival, 0))
		for fam: String in _human_families(st):
			var mine := int(sales.get(fam, 0))
			if mine > theirs:
				sim.events.append({"type": "rival_outsold", "family": fam, "rival": rival, "mine": mine, "theirs": theirs,
					"day": Clock.day(int(st.clock["minute"])) - 1})
	st.unlocks["_day_sales"] = {}


static func _title_rank(sim: Sim, title: String) -> int:
	return int(sim.catalog.titles().get(title, {}).get("rank", 0))


static func _employees(st: WorldState, fam: String) -> int:
	var n := 0
	for c: Dictionary in st.characters.values():
		var job: Variant = c.get("job")
		if job is Dictionary and st.buildings.has(str((job as Dictionary).get("building", ""))) \
				and str(st.buildings[str(job["building"])].get("owner", "")) == fam:
			n += 1
	return n


static func _family_of(st: WorldState, e: Dictionary) -> String:
	var fam := str(e.get("family", ""))
	if fam != "":
		return fam
	var who := str(e.get("actor", ""))
	if who == "":
		who = str(e.get("character", ""))  # vida: rumor_heard names who heard it
	return Money.family_of(st, who)


static func _human_families(st: WorldState) -> Array:
	var out: Array = []
	for f: String in _sorted(st.families.keys()):
		if str(st.families[f].get("controlled_by", "")) == "human":
			out.append(f)
	return out


static func _sorted(keys: Array) -> Array:
	var out: Array = keys.map(func(k: Variant) -> String: return str(k))
	out.sort()
	return out


# --- Queries (UI) ----------------------------------------------------------------------------------------------------

## The unlocks of `fam` in the order they came: [{id, minute, seen, used, def}] (not the ones of a game from before).
static func list(sim: Sim, fam: String) -> Array:
	var u: Variant = sim.state.unlocks.get(fam)
	var out: Array = []
	if not u is Dictionary:
		return out
	for id: Variant in (u as Dictionary).keys():
		var s := str(id)
		if s.begins_with("_") or not (u[id] is Dictionary):
			continue
		var e: Dictionary = (u[id] as Dictionary).duplicate()
		e["id"] = s
		e["def"] = def(sim, s)
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["minute"]) < int(b["minute"]) or (int(a["minute"]) == int(b["minute"]) and str(a["id"]) < str(b["id"])))
	return out


## The HUD marks of `fam`: {button node name: unlock id} of the unlocks open and not used yet.
static func marks(sim: Sim, fam: String) -> Dictionary:
	var out := {}
	for e: Dictionary in list(sim, fam):
		var m := str((e["def"] as Dictionary).get("mark", ""))
		if m != "" and not bool(e.get("used", false)):
			out[m] = str(e["id"])
	return out
