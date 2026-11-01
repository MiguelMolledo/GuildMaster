extends "res://tests/test_case.gd"
## Game's session controls (GDD 4.1, D4): speeds ×1/×2/×4 and pause change the steps per real second; orders given
## in pause wait for the resume; the start options (default scenario, --at=HH:MM).

const GameScript := preload("res://game/autoload/game.gd")

var cat := Catalog.load_from()


func _game() -> Node:
	var g: Node = GameScript.new()
	g.start(NewGame.from_scenario("town_e_start")["state"], cat)
	return g


## Steps run in `seconds` real seconds, fed as 0.1 s frames.
func _run(g: Node, seconds: float) -> int:
	var n := 0
	for i: int in roundi(seconds * 10.0):
		n += g.advance(0.1, false)
	return n


func test_speeds_and_pause_change_steps_per_second() -> void:
	var per_second := Clock.MINUTES_PER_DAY / float(cat.time["real_seconds_per_day"])  # 4.8 at x1
	for s: int in [1, 2, 4]:
		var g := _game()
		g.set_speed(s)
		near(g.steps_per_second(), per_second * s, 0.001, "steps/s at x%d" % s)
		var n := _run(g, 10.0)
		check(absi(n - roundi(per_second * s * 10.0)) <= 1, "x%d: %d steps in 10 s" % [s, n])
		g.free()
	var g := _game()
	g.set_speed(3)
	eq(g.speed, 1, "x3 does not exist")
	g.set_paused(true)
	eq(g.steps_per_second(), 0.0, "paused: no steps per second")
	var before := int(g.sim.state.clock["minute"])
	eq(_run(g, 5.0), 0, "paused: no steps")
	eq(int(g.sim.state.clock["minute"]), before, "the clock waits")
	g.toggle_pause()
	check(_run(g, 1.0) > 0, "resumed")
	g.free()


func test_orders_wait_in_pause() -> void:
	var g := _game()
	g.set_paused(true)
	g.give({"type": "move_to", "actor": "chr_0001", "tile": [24, 18]})
	_run(g, 2.0)
	eq(g.pending().size(), 1, "queued while paused")
	g.set_paused(false)
	_run(g, 1.0)
	eq(g.pending().size(), 0, "given on resume")
	check(not (g.sim.state.characters["chr_0001"]["path"] as Array).is_empty(), "and the sim took it")
	g.free()


func test_start_options() -> void:
	var d: Dictionary = GameScript.parse_args(PackedStringArray([]))
	eq(d["scenario"], "town_e_start", "default scenario")
	eq(d["at"], -1, "no --at")
	d = GameScript.parse_args(PackedStringArray(["--scenario=empty_town", "--at=23:30", "--seed=7"]))
	eq(d["scenario"], "empty_town", "--scenario still rules")
	eq(d["at"], 23 * 60 + 30, "--at=23:30")
	eq(d["seed"], 7, "--seed")
	var st: WorldState = NewGame.from_scenario("town_e_start")["state"]
	st.clock["minute"] = 3 * Clock.MINUTES_PER_DAY + 480
	GameScript.set_time_of_day(st, 12 * 60)
	eq(int(st.clock["minute"]), 3 * Clock.MINUTES_PER_DAY + 720, "--at keeps the day")
