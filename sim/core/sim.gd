class_name Sim
extends RefCounted
## Runs the world (GDD 05 §5.2-§5.4): pure rules, no nodes, deterministic. Same state + same seed + same orders
## = same game. One step = one game minute: orders first, then the clock, then the systems in a fixed order.
## The randomness comes only from state.rng, never from randf() or Time.

var state: WorldState
var catalog: Catalog
var events: Array = []       # what happened in the last step (the game layer reads it through the Events autoload)
var record: bool = false     # keep every order given, with its minute, to replay it
var recording: Array = []    # [{"minute": int, "order": Dictionary}]


func _init(s: WorldState, c: Catalog) -> void:
	state = s
	catalog = c


## One game minute. Returns the events of the step.
func step(orders: Array = []) -> Array:
	events = []
	for o: Dictionary in orders:
		if record:
			recording.append({"minute": int(state.clock["minute"]), "order": o.duplicate(true)})
		if bool(o.get("queued", false)):
			OrderQueue.push(self, o)  # given during pause: waits in the actor's queue (GDD 4.1, active pause)
			continue
		OrderQueue.clear_for(self, str(o.get("actor", "")))  # an order given live replaces what was queued
		var r := Orders.apply(self, o)
		if not r["ok"]:
			events.append({"type": "order_refused", "order": str(o.get("type", "")), "actor": str(o.get("actor", "")),
				"reason": r["reason"]})
	Clock.tick(state, catalog.time, events)
	# Systems, in a fixed order (GDD 05 §5.4). Each milestone adds its own here: routines, production, customers...
	OrderQueue.step(self)   # starts the next queued order of each idle actor
	Movement.step(self)
	Buildings.step(self)    # arrivals at doors -> inside
	Production.step(self)   # work cycles, master-touch windows
	return events


## Runs `minutes` steps. `bot` (optional) gives the orders of each step: an object with orders(sim) -> Array.
func run_minutes(minutes: int, bot: Object = null) -> void:
	for i: int in minutes:
		step(bot.orders(self) if bot != null else [])


func run_days(days: int, bot: Object = null) -> void:
	run_minutes(days * Clock.MINUTES_PER_DAY, bot)


## A fingerprint of the whole state (determinism tests, replays).
func state_hash() -> String:
	return SaveFile.canonical(state.to_dict()).md5_text()


func now() -> Dictionary:
	return Clock.describe(int(state.clock["minute"]), catalog.time)
