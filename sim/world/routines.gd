class_name Routines
extends RefCounted
## Daily routine of the townsfolk (GDD 4.11.2). In H4 only the employees: from home to work at dawn (with a delay
## per employee and day), to their station, back home at dusk; never at night. Owner: subgrim «cola».
## Contract: docs/contratos/h4_empleados.md. Figures: data/employees.json "schedule".
##
## It acts only with the real orders (enter_building, exit_building) given through Sim.give, so every rule (doors,
## routes, access) is the same as for the player; inside, WorkQueue gives the station and the recipe (work_at).
## Its memory per character lives in character.routine (JSON only):
##   {day: int (the day the delay was drawn), leave_at: int (absolute minute it leaves home that day),
##    retry_at: int (after a refused order, when to try again), state: "home" | "to_work" | "at_work" | "to_home" | "out"}
## Rules: an active employee leaves home at leave_at (start of leave_home_phase + a drawn delay) during the
## work_phases and walks to work. At the start of go_home_phase it gets no new work; a cycle already running ends and
## then it walks home (a blocked one does not hold it). At night it is never at work: still inside, it leaves (the cycle
## is interrupted, D11) and walks home. Townsfolk without a job stay at home (their routine is H7).
## The houses have no interior: inside = location == home.

const RETRY_MINUTES: int = 30


## Once per minute, after Staff and before WorkQueue (Sim.step).
static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var phase := Clock.phase(now, sim.catalog.time)
	var ids: Array = []
	for id: Variant in st.characters:
		if st.characters[id].get("job") is Dictionary:
			ids.append(str(id))
	ids.sort()
	for chr: String in ids:
		_step_one(sim, chr, now, phase)


static func _step_one(sim: Sim, chr: String, now: int, phase: String) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	if not bool(ch.get("alive", true)) or Region.is_away(st, chr):  # viajes: the carter of a caravan is away
		return
	if not ch.get("routine") is Dictionary:
		ch["routine"] = {}
	var r: Dictionary = ch["routine"]
	var sched: Dictionary = sim.catalog.employees.get("schedule", {})
	var work := Staff.employer(st, chr)
	var loc := str(ch.get("location", ""))
	var want := "home"
	var inn_shift := InnStaff.shift(sim, chr, work)  # posada: the Taberna-Posada's employees work the night (4.22.4.5)
	if inn_shift == "night":
		if Staff.is_active(sim, chr) and InnStaff.on_duty(sim, now):
			_go(sim, chr, r, work, "at_work", "to_work", now)
		else:
			_go(sim, chr, r, str(ch.get("home", "")), "home", "to_home", now)
		return
	if Staff.is_active(sim, chr) and phase in (sched.get("work_phases", ["dawn", "day"]) as Array):
		var today := Clock.day(now)
		if int(r.get("day", -1)) != today:
			_draw_departure(sim, chr, r, today, sched)
		if now >= int(r.get("leave_at", now)):
			want = "work"
	elif loc == work and phase == str(sched.get("go_home_phase", "dusk")) and _cycle_running(sim, chr, work):
		want = "work"  # dusk: no new work, but the running cycle ends first
	if want == "work":
		_go(sim, chr, r, work, "at_work", "to_work", now)
	else:
		_go(sim, chr, r, str(ch.get("home", "")), "home", "to_home", now)


## Draws today's delay (state.rng) and sets the minute to leave home.
static func _draw_departure(sim: Sim, chr: String, r: Dictionary, today: int, sched: Dictionary) -> void:
	var span: Array = sched.get("leave_home_delay_minutes", [0, 0])
	var delay := sim.state.rng.randi_range(int(span[0]), int(span[1]))
	var starts: Dictionary = sim.catalog.time["phase_starts"][Clock.season(today * Clock.MINUTES_PER_DAY, sim.catalog.time)]
	var start := today * Clock.MINUTES_PER_DAY + int(starts.get(str(sched.get("leave_home_phase", "dawn")), 0))
	r["day"] = today
	r["leave_at"] = start + delay
	if OS.is_debug_build():
		print("[Routines] %s sale de casa el día %d a las %s (retraso=%d min)" % [chr, today,
			_hhmm(start + delay), delay])


## Takes `chr` to building `target` (its work or its home): already inside -> `inside_state`; walking there -> nothing;
## else leaves where it is and walks there (exit_building + enter_building through Sim.give).
static func _go(sim: Sim, chr: String, r: Dictionary, target: String, inside_state: String, walking_state: String,
		now: int) -> void:
	var ch: Dictionary = sim.state.characters[chr]
	var loc := str(ch.get("location", ""))
	if target == "":
		# No home to go to: just never stay at work outside the hours.
		if loc != "" and loc == Staff.employer(sim.state, chr):
			sim.give({"type": "exit_building", "actor": chr})
		_set_state(sim, chr, r, "out")
		return
	if loc == target:
		_set_state(sim, chr, r, inside_state)
		return
	if _walking_to(ch) == target:
		_set_state(sim, chr, r, walking_state)
		return
	if now < int(r.get("retry_at", -1)):
		return
	if loc != "":
		sim.give({"type": "exit_building", "actor": chr})
	sim.give({"type": "enter_building", "actor": chr, "building": target})
	if str(ch.get("location", "")) == target or _walking_to(ch) == target:
		r.erase("retry_at")
		_set_state(sim, chr, r, inside_state if str(ch.get("location", "")) == target else walking_state)
		return
	r["retry_at"] = now + RETRY_MINUTES  # refused (order_refused in the events): try again later
	_set_state(sim, chr, r, "out" if str(ch.get("location", "")) == "" else inside_state)
	if OS.is_debug_build():
		print("[Routines] %s no puede ir a %s; lo intenta a las %s" % [chr, target, _hhmm(now + RETRY_MINUTES)])


static func _set_state(sim: Sim, chr: String, r: Dictionary, state: String) -> void:
	if str(r.get("state", "")) == state:
		return
	r["state"] = state
	sim.events.append({"type": "routine_changed", "employee": chr, "state": state})
	if OS.is_debug_build():
		print("[Routines] %s pasa a %s (%s)" % [chr, state, _hhmm(int(sim.state.clock["minute"]))])


## The building `ch` is walking to with a pending enter_building ("" if none).
static func _walking_to(ch: Dictionary) -> String:
	var queue: Array = ch.get("order_queue", [])
	if queue.is_empty():
		return ""
	var first: Dictionary = queue[0]
	if str(first.get("type", "")) == "enter_building" and bool(first.get("walking", false)):
		return str(first.get("building", ""))
	return ""


## Whether `chr` has a cycle in progress at `bld` (not a finished one waiting for room).
static func _cycle_running(sim: Sim, chr: String, bld: String) -> bool:
	var zone := Production.job_zone(sim, chr, bld)
	if zone == "":
		return false
	return not sim.state.buildings[bld]["zones"][zone]["job"].get("result") is Dictionary


static func _hhmm(minute: int) -> String:
	return "d%d %02d:%02d" % [Clock.day(minute), Clock.hour(minute), Clock.minute_of_day(minute) % 60]


## Where a character is in its day: "home" (inside its house), "at_work" (inside the building it works at),
## "walking" (on a route), "out" (on the map, standing) or "inside" (another building). Derived from the state.
static func state_of(sim: Sim, chr: String) -> String:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty():
		return ""
	var loc := str(ch.get("location", ""))
	if loc != "":
		if loc == str(ch.get("home", "")):
			return "home"
		if loc == Staff.employer(sim.state, chr):
			return "at_work"
		return "inside"
	if not (ch.get("path", []) as Array).is_empty():
		return "walking"
	return "out"
