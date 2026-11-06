extends "res://tests/test_case.gd"
## The countryside's clientele (docs/gdd/04g_interiores.md 4.6.5.7, sim/town/clientele.gd): off by default (today's
## targets do not move); on, they come to a counter that sells, are served by whoever holds the counter, pay with gold
## from outside up to their maximum price, leave when nobody serves them, and the whole thing is deterministic and
## survives a save and load.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()


func _sim(on: bool) -> Sim:
	var c := Catalog.load_from()
	c.town["counter"]["clientele"]["enabled"] = on
	var sim := Sim.new(NewGame.from_scenario("town_e_start")["state"], c)
	check(Upgrades.complete(sim, BLD, "forge_commerce_1"), "setup: the forge sells at its counter")
	check(Inventory.add(sim.state.buildings[BLD]["inventory"], c, "sword", 1, 6), "setup: six swords for sale")
	return sim


func _to_day(sim: Sim) -> void:
	var cfg: Dictionary = sim.catalog.town["counter"]
	var guard := 0
	while not (Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time) in (cfg.get("phases", ["day"]) as Array)) \
			and guard < 1440:
		sim.step()
		guard += 1


func _run(sim: Sim, minutes: int) -> Array:
	var ev: Array = []
	for i: int in minutes:
		ev.append_array(sim.step())
	return ev


func test_on_in_data_and_off_brings_nobody() -> void:
	# Equilibrio 14 (2026-11-06): on for the forge in data; switched off, nobody comes from the countryside
	check(bool(cat.town["counter"]["clientele"]["enabled"]), "data/town.json: counter.clientele.enabled true (Equilibrio 14)")
	var sim := _sim(false)
	_to_day(sim)
	var ev := _run(sim, 600)
	check(not ev.any(func(e: Dictionary) -> bool: return bool(e.get("clientele", false))), "nobody from the countryside")
	check(Clientele.waiting(sim.state, BLD).is_empty(), "no record in the state")


func test_they_come_and_buy_at_the_counter() -> void:
	var sim := _sim(true)
	_to_day(sim)
	check(Clientele.per_day(sim, BLD) > 0.0, "the forge draws some a day (%.2f)" % Clientele.per_day(sim, BLD))
	var st := sim.state
	st.characters[HUGO]["location"] = BLD
	sim.step([{"type": "go_to_station", "actor": HUGO, "zone": "counter"}])
	var fam := str(st.buildings[BLD]["owner"])
	var gold0 := int(st.families[fam]["gold"])
	var swords0 := Inventory.count(st.buildings[BLD]["inventory"], "sword")
	var ev := _run(sim, 600)
	var arrived := ev.filter(func(e: Dictionary) -> bool: return e["type"] == "customer_arrived" and bool(e.get("clientele", false)))
	var sold := ev.filter(func(e: Dictionary) -> bool: return e["type"] == "counter_sold" and bool(e.get("clientele", false)))
	check(arrived.size() > 0, "countryside customers came (%d)" % arrived.size())
	check(sold.size() > 0, "and bought (%d)" % sold.size())
	for e: Dictionary in sold:
		check(int(e["price"]) <= Clientele.max_price(sim, BLD, str(e["item"]), int(e["quality"])), "within its maximum price")
	var paid := 0
	for e: Dictionary in sold:
		paid += int(e["price"])
	var all_sold := ev.filter(func(e: Dictionary) -> bool: return e["type"] == "counter_sold" and str(e["item"]) == "sword")
	eq(Inventory.count(st.buildings[BLD]["inventory"], "sword"), swords0 - all_sold.size(),
		"a sword out of the storage per sale (the townsfolk's and the countryside's)")
	check(int(st.families[fam]["gold"]) >= gold0 + paid - 400, "the family is paid (gold from outside)")


func test_nobody_serves_them_and_they_leave() -> void:
	var sim := _sim(true)
	_to_day(sim)
	var ev := _run(sim, 600)
	var left := ev.filter(func(e: Dictionary) -> bool: return e["type"] == "customer_left" and bool(e.get("clientele", false)))
	check(left.size() > 0 and left.all(func(e: Dictionary) -> bool: return str(e["reason"]) in ["nobody", "closed"]),
		"with nobody at the counter they go away (%d)" % left.size())
	check(not ev.any(func(e: Dictionary) -> bool: return e["type"] == "counter_sold" and bool(e.get("clientele", false))),
		"and buy nothing")


func test_deterministic_and_saved() -> void:
	var a := _sim(true)
	var b := _sim(true)
	_to_day(a)
	_to_day(b)
	var ea := _run(a, 300)
	var eb := _run(b, 300)
	eq(SaveFile.canonical({"e": ea}), SaveFile.canonical({"e": eb}), "the same game gives the same customers")
	check(a.state.town.has("clientele"), "their records live in the state (town.clientele)")
	var back: WorldState = SaveFile.from_text(JSON.stringify(a.state.to_dict()))["state"]
	eq(SaveFile.canonical(back.town.get("clientele", {})), SaveFile.canonical(a.state.town["clientele"]),
		"and come back after a save and load")
	var c := a.catalog
	var sim2 := Sim.new(back, c)
	var e2 := _run(sim2, 120)
	var e1 := _run(a, 120)
	eq(SaveFile.canonical({"e": e2}), SaveFile.canonical({"e": e1}), "the loaded game goes on the same")
