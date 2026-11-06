extends Node
## Scripted capture of the festivals (04f 4.25; --smoke-script=fiestas, through `grimoire heavy` with the engine's
## --always-on-top). A real new game (artisan_blacksmith, fixed cast). For each festival of data/festivals.json (the
## eight fixed ones, then the variable ones): the clock on its day at a good hour, the festival put in force, the
## plaza with its decoration (fiesta_<id>_vista) and its card (fiesta_<id>_carta). Then a rich wedding of the rival
## family: the crier's card and the board with the bride's dress and the groom's sword (fiesta_boda_tablon). Orders only
## through the UI paths. Last, the player's wedding offer without the gold of the banquet (the button off, with its
## reason: fiesta_boda_sin_oro), and the clock's festival button and the card it opens again (fiesta_boton_reloj,
## fiesta_carta_reabierta), the corro with the preacher (fiesta_corro), the Christmas gifts (fiesta_regalos) and
## Sant Jordi in Bellcaire with its games on the city's page (fiesta_ciudad_sant_jordi) and its feast's contracts on
## its board (fiesta_ciudad_encargos), the peddler's stall in the plaza (vida_buhonero), the merchant who trades
## (vida_mercader) and a guard in the town's livery (vida_guardia). Quits when done, or after `timeout` seconds.

const DAY: int = 1440
const PLAZA: Vector2i = Vector2i(19, 19)

var app: Node = null
var timeout: float = 240.0
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _who: String = ""
var _list: Array = []
var _i: int = -1
var _inst: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	print("[SmokeFiestas] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeFiestas] %s -> %s (t=%.1f s, minute=%d)" % [_step, step, _total, int(Game.sim.state.clock["minute"])])
	_step = step
	_t = 0.0


func _start_game() -> bool:
	var cat: Catalog = Game.sim.catalog if Game.sim != null else Catalog.load_from()
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 3)
	if not bool(r.get("ok", false)):
		print("[SmokeFiestas] new game failed: %s" % r.get("error", ""))
		get_tree().quit(1)
		return false
	var st: WorldState = r["state"]
	app.hud().close_panels()
	Game.start(st, cat)
	Game.set_paused(true)
	_who = SimQuery.family_actor(st, SimQuery.player_family(st))
	app.world().select(_who)
	var fixed: Array = []
	var variable: Array = []
	for f: Dictionary in Festivals.calendar(Game.sim):
		fixed.append(str(f["id"]))
	for id: String in Festivals._sorted_keys(Festivals.defs(Game.sim)):
		if str(Festivals.def_of(Game.sim, id).get("kind", "")) == "variable":
			variable.append(id)
	_list = fixed + variable
	return true


## Puts festival `id` in force on its day (fixed: its day of year in year 1; variable: day 10) at a good hour.
func _force(id: String) -> void:
	var sim: Sim = Game.sim
	var d := Festivals.def_of(sim, id)
	var day := 8 + int(d.get("day_of_year", 2)) if str(d.get("kind", "")) == "fixed" else 10
	var hour := int(d.get("start_hour", 0)) + 2
	if int(d.get("start_hour", 0)) == 0:
		hour = 11
	sim.state.festivals = Festivals.new_block()
	sim.state.festivals["planned_day"] = day
	sim.state.clock["minute"] = day * DAY + hour * 60
	var board: Array = sim.state.contracts["board"]
	sim.state.contracts["board"] = board.filter(func(c: Dictionary) -> bool: return not bool(c.get("race", false)))
	_inst = Festivals._schedule(sim, id, day, "smoke", {"hosts": [], "couple": []})
	if id in ["mayday_corpus", "all_saints_matanza"]:
		var inst := Festivals.find(sim, _inst)
		inst["organized"]["bulls"] = "smoke"
	sim.events = []
	Festivals.step(sim)
	app.world().call("_refresh_festivals")
	app.world().camera().center_on(Iso.tile_to_world(PLAZA))
	print("[SmokeFiestas] %s en vigor (%s): %s" % [id, _inst, app.world().festival_layer.shown])


## Centres the camera on the first festival prop `prop` placed (the pens at the outskirts); false if none.
func _aim_at(prop: String) -> bool:
	for n: Node in (app.world().call("objects") as Node2D).get_children():
		if n is Node2D and str(n.get_meta("festival_prop", "")) == prop:
			app.world().camera().center_on((n as Node2D).position)
			print("[SmokeFiestas] afueras: %s en %s (casillas %s)" % [prop, (n as Node2D).position, n.get_meta("tiles", [])])
			return true
	print("[SmokeFiestas] afueras: no hay %s" % prop)
	return false


func _card(type: String) -> void:
	var inst := Festivals.find(Game.sim, _inst)
	var card: Node = app.get_node("CardsLayer/EventCard")
	card.call("close")
	card.call("show_festival", Game.sim, {"type": type, "id": _inst, "def": str(inst.get("def", "")),
		"day": int(inst.get("day", 0)), "start": int(inst.get("start", 0)), "end": int(inst.get("end", 0))})


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeFiestas] TIMEOUT in step %s" % _step)
		app.save_shot("fiesta_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.3 and _start_game():
				_go("next")
		"next":
			_i += 1
			if _i >= _list.size():
				_go("wedding")
				return
			_force(str(_list[_i]))
			_go("view")
		"view":
			if _t > 0.6:
				app.save_shot("fiesta_%s_vista" % _list[_i])
				if _list[_i] in ["harvest_fair", "cattle_fair"] and _aim_at("pen"):
					_go("outskirts")
				else:
					_card("festival_started")
					_go("card")
		"outskirts":
			if _t > 0.6:
				app.save_shot("fiesta_%s_afueras" % _list[_i])
				app.world().camera().center_on(Iso.tile_to_world(PLAZA))
				_card("festival_started")
				_go("card")
		"card":
			if _t > 0.5:
				app.save_shot("fiesta_%s_carta" % _list[_i])
				app.get_node("CardsLayer/EventCard").call("close")
				_go("next")
		"wedding":
			var sim: Sim = Game.sim
			sim.state.festivals = Festivals.new_block()
			sim.state.clock["minute"] = 11 * DAY + 9 * 60
			sim.state.festivals["planned_day"] = 11
			var rival := ""
			for f: String in Festivals._sorted_keys(sim.state.families):
				if str(sim.state.families[f].get("ai_profile", "")) != "":
					rival = f
					break
			sim.events = [{"type": "wedding", "family": rival, "character": Kin.head(sim.state, rival), "spouse": "",
				"from_family": ""}]
			Festivals.step(sim)
			sim.state.clock["minute"] = 11 * DAY + 13 * 60
			sim.events = []
			Festivals.step(sim)
			for i: Dictionary in sim.state.festivals["upcoming"]:
				if str(i["def"]) == "noble_wedding":
					_inst = str(i["id"])
			_card("festival_eve")
			_go("wedding_card")
		"wedding_card":
			if _t > 0.5:
				app.save_shot("fiesta_boda_pregon")
				app.get_node("CardsLayer/EventCard").call("close")
				var ch: Dictionary = Game.sim.state.characters[_who]
				ch["location"] = ""
				ch["path"] = []
				ch["position"] = Contracts.board_service(Game.sim).duplicate()
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(16, 21)))
				app.hud().board_panel().open_for(Game.sim, _who)
				_go("board")
		"board":
			if _t > 0.6:
				var open: Array = Game.sim.state.contracts.get("board", [])
				print("[SmokeFiestas] tablón: %s" % [open.map(func(c: Dictionary) -> String:
					return "%s %s q%d %s" % [c["id"], c["item"], int(c["min_quality"]), c.get("festival_def", "")])])
				app.save_shot("fiesta_boda_tablon")
				app.hud().board_panel().close()
				_go("court")
		"court":  # the marquis: the player is the mayor and a citizen; offers from both houses
			var sim: Sim = Game.sim
			var fam := SimQuery.player_family(sim.state)
			Offices.take(sim, "mayor", 0, _who)
			sim.state.families[fam]["title"] = "citizen"
			sim.state.festivals = Festivals.new_block()
			sim.state.festivals["planned_day"] = 20
			sim.state.clock["minute"] = 19 * DAY + 13 * 60
			_inst = Festivals._schedule(sim, "marquis_visit", 21, "smoke")
			sim.events = []
			Festivals.step(sim)
			var rival := ""
			for f: String in Festivals._sorted_keys(sim.state.families):
				if str(sim.state.families[f].get("ai_profile", "")) != "":
					rival = f
					break
			var rh := Kin.head(sim.state, rival)
			Inventory.add(sim.state.characters[rh]["inventory"], sim.catalog, "decorative_sword", 2, 1)
			Inventory.add(sim.state.characters[_who]["inventory"], sim.catalog, "sword", 1, 1)
			Inventory.add(sim.state.characters[_who]["inventory"], sim.catalog, "fine_clothes", 2, 1)
			Orders.apply(sim, {"type": "festival_offer_gift", "actor": rh, "festival": _inst})
			Orders.apply(sim, {"type": "festival_offer_gift", "actor": _who, "festival": _inst, "item": "sword"})
			sim.state.families[rival]["gold"] = 500  # the rival pays the banquet: the player sees it and may bid
			sim.state.families[fam]["gold"] = 300
			Orders.apply(sim, {"type": "festival_sponsor", "actor": rh, "festival": _inst, "part": "banquet"})
			_card("festival_eve")
			_go("court_card")
		"court_card":
			if _t > 0.5:
				app.save_shot("fiesta_marques_carta")
				var card: Node = app.get_node("CardsLayer/EventCard")
				card.call("show_page", FestivalPage.audience_menu(Game.sim, {"instance": _inst}))
				_go("audience_menu")
		"audience_menu":
			if _t > 0.5:
				app.save_shot("fiesta_audiencia")
				var card: Node = app.get_node("CardsLayer/EventCard")
				card.call("close")
				card.call("show_festival", Game.sim, {"type": "festival_gift_offers", "festival": _inst,
					"def": "marquis_visit", "mayor": _who, "offers": 2})
				_go("gift_card")
		"gift_card":
			if _t > 0.5:
				app.save_shot("fiesta_regalo_villa")
				var card: Node = app.get_node("CardsLayer/EventCard")
				card.call("close")
				card.call("show_festival", Game.sim, {"type": "festival_contest", "festival": "", "def": "harvest_fair",
					"family": SimQuery.player_family(Game.sim.state), "item": "decorative_sword", "quality": 2,
					"reputation": 6, "fame": 10, "entries": 3})
				_go("contest_card")
		"contest_card":
			if _t > 0.5:
				app.save_shot("fiesta_concurso")
				var fam := SimQuery.player_family(Game.sim.state)
				Game.sim.state.families[fam]["gold"] = 50  # the banquet costs 80: the button is off and says why
				var card: Node = app.get_node("CardsLayer/EventCard")
				card.call("close")
				card.call("show_festival", Game.sim, {"type": "festival_wedding_offer", "family": fam,
					"couple": [_who, _who]})
				_go("wedding_offer")
		"wedding_offer":
			if _t > 0.5:
				app.save_shot("fiesta_boda_sin_oro")
				app.get_node("CardsLayer/EventCard").call("close")
				Game.sim.state.families[SimQuery.player_family(Game.sim.state)]["gold"] = 120
				_force("tournament")  # the clock's button: the feast in force, its card again with its games
				var hud: Node = app.hud()
				hud.set("_last_minute", -1)
				hud.call("_refresh")
				_go("clock_button")
		"clock_button":
			if _t > 0.6:
				app.save_shot("fiesta_boton_reloj")
				(app.hud().get_node("%FestivalButton") as Button).pressed.emit()
				_go("reopened")
		"reopened":
			if _t > 0.6:
				app.save_shot("fiesta_carta_reabierta")
				var card: Node = app.get_node("CardsLayer/EventCard")
				card.call("close")
				_force("preacher")  # the corro in the plaza, frowned upon with the preacher in town
				print("[SmokeFiestas] corro: mal visto=%s (%s)" % [FestivalCorro.frowned(Game.sim), Festivals.active(Game.sim).map(func(i: Dictionary) -> String: return str(i["def"]))])
				card.call("show_page", FestivalPage.corro_menu(Game.sim, {"instance": _inst}))
				_go("corro")
		"corro":
			if _t > 0.6:
				app.save_shot("fiesta_corro")
				var card: Node = app.get_node("CardsLayer/EventCard")
				card.call("close")
				_force("christmas")  # Christmas gifts: the houses on a second card
				Inventory.add(Game.sim.state.characters[_who]["inventory"], Game.sim.catalog, "candlestick", 2, 1)
				card.call("show_page", FestivalPage.gifts_menu(Game.sim, {"instance": _inst}))
				_go("gifts")
		"gifts":
			if _t > 0.6:
				app.save_shot("fiesta_regalos")
				app.get_node("CardsLayer/EventCard").call("close")
				var sim: Sim = Game.sim  # Sant Jordi in Bellcaire: the traveller is there on its day
				sim.state.festivals = Festivals.new_block()
				sim.state.clock["minute"] = 1 * DAY + 10 * 60
				Region.ensure(sim)
				var now := int(sim.state.clock["minute"])
				(sim.state.region["trips"] as Dictionary)[_who] = {"id": "trv_smoke", "actor": _who,
					"family": SimQuery.player_family(sim.state), "from": Region.home(sim), "to": "capital", "path": [], "leg": 0,
					"at": "capital", "leg_start": now, "leg_end": now, "escort": false, "state": "city", "since": now}
				sim.state.families[SimQuery.player_family(sim.state)]["gold"] = 120
				app.call("open_city", "capital")
				_go("city")
		"city":
			if _t > 0.8:
				app.save_shot("fiesta_ciudad_sant_jordi")
				FestivalCity.post_contracts(Game.sim, "capital", 1)  # its feast's contracts on its board
				var cs: Node = app.call("city_screen")
				cs.set("tab", "board")
				cs.set("_sig", "")
				_go("city_board")
		"city_board":
			if _t > 0.8:
				app.save_shot("fiesta_ciudad_encargos")
				var cs: Node = app.call("city_screen")
				cs.call("hide")
				var sim: Sim = Game.sim  # back home, a peddler in the plaza with his wares
				(sim.state.region["trips"] as Dictionary).erase(_who)
				Region.put_on_map(sim, _who, [19, 21])
				Life.service_family(sim.state, Life.FAMILY_VISITORS, "family.visitors", {"primary": "#6a5a4a", "secondary": "#c8b8a0"})
				var stock := Peddler.stock_for(sim.state, Visitors.cfg(sim)["kinds"]["peddler"], "smoke|0")
				if not stock.any(func(w: Dictionary) -> bool: return str(w["item"]) == "loaded_dice"):
					stock.append({"item": "loaded_dice", "price": 30, "qty": 1})  # the capture shows the dice
				var pd := Life.add_person(sim, Life.FAMILY_VISITORS, "Buhonero", false, 44, {}, {}, [20, 21],
					{"visitor": {"kind": "peddler", "city": "port", "gate": "", "purse": 30, "plan": [], "stop": -1, "until": -1,
					"leaving": false, "arrived": 0, "wares": stock}})
				Life.put_on(sim, pd, [20, 21])
				app.world().camera().center_on(Iso.tile_to_world(Vector2i(19, 21)))
				app.hud().call("open_npc", pd)
				_go("peddler")
		"peddler":
			if _t > 0.8:
				app.save_shot("vida_buhonero")
				var sim: Sim = Game.sim  # a merchant of Portvell: he buys its dear goods, sells its cheap ones
				Inventory.add(sim.state.characters[_who]["inventory"], sim.catalog, "iron_ingot", Inventory.NORMAL, 3)
				var md := {"kind": "merchant", "city": "port", "gate": "", "purse": 90, "plan": [], "stop": -1, "until": -1,
					"leaving": false, "arrived": 0}
				var mid := Life.add_person(sim, Life.FAMILY_VISITORS, "Mercader", false, 38, {}, {}, [18, 21], {"visitor": md})
				VisitingMerchant.setup(sim, sim.state.characters[mid]["visitor"], "port", "smoke|merchant")
				Life.put_on(sim, mid, [18, 21])
				app.hud().call("open_npc", mid)
				_go("merchant")
		"merchant":
			if _t > 0.8:
				app.save_shot("vida_mercader")
				app.hud().close_panels()
				Watch.step(Game.sim)  # the watch is made by the life's step (the smoke moves the clock by hand)
				var guard := ""  # a guard of the watch at his post: the livery's placeholder
				for c: String in Game.sim.state.characters:
					var ch: Dictionary = Game.sim.state.characters[c]
					if str(ch.get("family", "")) == Life.FAMILY_WATCH and str(ch.get("location", "x")) == "":
						guard = c
						break
				if guard == "" and not Watch.guards(Game.sim.state).is_empty():  # off duty: one to the plaza for the capture
					guard = str(Watch.guards(Game.sim.state)[0])
					Life.put_on(Game.sim, guard, [21, 21])
				print("[SmokeFiestas] guardia: %s (%d en la guardia)" % [guard, Watch.guards(Game.sim.state).size()])
				if guard != "":
					var gt: Array = Life.tile_of(Game.sim.state, guard)
					app.world().camera().center_on(Iso.tile_to_world(Vector2i(int(gt[0]), int(gt[1]))))
				_go("guard")
		"guard":
			if _t > 0.8:
				app.save_shot("vida_guardia")
				_go("done")
				get_tree().quit()
