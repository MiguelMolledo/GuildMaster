extends SceneTree
## Bots playing whole days without a window (GDD 07 §7.2), checked against data/targets.json.
##   godot --headless --path . -s tools/sim_runner.gd -- [--scenario=<id>] [--bots=idle,...] [--days=<n>] [--seeds=<n>]
## Writes reports/sim/<scenario>_<bot>.json with the measures of every seed and exits with 1 if a target is missed.
## Measures today: days, refused_orders, refused_unreachable, refused_other (refused for any reason but unreachable),
## moves (tiles walked), arrivals, state_hash; H2: work_done, made_<item> (units produced); H3 rival: rival_sold, rival_gold_day10. Each milestone adds its own (gold_day10, days_to_citizen...).
## The default scenario is town_e_start (the H1 town).

var BOTS: Dictionary = {"idle": BotIdle, "wanderer": BotWanderer, "smith": BotSmith,
	"random_clicker": BotRandomClicker, "idle_rival": BotIdle}  # idle_rival: idle with the rival's targets (10 days)


func _init() -> void:
	var scenario := "town_e_start"
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
			var m := {"refused_orders": 0, "refused_unreachable": 0, "refused_other": 0, "moves": 0, "arrivals": 0}
			var gold0 := {}  # H3 conservation (GDD 4.19): ledger_mismatch = families whose book does not add up
			for f: String in sim.state.families:
				gold0[f] = Money.gold(sim.state, f) - Ledger.total(sim.state, f)
			for i: int in days * Clock.MINUTES_PER_DAY:
				for e: Dictionary in sim.step(bot.orders(sim)):
					match str(e["type"]):
						"order_refused":
							m["refused_orders"] += 1
							m["refused_unreachable" if str(e["reason"]) == "unreachable" else "refused_other"] += 1
							print("  [%s seed %d] refused %s %s: %s" % [bot_id, s, e["order"], e["actor"], e["reason"]])
						"character_moved":
							m["moves"] += 1
						"character_arrived":
							m["arrivals"] += 1
						"work_done":  # H2 production: work_done count and made_<item> units
							m["work_done"] = int(m.get("work_done", 0)) + 1
							var made := "made_" + str(e["item"])
							m[made] = int(m.get(made, 0)) + int(e["qty"])
						"market_sold":  # H3 rival (GDD 4.5.5): units sold by the AI families with a profile
							if str(sim.state.families.get(str(e.get("family", "")), {}).get("ai_profile", "")) != "":
								m["rival_sold"] = int(m.get("rival_sold", 0)) + int(e["qty"])
				if i + 1 == 10 * Clock.MINUTES_PER_DAY:  # H3 rival: gold of the AI families with a profile at day 10
					m["rival_gold_day10"] = _rival_gold(sim)
			m["ledger_mismatch"] = 0
			for f: String in sim.state.families:
				if Money.gold(sim.state, f) - Ledger.total(sim.state, f) != int(gold0.get(f, 0)):
					m["ledger_mismatch"] += 1
			m.merge({"seed": s, "days": days, "state_hash": sim.state_hash()})
			runs.append(m)
		var fails := _check(targets.get(bot_id, {}), runs)
		missed += fails.size()
		for f: String in fails:
			print("  MISS %s · %s" % [bot_id, f])
		var out := {"scenario": scenario, "bot": bot_id, "days": days, "seeds": seeds, "runs": runs, "misses": fails}
		var path := "res://reports/sim/%s_%s.json" % [scenario, bot_id]
		FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(out, "\t"))
		print("sim_runner: %s × %d seeds × %d days · %d misses · %s" % [bot_id, seeds, days, fails.size(), path])
	quit(1 if missed > 0 else 0)


## Gold of the AI families with an ai_profile (the rival smith, GDD 4.5.5).
func _rival_gold(sim: Sim) -> int:
	var g := 0
	for f: String in sim.state.families:
		if str(sim.state.families[f].get("ai_profile", "")) != "":
			g += Money.gold(sim.state, f)
	return g


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
