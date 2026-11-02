class_name Schedules
extends RefCounted
## The programmable routine of the controlled characters (GDD 4.10.8) and the Work directive of the family members
## run by AI (4.10.6). Contract: docs/contratos/h8_familia.md. Figures: data/family.json "routine", "directives".
##
## character.schedule = null (no routine: only manual orders) or {phase: slot} for the four phases of the day, slot =
## {action: "work" | "rest" | "free", building?, zone?, recipe?, mode?}. work: goes to the building (default: its
## assigned one, Kin.assigned_building) and works the recipe and mode given (default: the best paid one it can make
## now at a free station, normal mode), repeating on its own (Production). rest: goes home (Kin.home_of) and stays,
## not working. free: follows its directives (only "work" in the MVP: like work with the defaults).
## Who: the adults of the human family without a job. Controlled ones (controlled_by "human") with a schedule follow
## it; the AI ones (the spouse, adults outside the group) follow their directives, and rest in ai_rest_phases.
## It acts only with the real orders (exit_building, enter_building, work_at, stop_work) through Sim.give.
## A manual order rules (note_manual, from Sim.step for the orders from outside): the character carries out its order
## queue and, when it is idle again (not walking, nothing queued, no cycle running) and manual_grace_minutes have passed
## since the last manual order, goes back to the slot of now.
## Memory in character.routine: {manual: bool, manual_until: int, retry_at: int, slot: phase} (Routines only touches
## employees).


## The default routine of someone joining the group (data/family.json routine.default): Day = work, the rest free.
static func default_schedule(sim: Sim, _chr: String) -> Dictionary:
	return (sim.catalog.family.get("routine", {}).get("default", {}) as Dictionary).duplicate(true)


## Sim.step calls it for each order from outside, before applying it: a non-management order for a family member
## marks the manual override.
static func note_manual(sim: Sim, o: Dictionary) -> void:
	var type := str(o.get("type", ""))
	if Orders.is_management(type) or type in ["", "wait"]:
		return
	var ch: Dictionary = sim.state.characters.get(str(o.get("actor", "")), {})
	if ch.is_empty() or str(sim.state.families.get(str(ch.get("family", "")), {}).get("controlled_by", "")) != "human":
		return
	if not ch.get("routine") is Dictionary:
		ch["routine"] = {}
	if not bool(ch["routine"].get("manual", false)):
		ch["routine"]["manual"] = true
		sim.events.append({"type": "routine_paused", "character": str(ch["id"])})
		if OS.is_debug_build():
			print("[Schedules] %s: orden manual %s, la rutina espera" % [ch["id"], type])
	ch["routine"]["manual_until"] = int(sim.state.clock["minute"]) \
		+ int(sim.catalog.family.get("routine", {}).get("manual_grace_minutes", 60))
	ch["routine"].erase("retry_at")


## Once per minute, after Routines and before WorkQueue.
static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var phase := Clock.phase(now, sim.catalog.time)
	var fams: Array = st.families.keys()
	fams.sort()
	for fam: String in fams:
		if str(st.families[fam].get("controlled_by", "")) != "human":
			continue
		for m: Variant in (st.families[fam].get("members", []) as Array).duplicate():
			var chr := str(m)
			if Kin.alive(st, chr) and st.characters[chr].get("job") == null and Kin.is_adult(sim, chr):
				_step_one(sim, chr, phase, now)


## What `chr` should do now: {action, building, zone, recipe, mode} or {} (nothing: no routine, manual override).
static func current_slot(sim: Sim, chr: String, phase: String) -> Dictionary:
	var ch: Dictionary = sim.state.characters[chr]
	var slot := {}
	if str(ch.get("controlled_by", "")) == "human":
		var sched: Variant = ch.get("schedule")
		if not sched is Dictionary:
			return {}
		slot = ((sched as Dictionary).get(phase, {"action": "free"}) as Dictionary).duplicate()
	elif phase in (sim.catalog.family.get("routine", {}).get("ai_rest_phases", ["night"]) as Array):
		slot = {"action": "rest"}
	else:
		slot = {"action": "free"}
	if str(slot.get("action", "free")) == "free":
		slot = {"action": "work"} if "work" in (ch.get("directives", []) as Array) else {"action": "idle"}
	return slot


static func _step_one(sim: Sim, chr: String, phase: String, now: int) -> void:
	var ch: Dictionary = sim.state.characters[chr]
	if not ch.get("routine") is Dictionary:
		ch["routine"] = {}
	var r: Dictionary = ch["routine"]
	if bool(r.get("manual", false)):
		if not _idle(sim, chr) or now < int(r.get("manual_until", 0)):
			return
		r["manual"] = false
		r.erase("manual_until")
		sim.events.append({"type": "routine_resumed", "character": chr})
		if OS.is_debug_build():
			print("[Schedules] %s vuelve a su rutina (%s)" % [chr, phase])
	var slot := current_slot(sim, chr, phase)
	if slot.is_empty() or str(slot.get("action", "")) == "idle":
		return
	if str(r.get("slot", "")) != phase:
		r["slot"] = phase
		r.erase("retry_at")
		sim.events.append({"type": "routine_slot", "character": chr, "phase": phase, "action": str(slot["action"])})
	if now < int(r.get("retry_at", -1)):
		return
	match str(slot["action"]):
		"work":
			_work(sim, chr, r, slot, now)
		"rest":
			_rest(sim, chr, r, now)


## Idle: not walking, nothing queued, no cycle of its own running (a blocked one counts as finished).
static func _idle(sim: Sim, chr: String) -> bool:
	return OrderQueue.is_free(sim, chr) and not OrderQueue.has_pending(sim, chr)


static func _work(sim: Sim, chr: String, r: Dictionary, slot: Dictionary, now: int) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	var bld := str(slot.get("building", ""))
	if bld == "" or str(st.buildings.get(bld, {}).get("owner", "")) != str(ch.get("family", "")):
		bld = Kin.assigned_building(sim, chr)
	if bld == "":
		return
	if not _go(sim, chr, r, bld, now):
		return
	if Production.job_zone(sim, chr, bld) != "":
		return  # working (or its finished cycle waits for room): leave it
	if Production.may_work(sim, chr, bld) != "" or str(st.buildings[bld].get("state", "normal")) != "normal":
		return  # not now (night rule, under works, damaged for unpaid upkeep...): no order that would be refused
	var pick := pick_work(sim, chr, bld, str(slot.get("zone", "")), str(slot.get("recipe", "")))
	if pick.is_empty():
		r["retry_at"] = now + _retry(sim)
		return
	sim.give({"type": "work_at", "actor": chr, "building": bld, "zone": str(pick["zone"]), "recipe": str(pick["recipe"]),
		"mode": str(slot.get("mode", "normal"))})
	if Production.job_zone(sim, chr, bld) == "":
		r["retry_at"] = now + _retry(sim)
		if OS.is_debug_build():
			print("[Schedules] %s no puede trabajar %s en %s/%s; reintenta a las %s" % [chr, pick["recipe"], bld,
				pick["zone"], Routines._hhmm(now + _retry(sim))])


static func _rest(sim: Sim, chr: String, r: Dictionary, now: int) -> void:
	var home := Kin.home_of(sim, chr)
	if home == "":
		return
	var loc := str(sim.state.characters[chr].get("location", ""))
	if loc == home and Production.job_zone(sim, chr, home) != "":
		sim.give({"type": "stop_work", "actor": chr})
		return
	_go(sim, chr, r, home, now)


## Takes `chr` into `bld`: true when it is inside; walking there or just sent -> false.
static func _go(sim: Sim, chr: String, r: Dictionary, bld: String, now: int) -> bool:
	var ch: Dictionary = sim.state.characters[chr]
	var loc := str(ch.get("location", ""))
	if loc == bld:
		return true
	var q: Array = ch.get("order_queue", [])
	if not q.is_empty() and str(q[0].get("type", "")) == "enter_building" and str(q[0].get("building", "")) == bld:
		return false  # on its way
	if not (ch.get("path", []) as Array).is_empty() and q.is_empty():
		return false  # walking somewhere on its own: let it arrive
	if loc != "":
		sim.give({"type": "exit_building", "actor": chr})
	sim.give({"type": "enter_building", "actor": chr, "building": bld})
	var ok := str(ch.get("location", "")) == bld or (not (ch.get("order_queue", []) as Array).is_empty()
		and str(ch["order_queue"][0].get("building", "")) == bld)
	if not ok:
		r["retry_at"] = now + _retry(sim)
	return str(ch.get("location", "")) == bld


static func _retry(sim: Sim) -> int:
	return int(sim.catalog.family.get("routine", {}).get("retry_minutes", 30))


## The station and recipe to work at `bld` now: the given ones if they can be made, else the best paid recipe (sell
## price of its output, then id) the actor can make now at a free station of its kind. {} if none.
static func pick_work(sim: Sim, chr: String, bld: String, zone: String, recipe: String) -> Dictionary:
	var st := sim.state
	var zones: Dictionary = st.buildings[bld].get("zones", {})
	var free: Array = []
	var zs: Array = zones.keys()
	zs.sort()
	for z: String in zs:
		var occ := str(zones[z].get("occupant", ""))
		if (occ == "" or occ == chr or not Kin.alive(st, occ) or str(st.characters[occ].get("location", "")) != bld) \
				and not zones[z].get("job") is Dictionary:
			free.append(z)
	var best := {}
	var best_price := -1
	for z: String in free:
		if zone != "" and Upgrades.zone_kind(sim, bld, z) != Upgrades.zone_kind(sim, bld, zone):
			continue
		for opt: Dictionary in Production.recipe_options(sim, chr, bld, z):
			if str(opt["status"]) != "ok" or (recipe != "" and str(opt["recipe"]) != recipe):
				continue
			var out: Dictionary = sim.catalog.recipes()[str(opt["recipe"])].get("output", {})
			var p := Market.price(sim, str(out.get("item", "")), 0, "sell")
			if p > best_price or (p == best_price and str(opt["recipe"]) < str(best.get("recipe", ""))):
				best_price = p
				best = {"zone": z, "recipe": str(opt["recipe"])}
	return best


# --- Orders ----------------------------------------------------------------------------------------------------------

## {"type": "set_schedule", "actor", "character", "schedule"}: a member of the family sets the routine of a controlled
## member (null = none). Management order. Each slot is checked: phase, action, building of the family, its station and
## recipe, mode.
static func order_set(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var who := str(o.get("character", ""))
	if not Kin.alive(st, actor):
		return Orders.fail("unknown_actor")
	var fam := str(st.characters[actor].get("family", ""))
	if not Kin.alive(st, who) or str(st.characters[who].get("family", "")) != fam:
		return Orders.fail("not_family")
	if str(st.characters[who].get("controlled_by", "")) != "human":
		return Orders.fail("not_controlled")
	var sched: Variant = o.get("schedule")
	if sched != null:
		var why := check_schedule(sim, fam, sched)
		if why != "":
			return Orders.fail(why)
		sched = (sched as Dictionary).duplicate(true)
	st.characters[who]["schedule"] = sched
	if st.characters[who].get("routine") is Dictionary:
		st.characters[who]["routine"].erase("retry_at")
		st.characters[who]["routine"].erase("slot")
	sim.events.append({"type": "schedule_changed", "actor": actor, "character": who})
	if OS.is_debug_build():
		print("[Schedules] %s cambia la rutina de %s: %s" % [actor, who, sched])
	return Orders.ok()


## "" if `sched` is a valid routine for family `fam`, else the reason.
static func check_schedule(sim: Sim, fam: String, sched: Variant) -> String:
	if not sched is Dictionary:
		return "bad_schedule"
	var acts: Array = sim.catalog.family.get("routine", {}).get("actions", ["work", "rest", "free"])
	for ph: Variant in sched:
		var slot: Variant = sched[ph]
		if not str(ph) in Clock.PHASES or not slot is Dictionary:
			return "bad_schedule"
		if not str(slot.get("action", "")) in acts:
			return "bad_schedule"
		var bld := str(slot.get("building", ""))
		if bld != "" and str(sim.state.buildings.get(bld, {}).get("owner", "")) != fam:
			return "not_your_building"
		var zone := str(slot.get("zone", ""))
		if zone != "" and (bld == "" or not (sim.state.buildings[bld].get("zones", {}) as Dictionary).has(zone)):
			return "unknown_station"
		var rec := str(slot.get("recipe", ""))
		if rec != "":
			var r: Dictionary = sim.catalog.recipes().get(rec, {})
			if r.is_empty() or (bld != "" and str(r.get("building", "")) != str(sim.state.buildings[bld].get("type", ""))):
				return "unknown_recipe"
		var mode := str(slot.get("mode", "normal"))
		if not (sim.catalog.production.get("modes", {}) as Dictionary).has(mode):
			return "unknown_mode"
	return ""


## {"type": "set_directives", "actor", "character", "directives": [ids]}: the order of priority of a family member's
## directives (GDD 4.10.6; only "work" exists in the MVP). Management order.
static func order_set_directives(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var who := str(o.get("character", ""))
	if not Kin.alive(st, actor):
		return Orders.fail("unknown_actor")
	if not Kin.alive(st, who) or str(st.characters[who].get("family", "")) != str(st.characters[actor].get("family", "")):
		return Orders.fail("not_family")
	var d: Variant = o.get("directives", [])
	if not d is Array:
		return Orders.fail("bad_directives")
	var known: Array = sim.catalog.family.get("directives", {}).get("known", ["work"])
	for x: Variant in d:
		if not str(x) in known:
			return Orders.fail("bad_directives")
	st.characters[who]["directives"] = (d as Array).map(func(x: Variant) -> String: return str(x))
	sim.events.append({"type": "directives_changed", "actor": actor, "character": who})
	return Orders.ok()


## What the ficha shows: {schedule (or null), slot now, action now, manual}.
static func view(sim: Sim, chr: String) -> Dictionary:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty():
		return {}
	var phase := Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time)
	return {"schedule": ch.get("schedule"), "phase": phase, "now": current_slot(sim, chr, phase),
		"manual": bool(ch.get("routine", {}).get("manual", false)) if ch.get("routine") is Dictionary else false,
		"directives": ch.get("directives", [])}
