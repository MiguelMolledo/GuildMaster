extends "res://tests/test_case.gd"
const Pins = preload("res://tests/balance_pins.gd")
## Staff (GDD 4.7.1-4.7.3, docs/contratos/h4_empleados.md, zone «plantilla»): hire, fire, promote, bonus and the dawn
## step (day counted, leavers, starts, real wages, loyalty, promotion offers). Quitting, theft and save/load with
## pending hires: test_econ_staff_odds.gd.

var cat := Pins.classic(Catalog.load_from())  # pre-H5 figures: see tests/balance_pins.gd

const PLAYER := "chr_0001"
const FAM := "fam_0001"
const FORGE := "bld_0001"
const JOAN := "chr_0007"   # journeyman (town_e_start: unemployed; two_employees: anvil)
const AGNES := "chr_0008"  # apprentice


func _sim(id: String = "town_e_start") -> Sim:
	return Sim.new(NewGame.from_scenario(id, 1)["state"], cat)


func _today(sim: Sim) -> int:
	return Clock.day(int(sim.state.clock["minute"]))


## Steps until a step that begins a dawn (its events stay in sim.events).
func _to_dawn(sim: Sim) -> void:
	for i: int in Clock.MINUTES_PER_DAY * 2:
		sim.step()
		if Ledger.is_dawn(sim):
			return
	failures.append("no dawn in 2 days")


func _events(sim: Sim, type: String) -> Array:
	return sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


func _job(sim: Sim, c: String) -> Variant:
	return sim.state.characters[c].get("job")


func _wage_entries(sim: Sim, fam: String, ref: String) -> int:
	var n := 0
	for e: Dictionary in sim.state.ledger["entries"]:
		if str(e["family"]) == fam and str(e["category"]) == Money.WAGES and str(e["ref"]) == ref:
			n += int(e["amount"])
	return n


func _hire(sim: Sim, cand: String, bld: String = FORGE) -> Dictionary:
	return Orders.apply(sim, {"type": "hire", "actor": PLAYER, "building": bld, "candidate": cand})


# --- hire ------------------------------------------------------------------------------------------------------------

func test_hire_refusals() -> void:
	var sim := _sim()
	eq(_hire(sim, JOAN, "bld_0003")["reason"], "not_your_building", "the armory is not the player's")
	eq(_hire(sim, PLAYER)["reason"], "not_a_candidate", "the player is no candidate")
	eq(_hire(sim, "chr_0006")["reason"], "not_a_candidate", "the rival is no candidate")
	eq(Orders.apply(sim, {"type": "hire", "actor": "chr_9999", "building": FORGE, "candidate": JOAN})["reason"],
		"unknown_actor", "unknown actor")
	eq(_hire(sim, JOAN, "bld_9999")["reason"], "unknown_building", "unknown building")
	sim.state.characters[JOAN]["hire_bans"] = {FAM: _today(sim)}
	eq(_hire(sim, JOAN)["reason"], "banned", "banned until today included")
	sim.state.characters[JOAN]["hire_bans"] = {FAM: _today(sim) - 1, "fam_0002": 999}
	var gold := Money.gold(sim.state, FAM)
	sim.state.families[FAM]["gold"] = 2
	eq(_hire(sim, JOAN)["reason"], "not_enough_gold", "a journeyman needs 3 gold for one day")
	check(_hire(sim, AGNES)["ok"], "an apprentice needs 1")
	sim.state.families[FAM]["gold"] = gold
	eq(_hire(sim, JOAN)["reason"], "no_slot", "the forge has 1 place")
	eq(_hire(sim, AGNES)["reason"], "no_slot", "no slot even for the same one")


func test_hire_starts_next_dawn_and_pays_nothing_now() -> void:
	var sim := _sim()
	var gold := Money.gold(sim.state, FAM)
	var today := _today(sim)
	var r := _hire(sim, JOAN)
	check(r["ok"], "hires")
	eq(Money.gold(sim.state, FAM), gold, "nothing charged when hiring")
	var job: Dictionary = _job(sim, JOAN)
	eq([str(job["building"]), str(job["role"]), int(job["loyalty"]), int(job["hired_day"]), int(job["start_day"]),
		int(job["end_day"])], [FORGE, "any", 50, today, today + 1, -1], "the job of the contract")
	check(not Staff.is_active(sim, JOAN), "not active the day of the hire")
	eq(Staff.free_slots(sim.state, FORGE), 0, "the place is taken")
	eq(str(_events(sim, "employee_hired")[0]["employee"]), JOAN, "employee_hired")
	eq(Staff.candidates(sim, PLAYER, FORGE)[0]["status"], "no_slot", "the panel sees no slot")
	var home_fam := str(sim.state.characters[JOAN]["family"])
	var home_gold := Money.gold(sim.state, home_fam)
	_to_dawn(sim)
	eq(_today(sim), today + 1, "next day")
	check(Staff.is_active(sim, JOAN), "active from the dawn")
	eq(_events(sim, "employee_started").size(), 1, "employee_started")
	eq(_wage_entries(sim, FAM, "wage"), -3, "the journeyman's wage paid by the forge's family")
	eq(Money.gold(sim.state, home_fam), home_gold + 3, "and it goes to the employee's household")
	eq(int(_job(sim, JOAN)["loyalty"]), 51, "paid on time: +1")
	eq(int(_job(sim, JOAN)["days_worked"]), 0, "the day of the hire is not a day worked")


# --- wages -----------------------------------------------------------------------------------------------------------

func test_two_employees_paid_at_dawn() -> void:
	var sim := _sim("two_employees")
	var gold := Money.gold(sim.state, FAM)
	_to_dawn(sim)
	eq(_events(sim, "employee_started").size(), 2, "both start today")
	eq(_events(sim, "wage_paid").size(), 2, "both paid")
	eq(_wage_entries(sim, FAM, "wage"), -4, "3 + 1 gold")
	check(Money.gold(sim.state, FAM) <= gold - 4, "out of the forge's purse (and upkeep after)")
	for c: String in [JOAN, AGNES]:
		eq(int(_job(sim, c)["loyalty"]), 51, "%s loyalty +1" % c)
		eq(int(_job(sim, c)["unpaid_days"]), 0, "%s paid" % c)
	var paid_at := -1
	var upkeep_at := -1
	for i: int in sim.events.size():
		var e: Dictionary = sim.events[i]
		if str(e["type"]) == "gold_changed" and str(e["category"]) == Money.WAGES and paid_at < 0:
			paid_at = i
		if str(e["type"]) == "gold_changed" and str(e["category"]) == Money.UPKEEP and upkeep_at < 0:
			upkeep_at = i
	check(paid_at >= 0 and (upkeep_at < 0 or paid_at < upkeep_at), "wages before upkeep")


func test_unpaid_wage_lowers_loyalty_after_grace() -> void:
	var sim := _sim("two_employees")
	sim.state.families[FAM]["gold"] = 0
	var rep := int(sim.state.families[FAM]["reputation"])
	_to_dawn(sim)
	eq(_events(sim, "wage_unpaid").size(), 2, "both unpaid")
	eq(int(_job(sim, JOAN)["unpaid_days"]), 1, "1 day unpaid")
	eq(int(_job(sim, JOAN)["loyalty"]), 50, "grace day: loyalty kept")
	var notices := Notices.list(sim, FAM).filter(func(n: Dictionary) -> bool:
		return str(n["key"]) == "notice.wage_unpaid")
	eq(notices.size(), 2, "a notice per employee")
	check(str(notices[0]["target"]) in [JOAN, AGNES], "the notice points at the employee")
	eq(int(sim.state.families[FAM]["reputation"]) - _h9_rep(sim), rep - 2, "only the rumours (2 unhappy employees, -1 each)")
	_to_dawn(sim)
	eq(int(_job(sim, JOAN)["unpaid_days"]), 2, "2 days unpaid")
	eq(int(_job(sim, JOAN)["loyalty"]), 45, "after the grace: -5")
	eq(int(_job(sim, AGNES)["loyalty"]), 45, "both")
	eq(int(sim.state.families[FAM]["reputation"]) - _h9_rep(sim), rep - 2 - 2 * 2 - 2, "-2 per unpaid employee, plus rumours")
	var lc := _events(sim, "loyalty_changed").filter(func(e: Dictionary) -> bool:
		return str(e["reason"]) == "wage_unpaid")
	eq(lc.size(), 2, "loyalty_changed wage_unpaid")
	sim.state.families[FAM]["gold"] = 100
	_to_dawn(sim)
	eq(int(_job(sim, JOAN)["unpaid_days"]), 0, "paid again")
	eq(int(_job(sim, JOAN)["loyalty"]), 46, "+1")


# --- promotions ------------------------------------------------------------------------------------------------------

func test_apprentice_promotion_offered_at_dawn() -> void:
	var sim := _sim("apprentice_promotion")
	eq(Orders.apply(sim, {"type": "promote", "actor": PLAYER, "employee": AGNES, "accept": true})["reason"],
		"no_promotion", "nothing to answer yet")
	_to_dawn(sim)
	var job: Dictionary = _job(sim, AGNES)
	eq(int(job["rank_days"]), 8, "day 8 counted")
	eq(int(job["days_worked"]), 8, "8 days worked")
	check(bool(job["promotion_offered"]), "promotion offered")
	var ev := _events(sim, "promotion_offered")
	eq(ev.size(), 1, "promotion_offered event")
	eq(str(ev[0]["rank"]), "journeyman", "to journeyman")
	var n := Notices.list(sim, FAM).filter(func(x: Dictionary) -> bool:
		return str(x["key"]) == "notice.promotion_offered")
	eq(n.size(), 1, "a promotion notice")
	eq(str(n[0]["target"]), AGNES, "pointing at Agnès")
	_to_dawn(sim)
	eq(_events(sim, "promotion_offered").size(), 0, "not offered twice while pending")


func test_promotion_accept() -> void:
	var sim := _sim("apprentice_promotion")
	_to_dawn(sim)
	eq(int(_job(sim, AGNES)["loyalty"]), 61, "60 + wage")
	eq(Orders.apply(sim, {"type": "promote", "actor": "chr_0006", "employee": AGNES, "accept": true})["reason"],
		"not_your_employee", "the rival cannot answer")
	check(Orders.apply(sim, {"type": "promote", "actor": PLAYER, "employee": AGNES, "accept": true})["ok"], "accepts")
	var job: Dictionary = _job(sim, AGNES)
	eq(str(sim.state.characters[AGNES]["rank"]), "journeyman", "journeyman now")
	eq([int(job["rank_days"]), int(job["loyalty"]), bool(job["promotion_offered"])], [0, 76, false], "+15, rank days 0")
	eq(_events(sim, "employee_promoted").size(), 1, "employee_promoted")
	eq(Staff.wage(sim, AGNES), 3, "journeyman wage")
	var before := _wage_entries(sim, FAM, "wage")
	_to_dawn(sim)
	eq(_wage_entries(sim, FAM, "wage") - before, -3, "the new wage from the next dawn")
	eq(Orders.apply(sim, {"type": "promote", "actor": PLAYER, "employee": AGNES, "accept": true})["reason"],
		"no_promotion", "no second answer")


func test_promotion_refuse() -> void:
	var sim := _sim("apprentice_promotion")
	_to_dawn(sim)
	check(Orders.apply(sim, {"type": "promote", "actor": PLAYER, "employee": AGNES, "accept": false})["ok"], "refuses")
	var job: Dictionary = _job(sim, AGNES)
	eq(str(sim.state.characters[AGNES]["rank"]), "apprentice", "still apprentice")
	eq([int(job["rank_days"]), int(job["loyalty"]), bool(job["promotion_offered"])], [8, 51, false], "-10")
	eq(_events(sim, "promotion_refused").size(), 1, "promotion_refused")
	_to_dawn(sim)
	check(bool(_job(sim, AGNES)["promotion_offered"]), "offered again the next dawn while it still qualifies")


func test_no_offer_with_low_loyalty() -> void:
	var sim := _sim("apprentice_promotion")
	sim.state.characters[AGNES]["job"]["loyalty"] = 49
	_to_dawn(sim)
	eq(int(_job(sim, AGNES)["loyalty"]), 50, "49 + wage = 50: not > 50")
	check(not bool(_job(sim, AGNES)["promotion_offered"]), "no offer")


# --- fire ------------------------------------------------------------------------------------------------------------

func test_fire_leaves_at_end_of_day() -> void:
	var sim := _sim("two_employees")
	_to_dawn(sim)
	var today := _today(sim)
	var rep := int(sim.state.families[FAM]["reputation"])
	eq(Orders.apply(sim, {"type": "fire", "actor": "chr_0006", "employee": JOAN})["reason"], "not_your_employee",
		"the rival cannot fire him")
	eq(Orders.apply(sim, {"type": "fire", "actor": PLAYER, "employee": "chr_0009"})["reason"], "not_your_employee",
		"an unemployed townsperson")
	check(Orders.apply(sim, {"type": "fire", "actor": PLAYER, "employee": JOAN})["ok"], "fires")
	eq(Orders.apply(sim, {"type": "fire", "actor": PLAYER, "employee": JOAN})["reason"], "already_leaving", "once")
	eq(int(_job(sim, JOAN)["end_day"]), today, "end_day today")
	check(Staff.is_active(sim, JOAN), "still works today")
	eq(int(sim.state.families[FAM]["reputation"]), rep, "loyalty 51: no reputation")
	eq(_events(sim, "employee_fired").size(), 1, "employee_fired")
	var paid := _wage_entries(sim, FAM, "wage")
	_to_dawn(sim)
	check(_job(sim, JOAN) == null, "gone at the next dawn")
	var left := _events(sim, "employee_left")
	eq(left.size(), 1, "employee_left")
	eq(str(left[0]["reason"]), "fired", "fired")
	eq(_wage_entries(sim, FAM, "wage") - paid, -1, "only Agnès is paid")
	eq(int(_job(sim, AGNES)["days_worked"]), 1, "Agnès goes on (day 1 counted)")
	eq(str(sim.state.characters[JOAN]["rank"]), "journeyman", "the rank stays with the person")
	check(Staff.is_unemployed(sim, JOAN), "a candidate again")


func test_fire_loyal_costs_reputation() -> void:
	var sim := _sim("two_employees")
	_to_dawn(sim)
	sim.state.characters[JOAN]["job"]["loyalty"] = 71
	var rep := int(sim.state.families[FAM]["reputation"])
	check(Orders.apply(sim, {"type": "fire", "actor": PLAYER, "employee": JOAN})["ok"], "fires")
	eq(int(sim.state.families[FAM]["reputation"]), rep - 2, "loyalty > 70: reputation -2")


func test_fire_before_starting_goes_now() -> void:
	var sim := _sim()
	check(_hire(sim, AGNES)["ok"], "hires")
	check(Orders.apply(sim, {"type": "fire", "actor": PLAYER, "employee": AGNES})["ok"], "fires")
	check(_job(sim, AGNES) == null, "gone at once")
	eq(Staff.free_slots(sim.state, FORGE), 1, "the place is free")
	eq(str(_events(sim, "employee_left")[0]["reason"]), "fired", "employee_left")


func test_leaver_inside_goes_out() -> void:
	var sim := _sim("two_employees")
	var ch: Dictionary = sim.state.characters[JOAN]
	ch["job"]["end_day"] = 0
	ch["location"] = FORGE
	ch["position"] = (sim.state.buildings[FORGE]["door"] as Array).duplicate()
	_to_dawn(sim)
	check(ch.get("job") == null, "left")
	check(str(ch["location"]) != FORGE, "out of the forge")


# --- bonus -----------------------------------------------------------------------------------------------------------

func test_bonus() -> void:
	var sim := _sim("two_employees")
	var home_fam := str(sim.state.characters[AGNES]["family"])
	var gold := Money.gold(sim.state, FAM)
	var home_gold := Money.gold(sim.state, home_fam)
	check(Orders.apply(sim, {"type": "bonus", "actor": PLAYER, "employee": AGNES})["ok"], "bonus")
	eq(Money.gold(sim.state, FAM), gold - 5, "5 gold out")
	eq(Money.gold(sim.state, home_fam), home_gold + 5, "5 gold to the household")
	eq(_wage_entries(sim, FAM, "bonus"), -5, "ledger: wages, ref bonus")
	eq(int(_job(sim, AGNES)["loyalty"]), 55, "+5")
	eq(_events(sim, "employee_bonus").size(), 1, "employee_bonus")
	sim.state.families[FAM]["gold"] = 4
	eq(Orders.apply(sim, {"type": "bonus", "actor": PLAYER, "employee": AGNES})["reason"], "not_enough_gold", "4 < 5")
	eq(Orders.apply(sim, {"type": "bonus", "actor": PLAYER, "employee": "chr_0009"})["reason"], "not_your_employee",
		"not an employee")


func test_loyalty_clamped() -> void:
	var sim := _sim("two_employees")
	sim.state.characters[AGNES]["job"]["loyalty"] = 98
	check(Orders.apply(sim, {"type": "bonus", "actor": PLAYER, "employee": AGNES})["ok"], "bonus")
	eq(int(_job(sim, AGNES)["loyalty"]), 100, "at most 100")


func test_damaged_building_lowers_loyalty() -> void:
	var sim := _sim("two_employees")
	sim.state.buildings[FORGE]["state"] = "damaged"
	_to_dawn(sim)
	eq(int(_job(sim, JOAN)["loyalty"]), 49, "50 + 1 (paid) - 2 (damaged)")


# --- conservation ----------------------------------------------------------------------------------------------------

func test_ledger_adds_up_with_wages() -> void:
	var sim := _sim("two_employees")
	var gold0 := {}
	for f: String in sim.state.families:
		gold0[f] = Money.gold(sim.state, f) - Ledger.total(sim.state, f)
	check(Orders.apply(sim, {"type": "bonus", "actor": PLAYER, "employee": JOAN})["ok"], "bonus")
	_to_dawn(sim)
	_to_dawn(sim)
	var total_before := 0
	var total_after := 0
	for f: String in sim.state.families:
		eq(Money.gold(sim.state, f) - Ledger.total(sim.state, f), int(gold0.get(f, 0)), "%s book adds up" % f)  # vida: families made later start at 0
	for e: Dictionary in sim.state.ledger["entries"]:
		if str(e["category"]) == Money.WAGES:
			total_after += int(e["amount"])
	eq(total_after, total_before, "wages and bonus move gold between families: they add up to 0")


## H9: reputation from the sources H9 added (passive, trade, wages paid), apart from what this test measures.
func _h9_rep(sim: Sim) -> int:
	var n := 0
	for e: Dictionary in sim.state.families[FAM].get("reputation_log", []):
		if str(e["reason"]) in ["passive", "fair_trade", "quality_trade", "wages_paid"]:
			n += int(e["amount"])
	return n
