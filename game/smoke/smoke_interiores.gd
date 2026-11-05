extends Node
## Scripted capture of the interiors (--smoke-script=interiores; through `grimoire heavy` with --always-on-top): for
## each artisan trade (blacksmith, carpenter, mason, tailor) a new game, its workshop in management mode without
## upgrades and with every upgrade of its tree done (capture only: the state is edited directly), then the town's
## armory. Shots reports/shots/interiores_<what>.png, the reference of docs/arte/interiores.md (before and after).
## Prints "[SmokeInteriores] ok|FAIL ..."; quits with 1 on a FAIL or a timeout.

const BLD := "bld_0001"

var app: Node = null
var timeout: float = 90.0
var _t: float = 0.0
var _total: float = 0.0
var _i: int = -1
var _fails: int = 0
var _steps: Array = []  # [shot name, prepare: Callable]


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	for p: String in ["blacksmith", "carpenter", "mason", "tailor"]:
		_steps.append([p, func() -> void: _start(p)])
		_steps.append([p + "_mejoras", func() -> void: _all_upgrades()])
	_steps.append(["armory", func() -> void: _armory()])
	print("[SmokeInteriores] start (%d shots)" % _steps.size())


func _start(p: String) -> void:
	var r := NewGame.from_start(Game.sim.catalog, "artisan_" + p, "normal", {"cast": "fixed"}, 7)
	_check(bool(r["ok"]), "artisan_%s starts" % p)
	app.call("_on_new_game_started", r["state"])
	Game.set_paused(true)
	if app.interior_building != "":
		app.close_interior()
	app.open_interior(BLD, true)


func _all_upgrades() -> void:
	var b: Dictionary = Game.sim.state.buildings[BLD]
	for u: Variant in Game.sim.catalog.upgrade_tree(str(b["type"])):
		var id := str((u as Dictionary).get("id", u)) if u is Dictionary else str(u)
		Upgrades.complete(Game.sim, BLD, id)
	app.close_interior()
	app.open_interior(BLD, true)
	_check((b["upgrades"] as Array).size() > 0, "%s: upgrades done" % str(b["type"]))


func _armory() -> void:
	app.close_interior()
	var found := ""
	var ids: Array = Game.sim.state.buildings.keys()
	ids.sort()
	for id: Variant in ids:
		if str(Game.sim.state.buildings[id].get("type", "")) == "armory":
			found = str(id)
			break
	_check(found != "", "an armory in town")
	if found != "":
		app.open_interior(found, true)


func _check(cond: bool, what: String) -> void:
	print("[SmokeInteriores] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeInteriores] TIMEOUT at %d" % _i)
		get_tree().quit(1)
		return
	if _i == -1:
		if _t < 0.5:
			return
	elif _t < 1.2:
		return
	else:
		app.save_shot("interiores_" + str(_steps[_i][0]))
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokeInteriores] done (%d fails)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	(_steps[_i][1] as Callable).call()
