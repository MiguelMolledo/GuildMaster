extends SceneTree
## The «jugador completo» and its chaotic twin play whole games with every system on (docs/gdd/07_testing.md §7.4):
##   godot --headless --path . -s tools/full_player.gd -- [--bot=full_player|chaos_player] [--years=3 | --generation]
##       [--seeds=3 | --seed-list=1,4,7] [--difficulty=normal] [--start=artisan_blacksmith] [--roundtrip]
##       [--tag=<name>] [--no-check]
## --years=N plays N years (8 days each; default 3 = 24 days). --generation plays until the founder dies and the heir
## has run the house GENERATION_TAIL days (at most until the founder's certain death age). Every switch is on: the
## global events, the living town and the festivals as data/ says (the targets of the other bots run some of them off:
## this one never does). chaos_player saves and loads the game every day and compares the hash (--roundtrip does it
## for full_player too).
## Writes reports/<bot>/<seed>.json (curves, family, unlocks, mechanics used and never touched with the reason, the
## real seconds between decisions, the refused orders, the stalls, the engine's errors and warnings, the bench) and
## reports/<bot>/summary.json; saves the game at the end and at the first stall in reports/<bot>/saves/. The HTML
## summary: python3 tools/full_report.py. Checks data/targets.json full_player / chaos_player (the measures of
## "_needs_days" only when the run is that long) and exits with 1 if one is missed.

const Watch := preload("res://tools/full_watch.gd")  # the rival families and the town
const FORMAT_VERSION: int = 2  # docs/contratos/informe_jugador_completo.md: bump it when a field changes meaning
const YEAR_DAYS: int = 8
const GENERATION_TAIL: int = 8          # days the heir plays after the inheritance
const STALL_HOURS: int = 12             # a character that does not move nor work this long is stalled
const QUEUE_STALL_DAY_MIN: int = 480    # day-phase minutes of a pending queue with staff and no work started
const HANG_MS: float = 2000.0           # a step slower than this counts as a hang
const SLOW_MS: float = 50.0
const SKIP: float = 8.0                 # «Saltar hasta…» (03b §3b.5.2), as BotPacing
const MERGE_S: float = 3.0
## Order type -> mechanic (what the report calls each thing the player can do).
const MECH: Dictionary = {"work_at": "forge_hand", "master_touch": "forge_hand", "live_forge": "live_forge",
	"queue_add": "queue", "queue_remove": "queue", "queue_move": "queue", "queue_loop": "queue", "queue_pause": "queue",
	"set_role": "queue", "buy": "market", "sell": "market", "accept_contract": "contracts",
	"deliver_contract": "contracts", "abandon_contract": "contracts", "hire": "staff", "fire": "staff",
	"promote": "staff", "bonus": "staff", "buy_upgrade": "upgrades", "repay_loan": "debt", "take_emergency_loan": "debt", "court_talk": "courtship",
	"court_gift": "courtship", "propose": "courtship", "designate_heir": "heir", "school_choice": "heir",
	"request_title": "titles", "run_for_office": "offices", "campaign_action": "offices", "use_office_power": "offices",
	"accuse": "tribunal", "trial_cross": "tribunal", "trial_rest": "tribunal", "witness_action": "tribunal",
	"duel_challenge": "duels", "duel_answer": "duels", "duel_move": "duels", "duel_auto": "duels",
	"travel": "travel", "return": "travel", "city_sell": "travel", "city_buy": "travel", "city_accept": "travel",
	"city_deliver": "travel", "buy_cart": "caravans", "caravan_send": "caravans", "sign_treaty": "treaties",
	"propose_town_treaty": "treaties", "festival_sponsor": "festivals", "festival_host_wedding": "festivals",
	"resolve_incident": "incidents", "give_alms": "incidents", "resolve_microevent": "microevents",
	"unlock_seen": "unlocks", "buy_building": "tavern", "inn_set_menu": "tavern", "inn_set_price": "tavern",
	"inn_set_special": "tavern", "inn_buy_license": "tavern", "inn_serve": "tavern", "inn_make_bed": "tavern",
	"game_play": "games", "game_bet": "bets", "game_enter": "games", "npc_talk": "town_talk", "npc_gift": "town_talk",
	"npc_flatter": "town_talk", "npc_insult": "town_talk", "npc_threaten": "town_talk"}
## Event -> mechanic, when the event (of the player's family) is what shows the use.
const MECH_EVENTS: Dictionary = {"counter_sold": "counter", "wedding": "wedding", "child_born": "children",
	"inheritance": "inheritance", "festival_contract_done": "festival_contracts", "caravan_arrived": "caravans",
	"treaty_signed": "treaties", "title_granted": "titles", "office_taken": "offices", "trial_opened": "tribunal",
	"duel_finished": "duels", "trip_arrived": "travel", "building_bought": "tavern", "game_played": "games",
	"game_bet_settled": "bets", "masterwork_made": "masterwork", "spec_delivered": "variant_contracts",
	"live_forge_done": "live_forge", "unlocked": "unlocks"}
## The mechanics a whole game should touch, and the file that says the system is in the game (else "not_in_game").
const MECHANICS: Dictionary = {"forge_hand": "", "live_forge": "res://data/live_forge.json", "queue": "",
	"market": "", "counter": "", "contracts": "", "festival_contracts": "", "staff": "", "upgrades": "", "debt": "",
	"courtship": "", "wedding": "", "children": "", "heir": "", "inheritance": "", "titles": "", "offices": "",
	"tribunal": "", "travel": "", "caravans": "", "treaties": "", "tavern": "res://sim/inn/inn.gd", "duels": "",
	"bets": "res://sim/games/betting.gd", "games": "res://sim/games/games.gd", "incidents": "", "microevents": "",
	"festivals": "", "unlocks": "res://data/unlocks.json", "masterwork": "res://data/live_forge.json",
	"variant_contracts": "res://data/live_forge.json"}


## Counts the engine's errors and warnings while the games run (Godot 4.5+ OS.add_logger).
class ErrLog extends Logger:
	var errors: int = 0
	var warnings: int = 0
	var lines: Array = []
	var _mx: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mx.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			errors += 1
		if lines.size() < 40:
			lines.append("%s: %s (%s:%d %s)" % ["WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR",
				rationale if rationale != "" else code, file, line, function])
		_mx.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Dictionary:
		_mx.lock()
		var d := {"errors": errors, "warnings": warnings, "lines": lines.duplicate()}
		errors = 0
		warnings = 0
		lines = []
		_mx.unlock()
		return d


var log_sink: ErrLog = ErrLog.new()


func _init() -> void:
	OS.add_logger(log_sink)
	var bot_id := "full_player"
	var years := 3
	var generation := false
	var seeds: Array = [1, 2, 3]
	var diff := "normal"
	var start := "artisan_blacksmith"
	var roundtrip := false
	var tag := ""
	var check := true
	var sets: Array = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--bot="):
			bot_id = a.substr(6)
		elif a.begins_with("--years="):
			years = maxi(1, a.substr(8).to_int())
		elif a == "--generation":
			generation = true
		elif a.begins_with("--seeds="):
			seeds = range(1, a.substr(8).to_int() + 1)
		elif a.begins_with("--seed-list="):
			seeds = []
			for x: String in a.substr(12).split(","):
				seeds.append(x.to_int())
		elif a.begins_with("--difficulty="):
			diff = a.substr(13)
		elif a.begins_with("--start="):
			start = a.substr(8)
		elif a == "--roundtrip":
			roundtrip = true
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a == "--no-check":
			check = false
		elif a.begins_with("--set="):  # equilibrio: a balance trial, as sim_runner's --set (with --tag)
			sets.append(a.substr(6))
	if not bot_id in ["full_player", "chaos_player", "idle_player"]:
		print("full_player: unknown bot %s" % bot_id)
		quit(2)
		return
	roundtrip = roundtrip or bot_id == "chaos_player"
	var cat := Catalog.load_from()
	for spec: Variant in sets:
		if not _apply_set(cat, str(spec)):
			print("full_player: bad --set %s" % spec)
			quit(2)
			return
	var targets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/targets.json"))
	var dir := "res://reports/%s%s" % [bot_id, "" if tag == "" else "_" + tag]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + "/saves"))
	var runs: Array = []
	var horizon := "generation" if generation else "%dy" % years
	for s: Variant in seeds:
		var r := NewGame.from_start(cat, start, diff, {"cast": "fixed"}, int(s))
		if not r["ok"]:
			print("full_player: %s: %s" % [start, r["error"]])
			quit(2)
			return
		var bot: Object = BotChaosPlayer.new(int(s)) if bot_id == "chaos_player" else (BotIdle.new() \
			if bot_id == "idle_player" else BotFullPlayer.new())  # idle_player: the player does nothing (the AI alone)
		for kv: String in OS.get_environment("BOT_VARS").split(",", false):  # trials: k=v ints, as sim_runner
			bot.set(kv.get_slice("=", 0), kv.get_slice("=", 1).to_int())
		var rep := _play(Sim.new(r["state"], cat), bot, bot_id, int(s), years * YEAR_DAYS, generation, roundtrip, dir)
		rep["horizon"] = horizon
		rep["difficulty"] = diff
		rep["start"] = start
		FileAccess.open("%s/%d.json" % [dir, int(s)], FileAccess.WRITE).store_string(JSON.stringify(rep, "\t"))
		runs.append(rep["measures"])
		print("full_player: %s seed %d · %d días · %s" % [bot_id, int(s), int(rep["days"]), _brief(rep["measures"])])
	var t: Dictionary = (targets.get(bot_id, {}) as Dictionary).duplicate(true)
	var played := int(runs[0].get("days", 0)) if not runs.is_empty() else 0
	for k: String in (t.get("_needs_days", {}) as Dictionary):  # measures a short run cannot judge
		if played < int(t["_needs_days"][k]):
			t.erase(k)
			for kind: String in ["_mean", "_share"]:
				if t.get(kind) is Dictionary:
					(t[kind] as Dictionary).erase(k)
	var fails: PackedStringArray = _check(t, runs) if check else PackedStringArray()
	for f: String in fails:
		print("  MISS %s · %s" % [bot_id, f])
	var proposed: Dictionary = (t.get("_proposed", {}) as Dictionary).duplicate()  # informed, never failing
	for k: String in (t.get("_needs_days", {}) as Dictionary):
		if played < int(t["_needs_days"][k]):
			proposed.erase(k)
	var pfails: PackedStringArray = _check(proposed, runs)
	for f: String in pfails:
		print("  PROPOSED %s · %s" % [bot_id, f])
	var summary := {"format_version": FORMAT_VERSION, "bot": bot_id, "horizon": horizon, "difficulty": diff, "start": start, "seeds": seeds,
		"aggregate": _aggregate(t, runs), "misses": fails, "proposed_misses": pfails, "targets": t, "runs": runs}
	FileAccess.open(dir + "/summary.json", FileAccess.WRITE).store_string(JSON.stringify(summary, "\t"))
	print("full_player: %s × %d seeds (%s) · %d misses · %s" % [bot_id, seeds.size(), horizon, fails.size(),
		dir + "/summary.json"])
	quit(1 if fails.size() > 0 else 0)


## One seed: plays and returns its report.
func _play(sim: Sim, bot: Object, bot_id: String, s: int, days: int, generation: bool, roundtrip: bool,
		dir: String) -> Dictionary:
	var st := sim.state
	log_sink.take()
	var fam := Life.player_family(st)
	var start_minute := int(st.clock["minute"])
	var start_day := Clock.day(start_minute)
	var founder := Kin.head(st, fam)
	var max_days := days
	if generation:
		var death: Dictionary = sim.catalog.family.get("death", {})
		max_days = (int(death.get("certain_age", 75)) - Kin.age(sim, founder) + 1) * YEAR_DAYS + GENERATION_TAIL
	var gold0 := {}
	for f: String in st.families:
		gold0[f] = Money.gold(st, f) - Ledger.total(st, f)
	var dues := {}
	for id: String in st.loans:
		if str(st.loans[id].get("family", "")) == fam:
			dues[id] = int(st.loans[id].get("due_minute", 0))
	var watch: RefCounted = Watch.new()
	watch.call("begin", sim, fam)
	var rep := {"format_version": FORMAT_VERSION, "seed": s, "bot": bot_id, "curve": [], "family": {"weddings": [], "births": [], "deaths": [],
		"inheritance": [], "heir": []}, "titles": [], "offices": [], "refused": {}, "refused_examples": [],
		"stalls": [], "contracts_failed": [], "saves": {}, "chaos": {}}
	var mech := {}   # mechanic -> {orders, refused, events, first_day}
	var m := {"refused_orders": 0, "contracts_done": 0, "contracts_failed": 0, "hired": 0, "upgrades_done": 0,
		"duels_fought": 0, "duels_won": 0, "trips": 0, "caravans": 0, "treaties": 0, "festival_contracts": 0,
		"counter_sold": 0, "incidents": 0, "trials_against": 0, "trials_as_accuser": 0, "children": 0,
		"wedding_day": -1, "first_child_day": -1, "inherit_day": -1, "founder_death_day": -1, "debt_paid": 0,
		"debt_paid_day": -1, "office_won_day": -1, "ending_day": -1, "masterworks": 0, "masterworks_y3": 0, "masterwork_day": -1,
		"spec_pieces": 0, "spec_mismatch": 0, "gold_min": Money.gold(st, fam),
		"facts_vs_others": 0, "fact_day_vs_others": -1, "caravan_home_value": 0, "caravan_sold": 0,
		"caravans_ambushed": 0, "city_sales_gold": 0, "quota_units": 0, "quota_gold": 0, "treaties_broken": 0,
		"treaty_costs": 0, "carts_bought": 0}
	for t: String in sim.catalog.title_ladder():
		m["title_%s_day" % t] = -1
	var paid := {}
	var step_us := PackedInt32Array()
	var bot_us := 0
	var hangs := 0
	var slow := 0
	# pacing (as BotPacing, 03b §3b.6)
	var clock_s := 0.0
	var last_decision := -1.0
	var gaps: Array = []
	var gaps_y1: Array = []  # the year 1 (03b §3b.6: median < 30 s, max < 60 s)
	var last_minute := start_minute
	# stalls
	var sig := {}       # character -> [signature, since minute]
	var stalled := {}   # character -> index in rep.stalls of its open stall
	var q_idle := 0     # day-phase minutes of a stalled queue
	var q_open := -1
	var first_stall_saved := false
	# chaos
	var rt := {"roundtrips": 0, "roundtrip_mismatch": 0, "gold_negative": 0, "off_map": 0, "hangs": 0,
		"load_errors": 0, "examples": []}
	var map_size: Array = sim.catalog.maps().get(st.map_id, {}).get("size", [0, 0])
	var played := 0
	var tail_until := -1
	var i := 0
	while true:
		var now := int(sim.state.clock["minute"])
		played = Clock.day(now) - start_day + 1
		if i >= max_days * Clock.MINUTES_PER_DAY:
			break
		if not sim.state.ending.is_empty() and int(m["ending_day"]) < 0:
			m["ending_day"] = played  # the player's game is over; the world goes on (the AI and the town are measured)
			if generation:
				break
		if not generation and i >= days * Clock.MINUTES_PER_DAY:
			break
		if generation and tail_until >= 0 and now >= tail_until:
			break
		var t0 := Time.get_ticks_usec()
		var given: Array = bot.orders(sim)
		var t1 := Time.get_ticks_usec()
		var ev := sim.step(given)
		var t2 := Time.get_ticks_usec()
		i += 1
		bot_us += t1 - t0
		step_us.append(t2 - t1)
		if float(t2 - t1) / 1000.0 > HANG_MS:
			hangs += 1
		elif float(t2 - t1) / 1000.0 > SLOW_MS:
			slow += 1
		st = sim.state
		now = int(st.clock["minute"])
		played = Clock.day(now) - start_day + 1
		watch.call("step", sim, ev, played)
		var mine := {}  # "type|actor" of the bot's orders this step
		for o: Dictionary in given:
			var k := str(MECH.get(str(o.get("type", "")), ""))
			mine["%s|%s" % [o.get("type", ""), o.get("actor", "")]] = k
			if k != "":
				_mech(mech, k, "orders", played)
		for e: Dictionary in ev:
			var et := str(e.get("type", ""))
			var efam := str(e.get("family", ""))
			if et == "order_refused":
				var key := "%s|%s" % [e.get("order", ""), e.get("actor", "")]
				if mine.has(key):
					m["refused_orders"] = int(m["refused_orders"]) + 1
					var rk := "%s|%s" % [e.get("order", ""), e.get("reason", "")]
					rep["refused"][rk] = int(rep["refused"].get(rk, 0)) + 1
					if str(mine[key]) != "":
						_mech(mech, str(mine[key]), "refused", played)
					if (rep["refused_examples"] as Array).size() < 60:
						rep["refused_examples"].append({"day": played, "minute": Clock.minute_of_day(now),
							"order": e.get("order", ""), "actor": e.get("actor", ""), "reason": e.get("reason", "")})
				continue
			if et == "fact_added" and efam != fam:  # Equilibrio 6: a public fact against another family (a case to accuse)
				m["facts_vs_others"] = int(m["facts_vs_others"]) + 1
				if int(m["fact_day_vs_others"]) < 0:
					m["fact_day_vs_others"] = played
				var fk := "fact_" + str(e.get("kind", ""))
				m[fk] = int(m.get(fk, 0)) + 1
			if et == "trial_opened" and str(e.get("accuser_family", "")) == fam:  # the accused is the other family
				m["trials_as_accuser"] = int(m["trials_as_accuser"]) + 1
				_mech(mech, "tribunal", "events", played)
			if efam != fam and not et in ["duel_finished", "election_held", "spec_piece"]:
				continue
			if MECH_EVENTS.has(et):
				_mech(mech, str(MECH_EVENTS[et]), "events", played)
			match et:
				"wedding":
					rep["family"]["weddings"].append({"day": played, "character": e.get("character", ""),
						"spouse": e.get("spouse", "")})
					if int(m["wedding_day"]) < 0:
						m["wedding_day"] = played
				"child_born":
					m["children"] = int(m["children"]) + 1
					rep["family"]["births"].append({"day": played, "child": e.get("character", ""),
						"mother": e.get("mother", ""), "father": e.get("father", "")})
					if int(m["first_child_day"]) < 0:
						m["first_child_day"] = played
				"character_died":
					rep["family"]["deaths"].append({"day": played, "character": e.get("character", ""),
						"age": e.get("age", 0), "cause": e.get("cause", "")})
					if str(e.get("character", "")) == founder:
						m["founder_death_day"] = played
				"inheritance":
					rep["family"]["inheritance"].append({"day": played, "from": e.get("from", ""), "heir": e.get("heir", ""),
						"generation": e.get("generation", 0), "regent": e.get("regent", "")})
					if int(m["inherit_day"]) < 0:
						m["inherit_day"] = played
						tail_until = now + GENERATION_TAIL * Clock.MINUTES_PER_DAY
				"heir_designated":
					rep["family"]["heir"].append({"day": played, "heir": e.get("heir", "")})
				"title_granted":
					rep["titles"].append({"day": played, "title": e.get("title", "")})
					m["title_%s_day" % e.get("title", "")] = played
				"office_taken":
					rep["offices"].append({"day": played, "office": e.get("office", ""), "character": e.get("character", "")})
					if int(m["office_won_day"]) < 0:
						m["office_won_day"] = played
				"loan_repaid":
					if not bool(e.get("extended", false)):
						paid[str(e.get("loan", ""))] = now
				"contract_delivered":
					m["contracts_done"] = int(m["contracts_done"]) + 1
				"contract_failed":
					m["contracts_failed"] = int(m["contracts_failed"]) + 1
					if (rep["contracts_failed"] as Array).size() < 40:
						rep["contracts_failed"].append({"day": played, "contract": e.get("contract", ""),
							"item": e.get("item", "")})
				"employee_hired":
					m["hired"] = int(m["hired"]) + 1
				"upgrade_done":
					m["upgrades_done"] = int(m["upgrades_done"]) + 1
				"duel_finished":
					if efam == fam or str(e.get("target_family", "")) == fam:
						if str(e.get("outcome", "")) in ["fought", "yielded", "draw"]:
							m["duels_fought"] = int(m["duels_fought"]) + 1
							_mech(mech, "duels", "events", played)
						var w := str(e.get("winner", ""))
						if w != "" and str(st.characters.get(w, {}).get("family", "")) == fam:
							m["duels_won"] = int(m["duels_won"]) + 1
				"trip_arrived":
					m["trips"] = int(m["trips"]) + 1
				"caravan_sent":
					m["caravans"] = int(m["caravans"]) + 1
					for cv: Dictionary in Region.ensure(sim)["caravans"]:  # Equilibrio 7: the cargo at home's price now
						if str(cv["id"]) == str(e.get("caravan", "")):
							for l: Dictionary in cv["cargo"]:
								m["caravan_home_value"] = int(m["caravan_home_value"]) + int(Market.sell_preview(sim,
									str(bot.get("ACTOR")), "armory", str(l["item"]), int(l["quality"]), int(l["qty"]))["total"])
				"caravan_arrived":
					m["caravan_sold"] = int(m["caravan_sold"]) + int(e.get("sold", 0))
				"caravan_ambushed":
					m["caravans_ambushed"] = int(m["caravans_ambushed"]) + 1
				"city_sold":
					m["city_sales_gold"] = int(m["city_sales_gold"]) + int(e.get("total", 0))
					m["quota_units"] = int(m["quota_units"]) + int(e.get("quota", 0))
					var qt := Treaties.quota_of(sim, str(e.get("city", "")), fam, str(e.get("item", "")))
					m["quota_gold"] = int(m["quota_gold"]) + int(e.get("quota", 0)) * int(qt.get("price", 0))
				"treaty_broken":
					m["treaties_broken"] = int(m["treaties_broken"]) + 1
					m["treaty_costs"] = int(m["treaty_costs"]) + int(e.get("penalty", 0))
				"cart_bought":
					m["carts_bought"] = int(m["carts_bought"]) + 1
				"treaty_signed":
					m["treaties"] = int(m["treaties"]) + 1
					m["treaty_costs"] = int(m["treaty_costs"]) + int(sim.catalog.trade.get("treaties", {}).get("kinds", {}) \
						.get(str(e.get("kind", "")), {}).get("fee", 0))
				"festival_contract_done":
					m["festival_contracts"] = int(m["festival_contracts"]) + 1
				"counter_sold":
					m["counter_sold"] = int(m["counter_sold"]) + 1
				"masterwork_made":  # forja viva (03b §3b.2): named masterworks
					m["masterworks"] = int(m["masterworks"]) + 1
					if played <= 3 * YEAR_DAYS:
						m["masterworks_y3"] = int(m["masterworks_y3"]) + 1  # the band is for 3 years (any horizon)
					if int(m["masterwork_day"]) < 0:
						m["masterwork_day"] = played
				"trial_opened":
					m["trials_against"] = int(m["trials_against"]) + 1
			if et == "spec_piece" and str(st.characters.get(str(e.get("actor", "")), {}).get("family", "")) == fam:
				m["spec_pieces"] = int(m["spec_pieces"]) + 1  # a piece made to a contract's variant (03b §3b.3)
				if not bool(e.get("match", false)):
					m["spec_mismatch"] = int(m["spec_mismatch"]) + 1
					var why := "spec_mismatch_" + str(e.get("why", ""))
					m[why] = int(m.get(why, 0)) + 1
		for e: Dictionary in ev:  # an incident of its family's buildings answered
			if str(e.get("type", "")) == "incident_ended":
				m["incidents"] = int(m["incidents"]) + 1
		# pacing: a game minute is real_seconds_per_day / 1440 at ×1, ×8 while the player would skip
		var actor := str(bot.get("ACTOR"))
		var spm := float(sim.catalog.time.get("real_seconds_per_day", 300)) / float(Clock.MINUTES_PER_DAY)
		clock_s += float(now - last_minute) * spm / (SKIP if _skipping(sim, actor) else 1.0)
		last_minute = now
		if not given.is_empty():
			if last_decision < 0.0:
				last_decision = clock_s
			elif clock_s - last_decision >= MERGE_S:
				gaps.append(clock_s - last_decision)
				if played <= YEAR_DAYS:
					gaps_y1.append(clock_s - last_decision)
				last_decision = clock_s
		m["gold_min"] = mini(int(m["gold_min"]), Money.gold(st, fam))
		# stalls: every hour
		if now % 60 == 0:
			watch.call("hour", sim, played)
			var found := _stalls(sim, fam, sig, stalled, rep, played, now)
			var qs := _queue_stalled(sim, actor)
			if qs and Clock.phase(now, sim.catalog.time) == "day":
				q_idle += 60
				if q_idle >= QUEUE_STALL_DAY_MIN and q_open < 0:
					q_open = (rep["stalls"] as Array).size()
					rep["stalls"].append({"kind": "queue", "who": "bld_0001", "from_day": played,
						"hours": q_idle / 60, "where": "queue pending with staff, no work started",
						"cause": _stall_cause(sim, fam)})
					found = true
				elif q_open >= 0:
					rep["stalls"][q_open]["hours"] = q_idle / 60
			elif not qs:
				q_idle = 0
				q_open = -1
			if found and not first_stall_saved:
				first_stall_saved = true
				var p := "%s/saves/%d_atasco.json" % [dir, s]
				SaveFile.save(st, ProjectSettings.globalize_path(p))
				rep["saves"]["first_stall"] = p
		if now % Clock.MINUTES_PER_DAY == 0:
			rep["curve"].append(_sample(sim, fam, played))
			watch.call("day", sim, played, YEAR_DAYS)
			if (played - 1) % YEAR_DAYS == 0 and played > 1:  # a whole year closed: net gold per day (as sim_runner)
				var y := (played - 1) / YEAR_DAYS
				var lo := start_minute + (y - 1) * YEAR_DAYS * Clock.MINUTES_PER_DAY
				var net := 0
				for le: Dictionary in st.ledger.get("entries", []):
					if str(le.get("family", "")) == fam and int(le["minute"]) >= lo and int(le["minute"]) < now \
							and str(le["category"]) != "loans":
						net += int(le["amount"])
				m["net_year_%d" % y] = snappedf(float(net) / YEAR_DAYS, 0.01)
			if roundtrip:
				var r: Variant = _roundtrip(sim, rt, played)
				if r is WorldState:
					sim.state = r
					st = r
			_invariants(sim, rt, played, map_size)
	m["hangs"] = hangs
	rt["hangs"] = hangs
	# debt
	if not dues.is_empty():
		var ok := 1
		var last := -1
		for id: String in dues:
			if not paid.has(id) or int(paid[id]) >= int(dues[id]):
				ok = 0
			else:
				last = maxi(last, Clock.day(int(paid[id])) - start_day + 1)
		m["debt_paid"] = ok
		m["debt_paid_day"] = last if ok == 1 else -1
	m["ledger_mismatch"] = 0
	for f: String in st.families:
		if Money.gold(st, f) - Ledger.total(st, f) != int(gold0.get(f, 0)):
			m["ledger_mismatch"] = int(m["ledger_mismatch"]) + 1
	played = i / Clock.MINUTES_PER_DAY
	m["days"] = played
	m["gold_end"] = Money.gold(st, fam)
	m["reputation"] = Reputation.of(st, fam)
	m["title_rank"] = Titles.rank(sim, Titles.current(sim, fam))
	m["inherited"] = 1 if int(m["inherit_day"]) >= 0 else 0
	m["game_over"] = 0 if st.ending.is_empty() else 1
	for t: String in sim.catalog.title_ladder():  # days + 1 if never (as sim_runner); title_<id> 1 if it got it
		m["title_" + t] = 1 if int(m["title_%s_day" % t]) >= 0 else 0
		if int(m["title_%s_day" % t]) < 0:
			m["title_%s_day" % t] = played + 1
	m["wed"] = 1 if int(m["wedding_day"]) >= 0 else 0
	m["had_child"] = 1 if int(m["children"]) > 0 else 0
	# bench
	var sorted := step_us.duplicate()
	sorted.sort()
	var tot := 0
	for x: int in step_us:
		tot += x
	var n := maxi(1, step_us.size())
	rep["bench"] = {"steps": step_us.size(), "step_ms_mean": snappedf(float(tot) / n / 1000.0, 0.001),
		"step_ms_p99": snappedf(float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))]) / 1000.0, 0.001) if sorted.size() > 0 else 0.0,
		"step_ms_max": snappedf(float(sorted[sorted.size() - 1]) / 1000.0, 0.001) if sorted.size() > 0 else 0.0,
		"bot_ms_mean": snappedf(float(bot_us) / n / 1000.0, 0.001), "slow_steps": slow, "hangs": hangs}
	for k: String in ["step_ms_mean", "step_ms_max", "bot_ms_mean"]:
		m[k] = rep["bench"][k]
	# pacing
	gaps.sort()
	rep["pacing"] = {"decisions": gaps.size() + (1 if last_decision >= 0.0 else 0),
		"gap_median_s": snappedf(float(gaps[gaps.size() / 2]), 0.1) if not gaps.is_empty() else 0.0,
		"gap_p90_s": snappedf(float(gaps[mini(gaps.size() - 1, int(gaps.size() * 0.9))]), 0.1) if not gaps.is_empty() else 0.0,
		"gap_max_s": snappedf(float(gaps.back()), 0.1) if not gaps.is_empty() else 0.0,
		"real_minutes": snappedf(clock_s / 60.0, 0.1)}
	gaps_y1.sort()
	rep["pacing"]["y1_gap_median_s"] = snappedf(float(gaps_y1[gaps_y1.size() / 2]), 0.1) if not gaps_y1.is_empty() else 0.0
	rep["pacing"]["y1_gap_max_s"] = snappedf(float(gaps_y1.back()), 0.1) if not gaps_y1.is_empty() else 0.0
	for k: String in ["gap_median_s", "gap_p90_s", "gap_max_s", "y1_gap_median_s", "y1_gap_max_s"]:
		m[k] = rep["pacing"][k]
	# unlocks (data/unlocks.json, the forja's pacing): the day each one came, against its 03b window
	rep["unlocks"] = _unlocks(sim, fam, start_day, played)
	var off := 0
	for u: Dictionary in rep["unlocks"]:
		if str(u.get("verdict", "")) in ["early", "late", "never"]:
			off += 1
	m["unlocks_off"] = off
	# mechanics: used and never touched, with why
	var info: Dictionary = bot.call("report", sim) if bot.has_method("report") else {}
	var why: Dictionary = info.get("why_not", {})
	var unl: Dictionary = {}
	for u: Dictionary in rep["unlocks"]:
		unl[str(u["id"])] = u
	var mechs := {}
	var used_n := 0
	var avail := 0
	for k: String in MECHANICS:
		var row: Dictionary = mech.get(k, {"orders": 0, "refused": 0, "events": 0, "first_day": -1})
		var in_game := str(MECHANICS[k]) == "" or ResourceLoader.exists(str(MECHANICS[k])) \
			or FileAccess.file_exists(str(MECHANICS[k]))
		var touched := int(row["orders"]) - int(row["refused"]) > 0 or int(row["events"]) > 0
		row["used"] = touched
		if not in_game:
			row["why"] = "not_in_game"
		elif not touched:
			row["why"] = str(why.get(k, "no_occasion"))
			if k == "inheritance" and int(m["founder_death_day"]) < 0:
				row["why"] = "founder_alive"
		else:
			used_n += 1
		if in_game:
			avail += 1
		mechs[k] = row
	rep["mechanics"] = mechs
	m["mechanics_used"] = used_n
	m["mechanics_in_game"] = avail
	m["stalls"] = (rep["stalls"] as Array).size()
	m["stalls_y3"] = (rep["stalls"] as Array).filter(func(x: Dictionary) -> bool:
		return int(x.get("from_day", 0)) <= 3 * YEAR_DAYS).size()  # the band is for 3 years (any horizon)
	# engine
	rep["engine"] = log_sink.take()
	m["engine_errors"] = int(rep["engine"]["errors"])
	m["engine_warnings"] = int(rep["engine"]["warnings"])
	# chaos
	rep["chaos"] = rt
	for k: String in ["roundtrips", "roundtrip_mismatch", "gold_negative", "off_map", "load_errors"]:
		m[k] = int(rt[k])
	# the bot's own measures (festivals, courtship, incidents) and its report
	if bot.has_method("measures"):
		var bm: Dictionary = bot.call("measures", sim)
		for k: String in bm:
			if not m.has(k) and typeof(bm[k]) in [TYPE_INT, TYPE_FLOAT]:
				m["bot_" + k] = bm[k]
	rep["bot_report"] = info
	rep.merge(watch.call("report"))
	var wm: Dictionary = watch.call("measures", played, YEAR_DAYS)
	m.merge(wm)
	rep["days"] = played
	var endp := "%s/saves/%d_fin.json" % [dir, s]
	SaveFile.save(st, ProjectSettings.globalize_path(endp))
	rep["saves"]["end"] = endp
	m["seed"] = s
	m["state_hash"] = sim.state_hash()
	rep["measures"] = m
	return rep


func _mech(mech: Dictionary, k: String, what: String, day: int) -> void:
	if not mech.has(k):
		mech[k] = {"orders": 0, "refused": 0, "events": 0, "first_day": -1}
	mech[k][what] = int(mech[k][what]) + 1
	if what != "refused" and int(mech[k]["first_day"]) < 0:
		mech[k]["first_day"] = day


## Whether a player would skip time now (BotPacing._skipping): on the road to another town, or not walking and the night
## or its own cycle running.
func _skipping(sim: Sim, actor: String) -> bool:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	if Region.is_away(sim.state, actor) and Travel.in_city(sim.state, actor) == "":
		return true  # equilibrio: on the road between two towns «Saltar hasta…» goes to the arrival (09b, 03b §3b.5.2)
	if not (ch.get("path", []) as Array).is_empty():
		return false
	if Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time) == "night":
		return true
	return Production.job_zone(sim, actor, str(ch.get("location", ""))) != ""


## The day's point of the curves.
func _sample(sim: Sim, fam: String, played: int) -> Dictionary:
	var st := sim.state
	var debt := 0
	for id: String in Loans.of_family(sim, fam):
		var ls := Loans.status(sim, id)
		if str(ls["state"]) in ["active", "extended"]:
			debt += int(ls["outstanding"])
	var offices: Array = []
	var members := 0
	var children := 0
	for c: Variant in st.families[fam].get("members", []):
		var id := str(c)
		if not Kin.alive(st, id):
			continue
		members += 1
		if not Kin.is_adult(sim, id):
			children += 1
		var o := Offices.of_character(st, id)
		if o != "":
			offices.append(o)
	var staff := 0
	for c: String in st.characters:
		var job: Variant = st.characters[c].get("job")
		if job is Dictionary and str(st.buildings.get(str(job.get("building", "")), {}).get("owner", "")) == fam:
			staff += 1
	return {"day": played, "gold": Money.gold(st, fam), "debt": debt, "title": Titles.current(sim, fam),
		"title_rank": Titles.rank(sim, Titles.current(sim, fam)), "reputation": Reputation.of(st, fam),
		"offices": offices, "members": members, "children": children, "staff": staff,
		"head": Kin.head(st, fam)}


## Characters of the family's group and its employees that neither moved nor worked STALL_HOURS: a stall.
func _stalls(sim: Sim, fam: String, sig: Dictionary, stalled: Dictionary, rep: Dictionary, played: int,
		now: int) -> bool:
	var st := sim.state
	var who: Array = Kin.group(st, fam)
	for c: String in st.characters:
		var job: Variant = st.characters[c].get("job")
		if job is Dictionary and str(st.buildings.get(str(job.get("building", "")), {}).get("owner", "")) == fam \
				and not c in who:
			who.append(c)
	var found := false
	for c: String in who:
		var ch: Dictionary = st.characters[c]
		if not Kin.alive(st, c) or not Kin.is_adult(sim, c) or Region.is_away(st, c) \
				or (ch.get("job") is Dictionary and not Staff.is_active(sim, c)) \
				or (ch.get("job") is Dictionary and not InnStaff.in_shift(sim, c, str(ch["job"].get("building", "")))):
			# not started yet, a day off, sick, or out of its shift (the tavern's night shift sleeps by day)
			sig.erase(c)
			continue
		var loc := str(ch.get("location", ""))
		var z := Production.job_zone(sim, c, loc) if loc != "" else ""
		var job_start := ""
		if z != "":
			job_start = str(st.buildings[loc]["zones"][z].get("job", {}).get("start", ""))
		var s := "%s|%s|%s|%s|%s" % [ch.get("position", []), loc, ch.get("station", ""), z, job_start]
		if not sig.has(c) or str(sig[c][0]) != s:
			sig[c] = [s, now]
			stalled.erase(c)
			continue
		var hours := (now - int(sig[c][1])) / 60
		if hours < STALL_HOURS:
			continue
		if stalled.has(c):
			rep["stalls"][int(stalled[c])]["hours"] = hours
			continue
		stalled[c] = (rep["stalls"] as Array).size()
		var role := "head" if c == Kin.head(st, fam) else ("employee" if ch.get("job") is Dictionary else "kin")
		rep["stalls"].append({"kind": "character", "who": c, "name": str(ch.get("name", "")), "role": role,
			"from_day": played, "hours": hours, "where": loc if loc != "" else str(ch.get("position", [])),
			"cause": _stall_cause(sim, fam)})
		found = true
	return found


## Why the forge stands still now (a guess for the report): under_works (an upgrade closes it), no_gold (no raw
## materials in the storage and no gold to buy them), no_materials, or "".
func _stall_cause(sim: Sim, fam: String) -> String:
	var st := sim.state
	if not st.buildings.has("bld_0001"):
		return ""
	if Upgrades.blocks(st, "bld_0001"):
		return "under_works"
	var pending := false
	for e: Dictionary in st.buildings["bld_0001"].get("queue", {}).get("entries", []):
		if int(e["qty"]) == WorkQueue.INFINITE or int(e["done"]) < int(e["qty"]):
			pending = true
	if not pending and not Staff.employees_of(st, "bld_0001").is_empty():
		return "empty_queue"
	var inv: Dictionary = st.buildings["bld_0001"]["inventory"]
	if Inventory.count(inv, "iron") + Inventory.count(inv, "iron_ingot") == 0 or Inventory.count(inv, "coal") == 0:
		return "no_gold" if Money.gold(st, fam) < 20 else "no_materials"
	return ""


## The forge's queue has work pending, staff at it, and nobody started a cycle: true.
func _queue_stalled(sim: Sim, _actor: String) -> bool:
	var st := sim.state
	var forge := "bld_0001"
	if not st.buildings.has(forge):
		return false
	var pending := false
	for e: Dictionary in st.buildings[forge].get("queue", {}).get("entries", []):
		if (int(e["qty"]) == WorkQueue.INFINITE or int(e["done"]) < int(e["qty"])) and not bool(e.get("paused", false)):
			pending = true
	if not pending:
		return false
	var staff := 0
	var working := 0
	for c: String in Staff.employees_of(st, forge):
		if Staff.is_active(sim, c):
			staff += 1
			if Production.job_zone(sim, c, forge) != "":
				working += 1
	return staff > 0 and working == 0


## Saves and loads the game in memory and compares the fingerprint; returns the loaded state (the game goes on with
## it, as a player who saved and loaded) or null when it could not load.
func _roundtrip(sim: Sim, rt: Dictionary, played: int) -> Variant:
	var before := sim.state.to_dict()
	var h1 := SaveFile.canonical(before).md5_text()
	var r := SaveFile.from_text(JSON.stringify(before, "\t", true, true))
	rt["roundtrips"] = int(rt["roundtrips"]) + 1
	if not r["ok"]:
		rt["load_errors"] = int(rt["load_errors"]) + 1
		_example(rt, "día %d: no carga (%s)" % [played, r["error"]])
		return null
	var after: WorldState = r["state"]
	var h2 := SaveFile.canonical(after.to_dict()).md5_text()
	if h1 != h2:
		rt["roundtrip_mismatch"] = int(rt["roundtrip_mismatch"]) + 1
		_example(rt, "día %d: el hash cambia al guardar y cargar (%s)" % [played, _first_diff(before, after.to_dict(), "")])
	return after


func _first_diff(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b) and not (typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]):
		return "%s: %s -> %s" % [path, type_string(typeof(a)), type_string(typeof(b))]
	if a is Dictionary:
		var keys: Array = (a as Dictionary).keys()
		for k: Variant in (b as Dictionary).keys():
			if not k in keys:
				keys.append(k)
		for k: Variant in keys:
			if not (a as Dictionary).has(k) or not (b as Dictionary).has(k):
				return "%s.%s: missing on one side" % [path, k]
			var d := _first_diff(a[k], b[k], "%s.%s" % [path, k])
			if d != "":
				return d
		return ""
	if a is Array:
		if (a as Array).size() != (b as Array).size():
			return "%s: size %d -> %d" % [path, (a as Array).size(), (b as Array).size()]
		for i: int in (a as Array).size():
			var d := _first_diff(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	if SaveFile.canonical(a) != SaveFile.canonical(b):
		return "%s: %s -> %s" % [path, str(a).left(40), str(b).left(40)]
	return ""


## Impossible states: negative gold, a character off the map.
func _invariants(sim: Sim, rt: Dictionary, played: int, size: Array) -> void:
	var st := sim.state
	for f: String in st.families:
		if Money.gold(st, f) < 0:
			rt["gold_negative"] = int(rt["gold_negative"]) + 1
			_example(rt, "día %d: %s con oro %d" % [played, f, Money.gold(st, f)])
	if size.size() < 2:
		return
	for c: String in st.characters:
		var ch: Dictionary = st.characters[c]
		if not bool(ch.get("alive", true)) or str(ch.get("location", "")) != "" or Region.is_away(st, c):
			continue
		var p: Array = ch.get("position", [])
		if p.size() != 2:
			continue
		if int(p[0]) < 0 or int(p[1]) < 0 or int(p[0]) >= int(size[0]) or int(p[1]) >= int(size[1]):
			rt["off_map"] = int(rt["off_map"]) + 1
			_example(rt, "día %d: %s fuera del mapa en %s" % [played, c, p])


func _example(rt: Dictionary, s: String) -> void:
	if (rt["examples"] as Array).size() < 30:
		rt["examples"].append(s)
	print("  [chaos] " + s)


## data/unlocks.json (the forja's pacing): for each unlock its day (day index, as the windows), its window and a
## verdict: on_time, early, late, never, not_judged (its window ends after the days played), hook_missing.
func _unlocks(sim: Sim, fam: String, start_day: int, played: int) -> Array:
	var out: Array = []
	if not FileAccess.file_exists("res://data/unlocks.json"):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/unlocks.json"))
	if not data is Dictionary:
		return out
	var got: Variant = sim.state.get("unlocks")
	var mine: Dictionary = (got as Dictionary).get(fam, {}) if got is Dictionary and (got as Dictionary).get(fam) is Dictionary else {}
	for d: Dictionary in data.get("unlocks", []):
		var id := str(d["id"])
		var w: Array = d.get("window", [0, 0])
		var day := -1
		if mine.get(id) is Dictionary:
			day = Clock.day(int(mine[id].get("minute", 0))) - start_day
		var req := str(d.get("requires", ""))
		var verdict := "on_time"
		if req != "" and not FileAccess.file_exists("res://data/%s.json" % req) and not DirAccess.dir_exists_absolute("res://data/" + req):
			verdict = "hook_missing"
		elif day < 0:
			verdict = "never" if int(w[1]) <= played - 1 else "not_judged"
		elif day < int(w[0]) - 1:
			verdict = "early"
		elif day > int(w[1]) + 1:
			verdict = "late"
		out.append({"id": id, "day": day, "window": w, "verdict": verdict})
	return out


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


func _aggregate(t: Dictionary, runs: Array) -> Dictionary:
	var out := {}
	if runs.is_empty():
		return out
	for key: String in runs[0]:
		if key in ["seed", "state_hash"] or not typeof(runs[0][key]) in [TYPE_INT, TYPE_FLOAT]:
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


func _brief(m: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: String in ["gold_end", "debt_paid_day", "title_citizen_day", "wedding_day", "children", "office_won_day",
			"mechanics_used", "refused_orders", "stalls", "engine_errors", "step_ms_mean", "step_ms_max",
			"gap_median_s", "gap_max_s", "roundtrip_mismatch"]:
		if m.has(k):
			parts.append("%s %s" % [k, m[k]])
	return ", ".join(parts)


## --set=<where>=<json> (equilibrio): one figure of the loaded catalog for this run only, as sim_runner's (with
## upgrade_rules, trade, family, accounts and town too).
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
	if keys[0] in ["market", "employees", "production", "difficulty", "accounts", "seasons", "events", "town",
			"upgrade_rules", "trade", "family", "inn", "live_forge"]:
		node = cat.get(keys[0])
	elif keys[0] == "life" and keys.size() >= 3:
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
	cat.goods_reset()
	print("full_player: --set %s = %s" % [".".join(keys), value])
	return true
