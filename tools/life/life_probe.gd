extends SceneTree
## What the townsfolk do with the living town II on (docs/gdd/04f_vida_y_fiestas.md §4.24; a probe for balance):
##   /opt/homebrew/bin/godot --headless --path . -s tools/life/life_probe.gd -- [--scenario=town_e_start] [--days=2]
##       [--seed=1] [--off]
## Prints, per activity, how many times it started and its share by phase; the mean needs at the end of each day; the
## visitors, guards, rumours and incidents of the run; and the mean ms per step. --off runs it with the life off.

func _init() -> void:
	var scenario := "town_e_start"
	var days := 2
	var seed := 1
	var off := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.substr(11)
		elif a.begins_with("--days="):
			days = a.substr(7).to_int()
		elif a.begins_with("--seed="):
			seed = a.substr(7).to_int()
		elif a == "--off":
			off = true
	var cat := Catalog.load_from()
	if off:
		cat.life_tables["life"]["enabled"] = false
	var r := NewGame.from_scenario(scenario, seed)
	if not r["ok"]:
		print("life_probe: %s" % r["error"])
		quit(2)
		return
	var sim := Sim.new(r["state"], cat)
	var starts := {}  # activity -> {phase -> n}
	var kinds := {}
	var usec := 0
	var steps := days * Clock.MINUTES_PER_DAY
	for i: int in steps:
		var t0 := Time.get_ticks_usec()
		var ev := sim.step()
		usec += Time.get_ticks_usec() - t0
		var ph := Clock.phase(int(sim.state.clock["minute"]), cat.time)
		for e: Dictionary in ev:
			var ty := str(e.get("type", ""))
			if ty == "town_state" and str(e.get("activity", "")) != "":
				var a := str(e["activity"])
				if not starts.has(a):
					starts[a] = {}
				starts[a][ph] = int(starts[a].get(ph, 0)) + 1
			elif ty.begins_with("rumor") or ty.begins_with("visitor") or ty.begins_with("incident") \
					or ty.begins_with("watch") or ty.begins_with("guard") or ty.begins_with("spectacle"):
				kinds[ty] = int(kinds.get(ty, 0)) + 1
		if int(sim.state.clock["minute"]) % Clock.MINUTES_PER_DAY == 0:
			_needs(sim)
	var names: Array = starts.keys()
	names.sort()
	print("life_probe: %s, %d días, semilla %d, vida %s" % [scenario, days, seed, "apagada" if off else "encendida"])
	for a: String in names:
		print("  %-12s %s" % [a, starts[a]])
	var ks: Array = kinds.keys()
	ks.sort()
	for k: String in ks:
		print("  evento %-22s %d" % [k, int(kinds[k])])
	print("  vecinos: %d · personajes: %d · %.3f ms por paso" % [Population.townsfolk(sim.state).size(),
		sim.state.characters.size(), float(usec) / 1000.0 / float(steps)])
	quit(0)


func _needs(sim: Sim) -> void:
	var sums := {}
	var n := 0
	for id: String in Population.townsfolk(sim.state):
		var v := Agenda.view(sim, id)
		if v.is_empty():
			continue
		n += 1
		for k: String in v["needs"]:
			sums[k] = int(sums.get(k, 0)) + int(v["needs"][k])
	var out := {}
	for k: String in sums:
		out[k] = roundi(float(sums[k]) / float(maxi(1, n)))
	print("  día %d: necesidades medias %s (%d vecinos)" % [Clock.day(int(sim.state.clock["minute"])), out, n])
