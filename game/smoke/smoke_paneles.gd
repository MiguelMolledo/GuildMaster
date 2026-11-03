extends Node
## Scripted capture of every existing panel in its HUD zone (--smoke-script=paneles, docs/ui/01_hud.md §4; through
## `grimoire heavy` with --always-on-top): a new game as the blacksmith, then each panel opened as its button or key
## would, one shot each (reports/shots/ui_panel_<id>.png), checking that it sits inside its zone (5: the management
## panel, the wide one for the upgrade tree, the big modal for the tree and the offices). The market, the board and the
## town hall close unless the person stands on their service tile: --smoke-script=mercado and titulos show them. Prints
## "[SmokePaneles] ok|FAIL ..."; any FAIL quits with 1.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var app: Node = null
var timeout: float = 150.0
var _total: float = 0.0
var _t: float = 0.0
var _i: int = -1
var _fails: int = 0
var _steps: Array = []   # [id, open: Callable, panel: Callable -> Control, zone]


func _ready() -> void:
	var hud: Node = app.hud()
	var r := NewGame.from_start(Game.sim.catalog, "artisan_blacksmith", "normal", {"cast": "fixed"}, 7)
	app.call("_on_new_game_started", r["state"])
	Game.set_paused(true)
	var keeper := func() -> String: return TownLife.stall_keeper(Game.sim.state, Game.sim.catalog, "food")
	var other := func() -> String:
		for id: String in Game.sim.state.characters:
			var ch: Dictionary = Game.sim.state.characters[id]
			if str(ch.get("controlled_by", "")) != "human" and bool(ch.get("alive", true)) and str(ch.get("family", "")) != \
					SimQuery.player_family(Game.sim.state):
				return id
		return ""
	_steps = [
		["ledger", func() -> void: hud.open_ledger(), func() -> Control: return hud.ledger_panel(), "manage"],
		["ledger_debts", func() -> void: hud.open_ledger("debts"), func() -> Control: return hud.ledger_panel(), "manage"],
		["npc", func() -> void: hud.open_npc(keeper.call()), func() -> Control: return hud.npc_panel(), "manage"],
		["kin_ai", func() -> void: hud.open_kin_ai(HUGO), func() -> Control: return hud.kin_ai_panel(), "manage"],
		["character", func() -> void: hud.toggle_character_panel(), func() -> Control: return hud.get_node("%CharacterPanel"), "manage"],
		["courtship", func() -> void: hud.open_courtship(other.call()), func() -> Control: return hud.courtship_panel(), "manage"],
		["tree", func() -> void: hud.toggle_tree(), func() -> Control: return hud.tree_panel(), "modal"],
		["offices", func() -> void: hud.open_offices(HUGO), func() -> Control: return hud.offices_panel(), "modal"],
		["storage", func() -> void: _inside("storage"), func() -> Control: return app.interior().storage_panel(), "manage"],
		["production", func() -> void: _inside("production"), func() -> Control: return app.interior().production_panel(), "manage"],
		["staff", func() -> void: _inside("staff"), func() -> Control: return app.interior().staff_panel(), "manage"],
		["upgrades", func() -> void: _inside("upgrades"), func() -> Control: return app.interior().upgrade_panel(), "wide"],
	]
	print("[SmokePaneles] start (%d panels)" % _steps.size())


func _inside(panel: String) -> void:
	if app.interior_building != BLD:
		app.open_interior(BLD, true)
		await get_tree().create_timer(0.6).timeout
	match panel:
		"storage":
			app.interior().show_storage(true)
		"production":
			app.interior().show_production(true)
		"staff":
			app.interior().show_staff(true, "staff")
		"upgrades":
			app.interior().show_upgrades(true)


func _check(cond: bool, what: String) -> void:
	print("[SmokePaneles] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _zone(z: String) -> Rect2:
	match z:
		"modal":
			return HudLayout.big_modal()
		"wide":
			return Rect2(244, 58, 712, 430)
	return HudLayout.ZONES["manage"]


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokePaneles] TIMEOUT at %d" % _i)
		get_tree().quit(1)
		return
	if _i >= 0 and _t < 1.0:
		return
	if _i >= 0:
		var s: Array = _steps[_i]
		var p: Control = (s[2] as Callable).call()
		app.save_shot("ui_panel_" + str(s[0]))
		var r := p.get_global_rect()
		_check(p.is_visible_in_tree(), "%s is open" % s[0])
		_check(_zone(str(s[3])).grow(1.0).encloses(r), "%s inside its zone %s (%s)" % [s[0], s[3], r])
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokePaneles] done (%d fails)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	(_steps[_i][1] as Callable).call()
