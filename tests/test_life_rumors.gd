extends "res://tests/test_case.gd"
## Vida (docs/gdd/04f_vida_y_fiestas.md §4.24.2): meeting points and rumours. Every region map and town_e have the new
## meeting points and patrols (town_e keeps H7's six points as they were); a corrillo of two tells a rumour about
## something that happened (the chronicle) and the player's people within 4 tiles hear it: once, into the book.

const DAY := 1440
const HERO := "chr_0001"


func _sim(scenario: String = "town_e_start") -> Sim:
	var cat := Catalog.load_from()
	var r := NewGame.from_scenario(scenario, 1)
	check(bool(r["ok"]), "scenario loads")
	return Sim.new(r["state"], cat)


func test_maps_have_meeting_points_and_patrols() -> void:
	var cat := Catalog.load_from()
	for id: String in ["town_e", "region_capital", "region_port", "region_quarry", "region_hamlet", "region_abbey"]:
		var m: Dictionary = cat.maps().get(id, {})
		var kinds := {}
		for p: Dictionary in m.get("social_points", []):
			kinds[str(p["kind"])] = true
		for k: String in ["well", "atrium", "washhouse", "gate", "square"]:
			check(kinds.has(k), "%s has a %s point" % [id, k])
		check((m.get("patrols", []) as Array).size() >= 1, "%s has patrols" % id)
	var e: Array = cat.maps()["town_e"]["social_points"]
	eq([e[0]["id"], e[1]["id"], e[2]["id"], e[3]["id"], e[4]["id"], e[5]["id"]],
		["bench_w", "bench_e", "bench_n", "chat_well", "chat_board", "dice_plaza"], "town_e keeps H7's points first")


func test_a_corrillo_tells_and_the_player_hears_it_once() -> void:
	var sim := _sim()
	var st := sim.state
	Life.ensure(st)
	Chronicle.add(st, "wedding", {"family": "fam_0001", "character": HERO, "spouse": "chr_0002", "from_family": ""})
	var p: Dictionary = Life.points(sim, ["well"])[0]
	var folk := Population.townsfolk(st)
	var a := str(folk[0])
	var b := str(folk[1])
	for c: Array in [[a, p["slots"][0]], [b, p["slots"][1]]]:
		var ch: Dictionary = st.characters[c[0]]
		ch["location"] = ""
		ch["path"] = []
		ch["position"] = [int(c[1][0]), int(c[1][1])]
	st.characters[HERO]["location"] = ""
	st.characters[HERO]["path"] = []
	st.characters[HERO]["position"] = [int(p["slots"][0][0]) + 2, int(p["slots"][0][1])]
	st.clock["minute"] = 600
	var groups := Rumors.corrillos(sim)
	check((groups.get(str(p["id"]), []) as Array).size() >= 2, "two people at the well make a corrillo")
	var cands := Rumors.candidates(sim, 600)
	check(cands.any(func(c: Dictionary) -> bool: return str(c["rumor"]) == "wedding"), "the wedding is talked about")
	Rumors._tell(sim, 600)
	var told: Dictionary = st.town["rumors"]["told"].get(str(p["id"]), {})
	check(not told.is_empty(), "the corrillo tells a rumour")
	Rumors._hear(sim, 601)
	eq((st.town["rumors"]["heard"] as Array).size(), 1, "the hero hears it")
	Rumors._hear(sim, 602)
	eq((st.town["rumors"]["heard"] as Array).size(), 1, "only once")
	check(LifeQuery.rumor_text(sim, st.town["rumors"]["heard"][0]) != "", "its sentence reads")


func test_rumours_come_from_true_facts() -> void:
	var sim := _sim()
	var st := sim.state
	Life.ensure(st)
	var cands := Rumors.candidates(sim, int(st.clock["minute"]))
	for c: Dictionary in cands:
		check(str(c["rumor"]) in ["prices", "contract", "debt", "election", "event", "visitor", "visitor_prices"],
			"with an empty chronicle only the state talks (%s)" % c["rumor"])
	Incidents.book(st)["warned"]["test"] = {"until": int(st.clock["minute"]) + 60, "place_key": "nest.r4", "def": "bandit_raid"}
	cands = Rumors.candidates(sim, int(st.clock["minute"]))
	check(cands.any(func(c: Dictionary) -> bool: return str(c["rumor"]) == "bandits_seen"), "a planned raid is rumoured")


func test_a_day_of_corrillos_fills_the_book() -> void:
	var sim := _sim()
	sim.state.characters[HERO]["location"] = ""
	var told := 0
	for i: int in DAY:
		if i % 30 == 0:  # the hero walks round the meeting points
			var pts := Life.points(sim, ["well", "chat", "atrium", "washhouse", "gate"])
			var p: Dictionary = pts[(i / 30) % pts.size()]
			sim.state.characters[HERO]["location"] = ""
			sim.state.characters[HERO]["path"] = []
			sim.state.characters[HERO]["position"] = [int(p["slots"][0][0]), int(p["slots"][0][1]) + 1]
		for e: Dictionary in sim.step():
			if str(e.get("type", "")) == "rumor_told":
				told += 1
	check(told >= 5, "corrillos tell rumours through the day (%d)" % told)
	check(Rumors.heard(sim.state).size() >= 1, "the hero heard some")
