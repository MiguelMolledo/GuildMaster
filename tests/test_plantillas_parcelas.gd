extends "res://tests/test_case.gd"
## Plots (docs/gdd/04_diseno_de_juego.md §4.9.1; data/maps "plots", tools/city/plots.py): every town of the region has
## at least 2 free lots inside and 2 outside, 1 to 3 ruins, its NPC businesses (some for sale) and the valve of 4.9 (2
## free plots of each zone); the sim never reads them (the same game with or without them); the view draws the lot,
## the ruin and the «Se vende» sign.

const START: String = "artisan_blacksmith"

var cat := Catalog.load_from()


func _maps() -> Array:
	var out: Array = []
	for id: String in NewGame.cities(cat):
		out.append(str(NewGame.city(cat, id)["map"]))
	return out


func _game(city: String, seed_value: int = 1) -> WorldState:
	var ch := {"cast": "fixed"}
	if city != NewGame.start_city(cat, START):
		ch["city"] = city
	var r := NewGame.from_start(cat, START, "normal", ch, seed_value)
	check(bool(r.get("ok", false)), "from_start %s: %s" % [city, r.get("error", "")])
	return r.get("state") as WorldState


func test_every_town_has_its_plots() -> void:
	for mid: String in _maps():
		var ps: Array = cat.maps()[mid].get("plots", [])
		var n := {"lot_inside": 0, "lot_outside": 0, "ruin": 0, "business": 0, "for_sale": 0}
		var free := {"rustic": 0, "production": 0, "housing": 0}
		for p: Dictionary in ps:
			var st := str(p["state"])
			if st == "business":
				n["business"] += 1
				if bool(p.get("for_sale", false)):
					n["for_sale"] += 1
				check(cat.maps()[mid]["buildings"].has(str(p.get("site", ""))), "%s %s: its site" % [mid, p["id"]])
				continue
			n["ruin" if st == "ruin" else "lot_" + str(p["side"])] += 1
			free[str(p["zone"])] += 1
			check(float(p["location"]) >= 0.0 and float(p["location"]) <= 1.0, "%s %s: location in [0, 1]" % [mid, p["id"]])
		check(int(n["lot_inside"]) >= 2, "%s: 2 lots inside (%d)" % [mid, n["lot_inside"]])
		check(int(n["lot_outside"]) >= 2, "%s: 2 lots outside (%d)" % [mid, n["lot_outside"]])
		check(int(n["ruin"]) >= 1 and int(n["ruin"]) <= 3, "%s: 1 to 3 ruins (%d)" % [mid, n["ruin"]])
		check(int(n["business"]) > 0 and int(n["for_sale"]) > 0, "%s: NPC businesses, some for sale %s" % [mid, n])
		for z: String in free:
			check(int(free[z]) >= 2, "%s: the valve, 2 free %s plots (%d)" % [mid, z, free[z]])


func test_the_plots_do_not_touch_the_sim() -> void:
	for city: String in ["villa", "capital"]:
		var a := Sim.new(_game(city), cat)
		var bare := Catalog.load_from()
		for mid: String in bare.maps():
			(bare.maps()[mid] as Dictionary).erase("plots")
		var r := NewGame.from_start(bare, START, "normal", {"cast": "fixed"} if city == "villa" else {"cast": "fixed", "city": city}, 1)
		var b := Sim.new(r["state"], bare)
		eq(JSON.stringify(b.state.to_dict()), JSON.stringify(a.state.to_dict()), "%s: the same new game without plots" % city)
		for i: int in 600:
			a.step()
			b.step()
		eq(b.state_hash(), a.state_hash(), "%s: the same game 10 hours later without plots" % city)


func test_the_view_draws_lots_ruins_and_the_sale_sign() -> void:
	for city: String in ["villa", "capital"]:
		var st := _game(city)
		var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
		v.setup(st, cat)
		var kinds := {}
		for id: String in v.plot_layer.shown:
			kinds[str(v.plot_layer.shown[id])] = int(kinds.get(str(v.plot_layer.shown[id]), 0)) + 1
		check(int(kinds.get("lot", 0)) >= 4, "%s: the free lots drawn %s" % [city, kinds])
		check(int(kinds.get("ruin", 0)) >= 1, "%s: a ruin drawn %s" % [city, kinds])
		check(int(kinds.get("for_sale", 0)) >= 1, "%s: a «Se vende» sign %s" % [city, kinds])
		var stakes := 0
		for n: Node in v.objects().get_children():
			if str(n.name).begins_with("plot_stake_"):
				stakes += 1
		eq(stakes, 4 * int(kinds.get("lot", 0)), "%s: four stakes a lot" % city)
		v.free()


func test_the_festival_decoration_keeps_off_the_plots_and_the_dressing() -> void:
	for city: String in NewGame.cities(cat):
		var st := _game(city)
		var m: Dictionary = cat.maps()[st.map_id]
		var keep := {}
		for p: Dictionary in m.get("plots", []):
			if str(p["state"]) in ["lot", "ruin"]:
				for t: Vector2i in PlotLayer.tiles_of(p):
					keep[t] = "plot " + str(p["id"])
		for it: Dictionary in m.get("decor", {}).get("items", []):
			if str(it.get("kind", "")) == "single":  # the well
				keep[Vector2i(int(it["at"][0]), int(it["at"][1]))] = "decor " + str(it["id"])
		for svc: Dictionary in SimQuery.map_services(st, cat):  # the stalls, the board, the town hall
			keep[svc["tile"]] = "service"
		var sites := FestivalLayer.sites(st, cat)
		var bad: Array = []
		for where: String in sites:
			for t: Vector2i in sites[where]:
				if keep.has(t):
					bad.append("%s %s: %s" % [where, t, keep[t]])
		eq(bad, [], "%s: no festival site on a plot, the well or a stall" % city)
