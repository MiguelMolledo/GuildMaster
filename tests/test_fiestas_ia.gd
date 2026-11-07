extends "res://tests/test_case.gd"
## Fiestas · the AI families and the festivals (04f 4.25.4, owner 2026-11-05): a festival contract only if it gets it
## done in time with the real work minutes of its workshop until its hour, and if after buying the inputs it keeps
## the reserve of 3 days of upkeep; under the reserve, recovery mode (the cheapest sellable piece, and sell); the AI's
## sponsoring keeps the same reserve. The wedding banquet's button says why it is off.

const DAY: int = 1440

const Pins = preload("res://tests/balance_pins.gd")
var cat := Pins.no_ramp(Catalog.load_from())  # a whole day's upkeep from day 1: see tests/balance_pins.gd


func _game(c: Catalog = null) -> Sim:
	var k := c if c != null else cat
	var r := NewGame.from_start(k, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], k)
	sim.step()
	return sim


func _rival(sim: Sim) -> String:
	for f: String in Festivals._sorted_keys(sim.state.families):
		if str(sim.state.families[f].get("ai_profile", "")) != "":
			return f
	return ""


func _profile(sim: Sim, fam: String) -> Dictionary:
	return sim.catalog.ai_profiles()[str(sim.state.families[fam]["ai_profile"])]


func _empty_stock(sim: Sim, actor: String, home: String) -> void:
	(sim.state.buildings[home]["inventory"]["stacks"] as Array).clear()
	(sim.state.characters[actor]["inventory"]["stacks"] as Array).clear()


## A race contract for a piece of the rival's own trade (the first recipe of its workshop with inputs), due at `due`.
func _race(sim: Sim, actor: String, home: String, due: int) -> Dictionary:
	var item := ""
	for rid: String in RivalAI._home_recipes(sim, actor, home):
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("kind", "craft")) != "commission" and not (r.get("inputs", []) as Array).is_empty():
			item = str(r["output"]["item"])
			break
	return {"id": "ctr_test", "item": item, "qty": 1, "min_quality": 0, "race": true, "due_at": due,
		"deadline_days": maxi(1, ceili(float(due - int(sim.state.clock["minute"])) / DAY))}


func test_a_festival_contract_only_with_the_upkeep_reserve() -> void:
	var sim := _game()
	var fam := _rival(sim)
	var f: Dictionary = sim.state.families[fam]
	var actor := RivalAI._actor(sim, f)
	var home := RivalAI._home(sim, fam)
	var prof := _profile(sim, fam)
	_empty_stock(sim, actor, home)
	var c := _race(sim, actor, home, int(sim.state.clock["minute"]) + 2 * DAY)
	check(str(c["item"]) != "", "a piece of its trade")
	var upkeep := int(Upkeep.due_next_dawn(sim, fam)["total"])
	check(upkeep > 0, "its workshop pays upkeep (%d)" % upkeep)
	eq(RivalAI.upkeep_reserve(sim, fam, prof), int(prof.get("gold_reserve", 0)) + 3 * upkeep,
		"the reserve: gold_reserve + 3 days of upkeep")
	f["gold"] = RivalAI.upkeep_reserve(sim, fam, prof)  # the inputs would eat the reserve
	check(not RivalAI.makes_in_time(sim, fam, actor, home, prof, c), "without the reserve after the inputs: no")
	var plain := c.duplicate()
	plain.erase("race")
	check(RivalAI.makes_in_time(sim, fam, actor, home, prof, plain), "a plain contract keeps its rule (gold_reserve)")
	f["gold"] = 5000
	check(RivalAI.makes_in_time(sim, fam, actor, home, prof, c), "with gold to spare: yes")


func test_a_festival_contract_only_in_the_real_hours() -> void:
	var sim := _game()
	var fam := _rival(sim)
	var f: Dictionary = sim.state.families[fam]
	f["gold"] = 5000
	var actor := RivalAI._actor(sim, f)
	var home := RivalAI._home(sim, fam)
	var prof := _profile(sim, fam)
	var day0 := Clock.day(int(sim.state.clock["minute"])) * DAY
	sim.state.clock["minute"] = day0 + 6 * 60  # before the day phase: a whole day's work ahead
	eq(RivalAI.work_minutes_until(sim, prof, day0 + DAY + 6 * 60), RivalAI.work_minutes_per_day(sim, prof),
		"a whole day ahead has the work minutes of a day")
	eq(RivalAI.work_minutes_until(sim, prof, day0 + 6 * 60 + 30), 0, "half an hour of the night has none")
	var c := _race(sim, actor, home, day0 + 9 * 60)  # due this morning: deadline_days rounds it to a whole day
	eq(int(c["deadline_days"]), 1, "the rounded day")
	check(not RivalAI.makes_in_time(sim, fam, actor, home, prof, c), "but the real hours are not enough: no")
	c["due_at"] = day0 + 2 * DAY + 6 * 60
	check(RivalAI.makes_in_time(sim, fam, actor, home, prof, c), "two days ahead: yes")


func test_under_the_reserve_it_recovers_with_the_cheapest_piece() -> void:
	var sim := _game()
	var fam := _rival(sim)
	var f: Dictionary = sim.state.families[fam]
	var actor := RivalAI._actor(sim, f)
	var home := RivalAI._home(sim, fam)
	var prof := _profile(sim, fam)
	_empty_stock(sim, actor, home)
	f["gold"] = int(prof.get("gold_reserve", 0)) + 5
	sim.state.clock["minute"] = Clock.day(int(sim.state.clock["minute"])) * DAY + 10 * 60  # the market is open
	var ai := {}
	RivalAI._decide(sim, fam, actor, home, prof, ai, "day")
	check(bool(ai["recovering"]), "under the reserve and unable to pay its recipe: recovery")
	var cheap := RivalAI.recovery_recipe(sim, fam, actor, home)
	check(cheap != "", "a sellable piece it can pay")
	eq(str(ai["recipe"]), cheap, "it works the cheapest sellable piece")
	for rid: String in RivalAI._home_recipes(sim, actor, home):
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("kind", "craft")) == "commission" or RivalAI.margin(sim, rid) <= 0 \
				or RivalAI.stall_for(sim, str(r["output"]["item"])) == "":
			continue
		var cost := RivalAI._cycle_cost(sim, actor, home, rid)
		check(cost > Money.gold(sim.state, fam) or cost >= RivalAI._cycle_cost(sim, actor, home, cheap),
			"none cheaper (%s %d)" % [rid, cost])
	var need := RivalAI.buy_needs(sim, fam, actor, home, prof, ai)
	var one := {}
	RivalAI._add_inputs(sim, one, cheap, 1)
	eq(need, one, "just enough for one piece")
	check("buy" in (ai["plan"] as Array) and "sell" in (ai["plan"] as Array), "it buys and sells")
	f["gold"] = 5000
	RivalAI._decide(sim, fam, actor, home, prof, ai, "day")
	check(not bool(ai["recovering"]), "with gold, back to its best margin")


func test_in_recovery_it_never_stands_still() -> void:
	var sim := _game()
	var fam := _rival(sim)
	var f: Dictionary = sim.state.families[fam]
	var actor := RivalAI._actor(sim, f)
	var home := RivalAI._home(sim, fam)
	_empty_stock(sim, actor, home)
	f["gold"] = int(_profile(sim, fam).get("gold_reserve", 0)) + 5
	var bought := 0
	var made := 0
	for i: int in 2 * DAY:
		for e: Dictionary in sim.step():
			if str(e.get("family", "")) == fam and str(e["type"]) == "market_bought":
				bought += 1
			if str(e["type"]) == "work_done" and str(e.get("building", "")) == home:
				made += 1
	check(bought > 0, "it buys what its cheapest piece needs (%d)" % bought)
	check(made > 0, "and makes it (%d)" % made)


func test_the_ai_sponsors_only_over_the_same_reserve() -> void:
	var c2 := Catalog.load_from()
	c2.festivals["rules"]["ai_sponsor"]["chance"] = 1.0
	var sim := _game(c2)
	var spare := int(c2.festivals["rules"]["ai_sponsor"].get("spare", 150))
	var cost := int(c2.festivals["rules"]["sponsor"]["parts"]["banquet"]["gold"])
	var first := _rival(sim)
	for f: String in sim.state.families:  # enough under the old rule (gold_reserve + spare), not with the upkeep
		if str(sim.state.families[f].get("ai_profile", "")) != "":
			sim.state.families[f]["gold"] = int(_profile(sim, f).get("gold_reserve", 0)) + spare + cost
	var s3 := _game(c2)
	for f: String in s3.state.families:
		if str(s3.state.families[f].get("ai_profile", "")) != "":
			s3.state.families[f]["gold"] = sim.state.families[f]["gold"]
	s3.state.families[first]["gold"] = RivalAI.upkeep_reserve(s3, first, _profile(s3, first)) + spare + cost
	for s: Sim in [sim, s3]:
		while int(s.state.clock["minute"]) < 12 * 60 + 2:
			s.state.clock["minute"] = int(s.state.clock["minute"]) + 1
			s.events = []
			Festivals.step(s)
	eq(Festivals.part_taken_by(Festivals.announced(sim)[0], "banquet"), "", "without the upkeep reserve nobody pays")
	eq(Festivals.part_taken_by(Festivals.announced(s3)[0], "banquet"), first, "with it, the rival pays the banquet")


func test_the_banquet_button_says_why_it_is_off() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var head := Kin.head(sim.state, fam)
	var gold := int(Festivals.rules(sim)["wedding"]["player_feast_gold"])
	sim.state.families[fam]["gold"] = gold - 30
	var page := FestivalPage._wedding(sim, {"couple": [head, head], "family": fam})
	var btn: Dictionary = (page["buttons"] as Array).filter(func(b: Dictionary) -> bool: return str(b["id"]) == "host_wedding")[0]
	check(bool(btn["disabled"]), "off without the gold")
	var why := FestivalPage.gold_reason(sim, fam, gold)
	check(why != "" and str(gold) in why and str(gold - 30) in why, "the reason with the price and the gold (%s)" % why)
	eq(str(btn["tip"]), why, "in its tooltip")
	check((page["blocks"] as Array).any(func(b: Dictionary) -> bool: return str(b.get("text", "")) == why),
		"and in the card's text")
	sim.state.families[fam]["gold"] = gold + 100
	page = FestivalPage._wedding(sim, {"couple": [head, head], "family": fam})
	btn = (page["buttons"] as Array).filter(func(b: Dictionary) -> bool: return str(b["id"]) == "host_wedding")[0]
	check(not bool(btn["disabled"]), "on with the gold")
	eq((page["blocks"] as Array).size(), 1, "no reason then")
