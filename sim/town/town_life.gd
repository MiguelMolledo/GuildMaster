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


static var _wp_cache: Dictionary = {}  # "<catalog instance>:<map>" -> {workplace id -> workplace} (static map data)


## A workplace of the map by id ({} if none).
static func workplace(st: WorldState, catalog: Catalog, id: String) -> Dictionary:
	var key := "%d:%s" % [catalog.get_instance_id(), st.map_id]
	if not _wp_cache.has(key):
		var by := {}
		for w: Dictionary in workplaces(st, catalog):
			by[str(w.get("id", ""))] = w
		_wp_cache[key] = by
	return _wp_cache[key].get(id, {})


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


# --- The day of the townsfolk (GDD 4.11.2) ---------------------------------------------------------------------------
# character.town: {day, leave_at, break_permil, greets, met: [chr], plan, state, activity, spot, slot, target: [c, r],
#   dur, until (minute the activity ends; -1 until it arrives), wait_until (chat alone), stalls: [[c, r]...] (market),
#   break (the activity is a day break), greet_until, retry_at, customer (bld, set by Counter)}

const ACTIVITY_KEYS: Array[String] = ["activity", "spot", "slot", "target", "dur", "until", "wait_until", "stalls", "break"]


## Once per minute, after Routines (Sim.step).
static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	if now % 60 == 0:
		assign_occupations(st, sim.catalog)
	var phase := Clock.phase(now, sim.catalog.time)
	var today := Clock.day(now)
	var folk: Array = []
	for id: Variant in st.characters:
		if str(st.characters[id].get("home", "")) != "" and is_townsperson(st, str(id)):
			folk.append(str(id))
	folk.sort()
	var gcfg: Dictionary = sim.catalog.town.get("routine", {}).get("greet", {})
	if phase != "night" and now % maxi(1, int(gcfg.get("check_every", 5))) == 0:
		_greetings(sim, folk, now, today, gcfg)
	for chr: String in folk:
		_step_one(sim, chr, now, phase, today)


static func _step_one(sim: Sim, chr: String, now: int, phase: String, today: int) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	if ch.get("job") is Dictionary:
		return  # an employee: Routines (H4) takes it from home to work and back
	if not ch.get("town") is Dictionary:
		ch["town"] = {}
	var t: Dictionary = ch["town"]
	var home := str(ch.get("home", ""))
	var cfg: Dictionary = sim.catalog.town.get("routine", {})
	if int(t.get("adult_day", -1)) != today:  # ages change once a day at most: worked out once a day
		t["adult"] = is_adult(st, sim.catalog, chr)
		t["adult_day"] = today
	if not bool(t["adult"]):
		if bool(cfg.get("child_stays_home", true)):
			_go_building(sim, chr, t, home, now)
			_set_state(sim, chr, t, "home" if str(ch.get("location", "")) == home else "walking")
		return
	if int(t.get("day", -1)) != today:
		_new_day(sim, chr, t, today, cfg)
	if phase == "night":
		_clear_activity(t)
		t.erase("customer")
		t.erase("greet_until")
		_plan_home(sim, chr, t, now)
		return
	if int(t.get("greet_until", -1)) > now:
		_set_state(sim, chr, t, "social", "greet")
		return
	if str(t.get("customer", "")) != "" and phase in (sim.catalog.town.get("counter", {}).get("phases", ["day"]) as Array):
		_clear_activity(t)
		var bld := str(t["customer"])
		if _go_building(sim, chr, t, bld, now):
			_set_state(sim, chr, t, "customer")
		else:
			_set_state(sim, chr, t, "walking")
		return
	t.erase("customer")
	match phase:
		"dawn":
			if now < int(t.get("leave_at", 0)):
				_plan_home(sim, chr, t, now)
			else:
				_plan_work(sim, chr, t, now)
		"day":
			if t.has("activity"):
				_run_activity(sim, chr, t, now)
				if not t.has("activity"):
					_plan_work(sim, chr, t, now)  # the break is over: back to work
				return
			var mod := Clock.minute_of_day(now)
			if mod == int(cfg.get("market_hour", 10)) * 60 and Kin.roll(st, "town|mkt|%s|%d" % [chr, today]) \
					< float(cfg.get("market_visit_chance", 0.25)):
				if _start_activity(sim, chr, t, now, "market", true):
					return
			if mod % 60 == 0 and Kin.roll(st, "town|brk|%s|%d" % [chr, now]) * 1000.0 < float(t.get("break_permil", 0)):
				if _choose_activity(sim, chr, t, now, true):
					return
			_plan_work(sim, chr, t, now)
		"dusk":
			if t.has("activity") and bool(t.get("break", false)):
				_clear_activity(t)  # a day break does not run into the free time: the evening starts afresh
			if not t.has("activity"):
				if not _choose_activity(sim, chr, t, now, false):
					_stroll(sim, chr, t, now)
					return
			_run_activity(sim, chr, t, now)


## Today's leaving minute, break chance and greetings.
static func _new_day(sim: Sim, chr: String, t: Dictionary, today: int, cfg: Dictionary) -> void:
	var st := sim.state
	var span: Array = cfg.get("leave_home_delay_minutes", [0, 0])
	var delay := Kin.randi_range(st, "town|leave|%s|%d" % [chr, today], int(span[0]), int(span[1]))
	var starts: Dictionary = sim.catalog.time["phase_starts"][Clock.season(today * Clock.MINUTES_PER_DAY, sim.catalog.time)]
	var bc: Array = cfg.get("break_chance_per_hour", [0.15, 0.2])
	t["day"] = today
	t["leave_at"] = today * Clock.MINUTES_PER_DAY + int(starts.get("dawn", 300)) + delay
	# per mille, an int: a float would not come back identical from a save
	t["break_permil"] = roundi((float(bc[0]) + (float(bc[1]) - float(bc[0])) * Kin.roll(st, "town|bc|%s|%d" % [chr, today])) * 1000.0)
	t["greets"] = 0
	t["met"] = []


static func _plan_home(sim: Sim, chr: String, t: Dictionary, now: int) -> void:
	var home := str(sim.state.characters[chr].get("home", ""))
	t["plan"] = "home"
	if _go_building(sim, chr, t, home, now):
		_set_state(sim, chr, t, "home")
	else:
		_set_state(sim, chr, t, "walking")


static func _plan_work(sim: Sim, chr: String, t: Dictionary, now: int) -> void:
	var ch: Dictionary = sim.state.characters[chr]
	t["plan"] = "work"
	var wp := workplace(sim.state, sim.catalog, str(ch.get("occupation", "")))
	if wp.is_empty():
		if not _choose_activity(sim, chr, t, now, true):
			_stroll(sim, chr, t, now)
		return
	var there := false
	if str(wp.get("kind", "")) == "shop":
		var bld := _site_building(sim, str(wp.get("building", "")))
		if bld != "" and Buildings.can_enter(sim, chr, bld)["ok"]:
			there = _go_building(sim, chr, t, bld, now)
		else:
			there = _go_tile(sim, chr, t, wp["tile"], now)  # closed: waits at the door
	else:
		there = _go_tile(sim, chr, t, wp["tile"], now)
	_set_state(sim, chr, t, "working" if there else "walking")


## Walks somewhere in the plaza when nothing else is free.
static func _stroll(sim: Sim, chr: String, t: Dictionary, now: int) -> void:
	var pts: Array = sim.catalog.maps().get(sim.state.map_id, {}).get("social_points", [])
	if pts.is_empty():
		_plan_home(sim, chr, t, now)
		return
	var p: Dictionary = pts[Kin.randi_range(sim.state, "town|stroll|%s|%d" % [chr, Clock.day(now)], 0, pts.size() - 1)]
	var tile: Array = p["slots"][0]
	var there := _go_tile(sim, chr, t, [int(tile[0]) , int(tile[1]) + 1] if _walkable(sim, int(tile[0]), int(tile[1]) + 1) else tile, now)
	_set_state(sim, chr, t, "strolling" if there else "walking")


# --- Activities (GDD 4.11.3) ------------------------------------------------------------------------------------------

## Picks the next activity by weight × personality (12 % at random) among the ones with room. False if none.
static func _choose_activity(sim: Sim, chr: String, t: Dictionary, now: int, is_break: bool) -> bool:
	var st := sim.state
	var acts: Dictionary = sim.catalog.town.get("activities", {})
	var pers: Dictionary = sim.catalog.town.get("personality", {})
	var stats: Dictionary = st.characters[chr].get("stats", {})
	var names: Array = acts.keys()
	names.sort()
	var cands: Array = []
	var weights: Array = []
	var exception := Kin.roll(st, "town|exc|%s|%d" % [chr, now]) < float(pers.get("exception_chance", 0.12))
	for a: String in names:
		var d: Dictionary = acts[a]
		var w := float(d.get("weight", 0.0))
		if w <= 0.0 or not _has_room(sim, chr, a):
			continue
		var fav := str(d.get("favored_by", ""))
		if fav != "" and int(stats.get(fav, 0)) >= int(pers.get("stat_min", 7)):
			w *= float(pers.get("favored_mult", 3.0))
		cands.append(a)
		weights.append(1.0 if exception else w)
	if cands.is_empty():
		return false
	var total := 0.0
	for w: float in weights:
		total += w
	var r := Kin.roll(st, "town|act|%s|%d" % [chr, now]) * total
	var pick := str(cands[cands.size() - 1])
	for i: int in cands.size():
		r -= float(weights[i])
		if r < 0.0:
			pick = str(cands[i])
			break
	return _start_activity(sim, chr, t, now, pick, is_break)


## Sets up activity `a` (its spot or stalls, its duration). False if it has no room now.
static func _start_activity(sim: Sim, chr: String, t: Dictionary, now: int, a: String, is_break: bool) -> bool:
	var st := sim.state
	var d: Dictionary = sim.catalog.town.get("activities", {}).get(a, {})
	if d.is_empty():
		return false
	var key := "town|%s|%s|%d" % [a, chr, now]
	var spot := {}
	var stalls: Array = []
	match str(d.get("spot", "none")):
		"bench", "chat", "dice":
			spot = _free_slot(sim, chr, str(d["spot"]), key)
			if spot.is_empty():
				return false
		"stalls":
			var all := _stall_tiles(sim)
			if all.is_empty():
				return false
			var span: Array = d.get("stalls", [2, 4])
			var n := mini(all.size(), Kin.randi_range(st, key + "|n", int(span[0]), int(span[1])))
			var first := Kin.randi_range(st, key + "|first", 0, all.size() - 1)
			for i: int in n:
				stalls.append(all[(first + i) % all.size()])
		"doors":
			var doors := _doors(sim)
			if doors.is_empty():
				return false
			spot = {"id": "", "slot": -1, "tile": doors[Kin.randi_range(st, key + "|door", 0, doors.size() - 1)]}
	_clear_activity(t)
	t["activity"] = a
	t["break"] = is_break
	t["until"] = -1
	if is_break:
		var bm: Array = sim.catalog.town.get("routine", {}).get("break_minutes", [90, 150])
		t["dur"] = Kin.randi_range(st, key + "|dur", int(bm[0]), int(bm[1]))
	else:
		var mm: Array = d.get("per_stall_minutes" if a == "market" else "minutes", [60, 60])
		t["dur"] = Kin.randi_range(st, key + "|dur", int(mm[0]), int(mm[1]))
	if a == "market":
		t["stalls"] = stalls
		t["target"] = (stalls[0] as Array).duplicate()
		if is_break:  # a break at the market: split the break between the stalls
			t["dur"] = maxi(10, int(t["dur"]) / stalls.size())
	else:
		t["spot"] = str(spot.get("id", ""))
		t["slot"] = int(spot.get("slot", -1))
		t["target"] = (spot["tile"] as Array).duplicate()
	if OS.is_debug_build():
		print("[TownLife] %s empieza %s%s (destino=%s, %d min)" % [chr, a, " (descanso)" if is_break else "",
			t["target"], int(t["dur"])])
	return true


## Walks to the activity's spot and runs its clock. When it ends the activity is cleared (the caller picks the next).
static func _run_activity(sim: Sim, chr: String, t: Dictionary, now: int) -> void:
	var a := str(t.get("activity", ""))
	if not _go_tile(sim, chr, t, t["target"], now):
		_set_state(sim, chr, t, "walking", a)
		return
	if int(t.get("until", -1)) < 0:
		if a == "chat" and not _someone_chatting(sim, chr, str(t.get("spot", ""))):
			if not t.has("wait_until"):
				t["wait_until"] = now + int(sim.catalog.town.get("routine", {}).get("chat_wait_minutes", 30))
			if now >= int(t["wait_until"]):
				_clear_activity(t)  # nobody came: something else
				return
			_set_state(sim, chr, t, "strolling", a)
			return
		t["until"] = now + int(t.get("dur", 60))
	if now >= int(t["until"]):
		if a == "market" and (t.get("stalls", []) as Array).size() > 1:
			(t["stalls"] as Array).pop_front()
			t["target"] = (t["stalls"][0] as Array).duplicate()
			t["until"] = -1
			_set_state(sim, chr, t, "walking", a)
			return
		if OS.is_debug_build():
			print("[TownLife] %s acaba %s" % [chr, a])
		_clear_activity(t)
		return
	_set_state(sim, chr, t, "market" if a == "market" else "social", a)


static func _clear_activity(t: Dictionary) -> void:
	for k: String in ACTIVITY_KEYS:
		t.erase(k)


## Whether activity `a` has room for `chr` now.
static func _has_room(sim: Sim, chr: String, a: String) -> bool:
	var d: Dictionary = sim.catalog.town.get("activities", {}).get(a, {})
	match str(d.get("spot", "none")):
		"bench", "chat", "dice":
			return not _free_slot(sim, chr, str(d["spot"]), "room").is_empty()
		"stalls":
			return not _stall_tiles(sim).is_empty()
		"doors":
			return not _doors(sim).is_empty()
	return false


## A free slot of a social point of `kind` ({id, slot, tile} or {}): a random point among those with room.
static func _free_slot(sim: Sim, chr: String, kind: String, key: String) -> Dictionary:
	var st := sim.state
	var taken := {}
	for id: Variant in st.characters:
		if str(id) == chr:
			continue
		var tt: Variant = st.characters[id].get("town")
		if tt is Dictionary and (tt as Dictionary).has("activity") and str(tt.get("spot", "")) != "":
			taken["%s|%d" % [tt["spot"], int(tt.get("slot", -1))]] = true
	var free: Array = []
	var joined: Array = []  # chat: slots of a point somebody already goes to (a chat needs 2+)
	for p: Dictionary in sim.catalog.maps().get(st.map_id, {}).get("social_points", []):
		if str(p.get("kind", "")) != kind:
			continue
		var slots: Array = p.get("slots", [])
		var busy := false
		for i: int in slots.size():
			busy = busy or taken.has("%s|%d" % [p["id"], i])
		for i: int in slots.size():
			if not taken.has("%s|%d" % [p["id"], i]):
				free.append({"id": str(p["id"]), "slot": i, "tile": slots[i]})
				if busy:
					joined.append(free[free.size() - 1])
	if free.is_empty():
		return {}
	var pool: Array = joined if kind == "chat" and not joined.is_empty() else free
	return pool[Kin.randi_range(st, "town|slot|%s|%s" % [chr, key], 0, pool.size() - 1)]


## Whether another townsperson is already chatting at chat point `spot` (arrived there).
static func _someone_chatting(sim: Sim, chr: String, spot: String) -> bool:
	for id: Variant in sim.state.characters:
		if str(id) == chr:
			continue
		var tt: Variant = sim.state.characters[id].get("town")
		if tt is Dictionary and str(tt.get("activity", "")) == "chat" and str(tt.get("spot", "")) == spot \
				and str(tt.get("state", "")) in ["social", "strolling"]:
			var pos: Array = sim.state.characters[id].get("position", [])
			var tg: Array = tt.get("target", [])
			if pos.size() == 2 and tg.size() == 2 and int(pos[0]) == int(tg[0]) and int(pos[1]) == int(tg[1]):
				return true
	return false


## The service tiles of the market's outdoor stalls (data/maps "stalls").
static func _stall_tiles(sim: Sim) -> Array:
	var out: Array = []
	var stalls: Dictionary = sim.catalog.maps().get(sim.state.map_id, {}).get("stalls", {})
	var ks: Array = stalls.keys()
	ks.sort()
	for k: String in ks:
		out.append((stalls[k].get("service", []) as Array).duplicate())
	return out


## The doors of the buildings that are not houses (something to look at), by building id.
static func _doors(sim: Sim) -> Array:
	var out: Array = []
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		var bld: Dictionary = sim.state.buildings[b]
		if str(bld.get("type", "")) != "house" and (bld.get("door", []) as Array).size() == 2:
			out.append((bld["door"] as Array).duplicate())
	return out


# --- Greetings ---------------------------------------------------------------------------------------------------

## Two walking townsfolk 1 tile apart stop and greet (15-25 min) with greet.chance, at most per_day each, once per pair a
## day.
static func _greetings(sim: Sim, folk: Array, now: int, today: int, gcfg: Dictionary) -> void:
	var st := sim.state
	var walking: Array = []
	for chr: String in folk:
		var ch: Dictionary = st.characters[chr]
		var t: Variant = ch.get("town")
		if not t is Dictionary or ch.get("job") is Dictionary or str(ch.get("location", "")) != "" \
				or (ch.get("path", []) as Array).is_empty() or int(t.get("greets", 0)) >= int(gcfg.get("per_day", 2)) \
				or int(t.get("day", -1)) != today or str(t.get("customer", "")) != "":
			continue
		walking.append(chr)
	for i: int in walking.size():
		var a: String = walking[i]
		var ta: Dictionary = st.characters[a]["town"]
		if int(ta.get("greet_until", -1)) > now:
			continue
		for j: int in range(i + 1, walking.size()):
			var b: String = walking[j]
			var tb: Dictionary = st.characters[b]["town"]
			if int(tb.get("greet_until", -1)) > now or b in (ta.get("met", []) as Array):
				continue
			var pa: Array = st.characters[a]["position"]
			var pb: Array = st.characters[b]["position"]
			if maxi(absi(int(pa[0]) - int(pb[0])), absi(int(pa[1]) - int(pb[1]))) > 1:
				continue
			if Kin.roll(st, "town|greetroll|%s|%s|%d" % [a, b, today]) >= float(gcfg.get("chance", 1.0)):
				(ta.get("met", []) as Array).append(b)  # they crossed without stopping: not again today
				continue
			var mm: Array = gcfg.get("minutes", [15, 25])
			var dur := Kin.randi_range(st, "town|greet|%s|%s|%d" % [a, b, now], int(mm[0]), int(mm[1]))
			for p: Array in [[a, ta, b], [b, tb, a]]:
				var c: String = p[0]
				var tc: Dictionary = p[1]
				tc["greet_until"] = now + dur
				tc["greets"] = int(tc.get("greets", 0)) + 1
				var met: Array = tc.get("met", [])
				met.append(p[2])
				tc["met"] = met
				var pos: Array = st.characters[c]["position"]
				sim.give({"type": "move_to", "actor": c, "tile": [int(pos[0]), int(pos[1])]})  # stops here
				_set_state(sim, c, tc, "social", "greet")
			sim.events.append({"type": "greeted", "a": a, "b": b})
			if OS.is_debug_build():
				print("[TownLife] %s y %s se saludan (%d min)" % [a, b, dur])
			break


# --- Moving with real orders ------------------------------------------------------------------------------------

## Takes `chr` to tile `tile` on the map (leaving a building first). True when it stands there.
static func _go_tile(sim: Sim, chr: String, t: Dictionary, tile: Variant, now: int) -> bool:
	var ch: Dictionary = sim.state.characters[chr]
	var to: Array = tile
	if str(ch.get("location", "")) != "":
		sim.give({"type": "exit_building", "actor": chr})
		if str(ch.get("location", "")) != "":
			return false
	var pos: Array = ch.get("position", [0, 0])
	var path: Array = ch.get("path", [])
	if path.is_empty() and int(pos[0]) == int(to[0]) and int(pos[1]) == int(to[1]):
		if not (ch.get("order_queue", []) as Array).is_empty() and Routines._walking_to(ch) != "":
			sim.give({"type": "move_to", "actor": chr, "tile": [int(to[0]), int(to[1])]})  # drops a pending entry
		return true
	if not path.is_empty() and Routines._walking_to(ch) == "":  # (a walk to enter a building is not this one)
		var last: Array = path[path.size() - 1]
		if int(last[0]) == int(to[0]) and int(last[1]) == int(to[1]):
			return false
	if now < int(t.get("retry_at", -1)):
		return false
	sim.give({"type": "move_to", "actor": chr, "tile": [int(to[0]), int(to[1])]})
	if (ch.get("path", []) as Array).is_empty():
		t["retry_at"] = now + int(sim.catalog.town.get("routine", {}).get("retry_minutes", 30))
	return false


## Takes `chr` into building `bld` (its house, the shop it works at, a counter). True when inside.
static func _go_building(sim: Sim, chr: String, t: Dictionary, bld: String, now: int) -> bool:
	var ch: Dictionary = sim.state.characters[chr]
	if bld == "":
		return false
	var loc := str(ch.get("location", ""))
	if loc == bld:
		return true
	if Routines._walking_to(ch) == bld:
		return false
	if now < int(t.get("retry_at", -1)):
		return false
	if loc != "":
		sim.give({"type": "exit_building", "actor": chr})
	sim.give({"type": "enter_building", "actor": chr, "building": bld})
	if str(ch.get("location", "")) == bld:
		return true
	if Routines._walking_to(ch) != bld:
		t["retry_at"] = now + int(sim.catalog.town.get("routine", {}).get("retry_minutes", 30))
	return false


static func _set_state(sim: Sim, chr: String, t: Dictionary, state: String, activity: String = "") -> void:
	if str(t.get("state", "")) == state and str(t.get("shown", "")) == activity:
		return
	t["state"] = state
	t["shown"] = activity
	sim.events.append({"type": "town_state", "character": chr, "state": state, "activity": activity})


static func _walkable(sim: Sim, c: int, r: int) -> bool:
	var g := Grid.of(sim.catalog, sim.state.map_id)
	return g != null and g.in_bounds(c, r) and g.walkable(c, r)


## The state building placed at map site `site` (the armory): the first building whose door is the site's door.
static func _site_building(sim: Sim, site: String) -> String:
	var m: Dictionary = sim.catalog.maps().get(sim.state.map_id, {}).get("buildings", {}).get(site, {})
	var door: Array = m.get("door", [])
	if door.size() != 2:
		return ""
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		var d: Array = sim.state.buildings[b].get("door", [])
		if d.size() == 2 and int(d[0]) == int(door[0]) and int(d[1]) == int(door[1]):
			return b
	return ""


# --- Queries for the UI -----------------------------------------------------------------------------------------

## {state, activity, bubble, occupation} of a townsperson (employees: their Routines state; others: {}).
static func view(sim: Sim, chr: String) -> Dictionary:
	var st := sim.state
	var ch: Dictionary = st.characters.get(chr, {})
	if ch.is_empty() or not is_townsperson(st, chr):
		return {}
	var occ := str(ch.get("occupation", ""))
	if ch.get("job") is Dictionary:
		var rs := Routines.state_of(sim, chr)
		var map := {"home": "home", "at_work": "working", "walking": "walking", "out": "walking", "inside": "working"}
		return {"state": str(map.get(rs, "walking")), "activity": "", "bubble": "", "occupation": occ}
	var t: Dictionary = ch.get("town", {}) if ch.get("town") is Dictionary else {}
	var state := str(t.get("state", "home"))
	var shown := str(t.get("shown", ""))
	var bubble := ""
	if state in ["social", "market"] and shown != "":
		bubble = str(sim.catalog.town.get("activities", {}).get(shown, {}).get("bubble", ""))
	return {"state": state, "activity": shown, "bubble": bubble, "occupation": occ}
