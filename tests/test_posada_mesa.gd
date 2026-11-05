extends "res://tests/test_case.gd"
## Posada · the gaming table (docs/gdd/04f_vida_y_fiestas.md §4.27.4-5; docs/contratos/juegos.md §5): InnGames builds
## the games' request (opts.house = the tavern), the games apply it (game_play), the tavern hears game_played: the
## night's summary, the traveller's offer taken, and without the licence the light offence if the constable's men see.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const TABLE: Array = ["tavern_inn_ambience_1", "tavern_inn_ambience_2", "tavern_inn_ambience_3"]

var cat := Catalog.load_from()


func _start() -> Sim:
	return Sim.new(NewGame.from_scenario("innkeeper_start", 1)["state"], cat)


func _tavern(sim: Sim) -> String:
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Inn.is_inn(sim, b):
			return b
	return ""


func _run_to(sim: Sim, minute: int) -> Array:
	var all: Array = []
	for i: int in maxi(0, minute - int(sim.state.clock["minute"])):
		all.append_array(sim.step([]))
	return all


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


## A tavern with its gaming table, open tonight (the turn opened at dusk).
func _open_table(licensed: bool) -> Dictionary:
	var sim := _start()
	var t := _tavern(sim)
	(sim.state.buildings[t]["upgrades"] as Array).append_array(TABLE)
	if licensed:
		check(Orders.apply(sim, {"type": "inn_buy_license", "actor": HERO, "building": t})["ok"], "licence")
	Money.change(sim, FAM, 500, Money.GAMES, "test", "", HERO, false)
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	_run_to(sim, int(w[0]) + 5)
	check(Inn.is_open(sim, t), "open")
	return {"sim": sim, "t": t}


## Plays a request through the order game_play (what GameScreen gives), resolved without moves.
func _play(sim: Sim, req: Dictionary) -> Array:
	var o := req.duplicate(true)
	o["type"] = "game_play"
	o["auto"] = true
	return sim.step([o])


func test_the_table_needs_the_upgrade_and_the_open_turn() -> void:
	var sim := _start()
	var t := _tavern(sim)
	eq(InnGames.blocked(sim, t), "no_table", "no table without the upgrade")
	eq(str(InnGames.request(sim, t, HERO, "azar", 10).get("reason", "")), "no_table", "request refused")
	(sim.state.buildings[t]["upgrades"] as Array).append_array(TABLE)
	eq(InnGames.blocked(sim, t), "closed", "by day it is closed")
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	_run_to(sim, int(w[0]) + 1)
	eq(InnGames.blocked(sim, t), "", "open at night")


func test_request_has_the_house_and_regulars() -> void:
	var r := _open_table(true)
	var sim: Sim = r["sim"]
	var t := str(r["t"])
	var req := InnGames.request(sim, t, HERO, "azar", 10)
	eq(str(req["opts"]["house"]), t, "the house is the tavern")
	check(not (req["opts"] as Dictionary).has("event"), "no festival event (FestivalGames would refuse it)")
	eq((req["opponents"] as Array).size(), 1, "azar: one regular")
	eq((InnGames.request(sim, t, HERO, "mayor", 10)["opponents"] as Array).size(), 2, "mayor: two")
	check(Games.spec_of(sim, req).get("reason", "") == "", "the games accept it")
	eq(str(InnGames.request(sim, t, HERO, "pulso", 10).get("reason", "")), "unknown_game", "only dice and cards")


func test_a_game_at_the_table_goes_to_the_summary() -> void:
	var r := _open_table(true)
	var sim: Sim = r["sim"]
	var t := str(r["t"])
	var g0 := Money.gold(sim.state, FAM)
	var ev := _play(sim, InnGames.request(sim, t, HERO, "envite", 10))
	var gp := _of(ev, "game_played")
	eq(gp.size(), 1, "played")
	eq(str(gp[0]["house"]), t, "in the house")
	eq(int(gp[0]["house_cut"]), 0, "the player's own house takes nothing from him")
	eq(Money.gold(sim.state, FAM) - g0, int(gp[0]["net"]), "the family wins or loses the net")
	var games: Array = Inn.state_of(sim, t)["night"]["stats"]["games"]
	eq(games.size(), 1, "tonight's games")
	eq(_of(ev, "inn_illegal_gaming").size(), 0, "licensed: no offence")
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	_run_to(sim, int(w[1]) + 1)
	eq((Inn.state_of(sim, t)["last_turn"]["games"] as Array).size(), 1, "the summary keeps it")
	var lines := InnTurnPage.lines(sim, Inn.state_of(sim, t)["last_turn"])
	check(lines.any(func(l: String) -> bool: return l.begins_with(SimQuery.t_("ui.inn.sum.games").get_slice("%", 0))),
		"a line of the table in the summary")


func test_another_familys_game_pays_the_house() -> void:
	var r := _open_table(true)
	var sim: Sim = r["sim"]
	var t := str(r["t"])
	var other := ""
	for c: String in sim.state.characters:
		var ch: Dictionary = sim.state.characters[c]
		var f := str(ch.get("family", ""))
		if f != "" and f != FAM and sim.state.families.has(f) and bool(ch.get("alive", true)) \
				and int(ch.get("age", 30)) >= 16 and str(sim.state.families[f].get("head", "")) == c:
			other = c
			break
	check(other != "", "a head of another family")
	var of := str(sim.state.characters[other]["family"])
	Money.change(sim, of, 500, Money.GAMES, "test", "", other, false)
	var owner0 := Money.gold(sim.state, FAM)
	var won := false
	for i: int in 12:
		var ev := _play(sim, InnGames.request(sim, t, other, "azar", 25))
		var gp: Array = _of(ev, "game_played")
		if gp.size() == 1 and bool(gp[0]["won"]):
			check(int(gp[0]["house_cut"]) > 0, "a net win pays the house's rake")
			eq(Money.gold(sim.state, FAM) - owner0, int(gp[0]["house_cut"]), "to the tavern's owner")
			won = true
			break
		owner0 = Money.gold(sim.state, FAM)
	check(won, "one of twelve games won")


func test_without_licence_the_constable_may_see_it() -> void:
	var r := _open_table(false)
	var sim: Sim = r["sim"]
	var t := str(r["t"])
	(Inn.rules(sim)["games"]["illegal"] as Dictionary)["seen"] = 1.0
	(Inn.rules(sim)["games"]["illegal"] as Dictionary)["seen_constable"] = 1.0
	var facts0 := (sim.state.justice.get("facts", []) as Array).size()
	var ev := _play(sim, InnGames.request(sim, t, HERO, "azar", 5))
	var ill := _of(ev, "inn_illegal_gaming")
	eq(ill.size(), 1, "seen")
	var facts: Array = sim.state.justice["facts"]
	eq(facts.size(), facts0 + 1, "a fact for the court")
	eq(str(facts.back()["kind"]), "illegal_gaming", "illegal gaming")
	eq(str(facts.back()["charge"]), "minor_fraud", "a light charge")
	eq(str(facts.back()["family"]), FAM, "against who played")
	var night: Dictionary = Inn.state_of(sim, t)["night"]
	check(bool(night["stats"]["games"][0]["seen"]), "the summary says it was seen")
	check((night["stats"]["incidents"] as Array).any(func(i: Dictionary) -> bool: return str(i["kind"]) == "illegal_game"),
		"an incident of the night")
	(Inn.rules(sim)["games"]["illegal"] as Dictionary)["seen"] = 0.0
	(Inn.rules(sim)["games"]["illegal"] as Dictionary)["seen_constable"] = 0.0
	eq(_of(_play(sim, InnGames.request(sim, t, HERO, "azar", 5)), "inn_illegal_gaming").size(), 0, "unseen: nothing")
	Inn.rules(sim)["games"]["illegal"]["seen"] = 0.3
	Inn.rules(sim)["games"]["illegal"]["seen_constable"] = 0.5


func test_the_travellers_offer_is_played_and_taken() -> void:
	var r := _open_table(true)
	var sim: Sim = r["sim"]
	var t := str(r["t"])
	var inn := Inn.state_of(sim, t)
	eq(str(InnGames.offer_request(sim, t, HERO).get("reason", "")), "no_offer", "no offer yet")
	var offer := InnGames.make_offer(sim, t, inn)
	check(str(offer["preset"]) in (Inn.rules(sim)["games"]["offer"]["presets"] as Array), "a stranger of the list")
	check(str(offer["game"]) in ["azar", "envite"], "a game of two")
	check(not sim.catalog.games["presets"].get(str(offer["preset"]), {}).is_empty(), "its preset exists in games.json")
	var req := InnGames.offer_request(sim, t, HERO)
	eq(req["opponents"], ["preset:" + str(offer["preset"])], "against the stranger")
	eq(int(req["stake"]), int(offer["stake"]), "at his stake")
	var d := InnOfferCard.data_for(sim, t)
	check(not d.is_empty() and (d["buttons"] as Array).size() == 2, "the card: play or not now")
	_play(sim, req)
	eq(str(inn["night"]["offer"]["status"]), "played", "taken")
	check(InnGames.offer_of(sim, t).is_empty(), "no longer open")
	check(InnOfferCard.data_for(sim, t).is_empty(), "no card")


func test_the_offer_event_is_keyed_and_tells_the_family() -> void:
	var a := _open_table(true)
	var b := _open_table(true)
	var oa := InnGames.make_offer(a["sim"], str(a["t"]), Inn.state_of(a["sim"], str(a["t"])))
	var ob := InnGames.make_offer(b["sim"], str(b["t"]), Inn.state_of(b["sim"], str(b["t"])))
	eq(oa, ob, "same world, same stranger")
	var sim: Sim = a["sim"]
	var t := str(a["t"])
	Inn._game_offer(sim, t, Inn.state_of(sim, t))
	var e: Array = _of(sim.events, "inn_game_offer")
	eq(e.size(), 1, "the event")
	eq(str(e[0]["family"]), FAM, "for the owner's family (the card listens to it)")
