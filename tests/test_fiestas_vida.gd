extends "res://tests/test_case.gd"
## Fiestas × vida (04f 4.25.3 with 4.24): the festival hooks the living town reads — the agenda's activities
## (routine), the day of rest, the visitors of the day (how many and which kinds), the incidents, the spectacles the
## townsfolk go to watch and the needs (the preacher's faith). All through Life.event_mult / holy_day / festival.

const DAY: int = 1440

var cat := Catalog.load_from()


func _game() -> Sim:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var sim := Sim.new(r["state"], cat)
	sim.step()
	return sim


func _to(sim: Sim, minute: int) -> void:
	while int(sim.state.clock["minute"]) < minute:
		sim.state.clock["minute"] = int(sim.state.clock["minute"]) + 1
		sim.events = []
		Festivals.step(sim)


func test_routine_and_holy_day() -> void:
	var sim := _game()
	_to(sim, 8 * DAY + 8 * 60)  # Holy Week of year 2, 08:00
	near(Life.event_mult(sim, "routine", "mass"), 5.0, 0.0001, "mass ×5 in the morning")
	near(Life.event_mult(sim, "routine", "work"), 1.0, 0.0001, "work is not a festival activity")
	check(Life.holy_day(sim), "a day of rest for the agenda (holy_phases)")
	_to(sim, 8 * DAY + 18 * 60)
	check(not Life.holy_day(sim), "not in the evening")


func test_visitors_of_the_fair() -> void:
	var sim := _game()
	_to(sim, 3 * DAY + 1)  # the fair, its first minute: planned at the start of the day
	check(Life.festival(sim), "a festival day for the watch")
	near(Life.event_mult(sim, "visitors"), 5.0 * 0.7, 0.0001, "visitors ×5 (×0,7 unsponsored): fair_max for the cap")
	check("merchant" in Festivals.today_kinds(sim), "merchants weigh more today")
	var sim2 := _game()
	_to(sim2, 2 * DAY + 8 * 60)  # St John starts at 18:00: the morning already plans its visitors
	check(Festivals.on_today(sim2), "St John is today")
	near(Life.event_mult(sim2, "visitors"), 1.0, 0.0001, "St John brings no visitors effect")


func test_incidents_and_spectacles() -> void:
	var sim := _game()
	_to(sim, 7 * DAY + 20 * 60)  # Carnival
	near(Life.event_mult(sim, "incident", "altercation"), 3.0, 0.0001, "brawls ×3 in Carnival")
	near(Life.event_mult(sim, "routine", "tavern"), 2.0, 0.0001, "the tavern ×2")
	var s2 := _game()
	_to(s2, 13 * 60)
	var fam := SimQuery.player_family(s2.state)
	s2.state.families[fam]["gold"] = 500
	var inst: Dictionary = Festivals.announced(s2)[0]
	check(Festivals.order_sponsor(s2, {"actor": Kin.head(s2.state, fam), "festival": str(inst["id"]), "part": "bulls"})["ok"],
		"the bulls paid")
	_to(s2, DAY + 17 * 60 + 5)
	var spec: Array = Life.spectacles(s2.state).filter(func(x: Dictionary) -> bool: return str(x["id"]) == "bulls")
	eq(spec.size(), 1, "the bulls in the plaza for the townsfolk to watch")


func test_the_preacher_raises_faith() -> void:
	var sim := _game()
	sim.state.clock["minute"] = 10 * DAY + 7 * 60
	sim.state.festivals["planned_day"] = 10
	var c: String = Population.townsfolk(sim.state)[0]
	if not sim.state.characters[c].get("town") is Dictionary:
		sim.state.characters[c]["town"] = {}
	var t: Dictionary = sim.state.characters[c]["town"]
	var before := int(Agenda.needs(sim, t, int(sim.state.clock["minute"]))["faith"])
	Festivals._schedule(sim, "preacher", 10, "test")
	_to(sim, 10 * DAY + 8 * 60 + 1)
	var after := int(Agenda.needs(sim, t, int(sim.state.clock["minute"]))["faith"])
	check(after > before, "faith +40 when the preacher starts (%d -> %d)" % [before, after])
