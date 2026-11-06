extends "res://tests/test_case.gd"
## The Rogue's first trade, the thief (docs/gdd/04d_otras_clases.md §4.22.6.4): picking a purse by day, robbing a
## storage at night, stolen goods (<item>@stolen) that no stall takes, the fence with its daily cap, laundering at the
## den, the underworld, and the watch that arrests whoever it sees (a trial with the guard as witness).

const DAY: int = 1440

var cat := Catalog.load_from()


func _game() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], cat)
	sim.step()
	return sim


func _of(evs: Array, type: String) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == type)


func _refused(evs: Array) -> String:
	var r := _of(evs, "order_refused")
	return str(r[0]["reason"]) if not r.is_empty() else ""


func _out(sim: Sim, c: String, tile: Array) -> void:
	var ch: Dictionary = sim.state.characters[c]
	ch["location"] = ""
	ch["path"] = []
	ch["position"] = tile.duplicate()


func _thief(sim: Sim, dex: int = 9, stealth: int = 9) -> String:
	var me := Kin.head(sim.state, SimQuery.player_family(sim.state))
	var stats: Dictionary = sim.state.characters[me]["stats"]
	stats["dexterity"] = dex
	stats["stealth"] = stealth
	return me


## A townsperson of no playing family, not a guard.
func _townsperson(sim: Sim) -> String:
	for c: String in Festivals._sorted_keys(sim.state.characters):
		var ch: Dictionary = sim.state.characters[c]
		var f := str(ch.get("family", ""))
		if f == "" or f == SimQuery.player_family(sim.state) or Watch.is_guard(sim.state, c) or not bool(ch.get("alive", true)):
			continue
		var fd: Dictionary = sim.state.families.get(f, {})
		if str(fd.get("controlled_by", "")) != "human" and str(fd.get("ai_profile", "")) == "" and int(ch.get("age", 30)) >= 16:
			return c
	return ""


func _no_guards_near(sim: Sim) -> void:
	for g: String in Watch.guards(sim.state):
		_out(sim, g, [1, 1])


func test_stolen_goods_are_their_item_but_marked() -> void:
	eq(cat.item("sword@stolen").get("base_price"), cat.item("sword").get("base_price"), "the catalog reads the piece")
	eq(Rogue.stolen("sword"), "sword@stolen", "marked")
	eq(Rogue.clean("sword@stolen"), "sword", "and clean")
	check(Rogue.is_stolen("sword@stolen") and not Rogue.is_stolen("sword"), "the mark")


func test_a_purse_picked_by_day() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := _thief(sim)
	var v := _townsperson(sim)
	check(v != "", "a townsperson")
	sim.state.clock["minute"] = 1 * DAY + 11 * 60
	_no_guards_near(sim)
	_out(sim, me, [19, 21])
	_out(sim, v, [20, 21])
	var gold := Money.gold(sim.state, fam)
	var o := {"type": "pickpocket", "actor": me, "target": v}
	var ev := sim.step([o])
	eq(_refused(ev), "", "he tries")
	var done := _of(ev, "pickpocket_done")
	check(not done.is_empty(), "Destreza 9 against a townsperson: the purse (%s)" % [_of(ev, "pickpocket_failed")])
	if not done.is_empty():
		var g := int(done[0]["gold"])
		check(g >= 5 and g <= 12, "5-12 gold from outside (%d)" % g)
		eq(Money.gold(sim.state, fam) - gold, g, "into his family's purse")
		eq(Rogue.underworld(sim.state, fam), 2, "+2 in the underworld")
	eq(_refused(sim.step([o])), "already_picked", "the same victim, once a day")
	sim.state.clock["minute"] = 2 * DAY + 2 * 60
	var v2 := v
	sim.state.town["rogue"] = {}
	_out(sim, me, [19, 21])
	_out(sim, v2, [20, 21])
	eq(_refused(sim.step([o])), "wrong_time", "not at night")


func test_seen_by_the_victim_and_arrested_by_the_guard() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := _thief(sim, 1, 1)
	var v := _townsperson(sim)
	sim.state.characters[v]["stats"]["empathy"] = 10
	sim.state.clock["minute"] = 1 * DAY + 11 * 60
	_no_guards_near(sim)
	var g: String = Watch.guards(sim.state)[0]
	_out(sim, me, [19, 21])
	_out(sim, v, [20, 21])
	_out(sim, g, [22, 21])
	Inventory.add(sim.state.characters[me]["inventory"], cat, "sword@stolen", 0, 1)
	var ev := sim.step([{"type": "pickpocket", "actor": me, "target": v}])
	check(not _of(ev, "pickpocket_failed").is_empty(), "Destreza 1 against Empatía 10: seen")
	check(Emotions.relation(sim.state, v, me) < 0, "the victim takes it badly")
	check((sim.state.justice.get("facts", []) as Array).any(func(f: Dictionary) -> bool:
		return str(f["charge"]) == "petty_theft" and str(f["family"]) == fam), "a public fact of pickpocketing")
	eq(_of(ev, "rogue_arrest_card").size(), 1, "the guard in view catches him: the player's card")
	ev = sim.step([{"type": "arrest_response", "actor": me, "choice": "surrender"}])
	var arrested := _of(ev, "rogue_arrested")
	eq(arrested.size(), 1, "he surrenders: arrested")
	if not arrested.is_empty():
		var t := Tribunal.trial(sim.state, str(arrested[0]["trial"]))
		eq(str(t.get("source", "")), "arrest", "a trial from the arrest")
		check((t["witnesses"] as Array).any(func(w: Dictionary) -> bool: return str(w["character"]) == g), "the guard is a witness")
		eq(Inventory.count(sim.state.characters[me]["inventory"], "sword@stolen"), 0, "the stolen sword seized")


func test_a_storage_robbed_at_night() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := _thief(sim)
	var rival := ""
	for b: String in Festivals._sorted_keys(sim.state.buildings):
		var o := Money.family_of(sim.state, b)
		if o != "" and o != fam and str(sim.state.families[o].get("ai_profile", "")) != "":
			rival = b
			break
	check(rival != "", "a rival's workshop")
	var store: Dictionary = sim.state.buildings[rival]["inventory"]
	Inventory.add(store, cat, "sword", 1, 3)
	sim.state.clock["minute"] = 1 * DAY + 23 * 60
	_no_guards_near(sim)
	var door: Array = sim.state.buildings[rival]["door"]
	_out(sim, me, door)
	var o := {"type": "burgle", "actor": me, "building": rival}
	var ev := sim.step([o])
	eq(_refused(ev), "", "at its door at night")
	var done := _of(ev, "burgle_done")
	check(not done.is_empty(), "Sigilo 9 against its lock: in (%s)" % [_of(ev, "burgle_failed")])
	var bag: Dictionary = sim.state.characters[me]["inventory"]
	check(Inventory.count(bag, "sword@stolen") > 0, "the swords, marked, in his bag")
	eq(Inventory.count(bag, "sword"), 0, "none clean")
	eq(_refused(sim.step([o])), "recently_robbed", "not again so soon")
	sim.state.clock["minute"] = 2 * DAY + 11 * 60
	eq(Rogue.burgle_reason(sim, me, rival), "wrong_time", "not by day")


func test_the_fence_and_its_cap() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := _thief(sim)
	var tav := ""
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b].get("type", "")) == "tavern_inn":
			tav = b
	check(tav != "", "the tavern")
	Inventory.add(sim.state.characters[me]["inventory"], cat, "sword@stolen", 0, 6)
	sim.state.clock["minute"] = 1 * DAY + 11 * 60
	var ch: Dictionary = sim.state.characters[me]
	ch["location"] = tav
	var o := {"type": "fence_sell", "actor": me, "item": "sword", "quality": 0, "qty": 1}
	eq(_refused(sim.step([o])), "no_fence", "by day the tavern has no fence")
	sim.state.clock["minute"] = 1 * DAY + 23 * 60
	ch["location"] = tav
	var unit := Rogue.fence_price(sim, fam, "sword@stolen", 0)
	eq(unit, roundi(Market.price(sim, "sword", 0, "sell") * 0.5), "half the market's price")
	var gold := Money.gold(sim.state, fam)
	var ev := sim.step([o])
	eq(_refused(ev), "", "at night, in the tavern")
	eq(Money.gold(sim.state, fam) - gold, unit, "paid")
	var all := {"type": "fence_sell", "actor": me, "item": "sword", "quality": 0, "qty": 5}
	ev = sim.step([all])
	var sold := _of(ev, "fence_sold")
	check(not sold.is_empty() and int(sold[0]["qty"]) * unit + unit <= 150, "up to the daily cap")
	eq(_refused(sim.step([all])), "fence_full" if Inventory.count(ch["inventory"], "sword@stolen") > 0 else "not_enough",
		"then no more today")


func test_laundering_at_the_den() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := _thief(sim)
	var den := ""
	for b: String in sim.state.buildings:
		if Money.family_of(sim.state, b) == fam:
			den = b
	sim.state.buildings[den]["type"] = "den"  # the test's den: his own building
	sim.state.characters[me]["location"] = den
	Inventory.add(sim.state.characters[me]["inventory"], cat, "sword@stolen", 0, 1)
	var ev := sim.step([{"type": "launder", "actor": me, "building": den, "item": "sword", "quality": 0}])
	eq(_refused(ev), "", "at his bench")
	eq(_refused(sim.step([{"type": "launder", "actor": me, "building": den, "item": "sword", "quality": 0}])), "busy",
		"one at a time")
	for i: int in 31:
		sim.step()
	eq(Inventory.count(sim.state.buildings[den]["inventory"], "sword", 0), 1, "clean, in the den's storage")
	eq(Inventory.count(sim.state.characters[me]["inventory"], "sword@stolen"), 0, "the marked one is gone")


## The arrest card (4.22.6.3): a person's family answers it; unanswered, it surrenders.
func _caught(sim: Sim) -> Dictionary:
	var fam := SimQuery.player_family(sim.state)
	var me := _thief(sim, 1, 1)
	var v := _townsperson(sim)
	sim.state.characters[v]["stats"]["empathy"] = 10
	sim.state.clock["minute"] = 1 * DAY + 11 * 60
	_no_guards_near(sim)
	var g: String = Watch.guards(sim.state)[0]
	_out(sim, me, [19, 21])
	_out(sim, v, [20, 21])
	_out(sim, g, [22, 21])
	sim.state.families[fam]["controlled_by"] = "human"
	var ev := sim.step([{"type": "pickpocket", "actor": me, "target": v}])
	return {"me": me, "guard": g, "fam": fam, "ev": ev}


func test_the_arrest_card_waits_for_the_answer() -> void:
	var sim := _game()
	var c := _caught(sim)
	var me := str(c["me"])
	eq(_of(c["ev"], "rogue_arrest_card").size(), 1, "the card of the arrest")
	eq(_of(c["ev"], "rogue_arrested").size(), 0, "nobody is tried yet")
	var odds := Rogue.arrest_odds(sim, me, str(c["guard"]))
	check(float(odds["flee"]) > 0.0 and float(odds["bribe"]) > 0.0 and int(odds["bribe_price"]) > 0, "the odds it shows")
	var tried := false
	for i: int in 31:
		for e: Dictionary in sim.step():
			if str(e.get("type", "")) == "rogue_arrested":
				tried = true
	check(tried, "unanswered in half an hour: he surrenders and is tried")


func test_bribing_the_guard() -> void:
	var sim := _game()
	var c := _caught(sim)
	var me := str(c["me"])
	sim.state.characters[me]["stats"]["negotiation"] = 10
	sim.state.families[str(c["fam"])]["gold"] = 500
	var price := int(Rogue.arrest_odds(sim, me, str(c["guard"]))["bribe_price"])
	var gold := Money.gold(sim.state, str(c["fam"]))
	var ev := sim.step([{"type": "arrest_response", "actor": me, "choice": "bribe"}])
	eq(_refused(ev), "", "he offers the bribe")
	var ans := _of(ev, "arrest_answered")
	eq(ans.size(), 1, "answered")
	eq(Money.gold(sim.state, str(c["fam"])), gold - price, "the bribe is paid")
	if not ans.is_empty() and str(ans[0]["outcome"]) == "bribed":
		eq(_of(ev, "rogue_arrested").size(), 0, "let go: no trial")
	eq(_refused(sim.step([{"type": "arrest_response", "actor": me, "choice": "flee"}])), "no_arrest", "once")
