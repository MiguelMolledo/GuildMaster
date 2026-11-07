extends SceneTree
## H13 (docs/gdd/10_hitos.md fila H13, 04c 4.21.12): Bellcaire with its 5 rival families, played `days` days (80 = 10
## years) per seed and difficulty by the bot artisan_expert from a real new game in the capital (NewGame.from_start,
## choices.city capital, cast fixed), everything as data/ says (life, events, festivals). Per run it measures:
##   prod_share_max  the largest share of the map's production plots (data/maps plots, zone production) one family
##                   owned at any dawn (target: <= 0.6)
##   ai_titled       AI families that rose in title (target: >= 2)
##   player_attacks  attacks of the AI families on the player (town.rivalry.attacks; target: 1-4)
##   attacks         every attack by kind; ai_vs_ai the ones between AI families
##   net_gold        the player's gold minus what it owes at the end, minus the same at the start (4.23's order:
##                   easy > normal > hard, the median of the seeds)
##   refused_ai      orders of the AI families refused (target: 0), refused_player
##   ai_broke_days   days an AI family ended with no gold (target: <= 10 per game); ai_broke_streak the longest run of
##                   one family (target: <= 5); employees_max, sabotages
##   rivalry_max     the highest rivalry of an AI family towards the player
##   /opt/homebrew/bin/godot --headless --quiet --path . -s tools/ai/h13_probe.gd -- [--days=80] [--seeds=3]
##       [--difficulties=normal,easy,hard] [--short]
## --short (the QA step of tools/qa/run_all.py): 1 seed of Normal and Hard, 24 days; it checks the refused AI orders,
## the production share and the AI families without gold (Normal <= 10 days-family, Hard <= 20; streaks <= 5), not
## what needs the 80 days (titles, attacks, their order); reports/sim/h13_probe_short.json.
## Hard (manager, 2026-11-07): <= 20 days-family without gold and streaks <= 5 per seed too.
## Writes reports/sim/h13_probe.json; exits with 1 if a Normal target fails (production share, titles, attacks in
## at least 80 % of the seeds, refused AI orders, AI families without gold, attacks between AI families and a
## sabotage) or the order of net gold (easy > normal > hard) or of attacks (easy <= normal <= hard, medians) is broken.

const START: String = "artisan_blacksmith"


func _init() -> void:
	var days := 80
	var seeds := 3
	var diffs: PackedStringArray = ["normal", "easy", "hard"]
	var short := "--short" in OS.get_cmdline_user_args()
	if short:  # the QA step (tools/qa/run_all.py h13): one seed of Normal and Hard, 24 days
		days = 24
		seeds = 1
		diffs = ["normal", "hard"]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = a.substr(7).to_int()
		elif a.begins_with("--seeds="):
			seeds = a.substr(8).to_int()
		elif a.begins_with("--difficulties="):
			diffs = a.substr(15).split(",", false)
	var cat := Catalog.load_from()
	var out := {"days": days, "seeds": seeds, "runs": []}
	var by_diff := {}
	for d: String in diffs:
		by_diff[d] = []
		for s: int in range(1, seeds + 1):
			var r := NewGame.from_start(cat, START, d, {"city": "capital", "cast": "fixed"}, s)
			if not bool(r.get("ok", false)):
				printerr("h13_probe: %s" % r.get("error", ""))
				quit(2)
				return
			var t0 := Time.get_ticks_msec()
			var m := _run(Sim.new(r["state"], cat), BotArtisanExpert.new(), days)
			m["difficulty"] = d
			m["seed"] = s
			m["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
			(out["runs"] as Array).append(m)
			(by_diff[d] as Array).append(m)
			printerr("h13_probe: %-6s seed %d · cuota producción máx %.2f · IA que suben de título %d · ataques al jugador %d %s · IA contra IA %d · oro neto %d · rechazadas IA %d / jugador %d · días IA sin oro %d (racha %d) · sabotajes %d · empleados IA máx %d · rivalidad máx %d (%.0f s)" % [
				d, s, float(m["prod_share_max"]), int(m["ai_titled"]), int(m["player_attacks"]), m["attacks"],
				int(m["ai_vs_ai"]), int(m["net_gold"]), int(m["refused_ai"]), int(m["refused_player"]),
				int(m["ai_broke_days"]), int(m["ai_broke_streak"]), int(m["sabotages"]), int(m["employees_max"]),
				int(m["rivalry_max"]), float(m["seconds"])])
	var bad: Array = []
	var normal: Array = by_diff.get("normal", [])
	var in_band := 0
	if not normal.is_empty():
		for m: Dictionary in normal:
			if float(m["prod_share_max"]) > 0.6:
				bad.append("seed %d: una familia con %.0f %% de las parcelas de producción" % [m["seed"], float(m["prod_share_max"]) * 100])
			if int(m["refused_ai"]) > 0:
				bad.append("seed %d: %d órdenes de la IA rechazadas" % [m["seed"], m["refused_ai"]])
			if int(m["player_attacks"]) >= 1 and int(m["player_attacks"]) <= 4:
				in_band += 1
			if int(m["ai_broke_days"]) > 10:
				bad.append("seed %d: %d días-familia IA sin oro (> 10)" % [m["seed"], m["ai_broke_days"]])
			if int(m["ai_broke_streak"]) > 5:
				bad.append("seed %d: una familia IA %d días seguidos sin oro (> 5)" % [m["seed"], m["ai_broke_streak"]])
		if short:
			normal = []  # the short run checks only what 24 days can say (below)
	if short:
		for m: Dictionary in by_diff.get("hard", []):
			if float(m["prod_share_max"]) > 0.6:
				bad.append("%s: una familia con %.0f %% de las parcelas de producción" % [m["difficulty"], float(m["prod_share_max"]) * 100])
	if not normal.is_empty():
		var titled: Array = normal.map(func(m: Dictionary) -> int: return int(m["ai_titled"]))
		titled.sort()
		if int(titled[titled.size() / 2]) < 2:
			bad.append("mediana de familias IA que suben de título %d (< 2)" % titled[titled.size() / 2])
		if float(in_band) / float(normal.size()) < 0.8:
			bad.append("ataques al jugador entre 1 y 4 en %d de %d semillas (< 80 %%)" % [in_band, normal.size()])
	for m: Dictionary in by_diff.get("hard", []):  # manager, 2026-11-07: Hard too, without lowering the pressure
		if int(m["ai_broke_days"]) > 20:
			bad.append("difícil seed %d: %d días-familia IA sin oro (> 20)" % [m["seed"], m["ai_broke_days"]])
		if int(m["ai_broke_streak"]) > 5:
			bad.append("difícil seed %d: una familia IA %d días seguidos sin oro (> 5)" % [m["seed"], m["ai_broke_streak"]])
		if short and int(m["refused_ai"]) > 0:
			bad.append("difícil: %d órdenes de la IA rechazadas" % m["refused_ai"])
	var med := {}
	for d: String in by_diff:
		var g: Array = (by_diff[d] as Array).map(func(m: Dictionary) -> int: return int(m["net_gold"]))
		g.sort()
		if not g.is_empty():
			med[d] = int(g[g.size() / 2])
	out["net_gold_median"] = med
	var att := {}
	for d: String in by_diff:
		var g: Array = (by_diff[d] as Array).map(func(m: Dictionary) -> int: return int(m["player_attacks"]))
		g.sort()
		if not g.is_empty():
			att[d] = int(g[g.size() / 2])
	out["player_attacks_median"] = att
	if att.has("easy") and att.has("normal") and att.has("hard") \
			and not (int(att["easy"]) <= int(att["normal"]) and int(att["normal"]) <= int(att["hard"])):
		bad.append("orden de ataques roto: fácil %d, normal %d, difícil %d" % [att["easy"], att["normal"], att["hard"]])
	if not normal.is_empty() and not short:
		var ai_vs_ai := 0
		var sab := 0
		for m: Dictionary in normal:
			ai_vs_ai += int(m["ai_vs_ai"])
			sab += int(m["sabotages"])
		if ai_vs_ai == 0:
			bad.append("Normal: ningún ataque entre familias IA")
		if sab == 0:
			bad.append("Normal: ningún sabotaje")
	if med.has("easy") and med.has("normal") and med.has("hard") \
			and not (int(med["easy"]) > int(med["normal"]) and int(med["normal"]) > int(med["hard"])):
		bad.append("orden de oro neto roto: fácil %d, normal %d, difícil %d" % [med["easy"], med["normal"], med["hard"]])
	out["failures"] = bad
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/sim"))
	FileAccess.open("res://reports/sim/h13_probe%s.json" % ("_short" if short else ""), FileAccess.WRITE).store_string(JSON.stringify(out, "\t"))
	printerr("h13_probe: oro neto (mediana) %s · ataques al jugador (mediana) %s · %s" % [med, att, "todo bien" if bad.is_empty() else "FALLA: " + "; ".join(bad)])
	quit(1 if not bad.is_empty() else 0)


func _player(st: WorldState) -> String:
	for f: String in st.families:
		if str(st.families[f].get("controlled_by", "")) == "human":
			return f
	return ""


func _worth(sim: Sim, f: String) -> int:
	var owed := 0
	for id: String in sim.state.loans:
		var l: Dictionary = sim.state.loans[id]
		if str(l.get("family", "")) == f and Loans.is_open(l):
			owed += int(l.get("outstanding", 0))
	return Money.gold(sim.state, f) - owed


func _run(sim: Sim, bot: Object, days: int) -> Dictionary:
	var st := sim.state
	var me := _player(st)
	var m := {"prod_share_max": 0.0, "ai_titled": 0, "player_attacks": 0, "attacks": {}, "ai_vs_ai": 0, "net_gold": 0,
		"refused_ai": 0, "refused_player": 0, "ai_broke_days": 0, "ai_broke_streak": 0, "rivalry_max": 0, "reasons": {},
		"sabotages": 0, "employees_max": 0}
	var streak := {}
	var worth0 := _worth(sim, me)
	var titled := {}
	var plots: Array = []
	for p: Dictionary in sim.catalog.maps().get(st.map_id, {}).get("plots", []):
		if str(p.get("zone", "")) == "production":
			plots.append(p)
	for i: int in days * Clock.MINUTES_PER_DAY:
		var ev := sim.step(bot.orders(sim))
		for e: Dictionary in ev:
			match str(e.get("type", "")):
				"order_refused":
					var actor := str(e.get("actor", ""))
					var fam := str(st.characters.get(actor, {}).get("family", ""))
					var why := "%s:%s" % [e.get("order", ""), e.get("reason", "")]
					if str(st.families.get(fam, {}).get("ai_profile", "")) != "":  # the rival families, not the townsfolk
						m["refused_ai"] = int(m["refused_ai"]) + 1
						m["reasons"][why] = int(m["reasons"].get(why, 0)) + 1
					elif fam == me:
						m["refused_player"] = int(m["refused_player"]) + 1
				"title_granted":
					var f := str(e.get("family", ""))
					if str(st.families.get(f, {}).get("controlled_by", "")) == "ai":
						titled[f] = true
				"phase_changed":
					if str(e.get("phase", "")) == "dawn":
						m["prod_share_max"] = maxf(float(m["prod_share_max"]), _share(st, plots))
						var staff := 0
						for f: String in st.families:
							var fd: Dictionary = st.families[f]
							if str(fd.get("controlled_by", "")) != "ai" or str(fd.get("ai_profile", "")) == "":
								continue
							staff += Staff.employees_of(st, Hostility._workshop_of(st, f)).size()
							if Money.gold(st, f) <= 0:
								m["ai_broke_days"] = int(m["ai_broke_days"]) + 1
								streak[f] = int(streak.get(f, 0)) + 1
								m["ai_broke_streak"] = maxi(int(m["ai_broke_streak"]), int(streak[f]))
							else:
								streak[f] = 0
						m["employees_max"] = maxi(int(m["employees_max"]), staff)
		if i % 60 == 0:
			for f: String in st.families:
				m["rivalry_max"] = maxi(int(m["rivalry_max"]), Hostility.value(st, f, me))
	m["ai_titled"] = titled.size()
	for a: Dictionary in Hostility.book(st).get("attacks", []):
		m["attacks"][str(a["kind"])] = int(m["attacks"].get(str(a["kind"]), 0)) + 1
		if str(a["kind"]) == "sabotage":
			m["sabotages"] = int(m["sabotages"]) + 1
		if bool(a.get("player", false)):
			m["player_attacks"] = int(m["player_attacks"]) + 1
		else:
			m["ai_vs_ai"] = int(m["ai_vs_ai"]) + 1
	m["net_gold"] = _worth(sim, me) - worth0
	return m


## The largest share of the production plots one family holds now (a business plot is its site's building's owner).
func _share(st: WorldState, plots: Array) -> float:
	if plots.is_empty():
		return 0.0
	var site_owner := {}
	for b: String in st.buildings:
		var bd: Dictionary = st.buildings[b]
		site_owner[str(bd.get("site", ""))] = str(bd.get("owner", ""))
	var count := {}
	for p: Dictionary in plots:
		var o := str(site_owner.get(str(p.get("site", "")), ""))
		if o != "":
			count[o] = int(count.get(o, 0)) + 1
	var best := 0
	for o: String in count:
		best = maxi(best, int(count[o]))
	return float(best) / float(plots.size())
