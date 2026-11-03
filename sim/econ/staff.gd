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


# --- Orders ---------------------------------------------------------------------------------------------------------

## {"type": "hire", "actor", "building", "candidate"}: a free place at a building of the actor's family, an unemployed
## townsperson not banned by that family, a rank allowed by the building's upgrades, and gold for 1 day of wage. The
## job starts at the next dawn (start_day = today + hire.start_after_days). Nothing is charged when hiring.
static func order_hire(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var cand := str(o.get("candidate", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	if not st.buildings.has(bld):
		return Orders.fail("unknown_building")
	if not Buildings.owns(st, actor, bld):
		return Orders.fail("not_your_building")
	if free_slots(st, bld) <= 0:
		return Orders.fail("no_slot")
	if not is_unemployed(sim, cand):
		return Orders.fail("not_a_candidate")
	var fam := Money.family_of(st, bld)
	var today := _today(sim)
	var ch: Dictionary = st.characters[cand]
	if int((ch.get("hire_bans", {}) as Dictionary).get(fam, -1)) >= today:
		return Orders.fail("banned")
	if not _rank_allowed(sim, str(ch.get("rank", "")), bld):
		return Orders.fail("needs_upgrade")
	var w := wage(sim, cand)
	if not Money.can_pay(st, fam, w):
		return Orders.fail("not_enough_gold")
	var job := new_job(sim, bld, today)
	ch["job"] = job
	sim.events.append({"type": "employee_hired", "actor": actor, "family": fam, "building": bld, "employee": cand,
		"rank": str(ch.get("rank", "")), "wage": w, "start_day": int(job["start_day"])})
	if OS.is_debug_build():
		print("[Staff] %s contrata a %s (%s, salario=%d) en %s: empieza el día %d" % [actor, cand, ch.get("rank", ""),
			w, bld, int(job["start_day"])])
	return Orders.ok()


## {"type": "fire", "actor", "employee"}: an employee of a building of the actor's family. It leaves at the end of the
## day (end_day = today; today's wage was already paid at dawn); if its loyalty was > fire.reputation_loyalty_over,
## the family loses fire.reputation. A hire that has not started yet goes at once.
static func order_fire(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var emp := str(o.get("employee", ""))
	var why := _employee_reason(sim, actor, emp)
	if why != "":
		return Orders.fail(why)
	var job: Dictionary = st.characters[emp]["job"]
	if int(job.get("end_day", -1)) >= 0:
		return Orders.fail("already_leaving")
	var bld := str(job["building"])
	var fam := Money.family_of(st, bld)
	var today := _today(sim)
	var cfg: Dictionary = sim.catalog.employees.get("fire", {})
	var loyalty := int(job.get("loyalty", 0))
	job["end_day"] = today
	sim.events.append({"type": "employee_fired", "actor": actor, "family": fam, "building": bld, "employee": emp,
		"end_day": today})
	if loyalty > int(cfg.get("reputation_loyalty_over", 70)):
		_reputation(sim, fam, int(cfg.get("reputation", -2)), "fired_loyal")
	var name := str(st.characters[emp].get("name", ""))
	if int(job.get("start_day", 0)) > today:
		if OS.is_debug_build():
			print("[Staff] %s despide a %s antes de empezar: se va ya" % [actor, emp])
		_leave(sim, emp, "fired")
		Notices.add(sim, fam, Notices.INFO, "notice.employee_fired_now", {"name": name, "building": bld}, bld)
		return Orders.ok()
	if OS.is_debug_build():
		print("[Staff] %s despide a %s de %s: se va al final del día %d (lealtad=%d)" % [actor, emp, bld, today,
			loyalty])
	Notices.add(sim, fam, Notices.INFO, "notice.employee_fired", {"name": name, "building": bld}, emp)
	return Orders.ok()


## {"type": "promote", "actor", "employee", "accept": bool}: answers a promotion offer. Accept: rank = next,
## rank_days = 0, loyalty + promotion_accepted (the new wage is paid from the next dawn). Refuse: loyalty +
## promotion_refused. Either way the offer is gone.
static func order_promote(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var emp := str(o.get("employee", ""))
	var why := _employee_reason(sim, actor, emp)
	if why != "":
		return Orders.fail(why)
	var ch: Dictionary = st.characters[emp]
	var job: Dictionary = ch["job"]
	if not bool(job.get("promotion_offered", false)):
		return Orders.fail("no_promotion")
	var bld := str(job["building"])
	var fam := Money.family_of(st, bld)
	var lcfg: Dictionary = sim.catalog.employees.get("loyalty", {})
	var accept := bool(o.get("accept", false))
	var next := str(sim.catalog.rank(str(ch.get("rank", ""))).get("next", ""))
	if accept:
		if next == "":
			return Orders.fail("no_promotion")
		if not _rank_allowed(sim, next, bld):
			return Orders.fail("needs_upgrade")
		job["promotion_offered"] = false
		ch["rank"] = next
		job["rank_days"] = 0
		_add_loyalty(sim, emp, int(lcfg.get("promotion_accepted", 15)), "promotion_accepted")
		sim.events.append({"type": "employee_promoted", "actor": actor, "family": fam, "building": bld,
			"employee": emp, "rank": next})
	else:
		job["promotion_offered"] = false
		_add_loyalty(sim, emp, int(lcfg.get("promotion_refused", -10)), "promotion_refused")
		sim.events.append({"type": "promotion_refused", "actor": actor, "family": fam, "building": bld,
			"employee": emp})
	if OS.is_debug_build():
		print("[Staff] %s %s el ascenso de %s (rango=%s, lealtad=%d)" % [actor, "acepta" if accept else "rechaza",
			emp, ch.get("rank", ""), int(job["loyalty"])])
	return Orders.ok()


## {"type": "bonus", "actor", "employee"}: pays bonus_gold from the employer family to the employee's household
## (Money, category wages, ref "bonus") and loyalty + loyalty.bonus.
static func order_bonus(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var emp := str(o.get("employee", ""))
	var why := _employee_reason(sim, actor, emp)
	if why != "":
		return Orders.fail(why)
	var job: Dictionary = st.characters[emp]["job"]
	var bld := str(job["building"])
	var fam := Money.family_of(st, bld)
	var amount := int(sim.catalog.employees.get("bonus_gold", 5))
	if not Money.can_pay(st, fam, amount):
		return Orders.fail("not_enough_gold")
	_transfer(sim, fam, emp, amount, "bonus", bld)
	_add_loyalty(sim, emp, int(sim.catalog.employees.get("loyalty", {}).get("bonus", 5)), "bonus")
	sim.events.append({"type": "employee_bonus", "actor": actor, "family": fam, "employee": emp, "amount": amount})
	if OS.is_debug_build():
		print("[Staff] %s da un bonus de %d a %s (lealtad=%d)" % [actor, amount, emp, int(job["loyalty"])])
	return Orders.ok()


# --- Step ------------------------------------------------------------------------------------------------------------

## Once per minute, after Buildings and before Routines (Sim.step). Only at dawn, in the order of the contract: count
## the day just ended, leavers go, hires start, wages, daily loyalty (damage, rumours), quitting and theft, promotion
## offers. Every list in id order (String).
static func step(sim: Sim) -> void:
	if not Ledger.is_dawn(sim):
		return
	var st := sim.state
	var staff: Array = []
	for id: Variant in st.characters:
		if st.characters[id].get("job") is Dictionary:
			staff.append(str(id))
	if staff.is_empty():
		return
	staff.sort()
	var today := _today(sim)
	var emp_cfg := sim.catalog.employees
	var lcfg: Dictionary = emp_cfg.get("loyalty", {})
	if OS.is_debug_build():
		print("[Staff] amanecer del día %d: %d con empleo" % [today, staff.size()])
	# 1. The day that just ended.
	for c: String in staff:
		var job: Dictionary = st.characters[c]["job"]
		if _active_on(job, today - 1):
			job["days_worked"] = int(job.get("days_worked", 0)) + 1
			job["rank_days"] = int(job.get("rank_days", 0)) + 1
	# 2. Leavers (fired: their last day was before today).
	for c: String in staff:
		var end := int(st.characters[c]["job"].get("end_day", -1))
		if end >= 0 and end < today:
			_leave(sim, c, "fired")
	# 3. Hires that start today.
	for c: String in staff:
		var job: Variant = st.characters[c].get("job")
		if job is Dictionary and int(job.get("start_day", 0)) == today:
			var bld := str(job["building"])
			sim.events.append({"type": "employee_started", "family": Money.family_of(st, bld), "building": bld,
				"employee": c})
			if OS.is_debug_build():
				print("[Staff] %s empieza hoy en %s" % [c, bld])
	# 4. Today's wages.
	var wcfg: Dictionary = emp_cfg.get("wages", {})
	for c: String in _active_today(sim, staff):
		_pay_wage(sim, c, wcfg, lcfg)
	# 5. Daily loyalty: damaged building, rumours of the bands.
	for c: String in _active_today(sim, staff):
		var job: Dictionary = st.characters[c]["job"]
		var bld := str(job["building"])
		if str(st.buildings.get(bld, {}).get("state", "")) == "damaged":
			_add_loyalty(sim, c, int(lcfg.get("building_damaged", -2)), "building_damaged")
		var rumor := int(band(sim, int(job["loyalty"])).get("rumor_reputation", 0))
		if rumor != 0:
			_reputation(sim, Money.family_of(st, bld), rumor, "employee_rumor")
	# 6. Quitting and theft: one roll per employee and day, only in a band that has the chance.
	for c: String in _active_today(sim, staff):
		_roll_quit_or_theft(sim, c)
	# 7. Promotion offers.
	for c: String in _active_today(sim, staff):
		_maybe_offer_promotion(sim, c)


# --- Helpers ---------------------------------------------------------------------------------------------------------

static func _today(sim: Sim) -> int:
	return Clock.day(int(sim.state.clock["minute"]))


static func _active_on(job: Dictionary, day: int) -> bool:
	var end := int(job.get("end_day", -1))
	return int(job.get("start_day", 0)) <= day and (end < 0 or day <= end)


## Those of `ids` that still have a job and are active today (in the same order).
static func _active_today(sim: Sim, ids: Array) -> Array:
	var out: Array = []
	for c: String in ids:
		if is_active(sim, c):
			out.append(c)
	return out


## "" when `emp` has a job at a building of the actor's family, or why not.
static func _employee_reason(sim: Sim, actor: String, emp: String) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	var b := employer(st, emp)
	if b == "" or not Buildings.owns(st, actor, b):
		return "not_your_employee"
	return ""


## Whether a building can take someone of `rank`: H5, the building's upgrades allow it (Upgrades.rank_ok: a rank that
## an upgrade of its tree allows, e.g. master with "Taller de maestro", needs that upgrade); the H4 requires_upgrade
## of the rank (data/employees.json, empty) still applies if filled.
static func _rank_allowed(sim: Sim, rank: String, bld: String) -> bool:
	var need := str(sim.catalog.rank(rank).get("requires_upgrade", ""))
	if need != "" and not need in (sim.state.buildings[bld].get("upgrades", []) as Array):
		return false
	return Upgrades.rank_ok(sim, bld, rank)


## Gold from the employer family to the employee's household, both through Money (category wages): it stays in the
## economy (GDD 4.19). The caller checked the employer can pay.
static func _transfer(sim: Sim, fam: String, emp: String, amount: int, ref: String, bld: String) -> void:
	Money.change(sim, fam, -amount, Money.WAGES, ref, bld, emp)
	var home_fam := Money.family_of(sim.state, emp)
	if home_fam != "" and home_fam != fam:
		Money.change(sim, home_fam, amount, Money.WAGES, ref, bld, emp)


static func _pay_wage(sim: Sim, c: String, wcfg: Dictionary, lcfg: Dictionary) -> void:
	var st := sim.state
	var job: Dictionary = st.characters[c]["job"]
	var bld := str(job["building"])
	var fam := Money.family_of(st, bld)
	var w := wage(sim, c)
	if Money.can_pay(st, fam, w):
		_transfer(sim, fam, c, w, "wage", bld)
		job["unpaid_days"] = 0
		sim.events.append({"type": "wage_paid", "family": fam, "building": bld, "employee": c, "amount": w})
		_add_loyalty(sim, c, int(lcfg.get("wage_paid", 1)), "wage_paid")
		return
	var days := int(job.get("unpaid_days", 0)) + 1
	job["unpaid_days"] = days
	sim.events.append({"type": "wage_unpaid", "family": fam, "building": bld, "employee": c, "days": days})
	var grace := int(wcfg.get("grace_days", 1))
	Notices.add(sim, fam, Notices.WARNING, "notice.wage_unpaid", {"name": str(st.characters[c].get("name", "")),
		"building": bld, "amount": w, "days": days}, c)
	if OS.is_debug_build():
		print("[Staff] %s no puede pagar a %s (%d de oro): %d días sin cobrar (gracia=%d)" % [fam, c, w, days, grace])
	if days > grace:
		_add_loyalty(sim, c, int(lcfg.get("wage_unpaid", -5)), "wage_unpaid")
		_reputation(sim, fam, int(wcfg.get("unpaid_reputation", -2)), "wage_unpaid")


static func _roll_quit_or_theft(sim: Sim, c: String) -> void:
	var st := sim.state
	var job: Dictionary = st.characters[c]["job"]
	var bld := str(job["building"])
	var b := band(sim, int(job["loyalty"]))
	var quit := float(b.get("quit_chance", 0.0))
	var theft := float(b.get("theft_chance", 0.0))
	var tcfg: Dictionary = sim.catalog.employees.get("theft", {})
	if theft > 0.0 and _has_security(sim, bld):
		theft /= maxf(1.0, float(tcfg.get("security_divisor", 2)))
	if quit > 0.0:
		var r := st.rng.randf()
		if OS.is_debug_build():
			print("[Staff] %s tirada de abandono %.3f < %.3f ?" % [c, r, quit])
		if r < quit:
			var fam := Money.family_of(st, bld)
			Notices.add(sim, fam, Notices.URGENT, "notice.employee_quit",
				{"name": str(st.characters[c].get("name", "")), "building": bld}, bld)
			_leave(sim, c, "quit")
	elif theft > 0.0:
		var r := st.rng.randf()
		if OS.is_debug_build():
			print("[Staff] %s tirada de robo %.3f < %.3f ?" % [c, r, theft])
		if r < theft:
			_steal(sim, c, tcfg)


## Takes 1-3 units (state.rng) of the most valuable stack of the building's storage (market sell price; ties by item
## id, then quality), and the thief flees: the job ends, banned by that family for theft.no_rehire_days.
static func _steal(sim: Sim, c: String, tcfg: Dictionary) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[c]
	var bld := str(ch["job"]["building"])
	var fam := Money.family_of(st, bld)
	var units: Array = tcfg.get("units", [1, 3])
	var want := st.rng.randi_range(int(units[0]), int(units[1]))
	var inv: Dictionary = st.buildings[bld].get("inventory", {})
	var best: Dictionary = {}
	var best_price := -1
	for s: Dictionary in inv.get("stacks", []):
		if int(s["qty"]) <= 0:
			continue
		var p := Market.price(sim, str(s["item"]), int(s["quality"]), "sell")
		var better := p > best_price
		if p == best_price and not best.is_empty():
			var a := str(s["item"])
			var bi := str(best["item"])
			better = a < bi or (a == bi and int(s["quality"]) < int(best["quality"]))
		if better:
			best = s
			best_price = p
	var item := ""
	var quality := 0
	var qty := 0
	if not best.is_empty():
		item = str(best["item"])
		quality = int(best["quality"])
		qty = mini(want, Inventory.count(inv, item, quality))
		Inventory.remove(inv, item, quality, qty)
	var value := best_price * qty if qty > 0 else 0
	sim.events.append({"type": "employee_stole", "family": fam, "building": bld, "employee": c, "item": item,
		"quality": quality, "qty": qty, "value": value})
	Notices.add(sim, fam, Notices.URGENT, "notice.employee_stole", {"name": str(ch.get("name", "")), "building": bld,
		"item": item, "qty": qty, "value": value}, bld)
	var until := _today(sim) + int(tcfg.get("no_rehire_days", 8))
	var bans: Dictionary = ch.get("hire_bans", {})
	bans[fam] = until
	ch["hire_bans"] = bans
	if OS.is_debug_build():
		print("[Staff] %s roba %d × %s (calidad %d, valor %d) de %s y huye; vetado por %s hasta el día %d" % [c, qty,
			item, quality, value, bld, fam, until])
	_leave(sim, c, "theft")


## Whether the building has Security (GDD 4.7.3: the theft chance / security_divisor): H5, any finished upgrade with
## protection > 0 (Upgrades.amount; its percentage is for sabotage and fire, later) [provisional]. The H4 list
## theft.security_upgrades of data/employees.json (empty) still counts if filled.
## Read for the view (staff panel: «Security divides it by 2»): whether the building has Security.
static func has_security(sim: Sim, bld: String) -> bool:
	return _has_security(sim, bld)


static func _has_security(sim: Sim, bld: String) -> bool:
	if Upgrades.amount(sim, bld, "protection") > 0.0:
		return true
	var ups: Array = sim.state.buildings.get(bld, {}).get("upgrades", [])
	for u: Variant in sim.catalog.employees.get("theft", {}).get("security_upgrades", []):
		if u in ups:
			return true
	return false


static func _maybe_offer_promotion(sim: Sim, c: String) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[c]
	var job: Dictionary = ch["job"]
	if bool(job.get("promotion_offered", false)) or int(job.get("end_day", -1)) >= 0:
		return
	var rk := sim.catalog.rank(str(ch.get("rank", "")))
	var next := str(rk.get("next", ""))
	if next == "":
		return
	if int(job.get("rank_days", 0)) < int(rk.get("promote_after_days", 0)) \
			or int(job.get("loyalty", 0)) < int(rk.get("promote_min_loyalty", 0)):
		return
	var bld := str(job["building"])
	if not _rank_allowed(sim, next, bld):
		return
	job["promotion_offered"] = true
	var fam := Money.family_of(st, bld)
	sim.events.append({"type": "promotion_offered", "family": fam, "building": bld, "employee": c, "rank": next})
	Notices.add(sim, fam, Notices.INFO, "notice.promotion_offered", {"name": str(ch.get("name", "")),
		"building": bld, "rank": next}, c)
	if OS.is_debug_build():
		print("[Staff] %s puede ascender a %s (días de rango=%d, lealtad=%d)" % [c, next, int(job["rank_days"]),
			int(job["loyalty"])])


## The job ends (fired, quit, theft): job = null, out of the building if inside (Sim.give exit_building, which frees
## the station and interrupts the cycle), and back home. Emits employee_left.
static func _leave(sim: Sim, c: String, reason: String) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[c]
	var bld := str(ch["job"]["building"])
	var fam := Money.family_of(st, bld)
	ch["job"] = null
	OrderQueue.clear_for(sim, c)
	if str(ch.get("location", "")) == bld:
		sim.give({"type": "exit_building", "actor": c})
	var home := str(ch.get("home", ""))
	if home != "" and str(ch.get("location", "")) != home:
		sim.give({"type": "enter_building", "actor": c, "building": home})
	sim.events.append({"type": "employee_left", "family": fam, "building": bld, "employee": c, "reason": reason})
	if OS.is_debug_build():
		print("[Staff] %s deja %s (%s)" % [c, bld, reason])


static func _add_loyalty(sim: Sim, c: String, amount: int, reason: String) -> void:
	var job: Dictionary = sim.state.characters[c]["job"]
	var lcfg: Dictionary = sim.catalog.employees.get("loyalty", {})
	var before := int(job.get("loyalty", 0))
	var now := clampi(before + amount, int(lcfg.get("min", 0)), int(lcfg.get("max", 100)))
	job["loyalty"] = now
	if now == before:
		return
	sim.events.append({"type": "loyalty_changed", "employee": c, "building": str(job["building"]),
		"amount": now - before, "loyalty": now, "reason": reason})
	if OS.is_debug_build():
		print("[Staff] %s lealtad %+d (%s) -> %d" % [c, now - before, reason, now])


static func _reputation(sim: Sim, fam: String, amount: int, reason: String) -> void:
	Reputation.change(sim, fam, amount, reason)  # H9: the only way (class of the reason, log, event)


# --- Queries (pure; done in the base) --------------------------------------------------------------------------------

## The building `chr` works at ("" if it has no job).
static func employer(st: WorldState, chr: String) -> String:
	var job: Variant = st.characters.get(chr, {}).get("job")
	return str((job as Dictionary).get("building", "")) if job is Dictionary else ""


## Whether `chr` has a job at `bld` (active or not yet / no longer).
static func works_at(st: WorldState, chr: String, bld: String) -> bool:
	return bld != "" and employer(st, chr) == bld


## Whether the job of `chr` is active today (started, not ended and, H7, not absent: job.absent_until, the sick
## employee microevent).
static func is_active(sim: Sim, chr: String) -> bool:
	var job: Variant = sim.state.characters.get(chr, {}).get("job")
	if not job is Dictionary:
		return false
	var today := Clock.day(int(sim.state.clock["minute"]))
	var end := int(job.get("end_day", -1))
	if int(job.get("absent_until", -1)) >= today:
		return false
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


## Effective efficiency of an employee (GDD 4.7.2): rank × loyalty band × H7 its emotions towards the employer family
## (grateful +10 %, angry −20 %, GDD 4.11.5) (× equipment, later). 1.0 for anybody without a job.
static func efficiency(sim: Sim, chr: String) -> float:
	var job: Variant = sim.state.characters.get(chr, {}).get("job")
	if not job is Dictionary:
		return 1.0
	var base := float(sim.catalog.rank(str(sim.state.characters[chr].get("rank", ""))).get("efficiency", 1.0))
	var fam := str(sim.state.buildings.get(str(job.get("building", "")), {}).get("owner", ""))
	return base * float(band(sim, int(job.get("loyalty", 0))).get("efficiency_mult", 1.0)) \
		* Emotions.employee_mult(sim, chr, fam)


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


## The candidates for `bld` as `actor` sees them (hiring panel, GDD 4.7.1): first the ones that can be hired (status
## "ok"), then the rest; within each group by rank (best first) then id:
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
		elif not _rank_allowed(sim, rk, bld):
			status = "needs_upgrade"
		elif not Money.can_pay(st, fam, wage(sim, c)):
			status = "not_enough_gold"
		var stats: Dictionary = ch.get("stats", {})
		rows.append({"character": c, "name": str(ch.get("name", "")), "female": bool(ch.get("female", false)),
			"rank": rk, "stats": {"craft": int(stats.get("craft", 0)), "charisma": int(stats.get("charisma", 0)),
			"constitution": int(stats.get("constitution", 0))}, "wage": wage(sim, c), "status": status,
			"_order": -order.find(rk)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_ok := str(a["status"]) == "ok"
		if a_ok != (str(b["status"]) == "ok"):
			return a_ok   # H5 polish: the ones that can be hired first
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
