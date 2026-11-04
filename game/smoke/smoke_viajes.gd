extends Node
## Scripted capture of travel and trade (--smoke-script=viajes; docs/gdd/09b_region.md; run it through `grimoire
## heavy` with the engine's --always-on-top). two_employees with the family made patrician, 600 gold and swords: the
## region map with the card of the hamlet and «Viajar» on (viajes_ficha), the trip under way with the emblem on the
## road (viajes_camino), the city page that opens on arrival: market (viajes_mercado), contracts (viajes_encargos) and
## treaties (viajes_tratados); a sale there; then the caravans panel with a cart bought and the form filled
## (viajes_caravanas) and the caravan on the region map (viajes_caravana_mapa). Each shot checks what it should show.
## Quits when done (1 if a check fails), or after `timeout` seconds.

const SCENARIO: String = "two_employees"

var app: Node = null
var timeout: float = 150.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _bad: int = 0
var _hero: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeViajes] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeViajes] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_bad += 1
	print("[SmokeViajes] %s: %s" % [what, "ok" if ok else "FALLA"])


func _region() -> RegionScreen:
	return app.call("region_screen") as RegionScreen


func _city() -> CityScreen:
	return app.call("city_screen") as CityScreen


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeViajes] TIMEOUT in step %s" % _step)
		app.save_shot("viajes_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3:
				var r := NewGame.from_scenario(SCENARIO)
				app.hud().close_panels()
				Game.start(r["state"], Game.sim.catalog)
				var st := Game.sim.state
				var fam := SimQuery.player_family(st)
				st.families[fam]["title"] = "patrician"
				Money.change(Game.sim, fam, 600, Money.EVENTS, "smoke")
				_hero = str(st.families[fam]["head"])
				Inventory.add(st.characters[_hero]["inventory"], Game.sim.catalog, "sword", 0, 3)
				for b: String in st.buildings:
					if str(st.buildings[b]["owner"]) == fam and str(st.buildings[b]["type"]) == "forge":
						Inventory.add(st.buildings[b]["inventory"], Game.sim.catalog, "sword", 0, 4)
				Game.set_paused(true)
				app.call("open_region")
				_go("card")
		"card":
			if _t > 0.6:
				if not _region().visible:   # a stray key (Esc) to the always-on-top window may close it: open again
					app.call("open_region")
				_region().show_card("hamlet", true)
				_go("card_shot")
		"card_shot":
			if _t > 0.4:
				var b := _region().get_node("SettlementCard").find_child("Button_travel", true, false) as Button
				_check(b != null and not b.disabled, "«Viajar» enabled for a patrician")
				app.save_shot("viajes_ficha")
				_region()._on_card_button("travel")   # as the card's button does: the order, then the card closes
				(_region().get_node("SettlementCard") as PageCard).close()
				Game.set_speed(4)
				_go("road")
		"road":
			if _t > 3.0:
				_check(Region.is_away(Game.sim.state, _hero), "the hero is on the road")
				app.save_shot("viajes_camino")
				_go("arrive")
		"arrive":
			if _city().visible:
				Game.set_paused(true)
				_check(_city().city == "hamlet", "the city page of the hamlet opens on arrival")
				_go("market")
			elif _t > 40.0:
				_check(false, "arrived and the page opened")
				_go("market")
		"market":
			if _t > 0.8:
				app.save_shot("viajes_mercado")
				_city().tab = "board"
				_city()._sig = ""
				_city()._rebuild()
				_go("board")
		"board":
			if _t > 0.5:
				app.save_shot("viajes_encargos")
				_city().tab = "treaties"
				_city()._sig = ""
				_city()._rebuild()
				_go("treaties")
		"treaties":
			if _t > 0.5:
				app.save_shot("viajes_tratados")
				var g := Money.gold(Game.sim.state, SimQuery.player_family(Game.sim.state))
				Game.sim.step([{"type": "city_sell", "actor": _hero, "item": "sword", "quality": 0, "qty": 1}])
				_check(Money.gold(Game.sim.state, SimQuery.player_family(Game.sim.state)) > g, "a sword sold there")
				_city().close()
				Game.sim.step([{"type": "buy_cart", "actor": _home_actor()}])
				var cv := app.call("caravan_screen") as CaravanScreen
				cv.actor = str(Game.sim.state.families[SimQuery.player_family(Game.sim.state)]["head"])
				cv.open()
				_go("caravans")
		"caravans":
			if _t > 0.6:
				var cv := app.call("caravan_screen") as CaravanScreen
				for l: Dictionary in cv._cargo:
					if str(l["item"]) == "sword":
						(l["qty"] as SpinBox).value = 2
				cv._update_send()
				app.save_shot("viajes_caravanas")
				var o := cv.order()
				o["actor"] = _home_actor()
				var r := Orders.apply(Game.sim, o)
				_check(bool(r["ok"]), "the caravan leaves (%s)" % r["reason"])
				cv.close()
				app.call("open_region")
				Game.set_paused(false)
				_go("caravan_map")
		"caravan_map":
			if _t > 2.0:
				app.save_shot("viajes_caravana_mapa")
				print("[SmokeViajes] done: %d fallos" % _bad)
				_go("done")
				get_tree().quit(1 if _bad > 0 else 0)


## Who gives the caravan's order at home: the hero is away; a caravan is management, any member will do.
func _home_actor() -> String:
	var st := Game.sim.state
	for c: String in Kin.group(st, SimQuery.player_family(st)):
		if not Region.is_away(st, c):
			return c
	return _hero
