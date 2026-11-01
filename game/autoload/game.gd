extends Node
## Holds the WorldState and the Sim, turns real time into steps and loads/saves (GDD 05 §5.7).
## Options after "--": --scenario=<id> (a saved game in data/scenarios/; town_e_start by default), --seed=<n>,
## --dev-time (short days), --lang=es|en (Spanish by default until the options menu exists),
## --at=HH:MM (start at that time of the scenario's day: day and night screenshots).
## Speed and pause belong to the player's session, not to the world: they are not saved.

const MAX_STEPS_PER_FRAME: int = 64
const SAVE_DIR: String = "user://saves"
const SPEEDS: Array[int] = [1, 2, 4]
const SLOTS: Array[String] = ["slot_1", "slot_2", "slot_3"]  # D6: three slots + the daily autosave
const AUTOSAVE: String = "auto"
const DEFAULT_SCENARIO: String = "town_e_start"

signal started  # a new state is loaded (start, load): views rebuild

var sim: Sim
var speed: int = 1
var paused: bool = false
var _pending: Array = []  # orders given since the last step
var _acc: float = 0.0


func _ready() -> void:
	var opts := parse_args(OS.get_cmdline_user_args())
	TranslationServer.set_locale(str(opts["lang"]))
	var world_seed: int = opts["seed"]
	var state: WorldState
	var r := NewGame.from_scenario(str(opts["scenario"]), world_seed)
	if r["ok"]:
		state = r["state"]
	else:
		push_error("scenario %s: %s" % [opts["scenario"], r["error"]])
		state = NewGame.fresh(_catalog(), maxi(world_seed, 1))
	if opts["at"] >= 0:
		set_time_of_day(state, opts["at"])
	start(state, _catalog())


## The options of the command line that Game reads: {"scenario", "seed" (-1 = the scenario's), "lang", "at"
## (minute of the day, -1 = the scenario's), "new_game" (H3: open on the new game screen, GDD 4.16: true unless
## --scenario, --smoke, --shots or --smoke-script is given; --new-game forces it)}.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"scenario": DEFAULT_SCENARIO, "seed": -1, "lang": "es", "at": -1, "new_game": true}
	for a: String in args:
		if a.begins_with("--scenario=") or a == "--smoke" or a.begins_with("--shots=") or a.begins_with("--smoke-script="):
			out["new_game"] = false
	if "--new-game" in args:
		out["new_game"] = true
	for a: String in args:
		if a.begins_with("--lang="):
			out["lang"] = a.substr(7)
		elif a.begins_with("--scenario="):
			out["scenario"] = a.substr(11)
		elif a.begins_with("--seed="):
			out["seed"] = a.substr(7).to_int()
		elif a.begins_with("--at="):
			var hm := a.substr(5).split(":")
			if hm.size() == 2 and hm[0].is_valid_int() and hm[1].is_valid_int():
				out["at"] = clampi(hm[0].to_int(), 0, 23) * 60 + clampi(hm[1].to_int(), 0, 59)
			else:
				push_warning("--at expects HH:MM, got %s" % a.substr(5))
	return out


## Start-up option only (--at): moves the clock to `minute_of_day` of the same day, before the sim runs.
static func set_time_of_day(state: WorldState, minute_of_day: int) -> void:
	var now := int(state.clock["minute"])
	state.clock["minute"] = Clock.day(now) * Clock.MINUTES_PER_DAY + minute_of_day


func start(state: WorldState, catalog: Catalog = null) -> void:
	sim = Sim.new(state, catalog if catalog != null else _catalog())
	_pending.clear()
	_acc = 0.0
	_info("start (seed=%d, minute=%d, title=%s, map=%s)" % [state.world_seed, int(state.clock["minute"]),
		state.meta.get("title", ""), state.map_id])
	started.emit()


## Queues an order for the next step. Its result comes back as events (order_refused, or the effect).
## In pause (active pause, GDD 4.1) the order is marked "queued": on resume the sim puts it in the actor's
## order_queue instead of applying it, so several orders given in pause run one after another.
func give(order: Dictionary) -> void:
	var o := order.duplicate(true)
	if paused:
		o["queued"] = true
	_pending.append(o)


## The orders queued for the next step (read only: tests and debugging).
func pending() -> Array:
	return _pending.duplicate(true)


## D4: speeds ×1/×2/×4. Anything else is ignored.
func set_speed(s: int) -> void:
	if s in SPEEDS and s != speed:
		speed = s
		_info("speed x%d" % s)


func set_paused(p: bool) -> void:
	if p != paused:
		paused = p
		_info("paused=%s (queued orders=%d)" % [p, _pending.size()])


func toggle_pause() -> void:
	set_paused(not paused)


func seconds_per_minute() -> float:
	return float(sim.catalog.time["real_seconds_per_day"]) / Clock.MINUTES_PER_DAY


## Sim steps per real second at the current speed (0 in pause).
func steps_per_second() -> float:
	if sim == null or paused:
		return 0.0
	return speed / seconds_per_minute()


## 0..1: how far real time has gone towards the next step (views interpolate with it). Frozen in pause.
func step_fraction() -> float:
	if sim == null:
		return 0.0
	return clampf(_acc / seconds_per_minute(), 0.0, 1.0)


func _process(delta: float) -> void:
	advance(delta)


## Turns `delta` real seconds into sim steps at the current speed. Returns how many steps ran. With `publish`
## (the game), each step's events go to Events and the day start autosaves; tests pass false (no autoloads there).
func advance(delta: float, publish: bool = true) -> int:
	if sim == null or paused:
		return 0
	var spm := seconds_per_minute()
	_acc += delta * speed
	var steps := 0
	while _acc >= spm and steps < MAX_STEPS_PER_FRAME:
		_acc -= spm
		steps += 1
		var orders := _pending
		_pending = []
		var events := sim.step(orders)
		if publish:
			get_node("/root/Events").publish(events)
			if events.any(func(e: Dictionary) -> bool: return e["type"] == "day_started"):
				_autosave()
	if steps == MAX_STEPS_PER_FRAME:
		_acc = 0.0  # a long hitch: drop the backlog instead of fast-forwarding
	return steps


## Saves in one of SLOTS (or AUTOSAVE).
func save_slot(slot: String) -> Error:
	if not slot in SLOTS and slot != AUTOSAVE:
		push_error("save_slot: unknown slot %s" % slot)
		return ERR_INVALID_PARAMETER
	return SaveFile.save(sim.state, SAVE_DIR.path_join(slot + ".json"))


## At the start of every day (D6). A failed autosave is a warning, never a stop.
func _autosave() -> void:
	var e := save_slot(AUTOSAVE)
	if e != OK:
		push_warning("autosave failed (%s)" % error_string(e))
	else:
		_info("autosave (day=%d)" % Clock.day(int(sim.state.clock["minute"])))


func load_slot(slot: String) -> Dictionary:
	var r := SaveFile.load_file(SAVE_DIR.path_join(slot + ".json"))
	if r["ok"]:
		start(r["state"])
	return r


## The other autoloads are reached by path, not by name: the windowless tests compile this script without them.
func _catalog() -> Catalog:
	return get_node("/root/Data").get("catalog")


## Log.info, also safe when Game runs outside the tree (windowless tests build one by hand).
func _info(msg: String) -> void:
	if is_inside_tree():
		get_node("/root/Log").info("Game", msg)
