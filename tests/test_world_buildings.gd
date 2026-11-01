extends "res://tests/test_case.gd"
## Entering, leaving and stations of a building (GDD 4.6.4; docs/contratos/h2_forja.md): walk to the door and go in,
## refusals, move_to while inside, leaving puts you on the door, stations free/busy, leaving interrupts the work (D11).

var cat := Catalog.load_from()

const HUGO := "chr_0001"
const ELENA := "chr_0002"
const MARTA := "chr_0004"  # another family
const FORGE := "bld_0001"


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)


func _chr(sim: Sim, id: String) -> Dictionary:
	return sim.state.characters[id]


func _of_type(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _refusal(events: Array) -> String:
	var r := _of_type(events, "order_refused")
	return str(r[0]["reason"]) if r.size() == 1 else "none %s" % str(r)


## Steps until `cond` holds or `max` minutes pass; collects the events.
func _run_until(sim: Sim, cond: Callable, max_min: int = 120) -> Array:
	var all: Array = []
	for i: int in max_min:
		all.append_array(sim.step())
		if cond.call():
			break
	return all


func _put_inside(sim: Sim, id: String) -> void:
	var door: Array = sim.state.buildings[FORGE]["door"]
	_chr(sim, id)["position"] = [int(door[0]), int(door[1])]
	sim.step([{"type": "enter_building", "actor": id, "building": FORGE}])


func test_walks_to_the_door_and_enters() -> void:
	var sim := _sim()
	var ev := sim.step([{"type": "enter_building", "actor": HUGO, "building": FORGE}])
	eq(_of_type(ev, "order_refused").size(), 0, "accepted")
	check(not (_chr(sim, HUGO)["path"] as Array).is_empty(), "walking")
	eq(str(_chr(sim, HUGO)["location"]), "", "still outside while walking")
	eq(str((_chr(sim, HUGO)["order_queue"] as Array)[0]["type"]), "enter_building", "the entry waits first in the queue")
	var all := _run_until(sim, func() -> bool: return str(_chr(sim, HUGO)["location"]) == FORGE)
	eq(str(_chr(sim, HUGO)["location"]), FORGE, "inside")
	eq(str(_chr(sim, HUGO)["station"]), "", "no station yet")
	eq(_chr(sim, HUGO)["position"], sim.state.buildings[FORGE]["door"], "came in through the door")
	eq((_chr(sim, HUGO)["order_queue"] as Array).size(), 0, "queue empty after entering")
	var entered := _of_type(all, "building_entered")
	check(entered.size() == 1 and entered[0]["actor"] == HUGO and entered[0]["building"] == FORGE, "event")
	# The arrival and the entry happen in the same minute.
	var arrived := all.find(_of_type(all, "character_arrived")[0])
	check(arrived >= 0 and all.find(entered[0]) > arrived, "entered right on arrival")


func test_enters_at_once_from_the_door() -> void:
	var sim := _sim()
	var door: Array = sim.state.buildings[FORGE]["door"]
	_chr(sim, HUGO)["position"] = [int(door[0]), int(door[1])]
	var ev := sim.step([{"type": "enter_building", "actor": HUGO, "building": FORGE}])
	eq(str(_chr(sim, HUGO)["location"]), FORGE, "inside in the same minute")
	eq(_of_type(ev, "building_entered").size(), 1, "event")


func test_can_enter_and_refusals() -> void:
	var sim := _sim()
	check(Buildings.can_enter(sim, HUGO, FORGE)["ok"], "own family's forge")
	eq(str(Buildings.can_enter(sim, MARTA, FORGE)["reason"]), "not_your_building", "another family's")
	eq(str(Buildings.can_enter(sim, HUGO, "bld_0099")["reason"]), "unknown_building", "missing building")
	eq(str(Buildings.can_enter(sim, "chr_0099", FORGE)["reason"]), "unknown_actor", "missing actor")
	_chr(sim, ELENA)["alive"] = false
	eq(str(Buildings.can_enter(sim, ELENA, FORGE)["reason"]), "dead", "dead")
	var ev := sim.step([{"type": "enter_building", "actor": MARTA, "building": FORGE}])
	eq(_refusal(ev), "not_your_building", "refused order")
	eq((_chr(sim, MARTA)["path"] as Array).size(), 0, "Marta does not walk")


func test_inside_does_not_walk_the_map() -> void:
	var sim := _sim()
	_put_inside(sim, HUGO)
	var ev := sim.step([{"type": "move_to", "actor": HUGO, "tile": [20, 21]}])
	eq(_refusal(ev), "not_inside_map", "move_to refused inside")
	eq((_chr(sim, HUGO)["path"] as Array).size(), 0, "no route")


func test_exit_puts_on_the_door() -> void:
	var sim := _sim()
	var ev := sim.step([{"type": "exit_building", "actor": HUGO}])
	eq(_refusal(ev), "not_inside", "cannot leave from outside")
	_put_inside(sim, HUGO)
	sim.step([{"type": "go_to_station", "actor": HUGO, "zone": "anvil"}])
	_chr(sim, HUGO)["position"] = [0, 0]  # wherever: leaving puts it on the door
	ev = sim.step([{"type": "exit_building", "actor": HUGO}])
	eq(str(_chr(sim, HUGO)["location"]), "", "on the map")
	eq(str(_chr(sim, HUGO)["station"]), "", "no station")
	eq(_chr(sim, HUGO)["position"], sim.state.buildings[FORGE]["door"], "on the door")
	eq(str(sim.state.buildings[FORGE]["zones"]["anvil"]["occupant"]), "", "station freed")
	eq(_of_type(ev, "building_left").size(), 1, "event")
	ev = sim.step([{"type": "move_to", "actor": HUGO, "tile": [20, 21]}])
	eq(_of_type(ev, "order_refused").size(), 0, "walks again once outside")


func test_stations_free_and_busy() -> void:
	var sim := _sim()
	var ev := sim.step([{"type": "go_to_station", "actor": HUGO, "zone": "anvil"}])
	eq(_refusal(ev), "not_inside", "only inside")
	_put_inside(sim, HUGO)
	_put_inside(sim, ELENA)
	ev = sim.step([{"type": "go_to_station", "actor": HUGO, "zone": "chimney"}])
	eq(_refusal(ev), "unknown_station", "missing station")
	ev = sim.step([{"type": "go_to_station", "actor": HUGO, "zone": "anvil"}])
	eq(str(_chr(sim, HUGO)["station"]), "anvil", "at the anvil")
	eq(str(sim.state.buildings[FORGE]["zones"]["anvil"]["occupant"]), HUGO, "occupant")
	var taken := _of_type(ev, "station_taken")
	check(taken.size() == 1 and taken[0]["zone"] == "anvil" and taken[0]["building"] == FORGE, "event")
	ev = sim.step([{"type": "go_to_station", "actor": HUGO, "zone": "anvil"}])
	eq(_of_type(ev, "order_refused").size(), 0, "its own station again is fine")
	ev = sim.step([{"type": "go_to_station", "actor": ELENA, "zone": "anvil"}])
	eq(_refusal(ev), "station_busy", "taken by Hugo")
	sim.step([{"type": "go_to_station", "actor": HUGO, "zone": "furnace"}])
	eq(str(sim.state.buildings[FORGE]["zones"]["anvil"]["occupant"]), "", "old station freed")
	eq(str(sim.state.buildings[FORGE]["zones"]["furnace"]["occupant"]), HUGO, "new station")
	ev = sim.step([{"type": "go_to_station", "actor": ELENA, "zone": "anvil"}])
	eq(str(_chr(sim, ELENA)["station"]), "anvil", "now Elena can")


func test_leaving_interrupts_the_work() -> void:
	var sim := _sim()
	_put_inside(sim, HUGO)
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	var iron := Inventory.count(inv, "iron")
	var ev := sim.step([{"type": "work_at", "actor": HUGO, "building": FORGE, "zone": "furnace",
		"recipe": "forge_ingot", "mode": "normal"}])
	eq(_of_type(ev, "order_refused").size(), 0, "working (%s)" % str(_of_type(ev, "order_refused")))
	eq(Buildings.job_zone(sim, HUGO), "furnace", "job at the furnace")
	check(Inventory.count(inv, "iron") < iron, "inputs taken")
	ev = sim.step([{"type": "exit_building", "actor": HUGO}])
	eq(_of_type(ev, "work_interrupted").size(), 1, "interrupted (D11)")
	eq(Inventory.count(inv, "iron"), iron, "inputs back in the storage")
	eq(Buildings.job_zone(sim, HUGO), "", "no job")
	check(sim.state.buildings[FORGE]["zones"]["furnace"]["job"] == null, "station clear")


func test_changing_station_interrupts_the_work() -> void:
	var sim := _sim()
	_put_inside(sim, HUGO)
	sim.step([{"type": "work_at", "actor": HUGO, "building": FORGE, "zone": "furnace", "recipe": "forge_ingot",
		"mode": "normal"}])
	var ev := sim.step([{"type": "go_to_station", "actor": HUGO, "zone": "counter"}])
	eq(_of_type(ev, "work_interrupted").size(), 1, "interrupted")
	eq(str(sim.state.buildings[FORGE]["zones"]["furnace"]["occupant"]), "", "furnace freed")
	eq(str(_chr(sim, HUGO)["station"]), "counter", "at the counter")


func test_save_round_trip_with_someone_inside() -> void:
	var sim := _sim()
	_put_inside(sim, HUGO)
	sim.step([{"type": "go_to_station", "actor": HUGO, "zone": "anvil"}])
	sim.step([{"type": "enter_building", "actor": ELENA, "building": FORGE}])  # Elena walking to the door
	var path := "user://test_world_buildings.json"
	eq(SaveFile.save(sim.state, path), OK, "saved")
	var r := SaveFile.load_file(path)
	check(r["ok"], "loaded")
	var other := Sim.new(r["state"], cat)
	eq(other.state_hash(), sim.state_hash(), "same state after loading")
	sim.run_minutes(60)
	other.run_minutes(60)
	eq(other.state_hash(), sim.state_hash(), "same game when going on")
	eq(str(other.state.characters[ELENA]["location"]), FORGE, "Elena got in after the load")
	eq(str(other.state.characters[HUGO]["station"]), "anvil", "Hugo still at the anvil")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
