extends "res://tests/test_case.gd"
const Pins = preload("res://tests/balance_pins.gd")
## A new game from a start (GDD 4.16, 4.23, D5): the 3 difficulties, the new-game choices and their validation,
## the town, the family, the forge, the rival, the loan, the scripted contracts and the objective chain.

const FAM := "fam_0001"
const HUGO := "chr_0001"
const FORGE := "bld_0001"

var cat := Pins.classic(Catalog.load_from())  # pre-H5 figures: see tests/balance_pins.gd
var start: Dictionary = cat.starts()["artisan_blacksmith"]


func _new(difficulty: String, choices: Dictionary = {}, world_seed: int = 1) -> Dictionary:
	return NewGame.from_start(cat, "artisan_blacksmith", difficulty, choices, world_seed)


func test_three_difficulties() -> void:
	for lvl: String in ["easy", "normal", "hard"]:
		var r := _new(lvl)
		check(r["ok"], "%s starts: %s" % [lvl, r.get("error", "")])
		var st: WorldState = r["state"]
		var levers := cat.difficulty_levels(lvl)
		eq(st.difficulty, lvl, "%s saved" % lvl)
		eq(int(st.loans["lon_0001"]["principal"]), int(levers["start_debt"]), "%s debt" % lvl)
		for f: String in st.families:  # H12: the rival smith and the competitors (the heads of the AI families with a profile)
			if str(st.families[f].get("ai_profile", "")) == "":
				continue
			var rival := str(st.families[f]["head"])
			eq(int(st.characters[rival]["stats"]["craft"]), int(levers["rival_craft"]), "%s rival craft (%s)" % [lvl, f])
		eq(Money.gold(st, FAM), 30, "%s: 30 gold" % lvl)
		var sim := Sim.new(st, cat)
		sim.run_minutes(Clock.MINUTES_PER_DAY)  # a whole day runs without errors
	eq([int(_new("easy")["state"].loans["lon_0001"]["principal"]), int(_new("hard")["state"].loans["lon_0001"]["principal"])],
		[100, 300], "100 easy, 300 hard")
	eq(_new("impossible"), {"ok": false, "error": "unknown_difficulty"}, "unknown difficulty")
	eq(NewGame.from_start(cat, "nope", "normal", {}, 1), {"ok": false, "error": "unknown_start"}, "unknown start")


func test_the_town_at_dawn_of_day_one() -> void:
	var st: WorldState = _new("normal")["state"]
	eq(st.map_id, "town_e", "the map")
	eq(int(st.clock["minute"]), int(cat.time["phase_starts"]["spring"]["dawn"]), "dawn of day 1 of spring")
	var hero: Dictionary = st.characters[HUGO]
	eq([hero["name"], hero["female"], hero["family"], hero["controlled_by"], hero["location"]],
		["Hugo", false, FAM, "human", ""], "the default protagonist")
	eq(hero["position"], cat.maps()["town_e"]["spawns"]["player"], "at the player spawn")
	eq(hero["stats"], start["protagonist"]["stats"], "the artisan's stats")
	eq(hero["equipment"]["tool"], {"item": "hammer", "quality": 0}, "the hammer equipped")
	var sim := Sim.new(st, cat)
	near(Equipment.max_weight(sim, HUGO), 30.0, 0.001, "carries 30 kg with the hammer")
	var fam: Dictionary = st.families[FAM]
	eq([fam["name"], fam["controlled_by"], fam["members"], int(fam["reputation"]), fam["ai_profile"]],
		["Herrero", "human", [HUGO], 0, ""], "the player's family")
	var forge: Dictionary = st.buildings[FORGE]
	eq([forge["type"], forge["owner"], forge["origin"], forge["door"], forge["state"]],
		["forge", FAM, [25, 20], [26, 19], "normal"], "the forge in its site")
	eq([Inventory.count(forge["inventory"], "iron"), Inventory.count(forge["inventory"], "coal")], [8, 4], "its stock")
	eq((forge["zones"] as Dictionary).keys().size(), 4, "its stations")
	var rival_fam := ""
	for f: String in st.families:
		if f != FAM and str(st.families[f].get("ai_profile", "")) == "rival_smith":
			rival_fam = f  # H4: the household families of the townsfolk are AI families without a profile; H12: the competitors have rival_artisan
	var rf: Dictionary = st.families[rival_fam]
	eq([rf["name"], rf["controlled_by"], rf["ai_profile"], int(rf["gold"])], ["Ferrer", "ai", "rival_smith", 80], "rival")
	var bernat: Dictionary = st.characters[str(rf["members"][0])]
	eq([bernat["name"], bernat["controlled_by"]], ["Bernat", "ai"], "Bernat")
	eq(Money.family_of(st, str(bernat["location"])), rival_fam, "inside his forge")
	var armory := ""
	for b: String in st.buildings:
		if str(st.buildings[b]["type"]) == "armory":
			armory = b
	check(armory != "" and str(st.buildings[armory]["owner"]) == "", "the public armory")
	eq(st.buildings.size(), 3 + 8 + 3, "3 buildings, the 8 townsfolk houses (H4) and the 3 competitor workshops (H12)")
	eq(st.characters.size(), 2 + 16 + 6, "the protagonist, the rival, 16 townsfolk (H4) and 3 competitor couples (H12)")


func test_scripted_contracts_and_objectives() -> void:
	var st: WorldState = _new("normal")["state"]
	var sim := Sim.new(st, cat)
	var board: Array = st.contracts["board"]
	eq(board.size(), 2, "2 scripted contracts")
	var c: Dictionary = board[0]
	eq([c["id"], c["client"], c["item"], int(c["qty"]), int(c["min_quality"]), int(c["deadline_days"]), c["script"],
		c["family"], int(c["accepted"]), int(c["due"]), int(c["posted"])],
		["ctr_0001", "carpenter", "hammer", 2, 0, 2, "carpenter_hammers", "", -1, -1, 0], "the carpenter's")
	var premium := float(cat.contracts()["blacksmith"]["premium"])
	eq(int(c["pay"]), roundi(2 * Market.price(sim, "hammer", 0, "sell") * (1.0 + premium)), "pay with the premium")
	eq([board[1]["script"], int(board[1]["min_quality"])], ["guard_good_sword", 1], "the good sword")
	eq(Objectives.view(sim, FAM), {"current": "forge_sword", "done": [], "progress": [{"have": 0, "need": 2},
		{"have": 0, "need": 1}]}, "the chain starts")


func test_choices() -> void:
	var colors := {"primary": "#112233", "secondary": "#abcdef"}
	var r := _new("normal", {"name": "Aina", "female": true, "family_name": "Vives", "colors": colors,
		"stats_add": {"craft": 3, "charisma": 2}})
	check(r["ok"], "valid choices")
	var st: WorldState = r["state"]
	var hero: Dictionary = st.characters[HUGO]
	eq([hero["name"], hero["female"]], ["Aina", true], "name and gender")
	eq([st.families[FAM]["name"], st.families[FAM]["colors"]], ["Vives", colors], "family name and colours")
	eq([int(hero["stats"]["craft"]), int(hero["stats"]["charisma"])], [10, 6], "7+3, 4+2")
	check(_new("normal", {"stats_add": {"craft": 1}})["ok"], "fewer points than free is fine")
	var bad := [
		{"stats_add": {"craft": 4}},                         # 7 + 4 > 10
		{"stats_add": {"charisma": 3, "empathy": 3}},        # 6 > 5 free points
		{"stats_add": {"luck": 1}},                          # unknown stat
		{"stats_add": {"craft": -1}},                        # negative
		{"stats_add": {"craft": 1.5}},                       # not whole
		{"stats_add": "craft"},                              # not a dictionary
		{"name": "  "},                                      # empty name
		{"family_name": ""},                                 # empty family name
		{"colors": {"primary": "red?", "secondary": "#000000"}},
		{"colors": {"primary": "#000000"}},
	]
	for b: Dictionary in bad:
		eq(_new("normal", b), {"ok": false, "error": "bad_choices"}, "refused: %s" % str(b))


func test_deterministic() -> void:
	var a := Sim.new(_new("hard", {}, 5)["state"], cat)
	var b := Sim.new(_new("hard", {}, 5)["state"], cat)
	eq(a.state_hash(), b.state_hash(), "same start, same state")
	a.run_minutes(600)
	b.run_minutes(600)
	eq(a.state_hash(), b.state_hash(), "and the same game")
