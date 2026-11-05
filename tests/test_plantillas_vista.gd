extends "res://tests/test_case.gd"
## Plantillas, vista: each town's watch has its town's name (data/maps "watch"); in a corrillo at most 2 show their
## bubble or phrase at a time, the second higher, and everybody gets a turn (WorldView._take_turns).

var cat := Catalog.load_from()


func _game(city: String, seed_value: int = 1) -> WorldState:
	var ch := {}
	if city != "villa":
		ch["city"] = city
	return NewGame.from_start(cat, "artisan_blacksmith", "normal", ch, seed_value)["state"]


func test_each_town_has_its_watch() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var want := {"villa": "Guardia de la villa", "capital": "Guardia de Bellcaire", "port": "Guardia del puerto"}
	for city: String in want:
		var sim := Sim.new(_game(city), cat)
		for i: int in 3:
			sim.step()
		var guards := Watch.guards(sim.state)
		check(not guards.is_empty(), "%s: a watch" % city)
		if guards.is_empty():
			continue
		var line := LifeQuery.role_line(sim, str(guards[0]))
		check(line.begins_with(str(want[city]) + " · "), "%s: «%s»" % [city, line])
	TranslationServer.set_locale(before)


func test_a_corrillo_shows_two_at_a_time_and_everybody_gets_a_turn() -> void:
	var sim := Sim.new(_game("port"), cat)
	var g := {}
	var big := ""
	for i: int in 1440:
		sim.step()
		if int(sim.state.clock["minute"]) % 5 != 0:
			continue
		g = Rumors.corrillos(sim)
		for p: String in g:
			if (g[p] as Array).size() >= 4:
				big = p
		if big != "":
			break
	check(big != "", "a corrillo of 4 or more in Portvell's first day")
	if big == "":
		return
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(sim.state, cat, sim)
	var seen := {}
	for k: int in 12:
		v.sync(0.0)
		var shown := 0
		var raised := 0
		for id: String in v.turns:
			if (g[big] as Array).has(id):
				match str(v.turns[id]):
					"shown":
						shown += 1
						seen[id] = true
					"raised":
						raised += 1
						seen[id] = true
		check(shown + raised <= 2, "at most 2 at a time (%d, %d)" % [shown, raised])
		sim.state.clock["minute"] = int(sim.state.clock["minute"]) + WorldView.TURN_MINUTES / 2
	var talking := 0
	for id: String in v.turns:
		if (g[big] as Array).has(id):
			talking += 1
	check(seen.size() >= mini(talking, 3), "the turns go round (%d of %d)" % [seen.size(), talking])
	v.free()


func test_phrases_that_would_overlap_take_turns() -> void:
	var sim := Sim.new(_game("port"), cat)
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(sim.state, cat, sim)
	var ids: Array = []
	for id: String in sim.state.characters:
		if Population.townsfolk(sim.state).has(id):
			ids.append(id)
		if ids.size() == 4:
			break
	for i: int in ids.size():  # four townsfolk side by side, each saying something
		sim.state.characters[ids[i]]["position"] = [24 + i, 10]
		sim.state.characters[ids[i]]["location"] = ""
	v.sync(0.0)
	for id: String in ids:
		(v._views[id] as CharacterView).set_phrase("frase de %s" % id)
	v._take_phrase_turns(int(sim.state.clock["minute"]))
	var shown := 0
	for id: String in ids:
		if (v._views[id] as CharacterView).phrase() != "":
			shown += 1
	eq(shown, 2, "of four phrases that would overlap, two show (%s)" % v.phrase_turns)
	v.free()

