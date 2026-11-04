extends "res://tests/test_case.gd"
## Población (sim/meta/cast.gd, data/cast.json, docs/contratos/poblacion.md): the cast of a new game. Same seed, same
## cast; other seeds, other people (names barely repeated inside a game); the fixed cast is exactly today's; what weighs
## on the balance does not move; births and newcomers take their name and look from the cast; the cast seed is a
## sub-seed (another family, the same world); a bigger town scales; save v14 and its migration.

const STARTS: Array[String] = ["artisan_blacksmith", "artisan_carpenter", "artisan_mason", "artisan_tailor"]

var cat := Catalog.load_from()


func _game(start: String = "artisan_blacksmith", seed_value: int = 1, choices: Dictionary = {}) -> WorldState:
	var r := NewGame.from_start(cat, start, "normal", choices, seed_value)
	check(bool(r.get("ok", false)), "from_start %s: %s" % [start, r.get("error", "")])
	return r["state"]


## Everything cosmetic of the cast: per character name, sex, birth day, tones, portrait and family name and colours.
func _roster(st: WorldState) -> Array:
	var out: Array = []
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		var c: Dictionary = st.characters[id]
		var f: Dictionary = st.families[str(c["family"])]
		out.append([id, str(c["name"]), bool(c["female"]), int(c["birth_day"]), int(c["visual"]["hair"]),
			int(c["visual"]["skin"]), str(f["name"]), str(f["colors"]["primary"]), str(f["colors"]["secondary"])])
	return out


## What weighs on the balance (never from the cast): stats of the key characters, gold, buildings, loans, ranks,
## professions, sexes of the workshop families and the townsfolk's craft and constitution.
func _balance(st: WorldState) -> Array:
	var out: Array = []
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		var c: Dictionary = st.characters[id]
		var f: Dictionary = st.families[str(c["family"])]
		var key := str(f["controlled_by"]) == "human" or str(f.get("ai_profile", "")) != ""
		var stats: Variant = c["stats"] if key else [int(c["stats"]["craft"]), int(c["stats"]["constitution"]),
			int(c["stats"]["negotiation"])]
		out.append([id, c["family"], stats, str(c["rank"]), str(c["profession"]), str(c["home"]), str(c["location"]),
			c["position"], str(c["occupation"]), bool(c["female"]) if key else true])
		if key and str(c["controlled_by"]) == "human":
			out.append(int(c["birth_day"]))  # the protagonist's age stays the start's
	for fid: Variant in st.families:
		var f: Dictionary = st.families[fid]
		out.append([str(fid), int(f["gold"]), int(f["reputation"]), str(f["ai_profile"]), str(f.get("title", ""))])
	var by_age: Array = ids.duplicate()  # who is older than whom (the government, heirs): the data's order
	by_age.sort_custom(func(a: String, b: String) -> bool:
		var x := int(st.characters[a]["birth_day"])
		var y := int(st.characters[b]["birth_day"])
		return x < y or (x == y and a < b))
	var town: Array = by_age.filter(func(c: String) -> bool: return TownLife.is_household(st, str(st.characters[c]["family"])))
	out.append(town)
	out.append(SaveFile.canonical(st.buildings))
	out.append(SaveFile.canonical(st.loans))
	out.append(SaveFile.canonical(st.contracts))
	out.append(SaveFile.canonical(st.offices))
	return out


func test_same_seed_same_cast() -> void:
	for start: String in STARTS:
		var a := _game(start, 5)
		var b := _game(start, 5)
		eq(_roster(a), _roster(b), "%s: the same seed gives the same cast" % start)
		eq(SaveFile.canonical(a.to_dict()), SaveFile.canonical(b.to_dict()), "%s: and the same game" % start)
		eq(str(a.cast["mode"]), "random", "a new game deals its cast by default")


func test_other_seeds_other_people() -> void:
	var seen := {}
	var given_total := 0
	var given_repeats := 0
	for sd: int in range(1, 21):
		var st := _game("artisan_blacksmith", sd)
		var names: Array = []
		var sig := PackedStringArray()
		for row: Array in _roster(st):
			names.append(str(row[1]))
			sig.append("%s %s %d %d" % [row[1], row[6], row[3], row[4]])
		var key := ",".join(sig)
		check(not seen.has(key), "seed %d: its cast is not the one of seed %s" % [sd, seen.get(key, "")])
		seen[key] = sd
		var uniq := {}
		for n: String in names:
			uniq[n] = true
		given_total += names.size()
		given_repeats += names.size() - uniq.size()
		var houses := {}
		for f: Dictionary in st.families.values():
			check(not houses.has(str(f["name"])), "seed %d: no two families named %s" % [sd, f["name"]])
			houses[str(f["name"])] = true
	eq(seen.size(), 20, "20 seeds, 20 different casts")
	eq(given_repeats, 0, "no given name repeats inside a game (%d people)" % given_total)


func test_casts_vary_across_seeds() -> void:
	# The town's people are not always the same: across 20 games every role meets many different names and houses.
	var rival_names := {}
	var hero_houses := {}
	var town_houses := {}
	var first_names := {}
	for sd: int in range(1, 21):
		var st := _game("artisan_blacksmith", sd)
		rival_names[str(st.characters["chr_0002"]["name"])] = true
		hero_houses[str(st.families["fam_0001"]["name"])] = true
		town_houses[str(st.families["fam_0003"]["name"])] = true
		first_names[str(st.characters["chr_0003"]["name"])] = true
	check(rival_names.size() >= 15, "the rival smith has many names (%d of 20)" % rival_names.size())
	check(hero_houses.size() >= 6, "the player's house name varies (%d of 20; blacksmith surnames: 8)" % hero_houses.size())
	check(town_houses.size() >= 15, "the first household's surname varies (%d of 20)" % town_houses.size())
	check(first_names.size() >= 15, "its first member's name varies (%d of 20)" % first_names.size())


func test_fixed_cast_is_todays() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/cast_fixed.json"))
	for start: String in STARTS:
		var st := _game(start, 1, {"cast": "fixed"})
		eq(_roster(st), SaveFile.intify(golden[start]), "%s: the fixed cast is the one of before the generator" % start)
		eq(str(st.cast["mode"]), "fixed", "saved as fixed")


func test_balance_does_not_depend_on_the_cast() -> void:
	for start: String in STARTS:
		var fixed := _game(start, 3, {"cast": "fixed"})
		for roll: int in [0, 1, 7]:
			var st := _game(start, 3, {"cast_seed": Cast.sub_seed(3, roll)})
			eq(_balance(st), _balance(fixed), "%s roll %d: the balance inputs are the fixed cast's" % [start, roll])
			eq(str(st.rng.state), str(fixed.rng.state), "%s roll %d: the world rng has not moved" % [start, roll])
			eq(st.world_seed, fixed.world_seed, "the same world seed")


func test_ages_and_looks_in_their_ranges() -> void:
	var cfg: Dictionary = cat.cast
	var tf: Array = cfg["ages"]["townsfolk"]
	var rv: Array = cfg["ages"]["rival"]
	for sd: int in range(1, 11):
		var st := _game("artisan_blacksmith", sd)
		var sim := Sim.new(st, cat)
		for id: String in st.characters:
			var c: Dictionary = st.characters[id]
			var f: Dictionary = st.families[str(c["family"])]
			var age := Kin.age(sim, id)
			if TownLife.is_household(st, str(c["family"])):
				check(age >= int(tf[0]) and age <= int(tf[1]), "%s townsperson age %d in %s" % [id, age, tf])
				eq(str(c["visual"]["portrait"]["type"]), "commoner", "%s: a commoner's portrait" % id)
			elif id == "chr_0002":
				check(age >= int(rv[0]) and age <= int(rv[1]), "the rival's age %d in %s" % [age, rv])
				eq(str(c["visual"]["portrait"]["type"]), "artisan", "the rival smith's portrait type")
			elif str(f["controlled_by"]) == "human":
				eq(age, 20, "the protagonist keeps the start's age")
				eq(str(c["visual"]["portrait"]["type"]), "artisan", "the protagonist's portrait is of the class")
			check(int(c["visual"]["hair"]) in (cfg["look"]["hair"] as Array), "%s hair in the cast's tones" % id)
			check(int(c["visual"]["skin"]) in (cfg["look"]["skin"] as Array), "%s skin in the cast's tones" % id)
			_check_portrait(st, id, age)


func test_family_colors_are_distinct_and_far_from_the_player() -> void:
	for sd: int in range(1, 11):
		var st := _game("artisan_blacksmith", sd, {"colors": {"primary": "#3f6b3a", "secondary": "#c8a84e"}})
		var prim := {}
		for fid: String in st.families:
			var p := str(st.families[fid]["colors"]["primary"])
			check(not prim.has(p), "seed %d: %s and %s share the primary %s" % [sd, fid, prim.get(p, ""), p])
			prim[p] = fid
			if fid != "fam_0001":
				check(p != "#3f6b3a", "seed %d: %s does not take the player's green" % [sd, fid])


func test_another_family_is_a_sub_seed() -> void:
	var a := Cast.proposal(cat, cat.starts()["artisan_blacksmith"], "random", Cast.sub_seed(9, 0))
	var b := Cast.proposal(cat, cat.starts()["artisan_blacksmith"], "random", Cast.sub_seed(9, 1))
	check(a != b, "another roll proposes another family (%s / %s)" % [a["family_name"], b["family_name"]])
	var st := _game("artisan_blacksmith", 9, {"cast_seed": Cast.sub_seed(9, 1)})
	eq(str(st.characters["chr_0001"]["name"]), str(b["name_m"]), "the game takes the proposal of that roll")
	eq(str(st.families["fam_0001"]["name"]), str(b["family_name"]), "and its family name")
	eq(int(st.characters["chr_0001"]["visual"]["hair"]), int(b["visual"]["hair"]), "and its look")
	var her := _game("artisan_blacksmith", 9, {"cast_seed": Cast.sub_seed(9, 1), "female": true})
	eq(str(her.characters["chr_0001"]["name"]), str(b["name_f"]), "a woman takes the female name of the proposal")
	eq(str(st.cast["seed"]), str(Cast.sub_seed(9, 1)), "the cast seed is saved")
	var mine := _game("artisan_blacksmith", 9, {"name": "Aldonça", "family_name": "Vidal", "female": true})
	eq([str(mine.characters["chr_0001"]["name"]), str(mine.families["fam_0001"]["name"])], ["Aldonça", "Vidal"],
		"what the player writes wins")
	eq(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "nope"}, 1)["ok"], false, "unknown cast mode")
	eq(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast_seed": "x"}, 1)["ok"], false, "bad cast seed")


func test_newborns_take_name_and_look_from_the_cast() -> void:
	var st := _game("artisan_blacksmith", 4)
	var sim := Sim.new(st, cat)
	var father := "chr_0019"  # the carpenter competitor and his wife
	var mother := "chr_0020"
	eq(str(st.characters[mother]["spouse"]), father, "a married couple")
	var pool: Array = (cat.cast["names"]["male"] as Array) + (cat.cast["names"]["female"] as Array)
	for i: int in 8:
		st.clock["minute"] = int(st.clock["minute"]) + Clock.MINUTES_PER_DAY
		var kid := Births.born(sim, mother, father)
		var c: Dictionary = st.characters[kid]
		check(str(c["name"]) in pool, "%s «%s» is a name of data/cast.json" % [kid, c["name"]])
		for other: String in st.characters:
			if other != kid and bool(st.characters[other].get("alive", true)):
				check(str(st.characters[other]["name"]) != str(c["name"]), "%s «%s»: nobody alive has it" % [kid, c["name"]])
		eq(str(c["visual"]["portrait"]["type"]), str(st.characters[father]["visual"]["portrait"]["type"]),
			"the child's portrait type is the father's")
		var parents := [int(st.characters[mother]["visual"]["hair"]), int(st.characters[father]["visual"]["hair"])]
		check(int(c["visual"]["hair"]) in parents or int(c["visual"]["hair"]) in (cat.cast["look"]["hair"] as Array),
			"hair of a parent or a new cast tone")


func test_newcomers_take_name_and_look_from_the_cast() -> void:
	var st := _game("artisan_blacksmith", 6)
	var sim := Sim.new(st, cat)
	var house := ""
	for b: String in st.buildings:
		if str(st.buildings[b]["type"]) == "house":
			house = b
			break
	for i: int in 4:
		var id := Population._arrive(sim, house, 3, i)
		var c: Dictionary = st.characters[id]
		var pool: Array = cat.cast["names"]["female" if bool(c["female"]) else "male"]
		check(str(c["name"]) in pool, "newcomer %s «%s» from data/cast.json" % [id, c["name"]])
		var same := 0
		for other: Dictionary in st.characters.values():
			if bool(other.get("alive", true)) and str(other["name"]) == str(c["name"]):
				same += 1
		eq(same, 1, "newcomer «%s»: a name nobody else alive has" % c["name"])
		eq(str(c["visual"]["portrait"]["type"]), "commoner", "a newcomer is a commoner")
		check(int(c["visual"]["hair"]) in (cat.cast["look"]["hair"] as Array), "its hair is a cast tone")


func test_fixed_cast_keeps_the_old_draw_of_births_and_newcomers() -> void:
	var st := _game("artisan_blacksmith", 4, {"cast": "fixed"})
	var sim := Sim.new(st, cat)
	st.clock["minute"] = int(st.clock["minute"]) + Clock.MINUTES_PER_DAY
	var kid := Births.born(sim, "chr_0020", "chr_0019")
	var key := "child|%d|chr_0020" % Clock.day(int(st.clock["minute"]))
	var female := Kin.roll(st, key + "|sex") < 0.5
	var names: Array = cat.family["names"]["female" if female else "male"]
	eq(str(st.characters[kid]["name"]), str(names[Kin.randi_range(st, key + "|name", 0, names.size() - 1)]),
		"the H8 name draw (data/family.json names)")
	check(st.characters[kid]["visual"].get("portrait") is Dictionary, "and a base portrait")


func test_a_bigger_town_scales() -> void:
	# The EA map is not approved: a made-up one with 20 households whose members only give rank and stats (the rest is
	# the cast's), dealt with no repeated name or surname.
	var map: Dictionary = (cat.maps()["town_e"] as Dictionary).duplicate(true)
	map["id"] = "big_test"
	var pop: Array = []
	for i: int in 20:
		pop.append({"home": "house_nw", "gold": 20, "members": [
			{"rank": "apprentice", "stats": {"charisma": 4, "empathy": 4, "dexterity": 4, "craft": 3}},
			{"rank": "", "stats": {"charisma": 4, "empathy": 4, "dexterity": 4, "craft": 3}}]})
	map["population"] = pop
	var start: Dictionary = cat.starts()["artisan_blacksmith"]
	var cast := Cast.generate(cat, start, map, "random", 77)
	var names := {}
	var houses := {}
	var people := 0
	for hh: Dictionary in cast["households"]:
		check(not houses.has(str(hh["family_name"])), "house surname %s once" % hh["family_name"])
		houses[str(hh["family_name"])] = true
		for m: Dictionary in hh["members"]:
			people += 1
			names[str(m["name"])] = true
			check(m.has("female") and m.has("age") and m["visual"].has("portrait"), "every field generated")
	eq(people, 40, "40 townsfolk")
	eq(names.size(), people, "40 different given names")
	var fixed := Cast.generate(cat, start, map, "fixed", 77)
	eq((fixed["households"] as Array).size(), 20, "the fixed cast also fills what a map does not say")
	var other := Cast.generate(cat, start, (map.duplicate(true) as Dictionary).merged({"id": "another_town"}, true), "random", 77)
	check(str(other["households"][0]["members"][0]["name"]) + str(other["households"][0]["family_name"]) !=
		str(cast["households"][0]["members"][0]["name"]) + str(cast["households"][0]["family_name"]),
		"another town of the same game gets other people")


func test_save_round_trip_keeps_the_cast() -> void:
	var st := _game("artisan_blacksmith", 8)
	check(WorldState.VERSION >= 14, "v14 or later (the cast arrived with v14)")
	var back: WorldState = SaveFile.from_text(JSON.stringify(st.to_dict()))["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(st.to_dict()), "the cast and the portraits come back")
	eq(back.cast, st.cast, "the cast seed and mode")
	eq(back.characters["chr_0003"]["visual"]["portrait"], st.characters["chr_0003"]["visual"]["portrait"], "a portrait")


func test_migration_from_v13() -> void:
	var st := _game("artisan_blacksmith", 2, {"cast": "fixed"})
	var d := st.to_dict()
	d["version"] = 13
	d.erase("cast")
	for c: Dictionary in (d["characters"] as Dictionary).values():
		(c["visual"] as Dictionary).erase("portrait")
	var r := SaveFile.from_text(JSON.stringify(d))
	check(r["ok"], "a v13 game loads")
	var back: WorldState = r["state"]
	eq(back.version, WorldState.VERSION, "migrated to the current version (v14 brought the cast)")
	eq(str(back.cast["mode"]), "fixed", "a game from before keeps the fixed cast (old births and newcomers)")
	eq(str(back.characters["chr_0001"]["visual"]["portrait"]["type"]), "artisan", "the protagonist: the family's class")
	eq(str(back.characters["chr_0002"]["visual"]["portrait"]["type"]), "artisan", "the rival smith")
	eq(str(back.characters["chr_0003"]["visual"]["portrait"]["type"]), "commoner", "a townsperson")
	eq(str(back.characters["chr_0003"]["visual"]["portrait"]["id"]), "", "no id yet (the pool is not in the save)")
	check(Identity.portrait_texture(Identity.of(back, "chr_0003")) != null, "the view shows one of its type meanwhile")
	var sim := Sim.new(back, cat)
	Cast.grow_portraits(sim)
	check(str(back.characters["chr_0003"]["visual"]["portrait"]["id"]).begins_with("m_adult_commoner_"),
		"the next year change gives it its id (%s)" % back.characters["chr_0003"]["visual"]["portrait"]["id"])
	eq(int(back.characters["chr_0003"]["visual"]["hair"]), int(st.characters["chr_0003"]["visual"]["hair"]), "tones kept")


## The portrait of `id` is a pool id of its sex and age band, of its type or of the index's fallback / commoner.
func _check_portrait(st: WorldState, id: String, age: int) -> void:
	var c: Dictionary = st.characters[id]
	var pid := str(c["visual"]["portrait"]["id"])
	var band := Cast.stage_of(cat, age)
	var sex := "f" if bool(c["female"]) else "m"
	check(pid.begins_with("%s_%s_" % [sex, band]), "%s: portrait %s of its sex and band (%s %s)" % [id, pid, sex, band])
	var t := pid.substr(("%s_%s_" % [sex, band]).length()).get_slice("_", 0)
	var type := str(c["visual"]["portrait"]["type"])
	var fb := str(cat.portrait_pool["fallback"].get(type, {}).get(band, ""))
	check(t in [type, fb, "commoner"], "%s: %s is of its type %s (or its fallback)" % [id, pid, type])
	check(pid in ((cat.portrait_pool["by"] as Dictionary).get("%s|%s|%s" % [sex, band, t], []) as Array), "%s in the pool" % pid)


func test_portrait_ids_come_from_the_pool() -> void:
	eq(cat.portrait_pool["count"], 566, "the pool's 566 portraits")
	var seen := {}
	for sd: int in range(1, 11):
		var st := _game("artisan_blacksmith", sd)
		var sim := Sim.new(st, cat)
		var faces := {}
		for id: String in st.characters:
			_check_portrait(st, id, Kin.age(sim, id))
			var pid := str(st.characters[id]["visual"]["portrait"]["id"])
			check(not faces.has(pid), "seed %d: %s and %s share the face %s" % [sd, id, faces.get(pid, ""), pid])
			faces[pid] = id
			seen[pid] = true
	# town_e uses 4 combinations (adult m/f, commoner and artisan) of 8 faces each: nearly all 32 come out in 10 games
	check(seen.size() >= 28, "most faces of those combinations in 10 games (%d of 32)" % seen.size())
	# A girl of a guard family at 15: the index sends her to commoner; a scholar child to merchant.
	var r := RandomNumberGenerator.new()
	r.seed = 1
	check(Cast.pick_portrait(cat, "guard", 15, true, r).begins_with("f_youth_commoner_"), "guard girl of 15: commoner")
	check(Cast.pick_portrait(cat, "scholar", 8, false, r).begins_with("m_child_merchant_"), "scholar boy of 8: merchant")
	check(Cast.pick_portrait(cat, "artisan", 3, false, r).begins_with("m_child_artisan_"), "under 6: child")
	eq(Cast.pick_portrait(cat, "artisan", 30, false, r, 4), "m_adult_artisan_04", "the number asked for if the band has it")


func test_portraits_grow_with_age() -> void:
	var st := _game("artisan_blacksmith", 4)
	var sim := Sim.new(st, cat)
	st.clock["minute"] = int(st.clock["minute"]) + Clock.MINUTES_PER_DAY
	var kid := Births.born(sim, "chr_0020", "chr_0019")
	var first := str(st.characters[kid]["visual"]["portrait"]["id"])
	check(first.get_slice("_", 1) == "child", "a newborn has a child's portrait (%s)" % first)
	eq(str(st.characters[kid]["visual"]["portrait"]["type"]), "artisan", "of its father's type (a workshop family)")
	var dpy := Clock.days_per_year(cat.time)
	st.characters[kid]["birth_day"] = int(st.characters[kid]["birth_day"]) - 12 * dpy  # 12 years old now
	Cast.grow_portraits(sim)
	var grown := str(st.characters[kid]["visual"]["portrait"]["id"])
	check(grown.get_slice("_", 1) == "youth", "at 12 a youth's portrait (%s)" % grown)
	eq(grown.get_slice("_", 4), first.get_slice("_", 4), "the same number (the pool has 6+ of every band)")
	Cast.grow_portraits(sim)
	eq(str(st.characters[kid]["visual"]["portrait"]["id"]), grown, "the same band: the same portrait")
	var adult_before := str(st.characters["chr_0019"]["visual"]["portrait"]["id"])
	Cast.grow_portraits(sim)
	eq(str(st.characters["chr_0019"]["visual"]["portrait"]["id"]), adult_before, "an adult keeps his")


func test_portrait_resolution_in_the_view() -> void:
	# The view (game/visuals/visual_paths.gd) turns the id into the pool's face (32) or bust (64).
	var f := VisualPaths.portrait_file("f_mature_merchant_03", 32)
	check(f != null and f.resource_path.ends_with("f/mature/merchant/f_mature_merchant_03_32.png"), "the face (%s)" % f)
	var b := VisualPaths.portrait_file("f_mature_merchant_03", 64)
	check(b != null and b.resource_path.ends_with("f/mature/merchant/f_mature_merchant_03.png"), "the bust (%s)" % b)
	eq(VisualPaths.portrait_file("no_such_id"), null, "an unknown id: the greybox")
	var st := _game("artisan_blacksmith", 2)
	var who := Identity.of(st, "chr_0003")
	eq(str(who["portrait"]["id"]), str(st.characters["chr_0003"]["visual"]["portrait"]["id"]), "Identity passes the id")
	check(Identity.portrait_texture(who) != null, "and the view finds its texture")
	check(VisualPaths.portrait("clergy", "child", true, 3) != null, "without an id: the index's fallback (clergy child)")
	eq(Identity.stage(5), "child", "under 6: child")
	eq([Identity.stage(11), Identity.stage(12), Identity.stage(17), Identity.stage(18), Identity.stage(44),
		Identity.stage(45), Identity.stage(59), Identity.stage(60)],
		["child", "youth", "youth", "adult", "adult", "mature", "mature", "elder"], "the pool's age bands")
	var black := Color(0.1, 0.1, 0.1)
	eq(Identity.greyed(black, "adult"), black, "an adult keeps the hair")
	check(Identity.greyed(black, "elder").v > Identity.greyed(black, "mature").v, "the elder greys more than the mature")


func test_the_sim_reads_the_pool_from_data_only() -> void:
	# data/portraits.json is the sim's whole knowledge of the pool (tools/art/portraits_catalog.py exports it from the
	# index; the validator checks they match): without it a game still starts, with empty portrait ids.
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/portraits.json"))
	check(d is Dictionary and not (d as Dictionary).has("portraits"), "data/portraits.json: ids by combination, no files")
	eq(cat.portrait_pool["by"], d["by"], "Catalog.portrait_pool is data/portraits.json")
	var bare := Catalog.load_from()
	bare.portrait_pool = {}
	var r := NewGame.from_start(bare, "artisan_blacksmith", "normal", {}, 3)
	check(bool(r["ok"]), "a game starts without the pool")
	eq(str((r["state"] as WorldState).characters["chr_0003"]["visual"]["portrait"]["id"]), "", "with no portrait id")
