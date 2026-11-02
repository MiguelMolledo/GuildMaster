extends Node
## Scripted walk through the vertical slice (H5, --smoke-script=rebanada; run it through `grimoire heavy` with
## --dev-time and the engine's --always-on-top). It plays the first days the way the owner would, through the same
## calls the clicks make, and takes a shot at each step (reports/shots/h5_rebanada_NN_<step>.png):
## new game screen → start → the forge by hand (two ingots and a careful sword with the master touch) → the sword
## sold at the Armory → the carpenter's contract accepted at the board → two hammers made and delivered → an errand
## bought at the resources stall (wood and iron sent to the forge) → part of the debt repaid in the book → an
## employee hired → the production queue → an upgrade bought → three days at ×4 with a shot at each dawn, the
## interior with the upgrade and the book at the end. Also the help overlay (F1). Each step logs what it did and why
## it waits; a step that cannot go on (a refusal) is logged with its reason and the run goes on to the next part.
## Quits when done, or after `timeout` seconds with a shot of whatever is on screen.

var app: Node = null
var timeout: float = 420.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _n: int = 0
var _who: String = ""
var _fam: String = ""
var _forge: String = ""
var _armory: String = ""
var _contract: String = ""
var _touched: bool = false
var _last_day: int = -1
var _days_shot: int = 0
var _first_day: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeRebanada] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeRebanada] %s -> %s (t=%.1f s, %s, gold=%d)" % [_step, step, _total, _clock(), _gold()])
	_step = step
	_t = 0.0


func _clock() -> String:
	if Game.sim == null:
		return "-"
	var t := Game.sim.now()
	return "day %d %02d:%02d" % [int(t["day"]), int(t["hour"]), int(t["minute"])]


func _gold() -> int:
	return Money.gold(Game.sim.state, _fam) if Game.sim != null and _fam != "" else 0


func _shot(step_name: String) -> void:
	_n += 1
	app.save_shot("h5_rebanada_%02d_%s" % [_n, step_name])


func _ch() -> Dictionary:
	return Game.sim.state.characters.get(_who, {})


func _count(inv: Dictionary, item: String) -> int:
	return Inventory.count(inv, item)


func _storage(item: String) -> int:
	return _count(Game.sim.state.buildings[_forge]["inventory"], item)


func _bag(item: String) -> int:
	return _count(_ch().get("inventory", {}), item)


## The quality of the first stack of `item` in `inv` (-1 if none).
func _quality(inv: Dictionary, item: String) -> int:
	for s: Dictionary in inv.get("stacks", []):
		if str(s["item"]) == item:
			return int(s["quality"])
	return -1


func _svc(id: String) -> Dictionary:
	for s: Dictionary in SimQuery.map_services(Game.sim.state, Game.sim.catalog):
		if str(s["id"]) == id:
			return s
	return {}


func _centre_on_forge() -> void:
	var d: Array = Game.sim.state.buildings[_forge]["door"]
	app.world().camera().center_on(Iso.tile_to_world(Vector2i(int(d[0]), int(d[1]))))


## Stop at `zone` from its menu, only if the person still works there (else the sim says «not working»).
func _stop(zone: String) -> void:
	if str(_ch().get("station", "")) == zone and not Production.job_view(Game.sim, _forge, zone).is_empty():
		app.interior().station_menu().open_for(Game.sim, app.interior().actor(), _forge, zone)
		app.interior().station_menu().stop()


## Every stack of `item` in the forge's storage into the person's bag (one Take per quality).
func _take_all(item: String) -> void:
	for s: Dictionary in (Game.sim.state.buildings[_forge]["inventory"]["stacks"] as Array).duplicate(true):
		if str(s["item"]) == item:
			app.interior().storage_panel().move_to_actor(item, int(s["quality"]), int(s["qty"]))


func _work(zone: String, mode: String, recipe: String) -> void:
	var at: Vector2 = app.interior().station_screen(zone)
	app.interior().open_station_menu(zone, at)
	app.interior().station_menu().choose_mode(mode)
	app.interior().station_menu().choose_recipe(recipe)


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeRebanada] TIMEOUT in step %s (%s)" % [_step, _clock()])
		app.save_shot("h5_rebanada_timeout")
		get_tree().quit(1)
		return
	var hud: Node = app.hud()
	var iv: Node = app.interior()
	match _step:
		"start":
			if _t > 0.3:
				app.show_new_game()
				_go("new_game")
		"new_game":
			if _t > 0.6:
				_shot("partida_nueva")
				app.new_game_screen().start_game()   # the Start button
				_go("started")
		"started":
			if _t > 0.6 and not app.new_game_screen().visible:
				_fam = SimQuery.player_family(Game.sim.state)
				_who = SimQuery.family_actor(Game.sim.state, _fam)
				for b: String in Game.sim.state.buildings:
					var t := str(Game.sim.state.buildings[b]["type"])
					if t == "forge" and SimQuery.building_family(Game.sim.state, b) == _fam:
						_forge = b
					elif t == "armory":
						_armory = b
				_first_day = int(Game.sim.now()["day"])
				print("[SmokeRebanada] family=%s who=%s forge=%s armory=%s" % [_fam, _who, _forge, _armory])
				app.world().select(_who)
				Game.set_paused(true)
				_go("shot_start")
		"shot_start":
			if _t > 0.5:
				_shot("inicio")
				hud.toggle_help()
				_go("shot_help")
		"shot_help":
			if _t > 0.5:
				_shot("ayuda")
				hud.toggle_help()
				Game.set_paused(false)
				app.world().command_enter(_forge)   # right click on the forge
				_go("to_forge")
		# --- the forge by hand ---------------------------------------------------------------------------------
		"to_forge":
			if app.interior_building == _forge and str(_ch()["location"]) == _forge and _t > 0.6:
				_work("furnace", "normal", "forge_ingot")
				_go("ingots")
		"ingots":
			if _storage("iron_ingot") >= 2:
				var at: Vector2 = iv.station_screen("anvil")
				iv.open_station_menu("anvil", at)
				iv.station_menu().choose_mode("careful")
				_go("anvil_menu")
		"anvil_menu":
			if _t > 0.4:
				_shot("menu_yunque")
				iv.station_menu().choose_recipe("forge_sword")
				_go("sword")
		"sword":
			var job := Production.job_view(Game.sim, _forge, "anvil")
			if not _touched and bool(job.get("window_open", false)):
				iv.click_station("anvil")   # left click while it blinks: the master touch
				_touched = true
				Game.set_paused(true)
				_go("shot_touch")
			elif _storage("sword") > 0:
				_go("sword_done")
		"shot_touch":
			if _t > 0.4:
				_shot("toque_maestro")
				Game.set_paused(false)
				_go("sword")
		"sword_done":
			_stop("anvil")
			iv.show_storage(true)
			Game.set_paused(true)
			_go("shot_storage")
		"shot_storage":
			if _t > 0.5:
				_shot("almacen")
				iv.storage_panel().move_to_actor("sword", _quality(Game.sim.state.buildings[_forge]["inventory"], "sword"), 1)
				Game.set_paused(false)
				_go("carry")
		"carry":
			if _bag("sword") > 0 and _t > 0.3:
				iv.show_storage(false)
				iv.request_exit()   # the Exit button
				_go("leave_forge")
		# --- sell at the Armory ---------------------------------------------------------------------------------
		"leave_forge":
			if app.interior_building == "" and str(_ch()["location"]) == "" and _t > 0.6:
				app.world().command_enter(_armory)
				_go("to_armory")
		"to_armory":
			if app.interior_building == _armory and _t > 0.8:
				iv.open_shop()   # click on the counter
				_go("armory_panel")
		"armory_panel":
			if hud.market_panel().visible and _t > 0.4:
				hud.market_panel().show_tab("sell")
				Game.set_paused(true)
				_go("shot_armory")
			elif _t > 4.0:
				print("[SmokeRebanada] the armory panel did not open (%s)" % _clock())
				_shot("armeria_sin_panel")
				_go("leave_armory")
		"shot_armory":
			if _t > 0.5:
				_shot("armeria")
				hud.market_panel().sell("sword", _quality(_ch()["inventory"], "sword"), 1)
				Game.set_paused(false)
				_go("sold")
		"sold":
			if _bag("sword") == 0:
				_go("shot_sold")
			elif _t > 3.0:
				print("[SmokeRebanada] the sword was not sold (%s)" % _clock())
				_shot("armeria_no_vende")
				_go("leave_armory")
		"shot_sold":
			if _t > 0.6:
				_shot("vendida")
				hud.market_panel().close()
				_go("leave_armory")
		"leave_armory":
			hud.market_panel().close()
			iv.request_exit()
			_go("left_armory")
		# --- the carpenter's contract ---------------------------------------------------------------------------
		"left_armory":
			if app.interior_building == "" and str(_ch()["location"]) == "" and _t > 0.6:
				app.world().command_service(_svc("board"))   # right click on the board
				_go("to_board")
		"to_board":
			if hud.board_panel().visible and _t > 0.3:
				for c: Dictionary in Game.sim.state.contracts.get("board", []):
					if str(c.get("client", "")) == "carpenter":
						_contract = str(c["id"])
				if _contract != "":
					hud.board_panel().accept_contract(_contract)
				Game.set_paused(true)
				_go("shot_board")
		"shot_board":
			if _t > 0.6:
				_shot("tablon")
				hud.board_panel().close()
				Game.set_paused(false)
				app.world().command_enter(_forge)
				_go("to_forge_2")
		"to_forge_2":
			if app.interior_building == _forge and str(_ch()["location"]) == _forge and _t > 0.6:
				if _storage("iron_ingot") >= 2:
					_work("anvil", "normal", "forge_hammer")
					_go("hammers")
				else:
					_work("furnace", "normal", "forge_ingot")
					_go("ingots_2")
		"ingots_2":
			if _storage("iron_ingot") >= 2:
				_work("anvil", "normal", "forge_hammer")
				_go("hammers")
			elif _t > 20.0:
				print("[SmokeRebanada] no ingots for the hammers (%s)" % _clock())
				_shot("sin_lingotes")
				_go("errand")
		"hammers":
			if _storage("hammer") >= 2:
				_stop("anvil")
				iv.show_storage(true)
				_take_all("hammer")
				_go("carry_hammers")
			elif _t > 30.0:
				print("[SmokeRebanada] the hammers did not come out (%s)" % _clock())
				_shot("sin_martillos")
				_go("errand")
		"carry_hammers":
			if _bag("hammer") >= 2 and _t > 0.3:
				iv.show_storage(false)
				iv.request_exit()
				_go("leave_forge_2")
		"leave_forge_2":
			if app.interior_building == "" and str(_ch()["location"]) == "" and _t > 0.6:
				app.world().command_service(_svc("board"))
				_go("to_board_2")
		"to_board_2":
			if hud.board_panel().visible and _t > 0.3:
				hud.board_panel().deliver_contract(_contract)
				_go("delivered")
		"delivered":
			if _t > 0.6:
				Game.set_paused(true)
				_shot("entregado")
				hud.board_panel().close()
				Game.set_paused(false)
				_go("errand")
		# --- an errand at the resources stall -------------------------------------------------------------------
		"errand":
			app.world().command_service(_svc("resources"))
			_go("to_stall")
		"to_stall":
			if hud.market_panel().visible and _t > 0.3:
				hud.market_panel().show_tab("buy")
				if SimQuery.market_opens_at(Game.sim) > int(Game.sim.state.clock["minute"]) \
						and str(SimQuery.market_offers(Game.sim, _who, "resources").get("reason", "")) == "market_closed":
					Game.set_paused(true)
					_go("shot_closed")
				else:
					hud.market_panel().set_qty("wood", 0, 2)
					Game.set_paused(true)
					_go("shot_stall")
		"shot_closed":
			if _t > 0.5:
				_shot("mercado_cerrado")   # «El mercado está cerrado · abre a las…»
				Game.set_speed(4)
				Game.set_paused(false)
				_go("wait_open")
		"wait_open":
			if str(SimQuery.market_offers(Game.sim, _who, "resources").get("reason", "")) == "":
				Game.set_speed(1)
				hud.market_panel().set_qty("wood", 0, 2)
				Game.set_paused(true)
				_go("shot_stall")
		"shot_stall":
			if _t > 0.5:
				_shot("mercado")
				hud.market_panel().buy("wood", 0, 2, _forge)   # «Comprar y enviar a… Forja»
				hud.market_panel().buy("iron", 0, 6, _forge)
				_go("shot_errand")
		"shot_errand":
			if _t > 0.6:
				_shot("recado")
				hud.market_panel().close()
				Game.set_paused(false)
				_go("ledger")
		# --- repay part of the debt -----------------------------------------------------------------------------
		"ledger":
			if _t > 0.3:
				hud.open_ledger("debts")
				var loans := SimQuery.loans_of(Game.sim, _fam)
				if not loans.is_empty():
					hud.ledger_panel().repay(str(loans[0]["id"]), mini(10, _gold()))
				Game.set_paused(true)
				_go("shot_ledger")
		"shot_ledger":
			if _t > 0.6:
				_shot("deuda")
				hud.ledger_panel().close()
				Game.set_paused(false)
				app.open_interior(_forge, true)   # double click on the forge: management mode
				_go("manage")
		# --- hire, queue, upgrade -------------------------------------------------------------------------------
		"manage":
			if app.interior_building == _forge and _t > 0.8:
				iv.show_staff(true, "hire")
				_go("hire")
		"hire":
			if _t > 0.4:
				var hired := ""
				for r: Dictionary in SimQuery.candidates(Game.sim, iv.staff_panel().actor(), _forge):
					if str(r["status"]) == "ok":
						hired = str(r["character"])
						break
				Game.set_paused(true)
				_shot("contratar")
				if hired != "":
					iv.staff_panel().hire(hired)
				else:
					print("[SmokeRebanada] nobody to hire (%s)" % _clock())
				_go("hired")
		"hired":
			if _t > 0.5:
				Game.set_paused(false)
				iv.show_staff(true, "staff")
				_go("shot_staff")
		"shot_staff":
			if _t > 0.6:
				_shot("plantilla")
				iv.show_production(true)
				iv.production_panel().select_recipe("forge_ingot")
				iv.production_panel().add("forge_ingot", 5)
				_go("shot_queue")
		"shot_queue":
			if _t > 0.6:
				_shot("cola")
				iv.show_upgrades(true)
				iv.upgrade_panel().select("forge_production_1")
				_go("shot_tree")
		"shot_tree":
			if _t > 0.6:
				_shot("mejoras")
				var pick := "forge_production_1"
				if iv.upgrade_panel().status_of(pick) != "available":
					print("[SmokeRebanada] %s is %s: trying another" % [pick, iv.upgrade_panel().status_of(pick)])
					for u: String in Game.sim.catalog.upgrade_tree("forge"):
						if iv.upgrade_panel().status_of(u) == "available":
							pick = u
							break
				iv.upgrade_panel().select(pick)
				iv.upgrade_panel().buy(pick)
				_go("bought")
		"bought":
			if Upgrades.under_works(Game.sim.state, _forge) and _t > 0.4:
				_shot("obra")
				iv.show_upgrades(false)
				iv.request_exit()
				_go("days")
			elif _t > 3.0:
				print("[SmokeRebanada] no works started (%s)" % _clock())
				_shot("sin_obra")
				iv.show_upgrades(false)
				iv.request_exit()
				_go("days")
		# --- three days -----------------------------------------------------------------------------------------
		"days":
			if app.interior_building == "" and _t > 0.6:
				_last_day = int(Game.sim.now()["day"])
				Game.set_speed(4)
				_go("run")
		"run":
			var day := int(Game.sim.now()["day"])
			var hour := int(Game.sim.now()["hour"])
			if day != _last_day and hour >= 8:
				_last_day = day
				_days_shot += 1
				Game.set_paused(true)
				_centre_on_forge()
				app.world().pick_building_id(_forge)   # a left click on it: its panel (and why its employees idle)
				_go("shot_day")
		"shot_day":
			if _t > 0.5:
				_shot("dia%d" % (_last_day - _first_day + 1))
				if _days_shot >= 3:
					app.open_interior(_forge, true)
					_go("inside_end")
				else:
					Game.set_paused(false)
					_go("run")
		"inside_end":
			if app.interior_building == _forge and _t > 0.8:
				_shot("interior")
				iv.request_exit()
				hud.open_ledger("today")
				_go("book_end")
		"book_end":
			if _t > 0.8:
				_shot("libro")
				_go("done")
				get_tree().quit()
