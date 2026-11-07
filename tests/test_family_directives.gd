extends "res://tests/test_case.gd"
## H14 directives (GDD 4.10.6; docs/contratos/h14_ia_familiar.md). The criterion: a family member with «Trade»
## supplies the forge on its own (only with the player's orders: buy, transfer...). The order of the directives is
## the priority; the needs come first; work in normal mode, no master touch; learn is off.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim(id: String, s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, s)["state"], cat)


## Criterion of H14: nobody gives an order and, by the end of the first market day, the forge has iron and coal.
func test_a_trader_supplies_the_forge() -> void:
	for s: int in [1, 2, 3]:
		var sim := _sim("kin_trader", s)
		var st := sim.state
		var wife := str(st.characters[HERO]["spouse"])
		var types := {}
		var refused := 0
		for i: int in 12 * 60:
			for e: Dictionary in sim.step([]):
				if str(e["type"]) == "order_refused" and str(e["actor"]) == wife:
					refused += 1
				if str(e["type"]) in ["market_bought", "items_moved"] and str(e.get("actor", "")) == wife:
					types[str(e["type"])] = true
		var inv: Dictionary = st.buildings[FORGE]["inventory"]
		check(Inventory.count(inv, "iron") > 0 or Inventory.count(inv, "ingot") > 0, "seed %d: iron in the forge" % s)
		check(types.has("market_bought") and types.has("items_moved"), "seed %d: bought at the market and carried home" % s)
		eq(refused, 0, "seed %d: no refused orders (the same orders as the player, checked first)" % s)
		var notes := st.notices.map(func(n: Dictionary) -> String: return str(n.get("key", "")))
		check("notice.kin_supplied" in notes, "seed %d: the player is told" % s)


func test_order_is_priority() -> void:
	var sim := _sim("kin_trader")
	var st := sim.state
	var wife := str(st.characters[HERO]["spouse"])
	st.characters[wife]["directives"] = ["work", "trade"]
	var bought := false
	for i: int in 4 * 60:
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "market_bought" and str(e["actor"]) == wife:
				bought = true
	check(bought, "work first, but nothing to work with: trade comes next")
	st.characters[wife]["directives"] = []
	eq(Orders.apply(sim, {"type": "set_directives", "actor": HERO, "character": wife, "directives": ["learn"]})["reason"],
		"directive_not_ready", "learn is off (EA)")
	eq(Orders.apply(sim, {"type": "set_directives", "actor": HERO, "character": wife, "directives": ["trade", "trade"]})[
		"reason"], "bad_directives", "no repeats")
	check(Orders.apply(sim, {"type": "set_directives", "actor": HERO, "character": wife,
		"directives": ["socialize", "leisure", "work"]})["ok"], "the player orders them")


func test_needs_come_first() -> void:
	var sim := _sim("kin_tired")
	var st := sim.state
	var wife := str(st.characters[HERO]["spouse"])
	sim.run_minutes(90)
	eq(str(st.characters[wife]["ai"].get("doing", "")), "eat", "hungry and tired: home to eat before trading")
	eq(str(st.characters[wife]["ai"].get("why", "")), "need_hunger", "because of hunger, the lowest")
	eq(Inventory.count(st.buildings[FORGE]["inventory"], "iron"), 0, "no trading meanwhile")


func test_socialize_and_leisure() -> void:
	var sim := _sim("kin_trader")
	var st := sim.state
	var wife := str(st.characters[HERO]["spouse"])
	st.characters[wife]["directives"] = ["socialize"]
	st.clock["minute"] = 9 * Clock.MINUTES_PER_DAY + 18 * 60  # the townsfolk are out
	var talked := false
	for i: int in 3 * 60:
		for e: Dictionary in sim.step([]):
			if str(e["type"]) == "npc_action" and str(e["actor"]) == wife and str(e["action"]) == "talk":
				talked = true
	check(talked, "socialize: talks to a townsperson (npc_talk)")
	st.characters[wife]["directives"] = ["leisure"]
	st.clock["minute"] = 10 * Clock.MINUTES_PER_DAY + 9 * 60  # daytime again (at night an AI spouse rests)
	var sat := false
	for i: int in 3 * 60:
		sim.step([])
		if str(st.characters[wife]["ai"].get("leisure_at", "")) != "":
			sat = true
	check(sat, "leisure: on a bench of the plaza")
