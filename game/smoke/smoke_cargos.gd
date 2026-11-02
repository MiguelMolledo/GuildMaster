extends Node
## Scripted capture of H10 (--smoke-script=cargos; run it through `grimoire heavy` with the engine's --always-on-top).
## office_campaign: the offices panel (chart) for Hugo, a Citizen in autumn (h10_organigrama); a medium campaign is
## chosen and «Run» pressed for market inspector (h10_presentarse). office_election_eve: winter, 23:30, Hugo and
## Bernat run; the panel shows the campaign and a voter's sheet its campaign actions (h10_campana); the game runs to
## midnight: the vote's card with the count (h10_resultado). office_inspector: Hugo's powers; +10 % on swords is
## pressed and the panel shows the cooldown and the price in force (h10_poderes). The F1 help (h10_ayuda). Quits when done, or after `timeout` seconds with a shot.

const HERO: String = "chr_0001"
const RIVAL: String = "chr_0002"

var app: Node = null
var timeout: float = 120.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeCargos] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeCargos] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _load(id: String) -> bool:
	var r := NewGame.from_scenario(id)
	if not bool(r.get("ok", false)):
		print("[SmokeCargos] scenario %s failed: %s" % [id, r.get("error", "")])
		get_tree().quit(1)
		return false
	app.hud().close_panels()
	Game.start(r["state"])
	Game.set_paused(true)
	app.world().select(HERO)
	return true


func _row_button(office: String) -> Button:
	var chart := app.hud().offices_panel().get_node("%Chart") as Node
	var line := chart.get_node_or_null("Office_" + office)
	return null if line == null else line.get_node_or_null("Run") as Button


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeCargos] TIMEOUT in step %s" % _step)
		app.save_shot("h10_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3 and _load("office_campaign"):
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(20, 25)) + Vector2(-60, -110))
				app.hud().open_offices(HERO)
				_go("shot_chart")
		"shot_chart":
			if _t > 0.8:
				print("[SmokeCargos] organigrama: %s" % [Offices.chart(Game.sim)])
				app.save_shot("h10_organigrama")
				var lv := app.hud().offices_panel().get_node("%LevelOption") as OptionButton
				lv.select(1)
				lv.item_selected.emit(1)
				_go("run")
		"run":
			if _t > 0.4:
				var b := _row_button("market_inspector")
				if b != null:
					b.pressed.emit()
				Game.set_paused(false)  # the order waits for the next step
				_go("applied")
		"applied":
			if _t > 0.3:
				Game.set_paused(true)
				_go("shot_run")
		"shot_run":
			if _t > 0.8:
				print("[SmokeCargos] candidatura: %s" % [Elections.campaign_of(Game.sim, HERO)])
				app.save_shot("h10_presentarse")
				if _load("office_election_eve"):
					var voters := Elections.voters(Game.sim, [HERO, RIVAL])
					var v := str(voters[voters.size() - 1])
					app.world().camera().center_on(Iso.tile_to_world(Vector2i(20, 22)))
					app.hud().open_offices(HERO)
					app.hud().open_npc(v)
				_go("shot_campaign")
		"shot_campaign":
			if _t > 0.8:
				print("[SmokeCargos] campaña: %s" % [Elections.campaign_of(Game.sim, HERO)])
				app.save_shot("h10_campana")
				app.hud().close_panels()
				Game.set_speed(4)
				Game.set_paused(false)
				_go("wait_vote")
		"wait_vote":
			if app.hud().office_card().visible:
				Game.set_paused(true)
				_go("shot_result")
			elif _t > 30.0:
				print("[SmokeCargos] no vote card: %s" % [Elections.last_result(Game.sim.state, "market_inspector")])
				_go("shot_result")
		"shot_result":
			if _t > 0.8:
				print("[SmokeCargos] resultado: %s" % [Elections.last_result(Game.sim.state, "market_inspector").get(
					"result", {})])
				app.save_shot("h10_resultado")
				if _load("office_inspector"):
					app.hud().open_offices(HERO)
				_go("power")
		"power":
			if _t > 0.6:
				var box := app.hud().offices_panel().get_node("%Powers") as Node
				var b := box.get_node_or_null("Power_regulate_price/Use_regulate_price_up") as Button
				if b != null:
					b.pressed.emit()
				Game.set_paused(false)
				_go("applied_power")
		"applied_power":
			if _t > 0.3:
				Game.set_paused(true)
				_go("shot_powers")
		"shot_powers":
			if _t > 0.8:
				print("[SmokeCargos] regulación: espadas %+d%%, venta %d" % [Offices.regulation(Game.sim, "sword"),
					Market.price(Game.sim, "sword", 0, "sell")])
				app.save_shot("h10_poderes")
				app.hud().close_panels()
				app.hud().toggle_help()
				_go("shot_help")
		"shot_help":
			if _t > 0.8:
				app.save_shot("h10_ayuda")
				_go("done")
				get_tree().quit(0)
