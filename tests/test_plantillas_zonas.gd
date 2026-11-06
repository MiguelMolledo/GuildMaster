extends "res://tests/test_case.gd"
## Plantillas · H13, the map of Bellcaire (docs/gdd/10_hitos.md fila H13, 09b_region.md): 80×80 with its six zones
## (data/maps "zones" and "zone_rows", tools/city/organic.py from tools/city/ciudades.json): the market square, the
## craftsmen's quarter with the workshops, the patricians' quarter with the cathedral, the harbour and exchange on the
## river, the outskirts with the fields and the wood; their names on the map at the farthest zoom (ZoneLayer); the
## population by its houses (O-R9). Only Bellcaire has zones: Vilarrasa's map does not change.

const WORKSHOPS: Array[String] = ["forge", "carpentry", "masonry", "tailor_shop"]

var cat := Catalog.load_from()


func _cap() -> Dictionary:
	return cat.maps()["region_capital"]


func _zone_of(m: Dictionary, t: Array) -> String:
	var ch := str(m["zone_rows"][int(t[1])])[int(t[0])]
	for z: Dictionary in m["zones"]:
		if str(z["char"]) == ch:
			return str(z["kind"])
	return ""


func test_bellcaire_is_80_by_80_with_its_six_zones() -> void:
	var m := _cap()
	eq(m["size"], [80, 80], "80×80")
	var kinds: Array = (m["zones"] as Array).map(func(z: Dictionary) -> String: return str(z["kind"]))
	kinds.sort()
	eq(kinds, ["artisans", "centre", "forest", "nobles", "outskirts", "port"], "the six zones")
	var rows: Array = m["zone_rows"]
	eq(rows.size(), 80, "a zone row per map row")
	var chars := {}
	for z: Dictionary in m["zones"]:
		chars[str(z["char"])] = int(z["tiles"])
		check(int(z["tiles"]) >= 60, "%s: %d tiles" % [z["id"], z["tiles"]])
		eq(_zone_of(m, z["label"]), str(z["kind"]), "%s: its name over its own ground" % z["id"])
	var count := {}
	for r: String in rows:
		eq(r.length(), 80, "80 tiles a row")
		for i: int in r.length():
			count[r[i]] = int(count.get(r[i], 0)) + 1
	for ch: String in count:
		check(chars.has(ch), "every tile in a zone (%s)" % ch)
		eq(int(count[ch]), int(chars.get(ch, -1)), "zone %s: its tiles counted" % ch)


func test_each_zone_has_what_makes_it() -> void:
	var m := _cap()
	var b: Dictionary = m["buildings"]
	var in_artisans := 0
	var extra := {}  # H13: the city's own businesses (region.json ai_families extra: the drapers at the Exchange)
	for ex: Dictionary in NewGame.city(cat, "capital").get("ai_families", {}).get("extra", []):
		extra[str(ex["building"]["site"])] = true
	for id: String in b:
		if extra.has(id):
			eq(_zone_of(m, b[id]["door"]), "port", "%s at the Exchange" % id)
			continue
		if str(b[id]["type"]) in WORKSHOPS:
			eq(_zone_of(m, b[id]["door"]), "artisans", "%s in the craftsmen's quarter" % id)
			in_artisans += 1
	check(in_artisans >= 5, "the workshops of the four trades there (%d)" % in_artisans)
	for lm: Dictionary in m["landmarks"]:
		if str(lm["type"]) == "cathedral":
			eq(_zone_of(m, lm["origin"]), "nobles", "the cathedral in the patricians' quarter")
		if str(lm["type"]) in ["exchange", "customs", "warehouse"]:
			eq(_zone_of(m, lm["origin"]), "port", "%s by the harbour" % lm["type"])
	eq(_zone_of(m, m["town_hall"]["service"]), "centre", "the town hall on the market square")
	for s: String in m["stalls"]:
		eq(_zone_of(m, m["stalls"][s]["service"]), "centre", "stall %s on the square" % s)
	var rows: Array = m["rows"]
	var by := {}
	for r: int in 80:
		for c: int in 80:
			var k := _zone_of(m, [c, r]) + ":" + cat.tile_kind_of_char(str(rows[r])[c])
			by[k] = int(by.get(k, 0)) + 1
	check(int(by.get("port:water", 0)) >= 100 and int(by.get("port:dock", 0)) >= 6, "the river and its quays")
	check(int(by.get("outskirts:field", 0)) >= 100, "the fields outside the walls")
	var forest := 0
	for z: Dictionary in m["zones"]:
		if str(z["kind"]) == "forest":
			forest = int(z["tiles"])
	check(float(by.get("forest:tree", 0)) / float(maxi(1, forest)) >= 0.35, "a wood: trees on most of it")


func test_only_bellcaire_has_zones() -> void:
	for id: String in ["town_e", "region_port", "region_quarry", "region_hamlet", "region_abbey"]:
		check(not (cat.maps()[id] as Dictionary).has("zones"), "%s: no zones (unchanged)" % id)


func test_the_population_follows_the_houses() -> void:
	var m := _cap()
	var houses := (m["population"] as Array).size()
	eq(int(m["population_max"]), 5 * houses, "O-R9: 5 per house (%d houses)" % houses)
	var c := Catalog.load_from()
	c.life_tables.get("life", {})["enabled"] = true
	var sim := Sim.new(NewGame.from_start(c, "artisan_blacksmith", "normal", {"city": "capital", "cast": "fixed"}, 1)["state"], c)
	for i: int in 61:
		sim.step()
	var folk := Population.townsfolk(sim.state)
	eq(folk.size(), Population.max_total(sim), "the town full: its own figure")
	var housed_and_working := 0
	for id: String in folk:
		var ch: Dictionary = sim.state.characters[id]
		if str(ch.get("home", "")) != "" and str(ch.get("occupation", "")) != "":
			housed_and_working += 1
	eq(housed_and_working, folk.size(), "every townsperson with a house and a trade (%d)" % folk.size())


func test_the_zone_names_show_at_the_farthest_zoom() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var st: WorldState = NewGame.from_start(cat, "artisan_blacksmith", "normal", {"city": "capital"}, 1)["state"]
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(st, cat)
	eq(v.zone_layer.shown.size(), 6, "six names")
	eq((v.zone_layer.shown["artisans"] as Label).text, "Barrio de los Menestrales", "the craftsmen's quarter by name")
	v.zone_layer.update(2)
	check(not (v.zone_layer.shown["port"] as Label).visible, "hidden closer in")
	v.zone_layer.update(1)
	check((v.zone_layer.shown["port"] as Label).visible, "shown at the farthest zoom")
	v.free()
	var w: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	w.setup(NewGame.from_scenario("town_e_start")["state"], cat)
	eq(w.zone_layer.shown.size(), 0, "Vilarrasa: no zone names")
	w.free()
	TranslationServer.set_locale(before)
