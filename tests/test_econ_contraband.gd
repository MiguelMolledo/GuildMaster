extends "res://tests/test_case.gd"
## Pulido del MVP, arreglo 3: the Secrets «contraband» (forge_secrets_3, GDD 4.8: «beneficio ilegal ×2») doubles what
## the building's counter takes (Counter.price × illegal_profit) [provisional]. Its inspection risk (+15 %) was already
## read by Inspections. Nobody in the bots buys it (it asks for Stealth 5): the targets do not move.

const FAM: String = "fam_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func test_contraband_doubles_the_counter() -> void:
	var sim := Sim.new(NewGame.from_scenario("town_microevents", 1)["state"], cat)
	var st := sim.state
	var before := Counter.price(sim, FORGE, "", "sword", 0, "")
	near(Upgrades.mult(sim, FORGE, "illegal_profit"), 1.0, 0.0001, "no contraband: ×1")
	(st.buildings[FORGE]["upgrades"] as Array).append("forge_secrets_3")
	near(Upgrades.mult(sim, FORGE, "illegal_profit"), 2.0, 0.0001, "contraband: ×2")
	var after := Counter.price(sim, FORGE, "", "sword", 0, "")
	check(absi(after - before * 2) <= 1, "the counter takes twice as much (%d -> %d)" % [before, after])
	eq(Market.price(sim, "sword", 0, "sell"), Market.price(sim, "sword", 0, "sell"), "the market does not change")
	check(Inspections.risk(sim, FORGE) >= 0.15, "and the inspection risk is there (+15 %)")


func test_bots_cannot_buy_it() -> void:
	var sim := Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)["state"], cat)
	var req: Dictionary = cat.upgrade("forge_secrets_3")["requires"]
	check(int(sim.state.characters["chr_0001"]["stats"]["stealth"]) < int(req["stat"]["min"]),
		"Hugo's stealth (2) is below 5: the crook never reaches it (the targets stay)")
