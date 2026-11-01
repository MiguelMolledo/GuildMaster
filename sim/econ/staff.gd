class_name Staff
extends RefCounted
## Employees: hiring and firing, ranks and promotions, real wages, loyalty, quitting and theft (GDD 4.7.1-4.7.3).
## Owner: subgrim «plantilla». Contract: docs/contratos/h4_empleados.md. Figures in data/employees.json
## (Catalog.employees, catalog.rank(id)).
##
## An employee is a townsperson (a character of the world, GDD 4.11.1) with a job:
##   character.rank = "apprentice" | "journeyman" | "master" ("" = not a trade worker), kept when the job ends
##   character.job  = null (unemployed) or {building, role, loyalty, hired_day, start_day, end_day, days_worked,
##                    rank_days, unpaid_days, promotion_offered}
##   character.home = the house it sleeps in; character.hire_bans = {fam: until_day} (thief who fled, 4.7.3)
## Days are Clock.day. A job is active on `day` when start_day <= day and (end_day < 0 or day <= end_day).
##
## The base (H4) leaves the orders and step() as stubs, and the pure queries done (the rules they read are fixed in
## the contract); «plantilla» fills the stubs and may refine the queries without changing their shape.


# --- Orders (stubs until «plantilla») --------------------------------------------------------------------------------

## {"type": "hire", "actor", "building", "candidate"}.
static func order_hire(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "fire", "actor", "employee"}.
static func order_fire(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "promote", "actor", "employee", "accept": bool}.
static func order_promote(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "bonus", "actor", "employee"}.
static func order_bonus(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


# --- Step (stub until «plantilla») -----------------------------------------------------------------------------------

## Once per minute, after Buildings and before Routines (Sim.step). At dawn, in this order (contract): count the day
## just ended, leavers go, hires start, wages, daily loyalty, quitting and theft, promotion offers.
static func step(_sim: Sim) -> void:
	pass


# --- Queries (pure; done in the base) --------------------------------------------------------------------------------

## The building `chr` works at ("" if it has no job).
static func employer(st: WorldState, chr: String) -> String:
	var job: Variant = st.characters.get(chr, {}).get("job")
	return str((job as Dictionary).get("building", "")) if job is Dictionary else ""


## Whether `chr` has a job at `bld` (active or not yet / no longer).
static func works_at(st: WorldState, chr: String, bld: String) -> bool:
	return bld != "" and employer(st, chr) == bld


## Whether the job of `chr` is active today (started and not ended).
static func is_active(sim: Sim, chr: String) -> bool:
	var job: Variant = sim.state.characters.get(chr, {}).get("job")
	if not job is Dictionary:
		return false
	var today := Clock.day(int(sim.state.clock["minute"]))
	var end := int(job.get("end_day", -1))
	return int(job.get("start_day", 0)) <= today and (end < 0 or today <= end)


## Every character with a job at `bld`, sorted by id.
static func employees_of(st: WorldState, bld: String) -> Array:
	var out: Array = []
	for id: Variant in st.characters:
		if works_at(st, str(id), bld):
			out.append(str(id))
	out.sort()
	return out


## Employee places of the building (GDD 4.7.1: base_employees of its type, + Personal upgrades from H5).
static func slots(st: WorldState, bld: String) -> int:
	return int(st.buildings.get(bld, {}).get("employee_slots", 0))


static func free_slots(st: WorldState, bld: String) -> int:
	return maxi(0, slots(st, bld) - employees_of(st, bld).size())


## Gold per day of `chr` by its rank (0 without rank).
static func wage(sim: Sim, chr: String) -> int:
	return int(sim.catalog.rank(str(sim.state.characters.get(chr, {}).get("rank", ""))).get("wage", 0))


## Cycle speed multiplier of an employee by rank (GDD 4.4.1: duration / speed). 1.0 for anybody without a job.
static func speed(sim: Sim, chr: String) -> float:
	if employer(sim.state, chr) == "":
		return 1.0
	return float(sim.catalog.rank(str(sim.state.characters[chr].get("rank", ""))).get("speed", 1.0))


## Effective efficiency of an employee (GDD 4.7.2): rank × loyalty band (× emotion and equipment, later). 1.0 for
## anybody without a job.
static func efficiency(sim: Sim, chr: String) -> float:
	var job: Variant = sim.state.characters.get(chr, {}).get("job")
	if not job is Dictionary:
		return 1.0
	var base := float(sim.catalog.rank(str(sim.state.characters[chr].get("rank", ""))).get("efficiency", 1.0))
	return base * float(band(sim, int(job.get("loyalty", 0))).get("efficiency_mult", 1.0))


## The loyalty band of data/employees.json that holds `loyalty` ({} if none).
static func band(sim: Sim, loyalty: int) -> Dictionary:
	for b: Dictionary in sim.catalog.employees.get("bands", []):
		if loyalty >= int(b["min"]) and loyalty <= int(b["max"]):
			return b
	return {}


## Whether `chr` is a townsperson free to be hired: alive, with a trade rank, no job, and of a household family (an
## AI family without ai_profile: not the player's, not a rival's).
static func is_unemployed(sim: Sim, chr: String) -> bool:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty() or not bool(ch.get("alive", true)) or ch.get("job") is Dictionary:
		return false
	if str(ch.get("rank", "")) == "":
		return false
	var fam: Dictionary = sim.state.families.get(str(ch.get("family", "")), {})
	return str(fam.get("controlled_by", "")) == "ai" and str(fam.get("ai_profile", "")) == ""


## The candidates for `bld` as `actor` sees them (hiring panel, GDD 4.7.1), sorted by rank (best first) then id:
## [{character, name, female, rank, stats: {craft, charisma, constitution}, wage, status}]. status: "ok" or why not
## ("not_your_building", "no_slot", "not_enough_gold", "banned", "needs_upgrade"). Base version; «plantilla» owns it.
static func candidates(sim: Sim, actor: String, bld: String) -> Array:
	var st := sim.state
	if not st.buildings.has(bld) or not st.characters.has(actor):
		return []
	var fam := Money.family_of(st, bld)
	var today := Clock.day(int(st.clock["minute"]))
	var order: Array = sim.catalog.employees.get("rank_order", [])
	var rows: Array = []
	for id: Variant in st.characters:
		var c := str(id)
		if not is_unemployed(sim, c):
			continue
		var ch: Dictionary = st.characters[c]
		var rk := str(ch.get("rank", ""))
		var status := "ok"
		if not Buildings.owns(st, actor, bld):
			status = "not_your_building"
		elif free_slots(st, bld) <= 0:
			status = "no_slot"
		elif int((ch.get("hire_bans", {}) as Dictionary).get(fam, -1)) >= today:
			status = "banned"
		elif str(sim.catalog.rank(rk).get("requires_upgrade", "")) != "" \
				and not str(sim.catalog.rank(rk)["requires_upgrade"]) in (st.buildings[bld].get("upgrades", []) as Array):
			status = "needs_upgrade"
		elif not Money.can_pay(st, fam, wage(sim, c)):
			status = "not_enough_gold"
		var stats: Dictionary = ch.get("stats", {})
		rows.append({"character": c, "name": str(ch.get("name", "")), "female": bool(ch.get("female", false)),
			"rank": rk, "stats": {"craft": int(stats.get("craft", 0)), "charisma": int(stats.get("charisma", 0)),
			"constitution": int(stats.get("constitution", 0))}, "wage": wage(sim, c), "status": status,
			"_order": -order.find(rk)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["_order"]) != int(b["_order"]):
			return int(a["_order"]) < int(b["_order"])
		return str(a["character"]) < str(b["character"]))
	for r: Dictionary in rows:
		r.erase("_order")
	return rows


## The employees of `bld` for the employees panel (GDD 4.7): [{character, name, female, rank, role, loyalty, band,
## wage, days_worked, rank_days, unpaid_days, promotion_offered, active, start_day, end_day, routine, task}], by id.
## routine = Routines.state_of; task = WorkQueue.task_of ({} when idle or away). Base version; «plantilla» owns it.
static func employees(sim: Sim, bld: String) -> Array:
	var out: Array = []
	for c: String in employees_of(sim.state, bld):
		var ch: Dictionary = sim.state.characters[c]
		var job: Dictionary = ch["job"]
		out.append({"character": c, "name": str(ch.get("name", "")), "female": bool(ch.get("female", false)),
			"rank": str(ch.get("rank", "")), "role": str(job.get("role", "")), "loyalty": int(job.get("loyalty", 0)),
			"band": str(band(sim, int(job.get("loyalty", 0))).get("id", "")), "wage": wage(sim, c),
			"days_worked": int(job.get("days_worked", 0)), "rank_days": int(job.get("rank_days", 0)),
			"unpaid_days": int(job.get("unpaid_days", 0)), "promotion_offered": bool(job.get("promotion_offered", false)),
			"active": is_active(sim, c), "start_day": int(job.get("start_day", 0)), "end_day": int(job.get("end_day", -1)),
			"routine": Routines.state_of(sim, c), "task": WorkQueue.task_of(sim, c)})
	return out


## A new job (the shape of the contract) for `chr` at `bld`, hired on `day`. Used by hire and by the scenario tools.
## Does not check anything and does not move gold.
static func new_job(sim: Sim, bld: String, day: int, role: String = "") -> Dictionary:
	var emp := sim.catalog.employees
	return {"building": bld, "role": role if role != "" else str(emp.get("default_role", "any")),
		"loyalty": int(emp.get("loyalty", {}).get("start", 50)), "hired_day": day,
		"start_day": day + int(emp.get("hire", {}).get("start_after_days", 1)), "end_day": -1, "days_worked": 0,
		"rank_days": 0, "unpaid_days": 0, "promotion_offered": false}
