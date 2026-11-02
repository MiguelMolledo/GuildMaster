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
		Schedules.note_manual(self, o)  # H8: a manual order rules over the routine until the character is idle again
		_give(o)
	# The AI families give their orders like a bot, after the outside ones and on the same state (H3, GDD 4.5.5).
	# Not recorded: they come out of the state, so a replay gives them again.
	for o: Dictionary in RivalAI.orders(self):
		_give(o)
	for o: Dictionary in FamilyAI.orders(self):  # H8: the AI families court, marry and bring the spouse home
		_give(o)
	Clock.tick(state, catalog.time, events)
	# Systems, in a fixed order (GDD 05 §5.4). Each milestone adds its own here: routines, production, customers...
	OrderQueue.step(self)   # starts the next queued order of each idle actor
	Movement.step(self)
	Buildings.step(self)    # arrivals at doors -> inside
	# H8 · family (docs/contratos/h8_familia.md)
	Lifecycle.step(self)    # at year_changed: birthdays (school, trade, coming of age, decline), deaths, succession
	# H7 · the living town (docs/contratos/h7_ciudad.md)
	Population.step(self)   # dawn: townsfolk weddings; year_changed: coming of age, newcomers
	# H5 · upgrades (docs/contratos/h5_mejoras.md)
	Upgrades.step(self)     # works that end now finish: their effects apply before anyone reads them
	# H4 · employees (docs/contratos/h4_empleados.md)
	Staff.step(self)        # at dawn: day counted, leavers, hires start, wages, loyalty, quit/theft, promotions
	Microevents.step(self)  # H7: dawn roll, the night thief, cards that time out (default choice)
	Routines.step(self)     # employees: home -> work at dawn, work -> home at dusk (real orders, Sim.give)
	TownLife.step(self)     # H7: the townsfolk's day (trade, breaks, market, dusk activities, home at night)
	Counter.step(self)      # H7: customers at the shop counters
	Schedules.step(self)    # H8: the family's routines and the Work directive (real orders, Sim.give)
	WorkQueue.step(self)    # hands the queue's next unit to each free employee at its station (work_at)
	Production.step(self)   # work cycles, master-touch windows
	Courtship.step(self)    # H8: +affinity for working at the same building (reads work_done)
	Market.step(self)       # errands arriving; demand recovery at dawn
	Contracts.step(self)    # a new contract at dawn; deadline warnings; expiries
	Upkeep.step(self)       # daily upkeep at dawn (D12, D15)
	Inspections.step(self)  # at dawn: Secrets inspections (fines), after wages and upkeep
	Loans.step(self)        # debt warnings, due date, extension, seizure, ruin
	Births.step(self)       # H8: at dawn, children of the married couples
	Emotions.step(self)     # H7: every hour, emotions that faded end
	Offices.step(self)      # H10: the government, deaths free seats, elections at the year change, salaries and taxes
	Reputation.step(self)   # H9: reputation from the events of the step (trade, wages, townsfolk); passive at dawn
	Dynasty.step(self)      # H8: at dawn, wealth peaks and dynasty goals (chronicle)
	Objectives.step(self)   # reads the events of the step: after every system that emits
	Ledger.step(self)       # retention of the ledger at dawn
	Notices.step(self)      # retention of the notices log
	return events


## An order given by a system for the characters it moves (H4: Routines, WorkQueue), during its step: applied now,
## like one from outside (a refusal leaves order_refused in the events). Not recorded: it comes out of the state.
func give(o: Dictionary) -> void:
	_give(o)


func _give(o: Dictionary) -> void:
	if Orders.is_management(str(o.get("type", ""))):
		_apply_now(o)  # management (hire, bonus, queue_*...) is not something the character walks to do:
		return         # it never waits in their queue nor cancels it
	if bool(o.get("queued", false)):
		OrderQueue.push(self, o)  # given during pause: waits in the actor's queue (GDD 4.1, active pause)
		return
	OrderQueue.clear_for(self, str(o.get("actor", "")))  # an order given live replaces what was queued
	_apply_now(o)


func _apply_now(o: Dictionary) -> void:
	var r := Orders.apply(self, o)
	if not r["ok"]:
		events.append({"type": "order_refused", "order": str(o.get("type", "")), "actor": str(o.get("actor", "")),
			"reason": r["reason"]})


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
