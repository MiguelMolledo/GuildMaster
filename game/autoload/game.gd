extends Node
## Holds the WorldState and the Sim, turns real time into steps and loads/saves (GDD 05 §5.7).
## Options after "--": --scenario=<id> (a saved game in data/scenarios/), --seed=<n>, --dev-time (short days),
## --lang=es|en (Spanish by default until the options menu exists).
## Speed and pause belong to the player's session, not to the world: they are not saved.

const MAX_STEPS_PER_FRAME: int = 64
const SAVE_DIR: String = "user://saves"
const SPEEDS: Array[int] = [1, 2, 4]
const SLOTS: Array[String] = ["slot_1", "slot_2", "slot_3"]  # D6: three slots + the daily autosave
const AUTOSAVE: String = "auto"

var sim: Sim
var speed: int = 1
var paused: bool = false
var _pending: Array = []  # orders given since the last step
var _acc: float = 0.0


func _ready() -> void:
	var scenario := ""
	var world_seed := -1
	var lang := "es"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			lang = a.substr(7)
		if a.begins_with("--scenario="):
			scenario = a.substr(11)
		elif a.begins_with("--seed="):
			world_seed = a.substr(7).to_int()
	TranslationServer.set_locale(lang)
	if scenario != "":
		var r := NewGame.from_scenario(scenario, world_seed)
		if not r["ok"]:
			push_error("scenario %s: %s" % [scenario, r["error"]])
			start(NewGame.fresh(Data.catalog, maxi(world_seed, 1)))
			return
		start(r["state"])
	else:
		start(NewGame.fresh(Data.catalog, world_seed if world_seed >= 0 else 1))


func start(state: WorldState) -> void:
	sim = Sim.new(state, Data.catalog)
	_pending.clear()
	_acc = 0.0
	Log.info("Game", "start (seed=%d, minute=%d, title=%s)" % [state.world_seed, int(state.clock["minute"]),
		state.meta.get("title", "")])


## Queues an order for the next step. Its result comes back as events (order_refused, or the effect).
func give(order: Dictionary) -> void:
	_pending.append(order)


func _process(delta: float) -> void:
	if sim == null or paused:
		return
	var seconds_per_minute: float = float(Data.catalog.time["real_seconds_per_day"]) / Clock.MINUTES_PER_DAY
	_acc += delta * speed
	var steps := 0
	while _acc >= seconds_per_minute and steps < MAX_STEPS_PER_FRAME:
		_acc -= seconds_per_minute
		steps += 1
		var orders := _pending
		_pending = []
		var events := sim.step(orders)
		Events.publish(events)
		if events.any(func(e: Dictionary) -> bool: return e["type"] == "day_started"):
			_autosave()
	if steps == MAX_STEPS_PER_FRAME:
		_acc = 0.0  # a long hitch: drop the backlog instead of fast-forwarding


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
		Log.info("Game", "autosave (day=%d)" % Clock.day(int(sim.state.clock["minute"])))


func load_slot(slot: String) -> Dictionary:
	var r := SaveFile.load_file(SAVE_DIR.path_join(slot + ".json"))
	if r["ok"]:
		start(r["state"])
	return r
