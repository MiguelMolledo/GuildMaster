extends "res://tests/test_case.gd"
const Pins = preload("res://tests/balance_pins.gd")
## Pending «Empleado "cualquiera" ocioso puede bloquear un puesto a otro de rol fijo» (docs/decisiones.json
## proximos_pasos): after a cycle an employee stays at its station (Production keeps the occupant), so an idle «any»
## hand left at the only anvil kept the anvil smith out. Here Agnès («any», craft 2) stands idle at the anvil; the
## queue has only a sword (craft 4) whose ingots are in the storage: only Joan (role anvil, craft 5) can make it.

const FORGE: String = "bld_0001"
const PLAYER: String = "chr_0001"
const JOAN: String = "chr_0007"    # journeyman, craft 5
const AGNES: String = "chr_0008"   # apprentice, craft 2

var cat := Pins.classic(Catalog.load_from())


func _setup(entries: Array, stock: Dictionary) -> Sim:
	var sim := Sim.new(NewGame.from_scenario("two_employees", 1)["state"], cat)
	var st := sim.state
	var b: Dictionary = st.buildings[FORGE]
	b["inventory"]["stacks"] = []
	for item: String in stock:
		Inventory.add(b["inventory"], cat, item, 0, int(stock[item]))
	b["queue"] = {"entries": [], "loop": false, "paused": false}
	for e: Array in entries:
		eq(Orders.apply(sim, {"type": "queue_add", "actor": PLAYER, "building": FORGE, "recipe": e[0], "qty": e[1]}),
			Orders.ok(), "queue_add %s" % e[0])
	st.characters[JOAN]["job"]["role"] = "anvil"
	st.characters[AGNES]["job"]["role"] = "any"
	return sim


## Agnès at the anvil, idle (as after a horseshoe of hers).
func _agnes_at_the_anvil(sim: Sim) -> void:
	var zones: Dictionary = sim.state.buildings[FORGE]["zones"]
	for z: String in zones:
		if str(zones[z].get("occupant", "")) == AGNES:
			zones[z]["occupant"] = ""
	zones["anvil"]["occupant"] = AGNES
	sim.state.characters[AGNES]["station"] = "anvil"


func _started(events: Array, who: String, zone: String = "") -> Array:
	return events.filter(func(e: Dictionary) -> bool:
		return str(e["type"]) == "work_started" and str(e.get("actor", "")) == who \
			and (zone == "" or str(e.get("zone", "")) == zone))


func _run(sim: Sim, minutes: int) -> Array:
	var all: Array = []
	for i: int in minutes:
		all.append_array(sim.step())
	return all


func test_an_idle_any_hand_yields_the_anvil_to_the_anvil_smith() -> void:
	var sim := _setup([["forge_sword", 1]], {"iron_ingot": 2, "coal": 1})
	_agnes_at_the_anvil(sim)
	var ev := _run(sim, 480)
	check(not _started(ev, JOAN, "anvil").is_empty(), "Joan (anvil, craft 5) gets the anvil and forges the sword")
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword"), 1, "the sword is made")
	check(str(sim.state.buildings[FORGE]["zones"]["anvil"].get("occupant", "")) != AGNES or _started(ev, AGNES).size() > 0,
		"Agnès left the anvil to him")


func test_the_any_hand_keeps_the_anvil_when_it_works_there() -> void:
	# A hammer (craft 2) and a sword: Agnès forges the hammer at the anvil she holds; Joan waits for it, then forges.
	var sim := _setup([["forge_hammer", 1], ["forge_sword", 1]], {"iron_ingot": 3, "coal": 2})
	_agnes_at_the_anvil(sim)
	var ev := _run(sim, 960)
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "hammer"), 1, "the hammer")
	eq(Inventory.count(sim.state.buildings[FORGE]["inventory"], "sword"), 1, "and the sword")
	var interrupted := ev.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "work_interrupted")
	eq(interrupted, [], "nobody's work is cut short to make room")
