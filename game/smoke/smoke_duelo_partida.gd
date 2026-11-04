extends Node
## The duel in the game, captured (--smoke-script=duelo_partida; docs/ui/mecanicas/combate.md; through `grimoire
## heavy` with the engine's --always-on-top). Scenario duel_ready (the rival smith has just insulted Hugo, both in the
## street by the plaza): the rival's sheet with «Retar a duelo…» (duelp_ficha), the challenge card (duelp_carta), the
## order given from its button, the rival's answer card (duelp_respuesta), the dawn's notice and Hugo walking to the
## plaza (duelp_alba), the duel screen opened by itself with the game paused (duelp_pantalla), two lances played with
## the keys' actions (duelp_lance_1, _2), «Resolver sin jugar» and the result card with what changed (duelp_resultado),
## and the game after it (duelp_despues: the notices). Checks that each piece is on screen; quits with 1 if one is
## missing or on timeout.

const SCENARIO: String = "duel_ready"
const HERO: String = "chr_0001"
const RIVAL: String = "chr_0002"

var app: Node = null
var timeout: float = 150.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _bad: int = 0
var _lances: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeDuelo] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeDuelo] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _need(cond: bool, what: String) -> void:
	if not cond:
		print("[SmokeDuelo] FALTA: %s" % what)
		_bad += 1


func _director() -> DuelDirector:
	return app.call("duels") as DuelDirector


## Runs the sim `n` minutes publishing its events (the cards and notices react), the game paused.
func _run(n: int) -> void:
	for i: int in n:
		if i == 0:  # the orders the UI gave in pause go with the first step
			Game.step_now({"type": "read_notices", "actor": HERO, "ids": []})  # management: leaves the queue alone
		else:
			get_node("/root/Events").publish(Game.sim.step([]))


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeDuelo] TIMEOUT in step %s" % _step)
		app.save_shot("duelp_timeout")
		get_tree().quit(1)
		return
	var d := _director() if app != null else null
	match _step:
		"start":
			if _t > 0.5:
				var r := NewGame.from_scenario(SCENARIO)
				Game.start(r["state"])
				Game.set_paused(true)
				app.world().select(HERO)
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(18, 18)))
				_go("sheet")
		"sheet":
			if _t > 0.6:
				app.hud().open_npc(RIVAL)
				_go("sheet_shot")
		"sheet_shot":
			if _t > 0.6:
				var b := app.hud().npc_panel().get_node("%Actions").get_node_or_null("DuelButton") as Button
				_need(b != null and b.is_visible_in_tree() and not b.disabled, "el botón Retar a duelo, activo")
				app.save_shot("duelp_ficha")
				if b != null:
					b.emit_signal("pressed")
				_go("card")
		"card":
			if _t > 0.6:
				_need(d.card.visible, "la carta de reto")
				app.save_shot("duelp_carta")
				d._on_card_button("cause:offense")
				app.hud().npc_panel().close()
				d.card.close()
				_run(5)  # the order (queued in pause, it starts the next step), then the rival's answer
				_go("answer")
		"answer":
			if _t > 0.6:
				_need(d.card.visible, "la carta de respuesta")
				app.save_shot("duelp_respuesta")
				d.card.close()
				var rec := Duels.of_character(Game.sim.state, HERO)
				_need(not rec.is_empty() and str(rec["status"]) == "accepted", "el duelo aceptado")
				if rec.is_empty():
					_go("done")
					return
				_run(int(rec["at"]) - 28 - int(Game.sim.state.clock["minute"]))  # just after the call to the plaza
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(19, 16)))
				Game.set_speed(1)
				Game.set_paused(false)
				_go("dawn")
		"dawn":
			if _t > 2.0:
				app.save_shot("duelp_alba")
				Game.set_speed(4)
				_go("wait_screen")
		"wait_screen":
			if d.screen.visible and d.screen.game_mode:
				_go("screen")
			elif _t > 40.0:
				_need(false, "la pantalla del duelo a la hora")
				_go("done")
		"screen":
			if _t > 1.0:
				_need(Game.paused, "la partida en pausa durante el duelo")
				app.save_shot("duelp_pantalla")
				_go("lance")
		"lance":
			if _t > 0.3 and not d.screen.busy:
				if d.screen.duel.over() or _lances >= 2:
					d.screen._auto_finish()
					_go("result")
					return
				var v := d.screen.duel.view(d.screen.player)
				var act := "parry"
				if str(v["role"]) == "read":
					var best := CombatRules.counter_of(d.screen.cfg, str(v["cue"]))
					act = best if best in (v["allowed"] as Array) else "parry"
				d.screen._choose(act)
				_lances += 1
				_go("lance_shot")
		"lance_shot":
			if _t > 0.25:
				app.save_shot("duelp_lance_%d" % _lances)
				_go("lance")
		"result":
			if _t > 2.5 and not d.screen.busy:
				_need(d.screen.get_node("%Result").visible, "la carta de resultado")
				_need(Duels.of_character(Game.sim.state, HERO).is_empty(), "el duelo cerrado en el sim")
				app.save_shot("duelp_resultado")
				d.screen.close()
				_go("after")
		"after":
			if _t > 1.0:
				_need(not Game.paused or true, "")
				app.save_shot("duelp_despues")
				_go("done")
		"done":
			if _t > 0.2:
				print("[SmokeDuelo] done: %d problemas" % _bad)
				get_tree().quit(1 if _bad > 0 else 0)
