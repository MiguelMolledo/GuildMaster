extends Node
## Scripted capture of H11 (--smoke-script=tribunal; run it through `grimoire heavy` with the engine's --always-on-top).
## accused_player: the «you are accused» card (h11_acusacion) and the trial panel in preparation (h11_preparacion).
## trial_hearing: the game runs into the hearing (the HUD pauses and opens the panel: h11_vista); the witnesses against
## are questioned and the defense rests: the verdict card (h11_veredicto). rival_accused: the rival's sheet with
## «Accuse…» (h11_acusar). accused_player again with the maximum sentence: the banished head (h11_destierro).
## Quits when done, or after `timeout` seconds with a shot.

const HERO: String = "chr_0001"
const RIVAL: String = "chr_0002"

var app: Node = null
var timeout: float = 150.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeTribunal] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeTribunal] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _load(id: String) -> bool:
	var r := NewGame.from_scenario(id)
	if not bool(r.get("ok", false)):
		print("[SmokeTribunal] scenario %s failed: %s" % [id, r.get("error", "")])
		get_tree().quit(1)
		return false
	app.hud().close_panels()
	Game.start(r["state"])
	Game.set_paused(true)
	app.world().select(HERO)
	return true


func _tid() -> String:
	return str(Tribunal.of_family(Game.sim, "fam_0001", true).get("id", ""))


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeTribunal] TIMEOUT in step %s" % _step)
		app.save_shot("h11_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3 and _load("accused_player"):
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(20, 22)))
				app.hud().trial_card().show_accusation(Game.sim, _tid())
				_go("shot_card")
		"shot_card":
			if _t > 0.8:
				app.save_shot("h11_acusacion")
				app.hud().trial_card().close()
				app.hud().open_trial(_tid())
				_go("shot_prep")
		"shot_prep":
			if _t > 0.8:
				print("[SmokeTribunal] preparación: %s" % [Tribunal.scale(Game.sim, Tribunal.trial(Game.sim.state, _tid()))])
				app.save_shot("h11_preparacion")
				if _load("trial_hearing"):
					Game.set_paused(false)
				_go("wait_hearing")
		"wait_hearing":
			if app.hud().trial_panel().visible and Game.paused:
				_go("shot_hearing")
			elif _t > 20.0:
				print("[SmokeTribunal] no hearing: %s" % [Tribunal.trial(Game.sim.state, _tid()).get("status", "")])
				_go("shot_hearing")
		"shot_hearing":
			if _t > 0.8:
				app.save_shot("h11_vista")
				var box := app.hud().trial_panel().get_node("%Witnesses") as Node
				for row: Node in box.get_children():
					var b := row.get_node_or_null("Cross") as Button
					if b != null and not b.disabled:
						b.pressed.emit()
				Game.set_paused(false)
				_go("crossed")
		"crossed":
			if _t > 0.3:
				Game.set_paused(true)
				_go("shot_crossed")
		"shot_crossed":
			if _t > 0.8:
				app.save_shot("h11_vista_interrogada")
				(app.hud().trial_panel().get_node("%RestButton") as Button).pressed.emit()
				Game.set_paused(false)
				_go("wait_verdict")
		"wait_verdict":
			if app.hud().trial_card().visible:
				Game.set_paused(true)
				_go("shot_verdict")
			elif _t > 10.0:
				_go("shot_verdict")
		"shot_verdict":
			if _t > 0.8:
				print("[SmokeTribunal] veredicto: %s" % [Game.sim.state.trials[Game.sim.state.trials.size() - 1].get("sentence")])
				app.save_shot("h11_veredicto")
				if _load("rival_accused"):
					app.world().camera().center_on(Iso.tile_to_world(Vector2i(20, 24)))
					app.hud().open_npc(RIVAL)
				_go("shot_accuse")
		"shot_accuse":
			if _t > 0.8:
				app.save_shot("h11_acusar")
				if _load("accused_player"):
					var t := Tribunal.trial(Game.sim.state, _tid())
					t["severity"] = "maximum"
					Tribunal.rule(Game.sim, t)  # the harness rules a maximum sentence to show the banishment
					app.hud().trial_card().show_verdict(Game.sim, {"trial": str(t["id"])})
					app.hud().toggle_character_panel()
				_go("shot_banished")
		"shot_banished":
			if _t > 0.8:
				app.save_shot("h11_destierro")
				_go("done")
				get_tree().quit(0)
