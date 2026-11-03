extends Node
## Scripted captures of the economy panels from inside (--smoke-script=economia [--eco=forja,produccion,...]; through
## `grimoire heavy` with --always-on-top): a real new game as the blacksmith, then each document's screens as its
## buttons and keys would open them. Shots to reports/shots/<doc>_hoy_<what>.png (docs/ui/maquetas keeps the copies).
## Orders only through Game.give. Every check prints "[SmokeEconomia] ok|FAIL ..."; any FAIL quits with 1.
## A step waits for its condition (until), acts (do), then lets `wait` seconds pass before the next one.
## Sections: forja (station menu, the station's bar and the master touch, the active pause marks, the routine);
## produccion (the scenario two_employees: the Now, Queue and Recipes tabs); almacen (the storage's squares, the sheet).

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
	var r := NewGame.from_start(Game.sim.catalog, "artisan_blacksmith", "normal", {}, 7)
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
		var r := NewGame.from_start(Game.sim.catalog, "artisan_blacksmith", "normal", {}, 7)
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
