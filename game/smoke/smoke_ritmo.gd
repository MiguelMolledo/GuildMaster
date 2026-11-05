extends Node
## Scripted capture of «ritmo y desbloqueos» (docs/gdd/03b_diversion_y_ritmo.md §3b.4-§3b.5; --smoke-script=ritmo
## --scenario=pacing_day3, through `grimoire heavy` and --always-on-top): the goals zone on the map (rt_metas); an
## unlock that comes — the first one still closed (the forge's Upgrades or the next), opened with the same order a
## tutorial chapter gives — with its card
## «Nuevo: …» (rt_carta); the forge in management mode with the «Nuevo» mark on Mejoras (rt_marca); the «Saltar
## hasta…» menu (rt_saltar_menu), skipping to dawn at ×8 (rt_saltando) and stopped (rt_saltar_parado). Orders only
## through Game.give and the HUD's own paths. Quits when done, or after `timeout` seconds with a shot.

const BLD := "bld_0001"

var app: Node = null
var timeout: float = 90.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0


func _ready() -> void:
	print("[SmokeRitmo] start")


func _go(step: String) -> void:
	print("[SmokeRitmo] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])])
	_step = step
	_t = 0.0


func _ph() -> PacingHud:
	return app.hud().pacing()


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeRitmo] TIMEOUT in step %s" % _step)
		app.save_shot("rt_timeout")
		get_tree().quit(1)
		return
	var sim: Sim = Game.sim
	var fam := SimQuery.player_family(sim.state)
	var head := str(sim.state.families[fam]["head"])
	match _step:
		"start":
			if _t > 0.8:
				Game.set_paused(true)
				print("[SmokeRitmo] metas: %s · desbloqueos: %s" % [_ph().shown_goals(), Unlocks.list(sim, fam).map(
					func(e: Dictionary) -> String: return str(e["id"]))])
				app.save_shot("rt_metas")
				Game.set_paused(false)
				var next := ""   # the first unlock with a card the game has not opened yet (the forge's upgrades, if still closed)
				for id: String in ["upgrades", "fair", "rumors", "debt", "courtship"]:
					if next == "" and not Unlocks.is_open(sim.state, fam, id):
						next = id
				print("[SmokeRitmo] abre %s" % next)
				Game.give({"type": "unlock_seen", "actor": head, "unlock": next, "what": "now"})
				_go("card")
		"card":
			if app.unlock_card().visible and _t > 0.6:
				Game.set_paused(true)
				app.save_shot("rt_carta")
				app.unlock_card().close()
				Game.set_paused(false)
				app.open_interior(BLD, true)
				_go("mark")
		"mark":
			if app.interior_building == BLD and _t > 1.0:
				print("[SmokeRitmo] marcas: %s" % [_ph().marked()])
				app.save_shot("rt_marca")
				app.interior().request_exit()
				_go("menu")
		"menu":
			if _t > 0.8:
				_ph().open_skip_menu()
				_go("menu_shot")
		"menu_shot":
			if _t > 0.4:
				app.save_shot("rt_saltar_menu")
				_ph().skip_menu.hide()
				_ph().skip("dawn")
				_go("skipping")
		"skipping":
			if _t > 1.2:
				app.save_shot("rt_saltando")
				_go("wait_stop")
		"wait_stop":
			if str(Game.skip_kind) == "":
				_go("stopped")
		"stopped":
			if _t > 0.5:   # the toast and the button show the stop
				app.save_shot("rt_saltar_parado")
				_go("done")
				get_tree().quit()
