extends "res://tests/test_case.gd"
## Equilibrio (2026-11-06): the Taberna-Posada is sold with what the last keeper left in the larder (sale_stock).

var cat := Catalog.load_from()


func test_bought_with_its_larder() -> void:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], cat)
	var sale := ""
	for b: String in sim.state.buildings:
		if bool(sim.state.buildings[b].get("for_sale", false)) and Inn.is_inn(sim, b):
			sale = b
	check(sale != "", "a tavern for sale")
	sim.state.families["fam_0001"]["gold"] = 1000
	eq(Orders.apply(sim, {"type": "buy_building", "actor": "chr_0001", "building": sale})["ok"], true, "bought")
	var inv: Dictionary = sim.state.buildings[sale]["inventory"]
	for line: Dictionary in cat.buildings()["tavern_inn"]["sale_stock"]:
		eq(Inventory.count(inv, str(line["item"])), int(line["qty"]), "%s in the larder" % line["item"])
