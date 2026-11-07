extends "res://tests/test_case.gd"
## 04c 4.21.6.5 and 4.21.10 (sim/ai/ascent.gd, AIAscent; the manager, 2026-11-07): an AI family whose next title lacks
## reputation works towards its workshop's next facade when, after paying it, it still has the title's price; the
## difficulty scales what it keeps after a title, a candidacy or a facade (Easy climbs later, Hard sooner).

const FAM: String = "fam_0002"  # Ferrer, rival_smith (asks for titles)

var cat := Catalog.load_from()


func _sim(difficulty: String = "normal") -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", difficulty, {"cast": "fixed"}, 1)["state"], cat)


func test_a_facade_when_the_reputation_is_short_and_the_title_money_stays() -> void:
	var sim := _sim()
	var st := sim.state
	var head := Kin.head(st, FAM)
	var home := Hostility._workshop_of(st, FAM)
	var prof := Hostility._profile(sim, FAM)
	st.families[FAM]["gold"] = 1000
	eq(AIAscent.facade(sim, FAM, head, home, prof), "forge_facade_1", "reputation short, gold enough: the first facade")
	var mats := AIAscent.materials(sim, home, "forge_facade_1")
	check(int(mats.get("stone", 0)) > 0, "its stone to buy (%s)" % mats)
	st.families[FAM]["gold"] = 150
	eq(AIAscent.facade(sim, FAM, head, home, prof), "", "not if it would eat the title's money")
	st.families[FAM]["gold"] = 1000
	Inventory.add(st.buildings[home]["inventory"], cat, "stone", 0, 10)
	eq(Upgrades.status_of(sim, head, home, "forge_facade_1"), "available", "its materials there: available")
	check(bool(Orders.apply(sim, {"type": "buy_upgrade", "actor": head, "building": home, "upgrade": "forge_facade_1"})["ok"]),
		"the works ordered as the player would")
	var other := Hostility._profile(sim, "fam_0011").duplicate(true)
	other["title_rule"]["requests"] = false
	eq(AIAscent.facade(sim, "fam_0011", Kin.head(st, "fam_0011"), Hostility._workshop_of(st, "fam_0011"), other), "",
		"a profile that does not ask for titles does not climb")


func test_the_difficulty_scales_the_climb() -> void:
	var m := {}
	for d: String in ["easy", "normal", "hard"]:
		m[d] = AIAscent.spare_mult(_sim(d))
	check(float(m["easy"]) > float(m["normal"]) and float(m["normal"]) > float(m["hard"]),
		"Easy keeps more, Hard less (%s)" % m)
	var easy := _sim("easy")
	var hard := _sim("hard")
	for s: Sim in [easy, hard]:
		s.state.families[FAM]["gold"] = 200  # citizen: 100 + spare 100 × mult (Hard 160, Easy 250)
		s.state.families[FAM]["reputation"] = 60
	var prof: Dictionary = cat.ai_profiles()["rival_smith"]
	check(RivalAI.wants_title(hard, FAM, prof), "Hard: with 200 gold it asks for its title")
	check(not RivalAI.wants_title(easy, FAM, prof), "Easy: with 200 gold it keeps saving")
