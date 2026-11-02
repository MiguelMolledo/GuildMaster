extends "res://tests/test_case.gd"
## H8 courtship and wedding (GDD 4.10.1-4.10.2; docs/contratos/h8_familia.md): talk once a day, gift, working near,
## the multipliers, the requirements, propose at 80 and what the wedding does.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func _sim(s: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario("courtship", s)["state"], cat)


func _named(sim: Sim, name: String) -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		if str(sim.state.characters[id]["name"]) == name:
			return id
	return ""


func test_talk_then_propose_then_wedding() -> void:
	var sim := _sim()
	var st := sim.state
	var agnes := _named(sim, "Agnès")
	var old_fam := str(st.characters[agnes]["family"])
	eq(Orders.apply(sim, {"type": "propose", "actor": HERO, "target": agnes})["reason"], "low_affinity", "76 is not 80")
	eq(Orders.apply(sim, {"type": "court_talk", "actor": HERO, "target": agnes})["ok"], true, "talk")
	var aff := Courtship.affinity(st, HERO, agnes)
	# Hugo: charisma 4 (×0.9), same title (×1.15): +3..5 -> +3..5
	check(aff >= 79 and aff <= 81, "76 + 3..5 × 0.9 × 1.15 (%d)" % aff)
	eq(Orders.apply(sim, {"type": "court_talk", "actor": HERO, "target": agnes})["reason"], "already_talked", "once a day")
	Courtship.relation(st, HERO, agnes)["affinity"] = 80
	eq(Orders.apply(sim, {"type": "propose", "actor": HERO, "target": agnes})["ok"], true, "propose at 80")
	eq([str(st.characters[HERO]["spouse"]), str(st.characters[agnes]["spouse"])], [agnes, HERO], "spouses")
	eq(str(st.characters[agnes]["family"]), FAM, "she joins the family")
	check(agnes in (st.families[FAM]["members"] as Array), "member")
	check(not agnes in (st.families[old_fam]["members"] as Array), "she left her household")
	eq(str(st.characters[agnes]["home"]), "", "her home is now the family residence")
	eq(Kin.home_of(sim, agnes), "bld_0001", "the forge")
	eq(str(st.characters[agnes]["controlled_by"]), "ai", "the spouse acts with AI")
	eq(Kin.group(st, FAM), [HERO], "and takes no group place (4.10.2)")
	eq(st.chronicle.filter(func(e: Dictionary) -> bool: return str(e["kind"]) == "wedding").size(), 1, "chronicle")
	eq(int(Dynasty.score(sim, FAM)["by_kind"].get("wedding", 0)), 20, "20 points")
	eq(Orders.apply(sim, {"type": "court_talk", "actor": HERO, "target": _named(sim, "Clara")})["reason"], "not_single",
		"married people do not court")


func test_requirements() -> void:
	var sim := _sim()
	var st := sim.state
	var joan := _named(sim, "Joan")
	var margarida := _named(sim, "Margarida")
	eq(Courtship.status(sim, HERO, joan), "same_sex", "opposite sex (provisional)")
	eq(Courtship.status(sim, HERO, margarida), "too_far", "Margarida lives across town")
	eq(Courtship.status(sim, HERO, HERO), "unknown_target", "not oneself")
	var agnes := _named(sim, "Agnès")
	st.characters[agnes]["birth_day"] = Kin.birth_day_for(15, int(st.clock["minute"]), cat.time)
	eq(Courtship.status(sim, HERO, agnes), "too_young", "16 at least")
	st.characters[agnes]["birth_day"] = Kin.birth_day_for(20, int(st.clock["minute"]), cat.time)
	st.emotions[agnes] = [{"state": "offended", "source": HERO, "intensity": 100}]
	eq(Courtship.status(sim, HERO, agnes), "offended", "a negative emotion blocks it")
	st.emotions.erase(agnes)
	var cands := Courtship.candidates(sim, HERO)
	eq(cands.size(), 8, "eight single women in town")
	eq(str(cands[0]["character"]), agnes, "Agnès first (most affinity)")


func test_gift_and_work_near() -> void:
	var sim := _sim()
	var st := sim.state
	var agnes := _named(sim, "Agnès")
	Courtship.relation(st, HERO, agnes)["affinity"] = 10
	eq(Orders.apply(sim, {"type": "court_gift", "actor": HERO, "target": agnes, "item": "iron", "quality": 0})["reason"],
		"not_enough", "nothing to give")
	Inventory.add(st.characters[HERO]["inventory"], cat, "sword", 0, 1)
	eq(Orders.apply(sim, {"type": "court_gift", "actor": HERO, "target": agnes, "item": "sword", "quality": 0})["ok"], true,
		"a sword")
	eq(Inventory.count(st.characters[HERO]["inventory"], "sword"), 0, "it leaves the actor")
	eq(Courtship.affinity(st, HERO, agnes), 10 + roundi(15 * 0.9 * 1.15), "a valuable gift: +15 × multipliers")
	# working near: Agnès at the forge's anvil while Hugo finishes a cycle at the furnace
	st.characters[agnes]["location"] = "bld_0001"
	st.buildings["bld_0001"]["zones"]["anvil"]["occupant"] = agnes
	sim.events = [{"type": "work_done", "actor": HERO, "building": "bld_0001", "zone": "furnace"}]
	var before := Courtship.affinity(st, HERO, agnes)
	Courtship.step(sim)
	eq(Courtship.affinity(st, HERO, agnes), before + 1, "+1 working near (1 × 0.9 × 1.15 rounds to 1)")
	Courtship.step(sim)
	eq(Courtship.affinity(st, HERO, agnes), before + 1, "once a day")


func test_charisma_raises_the_gain() -> void:
	var sim := _sim()
	var st := sim.state
	var agnes := _named(sim, "Agnès")
	Courtship.relation(st, HERO, agnes)["affinity"] = 0
	st.characters[HERO]["stats"]["charisma"] = 10
	Courtship.add_affinity(sim, HERO, agnes, 10, "test")
	eq(Courtship.affinity(st, HERO, agnes), roundi(10 * 1.5 * 1.15), "charisma 10: ×1.5")
