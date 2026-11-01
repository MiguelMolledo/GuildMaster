extends SceneTree
## Cost of the sim per step (GDD 05 §5.4; target < 2 ms per step on the Mac).
##   godot --headless --path . -s tools/sim_bench.gd [-- --scenario=<id> --days=<n>]
## Prints ms per step (mean and worst) and exits with 1 if the mean is over the target.

const TARGET_MS: float = 2.0


func _init() -> void:
	var scenario := "empty_town"
	var days := 3
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.substr(11)
		elif a.begins_with("--days="):
			days = a.substr(7).to_int()
	var cat := Catalog.load_from()
	var r := NewGame.from_scenario(scenario)
	if not r["ok"]:
		print("sim_bench: scenario %s: %s" % [scenario, r["error"]])
		quit(2)
		return
	var sim := Sim.new(r["state"], cat)
	var steps := days * Clock.MINUTES_PER_DAY
	var worst := 0
	var t0 := Time.get_ticks_usec()
	for i: int in steps:
		var s := Time.get_ticks_usec()
		sim.step()
		worst = maxi(worst, Time.get_ticks_usec() - s)
	var mean_ms := (Time.get_ticks_usec() - t0) / 1000.0 / steps
	print("sim_bench: %s, %d steps, mean %.4f ms, worst %.3f ms (target < %.1f ms)" % [scenario, steps, mean_ms,
		worst / 1000.0, TARGET_MS])
	quit(0 if mean_ms < TARGET_MS else 1)
