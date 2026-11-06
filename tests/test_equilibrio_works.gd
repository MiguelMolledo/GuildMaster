extends "res://tests/test_case.gd"
## Equilibrio 9 (docs/decisiones.json; GDD 4.8): the small upgrades are built at night without stopping the forge; the
## big ones leave it working at half speed while they last. A works saved before (no mode) still closes the building.

const FORGE: String = "bld_0001"
const HERO: String = "chr_0001"
const JOAN: String = "chr_0007"

var cat := Catalog.load_from()


func _sim(id: String = "forge_upgrades", seed: int = 1) -> Sim:
	var sim := Sim.new(NewGame.from_scenario(id, seed)["state"], cat)
	sim.state.families["fam_0001"]["gold"] = 5000
	return sim


func _buy(sim: Sim, id: String) -> Dictionary:
	var u := cat.upgrade(id)
	for c: Dictionary in u.get("cost", {}).get("items", []):
		Inventory.add(sim.state.buildings[FORGE]["inventory"], cat, str(c["item"]), 0, int(c["qty"]))
	return Orders.apply(sim, {"type": "buy_upgrade", "actor": HERO, "building": FORGE, "upgrade": id})


func _run(sim: Sim, minutes: int) -> Array:
	var all: Array = []
	for i: int in minutes:
		all.append_array(sim.step())
	return all


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool:
		return str(e["type"]) == type and str(e.get("building", "")) == FORGE)


func test_modes_by_size() -> void:
	var sim := _sim()
	eq(Upgrades.works_mode(sim, "forge_production_2"), Upgrades.NIGHT, "1 day: small")
	eq(Upgrades.works_mode(sim, "forge_capacity_3"), Upgrades.HALF, "1.5 days: big")


func test_small_works_go_at_night_and_the_forge_keeps_working() -> void:
	var sim := _sim()
	var st := sim.state
	_run(sim, 270)  # 04:30 -> 09:00, the employees at work
	var running := 0
	for z: String in st.buildings[FORGE]["zones"]:
		if st.buildings[FORGE]["zones"][z].get("job") is Dictionary:
			running += 1
	check(running > 0, "cycles running (%d)" % running)
	sim.events = []
	var now := int(st.clock["minute"])
	check(_buy(sim, "forge_production_2")["ok"], "buys a small one by day")
	eq(sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "work_interrupted").size(), 0,
		"nothing interrupted")
	var w := Upgrades.work(st, FORGE)
	eq(str(w["mode"]), Upgrades.NIGHT, "night works")
	eq(Clock.day(int(w["end"])), Clock.day(now) + 1, "done at the next dawn")
	eq(Clock.phase(int(w["end"]), cat.time), "dawn", "at dawn")
	eq(Production.may_work(sim, HERO, FORGE), "", "the owner may work")
	var ev := _run(sim, 600)
	check(not _of(ev, "work_started").is_empty(), "cycles start during the day")
	check(not _of(ev, "work_done").is_empty(), "and finish")
	_run(sim, int(w["end"]) - int(st.clock["minute"]) + 1)
	check(Upgrades.has(st, FORGE, "forge_production_2"), "built by the dawn")


func test_big_works_leave_the_forge_at_half_speed() -> void:
	var sim := _sim()
	var st := sim.state
	var sword: Dictionary = cat.recipes()["forge_sword"]
	var normal := Production.owner_cycle_minutes(sim, FORGE, sword, "normal")
	var big := ""
	for id: String in ["forge_facade_1", "forge_staff_2", "forge_capacity_3", "forge_quality_3"]:
		if big == "" and Upgrades.status_of(sim, HERO, FORGE, id) in ["available", "missing_materials"]:
			big = id
	check(big != "", "a big upgrade can be bought")
	var r0 := _buy(sim, big)
	check(r0["ok"], "buys a big one (%s: %s)" % [big, r0.get("reason", "")])
	eq(str(Upgrades.work(st, FORGE)["mode"]), Upgrades.HALF, "half")
	eq(Upgrades.works_speed(sim, FORGE), 0.5, "half speed")
	eq(Production.may_work(sim, HERO, FORGE), "", "nobody is refused")
	st.characters[HERO]["location"] = FORGE
	Inventory.add(st.buildings[FORGE]["inventory"], cat, "iron_ingot", 0, 4)
	Inventory.add(st.buildings[FORGE]["inventory"], cat, "coal", 0, 4)
	var r := Orders.apply(sim, {"type": "work_at", "actor": HERO, "building": FORGE, "zone": "anvil",
		"recipe": "forge_sword", "mode": "normal"})
	eq(r["ok"], true, "the owner works during big works (%s)" % r.get("reason", ""))
	var job: Dictionary = st.buildings[FORGE]["zones"]["anvil"]["job"]
	var took := int(job["end"]) - int(job["start"])
	check(absi(took - normal * 2) <= 2, "the cycle takes twice as long (%d vs %d)" % [took, normal])


func test_a_works_saved_before_still_closes() -> void:
	var sim := _sim("forge_upgrade_works")
	eq(Upgrades.mode_of(sim.state, FORGE), Upgrades.CLOSED, "no mode: closed")
	eq(Production.may_work(sim, HERO, FORGE), "under_works", "the old rule")
