extends SceneTree
## Bots playing whole days without a window (GDD 07 §7.2), checked against data/targets.json.
##   godot --headless --path . -s tools/sim_runner.gd -- [--scenario=<id> | --start=<id>] [--difficulty=normal|easy,normal,hard]
##       [--bots=idle,...] [--days=<n>] [--seeds=<n>] [--set=<where>=<json>]...
## --set (balance trials, D14): changes one figure of the loaded catalog for this run only, without touching data/:
## <where> = <table>.<id>.<key>[.<key>...] for the tables of data/ (items, recipes, upgrades, buildings, contracts,
## ai_profiles, starts) or <market|employees|production|difficulty|accounts>.<key>[...] (e.g.
## --set=market.demand.recover_per_day=0.2 --set=items.iron.base_price=6 --set=employees.ranks.journeyman.wage=10).
## Reports of a run with --set (or --tag=<name>) go to reports/sim/trial_[<name>_]*.json, not the official ones.
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
## H5: sink_share_<a>_<b> (goldflow windows with sink_categories: those categories' expenses / gross income of the
## window, GDD 4.19 "30-60 %"; sink_base "revenue" = over the gross income, "margin" = over the gross income minus
## the input_categories (materials); both are written as sink_share_revenue_ / sink_share_margin_), net_year_<n> (net gold per day of each whole year of 8 days played, without the
## categories of year_exclude), hired (employees hired by the player's family), upgrades_bought, upgrades_spent,
## prod_gain_<upgrade> and prod_expected_<upgrade> for every production_speed upgrade the player finished
## (production rate = standard minutes of the cycles started / their real minutes, per worker, in PROD_DAYS days
## before the works and after; gain = after / before, expected = the building's production_speed after / before),
## prod_gain_error (largest |gain / expected - 1| of the run), output_hours_<upgrade>_before / _after (standard hours
## of work produced per day in those windows, for the report).
## Targets per bot: {measure: [min, max]} checked on every run; "_mean": {measure: [min, max]} on the mean of the runs;
## "_share": {measure: [min, max]} on the share of runs where the measure is 1.
## H8: a bot with measures(sim) adds its own (dynasty: wedding_day, first_child_days, inherited, inherit_day,
## generation_days, game_over), e.g. --scenario=dynasty_start --bots=dynasty --days=320 --seeds=3.
## H7 (docs/contratos/h7_ciudad.md): for the player's family mev_<id> (microevents started, one per id of
## data/microevents), mev_max_per_day (most in a single day), mev_timeouts (default applied after the timeout),
## counter_sold (sales at the counter), thefts and thefts_foiled; townsfolk (alive at the end), e.g.
## --scenario=town_microevents --bots=idle_town --days=30 --seeds=3.
## H10 (docs/contratos/h10_cargos.md): office_won (the player's family takes an office), office_won_day (day played,
## days + 1 if never), elections_run / elections_won (its candidacies and seats won), ai_office_runs / ai_ran (the AI
## families with a profile register for an election), ai_offices_won, e.g. --start=artisan_blacksmith
## --bots=politician --days=40 --seeds=10.
## H11 (docs/contratos/h11_tribunal.md): trials (against the player's family), trial_day (the first; days + 1 if
## never), guilty, inspected (inspections that caught it), ai_accusations (trials opened by an AI family with a
## profile) and ai_accusations_bad (one with no fact that is not a fabrication allowed by its honesty), e.g.
## --start=artisan_blacksmith --bots=crook --days=40 --seeds=10.
## H14 (docs/contratos/h14_ia_familiar.md): forge_supplied (a family member other than the head carried raw materials
## into the workshop), kin_bought (their purchases), low_morale_hours (hours of a family member with low morale), e.g.
## --scenario=kin_trader --bots=kin_trader --days=2 --seeds=10.
## H13 (seasons and global events, GDD 4.13): events_started (global events started), ev_<def> (times each one
## started), events_declared, events_ended, events_overdue (in force past their end at the close: 0), events_max_active
## (most at once), local_past_season (a local event that ends after its season: 0), event_days (days with an event in
## force), e.g. --start=artisan_blacksmith --bots=events --days=80 --seeds=2. --set also reaches seasons.<key> and
## events.<key> (e.g. --set=events.enabled=false: the same seeds without events). The bots listed in data/targets.json
## _no_events (targets fixed before H13) run without global events unless --events=on.
## Población: --start games use the fixed cast (today's names, ages and tones: the targets were set with it) unless
## --cast=random (a generated cast per seed, Cast.sub_seed of the seed: what a player's new game gets). The reports of
## a --cast=random run go with --tag (e.g. --tag=cast_random) so they do not replace the official ones.
## Vida (04f 4.24): the bots listed in data/targets.json _no_life (targets fixed before the living town II) run with
## data/life/life.json enabled = false unless --life=on; --set also reaches life.<file>.<key> (e.g.
## --set=life.life.enabled=false). Measures of the life (a bot with measures(sim) adds them, e.g. guard_watch).

var BOTS: Dictionary = {"idle": BotIdle, "wanderer": BotWanderer, "smith": BotSmith,
	"random_clicker": BotRandomClicker, "idle_rival": BotIdle, "artisan_novice": BotArtisanNovice,
	"artisan_expert": BotArtisanExpert, "artisan_expert_0": BotArtisanExpert, "artisan_expert_1": BotArtisanExpert,
	"artisan_expert_2": BotArtisanExpert, "dynasty": BotDynasty, "idle_town": BotIdle,
	"expert_titles": BotArtisanExpert, "idle_titles": BotIdle, "politician": BotArtisanExpert, "crook": BotArtisanExpert,
	"kin_trader": BotIdle, "events": BotArtisanExpert, "carpenter_novice": BotArtisanTrade,
	"mason_novice": BotArtisanTrade, "tailor_novice": BotArtisanTrade, "duelist": BotDuelist,
	"merchant": BotMerchant, "gambler": BotGambler, "guard_watch": BotGuardWatch, "festive": BotFestive,
	"innkeeper": BotInnkeeper}
	# artisan_expert_<n>: the expert hiring at most n employees (H4/H5: what the employees add, same seeds)
	# idle_rival: idle with the rival's targets (10 days)
	# idle_town: idle with the microevent targets (30 days, H7)
	# expert_titles: artisan_expert with the title targets (H9, 96 days); idle_titles: idle, the AI's titles (80 days)
	# politician: artisan_expert that runs for minor offices (H10, runs_office = 1, 40 days)
	# crook: artisan_expert with the Secrets upgrade that ends in court (H11, crook = 1, 40 days)
	# carpenter_novice / mason_novice / tailor_novice: the novice of any artisan trade (H12), with its --start
	# kin_trader: idle from the scenario kin_trader: a family member with Trade supplies the forge (H14, 2 days)
	# events: artisan_expert for 10 years with the global events on (H13 criterion 1: 80 days without getting stuck)
	# duelist: challenges the rival of the trade by the rules and plays its duels (duelo, --scenario=duel_ready)
	# gambler: plays dice and cards in a gambling house and bets on pulsos (juegos, --scenario=games_gambler)
	# merchant: travels to the capital, sells there, takes contracts, signs a quota, sends a caravan (viajes, 09b)
	# guard_watch: nights with bandit raids; the watch answers, nobody loses more than the cap (vida, 04f 4.28.4)
	# festive: artisan_expert for a year with the festivals on (fiestas, 04f 4.28.4): every feast, its contracts
	# innkeeper: runs the Taberna-Posada of innkeeper_start 16 days (posada, 04f §4.27; --scenario=innkeeper_start)
const IDLE_OK: Array = ["upkeep", "loans"]  # what may take gold from an idle family (GDD 4.19)
const PROD_DAYS: int = 2  # days before and after each production upgrade where the production rate is measured
const YEAR_DAYS: int = 8  # D1(b): 1 year = 8 days
const YEAR_EXCLUDE: Array = ["loans"]  # the start debt is what the first year pays, not a loss (as goldflow.start)


func _init() -> void:
	var scenario := "town_e_start"
	var start := ""
	var diffs: PackedStringArray = ["normal"]
	var bots: PackedStringArray = ["idle"]
	var days := 3
	var seeds := 5
	var sets: PackedStringArray = []
	var tag := ""  # name of a trial's report (reports/sim/trial_<tag>_...)
	var events_on := false  # H13: --events=on runs the bots of targets _no_events with the global events too
	var cast := "fixed"  # población: --cast=random deals a generated cast per seed (the targets were set with the fixed one)
	var life_on := false  # vida: --life=on runs the bots of targets _no_life with the living town II too
	var festivals_on := false  # fiestas: --festivals=on runs every bot with the festival calendar (else only _festivals)
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
		elif a.begins_with("--set="):
			sets.append(a.substr(6))
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a == "--events=on":
			events_on = true
		elif a == "--life=on":
			life_on = true
		elif a.begins_with("--cast="):
			cast = a.substr(7)
		elif a == "--festivals=on":
			festivals_on = true
	var cat := Catalog.load_from()
	for spec: String in sets:
		if not _apply_set(cat, spec):
			print("sim_runner: bad --set %s" % spec)
			quit(2)
			return
	cat.events["_enabled_data"] = bool(cat.events.get("enabled", true))  # what data/ (or --set) says, before _no_events
	var life_cfg: Dictionary = cat.life_tables.get("life", {})
	var life_data := bool(life_cfg.get("enabled", true))  # vida: what data/ (or --set) says, before _no_life
	cat.festivals["_enabled_data"] = bool(cat.festivals.get("enabled", false))  # fiestas: before _festivals
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
		# H13: the targets fixed before the global events run without them (data/targets.json _no_events).
		var quiet: bool = bot_id in (targets.get("_no_events", []) as Array) and not events_on
		cat.events["enabled"] = not quiet and bool(cat.events.get("_enabled_data", cat.events.get("enabled", true)))
		if quiet:
			print("sim_runner: %s without global events (targets _no_events; --events=on to include them)" % bot_id)
		var still: bool = bot_id in (targets.get("_no_life", []) as Array) and not life_on  # vida (04f 4.24)
		life_cfg["enabled"] = life_data and not still
		if still:
			print("sim_runner: %s without the living town II (targets _no_life; --life=on to include it)" % bot_id)
		# fiestas (04f 4.28.4, principle 4): the targets fixed before the festivals run without them; only the bots of
		# data/targets.json _festivals (or --festivals=on) play the calendar.
		cat.festivals["enabled"] = (bot_id in (targets.get("_festivals", []) as Array) or festivals_on) \
			and bool(cat.festivals.get("_enabled_data", false))
		for diff: String in diffs:
			var runs: Array = []
			for s: int in range(1, seeds + 1):
				var bot: Object = BOTS[bot_id].new()
				if bot_id == "politician":
					bot.set("runs_office", 1)
				if bot_id == "crook":
					bot.set("crook", 1)
				if bot_id.begins_with("artisan_expert_"):
					bot.set("max_employees", bot_id.substr(15).to_int())
					bot.set("second_needs_furnace", false)  # exactly n: what each employee adds
				for kv: String in OS.get_environment("BOT_VARS").split(",", false):  # balance trials: k=v ints
					bot.set(kv.get_slice("=", 0), kv.get_slice("=", 1).to_int())
				var r := {}
				if start != "":
					var choices: Dictionary = (bot.call("bot_choices") as Dictionary).duplicate() if bot.has_method("bot_choices") else {}
					if not choices.has("cast"):
						choices["cast"] = cast
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
					if fl.has("sink_share"):
						t["_mean"]["sink_share_" + _flow_key(fl).substr(8)] = fl["sink_share"]
			if t.get("_mean") is Dictionary:  # years the run does not reach are not checked (net_year_<n>)
				for k: String in (t["_mean"] as Dictionary).keys():
					if k.begins_with("net_year_") and days < k.substr(9).to_int() * YEAR_DAYS:
						t["_mean"].erase(k)
			var fails: PackedStringArray = []
			if diff in ["", "normal"]:
				fails = _check(t, runs)
			var agg := _aggregate(t, runs)
			for fl: Dictionary in flows:  # GDD 4.23 order on this bot's first goldflow window
				if str(fl.get("bot", "")) == bot_id and agg.has("mean_" + _flow_key(fl)):
					means[diff] = agg["mean_" + _flow_key(fl)]
					break
			missed += fails.size()
			for f: String in fails:
				print("  MISS %s%s · %s" % [bot_id, "" if diff == "" else " (%s)" % diff, f])
			var out := {"scenario": scenario if start == "" else "", "start": start, "difficulty": diff, "bot": bot_id,
				"sets": sets,
				"days": days, "seeds": seeds, "aggregate": agg, "runs": runs, "misses": fails}
			var path := "res://reports/sim/%s%s_%s%s.json" % [("trial_%s_" % tag if tag != "" else "trial_") if not sets.is_empty() or tag != "" else "", label, bot_id,
				"" if diff in ["", "normal"] else "_" + diff]
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


## --set=<where>=<json>: true if the figure existed (only existing keys can be changed).
func _apply_set(cat: Catalog, spec: String) -> bool:
	var eq := spec.find("=")
	if eq < 0:
		return false
	var keys := spec.substr(0, eq).split(".")
	var value: Variant = JSON.parse_string(spec.substr(eq + 1))
	if value == null or keys.size() < 2:
		return false
	var node: Variant = null
	var i := 1
	if keys[0] in ["market", "employees", "production", "difficulty", "accounts", "seasons", "events", "town"]:
		node = cat.get(keys[0])
	elif keys[0] == "life" and keys.size() >= 3:  # vida: data/life/<file>.json
		node = cat.life_tables.get(keys[1])
		i = 2
	elif cat.tables.has(keys[0]) and keys.size() >= 3:
		node = (cat.tables[keys[0]] as Dictionary).get(keys[1])
		i = 2
	for k: int in range(i, keys.size() - 1):
		if not node is Dictionary or not (node as Dictionary).has(keys[k]):
			return false
		node = node[keys[k]]
	if not node is Dictionary or not (node as Dictionary).has(keys[keys.size() - 1]):
		return false
	node[keys[keys.size() - 1]] = value
	cat.goods_reset()  # H13: seasons.goods may have changed
	print("sim_runner: --set %s = %s" % [".".join(keys), value])
	return true


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
	var cycles: Array = []  # H5: [{minute, actor, std, real, hours}] cycles started in the player's buildings
	var ups: Array = []     # H5: [{upgrade, start, end, mult_before, mult_after}] production upgrades of the player
	var mev_days := {}  # H7: day -> microevents started for the player's family
	var ladder := sim.catalog.title_ladder()  # H9: title_<id>_day = day played it was granted (days + 1 if never)
	for t: Variant in ladder:
		m["title_%s_day" % t] = days + 1
		m["title_" + str(t)] = 0
	m["ai_title_ups"] = 0
	m["ai_titled"] = 0
	for k: String in ["office_won", "elections_run", "elections_won", "ai_office_runs", "ai_offices_won", "ai_ran"]:  # H10
		m[k] = 0
	m["office_won_day"] = days + 1
	for k: String in ["trials", "tried", "guilty", "ai_accusations", "ai_accusations_bad", "inspected"]:  # H11
		m[k] = 0
	m["trial_day"] = days + 1
	for k: String in ["forge_supplied", "kin_bought", "low_morale_hours"]:  # H14
		m[k] = 0
	for k: String in ["events_started", "events_declared", "events_ended", "events_max_active", "local_past_season",
			"event_days"]:  # H13
		m[k] = 0
	for k: String in sim.catalog.world_events():
		m["ev_" + k] = 0
	for k: String in ["duels_challenged", "duels_fought", "duels_won", "duels_lost", "duel_draws", "duel_no_show",
			"duels_refused", "brawls"]:  # duelo (docs/contratos/duelo.md)
		m[k] = 0
	for i: int in days * Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step(bot.orders(sim)):
			match str(e["type"]):
				"duel_challenged":
					if str(e.get("family", "")) == player:
						m["duels_challenged"] = int(m["duels_challenged"]) + 1
				"duel_brawl":
					if str(e.get("family", "")) == player:
						m["brawls"] = int(m["brawls"]) + 1
				"duel_finished":
					if str(e.get("family", "")) == player or str(e.get("target_family", "")) == player:
						var oc := str(e.get("outcome", ""))
						var w := str(e.get("winner", ""))
						if oc in ["fought", "yielded"]:
							m["duels_fought"] = int(m["duels_fought"]) + 1
							var mine := w != "" and str(sim.state.characters.get(w, {}).get("family", "")) == player
							m["duels_won" if mine else "duels_lost"] = int(m["duels_won" if mine else "duels_lost"]) + 1
						elif oc == "draw":
							m["duels_fought"] = int(m["duels_fought"]) + 1
							m["duel_draws"] = int(m["duel_draws"]) + 1
						elif oc == "refused":
							m["duels_refused"] = int(m["duels_refused"]) + 1
						elif oc == "no_show" and str(e.get("absent", "")) != "" and \
								str(sim.state.characters.get(str(e["absent"]), {}).get("family", "")) == player:
							m["duel_no_show"] = int(m["duel_no_show"]) + 1
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
				"title_granted":  # H9 (GDD 4.12.2)
					var played := Clock.day(int(sim.state.clock["minute"])) - Clock.day(start_minute) + 1
					if str(e.get("family", "")) == player:
						m["title_%s_day" % e["title"]] = played
						m["title_" + str(e["title"])] = 1
						print("  [%s seed %d] día %d: título %s (reputación %d)" % [bot_id, s, played, e["title"],
							Reputation.of(sim.state, player)])
					elif str(sim.state.families.get(str(e.get("family", "")), {}).get("ai_profile", "")) != "":
						m["ai_title_ups"] = int(m["ai_title_ups"]) + 1
						m["ai_titled"] = 1
						print("  [%s seed %d] día %d: la familia IA %s sube a %s" % [bot_id, s, played, e["family"],
							e["title"]])
				"office_candidate":  # H10 (GDD 4.12.4)
					var fe := str(e.get("family", ""))
					if fe == player:
						m["elections_run"] = int(m["elections_run"]) + 1
					elif str(sim.state.families.get(fe, {}).get("ai_profile", "")) != "":
						m["ai_office_runs"] = int(m["ai_office_runs"]) + 1
						m["ai_ran"] = 1
						print("  [%s seed %d] día %d: la familia IA %s se presenta a %s" % [bot_id, s,
							Clock.day(int(sim.state.clock["minute"])) - Clock.day(start_minute) + 1, fe, e["office"]])
				"market_bought":  # H14: a family member other than the head buys (Trade)
					if str(e.get("family", "")) == player and str(e.get("actor", "")) != Kin.head(sim.state, player):
						m["kin_bought"] = int(m["kin_bought"]) + 1
				"items_moved":
					if player != "" and str(e.get("to", "")) == Kin.workplace(sim, player) \
							and str(e.get("actor", "")) != Kin.head(sim.state, player) \
							and str(sim.catalog.item(str(e.get("item", ""))).get("category", "")) == "raw":
						m["forge_supplied"] = 1
				"needs_changed":
					if Needs.morale(sim, str(e.get("character", ""))) <= int(sim.catalog.family.get("morale", {}).get("low", 30)):
						m["low_morale_hours"] = int(m["low_morale_hours"]) + 1
				"trial_opened":  # H11 (GDD 4.12.5)
					var dt := Clock.day(int(sim.state.clock["minute"])) - Clock.day(start_minute) + 1
					var afm := str(e.get("accuser_family", ""))
					if str(e.get("family", "")) == player:
						if int(m["trials"]) == 0:
							m["trial_day"] = dt
						m["tried"] = 1
						m["trials"] = int(m["trials"]) + 1
						print("  [%s seed %d] día %d: juicio por %s (%s)" % [bot_id, s, dt, e["charge"], e["source"]])
					if str(e.get("source", "")) == "accusation" and str(sim.state.families.get(afm, {}).get("ai_profile",
							"")) != "":
						m["ai_accusations"] = int(m["ai_accusations"]) + 1
						var tr := Tribunal.trial(sim.state, str(e["trial"]))
						var fab_ok := Tribunal.honesty(sim, afm) <= int(sim.catalog.ai_profiles().get(str(
							sim.state.families[afm]["ai_profile"]), {}).get("accuse_rule", {}).get("fabricate_max_honesty", -30))
						if (bool(tr.get("fabricated", false)) and not fab_ok) or (not bool(tr.get("fabricated", false))
								and str(tr.get("fact", "")) == ""):
							m["ai_accusations_bad"] = int(m["ai_accusations_bad"]) + 1
				"trial_verdict":
					if str(e.get("family", "")) == player and str(e.get("verdict", "")) == "guilty":
						m["guilty"] = int(m["guilty"]) + 1
				"inspection":
					if str(e.get("family", "")) == player and bool(e.get("caught", false)):
						m["inspected"] = int(m["inspected"]) + 1
				"office_taken":
					var fo := str(e.get("family", ""))
					var dplayed := Clock.day(int(sim.state.clock["minute"])) - Clock.day(start_minute) + 1
					if fo == player:
						if int(m["office_won"]) == 0:
							m["office_won_day"] = dplayed
						m["office_won"] = 1
						print("  [%s seed %d] día %d: cargo %s" % [bot_id, s, dplayed, e["office"]])
					elif str(sim.state.families.get(fo, {}).get("ai_profile", "")) != "":
						m["ai_offices_won"] = int(m["ai_offices_won"]) + 1
				"election_held":
					for w: Variant in e.get("winners", []):
						if str(sim.state.characters.get(str(w), {}).get("family", "")) == player:
							m["elections_won"] = int(m["elections_won"]) + 1
				"theft":
					if str(e.get("family", "")) == player:
						var tk := "thefts_foiled" if bool(e.get("frustrated", false)) else "thefts"
						m[tk] = int(m.get(tk, 0)) + 1
				"employee_hired":
					if str(e.get("family", "")) == player:
						m["hired"] = int(m.get("hired", 0)) + 1
				"work_started":
					if player != "" and Money.family_of(sim.state, str(e["building"])) == player:
						var rec: Dictionary = sim.catalog.recipes().get(str(e["recipe"]), {})
						var now := int(sim.state.clock["minute"])
						cycles.append({"minute": now, "actor": str(e["actor"]),
							"std": Production.cycle_minutes(sim.catalog, rec, str(e["mode"])),
							"real": maxi(1, int(e["end"]) - now), "hours": float(rec.get("duration_hours", 0.0)),
							"speed": Staff.speed(sim, str(e["actor"])) if Staff.employer(sim.state, str(e["actor"])) != "" \
								else 1.0})
				"upgrade_started":
					if str(e.get("family", "")) == player:
						m["upgrades_bought"] = int(m.get("upgrades_bought", 0)) + 1
						m["upgrades_spent"] = int(m.get("upgrades_spent", 0)) + int(sim.catalog.upgrade(
							str(e["upgrade"])).get("cost", {}).get("gold", 0))
						if _speeds(sim, str(e["upgrade"])):
							ups.append({"upgrade": str(e["upgrade"]), "building": str(e["building"]),
								"start": int(e["start"]), "end": int(e["end"]),
								"mult_before": Upgrades.mult(sim, str(e["building"]), "production_speed")})
				"world_event_started":  # H13 (GDD 4.13)
					var dps := int(sim.catalog.time["days_per_season"])
					var day0 := Clock.day(int(e["start"]))
					m["events_started"] = int(m["events_started"]) + 1
					m["ev_" + str(e["def"])] = int(m.get("ev_" + str(e["def"]), 0)) + 1
					if str(e.get("by", "")) != "":
						m["events_declared"] = int(m["events_declared"]) + 1
					if str(sim.catalog.world_events().get(str(e["def"]), {}).get("scope", "")) == "local" \
							and int(e["end"]) > (day0 - day0 % dps + dps) * Clock.MINUTES_PER_DAY:
						m["local_past_season"] = int(m["local_past_season"]) + 1
					m["events_max_active"] = maxi(int(m["events_max_active"]), sim.state.events_active.size())
					print("  [%s seed %d] día %d: empieza el evento %s hasta el día %d" % [bot_id, s,
						Clock.day(int(sim.state.clock["minute"])) - Clock.day(start_minute) + 1, e["def"],
						ceili(float(int(e["end"])) / Clock.MINUTES_PER_DAY) - Clock.day(start_minute)])
				"world_event_ended":
					m["events_ended"] = int(m["events_ended"]) + 1
				"upgrade_done":
					for u: Dictionary in ups:
						if str(u["upgrade"]) == str(e["upgrade"]) and str(u["building"]) == str(e["building"]):
							u["mult_after"] = Upgrades.mult(sim, str(e["building"]), "production_speed")
		var done_days := i + 1
		if done_days % Clock.MINUTES_PER_DAY == 0:
			var d := done_days / Clock.MINUTES_PER_DAY
			if not sim.state.events_active.is_empty():  # H13
				m["event_days"] = int(m["event_days"]) + 1
			if d == 10:  # H3 rival: gold of the AI families with a profile at day 10
				m["rival_gold_day10"] = _rival_gold(sim)
			if player != "":  # windows measured when they close (the ledger keeps only 2 years in detail)
				_close_windows(sim, m, player, start_minute, d, flows)
			if player != "" and d in [3, 8, 10]:
				m["gold_day%d" % d] = Money.gold(sim.state, player)
				m["gold_repaid_day%d" % d] = Money.gold(sim.state, player) + repaid
	m["events_overdue"] = 0  # H13: an event in force past its end would be stuck
	for ev: Dictionary in sim.state.events_active:
		if int(ev.get("end", 0)) <= int(sim.state.clock["minute"]):
			m["events_overdue"] = int(m["events_overdue"]) + 1
	if player != "":  # viajes (09b): the region's counters of the player's family (trips, sales away, caravans, treaties)
		var rs: Dictionary = (sim.state.region.get("stats", {}) as Dictionary).get(player, {})
		for k: String in ["arrivals", "returns", "ambushes", "city_sales_gold", "city_sales_units", "city_buys_gold",
				"city_contracts_done", "caravans_sent", "caravans_arrived", "caravans_back", "caravan_ambushes",
				"treaties_signed", "treaties_broken"]:
			m["trv_" + k] = int(rs.get(k, 0))
		m["gold_end"] = Money.gold(sim.state, player)
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
		_production_gains(m, cycles, ups)
	for d: String in sim.catalog.microevents():  # H7: every microevent measured, also the ones that never came
		m["mev_" + d] = int(m.get("mev_" + d, 0))
	var most := 0
	for dd: Variant in mev_days:
		most = maxi(most, int(mev_days[dd]))
	m["mev_max_per_day"] = most
	for k: String in ["mev_timeouts", "counter_sold", "thefts", "thefts_foiled"]:
		m[k] = int(m.get(k, 0))
	m["townsfolk"] = Population.townsfolk(sim.state).size()
	if player != "":  # H9: where the family ended
		m["reputation"] = Reputation.of(sim.state, player)
		m["title_rank"] = Titles.rank(sim, Titles.current(sim, player))
	if bot.has_method("measures"):  # H8: a bot may measure its own things (dynasty: wedding, children, inheritance)
		m.merge(bot.call("measures", sim))
	m.merge({"seed": s, "days": days, "state_hash": sim.state_hash()})
	return m


## Goldflow windows and whole years (GDD 4.19) that end with day `d` played: net_day_<a>_<b>, by_category_<a>_<b>,
## sink_share_<a>_<b> and net_year_<n>, from the ledger entries of the player's family.
func _close_windows(sim: Sim, m: Dictionary, player: String, start_minute: int, d: int, flows: Array) -> void:
	if d % YEAR_DAYS == 0:
		var yc := _window(sim, player, start_minute, d - YEAR_DAYS + 1, d)
		var net_y := 0
		for c: String in yc:
			if not c in YEAR_EXCLUDE:
				net_y += int(yc[c])
		m["net_year_%d" % (d / YEAR_DAYS)] = snappedf(float(net_y) / YEAR_DAYS, 0.01)
	for fl: Dictionary in flows:
		var w: Array = fl["window_days"]
		if int(w[1]) != d:
			continue
		var excl: Array = fl.get("exclude_categories", [])
		var cats := _window(sim, player, start_minute, int(w[0]), int(w[1]))
		var net := 0
		var gross := 0
		var sinks := 0
		for c: String in cats:
			if not c in excl:
				net += int(cats[c])
				if int(cats[c]) > 0:
					gross += int(cats[c])
			if c in (fl.get("sink_categories", []) as Array):
				sinks -= int(cats[c])
		m[_flow_key(fl)] = snappedf(float(net) / float(int(w[1]) - int(w[0]) + 1), 0.01)
		m["by_category_" + _flow_key(fl).substr(8)] = cats
		if fl.has("sink_categories"):  # GDD 4.19: recurrent sinks / gross income of the window
			var inputs := 0  # what the income cost in materials (purchases and errands): gross margin = gross + this
			for c: String in (fl.get("input_categories", []) as Array):
				inputs += int(cats.get(c, 0))
			var w_key := _flow_key(fl).substr(8)
			m["sink_share_revenue_" + w_key] = snappedf(float(sinks) / maxf(1.0, float(gross)), 0.001)
			m["sink_share_margin_" + w_key] = snappedf(float(sinks) / maxf(1.0, float(gross + inputs)), 0.001)
			m["sink_share_" + w_key] = m["sink_share_%s_%s" % [str(fl.get("sink_base", "revenue")), w_key]]


## The player's ledger entries of days [first, last] played (1 = the first day), summed by category.
func _window(sim: Sim, player: String, start_minute: int, first: int, last: int) -> Dictionary:
	var lo := start_minute + (first - 1) * Clock.MINUTES_PER_DAY
	var hi := start_minute + last * Clock.MINUTES_PER_DAY
	var cats := {}
	for e: Dictionary in sim.state.ledger.get("entries", []):
		if str(e.get("family", "")) == player and int(e["minute"]) >= lo and int(e["minute"]) < hi:
			cats[str(e["category"])] = int(cats.get(str(e["category"]), 0)) + int(e["amount"])
	return cats


## H5: prod_gain_<upgrade> / prod_expected_<upgrade> / prod_gain_error and output_hours_<upgrade>_before/_after.
func _production_gains(m: Dictionary, cycles: Array, ups: Array) -> void:
	var worst := 0.0
	for u: Dictionary in ups:
		if not u.has("mult_after"):
			continue
		var span := PROD_DAYS * Clock.MINUTES_PER_DAY
		var before := _rate(cycles, int(u["start"]) - span, int(u["start"]))
		var after := _rate(cycles, int(u["end"]), int(u["end"]) + span)
		var id := str(u["upgrade"])
		m["output_hours_%s_before" % id] = snappedf(_output_hours(cycles, int(u["start"]) - span, int(u["start"])) / PROD_DAYS, 0.01)
		m["output_hours_%s_after" % id] = snappedf(_output_hours(cycles, int(u["end"]), int(u["end"]) + span) / PROD_DAYS, 0.01)
		if before <= 0.0 or after <= 0.0:
			continue
		var expected := float(u["mult_after"]) / maxf(float(u["mult_before"]), 0.01)
		m["prod_gain_" + id] = snappedf(after / before, 0.001)
		m["prod_expected_" + id] = snappedf(expected, 0.001)
		worst = maxf(worst, absf(after / before / expected - 1.0))
	m["prod_gain_error"] = snappedf(worst, 0.001)


## Mean over workers of (standard minutes / (real minutes × rank speed)) of the cycles started in [lo, hi): 0 if none.
## Without the rank's speed (a promotion in the window), the mean only moves with the building's upgrades.
func _rate(cycles: Array, lo: int, hi: int) -> float:
	var by := {}
	for c: Dictionary in cycles:
		if int(c["minute"]) >= lo and int(c["minute"]) < hi:
			var a := str(c["actor"])
			if not by.has(a):
				by[a] = [0.0, 0.0]
			by[a][0] += float(c["std"])
			by[a][1] += float(c["real"]) * float(c["speed"])  # the rank's speed out: only the upgrades remain
	return 0.0 if by.is_empty() else _mean_ratio(by)


func _mean_ratio(by: Dictionary) -> float:
	var sum := 0.0
	for a: String in by:
		sum += float(by[a][0]) / maxf(1.0, float(by[a][1]))
	return sum / by.size()


func _output_hours(cycles: Array, lo: int, hi: int) -> float:
	var h := 0.0
	for c: Dictionary in cycles:
		if int(c["minute"]) >= lo and int(c["minute"]) < hi:
			h += float(c["hours"])
	return h


func _speeds(sim: Sim, id: String) -> bool:
	for e: Dictionary in sim.catalog.upgrade(id).get("effects", []):
		if str(e.get("kind", "")) == "production_speed":
			return true
	return false


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


## Gold of the AI families with an ai_profile (the rival smith, GDD 4.5.5). H12: in a real new game only the ones with
## the profile of the start's rival (the competitor workshops of the other trades are not the rival smith).
func _rival_gold(sim: Sim) -> int:
	var only := str(sim.catalog.starts().get(str(sim.state.meta.get("start", "")), {}).get("rival", {}).get("profile", ""))
	var g := 0
	for f: String in sim.state.families:
		var prof := str(sim.state.families[f].get("ai_profile", ""))
		if prof != "" and (only == "" or prof == only):
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
	for key: String in ["gold_day3", "gold_repaid_day3", "gold_day10", "net_day_1_8", "net_day_9_24", "sink_share_9_24",
			"net_year_1", "net_year_2", "net_year_3", "hired", "upgrades_bought", "prod_gain_error", "debt_paid",
			"debt_paid_day", "rival_gold_day10", "title_citizen_day", "title_patrician_day", "reputation", "ai_title_ups", "office_won", "office_won_day",
			"ai_office_runs", "trials", "trial_day", "guilty", "events_started", "event_days"]:
		if agg.has("mean_" + key):
			parts.append("%s %s [%s-%s]" % [key, agg["mean_" + key], agg["min_" + key], agg["max_" + key]])
	return ", ".join(parts)
