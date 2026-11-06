extends Node
## Scripted capture of the scholar's physician (H12.2, docs/gdd/04d_otras_clases.md 4.22.5; --smoke-script=erudito,
## through `grimoire heavy` with --always-on-top): the new game screen with the physician chosen; a new game as
## scholar_physician: the Consulta on the street; inside, Leonor at the cot seeing a patient while three more wait in the
## waiting room (one grave: its bubble asks for a salve); the cot's menu (the consultation and the surgery, the patients
## waiting, the price with − / +); the bandages at the mortar; the upper floor; the ledger's Debts tab with the
## moneylender's card; and every upgrade of its tree (capture only: the state is edited directly, as the oficios script).
## Shots reports/shots/erudito_<what>.png. Prints "[SmokeErudito] ok|FAIL ..."; quits with 1 on a FAIL or a timeout.

const BLD := "bld_0001"
const DOC := "chr_0001"
const LOT := Vector2i(24, 21)   # the lot by the plaza: the player's forge, here the Consulta

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
		["consulta", func() -> void: _consultation(), 3.0],
		["camilla", func() -> void: app.interior().open_station_menu("cot", Vector2(300, 170)), 1.0],
		["vendas", func() -> void: _bandages(), 2.0],
		["arriba", func() -> void: _upstairs(), 1.0],
		["deudas", func() -> void: _debts(), 1.0],
		["mejoras", func() -> void: _all_upgrades(), 1.5],
		["banco_calle", func() -> void: _start_bank(), 1.5],
		["banco", func() -> void: _bank_applications(), 1.5],
		["banco_cartera", func() -> void: _bank_portfolio(), 1.0],
		["banco_impagos", func() -> void: app.interior().bank_panel().show_tab("defaults"), 1.0],
	]
	print("[SmokeErudito] start (%d shots)" % _steps.size())


func _new_game_screen() -> void:
	app.show_new_game()
	var s: NewGameScreen = app.new_game_screen()
	var b := s.get_node("%Profession").get_node_or_null("Physician") as Button
	_check(b != null, "the physician's button")
	if b != null:
		b.pressed.emit()
	_check(s.start_id == "scholar_physician", "the physician's start chosen")


func _start() -> void:
	(app.new_game_screen().get_node("%TutorialCheck") as CheckBox).button_pressed = false  # its shots, not the tutorial's
	var r := NewGame.from_start(Game.sim.catalog, "scholar_physician", "normal", {"cast": "fixed"}, 7)
	_check(bool(r["ok"]), "scholar_physician starts")
	app.call("_on_new_game_started", r["state"])
	Game.set_paused(true)
	if app.interior_building != "":
		app.close_interior()
	app.world().camera().center_on(Iso.tile_to_world(LOT))
	_check(str(Game.sim.state.buildings[BLD]["type"]) == "clinic", "the Consulta is the player's")


## Leonor inside at the cot with a patient, three more waiting (one grave), the day running for the fades.
func _consultation() -> void:
	var st := Game.sim.state
	st.clock["minute"] = Clock.MINUTES_PER_DAY * Clock.day(int(st.clock["minute"])) + 10 * 60
	st.characters[DOC]["location"] = BLD
	var m: Dictionary = Services._mem(st, BLD)
	var now := int(st.clock["minute"])
	for sev: int in [3, 5, 7, 3]:
		m["seq"] = int(m["seq"]) + 1
		(m["waiting"] as Array).append({"id": "svc_%s_%d" % [BLD, int(m["seq"])], "service": "doctor", "severity": sev,
			"since": now - 10 * int(m["seq"]), "claimed": ""})
	var r := Orders.apply(Game.sim, {"type": "work_at", "actor": DOC, "building": BLD, "zone": "cot",
		"recipe": "doctor_visit", "mode": "normal"})
	_check(bool(r["ok"]), "Leonor at the cot: %s" % r["reason"])
	app.open_interior(BLD, false)
	Game.set_paused(false)
	_check(Services.waiting(st, BLD).size() == 4, "four patients")


func _bandages() -> void:
	app.interior().station_menu().close()
	Game.set_paused(true)
	var job: Variant = Game.sim.state.buildings[BLD]["zones"]["cot"].get("job")
	_check(job is Dictionary and str((job as Dictionary).get("client", "")) != "", "a patient on the cot")
	app.interior().open_station_menu("mortar", Vector2(260, 200))
	_check(app.interior().station_menu().visible, "the mortar's menu")


func _upstairs() -> void:
	app.interior().station_menu().close()
	var stage := app.interior().get_node_or_null("InteriorStage") as InteriorStage
	_check(stage != null, "the Consulta built from data")
	if stage != null:
		stage.show_level(1)


func _all_upgrades() -> void:
	app.hud().ledger_panel().close()
	var b: Dictionary = Game.sim.state.buildings[BLD]
	for u: Variant in Game.sim.catalog.upgrade_tree("clinic"):
		var id := str((u as Dictionary).get("id", u)) if u is Dictionary else str(u)
		Upgrades.complete(Game.sim, BLD, id)
	app.close_interior()
	app.open_interior(BLD, true)
	_check((b["upgrades"] as Array).size() == 24, "clinic: 24 upgrades")


func _debts() -> void:
	var stage := app.interior().get_node_or_null("InteriorStage") as InteriorStage
	if stage != null:
		stage.show_level(0)
	app.close_interior()
	Game.sim.state.families[SimQuery.player_family(Game.sim.state)]["gold"] = 160
	app.hud().open_ledger("debts")
	_check(app.hud().ledger_panel().visible, "the ledger on Debts")


## H12.2 · the banker: a new game as scholar_banker, its Banco on the forge's plot.
func _start_bank() -> void:
	app.close_interior()
	app.hud().ledger_panel().close()
	var r := NewGame.from_start(Game.sim.catalog, "scholar_banker", "normal", {"cast": "fixed"}, 7)
	_check(bool(r["ok"]), "scholar_banker starts")
	app.call("_on_new_game_started", r["state"])
	Game.set_paused(true)
	app.world().camera().center_on(Iso.tile_to_world(LOT))
	_check(str(Game.sim.state.buildings[BLD]["type"]) == "bank", "the Banco is the player's")


## Three households ask (a good, a fair and a poor solvency) and the Banco's panel shows them.
func _bank_applications() -> void:
	var st := Game.sim.state
	var who: Array = []
	var fams := {}
	for id: String in st.characters:
		var f := str(st.characters[id].get("family", ""))
		if TownLife.is_townsperson(st, id) and TownLife.is_adult(st, Game.sim.catalog, id) and not fams.has(f):
			fams[f] = true
			who.append(id)
	who.sort()
	var plan := [["A", 300, 8], ["B", 450, 12], ["C", 250, 4], ["B", 600, 8]]
	for k: int in mini(plan.size(), who.size()):
		Bank._add(Game.sim, BLD, "household", str(st.characters[who[k]]["family"]), str(who[k]), int(plan[k][1]),
			int(plan[k][2]), str(plan[k][0]))
	app.open_interior(BLD, true)
	app.interior().show_bank(true)
	_check(app.interior().bank_panel().visible, "the Banco's panel")
	_check(Bank.applications(st, BLD).size() >= 3, "applications waiting")


## Two loans granted, a day on, one of them in default: the portfolio.
func _bank_portfolio() -> void:
	var st := Game.sim.state
	var apps := Bank.applications(st, BLD)
	for a: Dictionary in apps:
		if str(a["risk"]) in ["A", "B"]:
			Orders.apply(Game.sim, {"type": "grant_loan", "actor": DOC, "application": str(a["id"]),
				"interest": float(a["max_interest"])})
	var mine := Bank.portfolio(st, SimQuery.player_family(st))
	_check(mine.size() >= 2, "loans granted (%d)" % mine.size())
	if not mine.is_empty():
		Bank._default(Game.sim, str(mine[-1]))
		st.loans[str(mine[-1])]["defaulted_at"] = int(st.clock["minute"]) - Clock.MINUTES_PER_DAY
	app.interior().bank_panel().show_tab("portfolio")


func _check(cond: bool, what: String) -> void:
	print("[SmokeErudito] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeErudito] TIMEOUT at %d" % _i)
		app.save_shot("erudito_timeout")
		get_tree().quit(1)
		return
	if _i == -1:
		if _t < 0.5:
			return
	elif _t < float(_steps[_i][2]):
		return
	else:
		app.save_shot("erudito_" + str(_steps[_i][0]))
	_i += 1
	_t = 0.0
	if _i >= _steps.size():
		print("[SmokeErudito] done (%d fails)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	(_steps[_i][1] as Callable).call()
