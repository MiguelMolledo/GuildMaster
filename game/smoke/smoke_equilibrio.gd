extends Node
## Scripted captures of the balance pass (--smoke-script=equilibrio; through `grimoire heavy` with --always-on-top):
## the courtship panel after a gift (Equilibrio 1: «hoy ya no cuenta»), the ledger's Debts tab of a broke forge with the
## emergency loan (Equilibrio 2), the upgrade tree with a small works done at night and the workshop's fame in the
## production panel (Equilibrio 9, 13), and the pause menu's «Retirarse…», its confirmation and the final screen (D19).
## Each step loads its scenario, opens the panel through the HUD's own calls and saves reports/shots/eq_<what>.png.

const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var app: Node = null
var timeout: float = 150.0
var _steps: Array = []   # [shot, setup: Callable, wait]
var _i: int = -1
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	_steps = [["regalo", _gift, 0.8], ["urgencia", _emergency, 0.8], ["obra_noche", _works, 1.6],
		["fama", _fame, 1.6], ["retirarse", _retire_menu, 0.8], ["retirarse_confirma", _retire_ask, 0.6],
		["retirarse_final", _retire_end, 1.2]]
	print("[SmokeEquilibrio] start (%d shots, timeout=%.0f s)" % [_steps.size(), timeout])


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeEquilibrio] TIMEOUT in step %d" % _i)
		app.save_shot("eq_timeout")
		get_tree().quit(1)
		return
	if _i == -1:
		if _t > 0.5:
			_next()
		return
	if _t >= float(_steps[_i][2]):
		app.save_shot("eq_" + str(_steps[_i][0]))
		_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokeEquilibrio] done")
		get_tree().quit(0)
		return
	print("[SmokeEquilibrio] %s" % _steps[_i][0])
	(_steps[_i][1] as Callable).call()


func _load(r: Dictionary) -> bool:
	if not bool(r.get("ok", false)):
		print("[SmokeEquilibrio] scenario failed: %s" % r.get("error", ""))
		get_tree().quit(1)
		return false
	if app.interior_building != "":
		app.close_interior()
	app.hud().close_panels()
	Game.start(r["state"])
	Game.set_paused(true)
	app.world().select(HERO)
	return true


func _gift() -> void:
	if not _load(NewGame.from_scenario("courtship")):
		return
	var who := str(Courtship.candidates(Game.sim, HERO)[0]["character"])
	Inventory.add(Game.sim.state.characters[HERO]["inventory"], Game.sim.catalog, "sword", 0, 2)
	Game.sim.state.characters[HERO]["position"] = (Game.sim.state.characters[who].get("position", [19, 20]) as Array).duplicate()
	Orders.apply(Game.sim, {"type": "court_gift", "actor": HERO, "target": who, "item": "sword", "quality": 0})
	app.hud().open_courtship(HERO)


func _emergency() -> void:
	if _load(NewGame.from_scenario("broke_forge")):
		app.hud().open_ledger("debts")


func _works() -> void:
	if not _load(NewGame.from_scenario("forge_upgrades")):
		return
	Game.sim.state.families["fam_0001"]["gold"] = 2000
	app.open_interior(FORGE, true)
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		app.interior().show_upgrades(true)
		var up: UpgradePanel = app.interior().upgrade_panel()
		for id: String in ["forge_production_2", "forge_quality_1", "forge_security_1", "forge_commerce_1"]:
			if Upgrades.status_of(Game.sim, HERO, FORGE, id) in ["available", "missing_materials"]:
				up.select(id)
				break)


func _fame() -> void:
	if not _load(NewGame.from_scenario("forge_upgrades")):
		return
	WorkshopFame.add(Game.sim, FORGE, "masterwork")
	WorkshopFame.add(Game.sim, FORGE, "festival_contract_done")
	app.open_interior(FORGE, true)
	get_tree().create_timer(0.6).timeout.connect(func() -> void: app.interior().show_production(true))


func _retire_menu() -> void:
	if app.interior_building != "":
		app.close_interior()
	if not _load(NewGame.from_start(Catalog.load_from(), "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)):
		return
	app.open_pause()


func _retire_ask() -> void:
	(app.pause_menu().get_node("%CloseDynastyButton") as Button).pressed.emit()


func _retire_end() -> void:
	app.pause_menu().call("_on_confirm", "close")
