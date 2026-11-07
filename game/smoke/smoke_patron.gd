extends Node
## Scripted capture of the patron's farmer (H12 Patrón, docs/gdd/04d_otras_clases.md 4.22.4; --smoke-script=patron,
## through `grimoire heavy` with --always-on-top): the new game screen with the farmer chosen; a new game as
## patron_farmer: the Granja on the street; inside, the four fields as they start (plowed) with the pen and its
## animals; Pere sowing; a later yard with every state at once (fallow, plowed, sprouts, green, ready with its days
## left, rotten); a field's menu (plow, sow, harvest with their reasons); the cattle fair at the market; the winter
## pen with its feed; and every upgrade of its tree with the two more fields. The state is edited directly for the
## captures, as the erudito script. Shots reports/shots/patron_<what>.png. Prints "[SmokePatron] ok|FAIL ...";
## quits with 1 on a FAIL or a timeout.

const BLD := "bld_0001"
const HERO := "chr_0001"
const LOT := Vector2i(24, 21)   # the lot by the plaza: the player's forge, here the Granja

var app: Node = null
var timeout: float = 120.0
var _t: float = 0.0
var _total: float = 0.0
var _i: int = -1
var _fails: int = 0
var _steps: Array = []  # [shot name, prepare: Callable, seconds before the shot]


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	_steps = [
		["partida_nueva", func() -> void: _new_game_screen(), 1.0],
		["calle", func() -> void: _start(), 1.5],
		["granja", func() -> void: _inside(), 2.0],
		["siembra", func() -> void: _sowing(), 1.5],
		["campos", func() -> void: _every_state(), 1.5],
		["menu_campo", func() -> void: app.interior().open_station_menu("field_b", Vector2(300, 170)), 1.0],
		["feria", func() -> void: _fair(), 1.5],
		["invierno", func() -> void: _winter(), 1.5],
		["mejoras", func() -> void: _all_upgrades(), 2.0],
	]
	print("[SmokePatron] start (%d shots)" % _steps.size())


func _new_game_screen() -> void:
	app.show_new_game()
	var s: NewGameScreen = app.new_game_screen()
	var b := s.get_node("%Profession").get_node_or_null("Farmer") as Button
	_check(b != null, "the farmer's button")
	if b != null:
		b.pressed.emit()
	_check(s.start_id == "patron_farmer", "the farmer's start chosen")


func _start() -> void:
	(app.new_game_screen().get_node("%TutorialCheck") as CheckBox).button_pressed = false
	var r := NewGame.from_start(Game.sim.catalog, "patron_farmer", "normal", {"cast": "fixed"}, 7)
	_check(bool(r["ok"]), "patron_farmer starts")
	app.call("_on_new_game_started", r["state"])
	Game.set_paused(true)
	if app.interior_building != "":
		app.close_interior()
	app.world().camera().center_on(Iso.tile_to_world(LOT))
	_check(str(Game.sim.state.buildings[BLD]["type"]) == "farm", "the Granja is the player's")


func _inside() -> void:
	Game.sim.state.characters[HERO]["location"] = BLD
	app.open_interior(BLD, false)
	_check(Fields.view(Game.sim, BLD).size() == 4, "four fields")
	_check(Herds.head_count(Game.sim, BLD) == 6, "four sheep and two pigs in the pen")


func _sowing() -> void:
	var r := Orders.apply(Game.sim, {"type": "work_at", "actor": HERO, "building": BLD, "zone": "field_a",
		"recipe": "farm_sow_wheat", "mode": "normal"})
	_check(bool(r["ok"]), "Pere sows field A: %s" % r.get("reason", ""))
	Game.set_paused(false)


## A later yard with every state: A fallow, B plowed, C sprouts, D green; and (with the two more fields) E ready on
## its last day, F rotten.
func _every_state() -> void:
	Game.set_paused(true)
	Orders.apply(Game.sim, {"type": "stop_work", "actor": HERO})
	var st := Game.sim.state
	Upgrades.complete(Game.sim, BLD, "farm_production_1")
	Upgrades.complete(Game.sim, BLD, "farm_production_2")
	app.close_interior()
	var today := Clock.day(int(st.clock["minute"]))
	var set := func(z: String, s: String, g: float, ready_day: int = -1) -> void:
		var f := Fields.field(st, BLD, z)
		f.merge({"state": s, "crop": "wheat" if s != "fallow" and s != "plowed" else "", "growth": g,
			"ready_day": ready_day, "sown_day": today - 1}, true)
	set.call("field_a", "fallow", 0.0)
	set.call("field_b", "plowed", 0.0)
	set.call("field_c", "growing", 1.0)
	set.call("field_d", "growing", 3.0)
	set.call("field_e", "ready", 4.0, today - 1)
	set.call("field_f", "rotten", 4.0, today - 3)
	app.open_interior(BLD, false)
	_check(Fields.view(Game.sim, BLD).size() == 6, "six fields with the upgrade")


func _fair() -> void:
	app.interior().station_menu().close()
	app.close_interior()
	var st := Game.sim.state
	st.clock["minute"] = Clock.MINUTES_PER_DAY * Clock.day(int(st.clock["minute"])) + 10 * 60
	st.characters[HERO]["location"] = ""
	st.characters[HERO]["position"] = (Game.sim.catalog.maps()["town_e"]["stalls"]["livestock"]["service"] as Array).duplicate()
	app.world().camera().center_on(Iso.tile_to_world(Vector2i(22, 23)))
	app.hud().open_market(HERO, "livestock")
	_check(Market.stall_at(Game.sim, HERO) == "livestock", "Pere at the cattle fair")


func _winter() -> void:
	app.hud().close_panels()
	var st := Game.sim.state
	st.clock["minute"] = 6 * Clock.MINUTES_PER_DAY + 9 * 60  # winter, day 7
	Inventory.add(st.buildings[BLD]["inventory"], Game.sim.catalog, "pig", 0, 2)
	st.characters[HERO]["location"] = BLD
	app.open_interior(BLD, false)
	_check(Herds.view(Game.sim, BLD)["winter_feed_days"] >= 0, "the winter feed counted")


func _all_upgrades() -> void:
	var b: Dictionary = Game.sim.state.buildings[BLD]
	Game.sim.state.unlocks[SimQuery.player_family(Game.sim.state)] = {Unlocks.ALL: true}  # the tree's panel open
	for u: Variant in Game.sim.catalog.upgrade_tree("farm"):
		var id := str((u as Dictionary).get("id", u)) if u is Dictionary else str(u)
		if not id in (b["upgrades"] as Array):
			Upgrades.complete(Game.sim, BLD, id)
	app.close_interior()
	app.open_interior(BLD, true)
	get_tree().create_timer(0.6).timeout.connect(func() -> void: app.interior().show_upgrades(true))
	_check((b["upgrades"] as Array).size() == 24, "farm: 24 upgrades")


func _check(cond: bool, what: String) -> void:
	print("[SmokePatron] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokePatron] TIMEOUT at %d" % _i)
		app.save_shot("patron_timeout")
		get_tree().quit(1)
		return
	if _i == -1:
		if _t < 0.5:
			return
	elif _t < float(_steps[_i][2]):
		return
	else:
		app.save_shot("patron_" + str(_steps[_i][0]))
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokePatron] done (%d fails)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	(_steps[_i][1] as Callable).call()
