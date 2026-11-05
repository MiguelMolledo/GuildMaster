extends SceneTree
## Whether each town of the region lives (plantillas, docs/contratos/vida.md): a real new game in every settlement
## (NewGame.from_start with choices.city, cast "fixed" like sim_runner), with the living town II on, played `days`
## days per seed with each bot. Per run it measures:
##   refused (orders refused, by reason), stuck_max (most townsfolk at once waiting to try a route again: a route not
##   found), stuck_minutes (townsfolk-minutes in that wait), unreachable (refused move_to: no way there);
##   gate_minutes (share of the day minutes with a guard on every gate post of the watch), night_moves (tiles walked
##   by the night round), visitors (arrived by a gate), rumours (told in a corrillo), corrillo_max (most people in one),
##   shopping (townsfolk visits to the market stalls), rival_sold (units the AI families with a profile sold), offices
##   (seats filled at the town hall), townsfolk (alive at the end).
##   /opt/homebrew/bin/godot --headless --path . -s tools/life/plantillas_probe.gd -- [--cities=a,b] [--bots=idle,...]
##       [--days=3] [--seeds=3]
## Writes reports/sim/plantillas_probe.json and exits with 1 if a run has a refused order or a townsperson stuck at the
## end of the run (waiting since more than an hour).

var BOTS: Dictionary = {"idle": BotIdle, "wanderer": BotWanderer, "smith": BotSmith, "guard_watch": BotGuardWatch}
const START: String = "artisan_blacksmith"


func _init() -> void:
	var cat := Catalog.load_from()
	cat.life_tables.get("life", {})["enabled"] = true
	var cities: Array = NewGame.cities(cat)
	var bots: PackedStringArray = ["idle"]
	var days := 3
	var seeds := 3
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--cities="):
			cities = Array(a.substr(9).split(",", false))
		elif a.begins_with("--bots="):
			bots = a.substr(7).split(",", false)
		elif a.begins_with("--days="):
			days = a.substr(7).to_int()
		elif a.begins_with("--seeds="):
			seeds = a.substr(8).to_int()
	var out := {"days": days, "seeds": seeds, "runs": []}
	var bad := 0
	for city: String in cities:
		for bot_id: String in bots:
			for s: int in range(1, seeds + 1):
				var choices := {"cast": "fixed"}
				if city != NewGame.start_city(cat, START):
					choices["city"] = city
				var r := NewGame.from_start(cat, START, "normal", choices, s)
				if not bool(r.get("ok", false)):
					print("plantillas_probe: %s: %s" % [city, r.get("error", "")])
					quit(2)
					return
				var m := _run(Sim.new(r["state"], cat), BOTS[bot_id].new(), days)
				m["city"] = city
				m["bot"] = bot_id
				m["seed"] = s
				(out["runs"] as Array).append(m)
				var fail := int(m["refused"]) > 0 or int(m["stuck_end"]) > 0
				bad += 1 if fail else 0
				print("plantillas_probe: %-8s %-11s seed %d · %s%s" % [city, bot_id, s, _brief(m), "  << FALLA" if fail else ""])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/sim"))
	FileAccess.open("res://reports/sim/plantillas_probe.json", FileAccess.WRITE).store_string(JSON.stringify(out, "\t"))
	print("plantillas_probe: %d runs, %d con fallos · reports/sim/plantillas_probe.json" % [(out["runs"] as Array).size(), bad])
	quit(1 if bad > 0 else 0)


func _run(sim: Sim, bot: Object, days: int) -> Dictionary:
	var m := {"refused": 0, "reasons": {}, "unreachable": 0, "stuck_max": 0, "stuck_minutes": 0, "stuck_end": 0,
		"gate_minutes": 0.0, "night_moves": 0, "visitors": 0, "rumours": 0, "corrillo_max": 0, "shopping": 0,
		"rival_sold": 0, "offices": 0, "townsfolk": 0}
	var day_minutes := 0
	var gate_ok := 0
	var posts: Array = []
	for i: int in days * Clock.MINUTES_PER_DAY:
		var ev := sim.step(bot.orders(sim))
		var st := sim.state
		var now := int(st.clock["minute"])
		for e: Dictionary in ev:
			match str(e.get("type", "")):
				"order_refused":
					m["refused"] = int(m["refused"]) + 1
					var why := str(e.get("reason", ""))
					m["reasons"][why] = int(m["reasons"].get(why, 0)) + 1
					if why == "unreachable":
						m["unreachable"] = int(m["unreachable"]) + 1
					print("  refused %s %s: %s" % [e.get("order", ""), e.get("actor", ""), why])
				"visitor_arrived":
					m["visitors"] = int(m["visitors"]) + 1
				"rumor_told":
					m["rumours"] = int(m["rumours"]) + 1
				"town_state":
					if str(e.get("activity", "")) == "shopping":
						m["shopping"] = int(m["shopping"]) + 1
				"market_sold":
					if str(st.families.get(str(e.get("family", "")), {}).get("ai_profile", "")) != "":
						m["rival_sold"] = int(m["rival_sold"]) + int(e.get("qty", 0))
				"character_moved":
					var who := str(e.get("character", e.get("actor", "")))
					if st.characters.has(who) and st.characters[who].get("guard") is Dictionary \
							and str(st.characters[who]["guard"].get("role", "")).begins_with("night"):
						m["night_moves"] = int(m["night_moves"]) + 1
		if now % 10 == 0:
			var stuck := 0
			for id: String in Population.townsfolk(st):
				var t: Variant = st.characters[id].get("town")
				if t is Dictionary and int((t as Dictionary).get("retry_at", -1)) > now:
					stuck += 1
			m["stuck_max"] = maxi(int(m["stuck_max"]), stuck)
			m["stuck_minutes"] = int(m["stuck_minutes"]) + stuck * 10
			for p: String in Rumors.corrillos(sim):
				m["corrillo_max"] = maxi(int(m["corrillo_max"]), (Rumors.corrillos(sim)[p] as Array).size())
		if Clock.phase(now, sim.catalog.time) == "day":
			if posts.is_empty():
				for role: Variant in Watch.roles(sim):
					if str(role).begins_with("gate_"):
						posts.append(str(role))
			day_minutes += 1
			var on := {}
			for g: String in Watch.guards(st):
				if not Life.offstage(st, g):
					on[str(st.characters[g]["guard"].get("role", ""))] = true
			var all := not posts.is_empty()
			for p: String in posts:
				all = all and on.has(p)
			gate_ok += 1 if all else 0
	var now_end := int(sim.state.clock["minute"])
	for id: String in Population.townsfolk(sim.state):
		var t: Variant = sim.state.characters[id].get("town")
		if t is Dictionary and int((t as Dictionary).get("retry_at", -1)) > now_end + 60:
			m["stuck_end"] = int(m["stuck_end"]) + 1
	m["gate_minutes"] = snappedf(float(gate_ok) / float(maxi(1, day_minutes)), 0.01)
	var seats := 0
	for o: Variant in sim.state.offices:
		var seat_list: Array = (sim.state.offices[o] as Dictionary).get("seats", [])
		for s: Dictionary in seat_list:
			if str(s.get("holder", "")) != "":
				seats += 1
	m["offices"] = seats
	m["townsfolk"] = Population.townsfolk(sim.state).size()
	return m


func _brief(m: Dictionary) -> String:
	return "vecinos %d · rechazadas %d %s · atascados máx %d (%d min·persona) · puertas %.0f%% · ronda %d casillas · forasteros %d · rumores %d · corrillo máx %d · compras %d · rival vende %d · cargos %d" % [
		int(m["townsfolk"]), int(m["refused"]), m["reasons"] if int(m["refused"]) > 0 else "", int(m["stuck_max"]),
		int(m["stuck_minutes"]), float(m["gate_minutes"]) * 100.0, int(m["night_moves"]), int(m["visitors"]),
		int(m["rumours"]), int(m["corrillo_max"]), int(m["shopping"]), int(m["rival_sold"]), int(m["offices"])]
