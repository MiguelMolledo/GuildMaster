extends Node
## Scripted capture of the Rogue's thief (H12, docs/gdd/04d_otras_clases.md 4.22.6; --smoke-script=picaro, through
## `grimoire heavy` with --always-on-top): the new game screen with the thief chosen; a new game as rogue_thief: the den
## on the street; a townsperson's sheet with «Robar la bolsa» and its chance; another family's workshop at night with
## «Robar el almacén»; inside the den, the fence's table with stolen goods and the bench that launders; the arrest card;
## every upgrade of its tree (capture only: the state is edited directly, as the other scripts). Shots
## reports/shots/picaro_<what>.png. Prints "[SmokePicaro] ok|FAIL ..."; quits with 1 on a FAIL or a timeout.

const BLD := "bld_0001"
const LOT := Vector2i(24, 21)   # the lot by the plaza: the player's forge, here the den

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
		["partida_nueva", func() -> void: _new_game_screen(), 1.0],
		["calle", func() -> void: _start(), 1.5],
		["bolsa", func() -> void: _purse(), 1.0],
		["almacen", func() -> void: _storage(), 1.0],
		["guarida", func() -> void: _fence(), 2.0],
		["perista", func() -> void: _fence_menu(), 1.0],
		["banco", func() -> void: _bench(), 1.0],
		["detencion", func() -> void: _arrest(), 1.0],
		["mejoras", func() -> void: _all_upgrades(), 1.5],
	]
	print("[SmokePicaro] start (%d shots)" % _steps.size())


func _new_game_screen() -> void:
	app.show_new_game()
	var s: NewGameScreen = app.new_game_screen()
	var b := s.get_node("%Profession").get_node_or_null("Thief") as Button
	_check(b != null, "the thief's button")
	if b != null:
		b.pressed.emit()
	_check(s.start_id == "rogue_thief", "the thief's start chosen")


func _start() -> void:
	(app.new_game_screen().get_node("%TutorialCheck") as CheckBox).button_pressed = false
	var r := NewGame.from_start(Game.sim.catalog, "rogue_thief", "normal", {"cast": "fixed"}, 7)
	_check(bool(r["ok"]), "rogue_thief starts")
	app.call("_on_new_game_started", r["state"])
	Game.set_paused(true)
	if app.interior_building != "":
		app.close_interior()
	_me = Kin.head(Game.sim.state, SimQuery.player_family(Game.sim.state))
	app.world().camera().center_on(Iso.tile_to_world(LOT))
	_check(str(Game.sim.state.buildings[BLD]["type"]) == "den", "the den is the player's")


## A townsperson by him in the plaza, by day: her sheet with «Robar la bolsa».
func _purse() -> void:
	var st := Game.sim.state
	st.clock["minute"] = Clock.MINUTES_PER_DAY * Clock.day(int(st.clock["minute"])) + 11 * 60
	var v := ""
	for c: String in Festivals._sorted_keys(st.characters):
		var f := str(st.characters[c].get("family", ""))
		if f != "" and f != SimQuery.player_family(st) and not Watch.is_guard(st, c) and Offices.of_character(st, c) == "" and int(st.characters[c].get("age", 30)) >= 16 \
				and str(st.families.get(f, {}).get("ai_profile", "")) == "" and str(st.families.get(f, {}).get("controlled_by", "")) != "human":
			v = c
			break
	for who: String in [_me, v]:
		var ch: Dictionary = st.characters[who]
		ch["location"] = ""
		ch["path"] = []
	st.characters[_me]["position"] = [19, 21]
	st.characters[v]["position"] = [20, 21]
	app.world().camera().center_on(Iso.tile_to_world(Vector2i(19, 21)))
	app.world().select(_me)
	app.hud().call("open_npc", v)
	_check(Rogue.pickpocket_reason(Game.sim, _me, v) == "", "she can be robbed: %s" % Rogue.pickpocket_reason(Game.sim, _me, v))


## Night: the rival's forge selected, «Robar el almacén».
func _storage() -> void:
	var st := Game.sim.state
	app.hud().close_panels()
	st.clock["minute"] = Clock.MINUTES_PER_DAY * Clock.day(int(st.clock["minute"])) + 23 * 60
	var rival := ""
	for b: String in Festivals._sorted_keys(st.buildings):
		var o := Money.family_of(st, b)
		if o != "" and o != SimQuery.player_family(st) and not (st.buildings[b].get("inventory", {}).get("stacks", []) as Array).is_empty():
			rival = b
			break
	app.world().camera().center_on(Iso.tile_to_world(Vector2i(int(st.buildings[rival]["door"][0]), int(st.buildings[rival]["door"][1]))))
	app.world().pick_building_id(rival)
	app.hud().set_building(rival)
	_check(Rogue.burgle_reason(Game.sim, _me, rival) == "", "its storage at night")


## Inside the den with three stolen pieces: the fence's table.
func _fence() -> void:
	var st := Game.sim.state
	app.hud().close_panels()
	app.world().pick_building_id("")
	var bag: Dictionary = st.characters[_me]["inventory"]
	for it: String in ["sword@stolen", "candlestick@stolen", "fine_clothes@stolen"]:
		Inventory.add(bag, Game.sim.catalog, it, 0, 1)
	st.characters[_me]["location"] = BLD
	app.open_interior(BLD, false)


## After the fade: inside the den, the fence's table opened.
func _fence_menu() -> void:
	_check(app.interior_building == BLD, "inside the den")
	app.interior().open_station_menu("fence", Vector2(300, 170))


func _bench() -> void:
	_check(app.interior().station_menu().visible, "the fence's menu")
	app.interior().station_menu().close()
	app.interior().open_station_menu("forger_bench", Vector2(300, 170))


func _arrest() -> void:
	app.interior().station_menu().close()
	app.close_interior()
	var st := Game.sim.state
	var g: String = Watch.guards(st)[0] if not Watch.guards(st).is_empty() else ""
	if g == "":
		Watch.step(Game.sim)
		g = str(Watch.guards(st)[0]) if not Watch.guards(st).is_empty() else ""
	var card: Node = app.get_node("CardsLayer/EventCard")
	card.call("show_arrest", Game.sim, {"actor": _me, "guard": g, "charge": "petty_theft", "family": SimQuery.player_family(st)})
	_check(card.visible, "the arrest card")


func _all_upgrades() -> void:
	app.get_node("CardsLayer/EventCard").call("close")
	var b: Dictionary = Game.sim.state.buildings[BLD]
	for u: Variant in Game.sim.catalog.upgrade_tree("den"):
		var id := str((u as Dictionary).get("id", u)) if u is Dictionary else str(u)
		Upgrades.complete(Game.sim, BLD, id)
	app.world().camera().center_on(Iso.tile_to_world(LOT))
	_check((b["upgrades"] as Array).size() == 24, "den: 24 upgrades")


func _check(cond: bool, what: String) -> void:
	print("[SmokePicaro] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokePicaro] TIMEOUT at %d" % _i)
		app.save_shot("picaro_timeout")
		get_tree().quit(1)
		return
	if _i == -1:
		if _t < 0.5:
			return
	elif _t < float(_steps[_i][2]):
		return
	else:
		app.save_shot("picaro_" + str(_steps[_i][0]))
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokePicaro] done (%d fails)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	(_steps[_i][1] as Callable).call()
