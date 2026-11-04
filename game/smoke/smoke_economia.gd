extends Node
## Scripted captures of the economy panels from inside (--smoke-script=economia [--eco=forja,produccion,...]; through
## `grimoire heavy` with --always-on-top): a real new game as the blacksmith, then each document's screens as its
## buttons and keys would open them. Shots to reports/shots/<doc>_hoy_<what>.png (docs/ui/maquetas keeps the copies).
## Orders only through Game.give. Every check prints "[SmokeEconomia] ok|FAIL ..."; any FAIL quits with 1.
## A step waits for its condition (until), acts (do), then lets `wait` seconds pass before the next one.
## Sections: forja (station menu, the station's bar and the master touch, the active pause marks, the routine);
## produccion (the scenario two_employees: the Now, Queue and Recipes tabs); almacen (the storage's squares, the sheet);
## mercado (Hugo walks to the Resources stall: buy, sell, then the book's debts, today, days and the confirmation);
## empleados (a new game: Hire with the ranks and the inline confirmation; two_employees with Joan's promotion pending
## (set in the state for the shot): Staff and the confirmation of firing); mejoras (a new game with the doc's 65 gold,
## 2 ingots and 3 wood: the tree with Second anvil chosen and Commercial reputation hovered, Build's confirmation, the
## works in progress, a facade drawn outside).

const BLD := "bld_0001"
const HUGO := "chr_0001"

var app: Node = null
var timeout: float = 240.0
var _steps: Array = []    # [{name, until: Callable, wait: float, do: Callable}]
var _i: int = -1
var _t: float = 0.0
var _total: float = 0.0
var _fails: int = 0
var _sections: Array = []
var _done_step: bool = false


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--eco="):
			_sections = Array(a.substr(6).split(","))
		elif a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	var r := NewGame.from_start(Game.sim.catalog, "artisan_blacksmith", "normal", {"cast": "fixed"}, 7)
	app.call("_on_new_game_started", r["state"])
	_step("pick", func() -> void:
		app.world().select(HUGO)
		Game.set_speed(4))
	if _on("forja"):
		_forja()
	if _on("produccion"):
		_produccion()
	if _on("almacen"):
		_almacen()
	if _on("mercado"):
		_mercado()
	if _on("empleados"):
		_empleados()
	if _on("mejoras"):
		_mejoras()
	print("[SmokeEconomia] start (%d steps, sections=%s)" % [_steps.size(), _sections])


func _on(section: String) -> bool:
	return _sections.is_empty() or section in _sections


func _step(name_: String, do: Callable, until: Callable = Callable(), wait: float = 0.6) -> void:
	_steps.append({"name": name_, "do": do, "until": until, "wait": wait})


func _shot(name_: String) -> void:
	app.save_shot(name_)


func _check(cond: bool, what: String) -> void:
	print("[SmokeEconomia] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeEconomia] TIMEOUT at %s" % (_steps[_i]["name"] if _i >= 0 else "start"))
		app.save_shot("economia_timeout")
		get_tree().quit(1)
		return
	if _i >= 0 and not _done_step:
		var until: Callable = _steps[_i]["until"]
		if until.is_valid() and not bool(until.call()):
			return   # the step waits for its condition, then acts
		_done_step = true
		_t = 0.0
		print("[SmokeEconomia] step %s (t=%.1f s)" % [_steps[_i]["name"], _total])
		(_steps[_i]["do"] as Callable).call()
		return
	if _i >= 0 and _t < float(_steps[_i]["wait"]):
		return
	_i += 1
	_t = 0.0
	_done_step = false
	if _i >= _steps.size():
		print("[SmokeEconomia] done (%d fails)" % _fails)
		get_tree().quit(1 if _fails > 0 else 0)


# --- forja_interior.md ---------------------------------------------------------------------------------------------

func _inside() -> bool:
	return str(Game.sim.state.characters[HUGO]["location"]) == BLD and app.interior_building == BLD


func _forja() -> void:
	_step("enter", func() -> void: app.world().command_enter(BLD), Callable(), 0.2)
	_step("menu", func() -> void:
		var iv: InteriorView = app.interior()
		iv.open_station_menu("anvil", iv.station_screen("anvil") + Vector2(40, -120)), _inside, 1.0)
	_step("menu_shot", func() -> void:
		_shot("forja_interior_hoy_menu")
		var m: StationMenu = app.interior().station_menu()
		_check(m.visible and m.recipe_buttons().size() == 3, "the anvil's menu in one box with its 3 recipes")
		_check(m.reason_of("forge_sword") != "", "the sword says why it cannot be made (no ingots yet)")
		var r := m.get_global_rect()
		_check(not r.intersects((app.interior().get_node("%BuildingBar") as Control).get_global_rect()),
			"the menu does not cover the building's bar")
		m.close()
		Game.give({"type": "work_at", "actor": HUGO, "building": BLD, "zone": "furnace", "recipe": "forge_ingot",
			"mode": "careful"}))
	_step("bar", func() -> void:
		var sv: StationView = app.interior().station_view("furnace")
		_check(sv.window_from > 0.0, "the touch window on the furnace's bar from the first minute (%.2f)" % sv.window_from)
		_shot("forja_interior_hoy_barra"),
		func() -> bool: return app.interior().station_view("furnace").progress > 0.05, 0.3)
	_step("touch", func() -> void:
		_shot("forja_interior_hoy_toque")
		_check(app.interior().station_view("furnace").status() == "window", "the station's mark: the window is open"),
		func() -> bool: return app.interior().station_view("furnace").window_open, 0.4)
	_step("pause", func() -> void:
		app.interior().click_station("furnace")   # the master touch
		Game.set_paused(true)
		Game.give({"type": "go_to_station", "actor": HUGO, "zone": "anvil"})
		Game.give({"type": "go_to_station", "actor": HUGO, "zone": "storage"})
		Game.give({"type": "go_to_station", "actor": HUGO, "zone": "counter"}), Callable(), 0.3)
	_step("pause_shot", func() -> void:
		_shot("forja_interior_hoy_pausa")
		var iv: InteriorView = app.interior()
		var a: Array = iv.station_view("anvil").marks
		var b: Array = iv.station_view("storage").marks
		var c: Array = iv.station_view("counter").marks
		_check(a.size() == 1 and b.size() == 1 and c.size() == 1 and int(b[0]) == int(a[0]) + 1 and int(c[0]) == int(b[0]) + 1,
			"numbered marks over the three stations in pause, in order (%s %s %s)" % [a, b, c])
		Game.set_paused(false)
		app.hud().toggle_character_panel()
		(app.hud().get_node("%CharacterPanel") as CharacterPanel).show_tab("routine"), Callable(), 0.8)
	_step("routine_shot", func() -> void:
		_shot("forja_interior_hoy_rutina")
		var p: Control = app.hud().get_node("%CharacterPanel")
		var ed := p.find_child("RoutineEditor", true, false) as RoutineEditor
		_check(ed != null and ed.is_visible_in_tree() and (ed.get_node("%Strip") as Control).get_child_count() == 4,
			"the routine as a strip of the day")
		(app.hud().get_node("%CharacterPanel") as CharacterPanel).show_tab("inventory")
		app.hud().toggle_character_panel(), Callable(), 0.8)

## A scenario as the game (the load does the same): its state starts, Hugo selected.
func _load(scenario: String) -> void:
	var r := NewGame.from_scenario(scenario)
	app.call("_on_new_game_started", r["state"])
	app.world().select(HUGO)


# --- produccion.md -------------------------------------------------------------------------------------------------

func _produccion() -> void:
	_step("prod_load", func() -> void:
		_load("two_employees")
		Game.set_speed(4), Callable(), 0.5)
	_step("prod_open", func() -> void:
		app.open_interior(BLD, true)
		Game.give({"type": "queue_add", "actor": HUGO, "building": BLD, "recipe": "forge_sword", "qty": 5}), Callable(), 1.0)
	_step("prod_now", func() -> void:
		app.interior().show_production(true)
		app.interior().production_panel().show_tab("now"),
		func() -> bool: return app.interior_building == BLD, 2.5)
	_step("prod_now_shot", func() -> void:
		_shot("produccion_hoy_ahora")
		var p: ProductionPanel = app.interior().production_panel()
		_check(p.visible and p.tab == "now", "the Now tab")
		p.show_tab("queue"), Callable(), 0.6)
	_step("prod_queue_shot", func() -> void:
		_shot("produccion_hoy_cola")
		var p: ProductionPanel = app.interior().production_panel()
		_check(p.get_global_rect().size.y <= 431.0, "the queue fits the management zone (%s)" % p.get_global_rect())
		p.show_tab("recipes"), Callable(), 0.6)
	_step("prod_recipes_shot", func() -> void:
		_shot("produccion_hoy_recetas")
		app.interior().production_panel().show_tab("now"), Callable(), 0.3)

# --- almacen_y_personaje.md ----------------------------------------------------------------------------------------

func _almacen() -> void:
	_step("alm_enter", func() -> void:
		var r := NewGame.from_start(Game.sim.catalog, "artisan_blacksmith", "normal", {"cast": "fixed"}, 7)
		app.call("_on_new_game_started", r["state"])
		app.world().select(HUGO)
		Game.set_speed(4), Callable(), 0.4)
	_step("alm_walk", func() -> void: app.world().command_enter(BLD), Callable(), 0.2)
	_step("alm_open", func() -> void:
		Game.give({"type": "transfer", "actor": HUGO, "from": BLD, "to": HUGO, "item": "coal", "quality": 0, "qty": 2})
		app.interior().show_storage(true), _inside, 1.0)
	_step("alm_shot", func() -> void:
		_shot("almacen_y_personaje_hoy")
		var p: StoragePanel = app.interior().storage_panel()
		_check(p.visible and (p.get_node("%BuildingGrid") as Node).get_child_count() >= 10, "every square of the storage")
		app.interior().show_storage(false)
		app.hud().toggle_character_panel(), Callable(), 0.8)
	_step("alm_sheet_shot", func() -> void:
		_shot("almacen_y_personaje_hoy_ficha")
		var p: CharacterPanel = app.hud().get_node("%CharacterPanel")
		_check(p.visible and p.tab == "inventory", "the sheet (I) on its Inventory tab")
		app.hud().toggle_character_panel(), Callable(), 0.4)

# --- mercado_y_libro.md --------------------------------------------------------------------------------------------

func _at_stall() -> bool:
	return SimQuery.stall_at(Game.sim, HUGO) == "resources"


func _mercado() -> void:
	_step("mer_new", func() -> void:
		var r := NewGame.from_start(Game.sim.catalog, "artisan_blacksmith", "normal", {"cast": "fixed"}, 7)
		app.call("_on_new_game_started", r["state"])
		app.world().select(HUGO)
		Game.set_speed(4), Callable(), 0.4)
	_step("mer_walk", func() -> void:
		Game.give({"type": "move_to", "actor": HUGO, "tile": [16, 15]}), Callable(), 0.2)
	_step("mer_open", func() -> void:
		Game.set_speed(1)
		app.hud().open_market(HUGO, "resources"),
		func() -> bool: return _at_stall() and Market.is_open(Game.sim), 0.8)
	_step("mer_buy_shot", func() -> void:
		_shot("mercado_y_libro_hoy_puesto")
		var p: MarketPanel = app.hud().market_panel()
		var send := p.row_of("iron", 0).get_node("Controls/Send") as MenuButton
		_check(p.visible and send.text.contains("·"), "the errand button with its cost and time (%s)" % send.text)
		_check(send.get_global_rect().end.x <= 957.0, "the buy row is not cut at 960×540")
		Game.give({"type": "buy", "actor": HUGO, "stall": "resources", "item": "iron", "quality": 0, "qty": 3}), Callable(), 0.6)
	_step("mer_sell", func() -> void:
		app.hud().market_panel().show_tab("sell"), Callable(), 0.6)
	_step("mer_sell_shot", func() -> void:
		_shot("mercado_y_libro_hoy_vender")
		var row: Control = app.hud().market_panel().row_of("iron", 0)
		_check(row != null and (row.get_node("SellAll") as Button).text.contains("="), "Sell all with the sum unit by unit")
		app.hud().market_panel().close()
		app.hud().open_ledger("debts"), Callable(), 0.8)
	_step("mer_debt_shot", func() -> void:
		_shot("mercado_y_libro_hoy_deuda")
		app.hud().ledger_panel().show_tab("today"), Callable(), 0.6)
	_step("mer_today_shot", func() -> void:
		_shot("mercado_y_libro_hoy_libro")
		app.hud().ledger_panel().show_tab("days"), Callable(), 0.6)
	_step("mer_days_shot", func() -> void:
		_shot("mercado_y_libro_hoy_dias")
		app.hud().ledger_panel().show_tab("debts")
		var loans: Array = SimQuery.loans_of(Game.sim, SimQuery.player_family(Game.sim.state))
		app.hud().ledger_panel().repay(str(loans[0]["id"]), Money.gold(Game.sim.state, SimQuery.player_family(Game.sim.state))),
		Callable(), 0.6)
	_step("mer_confirm_shot", func() -> void:
		_shot("mercado_y_libro_hoy_confirmar")
		_check(app.hud().confirm_modal().visible, "paying all the gold asks first (under the dawn's charges)")
		app.hud().confirm_modal().cancel()
		app.hud().ledger_panel().close(), Callable(), 0.4)


# --- empleados.md --------------------------------------------------------------------------------------------------

func _empleados() -> void:
	_step("emp_new", func() -> void:
		var r := NewGame.from_start(Game.sim.catalog, "artisan_blacksmith", "normal", {"cast": "fixed"}, 7)
		app.call("_on_new_game_started", r["state"])
		app.world().select(HUGO)
		app.open_interior(BLD, true), Callable(), 1.0)
	_step("emp_hire", func() -> void:
		app.interior().show_staff(true), func() -> bool: return app.interior_building == BLD, 0.6)
	_step("emp_arm", func() -> void:
		get_viewport().warp_mouse(Vector2(90, 470))   # off the objective's tooltip
		var p: StaffPanel = app.interior().staff_panel()
		_check(p.tab == "hire", "the staff empty: it opens on Hire")
		var ok: Array = SimQuery.candidates(Game.sim, p.actor(), BLD).filter(
			func(c: Dictionary) -> bool: return str(c["status"]) == "ok")
		if ok.size() > 1:
			(p.row_of(str(ok[1]["character"])).find_child("Hire", true, false) as Button).pressed.emit(), Callable(), 0.6)
	_step("emp_hire_shot", func() -> void:
		_shot("empleados_hoy_contratar")
		var p: StaffPanel = app.interior().staff_panel()
		_check(p.armed() != "", "Hire waits for its second click with the wage")
		_check(p.hidden_below() > 0, "the line says how many candidates are below (%d)" % p.hidden_below())
		_check(p.get_global_rect().size.x <= 357.0 and p.get_global_rect().end.y <= 540.0, "nothing cut at 960×540, in its zone (%s)" % p.get_global_rect())
		_load("two_employees")
		Game.sim.state.characters["chr_0007"]["job"]["promotion_offered"] = true
		Game.sim.state.characters["chr_0008"]["job"]["loyalty"] = 75
		app.open_interior(BLD, true), Callable(), 1.0)
	_step("emp_staff", func() -> void:
		app.interior().show_staff(true, "staff"), func() -> bool: return app.interior_building == BLD, 2.0)
	_step("emp_staff_shot", func() -> void:
		_shot("empleados_hoy_plantilla")
		var p: StaffPanel = app.interior().staff_panel()
		_check(str((p.get_node("%List") as Node).get_child(0).name) == "chr_0007", "the pending promotion first")
		_check(p.get_global_rect().size.x <= 357.0 and p.get_global_rect().end.y <= 540.0, "the staff fits its zone (%s)" % p.get_global_rect())
		_check(app.interior().badges().get("staff", 0) == 1, "the badge on the Staff button")
		p.fire("chr_0008"), Callable(), 0.6)
	_step("emp_fire_shot", func() -> void:
		_shot("empleados_hoy_despedir")
		_check(app.hud().confirm_modal().visible, "firing asks first")
		_check(str(app.interior().staff_panel().fire_spec("chr_0008")["body"]).contains("-2"), "and warns of the reputation (loyal)")
		app.hud().confirm_modal().cancel()
		app.interior().show_staff(false), Callable(), 0.4)


# --- mejoras.md ----------------------------------------------------------------------------------------------------

func _mejoras() -> void:
	_step("upg_new", func() -> void:
		var r := NewGame.from_start(Game.sim.catalog, "artisan_blacksmith", "normal", {"cast": "fixed"}, 7)
		app.call("_on_new_game_started", r["state"])
		app.world().select(HUGO)
		var fam := SimQuery.building_family(Game.sim.state, BLD)
		Game.sim.state.families[fam]["gold"] = 65   # the doc's case: 65 gold, 2 ingots, 3 wood
		var inv: Dictionary = Game.sim.state.buildings[BLD]["inventory"]
		inv["stacks"] = []
		Inventory.add(inv, Game.sim.catalog, "iron_ingot", 0, 2)
		Inventory.add(inv, Game.sim.catalog, "wood", 0, 3)
		app.open_interior(BLD, true), Callable(), 1.0)
	_step("upg_open", func() -> void:
		get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.12, 0.6))   # off any tooltip
		app.interior().show_upgrades(true)
		app.interior().upgrade_panel().select("forge_capacity_1")
		app.interior().upgrade_panel().hover("forge_commerce_3"),
		func() -> bool: return app.interior_building == BLD, 1.0)
	_step("upg_shot", func() -> void:
		_shot("mejoras_hoy")
		var p: UpgradePanel = app.interior().upgrade_panel()
		_check(p.status_of("forge_capacity_1") == "missing_materials", "Second anvil short of ingots")
		_check(p.prereq_marked("forge_facade_1"), "Stone facade lit as a prerequisite")
		var r := p.get_global_rect()
		_check(r.size.x <= 713.0 and r.end.y <= 489.0, "the panel in the wide zone (%s)" % r)
		var cut := 0
		for id: String in Game.sim.catalog.upgrade_tree("forge"):
			var l := p.cell_of(id).find_child("Name", true, false) as Label
			if l.get_line_count() > 2 or l.get_line_count() * l.get_line_height() > l.size.y + 1.0:
				cut += 1
				print("[SmokeEconomia] cut name: %s (%s)" % [l.text, l.size])
		_check(cut == 0, "the 24 names whole at 960×540 (%d cut)" % cut)
		p.hover("")
		var fam := SimQuery.building_family(Game.sim.state, BLD)
		Game.sim.state.families[fam]["gold"] = 200
		p.select("forge_production_1")
		p.buy("forge_production_1"), Callable(), 0.6)
	_step("upg_confirm_shot", func() -> void:
		_shot("mejoras_hoy_confirmar")
		_check(app.hud().confirm_modal().visible, "Build always asks")
		app.hud().confirm_modal().confirm(), Callable(), 0.4)
	_step("upg_works", func() -> void:
		app.interior().upgrade_panel().select("forge_quality_1"),
		func() -> bool: return not SimQuery.upgrade_works(Game.sim, BLD).is_empty(), 1.0)
	_step("upg_works_shot", func() -> void:
		_shot("mejoras_hoy_obra")
		var p: UpgradePanel = app.interior().upgrade_panel()
		var cut := 0
		for id: String in Game.sim.catalog.upgrade_tree("forge"):
			var l := p.cell_of(id).find_child("Name", true, false) as Label
			if l.get_line_count() > 2 or l.get_line_count() * l.get_line_height() > l.size.y + 1.0:
				cut += 1
				print("[SmokeEconomia] cut name in works: %s (%s)" % [l.text, l.size])
		_check(cut == 0, "the names whole during the works too (%d cut)" % cut)
		_check(p.status_of("forge_quality_1") == "busy" and (p.cell_of("forge_quality_1").find_child("Price", true, false) as Label).text != "",
			"the others say one at a time")
		p.select("forge_facade_1"), Callable(), 0.6)
	_step("upg_facade_shot", func() -> void:
		_shot("mejoras_hoy_fachada")
		_check((app.interior().upgrade_panel().get_node("%Preview") as UpgradePreview).side() == "exterior", "a facade drawn outside")
		app.interior().show_upgrades(false), Callable(), 0.4)
