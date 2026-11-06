extends "res://tests/test_case.gd"
## H12.2 · the physician (docs/gdd/04d_otras_clases.md 4.22.5.1, 4.22.3.2; sim/town/services.gd and the service
## recipes of sim/econ/production.gd): the scholar's start, the patients that come, wait and leave, the consultation
## (one bandage, the price from outside, the roll), the grave ones that only a surgery treats, the price and its
## share, an interrupted consultation, and a game with patients that survives a save and load.

const FAM := "fam_0001"
const DOC := "chr_0001"
const CLINIC := "bld_0001"

var cat := Catalog.load_from()


func _sim(difficulty: String = "normal") -> Sim:
	return Sim.new(NewGame.from_start(cat, "scholar_physician", difficulty, {"cast": "fixed"}, 1)["state"], cat)


func _run(sim: Sim, minutes: int, orders: Array = []) -> Array:
	var ev: Array = sim.step(orders)
	for i: int in minutes - 1:
		ev.append_array(sim.step())
	return ev


func _to_open(sim: Sim) -> void:
	var phases: Array = Services.cfg(sim, "doctor")["open_phases"]
	var guard := 0
	while not Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time) in phases and guard < 1440:
		sim.step()
		guard += 1


## A patient of `severity` waiting at the clinic now (as Services._arrive leaves it).
func _patient(sim: Sim, severity: int) -> String:
	var m: Dictionary = Services._mem(sim.state, CLINIC)
	m["seq"] = int(m["seq"]) + 1
	var id := "svc_test_%d" % int(m["seq"])
	(m["waiting"] as Array).append({"id": id, "service": "doctor", "severity": severity,
		"since": int(sim.state.clock["minute"]), "claimed": ""})
	return id


func _inside(sim: Sim) -> void:
	sim.state.characters[DOC]["location"] = CLINIC


func _of(ev: Array, type: String) -> Array:
	return ev.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


func test_the_start() -> void:
	var sim := _sim()
	var st := sim.state
	var b: Dictionary = st.buildings[CLINIC]
	eq([str(b["type"]), str(b["owner"])], ["clinic", FAM], "the Consulta médica is the family's")
	eq([Inventory.count(b["inventory"], "bandages"), Inventory.count(b["inventory"], "cloth")], [6, 4],
		"six bandages and four pieces of cloth")
	eq(str(st.characters[DOC]["equipment"]["tool"]["item"]), "doctor_bag", "the doctor's bag equipped")
	eq(int(st.characters[DOC]["stats"]["arcane"]), 7, "Arcane 7")
	eq(Money.gold(st, FAM), 30, "30 gold")
	var s := Loans.status(sim, "lon_0001")
	eq([int(s["outstanding"]), int(s["days_left"]), str(s["kind"]), int(s["next_due"])],
		[200, 8, "", 8 * Clock.MINUTES_PER_DAY], "the debt of the start, as the forge's (one payment, no interest)")
	var types: Array = []
	for id: String in st.buildings:
		types.append(str(st.buildings[id]["type"]))
	check("forge" in types and "carpentry" in types, "the town keeps its rival smith and its workshops")
	eq(Services.of_type(sim, "clinic"), ["doctor"], "the Consulta gives the doctor service")
	eq(Services.price(sim, CLINIC, "doctor"), 20, "at the reference price")


func test_patients_come_wait_and_leave() -> void:
	var sim := _sim()
	_to_open(sim)
	check(Services.per_day(sim, CLINIC, "doctor") > 0.5, "some a day (%.2f)" % Services.per_day(sim, CLINIC, "doctor"))
	var ev := _run(sim, 900)
	var came := _of(ev, "service_client_arrived")
	var left := _of(ev, "service_client_left")
	check(came.size() >= 1, "patients come (%d)" % came.size())
	check(left.any(func(e: Dictionary) -> bool: return str(e["reason"]) in ["nobody", "closed"]),
		"with nobody at the cot they leave")
	check(Services.waiting(sim.state, CLINIC).size() <= int(Services.cfg(sim, "doctor")["max_waiting"]), "at most max_waiting")


func test_a_consultation() -> void:
	var sim := _sim()
	_to_open(sim)
	_inside(sim)
	var p := _patient(sim, 3)
	var inv: Dictionary = sim.state.buildings[CLINIC]["inventory"]
	var gold0 := Money.gold(sim.state, FAM)
	var ev := _run(sim, 2, [{"type": "work_at", "actor": DOC, "building": CLINIC, "zone": "cot", "recipe": "doctor_visit",
		"mode": "normal"}])
	eq(Inventory.count(inv, "bandages"), 5, "the consultation takes one bandage when it starts")
	var job: Dictionary = sim.state.buildings[CLINIC]["zones"]["cot"]["job"]
	eq([str(job["client"]), bool(job["service"])], [p, true], "the cot works on the patient")
	ev.append_array(_run(sim, 70))
	var done := _of(ev, "service_done")
	eq(done.size(), 1, "one consultation done")
	eq([str(done[0]["client"]), int(done[0]["price"]), int(done[0]["severity"])], [p, 20, 3], "it pays the price")
	eq(Money.gold(sim.state, FAM), gold0 + 20, "20 gold from outside")
	var e: Dictionary = sim.state.ledger["entries"][-1]
	eq([str(e["category"]), int(e["amount"])], ["services", 20], "a services entry")
	check(Services.waiting(sim.state, CLINIC).is_empty(), "the patient is gone")
	job = sim.state.buildings[CLINIC]["zones"]["cot"]["job"]
	eq([int(job["end"]), str(job["client"])], [-1, ""], "the cot waits for the next one, nothing taken")
	eq(Inventory.count(inv, "bandages"), 5, "waiting takes nothing")


func test_the_roll_is_the_arcane() -> void:
	var sim := _sim()
	_to_open(sim)
	_inside(sim)
	var cured := 0
	var n := 0
	var ev := _run(sim, 1, [{"type": "work_at", "actor": DOC, "building": CLINIC, "zone": "cot", "recipe": "doctor_visit",
		"mode": "normal"}])
	for i: int in 6:  # one at a time (more would run out of patience while the others are seen)
		_patient(sim, 5)
		ev.append_array(_run(sim, 62))
	for d: Dictionary in _of(ev, "service_done"):
		n += 1
		if bool(d["cured"]):
			cured += 1
	check(n >= 4, "several consultations in a row (%d)" % n)
	check(cured >= 1 and cured <= n, "the roll cures some (%d of %d)" % [cured, n])
	var a := _sim()
	var b := _sim()
	for s: Sim in [a, b]:
		_to_open(s)
		s.state.characters[DOC]["location"] = CLINIC
		Services._mem(s.state, CLINIC)["waiting"].append({"id": "svc_x", "service": "doctor", "severity": 5,
			"since": int(s.state.clock["minute"]), "claimed": ""})
	var ea := _run(a, 70, [{"type": "work_at", "actor": DOC, "building": CLINIC, "zone": "cot", "recipe": "doctor_visit",
		"mode": "normal"}])
	var eb := _run(b, 70, [{"type": "work_at", "actor": DOC, "building": CLINIC, "zone": "cot", "recipe": "doctor_visit",
		"mode": "normal"}])
	eq(SaveFile.canonical({"e": _of(ea, "service_done")}), SaveFile.canonical({"e": _of(eb, "service_done")}),
		"the same game, the same roll")


func test_grave_patients_need_a_surgery() -> void:
	var sim := _sim()
	_to_open(sim)
	_inside(sim)
	var p := _patient(sim, 7)
	var ev := _run(sim, 30, [{"type": "work_at", "actor": DOC, "building": CLINIC, "zone": "cot", "recipe": "doctor_visit",
		"mode": "normal"}])
	eq(str(sim.state.buildings[CLINIC]["zones"]["cot"]["job"]["client"]), "", "a consultation does not take a grave one")
	var r := Orders.apply(sim, {"type": "work_at", "actor": DOC, "building": CLINIC, "zone": "cot", "recipe": "doctor_surgery",
		"mode": "normal"})
	eq(r["reason"], "missing_inputs", "the surgery asks for a salve")
	check(Inventory.add(sim.state.buildings[CLINIC]["inventory"], cat, "salve", 0, 1), "setup: a salve")
	ev = _run(sim, 130, [{"type": "work_at", "actor": DOC, "building": CLINIC, "zone": "cot", "recipe": "doctor_surgery",
		"mode": "normal"}])
	var done := _of(ev, "service_done")
	eq(done.size(), 1, "the surgery treats it")
	eq([str(done[0]["client"]), int(done[0]["price"]), str(done[0]["recipe"])], [p, 35, "doctor_surgery"],
		"35 gold: 1.75 × the consultation")
	eq(Inventory.count(sim.state.buildings[CLINIC]["inventory"], "salve"), 0, "the salve is used")


func test_the_price_and_its_share() -> void:
	var sim := _sim()
	var share20 := Services.share(sim, CLINIC, "doctor")
	var r := Orders.apply(sim, {"type": "set_service_price", "actor": DOC, "building": CLINIC, "service": "doctor",
		"price": 30})
	check(r["ok"], "the owner sets 30: %s" % r["reason"])
	eq(Services.price(sim, CLINIC, "doctor"), 30, "kept in the building")
	check(Services.share(sim, CLINIC, "doctor") < share20, "dearer, fewer patients (%.3f < %.3f)" % [
		Services.share(sim, CLINIC, "doctor"), share20])
	eq(_of(sim.events, "service_price_set").size(), 1, "the event of the objective")
	eq(Orders.apply(sim, {"type": "set_service_price", "actor": DOC, "building": CLINIC, "service": "doctor",
		"price": 41})["reason"], "bad_price", "more than 2× the reference")
	eq(Orders.apply(sim, {"type": "set_service_price", "actor": DOC, "building": CLINIC, "service": "doctor",
		"price": 9})["reason"], "bad_price", "less than 0.5×")
	eq(Orders.apply(sim, {"type": "set_service_price", "actor": DOC, "building": CLINIC, "service": "mass",
		"price": 9})["reason"], "unknown_service", "a service the Consulta does not give")
	var rival := ""
	for id: String in sim.state.characters:
		if str(sim.state.characters[id].get("family", "")) != FAM and str(sim.state.characters[id].get("family", "")) != "":
			rival = id
			break
	eq(Orders.apply(sim, {"type": "set_service_price", "actor": rival, "building": CLINIC, "service": "doctor",
		"price": 25})["reason"], "not_owner", "somebody else's building")


func test_an_interrupted_consultation() -> void:
	var sim := _sim()
	_to_open(sim)
	_inside(sim)
	var p := _patient(sim, 3)
	_run(sim, 5, [{"type": "work_at", "actor": DOC, "building": CLINIC, "zone": "cot", "recipe": "doctor_visit",
		"mode": "normal"}])
	eq(Inventory.count(sim.state.buildings[CLINIC]["inventory"], "bandages"), 5, "one bandage taken")
	var r := Orders.apply(sim, {"type": "stop_work", "actor": DOC})
	check(r["ok"], "stops: %s" % r["reason"])
	eq(Inventory.count(sim.state.buildings[CLINIC]["inventory"], "bandages"), 6, "the bandage comes back")
	var w: Array = Services.waiting(sim.state, CLINIC)
	eq([w.size(), str(w[0]["id"]), str(w[0]["claimed"])], [1, p, ""], "the patient waits again")


func test_bandages_at_the_mortar() -> void:
	var sim := _sim()
	_inside(sim)
	var ev := _run(sim, 62, [{"type": "work_at", "actor": DOC, "building": CLINIC, "zone": "mortar",
		"recipe": "doctor_bandages", "mode": "normal"}])
	var done := _of(ev, "work_done")
	check(not done.is_empty() and str(done[0]["item"]) == "bandages" and int(done[0]["qty"]) == 3,
		"a piece of cloth gives three bandages in an hour")
	eq(Inventory.count(sim.state.buildings[CLINIC]["inventory"], "cloth"), 2, "one piece used and the next cycle started")


func test_a_saved_game_with_patients() -> void:
	var a := _sim()
	_to_open(a)
	_inside(a)
	_patient(a, 3)
	_patient(a, 5)
	_run(a, 10, [{"type": "work_at", "actor": DOC, "building": CLINIC, "zone": "cot", "recipe": "doctor_visit",
		"mode": "normal"}])
	check(Orders.apply(a, {"type": "set_service_price", "actor": DOC, "building": CLINIC, "service": "doctor",
		"price": 25})["ok"], "a price of its own")
	var back: WorldState = SaveFile.from_text(JSON.stringify(a.state.to_dict()))["state"]
	eq(SaveFile.canonical(back.town.get("services", {})), SaveFile.canonical(a.state.town["services"]),
		"the patients waiting survive the save")
	var b := Sim.new(back, cat)
	var e1 := _run(a, 300)
	var e2 := _run(b, 300)
	eq(SaveFile.canonical({"e": _of(e2, "service_done")}), SaveFile.canonical({"e": _of(e1, "service_done")}),
		"the loaded game goes on the same")
	eq(Services.price(b, CLINIC, "doctor"), 25, "and keeps its price")
