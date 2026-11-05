class_name WorkQueue
extends RefCounted
## The production queue of a building and how its work is handed to the employees (GDD 4.7.4). Owner: subgrim
## «cola». Contract: docs/contratos/h4_empleados.md.
##
## state.buildings[bld].queue = {entries: [entry], loop: bool, paused: bool,
##                               assigned: {chr: {zone, recipe, entry}}, idle: {chr: reason}, stalled: ""|reason}
##   entry = {id: "qen_0001", recipe, qty: int (>= 1; -1 = infinite), done: int, blocked: ""|reason}
## assigned / idle / stalled / blocked are the memory of «cola» (JSON only; created when first needed).
## Employees work in normal mode, without master touch, and never at night (Production.may_work). Roles: a station id
## or "any" (character.job.role); a fixed role only works at its kind of station (BUG-023).
##
## Resolution per unit with dependencies: for the next unit of an entry not yet started, every input missing in the
## storage (counting what the running cycles will deliver) is made first by the recipe of the same building that
## produces it, only as many as that one unit needs (never a stock of intermediates). An entry that cannot be made
## (a raw material missing, no room, nobody able) is marked with a notice and skipped; if none can, the queue stalls
## (general notice) and the employees stay idle.
## Production calls cycle_done() when an employee's cycle delivers; employees do not repeat on their own.

const INFINITE: int = -1
const MAX_DEPTH: int = 4
## Reasons an entry is skipped (view status and notices).
const NOTICE_KEYS: Dictionary = {
	"missing_inputs": "notice.queue_missing_inputs",
	"storage_full": "notice.queue_storage_full",
	"skill_too_low": "notice.queue_cannot_make",
	"needs_upgrade": "notice.queue_cannot_make",
	"no_worker": "notice.queue_cannot_make",
}


# --- Orders ----------------------------------------------------------------------------------------------------------

## {"type": "queue_add", "actor", "building", "recipe", "qty"} (qty 1, 5, 10 or -1 = infinite; the sim takes >= 1).
static func order_add(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var why := _owner_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	var recipe_id := str(o.get("recipe", ""))
	var recipe: Dictionary = sim.catalog.recipes().get(recipe_id, {})
	if recipe.is_empty():
		return Orders.fail("unknown_recipe")
	if str(recipe.get("building", "")) != str(st.buildings[bld].get("type", "")):
		return Orders.fail("wrong_building")
	var qty := _as_int(o.get("qty"), 0)
	if qty < 1 and qty != INFINITE:
		return Orders.fail("bad_quantity")
	var q := _queue(st, bld)
	var id := Ids.next(st, "qen")
	(q["entries"] as Array).append({"id": id, "recipe": recipe_id, "qty": qty, "done": 0, "blocked": ""})
	_changed(sim, bld)
	if OS.is_debug_build():
		print("[WorkQueue] %s añade %s ×%d a la cola de %s (entrada=%s)" % [actor, recipe_id, qty, bld, id])
	return Orders.ok()


## {"type": "queue_remove", "actor", "building", "entry"}. A cycle already running for it ends normally (its output
## stays in the storage) but no longer counts for any entry.
static func order_remove(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var why := _owner_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	var q := _queue(sim.state, bld)
	var i := _entry_index(q, str(o.get("entry", "")))
	if i < 0:
		return Orders.fail("unknown_entry")
	var e: Dictionary = (q["entries"] as Array).pop_at(i)
	_changed(sim, bld)
	if OS.is_debug_build():
		print("[WorkQueue] %s quita %s (%s) de la cola de %s" % [actor, e["id"], e["recipe"], bld])
	return Orders.ok()


## {"type": "queue_move", "actor", "building", "entry", "to"} (to = new index, 0 = first; clamped to the range).
static func order_move(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var why := _owner_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	var q := _queue(sim.state, bld)
	var i := _entry_index(q, str(o.get("entry", "")))
	if i < 0:
		return Orders.fail("unknown_entry")
	var entries: Array = q["entries"]
	var to := clampi(_as_int(o.get("to"), 0), 0, entries.size() - 1)
	var e: Dictionary = entries.pop_at(i)
	entries.insert(to, e)
	_changed(sim, bld)
	if OS.is_debug_build():
		print("[WorkQueue] %s mueve %s de %d a %d en la cola de %s" % [actor, e["id"], i, to, bld])
	return Orders.ok()


## {"type": "queue_loop", "actor", "building", "on": bool}. Loop: when the last entry is done, back to the first with
## done = 0. Without loop, finished entries leave the queue.
static func order_loop(sim: Sim, o: Dictionary) -> Dictionary:
	return _set_flag(sim, o, "loop")


## {"type": "queue_pause", "actor", "building", "on": bool}. Paused: no new work (running cycles end).
static func order_pause(sim: Sim, o: Dictionary) -> Dictionary:
	return _set_flag(sim, o, "paused")


## {"type": "set_role", "actor", "employee", "role"} (a station id of the building that is in roles, or "any").
## A cycle already running ends normally; the next work follows the new role.
static func order_set_role(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var emp := str(o.get("employee", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var bld := Staff.employer(st, emp)
	if bld == "" or not Buildings.owns(st, actor, bld):
		return Orders.fail("not_your_employee")
	var role := str(o.get("role", ""))
	var roles: Dictionary = sim.catalog.employees.get("roles", {})
	if not roles.has(role) or (role != "any" and not (st.buildings[bld].get("zones", {}) as Dictionary).has(role)):
		return Orders.fail("unknown_role")
	st.characters[emp]["job"]["role"] = role
	sim.events.append({"type": "role_changed", "actor": actor, "employee": emp, "role": role})
	if OS.is_debug_build():
		print("[WorkQueue] %s pone a %s el rol %s (%s)" % [actor, emp, role, bld])
	return Orders.ok()


# --- Step ------------------------------------------------------------------------------------------------------------

## Once per minute, after Routines and before Production (Sim.step): for each building with employees at work, marks
## the entries that cannot be made (notice), the stalled queue (notice), and hands the next unit's work to each free
## employee at a station of its role (work_at, normal mode, through Sim.give).
static func step(sim: Sim) -> void:
	var st := sim.state
	# the staff of each building, in one pass over the characters (Staff.employees_of per building walked them all
	# for every building every minute); nothing in this step hires or fires, so it holds for the whole step
	var staff_of := {}
	for id: Variant in st.characters:
		var job: Variant = st.characters[id].get("job")
		if job is Dictionary:
			var eb := str((job as Dictionary).get("building", ""))
			if eb != "":
				if not staff_of.has(eb):
					staff_of[eb] = []
				(staff_of[eb] as Array).append(str(id))
	for k: Variant in staff_of:
		(staff_of[k] as Array).sort()
	for bld: String in _sorted_keys(st.buildings):
		var b: Dictionary = st.buildings[bld]
		if not b.get("queue") is Dictionary:
			continue
		var q: Dictionary = b["queue"]
		if int(b.get("employee_slots", 0)) <= 0 and (q.get("assigned", {}) as Dictionary).is_empty() \
				and (q.get("idle", {}) as Dictionary).is_empty():
			continue
		_step_building(sim, bld, staff_of.get(bld, []))


static func _step_building(sim: Sim, bld: String, staff: Array) -> void:
	var q := _queue(sim.state, bld)
	_clean_assigned(sim, bld, q)
	_tidy(sim, bld, q)
	if Upgrades.under_works(sim.state, bld):
		_idle_under_works(sim, bld, q, staff)
		return
	var present: Array = []  # active employees inside, allowed to work now
	for c: String in staff:
		if _at_work(sim, c, bld):
			present.append(c)
	_clean_idle(sim, bld, q, present)
	if present.is_empty():
		return
	var plans := _plans(sim, bld, q, staff)
	_mark_entries(sim, bld, q, plans)
	# Free employees: fixed roles first (they have only one kind of station), then "any"; by id inside each.
	var free: Array = []
	for c: String in present:
		if OrderQueue.is_free(sim, c) and Production.job_zone(sim, c, bld) == "":
			free.append(c)
	free.sort_custom(func(a: String, b: String) -> bool:
		var fa := _role(sim, a) == "any"
		var fb := _role(sim, b) == "any"
		if fa != fb:
			return not fa
		return a < b)
	for c: String in free:
		if _service_role(sim, bld, c):
			continue  # posada: a role at a service station (the inn's bar, tables, rooms) is run by its system, not the queue
		if bool(q.get("paused", false)):
			_set_idle(sim, bld, q, c, "paused")
			continue
		if _assign(sim, bld, q, c, plans):
			plans = _plans(sim, bld, q, staff)  # the storage changed
		else:
			_set_idle(sim, bld, q, c, _idle_reason(sim, bld, q, c, plans))


## Gives `chr` the first task of the queue it can do now. True if it started.
static func _assign(sim: Sim, bld: String, q: Dictionary, chr: String, plans: Array) -> bool:
	var st := sim.state
	var b: Dictionary = st.buildings[bld]
	var zones: Dictionary = b.get("zones", {})
	for p: Dictionary in plans:
		if str(p["reason"]) != "":
			continue
		for rid: String in p["tasks"]:
			var recipe: Dictionary = sim.catalog.recipes()[rid]
			var kind := str(recipe.get("zone", ""))
			if not _role_allows(sim, chr, kind) or Production._lock_reason(sim, st.characters[chr], b, recipe) != "":
				continue
			var zone := _free_station(sim, bld, kind, chr)
			if zone == "":
				continue
			sim.give({"type": "work_at", "actor": chr, "building": bld, "zone": zone, "recipe": rid, "mode": "normal"})
			if Production.job_zone(sim, chr, bld) != zone:
				continue  # refused (order_refused in the events): try the next task
			if not q.get("assigned") is Dictionary:
				q["assigned"] = {}
			q["assigned"][chr] = {"zone": zone, "recipe": rid, "entry": str(p["entry"])}
			_set_idle(sim, bld, q, chr, "")
			sim.events.append({"type": "employee_assigned", "building": bld, "employee": chr, "zone": zone,
				"recipe": rid, "entry": str(p["entry"])})
			if OS.is_debug_build():
				print("[WorkQueue] %s: %s hace %s en %s (entrada=%s)" % [bld, chr, rid, zone, p["entry"]])
			return true
	return false


## H5: the station of `kind` where `chr` can start now: the one it already holds if it is of that kind, else the first
## free one by id — the type's own station, then the copies an upgrade added (anvil, anvil_2; Upgrades.zone_kind).
## "" if none. A fixed role works at every station of its kind (the role names the kind).
static func _free_station(sim: Sim, bld: String, kind: String, chr: String) -> String:
	var zones: Dictionary = sim.state.buildings[bld].get("zones", {})
	var mine := str(sim.state.characters[chr].get("station", ""))
	if zones.has(mine) and Upgrades.zone_kind(sim, bld, mine) == kind and not zones[mine].get("job") is Dictionary:
		return mine
	for z: String in _sorted_keys(zones):
		if Upgrades.zone_kind(sim, bld, z) != kind:
			continue
		var occ := str(zones[z].get("occupant", ""))
		if (occ == "" or occ == chr) and not zones[z].get("job") is Dictionary:
			return z
	return ""


## H5: while the building is under works nobody gets work (GDD 4.8): the active employees inside are idle with reason
## under_works (no notice: the works have their own); the others lose their idle mark.
static func _idle_under_works(sim: Sim, bld: String, q: Dictionary, staff: Array) -> void:
	var inside: Array = []
	for c: String in staff:
		var ch: Dictionary = sim.state.characters.get(c, {})
		if bool(ch.get("alive", true)) and str(ch.get("location", "")) == bld and Staff.is_active(sim, c):
			inside.append(c)
	_clean_idle(sim, bld, q, inside)
	for c: String in inside:
		_set_idle(sim, bld, q, c, "under_works")


## Called by Production when an employee's cycle delivers `qty` of the output of `recipe` at `zone`.
static func cycle_done(sim: Sim, bld: String, zone: String, chr: String, recipe: String, qty: int) -> void:
	var q: Dictionary = sim.state.buildings.get(bld, {}).get("queue", {})
	var assigned: Dictionary = q.get("assigned", {})
	var a: Dictionary = assigned.get(chr, {})
	if a.is_empty() or str(a["zone"]) != zone or str(a["recipe"]) != recipe:
		return
	assigned.erase(chr)
	var i := _entry_index(q, str(a["entry"]))
	if i < 0:
		return
	var e: Dictionary = q["entries"][i]
	if str(e["recipe"]) != recipe:
		return  # an intermediate for that entry
	e["done"] = int(e["done"]) + qty
	_changed(sim, bld)
	if OS.is_debug_build():
		print("[WorkQueue] %s: %s entrega %d de %s (entrada=%s, hechas=%d/%d)" % [bld, chr, qty, recipe, e["id"],
			int(e["done"]), int(e["qty"])])
	if int(e["qty"]) != INFINITE and int(e["done"]) >= int(e["qty"]):
		sim.events.append({"type": "queue_entry_done", "building": bld, "entry": str(e["id"]), "recipe": recipe})


# --- Planning --------------------------------------------------------------------------------------------------------

## One plan per entry, in queue order, on a shared view of the storage (earlier entries reserve first):
## [{entry, recipe, tasks: [recipe ids startable now], reason: "" | why it is skipped, working: bool}].
static func _plans(sim: Sim, bld: String, q: Dictionary, staff: Array) -> Array:
	var st := sim.state
	var b: Dictionary = st.buildings[bld]
	var btype := str(b.get("type", ""))
	var avail := _available(sim, bld)
	var in_flight := _final_in_flight(sim, bld, q)
	var out: Array = []
	for e: Dictionary in q.get("entries", []):
		var eid := str(e["id"])
		var plan := {"entry": eid, "recipe": str(e["recipe"]), "tasks": [], "reason": "",
			"working": _entry_working(sim, bld, q, eid)}
		out.append(plan)
		var qty := int(e["qty"])
		if qty != INFINITE and int(e["done"]) + int(in_flight.get(eid, 0)) >= qty:
			continue  # every unit left is already being made
		if not sim.catalog.recipes().has(str(e["recipe"])):
			plan["reason"] = "missing_inputs"
			continue
		var trial := avail.duplicate(true)
		var r := _resolve(sim, btype, str(e["recipe"]), 1, trial, 0)
		if str(r["reason"]) != "":
			plan["reason"] = r["reason"]
			continue
		# Somebody must be able to do each task, and its output must fit.
		for rid: String in r["tasks"]:
			var why := _who_reason(sim, b, rid, staff)
			if why == "":
				why = _room_reason(sim, b, rid)
			if why != "":
				plan["reason"] = why
				break
		if str(plan["reason"]) != "":
			continue
		plan["tasks"] = r["tasks"]
		avail = trial
	return out


## What one more `units` of `recipe_id` need now on `avail` ({stock: item -> count in the storage, incoming: item ->
## count the running cycles will deliver}), which it consumes as it reserves: {tasks: [recipe ids startable now],
## reason: "" | "missing_inputs"}. An input short in the storage is covered first by what is coming (then it waits),
## else made first by the building's recipe that outputs it, only as many units as needed. The recipe itself is
## startable only when all its inputs are in the storage.
static func _resolve(sim: Sim, btype: String, recipe_id: String, units: int, avail: Dictionary, depth: int) -> Dictionary:
	var recipe: Dictionary = sim.catalog.recipes()[recipe_id]
	var stock: Dictionary = avail["stock"]
	var incoming: Dictionary = avail["incoming"]
	var tasks: Array = []
	var pending := false
	for inp: Dictionary in recipe.get("inputs", []):
		var item := str(inp["item"])
		var need := int(inp["qty"]) * units
		var use := mini(int(stock.get(item, 0)), need)
		stock[item] = int(stock.get(item, 0)) - use
		var short := need - use
		if short <= 0:
			continue
		pending = true
		var coming := mini(int(incoming.get(item, 0)), short)
		incoming[item] = int(incoming.get(item, 0)) - coming
		short -= coming
		if short <= 0:
			continue
		var prod := _producer(sim, btype, item)
		if prod == "" or depth >= MAX_DEPTH:
			return {"tasks": [], "reason": "missing_inputs"}
		var per := maxi(1, int(sim.catalog.recipes()[prod].get("output", {}).get("qty", 1)))
		var sub := _resolve(sim, btype, prod, ceili(float(short) / per), avail, depth + 1)
		if str(sub["reason"]) != "":
			return sub
		tasks.append_array(sub["tasks"])
	if not pending:
		for i: int in units:
			tasks.append(recipe_id)
	return {"tasks": tasks, "reason": ""}


## The recipe of `btype` whose output is `item` ("" if none), the first by id.
static func _producer(sim: Sim, btype: String, item: String) -> String:
	for rid: String in _sorted_keys(sim.catalog.recipes()):
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) == btype and str(r.get("output", {}).get("item", "")) == item:
			return rid
	return ""


## {stock: item -> count in the storage, incoming: item -> count the running cycles of the building will deliver}.
static func _available(sim: Sim, bld: String) -> Dictionary:
	var b: Dictionary = sim.state.buildings[bld]
	var stock := {}
	var incoming := {}
	for s: Dictionary in b.get("inventory", {}).get("stacks", []):
		stock[str(s["item"])] = int(stock.get(str(s["item"]), 0)) + int(s["qty"])
	var zones: Dictionary = b.get("zones", {})
	for z: String in _sorted_keys(zones):
		var job: Variant = zones[z].get("job")
		if not job is Dictionary:
			continue
		var res: Variant = job.get("result")
		var item := ""
		var n := 0
		if res is Dictionary:
			item = str(res["item"])
			n = int(res["qty"])
		else:
			var r: Dictionary = sim.catalog.recipes().get(str(job["recipe"]), {})
			item = str(r.get("output", {}).get("item", ""))
			n = Production.output_units(sim, str(job["actor"]), bld, r)
		if item != "":
			incoming[item] = int(incoming.get(item, 0)) + n
	return {"stock": stock, "incoming": incoming}


## entry id -> units of its own recipe being made now (assigned cycles still running).
static func _final_in_flight(sim: Sim, bld: String, q: Dictionary) -> Dictionary:
	var out := {}
	var assigned: Dictionary = q.get("assigned", {})
	for c: String in _sorted_keys(assigned):
		var a: Dictionary = assigned[c]
		var i := _entry_index(q, str(a["entry"]))
		if i < 0 or str(q["entries"][i]["recipe"]) != str(a["recipe"]):
			continue
		var r: Dictionary = sim.catalog.recipes().get(str(a["recipe"]), {})
		out[str(a["entry"])] = int(out.get(str(a["entry"]), 0)) + Production.output_units(sim, c, bld, r)
	return out


static func _entry_working(_sim: Sim, _bld: String, q: Dictionary, eid: String) -> bool:
	var assigned: Dictionary = q.get("assigned", {})
	for c: Variant in assigned:
		if str(assigned[c]["entry"]) == eid:
			return true
	return false


## "" if some active employee of the building could do `rid` (its role and its craft / the building's upgrades);
## else "no_worker" (no role for that station) or the lock reason ("skill_too_low", "needs_upgrade").
static func _who_reason(sim: Sim, b: Dictionary, rid: String, staff: Array) -> String:
	var recipe: Dictionary = sim.catalog.recipes()[rid]
	var zone := str(recipe.get("zone", ""))
	var why := "no_worker"
	for c: String in staff:
		if not Staff.is_active(sim, c) or not _role_allows(sim, c, zone):
			continue
		var lock := Production._lock_reason(sim, sim.state.characters[c], b, recipe)
		if lock == "":
			return ""
		why = lock
	return why


## "storage_full" if the output of `rid` would not fit in the building's storage after taking its inputs.
static func _room_reason(sim: Sim, b: Dictionary, rid: String) -> String:
	var why := Production._stock_reason(sim.catalog, b["inventory"], sim.catalog.recipes()[rid])
	return "storage_full" if why == "storage_full" else ""


## Writes each entry's blocked reason (notice and event when it changes) and the queue's stalled state.
static func _mark_entries(sim: Sim, bld: String, q: Dictionary, plans: Array) -> void:
	var fam := Money.family_of(sim.state, bld)
	var any_ok := false
	var first_reason := ""
	for p: Dictionary in plans:
		var i := _entry_index(q, str(p["entry"]))
		var e: Dictionary = q["entries"][i]
		var reason := str(p["reason"])
		if reason == "":
			any_ok = true
		elif first_reason == "":
			first_reason = reason
		if str(e.get("blocked", "")) == reason:
			continue
		e["blocked"] = reason
		sim.events.append({"type": "queue_entry_blocked", "building": bld, "entry": str(e["id"]), "reason": reason})
		if OS.is_debug_build():
			print("[WorkQueue] %s: entrada %s (%s) %s" % [bld, e["id"], e["recipe"],
				"se salta (motivo=%s)" % reason if reason != "" else "vuelve a poder hacerse"])
		if reason != "" and fam != "":
			Notices.add(sim, fam, Notices.WARNING, str(NOTICE_KEYS.get(reason, "notice.queue_cannot_make")),
				{"building": bld, "recipe": str(e["recipe"]), "reason": reason}, bld)
	var stalled := ""
	if plans.is_empty():
		stalled = "empty_queue"
	elif not any_ok:
		stalled = first_reason
	if str(q.get("stalled", "")) == stalled:
		return
	q["stalled"] = stalled
	sim.events.append({"type": "queue_stalled", "building": bld, "reason": stalled})
	if OS.is_debug_build():
		print("[WorkQueue] %s: cola %s" % [bld, "parada (motivo=%s)" % stalled if stalled != "" else "en marcha"])
	if stalled != "" and fam != "":
		var key := "notice.queue_empty" if stalled == "empty_queue" else "notice.queue_stalled"
		Notices.add(sim, fam, Notices.WARNING, key, {"building": bld, "reason": stalled}, bld)


## Why a free employee got nothing: "paused", "empty_queue", "stalled", "no_task" (nothing in the queue for its role:
## the idle icon) or "waiting" (its part comes when the others finish; not idle).
static func _idle_reason(sim: Sim, _bld: String, q: Dictionary, chr: String, plans: Array) -> String:
	if plans.is_empty():
		return "empty_queue"
	if str(q.get("stalled", "")) != "":
		return "stalled"
	for p: Dictionary in plans:
		if str(p["reason"]) != "":
			continue
		if _chain_uses_role(sim, chr, str(p["recipe"]), 0):
			return "waiting"
	return "no_task"


## Whether the recipe or any recipe of its dependency chain is made at a station `chr`'s role allows.
static func _chain_uses_role(sim: Sim, chr: String, rid: String, depth: int) -> bool:
	var r: Dictionary = sim.catalog.recipes().get(rid, {})
	if r.is_empty():
		return false
	if _role_allows(sim, chr, str(r.get("zone", ""))):
		return true
	if depth >= MAX_DEPTH:
		return false
	for inp: Dictionary in r.get("inputs", []):
		var prod := _producer(sim, str(r.get("building", "")), str(inp["item"]))
		if prod != "" and _chain_uses_role(sim, chr, prod, depth + 1):
			return true
	return false


## Records the idle state of `chr` ("" = busy, "waiting" = not idle); event and notice when it becomes idle.
static func _set_idle(sim: Sim, bld: String, q: Dictionary, chr: String, reason: String) -> void:
	if not q.get("idle") is Dictionary:
		q["idle"] = {}
	var idle: Dictionary = q["idle"]
	var now_idle := reason != "" and reason != "waiting"
	var before := str(idle.get(chr, ""))
	if not now_idle:
		idle.erase(chr)
		return
	if before == reason:
		return
	idle[chr] = reason
	sim.events.append({"type": "employee_idle", "building": bld, "employee": chr, "reason": reason})
	if OS.is_debug_build():
		print("[WorkQueue] %s: %s ocioso (motivo=%s)" % [bld, chr, reason])
	var fam := Money.family_of(sim.state, bld)
	if reason == "no_task" and fam != "":
		Notices.add(sim, fam, Notices.INFO, "notice.employee_idle",
			{"building": bld, "employee": chr, "role": _role(sim, chr)}, bld)


## Drops the assignments whose cycle is no longer running (interrupted, or the employee is gone).
static func _clean_assigned(sim: Sim, bld: String, q: Dictionary) -> void:
	var assigned: Dictionary = q.get("assigned", {})
	if assigned.is_empty():
		return
	var zones: Dictionary = sim.state.buildings[bld].get("zones", {})
	for c: String in _sorted_keys(assigned):
		var a: Dictionary = assigned[c]
		var job: Variant = zones.get(str(a["zone"]), {}).get("job")
		if job is Dictionary and str(job["actor"]) == c and str(job["recipe"]) == str(a["recipe"]):
			continue
		assigned.erase(c)
		if OS.is_debug_build():
			print("[WorkQueue] %s: la tarea de %s (%s) ya no corre" % [bld, c, a["recipe"]])


## Idle marks only for employees still at work.
static func _clean_idle(_sim: Sim, _bld: String, q: Dictionary, present: Array) -> void:
	var idle: Dictionary = q.get("idle", {})
	for c: String in _sorted_keys(idle):
		if not c in present:
			idle.erase(c)


## Finished entries: without loop they leave the queue; with loop, when every entry is finished, all start again.
static func _tidy(sim: Sim, bld: String, q: Dictionary) -> void:
	var entries: Array = q["entries"]
	if entries.is_empty():
		return
	if not bool(q.get("loop", false)):
		var keep: Array = entries.filter(func(e: Dictionary) -> bool: return not _finished(e))
		if keep.size() != entries.size():
			q["entries"] = keep
			_changed(sim, bld)
		return
	for e: Dictionary in entries:
		if not _finished(e):
			return
	for e: Dictionary in entries:
		e["done"] = 0
	_changed(sim, bld)
	if OS.is_debug_build():
		print("[WorkQueue] %s: bucle, la cola vuelve a empezar" % bld)


static func _finished(e: Dictionary) -> bool:
	return int(e["qty"]) != INFINITE and int(e["done"]) >= int(e["qty"])


# --- Queries ---------------------------------------------------------------------------------------------------------

## The queue of `bld` for the production panel: {entries: [{id, recipe, qty, done, status}], loop, paused, stalled}.
## status: "ok" | "working" | the reason it is skipped ("missing_inputs", "storage_full", "skill_too_low",
## "needs_upgrade", "no_worker"); stalled: "" or why nothing can be made ("empty_queue" or an entry's reason).
## How many units of `recipe` the building's storage allows now, from its direct inputs (the production panel's
## «da para N»). Read only.
static func can_make(sim: Sim, bld: String, recipe: String) -> int:
	var inv: Dictionary = sim.state.buildings.get(bld, {}).get("inventory", {})
	var r: Dictionary = sim.catalog.recipes().get(recipe, {})
	var n := 1 << 30
	for inp: Dictionary in r.get("inputs", []):
		n = mini(n, Inventory.count(inv, str(inp["item"])) / maxi(1, int(inp["qty"])))
	return 0 if n == 1 << 30 else n


static func view(sim: Sim, bld: String) -> Dictionary:
	var q: Dictionary = sim.state.buildings.get(bld, {}).get("queue", {})
	var entries: Array = []
	for e: Dictionary in q.get("entries", []):
		var eid := str(e.get("id", ""))
		var status := str(e.get("blocked", ""))
		if status == "":
			status = "working" if _entry_working(sim, bld, q, eid) else "ok"
		entries.append({"id": eid, "recipe": str(e.get("recipe", "")), "qty": int(e.get("qty", 1)),
			"done": int(e.get("done", 0)), "status": status})
	return {"entries": entries, "loop": bool(q.get("loop", false)), "paused": bool(q.get("paused", false)),
		"stalled": str(q.get("stalled", ""))}


## The active employees of `bld` that are at work with nothing to do now (the idle icon over the building), by id.
static func idle_employees(sim: Sim, bld: String) -> Array:
	var idle: Dictionary = sim.state.buildings.get(bld, {}).get("queue", {}).get("idle", {})
	var out: Array = []
	for c: String in _sorted_keys(idle):
		if _at_work(sim, c, bld) and Production.job_zone(sim, c, bld) == "":
			out.append(c)
	return out


## The buildings of `fam` with idle employees (the map icons), by id.
static func idle_buildings(sim: Sim, fam: String) -> Array:
	var out: Array = []
	for b: String in _sorted_keys(sim.state.buildings):
		if str(sim.state.buildings[b].get("owner", "")) == fam and not idle_employees(sim, b).is_empty():
			out.append(b)
	return out


## What `chr` is doing for the queue: {} or {zone, recipe, entry}.
static func task_of(sim: Sim, chr: String) -> Dictionary:
	var bld := Staff.employer(sim.state, chr)
	if bld == "":
		return {}
	var a: Dictionary = sim.state.buildings.get(bld, {}).get("queue", {}).get("assigned", {}).get(chr, {})
	if a.is_empty():
		return {}
	var job: Variant = sim.state.buildings[bld].get("zones", {}).get(str(a["zone"]), {}).get("job")
	if not job is Dictionary or str(job["actor"]) != chr:
		return {}
	return {"zone": str(a["zone"]), "recipe": str(a["recipe"]), "entry": str(a["entry"])}


# --- Helpers ---------------------------------------------------------------------------------------------------------

## Active employee of `bld`, inside it, alive, and allowed to work now (Production.may_work).
static func _at_work(sim: Sim, chr: String, bld: String) -> bool:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	return not ch.is_empty() and bool(ch.get("alive", true)) and str(ch.get("location", "")) == bld \
		and Staff.is_active(sim, chr) and Production.may_work(sim, chr, bld) == ""


## Posada: whether `chr`'s role is a station of kind "service" of `bld`'s type (Inn serves and makes beds with them).
static func _service_role(sim: Sim, bld: String, chr: String) -> bool:
	var role := _role(sim, chr)
	for z: Dictionary in sim.catalog.buildings().get(str(sim.state.buildings[bld].get("type", "")), {}).get("zones", []):
		if str(z.get("id", "")) == role:
			return str(z.get("kind", "")) == "service"
	return false


static func _role(sim: Sim, chr: String) -> String:
	var job: Variant = sim.state.characters.get(chr, {}).get("job")
	return str((job as Dictionary).get("role", "any")) if job is Dictionary else "any"


## A fixed role only works at its kind of station (BUG-023); "any" wherever needed.
static func _role_allows(sim: Sim, chr: String, zone: String) -> bool:
	var role := _role(sim, chr)
	return role == "any" or role == zone


static func _owner_reason(sim: Sim, actor: String, bld: String) -> String:
	if not sim.state.characters.has(actor):
		return "unknown_actor"
	if not sim.state.buildings.has(bld):
		return "unknown_building"
	if not Buildings.owns(sim.state, actor, bld):
		return "not_your_building"
	return ""


static func _set_flag(sim: Sim, o: Dictionary, flag: String) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var why := _owner_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	var on: Variant = o.get("on", false)
	var q := _queue(sim.state, bld)
	q[flag] = on is bool and bool(on)
	_changed(sim, bld)
	if OS.is_debug_build():
		print("[WorkQueue] %s pone %s=%s en la cola de %s" % [actor, flag, q[flag], bld])
	return Orders.ok()


## The queue of a building, created with its base shape if missing.
static func _queue(st: WorldState, bld: String) -> Dictionary:
	var b: Dictionary = st.buildings[bld]
	if not b.get("queue") is Dictionary:
		b["queue"] = {"entries": [], "loop": false, "paused": false}
	var q: Dictionary = b["queue"]
	if not q.get("entries") is Array:
		q["entries"] = []
	return q


static func _entry_index(q: Dictionary, eid: String) -> int:
	var entries: Array = q.get("entries", [])
	for i: int in entries.size():
		if str(entries[i].get("id", "")) == eid:
			return i
	return -1


static func _changed(sim: Sim, bld: String) -> void:
	sim.events.append({"type": "queue_changed", "building": bld, "family": Money.family_of(sim.state, bld)})


## An int from an order field: ints and whole floats; anything else gives `fallback`.
static func _as_int(v: Variant, fallback: int) -> int:
	if v is int:
		return v
	if v is float and is_equal_approx(v, roundf(v)):
		return roundi(v)
	return fallback


static func _sorted_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys().map(func(k: Variant) -> String: return str(k))
	keys.sort()
	return keys
