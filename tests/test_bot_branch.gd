extends "res://tests/test_case.gd"
## Barón (d) (the manager's decision, 2026-11-07): BotBranch run as its counter asks (mix): it keeps COUNTER_STOCK of
## every product its best hand can make (every intermediate step within its craft and its upgrades: the decorative sword's steel
## needs craft 6 and forge_production_3), the fewest first, and the errands on their way count as stock. Here the branch is the family's forge of
## the title_ready scenario, with its journeyman.

const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _branch(sim: Sim, craft: int) -> BotBranch:
	var br := BotBranch.new()
	br.bld = FORGE
	br.raw = ["iron", "coal"]
	for c: String in Staff.employees_of(sim.state, FORGE):
		sim.state.characters[c]["stats"]["craft"] = craft
	return br


func _sim() -> Sim:
	var sim := Sim.new(NewGame.from_scenario("title_ready", 1)["state"], cat)
	sim.state.buildings[FORGE]["queue"] = {"entries": []}
	return sim


func _outputs(sim: Sim, rids: Array) -> Array:
	return rids.map(func(r: String) -> String: return str(sim.catalog.recipes()[r]["output"]["item"]))


func test_products_follow_the_craft_of_every_step() -> void:
	var sim := _sim()
	check(not Staff.employees_of(sim.state, FORGE).is_empty(), "the forge has its journeyman")
	var low := _outputs(sim, _branch(sim, 3).products(sim))
	check("candlestick" in low and "horseshoe" in low, "craft 3: the plain pieces: %s" % [low])
	check(not "sword" in low, "craft 3: not the sword (4)")
	var high := _outputs(sim, _branch(sim, 7).products(sim))
	check("sword" in high, "craft 7: the sword: %s" % [high])
	check(not "decorative_sword" in high, "craft 7 but no forge_production_3: not the decorative sword (its steel)")
	check(not "steel" in high and not "iron_ingot" in high and not "hammer" in high, "only products (no tools, no intermediates)")
	(sim.state.buildings[FORGE]["upgrades"] as Array).append("forge_production_3")
	check("decorative_sword" in _outputs(sim, _branch(sim, 7).products(sim)), "with the steel's upgrade, the decorative sword")
	check(not "decorative_sword" in _outputs(sim, _branch(sim, 5).products(sim)), "but not with craft 5 (the steel asks for 6)")


func test_it_restocks_the_product_it_has_fewest_of() -> void:
	var sim := _sim()
	var br := _branch(sim, 5)
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	for rid: String in br.products(sim):
		var item := str(sim.catalog.recipes()[rid]["output"]["item"])
		Inventory.remove(inv, item, -1, Inventory.count(inv, item)) if Inventory.count(inv, item) > 0 else null
		if item != "horseshoe":
			Inventory.add(inv, sim.catalog, item, 0, BotBranch.COUNTER_STOCK)
	eq(str(sim.catalog.recipes()[br.recipe(sim)]["output"]["item"]), "horseshoe", "the one product missing")
	var o := br._queue(sim, "chr_0001")
	eq(int(o.get("qty", 0)), BotBranch.COUNTER_STOCK, "queued for the counter's stock, not forever")
	Inventory.add(inv, sim.catalog, "horseshoe", 0, BotBranch.COUNTER_STOCK)
	eq(br.recipe(sim), "", "all stocked: nothing to make")


func test_the_errands_on_their_way_count_as_stock() -> void:
	var sim := _sim()
	var br := _branch(sim, 5)
	var need := br.needs(sim)
	check(need.has("iron"), "it lacks iron: %s" % [need])
	sim.state.deliveries.append({"id": "dlv_test", "family": "fam_0001", "to": FORGE, "item": "iron", "quality": 0,
		"qty": int(need["iron"]), "arrive": int(sim.state.clock["minute"]) + 600})
	check(not br.needs(sim).has("iron"), "the iron on its way covers it: not bought again")
