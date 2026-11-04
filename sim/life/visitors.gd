class_name Visitors
extends RefCounted
## Visitors (docs/gdd/04f_vida_y_fiestas.md §4.24.3, 4.22.3.6 brought forward; docs/contratos/vida.md): per_day of
## them a day (more in a festival) come in by a gate of the map from a town of the region, walk their plan (by kind:
## the merchant the stalls, the pilgrim the atrium, the minstrel plays in the plaza...) and leave at dusk by the same
## gate (they will sleep at the inn when there is one: 4.27). Temporary characters of fam_visitors: taken out of the
## state when they leave. Figures: data/life/life.json "visitors".
##
## state.town.visitors: alive [chr], day (the day planned), planned [{at, kind, city, gate}], alms {fam: day}.
## character.visitor: {kind, city, gate, purse, plan [[spot, minutes]], stop, until, leaving}; character.town holds
## the seat it takes ({activity, spot, slot}), so the townsfolk see it taken.


static func cfg(sim: Sim) -> Dictionary:
	return Life.cfg(sim.catalog).get("visitors", {})


static func book(st: WorldState) -> Dictionary:
	var b: Variant = st.town.get("visitors")
	if b is Dictionary and (b as Dictionary).size() > 0:
		return b
	Life.ensure(st)
	return st.town["visitors"]


## The visitors on the map now (ids, sorted).
static func alive(st: WorldState) -> Array:
	var v: Variant = st.town.get("visitors")
	if not v is Dictionary:
		return []
	var out: Array = []
	for id: Variant in (v as Dictionary).get("alive", []):
		if st.characters.has(str(id)):
			out.append(str(id))
	return out


static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var today := Clock.day(now)
	var b := book(st)
	if int(b.get("day", -1)) != today:
		_plan_day(sim, today)
	var keep: Array = []
	for p: Dictionary in b["planned"]:
		if now >= int(p["at"]):
			_arrive(sim, p)
		else:
			keep.append(p)
	b["planned"] = keep
	var phase := Clock.phase(now, sim.catalog.time)
	for v: String in alive(st):
		_step_one(sim, v, now, phase)


## Today's arrivals: per_day [min, max] (× festival_mult in a festival, × the events' visitors effect), at most
## max_alive (fair_max in a fair) on the map at once.
static func _plan_day(sim: Sim, today: int) -> void:
	var st := sim.state
	var c := cfg(sim)
	var b := book(st)
	b["day"] = today
	b["planned"] = []
	var gates := Life.gates(sim)
	if gates.is_empty():
		return
	var span: Array = c.get("per_day", [2, 4])
	var n := Kin.randi_range(st, "life|vis|n|%d" % today, int(span[0]), int(span[1]))
	if Life.festival(sim) and not Festivals.on_today(sim):  # fiestas: a feast of the calendar brings its own
		n *= int(c.get("festival_mult", 3))
	n = roundi(float(n) * Life.event_mult(sim, "visitors"))
	var cities: Array = []
	var home := Region.home_id(sim)
	for s: Dictionary in Region.settlements(sim):
		if str(s.get("id", "")) != home:
			cities.append(str(s["id"]))
	if cities.is_empty():
		cities = [""]
	var gnames: Array = gates.keys()
	gnames.sort()
	var hours: Array = c.get("arrive_hours", [8, 13])
	var base := today * Clock.MINUTES_PER_DAY
	for i: int in n:
		var key := "life|vis|%d|%d" % [today, i]
		var at := base + Kin.randi_range(st, key + "|at", int(hours[0]) * 60, int(hours[1]) * 60)
		b["planned"].append({"at": at, "kind": _kind(sim, key), "city": str(cities[Kin.randi_range(st, key + "|city", 0, cities.size() - 1)]),
			"gate": str(gnames[Kin.randi_range(st, key + "|gate", 0, gnames.size() - 1)]), "key": key})
	(b["planned"] as Array).sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["at"]) < int(y["at"]))
	if OS.is_debug_build():
		print("[Visitors] día %d: %d forasteros previstos" % [today, n])


static func _kind(sim: Sim, key: String) -> String:
	var kinds: Dictionary = cfg(sim).get("kinds", {})
	var names: Array = kinds.keys()
	names.sort()
	var fest := Festivals.today_kinds(sim)  # fiestas (04f 4.25.3): the kinds the feast of the day brings weigh double
	var total := 0.0
	for k: String in names:
		total += float(kinds[k].get("weight", 0)) * (2.0 if k in fest else 1.0)
	var r := Kin.roll(sim.state, key + "|kind") * total
	for k: String in names:
		r -= float(kinds[k].get("weight", 0)) * (2.0 if k in fest else 1.0)
		if r < 0.0:
			return k
	return str(names[names.size() - 1])


static func _arrive(sim: Sim, p: Dictionary) -> void:
	var st := sim.state
	var c := cfg(sim)
	var b := book(st)
	var cap := int(c.get("fair_max", 30)) if Life.event_mult(sim, "visitors") > 3.0 else int(c.get("max_alive", 12))
	if alive(st).size() >= cap:
		return
	var gates := Life.gates(sim)
	if not gates.has(str(p["gate"])):
		return
	var kind := str(p["kind"])
	var kd: Dictionary = c.get("kinds", {}).get(kind, {})
	var key := str(p.get("key", "life|vis"))
	var female := Kin.roll(st, key + "|sex") < (0.3 if kind in ["soldier", "merchant"] else 0.5)
	var age_span: Array = c.get("age", [20, 50])
	var age := Kin.randi_range(st, key + "|age", int(age_span[0]), int(age_span[1]))
	var purse: Array = kd.get("purse", [0, 0])
	var dress: Dictionary = c.get("city_dress", {}).get(str(p["city"]), {})
	Life.service_family(st, Life.FAMILY_VISITORS, "family.visitors", {"primary": "#6a5a4a", "secondary": "#c8b8a0"})
	var look := Cast.newcomer(sim, key, female, age)
	var name := str(look.get("name", "?"))
	var gate_tile: Array = gates[str(p["gate"])]
	var plan: Array = (kd.get("plan", [["meet", 120]]) as Array).duplicate(true)
	var id := Life.add_person(sim, Life.FAMILY_VISITORS, name, female, age, kd.get("stats", {}), {}, gate_tile,
		{"visitor": {"kind": kind, "city": str(p["city"]), "gate": str(p["gate"]),
			"purse": Kin.randi_range(st, key + "|purse", int(purse[0]), int(purse[1])), "plan": plan, "stop": -1,
			"until": -1, "leaving": false, "arrived": int(st.clock["minute"])}})
	var vis: Dictionary = st.characters[id]["visual"]
	vis["hair"] = int(look.get("hair", vis.get("hair", 0)))
	vis["skin"] = int(look.get("skin", vis.get("skin", 0)))
	if not dress.is_empty():
		vis["dress"] = dress.duplicate()
	Life.put_on(sim, id, gate_tile)
	(b["alive"] as Array).append(id)
	sim.events.append({"type": "visitor_arrived", "character": id, "kind": kind, "city": str(p["city"]),
		"gate": str(p["gate"])})
	if OS.is_debug_build():
		print("[Visitors] llega %s «%s» (%s de %s) por %s" % [id, name, kind, p["city"], p["gate"]])


## One minute of a visitor: the next stop of its plan, or the way out at dusk.
static func _step_one(sim: Sim, v: String, now: int, phase: String) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[v]
	var vis: Dictionary = ch["visitor"]
	if not ch.get("town") is Dictionary:
		ch["town"] = {}
	var t: Dictionary = ch["town"]
	if Incidents.holds(st, v) or Life.is_captive(st, v):
		return  # in a brawl, or held by the bandits
	if phase in ["dusk", "night"] and not bool(vis.get("leaving", false)):
		_leave(sim, v)
	if bool(vis.get("leaving", false)):
		var gate: Array = Life.gates(sim).get(str(vis.get("gate", "")), Life.plaza(sim))
		if TownLife._go_tile(sim, v, t, gate, now):
			_gone(sim, v)
		return
	var plan: Array = vis.get("plan", [])
	var i := int(vis.get("stop", -1))
	if i < 0 or (int(vis.get("until", -1)) >= 0 and now >= int(vis["until"])):
		i += 1
		vis["stop"] = i
		vis["until"] = -1
		t.erase("spot")
		t.erase("slot")
		t.erase("activity")
		_end_show(sim, v)
		if i >= plan.size():
			_leave(sim, v)
			return
		var spot := _stop_tile(sim, v, str(plan[i][0]), "life|vstop|%s|%d" % [v, i])
		if spot.is_empty():
			vis["until"] = now  # nowhere to go: the next stop
			return
		vis["target"] = spot["tile"]
		t["activity"] = "visit_" + str(vis.get("kind", ""))
		if str(spot.get("spot", "")) != "":
			t["spot"] = str(spot["spot"])
			t["slot"] = int(spot.get("slot", -1))
			Agenda.taken(sim)["%s|%d" % [t["spot"], int(t["slot"])]] = v
	var target: Array = vis.get("target", [])
	if target.size() != 2:
		return
	if not TownLife._go_tile(sim, v, t, target, now):
		TownLife._set_state(sim, v, t, "walking", "")
		return
	if int(vis.get("until", -1)) < 0:
		vis["until"] = now + int(plan[i][1])
		var kd: Dictionary = cfg(sim).get("kinds", {}).get(str(vis.get("kind", "")), {})
		if str(kd.get("spectacle", "")) != "" and str(plan[i][0]) == "square":
			Life.add_spectacle(sim, str(kd["spectacle"]), target, int(vis["until"]), v)
	TownLife._set_state(sim, v, t, "social", "visit_" + str(vis.get("kind", "")))


## Where a stop of a visitor's plan is: a stall, a meeting point seat, the atrium, a bench, the open plaza...
static func _stop_tile(sim: Sim, v: String, spot: String, key: String) -> Dictionary:
	match spot:
		"stalls":
			var tiles := Agenda._stalls_by_demand(sim, key, [1, 1])
			return {} if tiles.is_empty() else {"tile": tiles[0]}
		"meet":
			return Agenda.free_slot(sim, v, ["chat", "well", "gate", "bridge", "tavern"], key)
		_:
			var s := Agenda.free_slot(sim, v, [spot], key)
			if s.is_empty() and spot in ["tavern", "atrium"]:
				s = Agenda.free_slot(sim, v, ["chat", "bench"], key)
			return s


static func _end_show(sim: Sim, v: String) -> void:
	var keep: Array = []
	for s: Dictionary in Life.spectacles(sim.state):
		if str(s.get("by", "")) != v:
			keep.append(s)
	sim.state.town["life"]["spectacles"] = keep


static func _leave(sim: Sim, v: String) -> void:
	var vis: Dictionary = sim.state.characters[v]["visitor"]
	vis["leaving"] = true
	var t: Dictionary = sim.state.characters[v].get("town", {})
	t.erase("spot")
	t.erase("slot")
	t.erase("activity")
	_end_show(sim, v)


static func _gone(sim: Sim, v: String) -> void:
	var b := book(sim.state)
	(b["alive"] as Array).erase(v)
	sim.events.append({"type": "visitor_left", "character": v})
	if OS.is_debug_build():
		print("[Visitors] se va %s" % v)
	Life.remove_person(sim, v)


# --- Alms (4.24.3: the beggar at the atrium) ---------------------------------------------------------------------

## {"type": "give_alms", "actor", "target"}: the actor, within the NPC actions' range of a beggar, gives him
## alms.gold; once a day per family its reputation goes up alms.reputation.
static func order_alms(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var tv: Dictionary = st.characters.get(target, {}).get("visitor", {}) if st.characters.has(target) else {}
	if str(tv.get("kind", "")) != "beggar":
		return Orders.fail("not_a_beggar")
	var range_tiles := int(sim.catalog.town.get("actions", {}).get("range_tiles", 3))
	if Life.dist(Life.tile_of(st, actor), Life.tile_of(st, target)) > range_tiles:
		return Orders.fail("too_far")
	var fam := str(st.characters[actor].get("family", ""))
	var a: Dictionary = cfg(sim).get("alms", {})
	var gold := int(a.get("gold", 1))
	if Money.gold(st, fam) < gold:
		return Orders.fail("not_enough_gold")
	Money.change(sim, fam, -gold, Money.DONATIONS, target, "", actor)
	var today := Clock.day(int(st.clock["minute"]))
	var b := book(st)
	if int(b["alms"].get(fam, -1)) != today:
		b["alms"][fam] = today
		Reputation.change(sim, fam, int(a.get("reputation", 1)), "alms")
	sim.events.append({"type": "alms_given", "actor": actor, "target": target, "family": fam, "gold": gold})
	return Orders.ok()
