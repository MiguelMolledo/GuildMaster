extends Node
## Scripted capture of H6 · plots and construction (--smoke-script=h6; through `grimoire heavy` with --always-on-top).
## A new game of the smith in town_e; the family is made Citizen with gold (the title limit lets a second building) so
## the captures show the whole loop: the building mode with the plots by zone (h6_modo), the card of the ruin
## (h6_carta_ruina), the order through the card's button and the works with their scaffold and bar (h6_obra), the
## second business finished (h6_terminado: the tailor's on the ruin, picked) and the card of another family's business
## with its price (h6_comprar), and the workshop's 3×4 lot of Vilarrasa (h6_solar_taller: with the forge and the tailor's
## the Citizen's limit is full, so the workshops are off with the reason and the tavern, which does not count, is on). Everything through the UI's own calls; the works' time is run with the sim's steps
## (published like the game does). Quits when done, or after `timeout` seconds with a shot of whatever is on screen.

var app: Node = null
var timeout: float = 90.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _shop: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeH6] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeH6] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])
		if Game.sim != null else -1])
	_step = step
	_t = 0.0


func _hero() -> String:
	return str(Game.sim.state.families[SimQuery.player_family(Game.sim.state)]["head"])


func _look_at(plot_id: String, lift: float = -20.0) -> void:
	var p := Plots.get_plot(Game.sim, plot_id)
	var o: Array = p["origin"]
	var s: Array = p["size"]
	app.world().camera().center_on(Iso.tilef_to_world(Vector2(float(o[0]) + float(s[0]) / 2.0,
		float(o[1]) + float(s[1]) / 2.0)) + Vector2(0, lift))


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeH6] TIMEOUT in step %s" % _step)
		app.save_shot("h6_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3:
				var cat: Catalog = Game.call("_catalog")
				var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
				Game.start(r["state"], cat)
				Game.set_paused(true)
				var fam := SimQuery.player_family(Game.sim.state)
				Game.sim.state.families[fam]["title"] = "citizen"
				Game.sim.state.families[fam]["gold"] = 900
				app.world().select(_hero())
				_go("mode")
		"mode":
			if _t > 0.4:
				app.hud().set_build_mode(true)
				_look_at("plot_01", 40.0)
				_go("shot_mode")
		"shot_mode":
			if _t > 0.7:
				app.save_shot("h6_modo")
				app.open_plot("plot_01")
				_go("shot_card")
		"shot_card":
			if _t > 0.7:
				app.save_shot("h6_carta_ruina")
				var card := app.get_node("CardsLayer/PlotCard") as PlotCard
				var btn := card.find_child("Button_build_tailor_shop", true, false) as Button  # «build:tailor_shop» (":" -> "_")
				print("[SmokeH6] restore button: %s (disabled=%s)" % [btn != null, btn.disabled if btn != null else true])
				if btn == null or btn.disabled:
					get_tree().quit(1)
					return
				btn.pressed.emit()   # as a click on it: the card gives the order and closes
				_go("works")
		"works":
			if _t > 0.2:
				_run(1)   # the step that applies the card's order (Game.give keeps it until then)
				_shop = str(Plots.get_plot(Game.sim, "plot_01")["building"])
				print("[SmokeH6] on plot_01: %s (%s)" % [_shop, Game.sim.state.buildings.get(_shop, {}).get("state", "")])
				# a third of the works, so the bar shows progress
				_run(roundi(float(Game.sim.state.buildings[_shop]["construction"]["end"] - int(Game.sim.state.clock["minute"])) / 3.0))
				app.hud().set_build_mode(false)
				_look_at("plot_01")
				_go("shot_works")
		"shot_works":
			if _t > 0.8:
				app.world().refresh_upgrades()
				app.save_shot("h6_obra")
				_run(int(Game.sim.state.buildings[_shop]["construction"]["end"]) - int(Game.sim.state.clock["minute"]) + 2)
				_go("finished")
		"finished":
			if _t > 0.8:
				print("[SmokeH6] %s: %s, businesses=%d" % [_shop, Game.sim.state.buildings[_shop]["state"],
					Titles.businesses(Game.sim, SimQuery.player_family(Game.sim.state))])
				app.world().pick_building_id(_shop)
				app.hud().set_building(_shop)
				_go("shot_finished")
		"shot_finished":
			if _t > 0.6:
				app.world().refresh_upgrades()
				app.save_shot("h6_terminado")
				app.hud().set_build_mode(true)
				_look_at("plot_16")
				app.open_plot("plot_16")
				_go("shot_buy")
		"shot_buy":
			if _t > 0.7:
				app.save_shot("h6_comprar")
				(app.get_node("CardsLayer/PlotCard") as PlotCard).close()
				_look_at("plot_21", 40.0)
				app.open_plot("plot_21")
				_go("shot_lot")
		"shot_lot":
			if _t > 0.7:
				app.save_shot("h6_solar_taller")   # the 3×4 lot: the workshops off (the title's limit), the tavern on
				_go("done")
				get_tree().quit(0)


## Runs `minutes` sim steps and hands their events to the views, as the game does.
func _run(minutes: int) -> void:
	var events := get_node("/root/Events")
	for i: int in maxi(0, minutes):
		var pending: Array = Game.get("_pending")
		Game.set("_pending", [])
		events.publish(Game.sim.step(pending))
