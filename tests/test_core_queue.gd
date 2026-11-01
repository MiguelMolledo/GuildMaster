extends "res://tests/test_case.gd"
## Active pause (GDD 4.1; docs/contratos/h2_forja.md): orders given in pause are marked queued, wait in the actor's
## order_queue and start in order when it is free; a live order empties the queue; a job ends at its cycle when
## orders wait; save/load with a pending queue goes on the same.

const GameScript := preload("res://game/autoload/game.gd")

var cat := Catalog.load_from()

const HUGO := "chr_0001"
const ELENA := "chr_0002"
const FORGE := "bld_0001"


func _game() -> Node:
	var g: Node = GameScript.new()
	g.start(NewGame.from_scenario("town_e_start", 1)["state"], cat)
	return g


func _sim() -> Sim:
	var st: WorldState = NewGame.from_scenario("town_e_start", 1)["state"]
	st.families["fam_0003"]["ai_profile"] = ""  # the rival smith (H3) off: these tests count one actor's events
	return Sim.new(st, cat)


func _chr(sim: Sim, id: String) -> Dictionary:
	return sim.state.characters[id]


func _of_type(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Runs whole sim minutes through Game (as the real game does), collecting the events.
func _minutes(g: Node, n: int) -> Array:
	var all: Array = []
	for i: int in n:
		var orders: Array = g.call("pending")
		g.set("_pending", [])
		all.append_array((g.get("sim") as Sim).step(orders))
	return all


func test_give_in_pause_marks_queued() -> void:
	var g := _game()
	g.give({"type": "wait", "actor": HUGO})
	check(not (g.pending()[0] as Dictionary).has("queued"), "live: not queued")
	g.set_paused(true)
	g.give({"type": "wait", "actor": HUGO})
	check(bool((g.pending()[1] as Dictionary).get("queued", false)), "in pause: queued")
	g.free()


func test_three_orders_in_pause_run_in_order() -> void:
	var g := _game()
	var sim: Sim = g.sim
	var door: Array = sim.state.buildings[FORGE]["door"]
	g.set_paused(true)
	g.give({"type": "move_to", "actor": HUGO, "tile": [int(door[0]) - 2, int(door[1])]})
	g.give({"type": "enter_building", "actor": HUGO, "building": FORGE})
	g.give({"type": "go_to_station", "actor": HUGO, "zone": "anvil"})
	eq(int(sim.state.clock["minute"]), 480, "nothing ran in pause")
	g.set_paused(false)
	var ev := _minutes(g, 1)
	eq(_of_type(ev, "order_queued").size(), 3, "three queued")
	var started := _of_type(ev, "order_started")
	check(started.size() == 1 and started[0]["order"]["type"] == "move_to", "the first starts")
	eq((_chr(sim, HUGO)["order_queue"] as Array).size(), 2, "two wait")
	ev.append_array(_minutes(g, 120))
	eq(str(_chr(sim, HUGO)["location"]), FORGE, "inside")
	eq(str(_chr(sim, HUGO)["station"]), "anvil", "at the anvil")
	eq((_chr(sim, HUGO)["order_queue"] as Array).size(), 0, "queue empty")
	var types: Array = _of_type(ev, "order_started").map(func(e: Dictionary) -> String: return str(e["order"]["type"]))
	eq(types, ["move_to", "enter_building", "go_to_station"], "in order")
	# The view sees each step happen after the previous one finished.
	var arrived := ev.find(_of_type(ev, "character_arrived")[0])
	var entered := ev.find(_of_type(ev, "building_entered")[0])
	var taken := ev.find(_of_type(ev, "station_taken")[0])
	check(arrived < entered and entered < taken, "walk, then enter, then station")
	eq(_of_type(ev, "order_refused").size(), 0, "nothing refused")
	g.free()


func test_live_order_empties_the_queue() -> void:
	var sim := _sim()
	sim.step([{"type": "move_to", "actor": HUGO, "tile": [26, 19], "queued": true},
		{"type": "enter_building", "actor": HUGO, "building": FORGE, "queued": true},
		{"type": "go_to_station", "actor": HUGO, "zone": "anvil", "queued": true}])
	eq((_chr(sim, HUGO)["order_queue"] as Array).size(), 2, "two waiting")
	sim.step([{"type": "move_to", "actor": HUGO, "tile": [20, 21]}])
	eq((_chr(sim, HUGO)["order_queue"] as Array).size(), 0, "live order empties the queue")
	sim.run_minutes(60)
	eq(str(_chr(sim, HUGO)["location"]), "", "never entered")
	eq(_chr(sim, HUGO)["position"], [20, 21], "went where the live order said")


func test_live_order_cancels_a_walking_entry() -> void:
	var sim := _sim()
	sim.step([{"type": "enter_building", "actor": HUGO, "building": FORGE}])
	sim.step([{"type": "move_to", "actor": HUGO, "tile": [20, 21]}])
	sim.run_minutes(60)
	eq(str(_chr(sim, HUGO)["location"]), "", "the entry was replaced")


func test_refused_queued_order_goes_to_the_next() -> void:
	var sim := _sim()
	var ev := sim.step([{"type": "go_to_station", "actor": ELENA, "zone": "anvil", "queued": true},
		{"type": "move_to", "actor": ELENA, "tile": [20, 21], "queued": true}])
	var refused := _of_type(ev, "order_refused")
	check(refused.size() == 1 and refused[0]["reason"] == "not_inside", "the first is refused")
	check(not (_chr(sim, ELENA)["path"] as Array).is_empty(), "the second runs")


func test_work_cycle_counts_as_done_with_orders_waiting() -> void:
	var sim := _sim()
	var door: Array = sim.state.buildings[FORGE]["door"]
	_chr(sim, HUGO)["position"] = [int(door[0]), int(door[1])]
	sim.step([{"type": "enter_building", "actor": HUGO, "building": FORGE}])
	var ev := sim.step([{"type": "work_at", "actor": HUGO, "building": FORGE, "zone": "furnace",
		"recipe": "forge_ingot", "mode": "normal"}])
	eq(_of_type(ev, "order_refused").size(), 0, "working")
	var end := int(sim.state.buildings[FORGE]["zones"]["furnace"]["job"]["end"])
	ev = sim.step([{"type": "exit_building", "actor": HUGO, "queued": true}])
	eq(str(_chr(sim, HUGO)["location"]), FORGE, "waits while the cycle runs")
	eq(_of_type(ev, "work_interrupted").size(), 0, "not interrupted")
	var all: Array = []
	while int(sim.state.clock["minute"]) <= end + 2:
		all.append_array(sim.step())
	eq(_of_type(all, "work_done").size(), 1, "the cycle finished")
	eq(_of_type(all, "work_interrupted").size(), 0, "and was not interrupted")
	eq(_of_type(all, "work_started").size(), 0, "no repeat with orders waiting")
	eq(str(_chr(sim, HUGO)["location"]), "", "then the queued exit ran")
	check(Inventory.count(sim.state.buildings[FORGE]["inventory"], "iron_ingot") >= 1, "the ingot is in the storage")


func test_save_with_queue_pending_goes_on_the_same() -> void:
	var sim := _sim()
	sim.step([{"type": "enter_building", "actor": HUGO, "building": FORGE, "queued": true},
		{"type": "go_to_station", "actor": HUGO, "zone": "anvil", "queued": true},
		{"type": "move_to", "actor": ELENA, "tile": [24, 18], "queued": true},
		{"type": "enter_building", "actor": ELENA, "building": FORGE, "queued": true}])
	sim.run_minutes(3)
	check(not (_chr(sim, HUGO)["order_queue"] as Array).is_empty(), "Hugo still has orders waiting")
	var path := "user://test_core_queue.json"
	eq(SaveFile.save(sim.state, path), OK, "saved")
	var r := SaveFile.load_file(path)
	check(r["ok"], "loaded")
	var other := Sim.new(r["state"], cat)
	eq(other.state_hash(), sim.state_hash(), "same state")
	sim.run_minutes(90)
	other.run_minutes(90)
	eq(other.state_hash(), sim.state_hash(), "same game when going on")
	eq(str(other.state.characters[HUGO]["station"]), "anvil", "Hugo ended at the anvil")
	eq(str(other.state.characters[ELENA]["location"]), FORGE, "Elena got in")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
