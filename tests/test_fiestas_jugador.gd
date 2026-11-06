extends "res://tests/test_case.gd"
## Fiestas · what the player can reach (H16 audit, 2026-11-06): the feast's card opens again from the clock (the HUD's
## festival button reads SimQuery.festival_now), its «Inscribirse» buttons say why they are off (the same checks as
## game_enter, read only), and the sortija is run at Carnival and at the tournament (the riding game of those without a
## title: anyone with the entry fee).

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


## The words of a card: its paragraphs and its effect lines (a docked card keeps both).
func _texts(d: Dictionary) -> Array:
	var out: Array = []
	for b: Dictionary in d.get("blocks", []):
		out.append(str(b.get("text", "")))
		for it: Dictionary in b.get("items", []):
			out.append(str(it.get("text", "")))
	return out


func _button(d: Dictionary, id: String) -> Dictionary:
	for b: Dictionary in d.get("buttons", []):
		if str(b["id"]) == id:
			return b
	return {}


func test_the_clock_shows_the_feast_and_opens_its_card() -> void:
	var sim := _game()
	eq(SimQuery.festival_now(sim), {}, "at dawn of day 0, no feast announced yet")
	_fest_to(sim, 12 * 60 + 1)  # the crier of the Mayos (day 1) at noon
	var now := SimQuery.festival_now(sim)
	check(not now.is_empty(), "announced: the clock shows it")
	eq(str(now["event"]["type"]), "festival_eve", "the eve's card")
	eq(str(now["event"]["def"]), "mayday_corpus", "the Mayos")
	check(str(now["text"]).begins_with(SimQuery.festival_name("mayday_corpus")), "its name (%s)" % now["text"])
	check(SimQuery.t_("hud.festival_tomorrow") in str(now["text"]), "tomorrow")
	eq(str(now["short"]), SimQuery.t_("hud.festival_short_eve"), "on the clock, short: the crier")
	var fam := SimQuery.player_family(sim.state)
	var d := FestivalPage.data_for(sim, now["event"], fam)
	check(not d.is_empty(), "the card opens again")
	check(not _button(d, "sponsor:banquet").is_empty(), "with its sponsoring")
	check(not _button(d, "sponsor:bulls").is_empty(), "and the bulls to pay (then they are run: enter or bet)")
	_fest_to(sim, DAY + 9 * 60)
	now = SimQuery.festival_now(sim)
	eq(str(now["event"]["type"]), "festival_started", "on the day, the feast in force")
	check(SimQuery.t_("hud.festival_today") in str(now["text"]), "today")
	eq(str(now["short"]), SimQuery.t_("hud.festival_short_today"), "on the clock, short: the feast")


func test_enter_buttons_say_why_they_are_off() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	var id := Festivals._schedule(sim, "tournament", 2, "organized", {"by": me})
	var inst := Festivals.find(sim, id)
	sim.state.families[fam]["gold"] = 2000  # the sponsoring is paid: the card's line is the joust's
	check(not inst.has("games"), "nothing written yet")
	eq(FestivalGames.enter_reason(sim, me, inst, "joust"), "no_title", "a commoner may not joust")
	check(not inst.has("games"), "asking writes nothing (the card asks it every time)")
	var d := FestivalPage.data_for(sim, {"type": "festival_eve", "id": id, "def": "tournament", "day": 2,
		"start": int(inst["start"]), "end": int(inst["end"])}, fam)
	var j := _button(d, "enter:joust")
	check(bool(j.get("disabled", false)), "the joust's button is off")
	eq(str(j.get("tip", "")), SimQuery.reason_text("no_title"), "and says why")
	check(_texts(d).any(func(t: String) -> bool: return SimQuery.reason_text("no_title") in t), "in the card's text too")
	var s := _button(d, "enter:sortija")
	check(not s.is_empty() and not bool(s.get("disabled", true)), "the sortija is open to him: no title needed")
	sim.state.families[fam]["gold"] = 0
	eq(FestivalGames.enter_reason(sim, me, inst, "sortija"), "not_enough_gold", "without the entry fee")
	d = FestivalPage.data_for(sim, {"type": "festival_eve", "id": id, "def": "tournament", "day": 2,
		"start": int(inst["start"]), "end": int(inst["end"])}, fam)
	s = _button(d, "enter:sortija")
	check(bool(s.get("disabled", false)) and str(int(cat.games["sortija"]["entry_fee"])) in str(s.get("tip", "")),
		"off, with the fee and the gold (%s)" % s.get("tip", ""))
	sim.state.families[fam]["gold"] = 100
	eq(_refused(sim.step([{"type": "game_enter", "actor": me, "festival": id, "spectacle": "sortija"}])), "",
		"with the fee he enters")
	eq(FestivalGames.enter_reason(sim, me, Festivals.find(sim, id), "sortija"), "already_entered", "once")


func test_the_sortija_is_run_at_carnival() -> void:
	var sim := _game()
	var seen := _fest_to(sim, 7 * DAY + 20 * 60)  # Carnival (day 7): the sortija at 19:00
	var res := _of(seen, "festival_game_result").filter(func(e: Dictionary) -> bool: return str(e["spectacle"]) == "sortija")
	eq(res.size(), 1, "the riders run the sortija at Carnival")
	var inst: Dictionary = {}
	for i: Dictionary in Festivals.active(sim):
		if str(i["def"]) == "carnival":
			inst = i
	check(not inst.is_empty() and not FestivalGames._to_come(inst, "sortija"), "and it is not to come any more")


func test_the_player_rides_the_sortija() -> void:
	var sim := _game()
	var fam := SimQuery.player_family(sim.state)
	var me := Kin.head(sim.state, fam)
	var id := Festivals._schedule(sim, "tournament", 2, "organized", {"by": me})
	eq(_refused(sim.step([{"type": "game_enter", "actor": me, "festival": id, "spectacle": "sortija"}])), "", "he enters")
	var seen := _fest_to(sim, 2 * DAY + 12 * 60 + 1)
	var call := _of(seen, "festival_game_call").filter(func(e: Dictionary) -> bool: return str(e.get("spectacle", "")) == "sortija" \
		or str(e.get("match", "")).ends_with("|sortija"))
	eq(call.size(), 1, "called to ride at noon")
	if call.is_empty():
		return
	var play := {"type": "game_play", "actor": me, "game": "sortija", "opponents": call[0]["opponents"],
		"match": str(call[0]["match"]), "opts": {"event": id}, "auto": true}
	var ev := sim.step([play])
	eq(_refused(ev), "", "he rides it")
	eq(_of(ev, "festival_game_result").size(), 1, "its result is the festival's")


## The tavern's service hook (04f 4.25.3 `service`): San Juan doubles the tavern's customers (the inn reads it).
func test_the_tavern_doubles_on_st_john() -> void:
	var sim := _game()
	var day := -1
	for f: Dictionary in Festivals.calendar(sim):
		if str(f["id"]) == "st_john":
			day = int(f["day_of_year"])
	check(day > 0, "San Juan is in the calendar")
	var d := Festivals.def_of(sim, "st_john")
	_fest_to(sim, day * DAY + (int(d.get("start_hour", 0)) + 1) * 60)
	check(Festivals.active(sim).any(func(i: Dictionary) -> bool: return str(i["def"]) == "st_john"), "San Juan is on")
	var others: Array = (Festivals.active(sim) as Array).filter(func(i: Dictionary) -> bool: return str(i["def"]) != "st_john")
	sim.state.festivals["active"] = (Festivals.active(sim) as Array).filter(func(i: Dictionary) -> bool:
		return str(i["def"]) == "st_john")  # alone (a feast of the same day, the comedians ×1,5, multiplies too)
	near(Festivals.hook_mult(sim, "service", "tavern"), 2.0, 0.0001, "the tavern ×2 (%d more feasts today)" % others.size())
