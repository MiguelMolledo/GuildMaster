extends Node
## Scripted capture of the Rogue's spy (H12, docs/gdd/04d_otras_clases.md 4.22.6.5; --smoke-script=espia, through
## `grimoire heavy` with --always-on-top): the new game screen with the spy chosen; a new game as rogue_spy: the rival's
## forge selected by day with «Espiar» and its chance; inside the den, the fence's table with a spying job ready to
## deliver and the secrets to blackmail or expose (the reports are made directly with an easy check, as the other
## scripts edit the state). Shots reports/shots/espia_<what>.png. Prints "[SmokeEspia] ok|FAIL ..."; quits with 1 on a
## FAIL or a timeout.

const BLD := "bld_0001"
const LOT := Vector2i(24, 21)   # the lot by the plaza: the den

var app: Node = null
var timeout: float = 120.0
var _t: float = 0.0
var _total: float = 0.0
var _i: int = -1
var _fails: int = 0
var _steps: Array = []
var _me: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	_steps = [
		["espia_partida_nueva", func() -> void: _new_game_screen(), 1.0],
		["espia_espiar", func() -> void: _start(), 1.5],
		["espia_guarida", func() -> void: _reports(), 2.0],
		["espia_perista", func() -> void: _fence_menu(), 1.0],
	]
	print("[SmokeEspia] start (%d shots)" % _steps.size())


func _new_game_screen() -> void:
	app.show_new_game()
	var s: NewGameScreen = app.new_game_screen()
	var b := s.get_node("%Profession").get_node_or_null("Spy") as Button
	_check(b != null, "the spy's button")
	if b != null:
		b.pressed.emit()
	_check(s.start_id == "rogue_spy", "the spy's start chosen")


## A new game as rogue_spy, by day: the rival's forge selected, «Espiar».
func _start() -> void:
	(app.new_game_screen().get_node("%TutorialCheck") as CheckBox).button_pressed = false
	var r := NewGame.from_start(Game.sim.catalog, "rogue_spy", "normal", {"cast": "fixed"}, 7)
	_check(bool(r["ok"]), "rogue_spy starts")
	app.call("_on_new_game_started", r["state"])
	Game.set_paused(true)
	if app.interior_building != "":
		app.close_interior()
	var st := Game.sim.state
	_me = Kin.head(st, SimQuery.player_family(st))
	st.clock["minute"] = Clock.MINUTES_PER_DAY * Clock.day(int(st.clock["minute"])) + 10 * 60
	var rival := ""
	for b: String in Festivals._sorted_keys(st.buildings):
		if str(st.buildings[b]["type"]) == "forge" and Money.family_of(st, b) != SimQuery.player_family(st):
			rival = b
			break
	var door: Array = st.buildings[rival]["door"]
	st.characters[_me]["location"] = ""
	st.characters[_me]["path"] = []
	st.characters[_me]["position"] = [int(door[0]), int(door[1]) + 1]
	app.world().camera().center_on(Iso.tile_to_world(Vector2i(int(door[0]), int(door[1]))))
	app.world().pick_building_id(rival)
	app.hud().set_building(rival)
	_check(Spy.spy_reason(Game.sim, _me, rival) == "", "the rival's forge can be spied")


## Two reports made (the town's job and a household with a secret), then inside the den.
func _reports() -> void:
	var sim: Sim = Game.sim
	var st := sim.state
	app.hud().close_panels()
	app.world().pick_building_id("")
	sim.catalog.rogue["spy"]["check_base"] = -30   # capture only: the reports come out
	Spy._post_jobs(sim)
	var jobs := Spy.jobs_for(sim, SimQuery.player_family(st))
	_check(not jobs.is_empty(), "a spying job at dawn")
	var abouts: Array = []
	if not jobs.is_empty():
		abouts.append(str(jobs[0]["about"]))
	for f: String in Festivals._sorted_keys(st.families):
		if Spy.household_secret(sim, f) != "" and not f in abouts:
			abouts.append(f)
			break
	for b: String in Festivals._sorted_keys(st.buildings):  # the rival's forge keeps a double ledger
		if str(st.buildings[b]["type"]) == "forge" and Money.family_of(st, b) != SimQuery.player_family(st):
			Upgrades.complete(sim, b, "forge_secrets_1")
			Spy._finish(sim, _me, b, int(st.clock["minute"]))
			break
	for f: String in abouts:
		for b: String in Festivals._sorted_keys(st.buildings):
			if Money.family_of(st, b) == f:
				Spy._finish(sim, _me, b, int(st.clock["minute"]))
				break
	_check(not Spy.usable_facts(sim, SimQuery.player_family(st)).is_empty(), "a secret to use")
	st.characters[_me]["location"] = BLD
	app.open_interior(BLD, false)


func _fence_menu() -> void:
	_check(app.interior_building == BLD, "inside the den")
	app.interior().open_station_menu("fence", Vector2(300, 140))
	_check(app.interior().station_menu().visible, "the fence's table")


func _check(cond: bool, what: String) -> void:
	print("[SmokeEspia] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeEspia] TIMEOUT at %d" % _i)
		app.save_shot("espia_timeout")
		get_tree().quit(1)
		return
	if _i == -1:
		if _t < 0.5:
			return
	elif _t < float(_steps[_i][2]):
		return
	else:
		app.save_shot(str(_steps[_i][0]))
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokeEspia] done (%d fails)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	(_steps[_i][1] as Callable).call()
