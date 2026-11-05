extends Node
## Scripted capture of the H2 forge (--smoke-script=forja; run it through `grimoire heavy`, with --dev-time and the
## engine's --always-on-top: macOS stops drawing a covered window and the shots would repeat an old frame):
## the forge on the map with Hugo selected (h2_mapa); Hugo goes into the forge, smelts two ingots at the furnace, forges a sword with care at the anvil (with the master
## touch when its window opens), and the screenshots are taken on the way: the interior with Hugo at the anvil and
## the progress bar (h2_interior) after its station menu (h2_menu), the storage panel with the sword (h2_almacen) and Hugo's panel with the sword in
## his bag (h2_personaje); then, in pause, three orders queued and shown as a numbered list (h2_cola). It plays through the real UI paths (the same calls the clicks make) and gives orders only
## through Game.give. Quits when done, or after `timeout` seconds with a shot of whatever is on screen.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var app: Node = null
var timeout: float = 90.0
var _step: String = "start"
var _t: float = 0.0       # seconds in the current step
var _total: float = 0.0
var _touched: bool = false


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeForja] start (timeout=%.0f s)" % timeout)


## The shots without cards over the forge: every day of the year has its festival (data/festivals.json), whose card
## (EventCard, not modal) would cover the interior, and an incident card (a street brawl) or a microevent card may come
## too. Each frame (the shot copies the frame already drawn) the event cards are closed, like «Entendido», and the
## incident and microevent cards put off, like «Luego» (no order: the default comes at its timeout, as in the game).
func _shot(shot_name: String) -> void:
	app.save_shot(shot_name)


## True when a card was cleared now: the step waits a frame, so the next shot copies a frame drawn without it.
func _clear_cards() -> bool:
	var cleared := false
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is IncidentCard and (n as CanvasItem).is_visible_in_tree():
			(n as IncidentCard).button_pressed.emit("later")
			(n as IncidentCard).close()
			cleared = true
		elif n is EventCard and (n as CanvasItem).is_visible_in_tree():
			(n as EventCard).close()
			cleared = true
		elif n is MicroeventCard and not (n as MicroeventCard).folded:
			(n as MicroeventCard).set_folded(true)
			cleared = true
		stack.append_array(n.get_children())
	return cleared


func _go(step: String) -> void:
	print("[SmokeForja] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])])
	_step = step
	_t = 0.0


func _sim() -> Sim:
	return Game.sim


func _storage(item: String) -> int:
	return Inventory.count(_sim().state.buildings[BLD]["inventory"], item)


func _process(delta: float) -> void:
	if _clear_cards():
		return
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeForja] TIMEOUT in step %s" % _step)
		_shot("h2_timeout")
		get_tree().quit(1)
		return
	var hugo: Dictionary = _sim().state.characters[HUGO]
	match _step:
		"start":
			if _t > 0.3:
				app.world().select(HUGO)
				app.world().pick_building_id(BLD)
				_go("map")
		"map":
			if _t > 0.5:
				_shot("h2_mapa")
				app.world().command_enter(BLD)
				_go("entering")
		"entering":
			if str(hugo["location"]) == BLD and app.interior_building == BLD and _t > 0.6:
				app.interior().open_station_menu("furnace", Vector2(300, 200))
				app.interior().station_menu().choose_mode("normal")
				app.interior().station_menu().choose_recipe("forge_ingot")
				_go("ingots")
		"ingots":
			if _storage("iron_ingot") >= 2:
				var at: Vector2 = app.interior().station_screen("anvil")
				app.interior().open_station_menu("anvil", at)
				app.interior().station_menu().choose_mode("careful")
				_go("menu")
		"menu":
			if _t > 0.4:
				_shot("h2_menu")
				app.interior().station_menu().choose_recipe("forge_sword")
				_go("sword")
		"sword":
			var job := Production.job_view(_sim(), BLD, "anvil")
			if job.is_empty():
				return
			if float(job.get("progress", 0.0)) >= 0.3:
				_shot("h2_interior")
				_go("touch")
		"touch":
			var job := Production.job_view(_sim(), BLD, "anvil")
			if not _touched and bool(job.get("window_open", false)):
				app.interior().click_station("anvil")
				_touched = true
			if _storage("sword") > 0:
				app.interior().show_storage(true)
				_go("storage")
		"storage":
			if _t > 0.6:
				_shot("h2_almacen")
				var inv: Dictionary = _sim().state.buildings[BLD]["inventory"]
				for s: Dictionary in inv["stacks"]:
					if str(s["item"]) == "sword":
						app.interior().storage_panel().move_to_actor("sword", int(s["quality"]), 1)
						break
				_go("carry")
		"carry":
			if Inventory.count(hugo["inventory"], "sword") > 0 and _t > 0.3:
				app.interior().show_storage(false)
				app.hud().toggle_character_panel()
				_go("panel")
		"panel":
			if _t > 0.6:
				_shot("h2_personaje")
				app.hud().toggle_character_panel()
				Game.set_paused(true)
				app.interior().click_station("furnace")
				app.interior().open_station_menu("furnace", Vector2(300, 200))
				app.interior().station_menu().choose_mode("careful")
				app.interior().station_menu().choose_recipe("forge_ingot")
				for st: Dictionary in hugo["inventory"]["stacks"]:
					if str(st["item"]) == "sword":
						app.interior().storage_panel().move_to_building("sword", int(st["quality"]), 1)
						break
				_go("queue")
		"queue":
			if _t > 0.5:
				_shot("h2_cola")
				_go("done")
				get_tree().quit()
