class_name InnStaff
extends RefCounted
## The shifts of the Taberna-Posada's employees (docs/gdd/04d_otras_clases.md 4.22.4.5: «sus empleados sí trabajan de
## noche», the exception of 4.1). The building's type says per role which shift it works (data/buildings work_schedule:
## "night" = from open_before_minutes before the opening until the closing at 02:00; "day" = the schedule of
## data/employees.json). Routines and Production.may_work ask here; a building without work_schedule is not touched.


## "night", "day" or "" (no work_schedule: the general rules) for `chr` working at `bld`.
static func shift(sim: Sim, chr: String, bld: String) -> String:
	if bld == "":
		return ""
	var b: Dictionary = sim.state.buildings.get(bld, {})
	var ws: Variant = sim.catalog.buildings().get(str(b.get("type", "")), {}).get("work_schedule")
	if not ws is Dictionary:
		return ""
	var job: Variant = sim.state.characters.get(chr, {}).get("job")
	var role := str((job as Dictionary).get("role", "any")) if job is Dictionary else "any"
	return str((ws as Dictionary).get(role, (ws as Dictionary).get("any", "night")))


## Whether the night shift is on at `minute`: from open_before_minutes before the opening (the start of open_phase of
## that day's season) until close_hour (past midnight).
static func on_duty(sim: Sim, minute: int) -> bool:
	var rules: Dictionary = sim.catalog.inn.get("rules", {})
	var hours: Dictionary = rules.get("hours", {})
	var mod := Clock.minute_of_day(minute)
	if mod < int(hours.get("close_hour", 2)) * 60:
		return true
	var starts: Dictionary = sim.catalog.time["phase_starts"][Clock.season(minute, sim.catalog.time)]
	var open := int(starts.get(str(hours.get("open_phase", "dusk")), 1140))
	return mod >= open - int(rules.get("staff", {}).get("open_before_minutes", 30))


## Whether `chr` (an employee of `bld`) is in its shift now: night -> on_duty; day -> the work_phases of the general
## schedule.
static func in_shift(sim: Sim, chr: String, bld: String) -> bool:
	var now := int(sim.state.clock["minute"])
	match shift(sim, chr, bld):
		"night":
			return on_duty(sim, now)
		"day":
			var phases: Array = sim.catalog.employees.get("schedule", {}).get("work_phases", ["dawn", "day"])
			return Clock.phase(now, sim.catalog.time) in phases
	return false


## The serving pace of an employee: 1 + (rank speed - 1) × rank_speed_share (apprentice 1, journeyman 1.5, master 2).
static func pace(sim: Sim, chr: String) -> float:
	var job: Variant = sim.state.characters.get(chr, {}).get("job")
	var rank := str((job as Dictionary).get("rank", "apprentice")) if job is Dictionary else \
		str(sim.catalog.inn.get("rules", {}).get("staff", {}).get("kin_server_rank", "journeyman"))
	var speed := float(sim.catalog.rank(rank).get("speed", 1.0))
	var share := float(sim.catalog.inn.get("rules", {}).get("staff", {}).get("rank_speed_share", 0.5))
	return maxf(0.25, 1.0 + (speed - 1.0) * share)
