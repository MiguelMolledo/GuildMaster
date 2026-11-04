extends Node
## Scripted capture of the H12 artisan trades (--smoke-script=oficios; through `grimoire heavy` with --always-on-top):
## the new game screen with the trade buttons (the carpenter chosen), then a new game as each of carpenter, mason and
## tailor: the street of the workshops south of the plaza, the rival of its trade by the plaza, its interior, and its interior with every upgrade of its
## tree marked as done (capture only: the state is edited directly). Shots reports/shots/oficios_<what>.png. Prints
## "[SmokeOficios] ok|FAIL ..."; quits with 1 on a FAIL or a timeout.

const BLD := "bld_0001"
const STREET := Vector2i(20, 32)
const RIVAL_LOT := Vector2i(24, 21)  # the lot by the plaza: the player's forge, or the rival of the other trades

var app: Node = null
var timeout: float = 90.0
var _t: float = 0.0
var _total: float = 0.0
var _i: int = -1
var _fails: int = 0
var _steps: Array = []  # [shot name, prepare: Callable]


func _ready() -> void:
	for p: String in ["carpenter", "mason", "tailor"]:
		_steps.append(["calle_" + p, func() -> void: _start(p)])
		_steps.append(["rival_" + p, func() -> void: app.world().camera().center_on(Iso.tile_to_world(RIVAL_LOT))])
		_steps.append(["interior_" + p, func() -> void: app.open_interior(BLD, true)])
		_steps.append(["mejoras_" + p, func() -> void: _all_upgrades()])
	_steps.push_front(["partida_nueva", func() -> void: _new_game_screen()])
	print("[SmokeOficios] start (%d shots)" % _steps.size())


func _new_game_screen() -> void:
	app.show_new_game()
	var s: NewGameScreen = app.new_game_screen()
	var b := s.get_node("%Profession").get_node_or_null("Carpenter") as Button
	_check(b != null, "the carpenter's button")
	if b != null:
		b.pressed.emit()
	_check(s.start_id == "artisan_carpenter", "the carpenter's start chosen")


func _start(p: String) -> void:
	var r := NewGame.from_start(Game.sim.catalog, "artisan_" + p, "normal", {}, 7)
	_check(bool(r["ok"]), "artisan_%s starts" % p)
	app.call("_on_new_game_started", r["state"])
	Game.set_paused(true)
	if app.interior_building != "":
		app.close_interior()
	app.world().camera().center_on(Iso.tile_to_world(STREET))
	_check(str(Game.sim.state.buildings[BLD]["type"]) == str(Game.sim.catalog.professions()[p]["building"]),
		"%s: the workshop is the player's" % p)


func _all_upgrades() -> void:
	var b: Dictionary = Game.sim.state.buildings[BLD]
	var tree := str(b["type"])
	for u: Variant in Game.sim.catalog.upgrade_tree(tree):
		var id := str((u as Dictionary).get("id", u)) if u is Dictionary else str(u)
		Upgrades.complete(Game.sim, BLD, id)
	app.close_interior()
	app.open_interior(BLD, true)
	_check((b["upgrades"] as Array).size() == 24, "%s: 24 upgrades" % tree)


func _check(cond: bool, what: String) -> void:
	print("[SmokeOficios] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeOficios] TIMEOUT at %d" % _i)
		get_tree().quit(1)
		return
	if _i == -1:
		if _t < 0.5:
			return
	elif _t < 1.0:
		return
	else:
		app.save_shot("oficios_" + str(_steps[_i][0]))
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokeOficios] done (%d fails)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	(_steps[_i][1] as Callable).call()
