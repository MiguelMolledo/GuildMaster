extends "res://tests/test_case.gd"
## H12 Patrón · the farm (docs/gdd/04d_otras_clases.md 4.22.4.1-2, 4.22.4.6, 4.22.10 H12.1; sim/farm/fields.gd,
## sim/farm/herds.gd and the field recipes of sim/econ/production.gd): the farmer's start, the wheat cycle (sown on
## day 1 it is ready at the dawn of day 5, the winter does not grow it, it rots two dawns after it is ready, the late
## harvest), the field orders and their reasons, an interrupted sowing gives the seed back, the pen (winter feed,
## death after two days unfed, breeding up to the pen's capacity), the demand weight of the wheat, the errand of the
## animals and a farm that survives a save and load.

const FAM := "fam_0001"
const HERO := "chr_0001"
const FARM := "bld_0001"

var cat := Catalog.load_from()


func _sim(difficulty: String = "normal") -> Sim:
	return Sim.new(NewGame.from_start(cat, "patron_farmer", difficulty, {"cast": "fixed"}, 1)["state"], cat)


## The dawn of sim day `d` for the farm modules only (Fields.step, Herds.step), as Sim.step runs them.
func _dawn(sim: Sim, d: int) -> void:
	var season := Clock.season(d * Clock.MINUTES_PER_DAY, sim.catalog.time)
	sim.state.clock["minute"] = d * Clock.MINUTES_PER_DAY + int(sim.catalog.time["phase_starts"][season]["dawn"])
	sim.events = [{"type": "phase_changed", "phase": "dawn"}]
	Fields.step(sim)
	Herds.step(sim)


func _sow(sim: Sim, zone: String, day: int) -> void:
	var f := Fields.field(sim.state, FARM, zone)
	f["state"] = "growing"
	f["crop"] = "wheat"
	f["growth"] = 0.0
	f["sown_day"] = day


func _state(sim: Sim, zone: String) -> String:
	return str(Fields.peek(sim.state, FARM, zone)["state"])


func _inside(sim: Sim) -> void:
	sim.state.characters[HERO]["location"] = FARM


func _run(sim: Sim, minutes: int, orders: Array = []) -> Array:
	var ev: Array = sim.step(orders)
	for i: int in minutes - 1:
		ev.append_array(sim.step())
	return ev


func _of(ev: Array, type: String) -> Array:
	return ev.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


func _work(zone: String, recipe: String, mode: String = "normal") -> Dictionary:
	return {"type": "work_at", "actor": HERO, "building": FARM, "zone": zone, "recipe": recipe, "mode": mode}


func test_the_start() -> void:
	var sim := _sim()
	var st := sim.state
	var b: Dictionary = st.buildings[FARM]
	eq([str(b["type"]), str(b["owner"])], ["farm", FAM], "the Granja is the family's")
	eq(Fields.zones(sim, FARM), ["field_a", "field_b", "field_c", "field_d"], "four fields")
	for z: String in Fields.zones(sim, FARM):
		eq(_state(sim, z), "plowed", "field %s plowed at the start" % z)
	eq([Inventory.count(b["inventory"], "wheat"), Inventory.count(b["inventory"], "sheep"),
		Inventory.count(b["inventory"], "pig")], [40, 4, 2], "wheat ×40, sheep ×4, pigs ×2")
	eq([Herds.has_pen(sim, FARM), Herds.capacity(sim, FARM), Herds.head_count(sim, FARM)], [true, 8, 6],
		"a pen of 8 with 6 heads")
	eq(str(st.characters[HERO]["equipment"]["tool"]["item"]), "hoe", "the hoe equipped")
	eq(Money.gold(st, FAM), 30, "30 gold")
	var s := Loans.status(sim, "lon_0001")
	eq([int(s["outstanding"]), int(s["days_left"])], [200, 8], "the debt of the start, as the forge's")
	check(sim.catalog.market["stalls"].has("livestock"), "the livestock stall")
	var miller: Array = (st.contracts["board"] as Array).filter(func(c: Dictionary) -> bool:
		return str(c.get("script", "")) == "miller_wheat")
	eq(miller.map(func(c: Dictionary) -> String: return "%s ×%d in %d" % [c["item"], int(c["qty"]),
		int(c["deadline_days"])]), ["wheat ×20 in 2"], "the miller's contract on the board, wheat ×20 in 2 days")


func test_the_wheat_cycle() -> void:
	var sim := _sim()
	_sow(sim, "field_a", 0)  # sown on day 1 (spring)
	var growth: Array = []
	for d: int in range(1, 5):
		_dawn(sim, d)
		growth.append(float(Fields.peek(sim.state, FARM, "field_a")["growth"]))
	eq(growth, [1.0, 2.0, 3.0, 4.0], "one a dawn in spring, summer and autumn")
	eq(_state(sim, "field_a"), "ready", "ready at the dawn of day 5 (autumn)")
	eq(Fields.harvest_of(sim, FARM, "field_a"), {"item": "wheat", "qty": 30}, "wheat ×30")
	_dawn(sim, 5)
	eq(_state(sim, "field_a"), "ready", "still ready on its second day")
	eq(int(Fields.harvest_of(sim, FARM, "field_a")["qty"]), roundi(30 * 0.75), "the late harvest gives −25 %")
	_dawn(sim, 6)
	eq(_state(sim, "field_a"), "rotten", "rotten at the dawn of day 7 (winter)")
	eq(Fields.harvest_of(sim, FARM, "field_a"), {}, "a rotten field gives nothing")


func test_the_winter_does_not_grow() -> void:
	var sim := _sim()
	_sow(sim, "field_b", 2)  # sown on day 3 (summer)
	var states: Array = []
	for d: int in range(3, 9):
		_dawn(sim, d)
		states.append("%s %.0f" % [_state(sim, "field_b"), float(Fields.peek(sim.state, FARM, "field_b")["growth"])])
	eq(states, ["growing 1", "growing 2", "growing 3", "growing 3", "growing 3", "ready 4"],
		"no growth in winter: ready on day 9 (the spring of year 2)")


func test_the_field_orders() -> void:
	var sim := _sim()
	_inside(sim)
	var ev := _run(sim, 1, [_work("field_a", "farm_harvest")])
	eq(str(_of(ev, "order_refused")[0].get("reason", "")), "field_not_ready", "nothing to harvest")
	ev = _run(sim, 1, [_work("field_a", "farm_plow")])
	eq(str(_of(ev, "order_refused")[0].get("reason", "")), "field_not_fallow", "a plowed field is not plowed again")
	ev = _run(sim, 1, [_work("field_a", "farm_sow_wheat", "careful")])
	eq(str(_of(ev, "order_refused")[0].get("reason", "")), "field_normal_only", "a field is worked in normal mode")
	ev = _run(sim, 1, [_work("field_a", "farm_sow_wheat")])
	check(_of(ev, "order_refused").is_empty(), "sowing a plowed field in spring")
	eq(Inventory.count(sim.state.buildings[FARM]["inventory"], "wheat"), 35, "the seed (wheat ×5) is taken")
	ev = _run(sim, 60)
	eq(_state(sim, "field_a"), "growing", "sown after an hour (constitution 5)")
	var w: Array = _of(ev, "field_worked")
	eq([str(w[0]["action"]), str(w[0]["zone"])], ["sow", "field_a"], "field_worked")
	# an autumn field cannot be sown
	var autumn := _sim()
	_inside(autumn)
	autumn.state.clock["minute"] = 4 * Clock.MINUTES_PER_DAY + 600
	ev = _run(autumn, 1, [_work("field_c", "farm_sow_wheat")])
	eq(str(_of(ev, "order_refused")[0].get("reason", "")), "not_sowing_season", "wheat is sown in spring or summer")


func test_plowing_with_the_hoe() -> void:
	var sim := _sim()
	_inside(sim)
	Fields.field(sim.state, FARM, "field_d")["state"] = "fallow"
	var ev := _run(sim, 1, [_work("field_d", "farm_plow")])
	var started: Array = _of(ev, "work_started")
	eq(int(started[0]["end"]) - int(sim.state.clock["minute"]), roundi(120 / 1.25) - 1, "2 h / 1.25 with the hoe")
	_run(sim, roundi(120 / 1.25))
	eq(_state(sim, "field_d"), "plowed", "plowed")
	sim.state.characters[HERO]["equipment"]["tool"] = null
	Fields.field(sim.state, FARM, "field_d")["state"] = "rotten"
	ev = _run(sim, 1, [_work("field_d", "farm_plow")])
	started = _of(ev, "work_started")
	eq(int(started[0]["end"]) - int(sim.state.clock["minute"]), 120 - 1, "2 h without it; a rotten field is plowed")


func test_an_interrupted_sowing_gives_the_seed_back() -> void:
	var sim := _sim()
	_inside(sim)
	_run(sim, 1, [_work("field_b", "farm_sow_wheat")])
	eq(Inventory.count(sim.state.buildings[FARM]["inventory"], "wheat"), 35, "the seed taken")
	_run(sim, 10, [{"type": "stop_work", "actor": HERO}])
	eq(Inventory.count(sim.state.buildings[FARM]["inventory"], "wheat"), 40, "the seed back in the storage (D11)")
	eq(_state(sim, "field_b"), "plowed", "the field as it was")


func test_harvesting_by_hand() -> void:
	var sim := _sim()
	_inside(sim)
	var f := Fields.field(sim.state, FARM, "field_c")
	f.merge({"state": "ready", "crop": "wheat", "growth": 4.0, "ready_day": 0}, true)
	_run(sim, 1, [_work("field_c", "farm_harvest")])
	var ev := _run(sim, 180)
	eq(_state(sim, "field_c"), "fallow", "fallow after the harvest")
	eq(Inventory.count(sim.state.buildings[FARM]["inventory"], "wheat"), 70, "wheat ×30 into the storage")
	var w: Array = _of(ev, "field_worked")
	eq([str(w[0]["action"]), int(w[0]["qty"])], ["harvest", 30], "field_worked harvest ×30")


func test_the_pen() -> void:
	var sim := _sim()
	var inv: Dictionary = sim.state.buildings[FARM]["inventory"]
	_dawn(sim, 1)
	eq(Inventory.count(inv, "wool"), 4, "a wool a sheep at dawn")
	eq(Inventory.count(inv, "wheat"), 40, "they graze in spring")
	_dawn(sim, 2)
	eq(Inventory.count(inv, "pig"), 3, "a pair of pigs gives one every two days")
	_dawn(sim, 6)  # winter
	eq(Inventory.count(inv, "wheat"), 40 - 7, "in winter a wheat a head")
	Inventory.remove(inv, "wheat", Inventory.NORMAL, Inventory.count(inv, "wheat"))
	var wool := Inventory.count(inv, "wool")
	_dawn(sim, 7)
	eq([Inventory.count(inv, "wool"), int(sim.state.buildings[FARM]["pen"]["unfed_days"])], [wool, 1],
		"unfed: no wool that day")
	var n_pigs := Inventory.count(inv, "pig")
	var n_sheep := Inventory.count(inv, "sheep")
	_dawn(sim, 14)  # winter of year 2, the second day unfed
	eq([Inventory.count(inv, "pig"), Inventory.count(inv, "sheep")], [n_pigs - 1, n_sheep],
		"two days unfed: the least valuable animal (a pig) dies")
	check(_of(sim.events, "animal_died").size() == 1, "animal_died")


func test_breeding_fills_the_pen_and_stops() -> void:
	var sim := _sim()
	var inv: Dictionary = sim.state.buildings[FARM]["inventory"]
	for d: int in range(1, 6):
		_dawn(sim, d)
	eq(Herds.head_count(sim, FARM), 8, "up to the pen's 8 heads")
	_dawn(sim, 6)
	_dawn(sim, 7)
	eq(Inventory.count(inv, "pig"), 4, "no more room: no more pigs")


func test_the_demand_weight() -> void:
	var sim := _sim()
	var drop := float(sim.catalog.market["demand"]["drop_per_unit"])
	var st := sim.state
	st.clock["minute"] = 600
	st.characters[HERO]["position"] = (sim.catalog.maps()["town_e"]["stalls"]["resources"]["service"] as Array).duplicate()
	st.characters[HERO]["location"] = ""
	Inventory.add(st.characters[HERO]["inventory"], sim.catalog, "wheat", 0, 10)
	var before := Market.demand(sim, "wheat")
	_run(sim, 1, [{"type": "sell", "actor": HERO, "stall": "resources", "item": "wheat", "quality": 0, "qty": 10}])
	near(before - Market.demand(sim, "wheat"), 10 * drop * 0.1, 0.0001, "ten wheat drop the demand ×0.1 of a sword")
	eq(sim.catalog.demand_weight("sword"), 1.0, "the artisan's goods keep weight 1")


func test_animals_go_to_the_pen() -> void:
	var sim := _sim()
	var st := sim.state
	st.clock["minute"] = 600
	st.families[FAM]["gold"] = 500
	st.characters[HERO]["position"] = (sim.catalog.maps()["town_e"]["stalls"]["livestock"]["service"] as Array).duplicate()
	st.characters[HERO]["location"] = ""
	var buy := {"type": "buy", "actor": HERO, "stall": "livestock", "item": "sheep", "quality": 0, "qty": 3,
		"deliver_to": FARM}
	var ev := _run(sim, 1, [buy])
	eq(str(_of(ev, "order_refused")[0].get("reason", "")), "pen_full", "6 + 3 > 8: the pen is full")
	buy["qty"] = 2
	ev = _run(sim, 1, [buy])
	var sent: Array = _of(ev, "errand_sent")
	eq([sent.size(), int(sent[0]["surcharge"])], [1, 0], "two sheep sent with no surcharge")


func test_a_saved_farm() -> void:
	var a := _sim()
	_sow(a, "field_a", 0)
	_dawn(a, 1)
	var back: WorldState = SaveFile.from_text(JSON.stringify(a.state.to_dict()))["state"]
	eq(SaveFile.canonical(back.buildings[FARM].get("fields", {})), SaveFile.canonical(a.state.buildings[FARM]["fields"]),
		"the fields survive a save and load (no save version: read with defaults)")
	var b := Sim.new(back, cat)
	for d: int in range(2, 5):
		_dawn(a, d)
		_dawn(b, d)
	eq([_state(a, "field_a"), _state(b, "field_a")], ["ready", "ready"], "and ripen the same")
	eq(Inventory.count(b.state.buildings[FARM]["inventory"], "wool"), Inventory.count(a.state.buildings[FARM]["inventory"],
		"wool"), "the pen too")
