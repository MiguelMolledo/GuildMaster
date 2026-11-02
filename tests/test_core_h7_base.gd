extends "res://tests/test_case.gd"
## H7 base (docs/contratos/h7_ciudad.md): the town tables, the v8 save and its migration from v7 (house, trade, routine
## memory and emotions of each townsperson, active microevents), the round trip with town state, the trades of a new
## game and the town scenarios (plaza_dusk, town_microevents).

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim(id: String, s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, s)["state"], cat)


func _townsfolk(st: WorldState) -> Array:
	var out: Array = []
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		if TownLife.is_townsperson(st, id):
			out.append(id)
	return out


func test_town_tables_load() -> void:
	eq(cat.validate(), PackedStringArray(), "no data problems")
	for k: String in ["routine", "activities", "emotions", "actions", "counter", "microevents", "population"]:
		check(cat.town.has(k), "town.json has %s" % k)
	eq(cat.town["emotions"].keys().size(), 4, "the 4 emotions of the MVP (4.11.5)")
	eq(float(cat.town["emotions"]["angry"]["buy_mult"]), 1.25, "angry: +25 % buying")
	eq(cat.microevents().keys().size(), 3, "the 3 microevents of 4.20")
	eq(str(cat.microevents()["night_thief"]["default_choice"]), "let", "thief: default let him (4.20)")
	eq(float(cat.town["microevents"]["base_chance"]), 0.35, "35 % per day (4.20)")
	eq([cat.difficulty_levels("easy")["microevent_chance"], cat.difficulty_levels("hard")["microevent_chance"]], [0.7, 1.3],
		"difficulty lever (4.23)")
	eq((cat.social_phrases["activities"]["chat"] as Array).size(), 10, "10 phrases per activity")
	var map: Dictionary = cat.maps()["town_e"]
	eq((map["workplaces"] as Array).size(), 16, "16 trades on the map")
	check((map["social_points"] as Array).size() >= 6, "benches, chat and dice points")


func test_v7_save_migrates_to_v8() -> void:
	var r := SaveFile.load_file("res://tests/data/saves/v7_family_routines.json")
	check(r["ok"], "the v7 save loads (%s)" % r.get("error", ""))
	var st: WorldState = r["state"]
	eq(WorldState.VERSION, 8, "v8")
	eq(st.version, 8, "migrated")
	for id: String in st.characters:
		eq(str(st.characters[id]["occupation"]), "", "%s: no trade yet" % id)
		eq(st.characters[id]["town"], {}, "%s: empty town memory" % id)
	eq(st.microevents, {"active": [], "pending": [], "cooldowns": {}, "last_day": {}}, "no microevents")
	eq(st.town, {"counters": {}}, "no counters")
	TownLife.assign_occupations(st, cat)
	var folk := _townsfolk(st)
	check(folk.size() >= 15, "15-20 townsfolk (%d)" % folk.size())
	var wps: Array = cat.maps()["town_e"]["workplaces"]
	for i: int in folk.size():
		if TownLife.is_adult(st, cat, folk[i]):
			check(str(st.characters[folk[i]]["occupation"]) != "", "%s gets a trade" % folk[i])
	# the same hand-out as a new game: the first townsperson gets the first workplace
	eq(str(st.characters[folk[0]]["occupation"]), str(wps[0]["id"]), "map order")
	var sim := Sim.new(st, cat)
	sim.run_minutes(60)
	check(true, "a migrated game runs")


func test_round_trip_with_h7_state() -> void:
	var sim := _sim("town_microevents")
	var st := sim.state
	var folk := _townsfolk(st)
	var npc: String = folk[0]
	st.characters[npc]["town"] = {"state": "social", "activity": "chat", "spot": "chat_well", "slot": 1, "until": 999,
		"day": 0, "leave_at": 330}
	st.emotions[npc] = [{"state": "angry", "source": FAM, "start": 300, "duration": 3600, "intensity0": 100}]
	st.microevents["active"] = [{"id": "mev_0001", "def": "sick_employee", "family": FAM, "building": FORGE,
		"target": folk[1], "actor": "", "started": 300, "expires": 420, "choices": ["doctor", "day_off", "dock"],
		"default": "day_off", "context": {}}]
	st.microevents["cooldowns"] = {"sick_employee|%s" % FORGE: 8}
	st.microevents["last_day"] = {FAM: 0}
	st.town["counters"] = {FORGE: {"next_at": 480}}
	var back: WorldState = SaveFile.from_text(JSON.stringify(st.to_dict()))["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "same content")
	eq(str(back.characters[npc]["home"]), str(st.characters[npc]["home"]), "house survives")
	eq(str(back.characters[npc]["occupation"]), str(st.characters[npc]["occupation"]), "trade survives")
	eq(str(back.characters[npc]["town"]["activity"]), "chat", "routine memory survives")
	eq(typeof(back.characters[npc]["town"]["until"]), TYPE_INT, "town numbers come back as int")
	eq(str(back.emotions[npc][0]["state"]), "angry", "emotion survives")
	eq(int(back.emotions[npc][0]["duration"]), 3600, "emotion duration survives")
	eq(str(back.microevents["active"][0]["def"]), "sick_employee", "active microevent survives")
	eq(int(back.microevents["cooldowns"]["sick_employee|%s" % FORGE]), 8, "cooldown survives")
	eq(int(back.town["counters"][FORGE]["next_at"]), 480, "counter survives")


func test_new_game_gives_trades_in_map_order() -> void:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 3)
	check(r["ok"], "new game")
	var st: WorldState = r["state"]
	var folk := _townsfolk(st)
	eq(folk.size(), 16, "16 townsfolk")
	var wps: Array = cat.maps()["town_e"]["workplaces"]
	for i: int in folk.size():
		eq(str(st.characters[folk[i]]["occupation"]), str(wps[i]["id"]), "%s: workplace %d" % [folk[i], i])
	for stall: String in ["resources", "food", "materials", "armory"]:
		check(TownLife.stall_keeper(st, cat, stall) != "", "the %s stall has a keeper" % stall)
	eq(str(st.characters[HERO]["occupation"]), "", "the player has no town trade")
	eq(st.version, 8, "a new game is v8")


func test_town_scenarios() -> void:
	var dusk := _sim("plaza_dusk")
	eq(dusk.now()["phase"], "day", "18:40 is still day")
	var out := 0
	for id: String in _townsfolk(dusk.state):
		if str(dusk.state.characters[id]["location"]) != str(dusk.state.characters[id]["home"]):
			out += 1
	eq(out, 16, "everybody at their trades, out of their houses")
	var mev := _sim("town_microevents")
	check(Upgrades.flag(mev, FORGE, "counter_sales"), "the forge has the sales counter")
	eq(Staff.employees_of(mev.state, FORGE).size(), 2, "two employees")
	check(Inventory.count(mev.state.buildings[FORGE]["inventory"], "sword") >= 6, "swords to sell")
	eq(mev.state.loans, {}, "no loan")
	eq(mev.state.version, 8, "v8 scenario")
	var start := _sim("town_e_start")
	eq(start.state.version, 8, "town_e_start regenerated as v8")
	for id: String in _townsfolk(start.state):
		check(str(start.state.characters[id]["occupation"]) != "", "%s has a trade in town_e_start" % id)
