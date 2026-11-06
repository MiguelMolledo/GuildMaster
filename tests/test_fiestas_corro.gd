extends "res://tests/test_case.gd"
## Fiestas · the corro in the plaza (owner, 2026-11-06): while a feast is on, the family plays the tavern's games in the
## plaza against the regulars (game_play with opts.corro): no house and no cut, never on the eve nor after it, and with
## the preacher in town each game costs reputation. The card's «Corro de juego» opens its games on a second card.

const DAY: int = 1440

var cat := Catalog.load_from()


func _init() -> void:
	GameMatch.verbose = false
	Duel.verbose = false


func _game() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], cat)
	sim.step()
	return sim


func _fest_to(sim: Sim, minute: int) -> void:
	while int(sim.state.clock["minute"]) < minute:
		sim.state.clock["minute"] = int(sim.state.clock["minute"]) + 1
		sim.events = []
		Festivals.step(sim)


func _of(evs: Array, type: String) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == type)


func _refused(evs: Array) -> String:
	var r := _of(evs, "order_refused")
	return str(r[0]["reason"]) if not r.is_empty() else ""


func _play(me: String, g: String, inst_id: String, opponents: Array, extra: Dictionary = {}) -> Dictionary:
	var opts := {"corro": inst_id}
	opts.merge(extra, true)
	return {"type": "game_play", "actor": me, "game": g, "opponents": opponents, "stake": 5, "opts": opts, "auto": true}


func test_the_corro_is_played_while_the_feast_is_on() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	sim.state.families[fam]["gold"] = 300
	var id := Festivals._schedule(sim, "comedians", 2, "test")
	var inst := Festivals.find(sim, id)
	eq(FestivalCorro.reason(sim, me, "pulso", id), "no_feast", "not before the feast")
	_fest_to(sim, int(inst["start"]) + 30)
	eq(FestivalCorro.reason(sim, me, "pulso", id), "", "on its day, yes")
	eq(FestivalCorro.reason(sim, me, "joust", id), "unknown_game", "only the tavern's games")
	for g: String in ["pulso", "azar", "mayor", "envite"]:
		var opp := FestivalCorro.opponents(sim, inst, me, g)
		eq(opp.size(), 2 if g == "mayor" else 1, "%s: its regulars" % g)
		var gold := Money.gold(sim.state, fam)
		var ev := sim.step([_play(me, g, id, opp)])
		eq(_refused(ev), "", "%s in the corro" % g)
		var played := _of(ev, "game_played")
		eq(played.size(), 1, "%s played" % g)
		if not played.is_empty():
			eq(int(played[0]["house_cut"]), 0, "%s: nobody takes a cut" % g)
			eq(Money.gold(sim.state, fam) - gold, int(played[0]["net"]) + int(played[0]["bets_net"]) - int(played[0]["entry"]),
				"%s: the family wins or loses its net" % g)
		eq(_of(ev, "game_corro").size(), 1, "%s: told as a corro" % g)
	var bld := ""
	for b: String in sim.state.buildings:
		bld = b
		break
	eq(_refused(sim.step([_play(me, "pulso", id, ["preset:regular_even"], {"house": bld})])), "bad_option",
		"never with a house")
	_fest_to(sim, int(inst["end"]) + 1)
	eq(_refused(sim.step([_play(me, "pulso", id, ["preset:regular_even"])])), "no_feast", "not after it")


func test_with_the_preacher_it_is_frowned_upon() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	sim.state.families[fam]["gold"] = 300
	var id := Festivals._schedule(sim, "preacher", 2, "test")
	_fest_to(sim, int(Festivals.find(sim, id)["start"]) + 30)
	check(FestivalCorro.frowned(sim), "the preacher frowns on gambling")
	var rep := Reputation.of(sim.state, fam)
	var ev := sim.step([_play(me, "pulso", id, ["preset:regular_even"])])
	eq(_refused(ev), "", "it may be played")
	eq(Reputation.of(sim.state, fam), rep + int(cat.festivals["rules"]["corro"]["frowned"]["reputation"]), "but it costs reputation")
	var corro := _of(ev, "game_corro")
	check(not corro.is_empty() and int(corro[0]["frowned"]) < 0, "told as frowned upon")


func test_the_card_opens_the_corro() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	sim.state.families[fam]["gold"] = 300
	var id := Festivals._schedule(sim, "comedians", 2, "test")
	var inst := Festivals.find(sim, id)
	var e := {"type": "festival_eve", "id": id, "def": "comedians", "day": 2, "start": int(inst["start"]), "end": int(inst["end"])}
	var d := FestivalPage.data_for(sim, e, fam)
	check(not (d["buttons"] as Array).any(func(b: Dictionary) -> bool: return str(b["id"]) == "corro_menu"), "not on the eve")
	_fest_to(sim, int(inst["start"]) + 30)
	e["type"] = "festival_started"
	d = FestivalPage.data_for(sim, e, fam)
	check((d["buttons"] as Array).any(func(b: Dictionary) -> bool: return str(b["id"]) == "corro_menu"), "on its day: «Corro de juego»")
	var m := FestivalPage.corro_menu(sim, d)
	var games: Array = (m["buttons"] as Array).filter(func(b: Dictionary) -> bool: return str(b["id"]).begins_with("corro:"))
	eq(games.size(), 4, "pulso, azar, a la mayor, envite")
	check(games.all(func(b: Dictionary) -> bool: return not bool(b.get("disabled", false))), "all open with gold")
	var req := FestivalPage.corro_request(sim, "corro:mayor", m, Kin.head(sim.state, fam))
	eq([str(req["game"]), (req["opponents"] as Array).size(), int(req["stake"]), str(req["opts"]["corro"])],
		["mayor", 2, 5, id], "the game screen's request")
	sim.state.families[fam]["gold"] = 0
	m = FestivalPage.corro_menu(sim, d)
	games = (m["buttons"] as Array).filter(func(b: Dictionary) -> bool: return str(b["id"]).begins_with("corro:"))
	check(games.all(func(b: Dictionary) -> bool: return bool(b.get("disabled", false))), "without gold, all off")
	var words: Array = []
	for b: Dictionary in m["blocks"]:
		for it: Dictionary in b.get("items", []):
			words.append(str(it.get("text", "")))
	check(words.any(func(t: String) -> bool: return SimQuery.t_("ui.festival_card.gold_short").get_slice("%", 0) in t),
		"and the card says why, as an effect line (a docked card keeps it)")
	var frown := _game()
	var fid := Festivals._schedule(frown, "preacher", 2, "test")
	_fest_to(frown, int(Festivals.find(frown, fid)["start"]) + 30)
	var fm := FestivalPage.corro_menu(frown, {"instance": fid})
	var fw: Array = []
	for b: Dictionary in fm["blocks"]:
		for it: Dictionary in b.get("items", []):
			fw.append(str(it.get("text", "")))
	check(fw.any(func(t: String) -> bool: return "-2" in t or "−2" in t), "with the preacher: frowned upon (%s)" % [fw])


# --- Christmas gifts between families --------------------------------------------------------------------------------

func _christmas(sim: Sim) -> Dictionary:
	var day := -1
	for f: Dictionary in Festivals.calendar(sim):
		if str(f["id"]) == "christmas":
			day = int(f["day_of_year"])
	_fest_to(sim, (day - 1) * DAY + 12 * 60 + 1)  # the crier, the eve at noon
	for i: Dictionary in Festivals.announced(sim):
		if str(i["def"]) == "christmas":
			return i
	return {}


func test_a_christmas_gift_to_another_house() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	var inst := _christmas(sim)
	check(not inst.is_empty(), "Christmas announced")
	var rival := ""
	for f: String in FestivalCourt.gift_targets(sim, fam):
		if str(sim.state.families[f].get("ai_profile", "")) != "":
			rival = f
			break
	var o := {"type": "festival_give_gift", "actor": me, "festival": str(inst["id"]), "to": rival}
	for c: String in [me]:
		(sim.state.characters[c]["inventory"]["stacks"] as Array).clear()
	for b: String in Titles.business_ids(sim, fam):
		(sim.state.buildings[b]["inventory"]["stacks"] as Array).clear()
	eq(_refused(sim.step([o])), "no_piece", "nothing to give")
	Inventory.add(sim.state.characters[me]["inventory"], cat, "candlestick", 2, 1)
	var rh := Kin.head(sim.state, rival)
	var before := Emotions.relation(sim.state, rh, me)
	var ev := sim.step([o])
	eq(_refused(ev), "", "the candlestick for the rival's house")
	eq(Inventory.count(sim.state.characters[me]["inventory"], "candlestick", 2), 0, "it leaves the bag")
	var got := 0
	for b: String in Titles.business_ids(sim, rival) + [rh]:
		got += Inventory.count(sim.state.inventory_of(b), "candlestick", 2)
	eq(got, 1, "and reaches the rival's house")
	var rel := FestivalCourt.gift_relation(sim, FestivalCourt.value(sim, "candlestick", 2))
	check(rel > 0, "a gift buys relation (+%d)" % rel)
	eq(Emotions.relation(sim.state, rh, me) - before, rel, "the rival's head likes him more")
	eq(_of(ev, "festival_gift_given").size(), 1, "told")
	Inventory.add(sim.state.characters[me]["inventory"], cat, "candlestick", 2, 1)
	eq(_refused(sim.step([o])), "already_given", "one gift per house")
	eq(_refused(sim.step([{"type": "festival_give_gift", "actor": me, "festival": str(inst["id"]), "to": fam}])),
		"bad_family", "not to oneself")


func test_the_ai_gives_if_it_has_gold_to_spare() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	var rival := ""
	for f: String in Festivals._sorted_keys(sim.state.families):
		if str(sim.state.families[f].get("ai_profile", "")) != "":
			rival = f
			break
	var rh := Kin.head(sim.state, rival)
	Emotions.change_relation(sim, rh, me, 40, "test")  # the rival's head likes the player's most
	sim.state.families[rival]["gold"] = 5000
	var inst := _christmas(sim)
	Inventory.add(sim.state.characters[rh]["inventory"], cat, "fine_clothes", 1, 1)  # a piece it neither sells nor delivers
	var gave := false
	while int(sim.state.clock["minute"]) < int(inst["start"]) + 5:
		for e: Dictionary in sim.step():
			if str(e.get("type", "")) == "festival_gift_given" and str(e["family"]) == rival and str(e["to"]) == fam:
				gave = true
	check(gave, "with gold to spare the AI gives its gift to the house it likes most")
	check(Notices.list(sim, fam).any(func(n: Dictionary) -> bool: return str(n.get("key", "")) == "notice.festival_gift_received"),
		"the player is told")
	var poor := _game()
	var pf := SimQuery.player_family(poor.state)
	var pr := ""
	for f: String in Festivals._sorted_keys(poor.state.families):
		if str(poor.state.families[f].get("ai_profile", "")) != "":
			pr = f
			break
	Emotions.change_relation(poor, Kin.head(poor.state, pr), Kin.head(poor.state, pf), 40, "test")
	poor.state.families[pr]["gold"] = 10
	var pi := _christmas(poor)
	var any := false
	while int(poor.state.clock["minute"]) < int(pi["start"]) + 5:
		for e: Dictionary in poor.step():
			if str(e.get("type", "")) == "festival_gift_given" and str(e["family"]) == pr:
				any = true
	check(not any, "without gold to spare, no gift")


func test_the_christmas_card_offers_the_gifts() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	var inst := _christmas(sim)
	var e := {"type": "festival_eve", "id": str(inst["id"]), "def": "christmas", "day": int(inst["day"]),
		"start": int(inst["start"]), "end": int(inst["end"])}
	var d := FestivalPage.data_for(sim, e, fam)
	check((d["buttons"] as Array).any(func(b: Dictionary) -> bool: return str(b["id"]) == "gifts_menu"), "«Regalos de Navidad»")
	Inventory.add(sim.state.characters[me]["inventory"], cat, "candlestick", 2, 1)
	var m := FestivalPage.gifts_menu(sim, d)
	var gifts: Array = (m["buttons"] as Array).filter(func(b: Dictionary) -> bool: return str(b["id"]).begins_with("gift:"))
	eq(gifts.size(), FestivalCourt.gift_targets(sim, fam).size(), "one per house")
	check(gifts.all(func(b: Dictionary) -> bool: return not bool(b.get("disabled", false))), "all open with a piece")
	var o := FestivalPage.order_for(str(gifts[0]["id"]), m, me)
	eq(str(o.get("type", "")), "festival_give_gift", "the button's order")
	eq(_refused(sim.step([o])), "", "given")
	m = FestivalPage.gifts_menu(sim, d)
	var first: Dictionary = (m["buttons"] as Array).filter(func(b: Dictionary) -> bool: return str(b["id"]) == str(gifts[0]["id"]))[0]
	check(bool(first.get("disabled", false)), "then off for that house")


# --- The feast of another city --------------------------------------------------------------------------------------

func _in_bellcaire(sim: Sim, me: String) -> void:
	Region.ensure(sim)
	sim.state.clock["minute"] = 1 * DAY + 10 * 60  # Sant Jordi and its fair (day 1)
	var now := int(sim.state.clock["minute"])
	(sim.state.region["trips"] as Dictionary)[me] = {"id": "trv_test", "actor": me, "family": str(sim.state.characters[me]["family"]),
		"from": Region.home(sim), "to": "capital", "path": [], "leg": 0, "at": "capital", "leg_start": now, "leg_end": now,
		"escort": false, "state": "city", "since": now}  # the traveller is there


func test_the_games_of_bellcaire_on_sant_jordi() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	sim.state.families[fam]["gold"] = 300
	eq(FestivalCity.here(sim, me), [], "at home, no city's feast")
	_in_bellcaire(sim, me)
	var here := FestivalCity.here(sim, me)
	var sps: Array = here.map(func(g: Dictionary) -> String: return str(g["spectacle"]))
	check("joust" in sps and "sortija" in sps and "horse_race" in sps, "Sant Jordi's joust and ring, the fair's race (%s)" % [sps])
	var k_ring := ""
	var k_joust := ""
	var k_race := ""
	for g: Dictionary in here:
		match str(g["spectacle"]):
			"sortija": k_ring = str(g["key"])
			"joust": k_joust = str(g["key"])
			"horse_race": k_race = str(g["key"])
	eq(FestivalCity.play_reason(sim, me, k_joust), "no_title", "the joust asks for a title")
	var req := FestivalCity.request(sim, me, k_ring, true)
	var play := {"type": "game_play", "actor": me, "game": str(req["game"]), "opponents": req["opponents"], "stake": 0,
		"opts": req["opts"], "match": k_ring, "auto": true}
	var ev := sim.step([play])
	eq(_refused(ev), "", "away from home, he rides the sortija there")
	eq(_of(ev, "game_played").size(), 1, "played")
	eq(_of(ev, "city_feast_game").size(), 1, "as the feast's")
	eq(_refused(sim.step([play])), "already_played", "once")
	var watch := FestivalCity.request(sim, me, k_race, false)
	var bet := {"type": "game_bet", "actor": me, "game": str(watch["game"]), "players": watch["players"], "match": k_race,
		"opts": watch["opts"], "on": 0, "stake": 5}
	ev = sim.step([bet])
	eq(_refused(ev), "", "he watches the race and bets")
	eq(_of(ev, "game_bet_settled").size(), 1, "paid at once with the race")
	eq(_refused(sim.step([bet])), "already_bet", "once")
	var other: Dictionary = bet.duplicate(true)
	other["match"] = "x"
	eq(_refused(sim.step([other])), "already_bet", "nor under another name")
	eq(_refused(sim.step([{"type": "game_play", "actor": me, "game": "pulso", "opponents": ["preset:regular_even"],
		"stake": 5, "opts": {"corro": "fst_x"}, "auto": true}])), "away", "no corro at home while away")
	sim.state.clock["minute"] = 2 * DAY + 10 * 60
	eq(FestivalCity.reason(sim, me, k_ring, "play"), "not_in_city", "the next day it is over")


func test_the_city_page_lists_its_games() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	_in_bellcaire(sim, me)
	var reqs: Array = FestivalCity.here(sim, me).map(func(g: Dictionary) -> Dictionary:
		return FestivalCity.request(sim, me, str(g["key"]), true))
	check(reqs.all(func(r: Dictionary) -> bool: return not r.is_empty() and str((r["opts"] as Dictionary)["city_feast"]) == str(r["match"])),
		"each game, its request with its key")
	var w := FestivalCity.request(sim, me, str(FestivalCity.here(sim, me)[0]["key"]), false)
	check(bool(w.get("watch", false)) and not (w["players"] as Array).has(me), "watching: the field without him")


# --- The feast's contracts on the city's board, and the peddler -----------------------------------------------------

func test_the_feast_of_bellcaire_posts_its_contracts() -> void:
	var sim := _game()
	Region.ensure(sim)
	var board: Array = Region.city(sim, "capital")["board"]
	board.clear()
	FestivalCity.post_contracts(sim, "capital", 0)  # the eve of Sant Jordi and its fair (day 1)
	var feast: Array = board.filter(func(o: Dictionary) -> bool: return o.has("feast"))
	var items: Array = feast.map(func(o: Dictionary) -> String: return str(o["item"]))
	check("sword" in items and "fine_clothes" in items, "Sant Jordi asks for swords and fine clothes (%s)" % [items])
	check("horseshoe" in items, "and its fair, horseshoes")
	var sword: Dictionary = feast.filter(func(o: Dictionary) -> bool: return str(o["item"]) == "sword")[0]
	eq(int(sword["reward"]), roundi(float(cat.item("sword")["base_price"]) * int(sword["qty"]) * 2.0), "it pays double")
	FestivalCity.post_contracts(sim, "capital", 0)
	eq(board.filter(func(o: Dictionary) -> bool: return o.has("feast")).size(), feast.size(), "once per feast and day")
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	sim.state.clock["minute"] = 1 * DAY + 10 * 60
	var now := int(sim.state.clock["minute"])
	(sim.state.region["trips"] as Dictionary)[me] = {"id": "trv_test", "actor": me, "family": fam, "from": Region.home(sim),
		"to": "capital", "path": [], "leg": 0, "at": "capital", "leg_start": now, "leg_end": now, "escort": false,
		"state": "city", "since": now}
	eq(_refused(sim.step([{"type": "city_accept", "actor": me, "contract": str(sword["id"])}])), "", "accepted there")
	Inventory.add(sim.state.characters[me]["inventory"], cat, "sword", 0, int(sword["qty"]))
	var rep := Region.reputation(sim, "capital", fam)
	eq(_refused(sim.step([{"type": "city_deliver", "actor": me, "contract": str(sword["id"])}])), "", "delivered")
	eq(Region.reputation(sim, "capital", fam) - rep, int(cat.trade["reputation"]["contract_done"]) + 3, "with the feast's reputation")
	sim.state.clock["minute"] = 2 * DAY
	FestivalCity.post_contracts(sim, "capital", 2)
	check(not board.any(func(o: Dictionary) -> bool: return str(o.get("feast", "")) == "st_george"), "after the feast they leave the board")
	FestivalCity.post_contracts(sim, Region.home(sim), 0)
	check(not (Region.city(sim, Region.home(sim)).get("board", []) as Array).any(func(o: Dictionary) -> bool: return o.has("feast")),
		"never at home (its feasts are the calendar's)")


func test_the_peddler_sells_his_wares() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	var kd: Dictionary = Visitors.cfg(sim)["kinds"]["peddler"]
	var all := Peddler.stock_for(sim.state, kd, "test|always")
	check(not all.is_empty(), "he brings some wares")
	var with_dice := 0
	for i: int in 40:
		if Peddler.stock_for(sim.state, kd, "test|%d" % i).any(func(w: Dictionary) -> bool: return str(w["item"]) == "loaded_dice"):
			with_dice += 1
	check(with_dice > 5 and with_dice < 35, "the loaded dice, about half the days (%d of 40)" % with_dice)
	var pd := ""
	for c: String in sim.state.characters:
		pd = c
		break
	Life.service_family(sim.state, Life.FAMILY_VISITORS, "family.visitors", {"primary": "#6a5a4a", "secondary": "#c8b8a0"})
	pd = Life.add_person(sim, Life.FAMILY_VISITORS, "Buhonero", false, 40, {}, {}, Life.tile_of(sim.state, me),
		{"visitor": {"kind": "peddler", "city": "port", "gate": "", "purse": 20, "plan": [], "stop": -1, "until": -1,
		"leaving": false, "arrived": 0, "wares": [{"item": "loaded_dice", "price": 30, "qty": 1}]}})
	Life.put_on(sim, pd, Life.tile_of(sim.state, me))
	sim.state.families[fam]["gold"] = 100
	var o := {"type": "buy_from_peddler", "actor": me, "target": pd, "item": "loaded_dice"}
	var ev := sim.step([o])
	eq(_refused(ev), "", "he buys the loaded dice")
	eq(Inventory.count(sim.state.characters[me]["inventory"], "loaded_dice"), 1, "in his bag")
	eq(Money.gold(sim.state, fam), 70, "for 30")
	eq(_refused(sim.step([o])), "sold_out", "only one")
	eq(Peddler.reason(sim, me, Kin.head(sim.state, SimQuery.player_family(sim.state)), "loaded_dice"), "not_a_peddler",
		"nobody else sells them")
