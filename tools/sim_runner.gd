extends SceneTree
## Bots playing whole days without a window (GDD 07 §7.2), checked against data/targets.json.
##   godot --headless --path . -s tools/sim_runner.gd -- [--scenario=<id> | --start=<id>] [--difficulty=normal|easy,normal,hard]
##       [--bots=idle,...] [--days=<n>] [--seeds=<n>]
## --scenario loads data/scenarios/<id>.json as is (default town_e_start, the H1 town). --start plays a real new game
## (NewGame.from_start, GDD 4.16) at each --difficulty (default normal; the bot may give its choices with
## bot_choices()). The targets of data/targets.json are those of Normal (GDD 4.23): with several difficulties the
## per-run targets are checked only on normal, and the mean net gold per day must keep easy > normal > hard.
## Writes reports/sim/<scenario|start>_<bot>[_<difficulty>].json with the measures of every seed and exits with 1 if
## a target is missed.
## Measures: days, refused_orders, refused_unreachable, refused_other (refused for any reason but unreachable), moves
## (tiles walked), arrivals, state_hash; H2: work_done, made_<item> (units produced); H3: ledger_mismatch (families
## whose book does not add up), rival_sold, rival_gold_day10, and for the player's family (the first family
## controlled by "human"): gold_day3 / gold_day8 / gold_day10, gold_repaid_day<N> (gold + what it already paid back
## to its loans: the gold of the start phase whether the debt was paid early or not), debt_paid (1 if every loan was
## repaid, not in extension, before its due minute), debt_paid_day, net_day_<a>_<b> (data/targets.json goldflow:
## ledger entries of the window outside its excluded categories / days; its target is checked on the mean of the
## seeds, GDD 4.19 "media"), by_category_<a>_<b> (the window by category, for the report), contracts_done,
## contracts_failed, player_other_flows (ledger entries of the player's family that are not a payment of upkeep or
## loans: an idle family must have 0, GDD 4.19).
## Targets per bot: {measure: [min, max]} checked on every run; "_mean": {measure: [min, max]} on the mean of the runs;
## "_share": {measure: [min, max]} on the share of runs where the measure is 1.
## H8: a bot with measures(sim) adds its own (dynasty: wedding_day, first_child_days, inherited, inherit_day,
## generation_days, game_over), e.g. --scenario=dynasty_start --bots=dynasty --days=320 --seeds=3.
## H7 (docs/contratos/h7_ciudad.md): for the player's family mev_<id> (microevents started, one per id of
## data/microevents), mev_max_per_day (most in a single day), mev_timeouts (default applied after the timeout),
## counter_sold (sales at the counter), thefts and thefts_foiled; townsfolk (alive at the end), e.g.
## --scenario=town_microevents --bots=idle_town --days=30 --seeds=3.

var BOTS: Dictionary = {"idle": BotIdle, "wanderer": BotWanderer, "smith": BotSmith,
	"random_clicker": BotRandomClicker, "idle_rival": BotIdle, "artisan_novice": BotArtisanNovice,
	"dynasty": BotDynasty, "idle_town": BotIdle}
	# idle_rival: idle with the rival's targets (10 days); idle_town: idle with the microevent targets (30 days)
const IDLE_OK: Array = ["upkeep", "loans"]  # what may take gold from an idle family (GDD 4.19)


func _init() -> void:
	var scenario := "town_e_start"
	var start := ""
	var diffs: PackedStringArray = ["normal"]
	var bots: PackedStringArray = ["idle"]
	var days := 3
	var seeds := 5
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.substr(11)
		elif a.begins_with("--start="):
			start = a.substr(8)
		elif a.begins_with("--difficulty="):
			diffs = a.substr(13).split(",")
		elif a.begins_with("--bots="):
			bots = a.substr(7).split(",")
		elif a.begins_with("--days="):
			days = a.substr(7).to_int()
		elif a.begins_with("--seeds="):
			seeds = a.substr(8).to_int()
	var cat := Catalog.load_from()
	var targets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/targets.json"))
	var flows := _goldflows(targets)
	var missed := 0
	var label := start if start != "" else scenario
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/sim"))
	if start == "":
		diffs = [""]
	for bot_id: String in bots:
		if not BOTS.has(bot_id):
			print("sim_runner: unknown bot %s" % bot_id)
			missed += 1
			continue
		var means := {}  # difficulty -> mean net gold per day of the first goldflow window (GDD 4.23 order)
		for diff: String in diffs:
			var runs: Array = []
			for s: int in range(1, seeds + 1):
				var bot: Object = BOTS[bot_id].new()
				var r := {}
				if start != "":
					var choices: Dictionary = bot.call("bot_choices") if bot.has_method("bot_choices") else {}
					r = NewGame.from_start(cat, start, diff, choices, s)
				else:
					r = NewGame.from_scenario(scenario, s)
				if not r["ok"]:
					print("sim_runner: %s: %s" % [label, r["error"]])
					quit(2)
					return
				runs.append(_run(Sim.new(r["state"], cat), bot, bot_id, s, days, flows))
			var t: Dictionary = (targets.get(bot_id, {}) as Dictionary).duplicate(true)
			for fl: Dictionary in flows:  # the goldflow window of this bot (GDD 4.19: the mean over the seeds)
				if str(fl.get("bot", "")) == bot_id and days >= int(fl["window_days"][1]):
					if not t.has("_mean"):
						t["_mean"] = {}
					t["_mean"][_flow_key(fl)] = fl["net_per_day"]
			var fails: PackedStringArray = []
			if diff in ["", "normal"]:
				fails = _check(t, runs)
			var agg := _aggregate(t, runs)
			if not flows.is_empty():
				means[diff] = agg.get("mean_" + _flow_key(flows[0]), NAN)
			missed += fails.size()
			for f: String in fails:
				print("  MISS %s%s · %s" % [bot_id, "" if diff == "" else " (%s)" % diff, f])
			var out := {"scenario": scenario if start == "" else "", "start": start, "difficulty": diff, "bot": bot_id,
				"days": days, "seeds": seeds, "aggregate": agg, "runs": runs, "misses": fails}
			var path := "res://reports/sim/%s_%s%s.json" % [label, bot_id, "" if diff in ["", "normal"] else "_" + diff]
			FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(out, "\t"))
			print("sim_runner: %s%s × %d seeds × %d days · %d misses · %s · %s" % [bot_id,
				"" if diff == "" else " (%s)" % diff, seeds, days, fails.size(), _brief(agg), path])
		# GDD 4.23: more net gold in easy than in normal, and in normal than in hard (only the ones that ran).
		var order: Array = []
		for d: String in ["easy", "normal", "hard"]:
			if means.has(d) and not is_nan(float(means[d])):
				order.append(d)
		for i: int in range(1, order.size()):
			if float(means[order[i - 1]]) <= float(means[order[i]]):
				missed += 1
				print("  MISS %s · difficulty order: %s %.1f <= %s %.1f" % [bot_id, order[i - 1], means[order[i - 1]],
					order[i], means[order[i]]])
		if order.size() > 1:
			print("sim_runner: %s net gold/day by difficulty: %s" % [bot_id, means])
	quit(1 if missed > 0 else 0)


## One seed: plays `days` days with `bot` and returns its measures.
func _run(sim: Sim, bot: Object, bot_id: String, s: int, days: int, flows: Array) -> Dictionary:
	var m := {"refused_orders": 0, "refused_unreachable": 0, "refused_other": 0, "moves": 0, "arrivals": 0}
	var gold0 := {}  # H3 conservation (GDD 4.19): ledger_mismatch = families whose book does not add up
	for f: String in sim.state.families:
		gold0[f] = Money.gold(sim.state, f) - Ledger.total(sim.state, f)
	var player := _player_family(sim)
	var start_minute := int(sim.state.clock["minute"])
	var dues := {}  # loan -> due minute at the start (repaid before it and not in extension = paid in time)
	for id: String in sim.state.loans:
		if str(sim.state.loans[id].get("family", "")) == player:
			dues[id] = int(sim.state.loans[id].get("due_minute", 0))
	var paid := {}
	var repaid := 0  # gold paid back to loans so far (gold_repaid_day<N> = gold + this)
	var mev_days := {}  # H7: day -> microevents started for the player's family
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
				"loan_payment":
					if str(e.get("family", "")) == player:
						repaid += int(e["amount"])
				"loan_repaid":
					if str(e.get("family", "")) == player and not bool(e.get("extended", false)):
						paid[str(e["loan"])] = int(sim.state.clock["minute"])
				"contract_delivered":
					if str(e.get("family", "")) == player:
						m["contracts_done"] = int(m.get("contracts_done", 0)) + 1
				"contract_failed":
					if str(e.get("family", "")) == player:
						m["contracts_failed"] = int(m.get("contracts_failed", 0)) + 1
				"microevent_started":  # H7 (GDD 4.20)
					if str(e.get("family", "")) == player:
						var k := "mev_" + str(e["def"])
						m[k] = int(m.get(k, 0)) + 1
						var dd := Clock.day(int(sim.state.clock["minute"]))
						mev_days[dd] = int(mev_days.get(dd, 0)) + 1
				"microevent_resolved":
					if str(e.get("family", "")) == player and str(e.get("by", "")) == "timeout":
						m["mev_timeouts"] = int(m.get("mev_timeouts", 0)) + 1
				"counter_sold":
					if str(e.get("family", "")) == player:
						m["counter_sold"] = int(m.get("counter_sold", 0)) + 1
				"theft":
					if str(e.get("family", "")) == player:
						var tk := "thefts_foiled" if bool(e.get("frustrated", false)) else "thefts"
						m[tk] = int(m.get(tk, 0)) + 1
		var done_days := i + 1
		if done_days % Clock.MINUTES_PER_DAY == 0:
			var d := done_days / Clock.MINUTES_PER_DAY
			if d == 10:  # H3 rival: gold of the AI families with a profile at day 10
				m["rival_gold_day10"] = _rival_gold(sim)
			if player != "" and d in [3, 8, 10]:
				m["gold_day%d" % d] = Money.gold(sim.state, player)
				m["gold_repaid_day%d" % d] = Money.gold(sim.state, player) + repaid
	m["ledger_mismatch"] = 0
	for f: String in sim.state.families:
		if Money.gold(sim.state, f) - Ledger.total(sim.state, f) != int(gold0.get(f, 0)):
			m["ledger_mismatch"] += 1
	if player != "":
		m["contracts_done"] = int(m.get("contracts_done", 0))
		m["contracts_failed"] = int(m.get("contracts_failed", 0))
		var other := 0
		for e: Dictionary in sim.state.ledger.get("entries", []):
			if str(e.get("family", "")) == player and (int(e["amount"]) > 0 or not str(e["category"]) in IDLE_OK):
				other += 1
		m["player_other_flows"] = other
		if not dues.is_empty():
			var ok := 1
			var last := -1
			for id: String in dues:
				if not paid.has(id) or int(paid[id]) >= int(dues[id]):
					ok = 0
				else:
					last = maxi(last, Clock.day(int(paid[id])))
			m["debt_paid"] = ok
			m["debt_paid_day"] = last if ok == 1 else -1
		for fl: Dictionary in flows:
			var w: Array = fl["window_days"]
			var lo := start_minute + (int(w[0]) - 1) * Clock.MINUTES_PER_DAY
			var hi := start_minute + int(w[1]) * Clock.MINUTES_PER_DAY
			if hi - start_minute > days * Clock.MINUTES_PER_DAY:
				continue  # the run is shorter than the window
			var net := 0
			var cats := {}  # the window by ledger category (for the report)
			for e: Dictionary in sim.state.ledger.get("entries", []):
				if str(e.get("family", "")) == player and int(e["minute"]) >= lo and int(e["minute"]) < hi:
					cats[str(e["category"])] = int(cats.get(str(e["category"]), 0)) + int(e["amount"])
					if not str(e["category"]) in (fl.get("exclude_categories", []) as Array):
						net += int(e["amount"])
			m[_flow_key(fl)] = snappedf(float(net) / float(int(w[1]) - int(w[0]) + 1), 0.01)
			m["by_category_" + _flow_key(fl).substr(8)] = cats
	for d: String in sim.catalog.microevents():  # H7: every microevent measured, also the ones that never came
		m["mev_" + d] = int(m.get("mev_" + d, 0))
	var most := 0
	for dd: Variant in mev_days:
		most = maxi(most, int(mev_days[dd]))
	m["mev_max_per_day"] = most
	for k: String in ["mev_timeouts", "counter_sold", "thefts", "thefts_foiled"]:
		m[k] = int(m.get(k, 0))
	m["townsfolk"] = Population.townsfolk(sim.state).size()
	if bot.has_method("measures"):  # H8: a bot may measure its own things (dynasty: wedding, children, inheritance)
		m.merge(bot.call("measures", sim))
	m.merge({"seed": s, "days": days, "state_hash": sim.state_hash()})
	return m


## The goldflow windows of data/targets.json that a bot measures (GDD 4.19), as an Array of their definitions.
func _goldflows(targets: Dictionary) -> Array:
	var out: Array = []
	var gf: Dictionary = targets.get("goldflow", {})
	var keys: Array = gf.keys()
	keys.sort()
	for k: String in keys:
		if gf[k] is Dictionary and (gf[k] as Dictionary).has("window_days"):
			out.append(gf[k])
	return out


func _flow_key(fl: Dictionary) -> String:
	var w: Array = fl["window_days"]
	return "net_day_%d_%d" % [int(w[0]), int(w[1])]


## The first family controlled by "human" (the player's), "" if none.
func _player_family(sim: Sim) -> String:
	var fams: Array = sim.state.families.keys()
	fams.sort()
	for f: String in fams:
		if str(sim.state.families[f].get("controlled_by", "")) == "human":
			return f
	return ""


## Gold of the AI families with an ai_profile (the rival smith, GDD 4.5.5).
func _rival_gold(sim: Sim) -> int:
	var g := 0
	for f: String in sim.state.families:
		if str(sim.state.families[f].get("ai_profile", "")) != "":
			g += Money.gold(sim.state, f)
	return g


## Every measure of every run inside [min, max] (null = open end); "_mean" on the mean, "_share" on the share of 1s.
func _check(t: Dictionary, runs: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for key: String in t:
		if key.begins_with("_"):
			continue
		var lo: Variant = t[key][0]
		var hi: Variant = t[key][1]
		for run: Dictionary in runs:
			var v := float(run.get(key, NAN))
			if is_nan(v) or (lo != null and v < float(lo)) or (hi != null and v > float(hi)):
				out.append("seed %d: %s = %s outside [%s, %s]" % [run["seed"], key, run.get(key), lo, hi])
	var agg := _aggregate(t, runs)
	for kind: String in ["_mean", "_share"]:
		var tt: Dictionary = t.get(kind, {})
		for key: String in tt:
			var v := float(agg.get(kind.substr(1) + "_" + key, NAN))
			var lo: Variant = tt[key][0]
			var hi: Variant = tt[key][1]
			if is_nan(v) or (lo != null and v < float(lo)) or (hi != null and v > float(hi)):
				out.append("%s %s = %s outside [%s, %s]" % [kind.substr(1), key, snappedf(v, 0.001), lo, hi])
	return out


## mean_<measure> and min/max of the numeric measures, and share_<measure> for the "_share" targets.
func _aggregate(t: Dictionary, runs: Array) -> Dictionary:
	var out := {}
	if runs.is_empty():
		return out
	for key: String in runs[0]:
		if key in ["seed", "state_hash", "days"] or not typeof(runs[0][key]) in [TYPE_INT, TYPE_FLOAT]:
			continue
		var sum := 0.0
		var lo := INF
		var hi := -INF
		for run: Dictionary in runs:
			var v := float(run.get(key, 0))
			sum += v
			lo = minf(lo, v)
			hi = maxf(hi, v)
		out["mean_" + key] = snappedf(sum / runs.size(), 0.01)
		out["min_" + key] = lo
		out["max_" + key] = hi
	for key: String in t.get("_share", {}):
		var n := 0
		for run: Dictionary in runs:
			if int(run.get(key, 0)) == 1:
				n += 1
		out["share_" + key] = snappedf(float(n) / runs.size(), 0.001)
	return out


func _brief(agg: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in ["gold_day3", "gold_repaid_day3", "gold_day10", "net_day_1_8", "debt_paid", "debt_paid_day", "rival_gold_day10"]:
		if agg.has("mean_" + key):
			parts.append("%s %s [%s-%s]" % [key, agg["mean_" + key], agg["min_" + key], agg["max_" + key]])
	return ", ".join(parts)
