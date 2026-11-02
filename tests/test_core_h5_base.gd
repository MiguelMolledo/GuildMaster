extends "res://tests/test_case.gd"
## H5 base (docs/contratos/h5_mejoras.md): the Forge tree as data and its validation, the v6 save, the orders wired,
## the effects registry (Upgrades.mult / amount / unlocks / flag), complete(), status_of / tree_view / visuals, the
## inspections' risk and the forge_upgrades scenarios. Buying, works and inspections themselves are tested by «arbol».

const FORGE: String = "bld_0001"
const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func _sim(id: String = "forge_upgrades") -> Sim:
	return Sim.new(NewGame.from_scenario(id, 1)["state"], cat)


func test_forge_tree_loads() -> void:
	eq(cat.validate(), PackedStringArray(), "no data problems")
	var ids := cat.upgrade_tree("forge")
	eq(ids.size(), 24, "24 upgrades")
	var per := {}
	for id: String in ids:
		var u := cat.upgrade(id)
		per[str(u["branch"])] = int(per.get(str(u["branch"]), 0)) + 1
		var key := str(u["name_key"])
		check(TranslationServer.translate(key) != key, "%s has text" % id)
	eq(per.size(), 8, "8 branches")
	for br: String in per:
		eq(int(per[br]), 3, "%s has 3 levels" % br)
	var p1 := cat.upgrade("forge_production_1")
	eq([int(p1["cost"]["gold"]), p1["cost"]["items"], float(p1["build_days"]), p1["effects"]],
		[15, [{"item": "wood", "qty": 2}], 0.5, [{"kind": "production_speed", "mult": 1.2}]], "Fuelle mejorado (GDD 4.8, oro ×5 de D14)")
	eq(cat.upgrade("forge_commerce_3")["requires"]["upgrades"], ["forge_commerce_2", "forge_facade_1"], "cross requirement")
	eq(cat.upgrade("forge_facade_3")["requires"]["title"], "citizen", "Fachada noble needs Ciudadano")
	eq(cat.upgrade("forge_secrets_2")["requires"]["stat"], {"id": "stealth", "min": 3}, "Sigilo 3")
	eq(str(cat.recipes()["forge_steel"]["requires_upgrade"]), "forge_production_3", "steel comes with production 3")
	eq(str(cat.buildings()["forge"]["upgrade_tree"]), "forge", "the forge's tree")


func test_validation_catches_bad_trees() -> void:
	var bad := Catalog.load_from()
	bad.tables["upgrades"]["forge_production_1"]["effects"] = [{"kind": "free_gold", "amount": 9}]
	bad.tables["upgrades"]["forge_production_1"]["requires"]["upgrades"] = ["forge_production_3"]  # a loop
	bad.tables["upgrades"]["forge_quality_2"]["requires"]["upgrades"] = ["forge_nothing"]
	bad.tables["upgrades"]["forge_staff_3"]["effects"] = [{"kind": "allow_rank", "rank": "king"}]
	bad.tables["upgrades"]["forge_secrets_3"]["requires"]["upgrades"] = []  # level 3 without level 2
	var errs := "\n".join(bad.validate())
	for want: String in ["unknown effect kind free_gold", "requirements loop back", "requires unknown upgrade forge_nothing",
			"unknown rank king", "level 3 must require level 2"]:
		check(want in errs, "caught: %s" % want)


func test_v5_save_migrates_to_v6() -> void:
	var r := SaveFile.load_file("res://tests/data/saves/v5_two_employees.json")
	check(r["ok"], "the v5 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	eq(st.version, WorldState.VERSION, "migrated")
	check(WorldState.VERSION >= 6, "v6 or later")
	for b: String in st.buildings:
		var bld: Dictionary = st.buildings[b]
		eq([bld["upgrades"], bld["upgrade_work"], bld["inspection"]], [[], null, Upgrades.new_inspection()],
			"%s v6 fields" % b)
	var sim := Sim.new(st, cat)
	sim.run_minutes(120)
	eq(Staff.employees_of(sim.state, FORGE).size(), 2, "a migrated game runs with its employees")


func test_round_trip_with_h5_state() -> void:
	var sim := _sim("forge_upgrade_works")
	var st := sim.state
	st.buildings[FORGE]["inspection"] = {"last_day": 3, "caught": 2, "escaped": 1, "fines": 37, "escape_ready_day": 11}
	var back: WorldState = SaveFile.from_text(JSON.stringify(st.to_dict()))["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "same content")
	eq(back.buildings[FORGE]["upgrades"], ["forge_production_1", "forge_capacity_1", "forge_quality_1", "forge_staff_1"],
		"finished upgrades in order")
	eq(typeof(back.buildings[FORGE]["upgrade_work"]["end"]), TYPE_INT, "works end is int")
	eq(int(back.buildings[FORGE]["inspection"]["fines"]), 37, "inspection memory survives")
	eq(typeof(back.buildings[FORGE]["inventory"]["limit"]), TYPE_INT, "storage limit is int")


func test_new_buildings_have_the_v6_fields() -> void:
	var st: WorldState = NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)["state"]
	for b: String in st.buildings:
		eq([st.buildings[b]["upgrades"], st.buildings[b]["upgrade_work"]], [[], null], "%s starts without upgrades" % b)
		eq(st.buildings[b]["inspection"], Upgrades.new_inspection(), "%s inspection memory" % b)


func test_buy_upgrade_is_wired_as_management() -> void:
	var sim := _sim()
	var r := Orders.apply(sim, {"type": "buy_upgrade", "actor": HERO, "building": FORGE, "upgrade": "forge_production_2"})
	check(r["reason"] != "unknown_order", "buy_upgrade is wired (%s)" % r["reason"])
	check(Orders.is_management("buy_upgrade"), "a panel order: never waits in the actor's queue")


func test_effects_registry() -> void:
	var sim := _sim()
	near(Upgrades.mult(sim, FORGE, "production_speed"), 1.2, 0.0001, "bellows ×1.2")
	near(Upgrades.amount(sim, FORGE, "quality_bonus"), 1.0, 0.0001, "tempered steel +1")
	near(Upgrades.mult(sim, FORGE, "price_multiplier"), 1.0, 0.0001, "no price effect yet")
	near(Upgrades.mult(sim, "bld_0002", "production_speed"), 1.0, 0.0001, "the rival's forge has none")
	check(Upgrades.complete(sim, FORGE, "forge_production_2"), "temple")
	near(Upgrades.mult(sim, FORGE, "production_speed"), 1.4, 0.0001, "levels of a branch replace: ×1.4, not ×1.68")
	Upgrades.complete(sim, FORGE, "forge_quality_2")
	Upgrades.complete(sim, FORGE, "forge_quality_3")
	near(Upgrades.amount(sim, FORGE, "quality_bonus"), 3.0, 0.0001, "seal +3 (not +6)")
	near(Upgrades.mult(sim, FORGE, "price_multiplier"), 1.5, 0.0001, "seal ×1.5")
	for id: String in ["forge_commerce_1", "forge_commerce_2", "forge_facade_1", "forge_commerce_3"]:
		Upgrades.complete(sim, FORGE, id)
	near(Upgrades.mult(sim, FORGE, "price_multiplier"), 1.65, 0.0001, "branches multiply: ×1.5 × ×1.1")
	near(Upgrades.amount(sim, FORGE, "customer_bonus"), 0.5, 0.0001, "customers +50 %")
	check(Upgrades.flag(sim, FORGE, "counter_sales"), "the counter sells")
	check(not Upgrades.flag(sim, FORGE, "inspection_escape"), "no passage")
	Upgrades.complete(sim, FORGE, "forge_secrets_1")
	Upgrades.complete(sim, FORGE, "forge_security_1")
	Upgrades.complete(sim, FORGE, "forge_secrets_2")
	Upgrades.complete(sim, FORGE, "forge_secrets_3")
	near(Upgrades.amount(sim, FORGE, "inspection_risk"), 0.2, 0.0001, "risks add up (stack all): 5 % + 15 %")
	near(Upgrades.amount(sim, FORGE, "protection"), 0.2, 0.0001, "lock 20 %")
	near(Inspections.risk(sim, FORGE), 0.2, 0.0001, "honesty 0: p = 0.2")
	sim.state.families["fam_0001"]["attitudes"] = {"honesty": 100}
	near(Inspections.risk(sim, FORGE), 0.1, 0.0001, "honesty 100: p = 0.2 × (1 − 100/200)")
	check(Inspections.can_escape(sim, FORGE), "the passage is ready")
	eq(Inspections.view(sim, FORGE).keys(), ["risk", "last_day", "caught", "escaped", "fines", "can_escape"], "view shape")
	Upgrades.complete(sim, FORGE, "forge_production_3")
	eq(Upgrades.unlocks(sim, FORGE, "unlock_recipe"), ["forge_steel"], "steel unlocked")
	check(not Upgrades.allows_rank(sim, FORGE, "master"), "no masters without the workshop")


func test_complete_applies_its_effects_once() -> void:
	var sim := _sim()
	var st := sim.state
	var b: Dictionary = st.buildings[FORGE]
	eq(int(b["employee_slots"]), 2, "base 1 + dormitory 1")
	eq(Upgrades.zone_kind(sim, FORGE, "anvil_2"), "anvil", "the second anvil works as an anvil")
	eq(Upgrades.zone_kind(sim, FORGE, "anvil"), "anvil", "own zones are themselves")
	eq(Upgrades.zone_kind(sim, FORGE, "furnace_2"), "", "no second furnace yet")
	eq(b["zones"]["anvil_2"], {"occupant": "", "job": null}, "an empty station")
	eq(Upgrades.new_zones(sim, FORGE), [{"zone": "anvil_2", "like": "anvil", "upgrade": "forge_capacity_1"}],
		"new stations and what they work as")
	var emps := Staff.employees_of(st, FORGE)
	var before := []
	for c: String in emps:
		before.append(int(st.characters[c]["job"]["loyalty"]))
	sim.events = []
	check(Upgrades.complete(sim, FORGE, "forge_capacity_2"), "storage")
	check(Upgrades.complete(sim, FORGE, "forge_staff_2"), "dining room")
	check(Upgrades.complete(sim, FORGE, "forge_staff_3"), "master's workshop")
	check(Upgrades.complete(sim, FORGE, "forge_facade_1"), "stone facade")
	eq(int(b["inventory"]["limit"]), 20, "storage 10 + 10 stacks")
	eq(int(b["employee_slots"]), 3, "places add up (stack all): 1 + 1 + 1")
	check(Upgrades.allows_rank(sim, FORGE, "master"), "masters allowed")
	for i: int in emps.size():
		eq(int(st.characters[str(emps[i])]["job"]["loyalty"]), int(before[i]) + 15, "dining +10 and facade +5, once")
	eq(int(st.families["fam_0001"]["reputation"]), 10, "facade +10 reputation")
	var types := []
	for e: Dictionary in sim.events:
		types.append(str(e["type"]))
	eq(types.count("upgrade_done"), 4, "one upgrade_done each")
	eq(types.count("reputation_changed"), 1, "the facade's reputation")
	check(not Upgrades.complete(sim, FORGE, "forge_capacity_2"), "never twice")
	eq(int(b["inventory"]["limit"]), 20, "still 20")
	check(not Upgrades.complete(sim, "bld_0003", "forge_production_1"), "not in the armory (no forge tree)")
	check(not Upgrades.complete(sim, FORGE, "forge_nothing"), "unknown")


func test_status_of_and_tree_view() -> void:
	var sim := _sim()
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_production_1"), "owned", "owned")
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_production_2"), "available", "5 ingots and 8 gold: available")
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_production_3"), "needs_upgrade", "needs temple first")
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_staff_3"), "needs_upgrade", "needs capacity 2 (cross)")
	eq(Upgrades.status_of(sim, "chr_0002", FORGE, "forge_quality_2"), "stat_too_low", "Elena: craft 4 < 5")
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_quality_2"), "available", "Hugo: craft 7")
	eq(Upgrades.status_of(sim, "chr_0006", FORGE, "forge_production_2"), "not_your_building", "the rival")
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_nothing"), "unknown_upgrade", "unknown")
	eq(Upgrades.status_of(sim, HERO, "bld_0003", "forge_production_1"), "not_your_building", "the public armory")
	Upgrades.complete(sim, FORGE, "forge_facade_1")
	Upgrades.complete(sim, FORGE, "forge_facade_2")
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_facade_3"), "title_too_low", "Fachada noble: Ciudadano")
	sim.state.families["fam_0001"]["title"] = "citizen"
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_facade_3"), "available", "with the title")
	sim.state.families["fam_0001"]["gold"] = 5
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_production_2"), "not_enough_gold", "8 gold")
	Inventory.remove(sim.state.buildings[FORGE]["inventory"], "iron_ingot", Inventory.NORMAL, 10)
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_production_2"), "missing_materials", "no ingots")
	var w := _sim("forge_upgrade_works")
	eq(Upgrades.status_of(w, HERO, FORGE, "forge_capacity_2"), "in_works", "the works")
	eq(Upgrades.status_of(w, HERO, FORGE, "forge_production_2"), "busy", "one works at a time")
	var v := Upgrades.tree_view(w, HERO, FORGE)
	eq(v.keys(), ["building", "tree", "owned", "work", "branches"], "view shape")
	eq((v["branches"] as Array).map(func(b: Dictionary) -> String: return str(b["id"])),
		["production", "capacity", "quality", "commerce", "staff", "facade", "security", "secrets"], "branches in order")
	for b: Dictionary in v["branches"]:
		eq((b["upgrades"] as Array).map(func(u: Dictionary) -> int: return int(u["level"])), [1, 2, 3], "%s by level" % b["id"])
	eq(str(v["work"]["upgrade"]), "forge_capacity_2", "the works")
	near(float(v["work"]["progress"]), 0.5, 0.001, "half done")
	eq(int(v["work"]["minutes_left"]), 720, "12 h left")
	eq(str(v["branches"][1]["upgrades"][1]["status"]), "in_works", "status in the view")


func test_visuals_are_ids() -> void:
	var sim := _sim()
	var v := Upgrades.visuals(sim, FORGE)
	eq((v["interior"] as Array).map(func(x: Dictionary) -> String: return str(x["node"])),
		["forge_bellows", "forge_anvil_2", "forge_quench_trough", "upgrade_bunks"], "interior nodes in finishing order")
	eq(v["exterior"], [], "nothing outside yet")
	Upgrades.complete(sim, FORGE, "forge_facade_1")
	eq(Upgrades.visuals(sim, FORGE)["exterior"], [{"upgrade": "forge_facade_1", "node": "upgrade_stone_facade"}],
		"the stone facade outside")


func test_upgrade_scenarios_run() -> void:
	for id: String in ["forge_upgrades", "forge_upgrade_works"]:
		var sim := _sim(id)
		eq(Money.gold(sim.state, "fam_0001"), 1000 if id == "forge_upgrades" else 1000 - int(cat.upgrade("forge_capacity_2")["cost"]["gold"]), "%s gold" % id)
		sim.run_minutes(240)  # through dawn: wages, upkeep, inspections (none: no Secrets)
		eq(Staff.employees_of(sim.state, FORGE).size(), 2, "%s keeps its 2 employees" % id)
		eq(int(sim.state.buildings[FORGE]["inspection"]["caught"]), 0, "%s: nobody inspects a forge without Secrets" % id)
