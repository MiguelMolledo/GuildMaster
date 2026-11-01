extends "res://tests/test_case.gd"
## Same seed + same orders = same game (GDD 05 §5.2, H0 acceptance: 30 empty days, same hash).

var cat := Catalog.load_from()


func _run(world_seed: int, days: int) -> String:
	var sim := Sim.new(NewGame.fresh(cat, world_seed), cat)
	sim.run_days(days, BotIdle.new())
	sim.state.rng.randi()
	return sim.state_hash()


func test_thirty_days_same_hash() -> void:
	eq(_run(7, 30), _run(7, 30), "same seed, same hash")
	check(_run(7, 1) != _run(8, 1), "another seed, another hash")


func test_save_mid_game_and_continue() -> void:
	var a := Sim.new(NewGame.fresh(cat, 3), cat)
	a.run_days(2)
	var b := Sim.new(SaveFile.from_text(JSON.stringify(a.state.to_dict()))["state"], cat)
	a.run_days(3)
	b.run_days(3)
	eq(b.state_hash(), a.state_hash(), "a loaded game goes on exactly like the original")


func test_replay_of_recorded_orders() -> void:
	var a := Sim.new(NewGame.fresh(cat, 5), cat)
	var start := JSON.stringify(a.state.to_dict())
	a.record = true
	for i: int in 300:
		a.step([{"type": "wait", "actor": "chr_0001"}] if i % 7 == 0 else [])
	var b := Sim.new(SaveFile.from_text(start)["state"], cat)
	var by_minute := {}
	for r: Dictionary in a.recording:
		by_minute.get_or_add(int(r["minute"]), []).append(r["order"])
	for i: int in 300:
		b.step(by_minute.get(int(b.state.clock["minute"]), []))
	eq(b.state_hash(), a.state_hash(), "the replay ends in the same state")
