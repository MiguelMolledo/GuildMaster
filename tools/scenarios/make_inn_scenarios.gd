extends SceneTree
## The scenarios of the Taberna-Posada (docs/gdd/04f_vida_y_fiestas.md §4.27):
##  - innkeeper_start: a new game of the smith (artisan_blacksmith, Normal, fixed cast, seed 1) whose family has just
##    bought the town's Taberna-Posada (buy_building, O-V7 a: a second business), with 200 gold left to run it, the
##    house's first stock (ale, cider, bread, soup, stew, wheat, wood, meat) and the hero inside at dusk-1 h of day 0.
##    The tutorial chapter «Tu taberna», the bot innkeeper and its target.
##  - inn_night: innkeeper_start played by the bot innkeeper until the fullest minute of the nights of days 4-6 (from day 4 at 19:00;
##    staff, upgrades, a full room): the
##    captures --smoke-script=posada (the tavern full at night, Clientela, the menu, a room, the turn summary).
##   /opt/homebrew/bin/godot --headless --path . -s tools/scenarios/make_inn_scenarios.gd
## Same code + same data = same files.

const START_OUT: String = "res://data/scenarios/innkeeper_start.json"
const NIGHT_OUT: String = "res://data/scenarios/inn_night.json"
const STOCK: Array = [["ale", 16], ["cider", 8], ["bread", 6], ["garlic_soup", 8], ["stew", 8], ["wheat", 12],
	["wood", 3], ["meat", 4]]


func _init() -> void:
	var cat := Catalog.load_from()
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	if not r["ok"]:
		print("make_inn_scenarios: %s" % r["error"])
		quit(1)
		return
	var st: WorldState = r["state"]
	var sim := Sim.new(st, cat)
	var fam := SimQuery.player_family(st)
	var hero := str(st.families[fam]["head"])
	var tavern := ""
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if str(st.buildings[b]["type"]) == Inn.TYPE:
			tavern = b
	if tavern == "":
		print("make_inn_scenarios: the map has no Taberna-Posada for sale")
		quit(1)
		return
	st.families[fam]["gold"] = int(st.families[fam]["gold"]) + Inn.sale_price(sim, tavern) + 200
	var bought := Orders.apply(sim, {"type": "buy_building", "actor": hero, "building": tavern})
	if not bought["ok"]:
		print("make_inn_scenarios: buy_building: %s" % bought["reason"])
		quit(1)
		return
	for s: Array in STOCK:
		Inventory.add(st.buildings[tavern]["inventory"], cat, str(s[0]), Inventory.NORMAL, int(s[1]))
	# the hero inside the tavern, an hour before it opens on day 0
	var w := Inn.turn_window(sim, int(st.clock["minute"]))
	st.clock["minute"] = int(w[0]) - 60
	st.characters[hero]["location"] = tavern
	st.characters[hero]["position"] = (st.buildings[tavern]["door"] as Array).duplicate()
	st.characters[hero]["path"] = []
	st.meta = {"title": "Tu taberna", "start": "artisan_blacksmith", "origin": "tools/scenarios/make_inn_scenarios.gd",
		"description": "Partida nueva del herrero (Normal, reparto fijo, semilla 1) con la Taberna-Posada del pueblo recién comprada (segundo negocio), 200 de oro para llevarla, sus primeras existencias y el protagonista dentro una hora antes de abrir: el capítulo «Tu taberna», el bot innkeeper y su diana."}
	var clean := WorldState.from_dict(st.to_dict())
	var e := SaveFile.save(clean, START_OUT)
	print("make_inn_scenarios: %s (%s)" % [START_OUT, error_string(e)])
	if e != OK:
		quit(1)
		return
	# inn_night: the bot plays it until day 6 at 22:30
	var sim2 := Sim.new(WorldState.from_dict(clean.to_dict()), cat)
	var bot := BotInnkeeper.new()
	var from := 4 * Clock.MINUTES_PER_DAY + 19 * 60
	var until := 6 * Clock.MINUTES_PER_DAY + 23 * 60 + 30
	while int(sim2.state.clock["minute"]) < from:
		sim2.step(bot.orders(sim2))
	var best := {}
	var most := -1
	while int(sim2.state.clock["minute"]) < until:  # the fullest minute of the night (the capture of a full tavern)
		sim2.step(bot.orders(sim2))
		var n := 0  # full and with people waiting: guests + 2 × the ones waiting for their order
		for g: Dictionary in Inn.guests(sim2, tavern):
			n += 3 if str(g.get("state", "")) == "waiting" else 1
		if n > most and Inn.is_open(sim2, tavern):
			most = n
			best = sim2.state.to_dict().duplicate(true)
	var st2 := WorldState.from_dict(best)
	sim2 = Sim.new(st2, cat)
	st2.characters[hero]["location"] = tavern
	st2.characters[hero]["station"] = ""
	st2.characters[hero]["path"] = []
	st2.characters[hero]["order_queue"] = []
	for z: Variant in st2.buildings[tavern]["zones"]:
		if str(st2.buildings[tavern]["zones"][z].get("occupant", "")) == hero:
			st2.buildings[tavern]["zones"][z]["occupant"] = ""
	st2.meta = {"title": "La taberna llena", "start": "artisan_blacksmith", "origin": "tools/scenarios/make_inn_scenarios.gd",
		"description": "innkeeper_start jugado por el bot innkeeper hasta el minuto más lleno de las noches de los días 4 a 6: empleados, mejoras, la carta y el salón lleno. Las capturas --smoke-script=posada."}
	e = SaveFile.save(WorldState.from_dict(st2.to_dict()), NIGHT_OUT)
	print("make_inn_scenarios: %s (%s): %d huéspedes dentro, fama %.2f, oro %d" % [NIGHT_OUT, error_string(e),
		Inn.guests(sim2, tavern).size(), Inn.fame(sim2, tavern), int(st2.families[fam]["gold"])])
	quit(0 if e == OK else 1)
