extends SceneTree
## Cost of the sim per step (GDD 05 §5.4; target < 2 ms per step on the Mac).
##   godot --headless --path . -s tools/sim_bench.gd [-- --scenario=<id> --days=<n> --bot=wanderer|idle|none]
## Default: town_e_start with the wanderer bot (everybody walking); the bot's orders count in the time of the step.
## Prints ms per step (mean and worst) and exits with 1 if the mean is over the target.

const TARGET_MS: float = 2.0


func _init() -> void:
	var scenario := "town_e_start"
	var days := 3
	var bot_id := "wanderer"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.substr(11)
		elif a.begins_with("--days="):
			days = a.substr(7).to_int()
		elif a.begins_with("--bot="):
			bot_id = a.substr(6)
	var bots := {"wanderer": BotWanderer, "idle": BotIdle}
	var bot: Object = bots[bot_id].new() if bots.has(bot_id) else null
	var cat := Catalog.load_from()
	var r := NewGame.from_scenario(scenario)
	if not r["ok"]:
		print("sim_bench: scenario %s: %s" % [scenario, r["error"]])
		quit(2)
		return
	var sim := Sim.new(r["state"], cat)
	var steps := days * Clock.MINUTES_PER_DAY
	var worst := 0
	var moves := 0
	var t0 := Time.get_ticks_usec()
	for i: int in steps:
		var s := Time.get_ticks_usec()
		for e: Dictionary in sim.step(bot.orders(sim) if bot != null else []):
			if e["type"] == "character_moved":
				moves += 1
		worst = maxi(worst, Time.get_ticks_usec() - s)
	var mean_ms := (Time.get_ticks_usec() - t0) / 1000.0 / steps
	print("sim_bench: %s, bot %s, %d characters, %d steps, %d tiles walked, mean %.4f ms, worst %.3f ms (target < %.1f ms)"
		% [scenario, bot_id if bot != null else "none", sim.state.characters.size(), steps, moves, mean_ms,
		worst / 1000.0, TARGET_MS])
	quit(0 if mean_ms < TARGET_MS else 1)
