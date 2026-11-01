extends SceneTree
## Bots playing whole days without a window (GDD 07 §7.2), checked against data/targets.json.
##   godot --headless --path . -s tools/sim_runner.gd -- [--scenario=<id>] [--bots=idle,...] [--days=<n>] [--seeds=<n>]
## Writes reports/sim/<scenario>_<bot>.json with the measures of every seed and exits with 1 if a target is missed.
## Measures today: days, refused_orders, state_hash. Each milestone adds its own (gold_day10, days_to_citizen...).

var BOTS: Dictionary = {"idle": BotIdle}


func _init() -> void:
	var scenario := "empty_town"
	var bots: PackedStringArray = ["idle"]
	var days := 3
	var seeds := 5
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.substr(11)
		elif a.begins_with("--bots="):
			bots = a.substr(7).split(",")
		elif a.begins_with("--days="):
			days = a.substr(7).to_int()
		elif a.begins_with("--seeds="):
			seeds = a.substr(8).to_int()
	var cat := Catalog.load_from()
	var targets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/targets.json"))
	var missed := 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/sim"))
	for bot_id: String in bots:
		if not BOTS.has(bot_id):
			print("sim_runner: unknown bot %s" % bot_id)
			missed += 1
			continue
		var runs: Array = []
		for s: int in range(1, seeds + 1):
			var r := NewGame.from_scenario(scenario, s)
			if not r["ok"]:
				print("sim_runner: scenario %s: %s" % [scenario, r["error"]])
				quit(2)
				return
			var sim := Sim.new(r["state"], cat)
			var bot: Object = BOTS[bot_id].new()
			var refused := 0
			for m: int in days * Clock.MINUTES_PER_DAY:
				for e: Dictionary in sim.step(bot.orders(sim)):
					if e["type"] == "order_refused":
						refused += 1
			runs.append({"seed": s, "days": days, "refused_orders": refused, "state_hash": sim.state_hash()})
		var fails := _check(targets.get(bot_id, {}), runs)
		missed += fails.size()
		for f: String in fails:
			print("  MISS %s · %s" % [bot_id, f])
		var out := {"scenario": scenario, "bot": bot_id, "days": days, "seeds": seeds, "runs": runs, "misses": fails}
		var path := "res://reports/sim/%s_%s.json" % [scenario, bot_id]
		FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(out, "\t"))
		print("sim_runner: %s × %d seeds × %d days · %d misses · %s" % [bot_id, seeds, days, fails.size(), path])
	quit(1 if missed > 0 else 0)


## Every measure of every run inside [min, max] (null = open end).
func _check(t: Dictionary, runs: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for key: String in t:
		var lo: Variant = t[key][0]
		var hi: Variant = t[key][1]
		for run: Dictionary in runs:
			var v := float(run.get(key, NAN))
			if is_nan(v) or (lo != null and v < float(lo)) or (hi != null and v > float(hi)):
				out.append("seed %d: %s = %s outside [%s, %s]" % [run["seed"], key, run.get(key), lo, hi])
	return out
