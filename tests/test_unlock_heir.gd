extends "res://tests/test_case.gd"
## The «heir» unlock (data/unlocks.json, sim/pacing/unlocks.gd; docs/gdd/03b_diversion_y_ritmo.md, «Generación 2»):
## it comes when the head's eldest child turns 16 or when the player names an heir, whichever is first, so the player
## learns to prepare the inheritance before the death (an inheritance still opens it if neither came first).

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	var sim := Sim.new(NewGame.from_scenario("founder_old", 1)["state"], cat)
	sim.state.unlocks[FAM] = {}  # a game of today: the unlocks from the first step
	return sim


func _open(sim: Sim) -> bool:
	return (sim.state.unlocks.get(FAM, {}) as Dictionary).has("heir")


## Makes every child of the head younger than 16 (the eldest `eldest` years old).
func _young(sim: Sim, eldest: int) -> Array:
	var st := sim.state
	var kids: Array = st.characters[HERO]["children"]
	var now := int(st.clock["minute"])
	for i: int in kids.size():
		st.characters[str(kids[i])]["birth_day"] = Kin.birth_day_for(maxi(eldest - i, 1), now, cat.time)
	return kids


func _to_new_year(sim: Sim) -> void:
	var dpy := Clock.days_per_year(cat.time)
	var day := Clock.day(int(sim.state.clock["minute"]))
	sim.state.clock["minute"] = (floori(float(day) / dpy) + 1) * dpy * Clock.MINUTES_PER_DAY - 2


func test_naming_an_heir_opens_it() -> void:
	var sim := _sim()
	var kids := _young(sim, 10)
	sim.step()
	check(not _open(sim), "children of 10 and less, nobody named: closed")
	var ev := sim.step([{"type": "designate_heir", "actor": HERO, "heir": str(kids[0])}])
	check(_open(sim), "named: open")
	eq(ev.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "unlocked" and str(e["unlock"]) == "heir").size(),
		1, "with its event in that step")


func test_the_eldest_turning_16_opens_it() -> void:
	var sim := _sim()
	_young(sim, 15)
	sim.step()
	check(not _open(sim), "the eldest is 15: closed")
	_to_new_year(sim)
	sim.step()
	check(not _open(sim), "still 15 the minute before the year changes")
	sim.run_minutes(3)
	eq(Kin.age(sim, str(sim.state.characters[HERO]["children"][0])), 16, "16 now")
	check(_open(sim), "open at the birthday, nobody named")


func test_an_inheritance_still_opens_it() -> void:
	var sim := _sim()
	_young(sim, 10)
	sim.step()
	sim.events = []
	Lifecycle.die(sim, HERO, "test")  # its inheritance event in sim.events, as in a step
	check(sim.events.any(func(e: Dictionary) -> bool: return str(e["type"]) == "inheritance"), "an inheritance")
	Unlocks.step(sim)
	check(_open(sim), "the head died before: open with the inheritance")


## The new leaf reads no event and is not volatile: its age moves with the day of the signature. A game whose memo is
## forgotten every minute opens it at the same minute.
func test_the_memo_does_not_hide_the_birthday() -> void:
	var a := _sim()
	var b := _sim()
	_young(a, 15)
	_young(b, 15)
	_to_new_year(a)
	_to_new_year(b)
	var got_a := -1
	var got_b := -1
	for i: int in 10:
		a.step()
		for k: StringName in [&"_unlocks_memo", &"_goals_memo", &"_event_types"]:
			b.remove_meta(k)
		b.step()
		if got_a < 0 and _open(a):
			got_a = int(a.state.clock["minute"])
		if got_b < 0 and _open(b):
			got_b = int(b.state.clock["minute"])
	check(got_a > 0, "it opened")
	eq(got_a, got_b, "at the same minute")
	eq(a.state_hash(), b.state_hash(), "the same state")
