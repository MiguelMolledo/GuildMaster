extends Node
## Holds the WorldState and the Sim, turns real time into steps and loads/saves (GDD 05 §5.7).
## Options after "--": --scenario=<id> (a saved game in data/scenarios/; town_e_start by default), --seed=<n>,
## --dev-time (short days), --lang=es|en (Spanish by default until the options menu exists),
## --at=HH:MM (start at that time of the scenario's day: day and night screenshots).
## Speed and pause belong to the player's session, not to the world: they are not saved.
## The menus (docs/ui/02_menu_inicial.md): the pause menu locks the orders (lock_orders: GDD 4.1, the one pause that is
## not active); saved_minute tells a game with something unsaved (unsaved()); the options (Settings) are applied here
## at start-up (--lang wins over the saved language; with --smoke / --shots / --smoke-script / --gallery the window
## options are left alone so the captures keep their size).

const MAX_STEPS_PER_FRAME: int = 64
const SAVE_DIR: String = "user://saves"
const SPEEDS: Array[int] = [1, 2, 4]
const SLOTS: Array[String] = ["slot_1", "slot_2", "slot_3"]  # D6: three slots + the daily autosave
const AUTOSAVE: String = "auto"
const DEFAULT_SCENARIO: String = "town_e_start"

signal started  # a new state is loaded (start, load): views rebuild
signal saved(slot: String)  # a slot (or the autosave) was written: the app adds its thumbnail
signal order_given(order: Dictionary)  # an order was given (the tutorial listens: docs/ui/05_tutorial.md §4.3)

var sim: Sim
var speed: int = 1
var paused: bool = false
var _pending: Array = []  # orders given since the last step
var _acc: float = 0.0
var orders_locked: bool = false   # the pause menu is open: orders are dropped, not queued
var saved_minute: int = -1        # the clock minute of the last save or load (-1: never saved this game)
var last_saved_ms: int = -1       # Time.get_ticks_msec() of the last save this session (-1: none)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var opts := parse_args(args)
	var lang_given := false
	var capture := false
	for a: String in args:
		lang_given = lang_given or a.begins_with("--lang=")
		capture = capture or a == "--smoke" or a.begins_with("--shots=") or a.begins_with("--smoke-script=") or a == "--gallery" \
			or a.begins_with("--flow=") or a.begins_with("--flows=")
	if capture:
		TranslationServer.set_locale(str(opts["lang"]))
		for k: String in Settings.BUSES:
			Settings.apply(k)
	else:
		Settings.apply_all(lang_given)
		if lang_given:
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
## (minute of the day, -1 = the scenario's), "new_game" (H3: open on the menus instead of straight in the game,
## GDD 4.16: true unless --scenario, --smoke, --shots or --smoke-script is given; --new-game forces it), "title"
## (02_menu_inicial: the menus start on the title screen; false with --new-game, which opens the new game screen),
## "start_city" (plantillas: --start-city=<id> opens the new game screen with that settlement of the region chosen)}.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"scenario": DEFAULT_SCENARIO, "seed": -1, "lang": "es", "at": -1, "new_game": true, "title": true,
		"start_city": ""}
	for a: String in args:
		if a.begins_with("--scenario=") or a == "--smoke" or a.begins_with("--shots=") or a.begins_with("--smoke-script=") \
				or a.begins_with("--flow=") or a.begins_with("--flows="):
			out["new_game"] = false
			out["title"] = false
	if "--new-game" in args:
		out["new_game"] = true
		out["title"] = false
	for a: String in args:  # plantillas: Partida nueva with «Dónde empiezas» on that settlement of the region
		if a.begins_with("--start-city="):
			out["start_city"] = a.substr(13)
			out["new_game"] = out["new_game"] or bool(out["title"])
			out["title"] = false
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
	saved_minute = -1
	_info("start (seed=%d, minute=%d, title=%s, map=%s)" % [state.world_seed, int(state.clock["minute"]),
		state.meta.get("title", ""), state.map_id])
	started.emit()


## Queues an order for the next step. Its result comes back as events (order_refused, or the effect).
## In pause (active pause, GDD 4.1) the order is marked "queued": on resume the sim puts it in the actor's
## order_queue instead of applying it, so several orders given in pause run one after another.
func give(order: Dictionary) -> void:
	if orders_locked:
		_info("order dropped: the pause menu is open (type=%s)" % order.get("type", ""))
		return
	var o := order.duplicate(true)
	if paused:
		o["queued"] = true
	_pending.append(o)
	order_given.emit(order)


## Duelo (docs/ui/mecanicas/combate.md §2): applies `order` now, in pause too, by running one sim step with it (and
## whatever was pending): a lance is one game minute, recorded like any order, and its events are published at once.
## Only the duel screen uses it (the game is paused while it is open). Returns the step's events.
func step_now(order: Dictionary) -> Array:
	if sim == null or orders_locked:
		return []
	var orders := _pending
	_pending = []
	var o := order.duplicate(true)
	o.erase("queued")
	orders.append(o)
	order_given.emit(order)
	var events := sim.step(orders)
	get_node("/root/Events").publish(events)
	return events


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


## The pause menu (02 §6): pauses and locks the orders; unlocking leaves the pause as the menu found it (the caller
## restores it).
func lock_orders(locked: bool) -> void:
	if locked != orders_locked:
		orders_locked = locked
		_info("orders locked=%s" % locked)


## Something was played since the last save or load (a new game that has not been saved counts once it runs).
func unsaved() -> bool:
	if sim == null:
		return false
	return int(sim.state.clock["minute"]) != saved_minute


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


## Saves in one of SLOTS (or AUTOSAVE), in SaveSlots.dir (user://saves).
func save_slot(slot: String) -> Error:
	if not slot in SLOTS and slot != AUTOSAVE:
		push_error("save_slot: unknown slot %s" % slot)
		return ERR_INVALID_PARAMETER
	var e := SaveFile.save(sim.state, SaveSlots.path_of(slot))
	if e == OK:
		saved_minute = int(sim.state.clock["minute"])
		last_saved_ms = Time.get_ticks_msec()
		_info("saved %s (minute=%d)" % [slot, int(sim.state.clock["minute"])])
		saved.emit(slot)
	return e


## At the start of every day (D6). A failed autosave is a warning, never a stop.
func _autosave() -> void:
	var e := save_slot(AUTOSAVE)
	if e != OK:
		push_warning("autosave failed (%s)" % error_string(e))
	else:
		_info("autosave (day=%d)" % Clock.day(int(sim.state.clock["minute"])))


func load_slot(slot: String) -> Dictionary:
	var r := SaveFile.load_file(SaveSlots.path_of(slot))
	if r["ok"]:
		start(r["state"], sim.catalog if sim != null else null)
		saved_minute = int(sim.state.clock["minute"])
		_info("loaded %s (minute=%d)" % [slot, saved_minute])
	return r


## The other autoloads are reached by path, not by name: the windowless tests compile this script without them.
func _catalog() -> Catalog:
	return get_node("/root/Data").get("catalog")


## Log.info, also safe when Game runs outside the tree (windowless tests build one by hand).
func _info(msg: String) -> void:
	if is_inside_tree():
		get_node("/root/Log").info("Game", msg)
