extends "res://tests/test_case.gd"
## H6 · the AI families' construction (docs/gdd/04c_ia_rival.md §4.21.6.2; Construction) and the plot's card
## (PlotCard.data_for): what they could build or buy, the valve and the title limit for them, the dawn's orders, a
## family that sold its workshop puts up another; the card's buttons with their prices and why they are off.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const RIVAL: String = "fam_0002"

var cat := Catalog.load_from()


func _new() -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"], cat)


func _valve(n: int) -> void:
	cat.construction["valve"]["min_free"] = n


func test_the_valve_keeps_the_ai_out_of_the_last_plots() -> void:
	var sim := _new()
	var tailor := str(sim.state.buildings[str(Plots.get_plot(sim, "plot_16")["building"])]["owner"])  # the AI tailor
	sim.state.families[tailor]["title"] = "citizen"
	sim.state.families[tailor]["gold"] = 2000
	var free := Plots.free_count(sim, "production")
	_valve(free)
	for c: Dictionary in Construction.candidates(sim, tailor):
		check(str(c["kind"]) != "build", "no plot to build on while only the valve's are free: %s" % c)
	_valve(free - 1)
	var any := false
	for c: Dictionary in Construction.candidates(sim, tailor):
		if str(c["kind"]) == "build" and str(c["plot"]) == "plot_01":
			any = true
	check(any, "with the valve at one, the ruin is a candidate for the AI tailor (a tailor's fits it)")
	_valve(2)


func test_the_title_limit_holds_for_the_ai() -> void:
	var sim := _new()
	sim.state.families[RIVAL]["gold"] = 2000
	_valve(0)
	eq(Construction.candidates(sim, RIVAL).filter(func(c: Dictionary) -> bool: return str(c["kind"]) == "build"), [],
		"a commoner family with its forge has no room for a second building")
	_valve(2)


func test_a_family_that_sold_its_workshop_builds_another() -> void:
	var sim := _new()
	_valve(0)
	var shop := str(Plots.get_plot(sim, "plot_16")["building"])
	var seller := str(sim.state.buildings[shop]["owner"])
	var head := Kin.head(sim.state, seller)
	sim.state.families[FAM]["gold"] = 5000
	sim.state.families[FAM]["title"] = "citizen"
	Emotions.change_relation(sim, head, HERO, 0 - Emotions.relation(sim.state, head, HERO), "test")
	check(Orders.apply(sim, {"type": "buy_building", "actor": HERO, "building": shop})["ok"], "the player buys it")
	eq(str(sim.state.families[seller]["after_sale"]["fate"]), "rebuilds", "a neutral seller puts up a business elsewhere")
	sim.state.families[seller]["gold"] = 500
	var c := Construction.choose(sim, seller)
	eq(str(c.get("kind", "")), "build", "it chooses to build: %s" % c)
	eq(str(c.get("building_type", "")), "tailor_shop", "its own trade")
	var o := Construction.order_for(sim, seller, c)
	check(Orders.apply(sim, o)["ok"], "and the order is taken: %s" % o)
	_valve(2)


func test_the_dawn_orders_wait_for_first_day() -> void:
	var sim := _new()
	_valve(0)
	sim.state.families[RIVAL]["title"] = "citizen"
	sim.state.families[RIVAL]["gold"] = 5000
	eq(Construction.ai_orders(sim), [], "nothing before construction.json ai.first_day")
	_valve(2)


func test_buying_a_building_for_sale() -> void:
	var sim := _new()
	sim.state.families[RIVAL]["title"] = "citizen"
	sim.state.families[RIVAL]["gold"] = 5000
	var forge := str(Plots.get_plot(sim, "plot_09")["building"])
	var spare := NewGame.make_building(sim.state, cat, "forge", [40, 40], [41, 39], "")
	sim.state.buildings[spare]["for_sale"] = true
	var buys := Construction.candidates(sim, RIVAL).filter(func(c: Dictionary) -> bool: return str(c["kind"]) == "buy")
	eq(buys.size(), 1, "a forge for sale is a candidate for the rival smith")
	eq(str(buys[0]["building"]) if not buys.is_empty() else "", spare, "that one")
	check(forge != spare, "not its own")


func test_the_card_of_a_ruin() -> void:
	var sim := _new()
	sim.state.families[FAM]["gold"] = 1000
	var d := PlotCard.data_for(sim, "plot_01", HERO)
	eq(str(d["title"]), SimQuery.t_("ui.plots.title.ruin"), "a ruin")
	var ids: Array = (d["buttons"] as Array).map(func(b: Dictionary) -> String: return str(b["id"]))
	check(ids.has("build:tailor_shop") and ids.back() == "ok", "restore as the tailor's, or close: %s" % [ids])
	var b: Dictionary = d["buttons"][ids.find("build:tailor_shop")]
	check(bool(b["disabled"]), "off for a commoner with a forge")
	check(str(b["tip"]).contains(str(Titles.max_buildings(sim, FAM))), "it says the title's limit: %s" % b["tip"])
	sim.state.families[FAM]["title"] = "citizen"
	d = PlotCard.data_for(sim, "plot_01", HERO)
	ids = (d["buttons"] as Array).map(func(x: Dictionary) -> String: return str(x["id"]))
	check(not bool(d["buttons"][ids.find("build:tailor_shop")]["disabled"]), "on for a citizen")
	check(str(d["buttons"][ids.find("build:tailor_shop")]["text"]).contains(str(Plots.quote(sim, Plots.get_plot(sim, "plot_01"), "tailor_shop")["price"])),
		"with its price")


func test_the_card_of_the_own_forge_and_of_a_npc_business() -> void:
	var sim := _new()
	sim.state.families[FAM]["gold"] = 1000
	var d := PlotCard.data_for(sim, "plot_08", HERO)
	var ids: Array = (d["buttons"] as Array).map(func(b: Dictionary) -> String: return str(b["id"]))
	check(ids.has("demolish"), "the own forge can be pulled down… %s" % [ids])
	check(bool(d["buttons"][ids.find("demolish")]["disabled"]), "…but not the family's only roof")
	check(ids.has("convert:carpentry"), "or converted")
	d = PlotCard.data_for(sim, "plot_16", HERO)
	ids = (d["buttons"] as Array).map(func(b: Dictionary) -> String: return str(b["id"]))
	eq(ids, ["buy", "ok"], "another family's business: buy it")
	var card := PlotCard.new()
	card.plot = "plot_16"
	card.actor = HERO
	eq(card.order_of(sim, "buy"), {"type": "buy_building", "actor": HERO, "building": str(Plots.get_plot(sim, "plot_16")["building"])},
		"the order of its button")
	card.free()


func test_a_second_building_waits_for_the_ai_economy() -> void:
	var sim := _new()
	sim.state.families[RIVAL]["title"] = "citizen"
	sim.state.families[RIVAL]["gold"] = 3000
	cat.construction["ai"]["expand"] = false
	eq(Construction.choose(sim, RIVAL), {}, "ai.expand off: a family with its forge builds no second one")
	cat.construction["ai"]["expand"] = true
	var c := Construction.choose(sim, RIVAL)
	eq(str(c.get("plot", "")), "plot_21", "ai.expand on: the rival smith's second forge on the 3×4 lot north of the lane")
	eq(str(c.get("building_type", "")), "forge", "a forge")
	check(Plots.free_count(sim, "production") - 1 >= int(cat.construction["valve"]["min_free"]), "the valve still holds")
	cat.construction["ai"]["expand"] = false
