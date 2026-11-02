extends "res://tests/test_case.gd"
## H7 · the player's actions on an NPC (GDD 4.11.5) and the SkillCheck (GDD 4.2.4): talk, gift, flatter, insult,
## threaten, with their range, once-a-day limits, relation and emotions.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	var sim := Sim.new(NewGame.from_scenario("plaza_dusk", 1)["state"], cat)
	return sim


## The food stall keeper (out at its trade) with the hero next to it.
func _pair(sim: Sim) -> String:
	var npc := TownLife.stall_keeper(sim.state, cat, "food")
	var pos: Array = sim.state.characters[npc]["position"]
	sim.state.characters[HERO]["location"] = ""
	sim.state.characters[HERO]["position"] = [int(pos[0]), int(pos[1]) + 2]
	return npc


func _o(type: String, npc: String, extra: Dictionary = {}) -> Dictionary:
	var o := {"type": type, "actor": HERO, "target": npc}
	o.merge(extra)
	return o


func test_talk_once_a_day_in_range() -> void:
	var sim := _sim()
	var npc := _pair(sim)
	var r := Orders.apply(sim, _o("npc_talk", npc))
	check(r["ok"], "talk (%s)" % r["reason"])
	eq(Emotions.relation(sim.state, HERO, npc), 2, "+2 relation")
	eq(Orders.apply(sim, _o("npc_talk", npc))["reason"], "already_today", "once per day")
	var far := _sim()
	var n2 := _pair(far)
	far.state.characters[HERO]["position"] = [2, 19]
	eq(Orders.apply(far, _o("npc_talk", n2))["reason"], "too_far", "out of range")
	Emotions.add(far, n2, "offended", FAM)
	far.state.characters[HERO]["position"] = far.state.characters[n2]["position"].duplicate()
	eq(Orders.apply(far, _o("npc_talk", n2))["reason"], "refuses_talk", "offended will not talk")


func test_gift_valuable_makes_grateful_cheap_adds_relation() -> void:
	var sim := _sim()
	var npc := _pair(sim)
	var inv: Dictionary = sim.state.characters[HERO]["inventory"]
	inv["stacks"] = []
	Inventory.add(inv, cat, "sword", 2, 1)
	Inventory.add(inv, cat, "bread", 0, 1)
	check(Market.price(sim, "sword", 2, "sell") > 50, "a good sword is worth more than 50")
	check(Orders.apply(sim, _o("npc_gift", npc, {"item": "sword", "quality": 2}))["ok"], "gift the sword")
	check(Emotions.has(sim, npc, "grateful", FAM), "a valuable gift: grateful (4.11.5)")
	eq(Inventory.count(inv, "sword"), 0, "the sword is gone")
	check(Orders.apply(sim, _o("npc_gift", npc, {"item": "bread", "quality": 0}))["ok"], "gift the bread")
	eq(Emotions.relation(sim.state, HERO, npc), 1, "a cheap gift: +1 relation")
	eq(Orders.apply(sim, _o("npc_gift", npc, {"item": "bread", "quality": 0}))["reason"], "no_item", "nothing left")


func test_insult_offends() -> void:
	var sim := _sim()
	var npc := _pair(sim)
	check(Orders.apply(sim, _o("npc_insult", npc))["ok"], "insult")
	eq(Emotions.relation(sim.state, HERO, npc), -10, "−10 (4.11.5 example)")
	check(Emotions.has(sim, npc, "offended", FAM), "offended")


func test_threaten_scares_or_angers() -> void:
	var seen := {}
	for minute: int in range(0, 40):
		var sim := _sim()
		var npc := _pair(sim)
		sim.state.clock["minute"] = int(sim.state.clock["minute"]) + minute
		check(Orders.apply(sim, _o("npc_threaten", npc))["ok"], "threaten")
		eq(Emotions.relation(sim.state, HERO, npc), -5, "−5 either way")
		var states: Array = Emotions.active(sim, npc, FAM).map(func(x: Dictionary) -> String: return str(x["state"]))
		eq(states.size(), 1, "one emotion")
		seen[str(states[0])] = true
	check(seen.has("scared"), "a successful threat scares")
	check(seen.has("angry"), "a failed threat angers [provisional]")


func test_flatter_by_skill_check() -> void:
	var results := {}
	for minute: int in range(0, 30):
		var sim := _sim()
		var npc := _pair(sim)
		sim.state.clock["minute"] = int(sim.state.clock["minute"]) + minute
		check(Orders.apply(sim, _o("npc_flatter", npc))["ok"], "flatter")
		results[Emotions.relation(sim.state, HERO, npc)] = true
		eq(Orders.apply(sim, _o("npc_flatter", npc))["reason"], "already_today", "once per day")
	eq(results.keys().size(), 2, "success (+3) and failure (−2) both happen")


func test_skill_check_follows_the_formula() -> void:
	var sim := _sim()
	var wins := 0
	var n := 2000
	for i: int in n:
		if bool(SkillCheck.roll(sim, "t|%d" % i, 7, 5)["success"]):
			wins += 1
	var p := float(wins) / n
	check(p > 0.55 and p < 0.65, "threshold 50 + (7 − 5) × 5 = 60 %% (%.3f)" % p)
	var r := SkillCheck.roll(sim, "fixed", 5, 5)
	eq(SkillCheck.roll(sim, "fixed", 5, 5)["roll"], r["roll"], "same key, same roll (deterministic)")
	var crit := 0
	for i: int in 1000:
		var x := SkillCheck.roll(sim, "c|%d" % i, 1, 10)
		if bool(x["success"]):
			crit += 1
			check(int(x["roll"]) <= 5, "with threshold 5 only criticals succeed")
	check(crit > 20 and crit < 90, "about 5 %% criticals (%d)" % crit)
