class_name Routines
extends RefCounted
## Daily routine of the townsfolk (GDD 4.11.2). In H4 only the employees: from home to work at dawn (with a delay
## per employee and day), to their station, back home at dusk; never at night. Owner: subgrim «cola».
## Contract: docs/contratos/h4_empleados.md. Figures: data/employees.json "schedule".
##
## It acts only with the real orders (move_to, enter_building, go_to_station, work_at, exit_building) given through
## Sim.give, so every rule (doors, routes, stations) is the same as for the player. Its memory per character lives in
## character.routine (free dictionary of «cola», JSON only). The houses have no interior: inside = location == home.
##
## The base (H4) leaves step() as a stub and state_of() derived from the state.


## Once per minute, after Staff and before WorkQueue (Sim.step).
static func step(_sim: Sim) -> void:
	pass


## Where a character is in its day: "home" (inside its house), "at_work" (inside the building it works at),
## "walking" (on a route), "out" (on the map, standing) or "inside" (another building). Base: derived from the state;
## «cola» may refine it (e.g. "to_work" / "to_home") keeping these values.
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
