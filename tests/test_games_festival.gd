extends "res://tests/test_case.gd"
## Games and fiestas (docs/gdd/04f_vida_y_fiestas.md §4.25.3 spectacle, §4.26; docs/contratos/juegos.md §5 ter): the
## festival's spectacles that are games are fought at their hour (FestivalGames.on_spectacle); the bets at the fair are
## paid with the competition's own result; the player who entered (game_enter) is called to play it, plays it once,
## and if he never does the festival's end resolves it; the joust the mayor organizes opens the tournament.

const DAY: int = 1440

var cat := Catalog.load_from()


func _init() -> void:
	GameMatch.verbose = false
	Duel.verbose = false


func _game(seed: int = 1) -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, seed)
	var sim := Sim.new(r["state"], cat)
	sim.step()
	return sim


func _fest_to(sim: Sim, minute: int) -> Array:
	var seen: Array = []
	while int(sim.state.clock["minute"]) < minute:
		sim.state.clock["minute"] = int(sim.state.clock["minute"]) + 1
		sim.events = []
		Festivals.step(sim)
		seen.append_array(sim.events)
	return seen


func _of(evs: Array, type: String) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == type)


func _refused(evs: Array) -> String:
	var r := _of(evs, "order_refused")
	return str(r[0]["reason"]) if not r.is_empty() else ""


func _head(sim: Sim) -> String:
	return Kin.head(sim.state, SimQuery.player_family(sim.state))


func test_bet_at_the_fair_paid_with_the_race() -> void:
	var sim := _game()
	_fest_to(sim, 3 * DAY + 10 * 60)  # the harvest fair, before its race at 17:00
	var inst: Dictionary = Festivals.active(sim)[0]
	eq(str(inst["def"]), "harvest_fair", "the fair is on")
	var me := _head(sim)
	var fam := SimQuery.player_family(sim.state)
	var g0 := Money.gold(sim.state, fam)
	var ev := sim.step([{"type": "game_bet", "actor": me, "festival": str(inst["id"]), "spectacle": "horse_race", "on": 0,
		"stake": 10}])
	eq(_refused(ev), "", "a bet on the fair's race")
	eq(Money.gold(sim.state, fam) - g0, -10, "the stake is taken")
	var spec := FestivalGames.spec_for(sim, inst, "horse_race")
	var w := int(Games.auto(cat.games, spec)["winner"])
	var seen := _fest_to(sim, 3 * DAY + 17 * 60 + 1)
	var res := _of(seen, "festival_game_result")
	eq(res.size(), 1, "the race is run at its hour")
	var paid := _of(seen, "game_bet_settled")
	eq(paid.size(), 1, "and the bet settled")
	eq(int(paid[0]["winner"]), w, "with the race's own result")
	var odds := float(inst["games"]["bets"][0]["odds"])
	eq(Money.gold(sim.state, fam) - g0, (Betting.payout(10, odds) - 10) if w == 0 else -10, "paid at its odds")
	eq(_refused(sim.step([{"type": "game_bet", "actor": me, "festival": str(inst["id"]), "spectacle": "horse_race", "on": 0,
		"stake": 10}])), "too_late", "no bets once it is run")


func test_joust_entry_call_and_play_once() -> void:
	var sim := _game()
	var me := _head(sim)
	var fam := SimQuery.player_family(sim.state)
	var id := Festivals._schedule(sim, "tournament", 2, "organized", {"by": me})
	check(id != "", "the tournament the mayor's joust opens")
	var o := {"type": "game_enter", "actor": me, "festival": id, "spectacle": "joust"}
	eq(_refused(sim.step([o])), "no_title", "a commoner may not joust")
	sim.state.families[fam]["title"] = "citizen"
	eq(_refused(sim.step([o])), "", "a citizen enters the joust")
	eq(_refused(sim.step([o])), "already_entered", "once")
	eq(_refused(sim.step([{"type": "game_bet", "actor": me, "festival": id, "spectacle": "joust", "on": 1, "stake": 5}])),
		"bad_bet", "no bets on a field one is in (they go with its game)")
	var seen := _fest_to(sim, 2 * DAY + 10 * 60 + 1)
	var call := _of(seen, "festival_game_call")
	eq(call.size(), 1, "the joust calls him at its hour")
	eq(str(call[0]["actor"]), me, "him")
	var play := {"type": "game_play", "actor": me, "game": "joust", "opponents": call[0]["opponents"],
		"match": str(call[0]["match"]), "opts": {"event": id}, "auto": true}
	var ev := sim.step([play])
	eq(_refused(ev), "", "he plays it")
	eq(_of(ev, "festival_game_result").size(), 1, "its result is the festival's")
	eq(_refused(sim.step([play])), "not_called", "and not again")
	var fake: Dictionary = play.duplicate(true)
	fake["match"] = "%s|fight_tournament" % id
	eq(_refused(sim.step([fake])), "not_called", "nor a competition he did not enter")


func test_unplayed_entry_resolved_at_the_end() -> void:
	var sim := _game()
	var me := _head(sim)
	var id := Festivals._schedule(sim, "tournament", 2, "organized", {"by": me})
	eq(_refused(sim.step([{"type": "game_enter", "actor": me, "festival": id, "spectacle": "fight_tournament"}])), "",
		"anyone may enter the fighting tournament")
	var inst := Festivals.find(sim, id)
	var seen := _fest_to(sim, int(inst["end"]) + 2)
	check(not _of(seen, "festival_game_call").is_empty(), "called at 14:00")
	var res := _of(seen, "festival_game_result").filter(func(e: Dictionary) -> bool: return str(e["spectacle"]) == "fight_tournament")
	eq(res.size(), 1, "never played: the end resolves it without playing")
	check(not _of(seen, "game_played").is_empty(), "as a game_play of his (his prize if he wins)")


func test_bet_refunded_when_it_never_comes() -> void:
	var sim := _game()
	_fest_to(sim, 3 * DAY + 10 * 60)
	var inst: Dictionary = Festivals.active(sim)[0]
	var fam := SimQuery.player_family(sim.state)
	sim.step([{"type": "game_bet", "actor": _head(sim), "festival": str(inst["id"]), "spectacle": "horse_race", "on": 1,
		"stake": 5}])
	var g0 := Money.gold(sim.state, fam)
	FestivalGames.on_end(sim, inst)
	eq(Money.gold(sim.state, fam) - g0, 5, "a bet whose race never came is given back")
