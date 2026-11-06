extends "res://tests/test_case.gd"
## hail (verificación A8): whoever is called stops and waits while the caller walks to it; the wait ends when the
## caller has done its business (no path, no queued orders), when the time runs out, or when one of them dies; it
## survives a save and load.

const SC := "town_e_start"


func _sim() -> Sim:
	var r := NewGame.from_scenario(SC, 3)
	return Sim.new(r["state"], Catalog.load_from())


func _walker(sim: Sim, not_id: String) -> String:
	for id: String in sim.state.characters:
		var c: Dictionary = sim.state.characters[id]
		if id != not_id and str(c.get("family", "")) != str(sim.state.characters[not_id].get("family", "")) \
				and str(c.get("location", "")) == "" and bool(c.get("alive", true)):
			return id
	return ""


func test_the_called_one_waits_and_is_released() -> void:
	var sim := _sim()
	var hero := SimQuery.family_actor(sim.state, SimQuery.player_family(sim.state))
	var other := _walker(sim, hero)
	check(other != "", "somebody out in the street")
	var o: Dictionary = sim.state.characters[other]
	var r := Orders.apply(sim, {"type": "hail", "actor": hero, "target": other})
	check(bool(r["ok"]), "hail is accepted (%s)" % r)
	check(Orders.is_management("hail"), "hail applies at once (management)")
	# a walk of the called one does not advance while it waits
	var before: Array = (o["position"] as Array).duplicate()
	var h: Dictionary = sim.state.characters[hero]
	for i: int in 10:   # the caller is still on its way (a long path), the called one wants to walk
		h["path"] = [[0, 0], [0, 1]]
		h["move_progress"] = 0
		o["path"] = [[int(before[0]) + 1, int(before[1])]]
		o["move_progress"] = 0
		sim.step([])
	eq(o["position"], before, "it waits where it was")
	check(NpcActions.held(sim.state, other), "still held while the caller has something to do")
	h["order_queue"] = []
	h["path"] = []
	sim.step([])
	check(not NpcActions.held(sim.state, other), "released once the caller has nothing left to do")


func test_the_wait_runs_out_and_survives_a_save() -> void:
	var sim := _sim()
	var hero := SimQuery.family_actor(sim.state, SimQuery.player_family(sim.state))
	var other := _walker(sim, hero)
	var r := Orders.apply(sim, {"type": "hail", "actor": hero, "target": other})
	check(bool(r["ok"]), "hail (%s)" % r)
	var d: Dictionary = JSON.parse_string(JSON.stringify(sim.state.to_dict()))
	var back := WorldState.from_dict(SaveFile.migrate(d)["data"])
	check((back.town.get("holds", {}) as Dictionary).has(other), "the wait is saved (%s → %s)" % [sim.state.town.get("holds"), back.town.keys()])
	var mins := int(sim.catalog.town["actions"]["hail"]["wait_minutes"])
	for i: int in mins + 2:
		sim.state.characters[hero]["path"] = [[0, 0]]
		sim.state.characters[hero]["move_progress"] = 0
		NpcActions.step_holds(sim)
		sim.state.clock["minute"] = int(sim.state.clock["minute"]) + 1
	check(not NpcActions.held(sim.state, other), "after wait_minutes it goes on with its day")
