extends "res://tests/test_case.gd"
## H12 (GDD 4.2.1, 4.4, 4.5.5, 4.8): the other artisan trades (carpenter, mason, tailor) on the MVP systems: their
## profession sheets, a new game as each one, the competitor workshops of the other trades (the rival smith's AI),
## the contracts of the player's trade, the production chain with quality, the upgrade tree and the save.

const FAM := "fam_0001"
const HERO := "chr_0001"
const BLD := "bld_0001"
const TRADES := {"carpenter": ["carpentry", "sawhorse", "workbench", "carpentry_planks", "carpentry_chest", "chest"],
	"mason": ["masonry", "cutting_bench", "carving_bench", "masonry_ashlar", "masonry_trough", "trough"],
	"tailor": ["tailor_shop", "loom", "sewing_table", "tailor_cloth", "tailor_common_clothes", "common_clothes"]}

var cat := Catalog.load_from()


func _new(prof: String, difficulty: String = "normal", world_seed: int = 1) -> WorldState:
	var r := NewGame.from_start(cat, "artisan_" + prof, difficulty, {"cast": "fixed"}, world_seed)
	check(r["ok"], "artisan_%s starts: %s" % [prof, r.get("error", "")])
	return r["state"]


func _run(sim: Sim, minutes: int) -> Array:
	var out: Array = []
	for i: int in minutes:
		out.append_array(sim.step([]))
	return out


func _ai_families(st: WorldState) -> Array:
	var out: Array = []
	var ids: Array = st.families.keys()
	ids.sort()
	for f: String in ids:
		if str(st.families[f].get("ai_profile", "")) != "":
			out.append(f)
	return out


func _home_of(st: WorldState, fam: String) -> Dictionary:
	for b: String in st.buildings:
		if str(st.buildings[b].get("owner", "")) == fam and not (st.buildings[b].get("zones", {}) as Dictionary).is_empty():
			return st.buildings[b]
	return {}


func test_every_artisan_profession_has_its_sheet_and_start() -> void:
	eq(cat.professions_of("artisan"), ["blacksmith", "carpenter", "mason", "tailor"], "the four artisan trades in order (GDD 4.2.1)")
	for p: String in cat.professions_of("artisan"):
		var def: Dictionary = cat.professions()[p]
		var start: Dictionary = cat.starts().get(str(def["start"]), {})
		eq(str(start.get("profession", "")), p, "%s: its start plays it" % p)
		eq(str(start.get("building", {}).get("type", "")), str(def["building"]), "%s: starts in its workshop" % p)
		eq(str(cat.buildings()[str(def["building"])].get("tool", "")), str(def["tool"]), "%s: the right tool" % p)
		check(cat.upgrade_tree(str(def["building"])).size() == 24, "%s: 8 branches × 3 levels (GDD 4.8)" % p)
	check(cat.validate().is_empty(), "the catalog validates: %s" % [cat.validate()])


func test_a_new_game_as_each_trade() -> void:
	for p: String in TRADES:
		var t: Array = TRADES[p]
		var st := _new(p)
		var b: Dictionary = st.buildings[BLD]
		eq([str(b["type"]), str(b["owner"])], [t[0], FAM], "%s: the workshop is the player's" % p)
		eq(str(st.characters[HERO]["profession"]), p, "%s: the protagonist's trade" % p)
		eq(str(st.characters[HERO]["equipment"]["tool"]["item"]), str(cat.professions()[p]["tool"]), "%s: tool equipped" % p)
		check((b["zones"] as Dictionary).has(str(t[1])) and (b["zones"] as Dictionary).has(str(t[2])), "%s: its stations" % p)
		eq(int(st.loans["lon_0001"]["principal"]), 200, "%s: the start debt of normal" % p)
		eq((st.contracts["board"] as Array).size(), 2, "%s: two scripted contracts" % p)
		for c: Dictionary in st.contracts["board"]:
			eq(str(Contracts.table_for_item(cat, str(c["item"])).get("profession", "")), p, "%s: contract of its trade" % p)
		eq(st.objectives[FAM]["chain"], cat.starts()["artisan_" + p]["objectives"], "%s: its objective chain" % p)


func test_one_workshop_of_each_trade_in_town_e() -> void:
	for start: String in ["artisan_blacksmith", "artisan_carpenter", "artisan_mason", "artisan_tailor"]:
		var st: WorldState = NewGame.from_start(cat, start, "normal", {"cast": "fixed"}, 1)["state"]
		var types := {}
		var origins := {}
		for b: String in st.buildings:
			var bld: Dictionary = st.buildings[b]
			var key := "%d,%d" % [int(bld["origin"][0]), int(bld["origin"][1])]
			check(not origins.has(key), "%s: one building per site (%s)" % [start, key])
			origins[key] = true
			types[str(bld["type"])] = int(types.get(str(bld["type"]), 0)) + 1
		var own := str(cat.buildings().keys().filter(func(b: String) -> bool:
			return b == str(cat.starts()[start]["building"]["type"]))[0])
		for ty: String in ["forge", "carpentry", "masonry", "tailor_shop"]:
			eq(int(types.get(ty, 0)), 2 if ty == own else 1, "%s: %s (the player's trade twice: its rival)" % [start, ty])
		var rival := ""
		for f: String in st.families:
			if str(st.families[f].get("ai_profile", "")) == "rival_smith":
				rival = f
		eq(str(_home_of(st, rival).get("type", "")), own, "%s: the rival (GDD 4.5.5) is of the player's trade" % start)
		for f: String in _ai_families(st):
			var home := _home_of(st, f)
			check(not home.is_empty(), "%s: AI family %s has its workshop" % [start, f])
			var head := str(st.families[f]["head"])
			eq(str(st.characters[head]["location"]), str(home.get("id", "")), "%s: %s starts inside" % [start, head])


func test_the_ids_of_the_blacksmith_start_do_not_move() -> void:
	var st: WorldState = NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"]
	eq([str(st.buildings["bld_0001"]["type"]), str(st.buildings["bld_0002"]["type"])], ["forge", "forge"],
		"player forge, then the rival's")
	eq(str(st.families["fam_0002"]["ai_profile"]), "rival_smith", "the rival smith is still fam_0002")
	var comps := _ai_families(st)
	comps.erase("fam_0002")
	eq(comps.size(), 3, "three competitors (carpenter, mason, tailor)")
	for f: String in comps:
		eq(str(st.families[f]["ai_profile"]), "rival_artisan", "%s: the competitor profile" % f)
		check(int(f.get_slice("_", 1)) > 2 + 8, "%s: added after the townsfolk" % f)


func test_competitors_follow_the_difficulty_and_never_ask_for_titles() -> void:
	for lvl: String in ["easy", "hard"]:
		var st: WorldState = NewGame.from_start(cat, "artisan_blacksmith", lvl, {"cast": "fixed"}, 1)["state"]
		for f: String in _ai_families(st):
			eq(int(st.characters[str(st.families[f]["head"])]["stats"]["craft"]),
				int(cat.difficulty_levels(lvl)["rival_craft"]), "%s %s: craft of the difficulty" % [lvl, f])
	var prof: Dictionary = cat.ai_profiles()["rival_artisan"]
	check(not bool(prof["title_rule"]["requests"]) and not bool(prof["office_rule"]["runs"])
		and not bool(prof["accuse_rule"]["accuses"]), "no titles, offices nor accusations (04c pending)")


func test_the_board_draws_from_the_players_trade() -> void:
	for p: String in ["blacksmith", "carpenter", "mason", "tailor"]:
		var st: WorldState = NewGame.from_start(cat, "artisan_" + p, "normal", {"cast": "fixed"}, 3)["state"]
		var sim := Sim.new(st, cat)
		eq(Contracts.board_tables(sim), [p], "%s: only its table" % p)
		st.contracts["board"] = []
		for i: int in 3:
			var id := Contracts.post_random(sim)
			for c: Dictionary in st.contracts["board"]:
				if str(c["id"]) == id:
					eq(str(Contracts.table_for_item(cat, str(c["item"])).get("profession", "")), p, "%s: random contract of its trade" % p)
	var st2: WorldState = NewGame.from_start(cat, "artisan_carpenter", "normal", {"cast": "fixed"}, 3)["state"]
	st2.characters[HERO]["profession"] = ""
	eq(Contracts.board_tables(Sim.new(st2, cat)).size(), cat.contracts().size(), "no trade: every table")


func test_the_chain_of_each_trade_with_quality() -> void:
	for p: String in TRADES:
		var t: Array = TRADES[p]
		var st := _new(p)
		var sim := Sim.new(st, cat)
		st.characters[HERO]["location"] = BLD
		var inv: Dictionary = st.buildings[BLD]["inventory"]
		var r_inter: Dictionary = cat.recipes()[str(t[3])]
		var r_prod: Dictionary = cat.recipes()[str(t[4])]
		for inp: Dictionary in r_inter["inputs"] + r_prod["inputs"]:
			Inventory.add(inv, cat, str(inp["item"]), 0, 10)
		var made := {}
		var ev := sim.step([{"type": "work_at", "actor": HERO, "building": BLD, "zone": str(t[1]), "recipe": str(t[3]),
			"mode": "normal"}])
		for e: Dictionary in ev:
			check(str(e["type"]) != "order_refused", "%s: %s accepted (%s)" % [p, t[3], e.get("reason", "")])
		for e: Dictionary in _run(sim, Production.cycle_minutes(cat, r_inter, "normal") + 1):
			if str(e["type"]) == "work_done":
				made[str(e["item"])] = int(made.get(str(e["item"]), 0)) + 1
		check(int(made.get(str(r_inter["output"]["item"]), 0)) >= 1, "%s: the intermediate is made" % p)
		sim.step([{"type": "stop_work", "actor": HERO, "building": BLD}])
		ev = sim.step([{"type": "work_at", "actor": HERO, "building": BLD, "zone": str(t[2]), "recipe": str(t[4]),
			"mode": "careful"}])
		for e: Dictionary in ev:
			check(str(e["type"]) != "order_refused", "%s: %s accepted (%s)" % [p, t[4], e.get("reason", "")])
		var q := -1
		for e: Dictionary in _run(sim, Production.cycle_minutes(cat, r_prod, "careful") + 2):
			if str(e["type"]) == "work_done" and str(e["item"]) == str(t[5]):
				q = int(e.get("quality", -1))
		check(q >= 0 and q <= 2, "%s: the product comes out with a quality (got %d)" % [p, q])
		check(Inventory.count(inv, str(t[5])) >= 1, "%s: in the storage" % p)


func test_the_upgrade_tree_of_each_trade() -> void:
	for p: String in TRADES:
		var t: Array = TRADES[p]
		var tree := str(t[0])
		var st := _new(p)
		var sim := Sim.new(st, cat)
		Upgrades.complete(sim, BLD, tree + "_capacity_1")
		check((st.buildings[BLD]["zones"] as Dictionary).has(str(t[2]) + "_2"), "%s: second product station" % p)
		eq(Upgrades.zone_kind(sim, BLD, str(t[2]) + "_2"), str(t[2]), "%s: it works as the first" % p)
		var locked := ""
		for rid: String in cat.recipes():
			if str(cat.recipes()[rid].get("building", "")) == tree and str(cat.recipes()[rid].get("requires_upgrade", "")) != "":
				locked = rid
		check(locked != "", "%s: a recipe unlocked by Production 3 (like steel)" % p)
		var zone := str(cat.recipes()[locked]["zone"])
		var before := ""
		for o: Dictionary in Production.recipe_options(sim, HERO, BLD, zone):
			if str(o["recipe"]) == locked:
				before = str(o["status"])
		eq(before, "locked", "%s: locked before" % p)
		for u: String in [tree + "_production_1", tree + "_production_2", tree + "_production_3"]:
			Upgrades.complete(sim, BLD, u)
		near(Upgrades.mult(sim, BLD, "production_speed"), 1.6, 0.0001, "%s: ×1.6 (branch top)" % p)
		check(locked in Upgrades.unlocks(sim, BLD, "unlock_recipe"), "%s: unlocked" % p)


func test_a_day_of_the_town_with_every_workshop() -> void:
	var st: WorldState = NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 2)["state"]
	var sim := Sim.new(st, cat)
	var comps := _ai_families(st)
	var made := {}
	var refused := 0
	for e: Dictionary in _run(sim, Clock.MINUTES_PER_DAY):
		if str(e["type"]) == "order_refused":
			refused += 1
		if str(e["type"]) == "work_done":
			var fam := str(st.characters.get(str(e.get("actor", "")), {}).get("family", ""))
			made[fam] = int(made.get(fam, 0)) + 1
	eq(refused, 0, "the AI gives no refused orders")
	for f: String in comps:
		check(int(made.get(f, 0)) > 0, "%s (%s) works its workshop on day 1" % [f, st.families[f]["name"]])


func test_save_round_trip_of_a_trade_game() -> void:
	var st := _new("tailor")
	var sim := Sim.new(st, cat)
	_run(sim, 6 * 60)
	var r := SaveFile.from_text(JSON.stringify(st.to_dict()))
	check(r["ok"], "saved and loaded")
	var back: WorldState = r["state"]
	eq(SaveFile.canonical(back.to_dict()), SaveFile.canonical(WorldState.from_dict(st.to_dict()).to_dict()), "same state")
	eq(str(back.buildings[BLD]["type"]), "tailor_shop", "the tailor's shop")


func test_new_game_screen_offers_the_trades() -> void:
	var s: NewGameScreen = (load("res://game/ui/new_game_screen.tscn") as PackedScene).instantiate()
	s.setup(cat, 7)
	var box := s.get_node("%Profession") as HBoxContainer
	eq(box.get_child_count(), 8, "a button per artisan trade, (H12 Patrón) the patron's farmer, (H12.2) the scholar's physician and banker and (H12) the rogue's thief")
	check(box.visible, "shown")
	var calls: Array = []
	s.from_start = func(c: Catalog, start: String, diff: String, ch: Dictionary, sd: int) -> Dictionary:
		calls.append([start, ch])
		return NewGame.from_start(c, start, diff, ch, sd)
	(box.get_node("Carpenter") as Button).pressed.emit()
	eq(s.start_id, "artisan_carpenter", "the carpenter's start")
	# población: the name and family proposed are the cast's (Cast.proposal of the screen's seed and start)
	var pro := Cast.proposal(cat, cat.starts()["artisan_carpenter"], "random", s.cast_seed())
	eq((s.get_node("%NameEdit") as LineEdit).text, str(pro["name_m"]), "its proposed name")
	eq((s.get_node("%FamilyEdit") as LineEdit).text, str(pro["family_name"]), "its proposed family")
	check(str(pro["family_name"]) in (cat.cast["surnames"]["trade"]["carpenter"] as Array), "a carpenter's surname")
	(box.get_node("Tailor") as Button).pressed.emit()
	eq(s.start_id, "artisan_tailor", "the tailor's")
	check(s.female, "the tailor's start is a woman")
	eq((s.get_node("%NameEdit") as LineEdit).text,
		str(Cast.proposal(cat, cat.starts()["artisan_tailor"], "random", s.cast_seed())["name_f"]), "her proposed name")
	(s.get_node("%FamilyEdit") as LineEdit).text = "Mora"
	(box.get_node("Mason") as Button).pressed.emit()
	eq((s.get_node("%FamilyEdit") as LineEdit).text, "Mora", "a family the player typed stays")
	s.start_game()
	eq(calls.size(), 1, "from_start called")
	if not calls.is_empty():
		eq(calls[0][0], "artisan_mason", "with the mason's start")
	s.free()


func test_new_game_screen_another_family() -> void:
	# Población: «Otra familia» rolls the cast again (name, family name, look and the town), the world seed stays.
	var s: NewGameScreen = (load("res://game/ui/new_game_screen.tscn") as PackedScene).instantiate()
	s.setup(cat, 7)
	var start: Dictionary = cat.starts()["artisan_blacksmith"]
	var first := Cast.proposal(cat, start, "random", Cast.sub_seed(7, 0))
	eq((s.get_node("%NameEdit") as LineEdit).text, str(first["name_m"]), "the first proposal")
	eq((s.get_node("%FamilyEdit") as LineEdit).text, str(first["family_name"]), "and its family")
	var btn := s.get_node("%RerollButton") as Button
	eq(btn.text, SimQuery.t_("ui.new_game.reroll"), "the button")
	btn.pressed.emit()
	var second := Cast.proposal(cat, start, "random", Cast.sub_seed(7, 1))
	eq(s.cast_roll, 1, "one more roll")
	eq((s.get_node("%NameEdit") as LineEdit).text, str(second["name_m"]), "another name")
	eq((s.get_node("%FamilyEdit") as LineEdit).text, str(second["family_name"]), "another family")
	(s.get_node("%Female") as Button).pressed.emit()
	eq((s.get_node("%NameEdit") as LineEdit).text, str(second["name_f"]), "a woman: the female name of the proposal")
	(s.get_node("%NameEdit") as LineEdit).text = "Oria"
	(s.get_node("%Male") as Button).pressed.emit()
	eq((s.get_node("%NameEdit") as LineEdit).text, "Oria", "a name the player typed stays when the sex changes")
	var calls: Array = []
	s.from_start = func(c: Catalog, st: String, diff: String, ch: Dictionary, sd: int) -> Dictionary:
		calls.append([ch, sd])
		return NewGame.from_start(c, st, diff, ch, sd)
	var started: Array = []
	s.started.connect(func(w: WorldState) -> void: started.append(w))
	s.start_game()
	eq(int(calls[0][1]), 7, "the same world seed")
	eq(int(calls[0][0]["cast_seed"]), Cast.sub_seed(7, 1), "the cast seed of the roll")
	var st: WorldState = started[0]
	eq(str(st.families["fam_0001"]["name"]), str(second["family_name"]), "the game takes the family proposed")
	var other: WorldState = NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast_seed": Cast.sub_seed(7, 0)}, 7)["state"]
	check(str(st.characters["chr_0003"]["name"]) + str(st.families["fam_0003"]["name"]) !=
		str(other.characters["chr_0003"]["name"]) + str(other.families["fam_0003"]["name"]), "and other neighbours")
	eq(str(st.rng.state), str(other.rng.state), "the world's rng is the same")
	s.free()
