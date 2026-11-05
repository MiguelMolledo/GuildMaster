extends "res://tests/test_case.gd"
## Ritmo (docs/gdd/03b_diversion_y_ritmo.md §3b.4-§3b.5): the unlocks (triggers, hooks, marks, cards read, a game
## from before with everything open), that they draw no randomness (the targets of today stay), the open goals and
## «Saltar hasta…» (×8 until its target, any notice cuts it).

const GameScript := preload("res://game/autoload/game.gd")
const HUGO: String = "chr_0001"
const FAM: String = "fam_0001"

var cat := Catalog.load_from()


func _new_game(c: Catalog = null) -> Sim:
	var cc := c if c != null else cat
	var r := NewGame.from_start(cc, "artisan_blacksmith", "normal", {"cast": "fixed"}, 3)
	return Sim.new(r["state"], cc)


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


func test_start_unlocks_and_hides_staff_until_gold() -> void:
	var sim := _new_game()
	var ev := sim.step()
	var got := _of(ev, "unlocked").map(func(e: Dictionary) -> String: return str(e["unlock"]))
	eq(got, ["live_forge"], "the first step opens only the start's mechanic")
	check(bool(sim.state.unlocks[FAM]["live_forge"]["seen"]), "no card for it: seen")
	check(not Unlocks.ui_open(sim, FAM, "staff"), "Staff hidden at the start")
	check(not Unlocks.ui_open(sim, FAM, "upgrades"), "Upgrades hidden at the start")
	check(Unlocks.ui_open(sim, "fam_0003", "staff"), "an AI family has everything open")
	sim.state.families[FAM]["gold"] = 160
	ev = sim.step()
	eq(_of(ev, "unlocked").size(), 1, "150 gold: one more")
	check(Unlocks.ui_open(sim, FAM, "staff"), "Staff open with 150 gold")
	eq(Unlocks.marks(sim, FAM), {"StaffButton": "staff"}, "the mark on Empleados")
	check(_of(ev, "notice_added").any(func(e: Dictionary) -> bool: return str(e["key"]) == "notice.unlocked"),
		"and a notice")
	check(Orders.apply(sim, {"type": "unlock_seen", "actor": HUGO, "unlock": "staff", "what": "card"})["ok"], "card read")
	eq(Unlocks.marks(sim, FAM).size(), 1, "the mark stays until the button is used")
	check(Orders.apply(sim, {"type": "unlock_seen", "actor": HUGO, "unlock": "staff", "what": "mark"})["ok"], "used")
	eq(Unlocks.marks(sim, FAM), {}, "no mark")
	eq(Orders.apply(sim, {"type": "unlock_seen", "actor": HUGO, "unlock": "upgrades", "what": "card"})["reason"],
		"not_unlocked", "a card of something not open")
	check(Orders.apply(sim, {"type": "unlock_seen", "actor": HUGO, "unlock": "upgrades", "what": "now"})["ok"],
		"a tutorial chapter opens it now")
	check(Unlocks.ui_open(sim, FAM, "upgrades"), "Upgrades open")


func test_calendar_event_and_hooks() -> void:
	var sim := _new_game()
	sim.step()
	check(not Unlocks.is_open(sim.state, FAM, "contracts"), "no contracts before the first sale")
	sim.events = [{"type": "market_sold", "family": FAM, "actor": HUGO, "stall": "armory", "item": "sword", "qty": 1}]
	Unlocks.step(sim)
	check(Unlocks.is_open(sim.state, FAM, "contracts"), "the first sale opens the contracts")
	sim.state.clock["minute"] = Clock.MINUTES_PER_DAY + 60
	sim.events = []
	Unlocks.step(sim)
	check(Unlocks.is_open(sim.state, FAM, "counter"), "day 2: the counter")
	eq(Unlocks.ready(sim, Unlocks.def(sim, "first_festival")), Festivals.enabled(sim), "the festival: with the calendar on")
	check(not Unlocks.is_open(sim.state, FAM, "first_festival"), "it opens when a festival starts, not by the date")
	sim.events = [{"type": "festival_started", "id": "f1", "def": "mayday_corpus"}]
	Unlocks.step(sim)
	eq(Unlocks.is_open(sim.state, FAM, "first_festival"), Festivals.enabled(sim), "a festival of the town starts (anyone)")
	check(not Unlocks.is_open(sim.state, FAM, "fair"), "the fair waits for the harvest fair")


func test_outsold_rival() -> void:
	var sim := _new_game()
	sim.step()
	sim.events = [{"type": "market_sold", "family": FAM, "qty": 3}, {"type": "market_sold", "family": "fam_0002", "qty": 1}]
	Unlocks.step(sim)
	sim.events = [{"type": "day_started"}]
	Unlocks.step(sim)
	var rival := ""
	for f: String in sim.state.families:
		if str(sim.state.families[f].get("ai_profile", "")) == "rival_smith":
			rival = f
	check(rival != "", "there is a rival smith")
	if rival == "fam_0002":
		eq(_of(sim.events, "rival_outsold").size(), 1, "3 > 1: outsold")
		Unlocks.step(sim)
		check(Unlocks.is_open(sim.state, FAM, "rival"), "the rival notices you")


func test_a_game_from_before_has_everything_open() -> void:
	var r := NewGame.from_scenario("town_e_start", 1)
	var sim := Sim.new(r["state"], cat)
	check(sim.state.unlocks.get(FAM, {}).has(Unlocks.ALL), "migrated with _all")
	var ev := sim.step()
	eq(_of(ev, "unlocked").size(), 0, "nothing comes: it was all open")
	check(Unlocks.ui_open(sim, FAM, "staff") and Unlocks.ui_open(sim, FAM, "upgrades"), "Staff and Upgrades open")


## The unlocks and the goals draw nothing from state.rng and give no orders: a day of the novice with them is the
## same economy as without (the targets of data/targets.json do not move).
func test_unlocks_do_not_change_the_economy() -> void:
	var off := Catalog.load_from()
	off.unlocks = {}
	var a := _new_game()
	var b := _new_game(off)
	var bot_a := BotArtisanNovice.new()
	var bot_b := BotArtisanNovice.new()
	for i: int in Clock.MINUTES_PER_DAY * 2:
		a.step(bot_a.orders(a))
		b.step(bot_b.orders(b))
	eq(a.state.rng.state, b.state.rng.state, "same rng")
	eq(int(a.state.families[FAM]["gold"]), int(b.state.families[FAM]["gold"]), "same gold")
	eq(JSON.stringify(a.state.buildings), JSON.stringify(b.state.buildings), "same buildings")
	check(not a.state.unlocks.get(FAM, {}).is_empty(), "the unlocks ran in one of them")


func test_open_goals() -> void:
	var sim := _new_game()
	sim.step()
	var v := OpenGoals.view(sim, FAM)
	eq(v.map(func(g: Dictionary) -> String: return str(g["horizon"])), ["short", "long"], "today and this year")
	eq(str(v[0]["objective"]), "forge_sword", "today: the start objective")
	eq(str(v[1]["objective"]), "repay_debt", "this year: the debt")
	sim.state.families[FAM]["gold"] = 160
	sim.step()
	v = OpenGoals.view(sim, FAM)
	eq(v.size(), 3, "three goals")
	eq(str(v[1]["objective"]), "hire_apprentice", "this season: the latest unlock's")
	sim.events = [{"type": "employee_hired", "family": FAM, "actor": HUGO}]
	OpenGoals.step(sim)
	check(bool(sim.state.unlocks[FAM]["_goals"]["hire_apprentice"]["done"]), "done")
	check(_of(sim.events, "open_goal_done").size() == 1, "with its event")
	v = OpenGoals.view(sim, FAM)
	eq(v.size(), 2, "back to two: the next unlock brings the next one")


func test_skip_until_dawn_and_a_notice_cuts_it() -> void:
	var g: Node = GameScript.new()
	g.start(_new_game().state, cat)
	g.sim.state.clock["minute"] = 20 * 60
	check(g.skip_until("dawn"), "skips")
	eq(g.effective_speed(), 8, "×8")
	var guard := 0
	for attempt: int in 20:  # a notice of the night (a thief, a warning) may cut it first: skip again
		if Clock.phase(int(g.sim.state.clock["minute"]), cat.time) == "dawn":
			break
		if str(g.skip_kind) == "":
			g.skip_until("dawn")
		while str(g.skip_kind) != "" and guard < 8000:
			g.advance(0.1, false)
			guard += 1
	var t: Dictionary = g.sim.now()
	eq(str(Clock.phase(int(g.sim.state.clock["minute"]), cat.time)), "dawn", "stops at dawn (%s)" % [t])
	eq(g.effective_speed(), 1, "back to the chosen speed")
	check(not g.skip_until("queue", "bld_0001"), "an empty queue: nothing to wait for")
	check(g.skip_until("event"), "the next event")
	g._check_skip([{"type": "notice_added", "family": FAM, "key": "x"}])
	eq(str(g.skip_kind), "", "a notice cuts it")
	check(g.skip_until("event"), "again")
	g.give({"type": "wait", "actor": HUGO})
	eq(str(g.skip_kind), "", "an order of the player cuts it")
	g.free()


## The hooks of vida (merged 2026-11-04): rumours and incidents open only with the living town on.
func test_life_hooks_follow_the_living_town() -> void:
	var sim := _new_game()
	sim.step()
	var on := Life.on(sim)
	eq(Unlocks.ready(sim, Unlocks.def(sim, "rumors")), on, "rumours: ready with the town alive")
	eq(Unlocks.ready(sim, Unlocks.def(sim, "incidents")), on, "incidents: the same")
	sim.state.clock["minute"] = 4 * Clock.MINUTES_PER_DAY + 60
	sim.events = []
	Unlocks.step(sim)
	eq(Unlocks.is_open(sim.state, FAM, "rumors"), on, "day 5: the rumours (with the town alive)")
	if on:
		sim.events = [{"type": "rumor_heard", "character": HUGO, "rumor": "r", "key": "k"}]
		OpenGoals.step(sim)
		eq(int(sim.state.unlocks[FAM]["_goals"]["hear_rumors"]["have"][0]), 1, "a rumour heard by Hugo counts")


## The hook of the inn (posada, merged 2026-11-05): the tavern's unlock comes on day 5 and its goal is to buy it.
func test_tavern_hook_follows_the_inn() -> void:
	var sim := _new_game()
	sim.step()
	check(Unlocks.ready(sim, Unlocks.def(sim, "tavern")), "the inn exists: the tavern's unlock is ready")
	sim.state.clock["minute"] = 4 * Clock.MINUTES_PER_DAY + 60
	sim.events = []
	Unlocks.step(sim)
	check(Unlocks.is_open(sim.state, FAM, "tavern"), "day 5: the tavern for sale")
	sim.events = [{"type": "building_bought", "family": FAM, "building": "bld_x", "actor": HUGO, "price": 1}]
	OpenGoals.step(sim)
	check(bool(sim.state.unlocks[FAM]["_goals"]["open_tavern"]["done"]), "bought: «Abre tu taberna» done")


## v19 (posada) -> v20: a save of the inn's version gets the roots of the unlocks behind _to_v19.
func test_v19_save_migrates_to_v20() -> void:
	var d: Dictionary = NewGame.from_scenario("town_e_start", 2)["state"].to_dict()
	d.erase("unlocks")
	d.erase("masterworks")
	d["version"] = 19
	var m := SaveFile.migrate(d)
	check(m["ok"], "migrates")
	eq(int(m["data"]["version"]), 20, "to v20")
	check((m["data"]["unlocks"] as Dictionary).has(FAM), "everything open for the family of before")
