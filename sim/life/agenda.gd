class_name Agenda
extends RefCounted
## The townsfolk's agenda (docs/gdd/04f_vida_y_fiestas.md §4.24.1; docs/contratos/vida.md): needs and many things to
## do, chosen by utility. TownLife hands it the adult townsfolk (and the children) when Life.on(); employees keep
## their H4 routine. Figures: data/life/life.json needs / agenda, data/life/activities.json.
##
## character.town keeps, besides the H7 memory: needs {hunger, rest, social, fun, faith} in tenths (0-1000) and
## needs_at (the minute they were last brought up to date: they fall per_hour each whole hour), group (child | adult |
## elder, worked out once a day), and the running activity: activity, spot, slot, target, dur, until, stops (the next
## targets of a chain: stalls, a stroll), break (a break from work), started.
##
## Choosing (when an activity ends, on every hour, and when a phase starts): every activity that may be done now, by
## this person, with room, gets
##   utility(a) = (base + Σ urgency(n) × raises(a, n) / raise_scale) × liking × hour × event × group − distance × cost
##   urgency(n) = ((100 − n) / 100) ^ 2
## and the best is taken (random_share of the times one of the random_top best, at random). In DAY the work is the
## duty: a break (break_chance_per_hour of data/town.json) or a day of rest lets another activity in.
## No rule of the economy changes: shopping walks the stalls the market's demand points to (Market.effective_demand)
## and raises hunger; nothing is bought.

const LOG_PREFIX: String = "[Agenda]"


static func acts(sim: Sim) -> Dictionary:
	return sim.catalog.life_tables.get("activities", {})


static func acfg(sim: Sim) -> Dictionary:
	return Life.cfg(sim.catalog).get("agenda", {})


static func ncfg(sim: Sim) -> Dictionary:
	return Life.cfg(sim.catalog).get("needs", {})


# --- Needs ------------------------------------------------------------------------------------------------------------

## The needs of townsperson memory `t` now, in tenths (created at needs.start the first time).
static func needs(sim: Sim, t: Dictionary, now: int) -> Dictionary:
	var c := ncfg(sim)
	if not t.get("needs") is Dictionary or (t["needs"] as Dictionary).is_empty():
		var n := {}
		for k: Variant in c.get("ids", []):
			n[str(k)] = int(c.get("start", 700))
		t["needs"] = n
		t["needs_at"] = now
	var hours := (now - int(t.get("needs_at", now))) / 60
	if hours > 0:
		var per: Dictionary = c.get("per_hour", {})
		for k: String in (t["needs"] as Dictionary).keys():
			t["needs"][k] = maxi(0, int(t["needs"][k]) - int(per.get(k, 0)) * hours)
		t["needs_at"] = int(t.get("needs_at", now)) + hours * 60
	return t["needs"]


## Raises the needs of `t` by `raises` (points 0-100).
static func raise(sim: Sim, t: Dictionary, raises: Dictionary, now: int) -> void:
	var n := needs(sim, t, now)
	for k: String in raises:
		if n.has(k):
			n[k] = clampi(int(n[k]) + int(raises[k]) * 10, 0, 1000)


## Sets each need of `t` to at least `to` (tenths): what a night at home gives.
static func at_least(sim: Sim, t: Dictionary, to: Dictionary, now: int) -> void:
	var n := needs(sim, t, now)
	for k: String in to:
		if n.has(k):
			n[k] = maxi(int(n[k]), mini(1000, int(n[k]) + int(to[k])))


static func urgency(v: int) -> float:
	var x := float(100 - clampi(v / 10, 0, 100)) / 100.0
	return x * x


## Whether `chr` is «of much faith» (a share of the townsfolk, drawn per person once and for all).
static func pious(sim: Sim, chr: String) -> bool:
	return Kin.roll(sim.state, "life|pious|%s" % chr) < float(ncfg(sim).get("pious_share", 0.3))


# --- The day -----------------------------------------------------------------------------------------------------------

## child | adult | elder for `chr` (once a day in t.group).
static func group(sim: Sim, chr: String, t: Dictionary, today: int) -> String:
	if int(t.get("group_day", -1)) != today:
		var age := Kin.age(sim, chr)
		var g := "adult"
		if age < int(sim.catalog.family.get("life", {}).get("majority_age", 16)):
			g = "child"
		elif age >= int(acfg(sim).get("elder_age", 55)):
			g = "elder"
		t["group"] = g
		t["group_day"] = today
		t["age"] = age
	return str(t["group"])


## One minute of townsperson `chr` (TownLife._step_one with the living town on; the greeting, the counter customer
## and the night home are TownLife's).
static func run(sim: Sim, chr: String, t: Dictionary, now: int, phase: String) -> void:
	if Incidents.holds(sim.state, chr):
		return  # a brawler or a watcher: the incident moves it
	if t.has("activity"):
		if now % 60 == 0 and phase == "day" and str(t["activity"]) == "work" and _breaks(sim, chr, t, now):
			if decide(sim, chr, t, now, phase, true):
				_go(sim, chr, t, now)
				return
		var asleep_ok := phase == "night" or (phase == "dawn" and now < int(t.get("leave_at", 0)))
		if int(t.get("phase_seen", -1)) != _phase_index(phase) and str(t["activity"]) in ["work", "sleep"]:
			_clear(t)  # a new phase: the duty or the bed of the last one is over
		elif str(t["activity"]) == "sleep" and not asleep_ok:
			_clear(t)  # time to get up
		elif now % 60 == 0 and not bool(t.get("break", false)) and not _allowed_now(sim, str(t["activity"]), phase, now):
			_clear(t)  # out of its hours (the tavern at 02:00, the mass after 09:00)
		else:
			_go(sim, chr, t, now)
			if t.has("activity"):
				return
	t["phase_seen"] = _phase_index(phase)
	if phase == "dawn" and now < int(t.get("leave_at", 0)):
		_start(sim, chr, t, now, "sleep", false)
		_go(sim, chr, t, now)
		return
	if decide(sim, chr, t, now, phase, false):
		_go(sim, chr, t, now)
		return
	if str(t.get("group", "")) == "child" or phase == "night":
		_start(sim, chr, t, now, "sleep", false)
		_go(sim, chr, t, now)
		return
	TownLife._stroll(sim, chr, t, now)


## A child's minute: at home, except to play in the day (agenda.children_play).
static func run_child(sim: Sim, chr: String, t: Dictionary, now: int, phase: String) -> void:
	if Incidents.holds(sim.state, chr):
		return
	if not bool(acfg(sim).get("children_play", true)) or phase != "day":
		_clear(t)
		var home := str(sim.state.characters[chr].get("home", ""))
		TownLife._go_building(sim, chr, t, home, now)
		TownLife._set_state(sim, chr, t, "home" if str(sim.state.characters[chr].get("location", "")) == home else "walking")
		return
	run(sim, chr, t, now, phase)


static func _phase_index(phase: String) -> int:
	return ["dawn", "day", "dusk", "night"].find(phase)


## Whether the work gives way to a break this hour (H7's break chance; elders more; a day of rest, more).
static func _breaks(sim: Sim, chr: String, t: Dictionary, now: int) -> bool:
	var p := float(t.get("break_permil", 0)) / 1000.0
	if str(t.get("group", "")) == "elder":
		p *= float(acfg(sim).get("elder_break_mult", 2.0))
	if Life.holy_day(sim):
		p = maxf(p, 1.0 - float(acfg(sim).get("holy_day_work_mult", 0.3)))
	return Kin.roll(sim.state, "life|brk|%s|%d" % [chr, now]) < p


## Chooses and sets up the next activity. `is_break`: only the ones allowed in a work break (not the work).
static func decide(sim: Sim, chr: String, t: Dictionary, now: int, phase: String, is_break: bool) -> bool:
	var st := sim.state
	var a := acfg(sim)
	var grp := str(t.get("group", "adult"))
	var n := needs(sim, t, now)
	var pos := Life.tile_of(st, chr)
	var stats: Dictionary = st.characters[chr].get("stats", {})
	if phase == "day" and not is_break and grp != "child" and _qualifies(sim, chr, acts(sim).get("work", {}), stats, t) \
			and acts(sim).has("work"):
		return _start(sim, chr, t, now, "work", false)  # the duty of the day
	var pre: Array = []  # [utility before the walk, id]: the walk only takes away, so the places are looked up best first
	var all := acts(sim)
	var names: Array = all.keys()
	names.sort()
	for id: String in names:
		var d: Dictionary = all[id]
		if is_break and (not bool(d.get("break", false)) or id == "work"):
			continue
		var w := _when(sim, d, phase, now)
		if w <= 0.0:
			continue
		var gm := float((d.get("who", {}) as Dictionary).get(grp, 0.0))
		if gm <= 0.0 or not _qualifies(sim, chr, d, stats, t):
			continue
		var u := float(d.get("base", 0.0))
		var raises: Dictionary = d.get("raises", {})
		for k: String in raises:
			u += urgency(int(n.get(k, 1000))) * float(raises[k]) / float(a.get("raise_scale", 20))
		u *= w * gm * _liking(sim, chr, d, stats) * Life.event_mult(sim, "routine", id)
		if bool(st.characters[chr].get("female", false)):
			u *= float(d.get("female_mult", 1.0))
		pre.append([u, id])
	pre.sort_custom(func(x: Array, y: Array) -> bool:
		return float(x[0]) > float(y[0]) or (float(x[0]) == float(y[0]) and str(x[1]) < str(y[1])))
	var top_n := int(a.get("random_top", 3))
	var cands: Array = []  # [utility, id, spot], the best top_n exactly
	for e: Array in pre:
		if cands.size() >= top_n and float(e[0]) < float(cands[top_n - 1][0]):
			break  # nothing further down can enter the top: its utility before the walk is already lower
		var spot := _spot(sim, chr, str(e[1]), all[e[1]], now)
		if spot.is_empty():
			continue
		var u := float(e[0])
		if spot.has("tile"):
			u -= float(Life.dist(pos, spot["tile"])) * float(a.get("distance_cost", 0.02))
		cands.append([u, str(e[1]), spot])
		cands.sort_custom(func(x: Array, y: Array) -> bool:
			return float(x[0]) > float(y[0]) or (float(x[0]) == float(y[0]) and str(x[1]) < str(y[1])))
	if cands.is_empty():
		return false
	var pick: Array = cands[0]
	if Kin.roll(st, "life|exc|%s|%d" % [chr, now]) < float(a.get("random_share", 0.12)):
		var top := mini(top_n, cands.size())
		pick = cands[Kin.randi_range(st, "life|exc_pick|%s|%d" % [chr, now], 0, top - 1)]
	if OS.is_debug_build():
		var shown: Array = []
		for c: Array in cands.slice(0, 3):
			shown.append("%s=%.2f" % [c[1], float(c[0])])
		print("%s %s elige %s%s (%s)" % [LOG_PREFIX, chr, pick[1], " (descanso)" if is_break else "", ", ".join(shown)])
	return _start(sim, chr, t, now, str(pick[1]), is_break, pick[2])


## hour(a): the weight of the phase (0 = not now), the hour window, the peak; a day of rest opens holy_phases.
static func _when(sim: Sim, d: Dictionary, phase: String, now: int) -> float:
	var when: Dictionary = d.get("when", {})
	var w := float(when.get(phase, 0.0))
	if w <= 0.0 and phase in (d.get("holy_phases", []) as Array) and Life.holy_day(sim):
		w = 1.0
	if w <= 0.0:
		return 0.0
	var h := Clock.minute_of_day(now) / 60
	var win: Array = d.get("hours", [])
	if win.size() == 2 and not _in_hours(h, int(win[0]), int(win[1])):
		return 0.0
	var peak: Dictionary = d.get("peak", {})
	var ph: Array = peak.get("hours", [])
	if ph.size() == 2 and _in_hours(h, int(ph[0]), int(ph[1])):
		w *= float(peak.get("mult", 1.0))
	return w


static func _in_hours(h: int, from: int, to: int) -> bool:
	return (h >= from and h < to) or (to > 24 and h < to - 24)


static func _allowed_now(sim: Sim, id: String, phase: String, now: int) -> bool:
	var d: Dictionary = acts(sim).get(id, {})
	if d.is_empty():
		return false
	if id in ["work", "sleep"]:
		return true
	return _when(sim, d, phase, now) > 0.0


static func _qualifies(sim: Sim, chr: String, d: Dictionary, stats: Dictionary, t: Dictionary) -> bool:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	for k: String in (d.get("min_stat", {}) as Dictionary):
		if int(stats.get(k, 0)) < int(d["min_stat"][k]):
			return false
	if d.has("requires_young") and int(t.get("age", 30)) > int(d["requires_young"]):
		return false
	match str(d.get("requires", "")):
		"occupation":
			return str(ch.get("occupation", "")) != "" and not TownLife.workplace(st, sim.catalog, str(ch["occupation"])).is_empty()
		"relatives":
			return not relative_doors(sim, chr).is_empty()
		"single":
			return Kin.is_single(st, chr)
	return true


static func _liking(sim: Sim, chr: String, d: Dictionary, stats: Dictionary) -> float:
	var by := str(d.get("liked_by", ""))
	if by == "":
		return 1.0
	var a := acfg(sim)
	var yes := pious(sim, chr) if by == "pious" else int(stats.get(by, 0)) >= int(a.get("stat_min", 7))
	return float(a.get("liking_mult", 1.4)) if yes else 1.0


# --- Where ---------------------------------------------------------------------------------------------------------

## Where activity `id` would take `chr` now: {tile, spot?, slot?, stops?, building?} ({} = no room).
static func _spot(sim: Sim, chr: String, id: String, d: Dictionary, now: int) -> Dictionary:
	var st := sim.state
	var key := "life|%s|%s|%d" % [id, chr, now]
	match str(d.get("spot", "")):
		"work":
			var wp := TownLife.workplace(st, sim.catalog, str(st.characters[chr].get("occupation", "")))
			return {} if wp.is_empty() else {"tile": (wp.get("tile", [0, 0]) as Array).duplicate()}
		"home":
			var h := str(st.characters[chr].get("home", ""))
			return {} if not st.buildings.has(h) else {"tile": (st.buildings[h].get("door", [0, 0]) as Array).duplicate(), "building": h}
		"points":
			return free_slot(sim, chr, d.get("kinds", []), key)
		"stalls":
			var stops := _stalls_by_demand(sim, key, d.get("stops", [2, 3]))
			return {} if stops.is_empty() else {"tile": stops[0], "stops": stops}
		"stroll":
			var stops: Array = []
			var span: Array = d.get("stops", [2, 3])
			var n := Kin.randi_range(st, key + "|n", int(span[0]), int(span[1]))
			var pts := Life.points(sim, d.get("kinds", []))
			if pts.is_empty():
				return {}
			for i: int in n:
				var p: Dictionary = pts[Kin.randi_range(st, key + "|%d" % i, 0, pts.size() - 1)]
				var slots: Array = p.get("slots", [])
				stops.append((slots[Kin.randi_range(st, key + "|s%d" % i, 0, slots.size() - 1)] as Array).duplicate())
			return {"tile": stops[0], "stops": stops}
		"gate":
			var g := Life.gates(sim)
			if g.is_empty():
				return {}
			var names: Array = g.keys()
			names.sort()
			var gt: Array = g[names[Kin.randi_range(st, key, 0, names.size() - 1)]]
			return {"tile": _inside(sim, gt)}
		"relative":
			var doors := relative_doors(sim, chr)
			return {} if doors.is_empty() else {"tile": doors[Kin.randi_range(st, key, 0, doors.size() - 1)]}
		"spectacle":
			var sp := Life.spectacles(st)
			if sp.is_empty():
				return {}
			var s: Dictionary = sp[Kin.randi_range(st, key, 0, sp.size() - 1)]
			var base: Array = s["tile"]
			var off := Kin.randi_range(st, key + "|off", 0, 7)
			var dirs := [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
			for i: int in 8:
				var dd: Array = dirs[(off + i) % 8]
				var tt := [int(base[0]) + int(dd[0]) * 2, int(base[1]) + int(dd[1]) * 2]
				if TownLife._walkable(sim, int(tt[0]), int(tt[1])):
					return {"tile": tt, "until": int(s["until"])}
			return {}
	return {}


## A gate tile one step into the map (the gate spawn is on the edge).
static func _inside(sim: Sim, gt: Array) -> Array:
	var size: Array = Life.map(sim).get("size", [40, 40])
	var c := clampi(int(gt[0]), 1, int(size[0]) - 2)
	var r := clampi(int(gt[1]), 1, int(size[1]) - 2)
	if TownLife._walkable(sim, c, r):
		return [c, r]
	return (gt as Array).duplicate()


## The service tiles of the outdoor stalls, `stops` of them drawn by the demand of what each sells (the market's own
## demand: Market.effective_demand; nothing is bought).
static var _stall_w_key: String = ""
static var _stall_w: Array = []


static func _stalls_by_demand(sim: Sim, key: String, span: Array) -> Array:
	var stalls: Dictionary = Life.map(sim).get("stalls", {})
	var ks: Array = stalls.keys()
	ks.sort()
	if ks.is_empty():
		return []
	var wkey := "%d|%d" % [sim.state.get_instance_id(), int(sim.state.clock["minute"]) / 60]
	if wkey != _stall_w_key:  # the demand moves slowly: worked out once an hour
		_stall_w = []
		for k: String in ks:
			var sells: Array = sim.catalog.market.get("stalls", {}).get(k, {}).get("sells", [k])
			var sum := 0.0
			var cnt := 0
			for item: String in sim.catalog.items():
				if str(sim.catalog.item(item).get("market_stall", "")) in sells:
					sum += Market.effective_demand(sim, item)
					cnt += 1
			_stall_w.append(sum / float(cnt) if cnt > 0 else 1.0)
		_stall_w_key = wkey
	var weights: Array = _stall_w.duplicate()
	var n := mini(ks.size(), Kin.randi_range(sim.state, key + "|n", int(span[0]), int(span[1])))
	var out: Array = []
	for i: int in n:
		var total := 0.0
		for w: float in weights:
			total += w
		if total <= 0.0:
			break
		var r := Kin.roll(sim.state, key + "|st%d" % i) * total
		var pick := weights.size() - 1
		for j: int in weights.size():
			r -= float(weights[j])
			if r < 0.0:
				pick = j
				break
		out.append((stalls[ks[pick]].get("service", [0, 0]) as Array).duplicate())
		weights[pick] = 0.0
	return out


## The doors of the houses where `chr`'s parents, children or siblings live (not its own).
static func relative_doors(sim: Sim, chr: String) -> Array:
	var st := sim.state
	var ch: Dictionary = st.characters.get(chr, {})
	var home := str(ch.get("home", ""))
	var kin: Array = (ch.get("parents", []) as Array) + (ch.get("children", []) as Array)
	for p: Variant in ch.get("parents", []):
		kin += (st.characters.get(str(p), {}).get("children", []) as Array)
	var seen := {}
	var out: Array = []
	for k: Variant in kin:
		var o: Dictionary = st.characters.get(str(k), {})
		var h := str(o.get("home", ""))
		if o.is_empty() or not bool(o.get("alive", true)) or h == "" or h == home or seen.has(h) or not st.buildings.has(h):
			continue
		seen[h] = true
		out.append((st.buildings[h].get("door", [0, 0]) as Array).duplicate())
	return out


static var _taken_minute: int = -1
static var _taken_state: int = 0
static var _taken: Dictionary = {}


## The slots taken now ("point|slot" -> chr): built once per minute and kept up to date as people choose.
static func taken(sim: Sim) -> Dictionary:
	var now := int(sim.state.clock["minute"])
	if now != _taken_minute or sim.state.get_instance_id() != _taken_state:
		_taken = {}
		for id: Variant in sim.state.characters:
			var tt: Variant = sim.state.characters[id].get("town")
			if tt is Dictionary and (tt as Dictionary).has("activity") and str(tt.get("spot", "")) != "":
				_taken["%s|%d" % [tt["spot"], int(tt.get("slot", -1))]] = str(id)
		_taken_minute = now
		_taken_state = sim.state.get_instance_id()
	return _taken


## A free slot of a social point of one of `kinds` ({spot, slot, tile} or {}): among the points somebody already
## stands at first (a corrillo forms), else any with room; the corrillo has at most meeting.corrillo.max.
static func free_slot(sim: Sim, chr: String, kinds: Array, key: String) -> Dictionary:
	var tk := taken(sim)
	var cmax := int(Life.cfg(sim.catalog).get("meeting", {}).get("corrillo", {}).get("max", 5))
	var free: Array = []
	var joined: Array = []
	for p: Dictionary in Life.points(sim, kinds):
		var slots: Array = p.get("slots", [])
		var busy := 0
		for i: int in slots.size():
			if tk.has("%s|%d" % [p["id"], i]) and str(tk["%s|%d" % [p["id"], i]]) != chr:
				busy += 1
		if busy >= cmax:
			continue
		for i: int in slots.size():
			var k := "%s|%d" % [p["id"], i]
			if not tk.has(k) or str(tk[k]) == chr:
				var e := {"spot": str(p["id"]), "slot": i, "tile": (slots[i] as Array).duplicate(), "kind": str(p.get("kind", ""))}
				free.append(e)
				if busy > 0:
					joined.append(e)
	if free.is_empty():
		return {}
	var pool: Array = joined if not joined.is_empty() and Kin.roll(sim.state, key + "|join") < 0.7 else free
	return pool[Kin.randi_range(sim.state, key + "|slot", 0, pool.size() - 1)]


# --- Running an activity ---------------------------------------------------------------------------------------------

static func _start(sim: Sim, chr: String, t: Dictionary, now: int, id: String, is_break: bool, spot: Dictionary = {}) -> bool:
	var d: Dictionary = acts(sim).get(id, {})
	if d.is_empty():
		return false
	var key := "life|dur|%s|%s|%d" % [id, chr, now]
	_clear(t)
	t["activity"] = id
	t["break"] = is_break
	t["until"] = -1
	t["started"] = now
	if spot.is_empty() and str(d.get("spot", "")) in ["work", "home"]:
		spot = _spot(sim, chr, id, d, now)
	if spot.has("stops"):
		var stops: Array = (spot["stops"] as Array).duplicate()
		stops.pop_front()
		t["stops"] = stops
		var pm: Array = d.get("per_stop_minutes", [30, 30])
		t["dur"] = Kin.randi_range(sim.state, key, int(pm[0]), int(pm[1]))
	else:
		var mm: Array = d.get("minutes", [60, 60])
		t["dur"] = Kin.randi_range(sim.state, key, int(mm[0]), int(mm[1]))
	if is_break:
		var bm: Array = sim.catalog.town.get("routine", {}).get("break_minutes", [90, 150])
		t["dur"] = mini(int(t["dur"]), Kin.randi_range(sim.state, key + "|brk", int(bm[0]), int(bm[1])))
	if spot.has("until"):
		t["dur"] = mini(int(t["dur"]), maxi(10, int(spot["until"]) - now))
	if spot.has("tile"):
		t["target"] = (spot["tile"] as Array).duplicate()
	if str(spot.get("spot", "")) != "":
		t["spot"] = str(spot["spot"])
		t["slot"] = int(spot.get("slot", -1))
		taken(sim)["%s|%d" % [t["spot"], int(t["slot"])]] = chr
	if OS.is_debug_build():
		print("%s %s empieza %s%s (destino=%s, %d min)" % [LOG_PREFIX, chr, id, " (descanso)" if is_break else "",
			t.get("target", "-"), int(t["dur"])])
	return true


## Walks to the activity's place and runs its clock; at its end its needs go up and it is cleared.
static func _go(sim: Sim, chr: String, t: Dictionary, now: int) -> void:
	var id := str(t.get("activity", ""))
	var d: Dictionary = acts(sim).get(id, {})
	var shown := str(d.get("shown", "social"))
	match str(d.get("spot", "")):
		"work":
			TownLife._plan_work(sim, chr, t, now)
			return
		"home":
			var home := str(sim.state.characters[chr].get("home", ""))
			t["plan"] = "home"
			if not TownLife._go_building(sim, chr, t, home, now):
				TownLife._set_state(sim, chr, t, "walking", id)
				return
			TownLife._set_state(sim, chr, t, "home", id)
			if id == "sleep":
				return
	if not t.has("target") and str(d.get("spot", "")) != "home":
		_clear(t)
		return
	if t.has("target") and not TownLife._go_tile(sim, chr, t, t["target"], now):
		TownLife._set_state(sim, chr, t, "walking", id)
		return
	if int(t.get("until", -1)) < 0:
		t["until"] = now + int(t.get("dur", 60))
	if now >= int(t["until"]):
		var stops: Array = t.get("stops", [])
		if not stops.is_empty():
			t["target"] = (stops.pop_front() as Array).duplicate()
			t["until"] = -1
			TownLife._set_state(sim, chr, t, "walking", id)
			return
		raise(sim, t, d.get("raises", {}), now)
		if OS.is_debug_build():
			print("%s %s acaba %s" % [LOG_PREFIX, chr, id])
		sim.events.append({"type": "activity_done", "character": chr, "activity": id})
		_clear(t)
		return
	if shown != "home":
		TownLife._set_state(sim, chr, t, shown, id)


const KEYS: Array[String] = ["activity", "spot", "slot", "target", "dur", "until", "stops", "break", "started",
	"wait_until", "stalls"]


static func _clear(t: Dictionary) -> void:
	for k: String in KEYS:
		t.erase(k)


## The night at home: rest, supper and breakfast (needs.night) at the start of the townsperson's day.
static func new_day(sim: Sim, t: Dictionary, now: int) -> void:
	at_least(sim, t, ncfg(sim).get("night", {}), now)


# --- Queries for the UI ---------------------------------------------------------------------------------------------

## {needs: {id: 0-100}, activity, pious} of a townsperson ({} if it has no agenda yet).
static func view(sim: Sim, chr: String) -> Dictionary:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	var t: Variant = ch.get("town")
	if not t is Dictionary or not (t as Dictionary).get("needs") is Dictionary:
		return {}
	var n := needs(sim, t, int(sim.state.clock["minute"]))
	var out := {}
	for k: String in n:
		out[k] = int(n[k]) / 10
	return {"needs": out, "activity": str((t as Dictionary).get("activity", "")), "pious": pious(sim, chr)}
