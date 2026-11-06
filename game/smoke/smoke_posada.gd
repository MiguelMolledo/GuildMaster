extends Node
## Scripted capture of the Taberna-Posada (--smoke-script=posada; through `grimoire heavy` with --always-on-top).
## Scenario inn_night (innkeeper_start played by the bot until the fullest minute of a night): the tavern on the map
## (posada_mapa), its interior full at night (posada_noche), the panel's Clientela (posada_clientela), the menu
## (posada_carta), the rooms (posada_habitacion), the gaming table (posada_mesa: the Mesa tab, the table built and
## licensed if the bot had not), the traveller's offer (posada_forastero: its card) and its game on the games' screen
## (posada_partida), the card of the turn summary (posada_resumen) and another family's table from its door (posada_mesa_ajena: the
## tavern given to the rival smith, the HUD's «Jugar en la mesa» and its card). Everything through the UI's own calls. Quits when done, or after `timeout` seconds with a shot of whatever is on screen.

var app: Node = null
var timeout: float = 90.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _tavern: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokePosada] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokePosada] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])])
	_step = step
	_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokePosada] TIMEOUT in step %s" % _step)
		app.save_shot("posada_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3:
				var r := NewGame.from_scenario("inn_night")
				if not bool(r.get("ok", false)):
					print("[SmokePosada] scenario failed: %s" % r.get("error", ""))
					get_tree().quit(1)
					return
				Game.start(r["state"])
				Game.set_paused(true)
				for b: String in Game.sim.state.buildings:
					if Inn.is_inn(Game.sim, b):
						_tavern = b
				_go("map")
		"map":
			if _t > 0.3:
				var b: Dictionary = Game.sim.state.buildings[_tavern]
				var o: Array = b["origin"]
				app.world().camera().center_on(Iso.tilef_to_world(Vector2(float(o[0]) + 1.5, float(o[1]) + 1.5)) + Vector2(0, -30))
				app.world().pick_building_id(_tavern)
				_go("shot_map")
		"shot_map":
			if _t > 0.6:
				app.save_shot("posada_mapa")
				var hero := str(Game.sim.state.families[SimQuery.player_family(Game.sim.state)]["head"])
				app.world().select(hero)
				app.open_interior(_tavern, false)
				_go("inside")
		"inside":
			if app.interior_building == _tavern and _t > 1.0:
				var layer: InnLayer = app.interior().inn_layer()
				print("[SmokePosada] guests drawn: %d, inside: %d" % [layer.guest_count() if layer != null else -1,
					Inn.guests(Game.sim, _tavern).size()])
				_go("shot_night")
		"shot_night":
			if _t > 0.5:
				app.save_shot("posada_noche")
				app.interior().show_inn(true)
				app.interior().inn_panel().show_tab("clientele")
				_go("shot_clientele")
		"shot_clientele":
			if _t > 0.6:
				app.save_shot("posada_clientela")
				app.interior().inn_panel().show_tab("menu")
				_go("shot_menu")
		"shot_menu":
			if _t > 0.6:
				app.save_shot("posada_carta")
				app.interior().inn_panel().show_tab("rooms")
				_go("shot_rooms")
		"shot_rooms":
			if _t > 0.6:
				app.save_shot("posada_habitacion")
				var sim: Sim = Game.sim
				var ups: Array = sim.state.buildings[_tavern]["upgrades"]
				for u: String in ["tavern_inn_ambience_1", "tavern_inn_ambience_2", "tavern_inn_ambience_3"]:
					if not ups.has(u):
						ups.append(u)
				if not Inn.licensed(sim, _tavern):
					Inn.state_of(sim, _tavern)["license_until"] = Clock.day(int(sim.state.clock["minute"])) + 8
				InnGames.make_offer(sim, _tavern, Inn.state_of(sim, _tavern))
				app.interior().inn_panel().show_tab("games")
				_go("shot_table")
		"shot_table":
			if _t > 0.6:
				app.save_shot("posada_mesa")
				app.interior().show_inn(false)
				var oc := app.get_node("%InnOfferCard") as InnOfferCard
				oc.show_for(Game.sim, _tavern)
				_go("shot_offer")
		"shot_offer":
			if _t > 0.8:
				app.save_shot("posada_forastero")
				(app.get_node("%InnOfferCard") as InnOfferCard).close()
				var fam := SimQuery.player_family(Game.sim.state)
				var req := InnGames.offer_request(Game.sim, _tavern, InnGames.player_for(Game.sim, _tavern, fam))
				print("[SmokePosada] partida del forastero: %s" % [req])
				app.open_game(req)
				_go("shot_game")
		"shot_game":
			if _t > 1.2:
				app.save_shot("posada_partida")
				var layer := app.get_node_or_null("GamesLayer")
				if layer != null:
					for c: Node in layer.get_children():
						if c is GameScreen:
							(c as GameScreen).close()
				var card := app.get_node("%InnTurnCard") as InnTurnCard
				card.show_for(Game.sim, _tavern)
				_go("shot_summary")
		"shot_summary":
			if _t > 0.8:
				app.save_shot("posada_resumen")
				(app.get_node("%InnTurnCard") as InnTurnCard).close()
				# another family's table: the tavern given to the rival smith, the hero at its door
				var st: WorldState = Game.sim.state
				st.buildings[_tavern]["owner"] = "fam_0002"
				var hero := str(st.families[SimQuery.player_family(st)]["head"])
				st.characters[hero]["location"] = ""
				st.characters[hero]["position"] = (st.buildings[_tavern]["door"] as Array).duplicate()
				app.close_interior()
				_go("foreign")
		"foreign":
			if app.interior_building == "" and _t > 1.0:
				app.world().pick_building_id(_tavern)
				_go("shot_foreign")
		"shot_foreign":
			if _t > 0.6:
				var hero2 := str(Game.sim.state.families[SimQuery.player_family(Game.sim.state)]["head"])
				print("[SmokePosada] mesa ajena: %s" % InnGames.visitor_blocked(Game.sim, _tavern, hero2))
				(app.get_node("%InnVisitCard") as InnVisitCard).show_for(Game.sim, _tavern, hero2)
				_go("shot_foreign_card")
		"shot_foreign_card":
			if _t > 0.8:
				app.save_shot("posada_mesa_ajena")
				_go("done")
				get_tree().quit()
