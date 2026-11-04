extends Node
## Scripted capture of the map of the region (--smoke-script=region; docs/gdd/09b_region.md; run it through `grimoire
## heavy` with the engine's --always-on-top). town_e_start: the pause menu with its «Mapa de la región» button
## (region_menu), the map opened from it (region_mapa), the card of the capital pinned (region_ficha_capital), the card
## of home (region_ficha_villa), and with the regional war in force the routes it cuts in red and the card of the
## port (region_guerra). Then Esc closes the card and the map, and R in the HUD opens it again (region_tecla). Every
## shot checks that the «Viajar» button of the card is shown off and that no card leaves the screen. Quits when done
## (1 if a check fails), or after `timeout` seconds.

const SCENARIO: String = "town_e_start"
const DAY: int = 1440

var app: Node = null
var timeout: float = 90.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _bad: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeRegion] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeRegion] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _screen() -> RegionScreen:
	return app.call("region_screen") as RegionScreen


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


## The card shown: on screen, and its travel button off.
func _check(shot: String) -> void:
	var sc := _screen()
	var card := sc.get_node("SettlementCard") as PageCard
	if card.visible:
		var r := card.get_global_rect()
		var view := sc.get_viewport_rect()
		var on := view.grow(0.5).encloses(r)
		var b := card.find_child("Button_travel", true, false) as Button
		var off := b == null or b.disabled   # a commoner (town_e_start) cannot travel; home's card has no travel button
		if not on or not off:
			_bad += 1
		print("[SmokeRegion] %s: ficha %s en %s (dentro=%s), «%s» deshabilitado=%s" % [shot, sc.selected, r, on,
			b.text if b != null else "?", off])
	print("[SmokeRegion] %s: casa=%s, cortadas=%s, horas=%s" % [shot, sc.home, sc.cut, sc.hours])
	app.save_shot(shot)


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeRegion] TIMEOUT in step %s" % _step)
		app.save_shot("region_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3:
				var r := NewGame.from_scenario(SCENARIO)
				app.hud().close_panels()
				Game.start(r["state"], Game.sim.catalog)
				Game.set_paused(true)
				app.call("open_pause")
				_go("menu")
		"menu":
			if _t > 0.6:
				app.save_shot("region_menu")
				(app.call("pause_menu") as PauseMenu).get_node("%RegionButton").emit_signal("pressed")
				_go("map")
		"map":
			if _t > 0.6:
				if not _screen().visible:
					print("[SmokeRegion] the map did not open from the pause menu")
					_bad += 1
				_check("region_mapa")
				_screen().show_card("capital", true)
				_go("capital")
		"capital":
			if _t > 0.5:
				_check("region_ficha_capital")
				_screen().show_card("villa", true)
				_go("villa")
		"villa":
			if _t > 0.5:
				_check("region_ficha_villa")
				var now := int(Game.sim.state.clock["minute"])
				var why := WorldEvents.start(Game.sim, "war")
				print("[SmokeRegion] guerra: %s (minuto %d)" % [why if why != "" else "activa", now])
				_screen().close()
				_screen().open()
				_screen().show_card("port", true)
				_go("war")
		"war":
			if _t > 0.5:
				if _screen().cut.size() < 3:
					print("[SmokeRegion] the war should cut r2, r3 and r4: %s" % [_screen().cut])
					_bad += 1
				_check("region_guerra")
				_key(KEY_ESCAPE)   # the card
				_go("esc1")
		"esc1":
			if _t > 0.3:
				_key(KEY_ESCAPE)   # the map
				_go("esc2")
		"esc2":
			if _t > 0.4:
				if _screen().visible:
					print("[SmokeRegion] Esc did not close the map")
					_bad += 1
				(app.call("pause_menu") as PauseMenu).close()
				Game.set_paused(true)
				_key(KEY_R)
				_go("key")
		"key":
			if _t > 0.6:
				if not _screen().visible:
					print("[SmokeRegion] R in the HUD did not open the map")
					_bad += 1
				_check("region_tecla")
				print("[SmokeRegion] done: %d fallos" % _bad)
				_go("done")
				get_tree().quit(1 if _bad > 0 else 0)
