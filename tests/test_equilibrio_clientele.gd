extends "res://tests/test_case.gd"
## Equilibrio 14 (docs/decisiones.json): one clientele of the countryside for the shops and the Taberna-Posada; its
## fame(b) is the workshop's fame (Equilibrio 13) or the tavern's own.

const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"], cat)


func test_on_for_the_forge() -> void:
	check(Clientele.enabled(_sim()), "the clientele is on")
	eq(float(cat.town["counter"]["clientele"]["base_per_day"]["forge"]) > 0.0, true, "measured for the forge")


func test_fame_is_the_workshops() -> void:
	var sim := _sim()
	eq(Clientele.fame(sim, FORGE), 1.0, "1 at the start")
	WorkshopFame.add(sim, FORGE, "masterwork")
	near(Clientele.fame(sim, FORGE), WorkshopFame.of(sim, FORGE), 0.0001, "the workshop's fame")
	check(Clientele.max_price(sim, FORGE, "sword", 0) > roundi(float(cat.item("sword")["base_price"]) * 1.1),
		"a famous workshop's customers pay more")


func test_one_formula_for_shop_and_inn() -> void:
	var sim := Sim.new(NewGame.from_scenario("innkeeper_start", 1)["state"], cat)
	var tav := ""
	for b: String in sim.state.buildings:
		if Inn.is_inn(sim, b):
			tav = b
	check(tav != "", "a tavern")
	var a := Clientele.provider_appeal(sim, tav, 1.2, "inn_customers")
	near(InnClientele.provider_share(sim, tav, 1.2), a / (a + float(cat.services["no_go"])), 0.0001,
		"the inn's share is the shared appeal over the no_go")
	near(Clientele.fame(sim, tav), Inn.fame(sim, tav), 0.0001, "the tavern's fame")
