extends SceneTree
## Cost of the sim per step (GDD 05 §5.4; target < 2 ms per step on the Mac, worst step < 8 ms).
##   godot --headless --path . -s tools/sim_bench.gd [-- --scenario=<id> --days=<n> --bot=wanderer|dawn|idle|none
##        --rush --runs=<n> --at-day=<n>]  (--at-day: start that day at 05:00; fiestas: 3 = the harvest fair)
## Default: town_e_start with the wanderer bot (everybody walking); the bot's orders count in the time of the step.
## --bot=dawn: every neighbour (a character with a home) leaves home at dawn and walks to a work door, waits there
##   (as if inside) and goes home at the start of dusk, like the H4 routine: each one leaves after a delay drawn per
##   day in schedule.leave_home_delay_minutes (data/employees.json); --rush: all in the same minute (delay 0). The
##   rest of the people on the map wander as with the wanderer bot.
## The grid of the map is built before timing (a one-off load cost, printed apart).
## --runs=n: plays the same (deterministic) game n times, forgetting the remembered routes between runs, and keeps
##   for each step its least time: filters out the moments the OS takes the CPU away on a busy machine.
## Prints ms per step (mean, 99th percentile and worst, with the minute of the worst) and exits with 1 if the mean is
## over the target (the worst step is reported, not enforced: it is noisy on a busy machine).

const TARGET_MS: float = 2.0
const WORST_TARGET_MS: float = 8.0


func _init() -> void:
	var scenario := "town_e_start"
	var days := 3
	var bot_id := "wanderer"
	var rush := false
	var runs := 1
	var at_day := -1
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.substr(11)
		elif a.begins_with("--days="):
			days = a.substr(7).to_int()
		elif a.begins_with("--bot="):
			bot_id = a.substr(6)
		elif a == "--rush":
			rush = true
		elif a.begins_with("--runs="):
			runs = maxi(1, a.substr(7).to_int())
		elif a.begins_with("--at-day="):  # fiestas: start on that day (05:00), e.g. --at-day=3 = the harvest fair
			at_day = a.substr(9).to_int()
	var cat := Catalog.load_from()
	var steps := days * Clock.MINUTES_PER_DAY
	var best := PackedInt64Array()  # per step, the least time over the runs
	best.resize(steps)
	best.fill(1 << 62)
	var grid_ms := 0.0
	var moves := 0
	var minutes := PackedInt64Array()
	minutes.resize(steps)
	var name := ""
	var chars := 0
	for run: int in runs:
		var r := NewGame.from_scenario(scenario)
		if not r["ok"]:
			print("sim_bench: scenario %s: %s" % [scenario, r["error"]])
			quit(2)
			return
		var sim := Sim.new(r["state"], cat)
		if at_day >= 0:
			sim.state.clock["minute"] = at_day * Clock.MINUTES_PER_DAY + 300
		var bot: Object = null
		if bot_id == "wanderer":
			bot = BotWanderer.new()
		elif bot_id == "dawn":
			bot = DawnBot.new(rush)
		elif bot_id == "idle":
			bot = BotIdle.new()
		var tg := Time.get_ticks_usec()
		var grid := Grid.of(cat, sim.state.map_id)
		if run == 0:
			grid_ms = (Time.get_ticks_usec() - tg) / 1000.0
		elif grid != null and grid.get("routes") != null:
			(grid.get("routes") as Dictionary).clear()  # every run finds its routes again
		moves = 0
		for i: int in steps:
			var s := Time.get_ticks_usec()
			for e: Dictionary in sim.step(bot.orders(sim) if bot != null else []):
				if e["type"] == "character_moved":
					moves += 1
			best[i] = mini(best[i], Time.get_ticks_usec() - s)
			minutes[i] = int(sim.state.clock["minute"])
		name = (bot_id + (" (rush)" if rush else "")) if bot != null else "none"
		if bot is DawnBot:
			name += ", %d neighbours, %d departures" % [(bot as DawnBot).neighbours, (bot as DawnBot).departures]
		chars = sim.state.characters.size()
	var total := 0
	var worst := 0
	var worst_minute := 0
	for i: int in steps:
		total += best[i]
		if best[i] > worst:
			worst = best[i]
			worst_minute = minutes[i]
	var mean_ms := total / 1000.0 / steps
	var sorted := best.duplicate()
	sorted.sort()
	var p99_ms := sorted[int(steps * 0.99)] / 1000.0
	print("sim_bench: %s, bot %s, %d characters, %d steps, %d tiles walked, %s, mean %.4f ms, p99 %.3f ms, "
		% [scenario, name, chars, steps, moves, "1 run" if runs == 1 else "best of %d runs per step" % runs, mean_ms,
		p99_ms]
		+ "worst %.3f ms at %s (target mean < %.1f ms, worst < %.1f ms; grid built in %.2f ms before timing)"
		% [worst / 1000.0, _hhmm(worst_minute), TARGET_MS, WORST_TARGET_MS, grid_ms])
	quit(0 if mean_ms < TARGET_MS else 1)


func _hhmm(minute: int) -> String:
	return "day %d %02d:%02d" % [Clock.day(minute), Clock.hour(minute), Clock.minute_of_day(minute) % 60]


## Bench bot (not a game rule): the neighbours' commute, and the wanderer's rule for everybody else on the map. Every
## neighbour has a fixed work door (the doors of the buildings that are not houses, in turn by id), so its routes
## repeat from the second day, as an employee's would. Randomness from state.rng.
class DawnBot:
	extends RefCounted
	var rush: bool = false
	var neighbours: int = 0
	var departures: int = 0
	var _leave_at: Dictionary = {}  # chr -> absolute minute it leaves home today
	var _work_door: Dictionary = {}  # chr -> [col, row]
	var _last_phase: String = ""

	func _init(all_at_once: bool) -> void:
		rush = all_at_once

	func orders(sim: Sim) -> Array:
		var st := sim.state
		var sched: Dictionary = sim.catalog.employees.get("schedule", {})
		var leave_phase := str(sched.get("leave_home_phase", "dawn"))
		var home_phase := str(sched.get("go_home_phase", "dusk"))
		var delay: Array = sched.get("leave_home_delay_minutes", [0, 0])
		if _work_door.is_empty():
			_assign_doors(st)
		var minute := int(st.clock["minute"])
		var phase := Clock.phase(minute, sim.catalog.time)
		var out: Array = _wander(sim)
		if phase != _last_phase:
			if phase == leave_phase:
				for id: String in _work_door:
					var d := 0 if rush else st.rng.randi_range(int(delay[0]), int(delay[1]))
					_leave_at[id] = minute + d
			elif phase == home_phase:
				_leave_at.clear()
				for id: String in _work_door:
					var ch: Dictionary = st.characters[id]
					if str(ch.get("location", "")) == "":
						out.append({"type": "enter_building", "actor": id, "building": str(ch.get("home", ""))})
			_last_phase = phase
		for id: String in _leave_at.keys():
			if int(_leave_at[id]) > minute:
				continue
			_leave_at.erase(id)
			var ch: Dictionary = st.characters[id]
			if str(ch.get("location", "")) != str(ch.get("home", "")):
				continue
			out.append({"type": "exit_building", "actor": id})
			out.append({"type": "move_to", "actor": id, "tile": _work_door[id]})
			departures += 1
		return out

	## BotWanderer's rule, leaving the neighbours alone.
	func _wander(sim: Sim) -> Array:
		var grid := Grid.of(sim.catalog, sim.state.map_id)
		var out: Array = []
		for id: String in sim.state.characters:
			var ch: Dictionary = sim.state.characters[id]
			if _work_door.has(id) or not bool(ch.get("alive", true)) or not (ch.get("path", []) as Array).is_empty() \
					or str(ch.get("location", "")) != "":
				continue
			if sim.state.rng.randf() >= BotWanderer.CHANCE_PER_MINUTE:
				continue
			var t := grid.tile_of(grid.walkable_tiles[sim.state.rng.randi_range(0, grid.walkable_tiles.size() - 1)])
			out.append({"type": "move_to", "actor": id, "tile": [t.x, t.y]})
		return out

	func _assign_doors(st: WorldState) -> void:
		var doors: Array = []
		var ids: Array = st.buildings.keys()
		ids.sort()
		for b: String in ids:
			var bld: Dictionary = st.buildings[b]
			var door: Array = bld.get("door", [])
			if str(bld.get("type", "")) != "house" and door.size() == 2:
				doors.append([int(door[0]), int(door[1])])
		var chars: Array = st.characters.keys()
		chars.sort()
		for id: String in chars:
			var ch: Dictionary = st.characters[id]
			if str(ch.get("home", "")) == "" or not bool(ch.get("alive", true)) or doors.is_empty():
				continue
			_work_door[id] = doors[neighbours % doors.size()]
			neighbours += 1
