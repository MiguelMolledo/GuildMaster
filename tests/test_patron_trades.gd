extends "res://tests/test_case.gd"
## H12 Patrón · the miller, the baker and the butcher (docs/gdd/04d_otras_clases.md 4.22.4.4-4.22.4.9, 4.22.7): their
## starts (the trade's building on the player's plot, 150 gold, no debt) are bot starts kept off the new game screen;
## the chain wheat → flour → bread / pie and pig → meat → sausage; the pig bought for the butchery waits in its storage
## (it has no pen); the demand weights of the patron's goods; and the farm panel's sowing calendar (FarmPanel.strip).

const FAM := "fam_0001"
const HERO := "chr_0001"
const BLD := "bld_0001"

var cat := Catalog.load_from()


func _sim(start: String) -> Sim:
	var r := NewGame.from_start(cat, start, "normal", {"cast": "fixed"}, 1)
	check(bool(r["ok"]), "%s starts" % start)
	return Sim.new(r["state"], cat)


func test_the_three_starts() -> void:
	for pair: Array in [["patron_miller", "mill", "millstone"], ["patron_baker", "bakery", "oven"],
			["patron_butcher", "butchery", "chopping_block"]]:
		var sim := _sim(str(pair[0]))
		eq(str(sim.state.buildings[BLD]["type"]), str(pair[1]), "%s: the %s on the player's plot" % pair.slice(0, 2))
		check((sim.state.buildings[BLD]["zones"] as Dictionary).has(str(pair[2])), "%s: its station" % pair[2])
		eq(Money.gold(sim.state, FAM), 150, "%s: 150 gold" % pair[0])
		check(Loans.of_family(sim, FAM).is_empty(), "%s: no debt" % pair[0])


func test_bot_trades_stay_off_the_new_game_screen() -> void:
	for p: String in ["miller", "baker", "butcher"]:
		check(not bool(cat.professions()[p].get("new_game", true)), "%s: not offered in a new game" % p)
	check(bool(cat.professions().get("farmer", {}).get("new_game", true)), "the farmer is")


func test_the_chain_recipes() -> void:
	var r := cat.recipes()
	eq(_io(r["mill_flour"]), {"in": {"wheat": 2}, "out": {"flour": 1}}, "the mill: wheat ×2 → flour")
	eq(_io(r["bakery_bread"])["out"], {"bread": 6}, "the oven: bread ×6 [balance]")
	check(_io(r["bakery_bread"])["in"].has("flour"), "bread takes flour")
	eq(_io(r["butcher_cut"]), {"in": {"pig": 1}, "out": {"meat": 6}}, "the block: a pig → meat ×6")
	eq(float(r["butcher_cut"]["duration_hours"]), 1.5, "the cut takes 1.5 h [balance]")
	check(_io(r["butcher_sausage"])["in"].has("meat"), "the sausage takes meat")


func _io(rec: Dictionary) -> Dictionary:
	var i := {}
	for x: Dictionary in rec.get("inputs", []):
		i[str(x["item"])] = int(x["qty"])
	var o := {}
	var out: Dictionary = rec.get("output", {})
	if not out.is_empty():
		o[str(out["item"])] = int(out["qty"])
	return {"in": i, "out": o}


func test_the_demand_weights() -> void:
	for item: String in ["flour", "meat"]:
		near(cat.demand_weight(item), 0.2, 0.0001, "%s weighs 0.2" % item)
	for item: String in ["bread", "ale", "meat_pie", "sausage"]:
		near(cat.demand_weight(item), 0.25, 0.0001, "%s weighs 0.25" % item)
	eq(int(cat.items()["flour"]["base_price"]), 15, "flour at 15 (P10)")


func test_a_pig_bought_for_the_butchery_waits_in_its_storage() -> void:
	var sim := _sim("patron_butcher")
	var st := sim.state
	st.clock["minute"] = 600
	st.characters[HERO]["location"] = ""
	st.characters[HERO]["position"] = (sim.catalog.maps()["town_e"]["stalls"]["livestock"]["service"] as Array).duplicate()
	var res := Orders.apply(sim, {"type": "buy", "actor": HERO, "stall": "livestock", "item": "pig",
		"quality": Inventory.NORMAL, "qty": 1, "deliver_to": BLD})
	check(bool(res["ok"]), "the pig is sent to the butchery: %s" % res.get("reason", ""))


func test_the_sowing_calendar() -> void:
	var sim := Sim.new(NewGame.from_start(cat, "patron_farmer", "normal", {"cast": "fixed"}, 1)["state"], cat)
	var f := Fields.field(sim.state, BLD, "field_a")
	f.merge({"state": "growing", "crop": "wheat", "growth": 0.0, "sown_day": 0}, true)
	var panel: FarmPanel = (load("res://game/ui/farm_panel.tscn") as PackedScene).instantiate()
	panel.setup(sim, BLD)
	var s := panel.strip()
	eq(s.size(), FarmPanel.STRIP_DAYS, "eight days")
	eq(str(s[0]["season"]), "spring", "day 1 is spring")
	eq(int(s[0]["sow"]["wheat"]), 4, "sown today, ready on day index 4 (the dawn of day 5)")
	eq(int(s[0]["sow"]["wheat"]), Fields.sow_preview(sim, "wheat"), "the same as the field's menu")
	check("field_a" in (s[4]["ready"] as Array), "field A is marked ready on its day")
	for cell: Dictionary in s:
		if str(cell["season"]) in ["autumn", "winter"]:
			check((cell["sow"] as Dictionary).is_empty(), "no wheat sowing in %s" % cell["season"])
	var body := panel.get_node("%Body") as VBoxContainer
	check(body.get_child_count() > 6, "the panel lists the calendar, the fields and the pen")
	panel.free()
