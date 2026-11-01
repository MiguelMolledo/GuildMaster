class_name WorkQueue
extends RefCounted
## The production queue of a building and how its work is handed to the employees (GDD 4.7.4). Owner: subgrim
## «cola». Contract: docs/contratos/h4_empleados.md.
##
## state.buildings[bld].queue = {entries: [entry], loop: bool, paused: bool}
##   entry = {id: "qen_0001", recipe, qty: int (>= 1; -1 = infinite), done: int}
## «cola» may add fields inside the queue and its entries (its own memory: per-unit plan, warnings already given...)
## without a format change, always JSON and with a round-trip test.
## Employees work in normal mode, without master touch, and never at night (Production.may_work). Roles: a station id
## or "any" (character.job.role); a fixed role only works at its kind of station (BUG-023).
##
## The base (H4) leaves the orders and step() as stubs and the queries with their shape; «cola» fills them.


# --- Orders (stubs until «cola») -------------------------------------------------------------------------------------

## {"type": "queue_add", "actor", "building", "recipe", "qty"} (qty 1, 5, 10 or -1 = infinite).
static func order_add(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "queue_remove", "actor", "building", "entry"}.
static func order_remove(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "queue_move", "actor", "building", "entry", "to"} (to = new index, 0 = first).
static func order_move(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "queue_loop", "actor", "building", "on": bool}.
static func order_loop(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "queue_pause", "actor", "building", "on": bool}.
static func order_pause(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## {"type": "set_role", "actor", "employee", "role"} (a station id of the building or "any").
static func order_set_role(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


# --- Step (stub until «cola») ----------------------------------------------------------------------------------------

## Once per minute, after Routines and before Production (Sim.step): hands the next unit of the queue (dependencies
## first) to each free employee inside its workplace at a station of its role (go_to_station / work_at, normal mode),
## marks the entries that cannot be made and warns.
static func step(_sim: Sim) -> void:
	pass


# --- Queries (shape fixed in the base; «cola» fills them) ------------------------------------------------------------

## The queue of `bld` for the production panel: {entries: [{id, recipe, qty, done, status}], loop, paused, stalled}.
## status: "ok" | "working" | the reason it is skipped ("missing_inputs", "storage_full", "skill_too_low", ...);
## stalled: "" or why nothing can be made. Base: the entries as they are with status "".
static func view(sim: Sim, bld: String) -> Dictionary:
	var q: Dictionary = sim.state.buildings.get(bld, {}).get("queue", {})
	var entries: Array = []
	for e: Dictionary in q.get("entries", []):
		entries.append({"id": str(e.get("id", "")), "recipe": str(e.get("recipe", "")), "qty": int(e.get("qty", 1)),
			"done": int(e.get("done", 0)), "status": ""})
	return {"entries": entries, "loop": bool(q.get("loop", false)), "paused": bool(q.get("paused", false)),
		"stalled": ""}


## The active employees of `bld` that are at work with nothing to do now (the idle icon over the building). Base: [].
static func idle_employees(_sim: Sim, _bld: String) -> Array:
	return []


## The buildings of `fam` with idle employees (the map icons). Base: [].
static func idle_buildings(_sim: Sim, _fam: String) -> Array:
	return []


## What `chr` is doing for the queue: {} or {zone, recipe, entry}. Base: {}.
static func task_of(_sim: Sim, _chr: String) -> Dictionary:
	return {}
