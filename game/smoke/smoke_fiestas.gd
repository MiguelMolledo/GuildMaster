extends Node
## Scripted capture of the festivals (04f 4.25; --smoke-script=fiestas, through `grimoire heavy` with the engine's
## --always-on-top). A real new game (artisan_blacksmith, fixed cast). For each festival of data/festivals.json (the
## eight fixed ones, then the variable ones): the clock on its day at a good hour, the festival put in force, the
## plaza with its decoration (fiesta_<id>_vista) and its card (fiesta_<id>_carta). Then a rich wedding of the rival
## family: the crier's card and the board with the bride's dress and the groom's sword (fiesta_boda_tablon). Orders only
## through the UI paths. Quits when done, or after `timeout` seconds.

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
				_go("done")
				get_tree().quit()
