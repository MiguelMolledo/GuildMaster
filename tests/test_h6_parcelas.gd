extends "res://tests/test_case.gd"
## H6 · plots and construction (docs/gdd/04_diseno_de_juego.md §4.9, §4.9.1; data/construction.json): the plots of
## the map with their state, building and restoring with its works, the title limit (the tavern does not count,
## O-V11), the valve for the AI families, pulling down, converting and buying a business of a NPC.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func _new() -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"], cat)


func _rich(sim: Sim, fam: String = FAM, gold: int = 5000, title: String = "citizen") -> void:
	sim.state.families[fam]["gold"] = gold
	sim.state.families[fam]["title"] = title


func _plot(sim: Sim, id: String) -> Dictionary:
	return Plots.get_plot(sim, id)


func _run_days(sim: Sim, days: float) -> Array:
	var all: Array = []
	for i: int in roundi(days * Clock.MINUTES_PER_DAY):
		all.append_array(sim.step([]))
	return all


func test_the_plots_of_the_map() -> void:
	var sim := _new()
	var ps := Plots.all(sim)
	eq(ps.size(), (cat.maps()["town_e"]["plots"] as Array).size(), "every plot of town_e")
	eq(str(_plot(sim, "plot_01")["kind"]), "ruin", "plot_01 is a ruin")
	eq(str(_plot(sim, "plot_02")["kind"]), "lot", "plot_02 a free lot")
	var forge := _plot(sim, "plot_08")
	eq(str(forge["kind"]), "building", "the player's forge stands on plot_08")
	eq(str(sim.state.buildings[str(forge["building"])]["owner"]), FAM, "and it is the player's")
	eq(Plots.plot_of(sim, str(forge["building"])), "plot_08", "plot_of finds it back")
	check(Plots.free_count(sim, "production") >= 2, "the valve holds at the start (production)")
	check(sim.state.parcels.is_empty(), "nothing is written in state.parcels until something changes")


func test_what_fits_where() -> void:
	var sim := _new()
	eq(Plots.types_for(sim, _plot(sim, "plot_02")), [], "a 3×2 lot takes no workshop")
	eq(Plots.types_for(sim, _plot(sim, "plot_01")), ["tailor_shop"], "the 3×3 ruin takes a tailor's")
	var turned := {"size": [4, 3], "zone": "production"}
	eq(Plots.footprint_on(sim, "forge", turned), [4, 3], "a 3×4 forge turned a quarter on a 4×3 plot")
	check("house" in Plots.types_for(sim, {"size": [3, 3], "zone": "housing"}), "a house on a 3×3 housing plot")
	check(not "armory" in Plots.types_for(sim, {"size": [5, 5], "zone": "government"}), "never a town building")


func test_the_title_limit_and_the_tavern() -> void:
	var sim := _new()
	_rich(sim, FAM, 5000, "common")
	eq(str(Plots.can_build(sim, HERO, "plot_01", "tailor_shop")["reason"]), "title_limit", "a commoner with a forge has no room")
	check(Plots.room_for(sim, FAM, "tavern_inn"), "the tavern does not count for the limit (O-V11)")
	var tavern := ""
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b]["type"]) == "tavern_inn":
			tavern = b
	check(Orders.apply(sim, {"type": "buy_building", "actor": HERO, "building": tavern})["ok"], "so the commoner buys it")
	sim.state.families[FAM]["title"] = "citizen"
	check(Plots.can_build(sim, HERO, "plot_01", "tailor_shop")["ok"], "a citizen has room for a second one")


func test_restoring_a_ruin_with_its_works() -> void:
	var sim := _new()
	_rich(sim)
	var q := Plots.quote(sim, _plot(sim, "plot_01"), "tailor_shop")
	eq(str(q["kind"]), "restore", "a ruin is restored")
	var gold := int(sim.state.families[FAM]["gold"])
	var r := Orders.apply(sim, {"type": "build", "actor": HERO, "plot": "plot_01", "building_type": "tailor_shop"})
	check(r["ok"], "the order is taken: %s" % r)
	eq(int(sim.state.families[FAM]["gold"]), gold - int(q["price"]), "paid the quote")
	var p := _plot(sim, "plot_01")
	eq(str(p["kind"]), "building", "the plot has its building")
	var bld := str(p["building"])
	eq(str(sim.state.buildings[bld]["state"]), "construction", "under works")
	eq(Titles.businesses(sim, FAM), 1, "works do not count as a business yet")
	eq(str(Plots.can_build(sim, HERO, "plot_01", "tailor_shop")["reason"]), "plot_taken", "nobody builds there now")
	var events := _run_days(sim, float(q["days"]) + 0.05)
	eq(str(sim.state.buildings[bld]["state"]), "normal", "finished after its days")
	check(events.any(func(e: Dictionary) -> bool: return str(e["type"]) == "construction_done" and str(e["building"]) == bld),
		"construction_done")
	eq(Titles.businesses(sim, FAM), 2, "now a second business")
	eq(str(sim.state.buildings[bld]["owner"]), FAM, "the family's")
	check(Plots.free_count(sim, "production") >= 1, "a free production plot is still there")


func test_no_upkeep_while_under_works() -> void:
	var sim := _new()
	_rich(sim)
	check(Orders.apply(sim, {"type": "build", "actor": HERO, "plot": "plot_01", "building_type": "tailor_shop"})["ok"], "build")
	var bld := str(_plot(sim, "plot_01")["building"])
	sim.state.buildings[bld]["construction"]["end"] = int(sim.state.clock["minute"]) + 3 * Clock.MINUTES_PER_DAY
	_run_days(sim, 1.2)
	var paid := 0
	for e: Dictionary in sim.state.ledger["entries"]:
		if str(e.get("building", "")) == bld and str(e.get("category", "")) == "upkeep":
			paid += 1
	eq(paid, 0, "no upkeep for a building under works")


func test_the_valve_stops_the_ai_not_the_player() -> void:
	var sim := _new()
	var rival := "fam_0002"
	_rich(sim, rival)
	var head := Kin.head(sim.state, rival)
	var free := Plots.free_count(sim, "production")
	var min_free := int(cat.construction["valve"]["min_free"])
	eq(free, min_free, "town_e starts with the valve's two free production plots")
	eq(str(Plots.can_build(sim, head, "plot_01", "tailor_shop")["reason"]), "valve", "the AI may not take one of the last two")
	_rich(sim)
	check(Plots.can_build(sim, HERO, "plot_01", "tailor_shop")["ok"], "the player may")


func test_demolish() -> void:
	var sim := _new()
	_rich(sim)
	var forge := str(_plot(sim, "plot_08")["building"])
	eq(str(Plots.can_demolish(sim, HERO, forge)["reason"]), "someone_inside" if str(sim.state.characters[HERO]["location"]) == forge
		else "only_home", "the forge is the family's only roof")
	check(Orders.apply(sim, {"type": "build", "actor": HERO, "plot": "plot_01", "building_type": "tailor_shop"})["ok"], "build")
	var shop := str(_plot(sim, "plot_01")["building"])
	eq(str(Plots.can_demolish(sim, HERO, shop)["reason"]), "under_construction", "not while it is being built")
	_run_days(sim, 2.0)
	var gold := int(sim.state.families[FAM]["gold"])
	var r := Orders.apply(sim, {"type": "demolish", "actor": HERO, "building": shop})
	check(r["ok"], "demolished: %s" % r)
	eq(int(sim.state.families[FAM]["gold"]), gold + roundi(100.0 * 0.4), "40 % of its cost back")
	check(not sim.state.buildings.has(shop), "gone")
	eq(str(_plot(sim, "plot_01")["kind"]), "lot", "the ruin's plot is a free lot now")


func test_convert() -> void:
	var sim := _new()
	_rich(sim)
	var forge := str(_plot(sim, "plot_08")["building"])
	eq(Plots.types_for(sim, _plot(sim, "plot_08")), ["carpentry", "forge", "masonry", "tailor_shop", "tavern_inn"],
		"what fits the forge's 3×4 plot")
	sim.state.characters[HERO]["location"] = ""
	var r := Orders.apply(sim, {"type": "convert_building", "actor": HERO, "building": forge, "building_type": "carpentry"})
	check(r["ok"], "converted: %s" % r)
	eq(str(sim.state.buildings[forge]["type"]), "carpentry", "a carpentry now")
	eq(str(sim.state.buildings[forge]["state"]), "construction", "after its works")
	eq((sim.state.buildings[forge]["upgrades"] as Array).size(), 0, "its upgrades are lost")
	check((sim.state.buildings[forge]["zones"] as Dictionary).has("workbench"), "with the carpentry's stations")


func test_buying_a_business_of_a_npc() -> void:
	var sim := _new()
	_rich(sim)
	var shop := str(_plot(sim, "plot_16")["building"])
	var seller := str(sim.state.buildings[shop]["owner"])
	check(seller != "" and seller != FAM, "the tailor's of plot_16 is an AI family's")
	var head := Kin.head(sim.state, seller)
	Emotions.change_relation(sim, head, HERO, -80 - Emotions.relation(sim.state, head, HERO), "test")
	eq(str(Plots.can_buy_from(sim, HERO, shop)["reason"]), "refuses", "it will not sell to who it hates")
	Emotions.change_relation(sim, head, HERO, 100 - Emotions.relation(sim.state, head, HERO), "test")
	var q := Plots.can_buy_from(sim, HERO, shop)
	check(q["ok"], "it sells to a friend: %s" % q)
	var gold := int(sim.state.families[seller]["gold"])
	check(Orders.apply(sim, {"type": "buy_building", "actor": HERO, "building": shop})["ok"], "bought")
	eq(str(sim.state.buildings[shop]["owner"]), FAM, "the player's now")
	eq(int(sim.state.families[seller]["gold"]), gold + int(q["price"]), "the seller has the gold")
	eq(str(sim.state.families[seller]["after_sale"]["fate"]), "stays", "a friend stays on")
	var cheap := Plots.npc_price(sim, shop, 60)
	var dear := Plots.npc_price(sim, shop, -60)
	check(dear > cheap, "a bad relation costs more (%d > %d)" % [dear, cheap])


func test_nothing_changes_without_building() -> void:
	var a := _new()
	var b := _new()
	b.state.parcels = {}
	_run_days(a, 0.5)
	_run_days(b, 0.5)
	eq(Grid.for_state(cat, a.state), Grid.of(cat, a.state.map_id), "no plot built: the map's grid")
	eq(JSON.stringify(a.state.to_dict()).hash(), JSON.stringify(b.state.to_dict()).hash(), "same game")


func test_the_tavern_counts_for_the_titles_requirements_only() -> void:
	var sim := _new()
	_rich(sim, FAM, 5000, "common")
	var tavern := ""
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b]["type"]) == "tavern_inn":
			tavern = b
	check(Orders.apply(sim, {"type": "buy_building", "actor": HERO, "building": tavern})["ok"], "the tavern bought")
	eq(Titles.businesses(sim, FAM), 1, "the workshops: the forge only (passive reputation, taxes)")
	var need := {}
	for r: Dictionary in Titles.requirements(sim, FAM, "baron"):
		need[str(r["kind"])] = r
	eq(int(need["businesses"]["have"]), 2, "for the title the tavern is a second business (Equilibrio 4)")
