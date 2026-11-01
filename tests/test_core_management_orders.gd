extends "res://tests/test_case.gd"
## Management orders (hire, bonus, queue_*...) act at once and never touch the signer's order queue.


func _sim() -> Sim:
	var r := NewGame.from_scenario("two_employees", 1)
	return Sim.new(r["state"], Catalog.load_from())


func test_live_management_order_keeps_the_walk() -> void:
	var sim := _sim()
	var st := sim.state
	var hugo := "chr_0001"
	sim.step([{"type": "move_to", "actor": hugo, "tile": [20, 18], "queued": true},
		{"type": "move_to", "actor": hugo, "tile": [22, 18], "queued": true}])
	var before := (st.characters[hugo]["order_queue"] as Array).size() + (1 if not (st.characters[hugo]["path"] as Array).is_empty() else 0)
	sim.step([{"type": "queue_pause", "actor": hugo, "building": "bld_0001", "on": true}])
	check(before > 0, "Hugo has a walk and a queue")
	var after := (st.characters[hugo]["order_queue"] as Array).size() + (1 if not (st.characters[hugo]["path"] as Array).is_empty() else 0)
	eq(after, before, "the walk and the queue survive a management order")


func test_queued_management_order_applies_at_once() -> void:
	var sim := _sim()
	var hugo := "chr_0001"
	sim.step([{"type": "queue_pause", "actor": hugo, "building": "bld_0001", "on": true, "queued": true}])
	eq((sim.state.characters[hugo]["order_queue"] as Array).size(), 0, "not queued behind anything")
