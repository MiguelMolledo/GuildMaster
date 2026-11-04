extends Node
## Scripted capture of the new HUD (--smoke-script=hud, docs/ui/01_hud.md §13; run it through `grimoire heavy` with
## --always-on-top): the town with the forge picked (hud_hoy_mapa); the account book open, the forge's bar still in
## sight (hud_hoy_libro); four urgent notices and a warning (three on screen: hud_hoy_avisos); the help with «Ahora
## mismo» (hud_hoy_ayuda); ESC closing in order and then asking for the pause menu; Hugo inside the forge in pause with
## two orders queued (hud_hoy_interior) and the forge's production panel (hud_hoy_produccion). Each check prints
## "[SmokeHud] ok|FAIL ..."; any FAIL quits with 1. Shots in reports/shots/.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var app: Node = null
var timeout: float = 120.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _fails: int = 0
var _menu_asked: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	app.hud().connect("pause_menu_requested", func() -> void: _menu_asked += 1)
	print("[SmokeHud] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeHud] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _check(cond: bool, what: String) -> void:
	print("[SmokeHud] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _rect(n: String) -> Rect2:
	var c := app.hud().get_node(n) as Control
	return c.get_global_rect() if c.is_visible_in_tree() else Rect2()


func _fixed_overlaps() -> Array:
	var names := ["%Card", "%StatusBar", "%ClockPanel", "%SelectionBar", "%NoticePopups"]
	var out: Array = []
	for i: int in names.size():
		for j: int in range(i + 1, names.size()):
			var a := _rect(names[i])
			var b := _rect(names[j])
			if a.has_area() and b.has_area() and a.intersects(b):
				out.append([names[i], names[j]])
	return out


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeHud] TIMEOUT in step %s" % _step)
		app.save_shot("hud_timeout")
		get_tree().quit(1)
		return
	var hud: Node = app.hud()
	var hugo: Dictionary = Game.sim.state.characters[HUGO]
	match _step:
		"start":
			if _t > 0.3:
				# a real new game (the debt, the start objectives), as the Start button does
				var r := NewGame.from_start(Game.sim.catalog, "artisan_blacksmith", "normal", {"cast": "fixed"}, 7)
				app.call("_on_new_game_started", r["state"])
				_go("pick")
		"pick":
			if _t > 0.5:
				app.world().select(HUGO)
				app.world().pick_building_id(BLD)
				_go("map")
		"map":
			if _t > 0.8:
				app.save_shot("hud_hoy_mapa")
				_check(_fixed_overlaps().is_empty(), "no fixed zones overlap on the map (%s)" % [_fixed_overlaps()])
				for pair: Array in [["card", "%Card"], ["status", "%StatusBar"], ["clock", "%ClockPanel"]]:
					var r := _rect(str(pair[1]))
					_check((HudLayout.ZONES[pair[0]] as Rect2).grow(0.5).encloses(r), "%s fits its zone (%s)" % [pair[0], r])
				_check(_rect("%SelectionBar").has_area(), "the forge in the selection bar")
				_check((HudLayout.ZONES["selection"] as Rect2).grow(0.5).encloses(_rect("%SelectionBar")),
					"the selection bar inside zone 6 (%s)" % _rect("%SelectionBar"))
				app.world().pick_building_id("")
				# Hugo where the book will open: the camera must move him out from under it (§4.6)
				var cam: WorldCamera = app.world().camera()
				cam.pan(-(Vector2(780, 260) - cam.world_to_screen(app.world().view_of(HUGO).position)))
				_go("reveal")
		"reveal":
			if _t > 0.3:
				hud.open_ledger()
				_go("revealed")
		"revealed":
			if _t > 0.4:
				var cam: WorldCamera = app.world().camera()
				var at := cam.world_to_screen(app.world().view_of(HUGO).position)
				var book: Rect2 = (hud.call("ledger_panel") as Control).get_global_rect()
				_check(not book.has_point(at), "the camera moved Hugo out from under the book (%s, book %s)" % [at, book])
				hud.ledger_panel().close()
				app.world().pick_building_id(BLD)
				hud.open_ledger()
				_go("book")
		"book":
			if _t > 0.6:
				app.save_shot("hud_hoy_libro")
				var book: Rect2 = (hud.call("ledger_panel") as Control).get_global_rect()
				var bar := _rect("%SelectionBar")
				_check(hud.ledger_panel().visible and bar.has_area() and not book.intersects(bar),
					"with the book open the forge's bar is seen whole (book=%s, bar=%s, open=%s)" % [book, bar,
					hud.ledger_panel().visible])
				var fam := SimQuery.player_family(Game.sim.state)
				for i: int in 4:
					hud.call("_on_notice", {"type": "notice_added", "family": fam, "severity": "urgent",
						"key": "notice.loan_due_soon", "params": {"days": 4 - i, "amount": 190 - 10 * i}})
				hud.ledger_panel().close()
				_go("notices")
		"notices":
			if _t > 0.5:
				var shown: Array = hud.call("shown_notices")
				_check(shown.size() == 3, "4 urgent notices: 3 on screen (%d)" % shown.size())
				var fam := SimQuery.player_family(Game.sim.state)
				hud.call("_on_notice", {"type": "notice_added", "family": fam, "severity": "info",
					"key": "notice.objective_done", "params": {"objective": "errand_purchase"}})
				_go("notices_shot")
		"notices_shot":
			if _t > 0.4:
				app.save_shot("hud_hoy_avisos")
				var shown: Array = hud.call("shown_notices")
				_check(str(shown[-1]["gravity"]) == "done", "a goal met pops up too, the newest at the bottom")
				hud.toggle_help()
				_go("help")
		"help":
			if _t > 0.5:
				app.save_shot("hud_hoy_ayuda")
				hud.open_ledger()   # one more thing open under the help
				_check(bool(hud.call("close_top")) and not hud.help_visible() and hud.ledger_panel().visible,
					"ESC 1 closes the help, the book stays")
				_check(bool(hud.call("close_top")) and not hud.ledger_panel().visible, "ESC 2 closes the book")
				_check(bool(hud.call("close_top")) and hud.building_id == "", "ESC 3 forgets the picked building")
				var before := _menu_asked
				var esc := InputEventAction.new()
				esc.action = "ui_cancel"
				esc.pressed = true
				Input.parse_input_event(esc)
				_go("menu")
				set_meta("before", before)
		"menu":
			if _t > 0.3:
				_check(_menu_asked == int(get_meta("before")) + 1, "ESC with nothing open asks for the pause menu")
				_check(app.pause_menu().visible, "and the pause menu opens")
				app.pause_menu().close()
				Game.set_paused(false)
				app.world().command_enter(BLD)
				_go("entering")
		"entering":
			if str(hugo["location"]) == BLD and app.interior_building == BLD and _t > 0.8:
				Game.set_paused(true)
				app.interior().open_station_menu("anvil", app.interior().station_screen("anvil"))
				app.interior().station_menu().choose_mode("careful")
				app.interior().station_menu().choose_recipe("forge_sword")
				app.interior().open_station_menu("furnace", app.interior().station_screen("furnace"))
				app.interior().station_menu().choose_mode("normal")
				app.interior().station_menu().choose_recipe("forge_ingot")
				_go("inside")
		"inside":
			if _t > 0.8:
				app.save_shot("hud_hoy_interior")
				var col: Dictionary = hud.call("column_rects")
				var obj: Rect2 = col.get("ObjectivePanel", Rect2())
				var queue: Rect2 = col.get("QueuePanel", Rect2())
				var zone: Rect2 = HudLayout.ZONES["column"]
				_check(queue.has_area() and not obj.intersects(queue), "objective and orders do not overlap (%s, %s)" % [obj, queue])
				_check(zone.grow(1).encloses(obj) and zone.grow(1).encloses(queue), "both inside the column %s" % zone)
				_check(_rect("%SelectionBar") == Rect2(), "inside, the HUD's selection bar gives way to the building's")
				var ibar: Rect2 = (app.interior().get_node("%BuildingBar") as Control).get_global_rect()
				_check((HudLayout.ZONES["selection"] as Rect2).grow(0.5).encloses(ibar), "the building's bar in zone 6 (%s)" % ibar)
				app.interior().show_production(true)
				_go("production")
		"production":
			if _t > 0.6:
				app.save_shot("hud_hoy_produccion")
				hud.open_ledger()
				_check(not app.interior().production_panel().visible, "the book closes the production (one panel)")
				hud.ledger_panel().close()
				var said := [""]
				hud.confirm_modal().answered.connect(func(yes: bool) -> void: said[0] = "yes" if yes else "no", CONNECT_ONE_SHOT)
				hud.confirm_modal().ask({"title": "¿Comprar Acero templado?",
					"body": "Cuesta 25 de oro y 3 de carbón. Te quedan 5 de oro.", "action": "Comprar", "irreversible": true,
					"seal": true})
				set_meta("said", said)
				_go("confirm")
		"confirm":
			if _t > 0.5:
				app.save_shot("hud_hoy_confirmacion")
				var esc := InputEventAction.new()
				esc.action = "ui_cancel"
				esc.pressed = true
				Input.parse_input_event(esc)
				_go("confirm_esc")
		"confirm_esc":
			if _t > 0.3:
				_check(not hud.confirm_modal().visible and str((get_meta("said") as Array)[0]) == "no",
					"ESC cancels the confirmation first (01 §2)")
				_check(not app.pause_menu().visible, "and does not open the pause menu with it")
				print("[SmokeHud] done (%d fails)" % _fails)
				_go("done")
				get_tree().quit(1 if _fails > 0 else 0)
