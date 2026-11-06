extends "res://tests/test_case.gd"
## Posada (docs/gdd/04f_vida_y_fiestas.md §4.27): the Taberna-Posada's rules. The building for sale in a new game
## (after every id of before), buy_building, the menu and its prices, the night turn (open at dusk, arrivals, seats,
## orders, serving by hand and by the staff, the bill and the tip, close at 02:00 with its summary and the fame), the
## beds (paid on arrival, dirty at dawn, made by hand or by the maid), the spoilage, the licence, the clientele's
## reasons, the shifts of the staff, save v19 and the determinism.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"

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


func _run(sim: Sim, minutes: int, bot: Object = null) -> Array:
	var all: Array = []
	for i: int in minutes:
		all.append_array(sim.step(bot.orders(sim) if bot != null else []))
	return all


func _run_to(sim: Sim, minute: int) -> Array:
	return _run(sim, maxi(0, minute - int(sim.state.clock["minute"])))


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


# --- The building for sale ----------------------------------------------------------------------------------------

func test_new_game_puts_the_tavern_for_sale_after_every_id() -> void:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	check(r["ok"], "new game")
	var st: WorldState = r["state"]
	var sim := Sim.new(st, cat)
	var t := _tavern(sim)
	check(t != "", "the map's Taberna-Posada is in the game")
	check(bool(st.buildings[t].get("for_sale", false)), "for sale")
	eq(str(st.buildings[t]["owner"]), "", "no owner")
	var ids: Array = st.buildings.keys()
	ids.sort()
	eq(str(ids[ids.size() - 1]), t, "its id comes after every other building (the ids of before do not move)")
	eq(int(st.next_ids.get("bld", 0)), ids.size() + 1, "one building more, nothing else")


func test_buy_building_pays_and_owns() -> void:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	var st: WorldState = r["state"]
	var sim := Sim.new(st, cat)
	var t := _tavern(sim)
	var price := Inn.sale_price(sim, t)
	var no := Orders.apply(sim, {"type": "buy_building", "actor": HERO, "building": t})
	eq(no["reason"], "not_enough_gold", "30 gold is not enough")
	st.families[FAM]["gold"] = price + 5
	var ok := Orders.apply(sim, {"type": "buy_building", "actor": HERO, "building": t})
	check(ok["ok"], "bought")
	eq(Money.gold(st, FAM), 5, "paid the sale price")
	eq(str(st.buildings[t]["owner"]), FAM, "the family owns it")
	check(not st.buildings[t].has("for_sale"), "no longer for sale")
	check(st.buildings[t].get("inn") is Dictionary, "the inn state is there")
	eq(Orders.apply(sim, {"type": "buy_building", "actor": HERO, "building": t})["reason"], "own_building", "only once")
	eq(Orders.apply(sim, {"type": "buy_building", "actor": HERO, "building": "bld_0001"})["reason"], "own_building",
		"the forge is already the family's (H6: buying another family's business is Plots')")
	check(Orders.is_management("buy_building"), "a management order")


# --- Menu and prices ----------------------------------------------------------------------------------------------

func test_menu_and_prices_orders() -> void:
	var sim := _start()
	var t := _tavern(sim)
	check(Orders.apply(sim, {"type": "inn_set_menu", "actor": HERO, "building": t, "dishes": ["ale", "stew"]})["ok"], "menu")
	eq(Inn.state_of(sim, t)["menu"], ["ale", "stew"], "the menu")
	eq(Orders.apply(sim, {"type": "inn_set_menu", "actor": HERO, "building": t, "dishes": ["ale", "ale"]})["reason"],
		"bad_menu", "no repeats")
	eq(Orders.apply(sim, {"type": "inn_set_menu", "actor": HERO, "building": t, "dishes": Inn.dishes(sim)})["reason"],
		"menu_full", "at most menu_slots (6 at the start)")
	check(Orders.apply(sim, {"type": "inn_set_price", "actor": HERO, "building": t, "dish": "ale", "mult": 1.5})["ok"], "price")
	eq(Inn.dish_price(sim, t, "ale", 0), 9, "ale 6 × 1.5")
	eq(Inn.dish_price(sim, t, "ale", 2), 12, "excellent ×1.3")
	eq(Orders.apply(sim, {"type": "inn_set_price", "actor": HERO, "building": t, "dish": "ale", "mult": 2.5})["reason"],
		"bad_price", "out of range")
	check(Orders.apply(sim, {"type": "inn_set_price", "actor": HERO, "building": t, "dish": "bed", "mult": 0.8})["ok"], "bed price")
	eq(Inn.bed_price(sim, t, false), 10, "12 × 0.8 rounded")
	eq(Orders.apply(sim, {"type": "inn_set_special", "actor": HERO, "building": t, "dish": "wine"})["reason"],
		"not_on_menu", "the special is a dish of the menu")
	eq(Orders.apply(sim, {"type": "inn_set_menu", "actor": "chr_0002", "building": t, "dishes": ["ale"]})["reason"],
		"not_your_building", "the rival cannot")


# --- The night turn -----------------------------------------------------------------------------------------------

func test_turn_opens_at_dusk_guests_come_and_it_closes_at_two() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	check(not Inn.is_open(sim, t), "closed before dusk")
	var ev := _run_to(sim, int(w[0]) + 1)
	eq(_of(ev, "inn_turn_opened").size(), 1, "opens at dusk")
	check(Inn.is_open(sim, t), "open")
	ev = _run_to(sim, int(w[1]) + 1)
	check(_of(ev, "inn_guest_arrived").size() > 0, "guests came")
	eq(_of(ev, "inn_turn_closed").size(), 1, "closes at 02:00")
	check(not Inn.is_open(sim, t), "closed after")
	var sum: Dictionary = Inn.state_of(sim, t)["last_turn"]
	eq(int(sum["day"]), 0, "the turn of day 0")
	check(int(sum["guests"]) > 0, "the summary counts the guests")
	check(sum.has("by_group") and sum.has("dishes") and sum.has("complaints") and sum.has("fame_after"), "summary shape")
	eq((Inn.state_of(sim, t)["history"] as Array).size(), 1, "one night in the history")


func test_without_anyone_serving_guests_leave_slow() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	var ev := _run_to(sim, int(w[1]) + 1)
	var slow := _of(ev, "inn_guest_left").filter(func(e: Dictionary) -> bool: return str(e["reason"]) == "slow")
	check(slow.size() > 0, "nobody serves: they leave (slow)")
	eq(int(Inn.state_of(sim, t)["last_turn"]["income"]), 0, "no income")
	eq(_of(ev, "inn_guest_served").size(), 0, "nobody served")


func test_serving_by_hand_pays_bill_and_tip() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	_run_to(sim, int(w[0]) + 1)
	var gold0 := Money.gold(sim.state, FAM)
	var served := 0
	var gave := 0
	for i: int in 240:
		var orders: Array = []
		for g: Dictionary in Inn.guests(sim, t):
			if str(g["state"]) == "waiting" and orders.is_empty():
				orders.append({"type": "inn_serve", "actor": HERO, "building": t, "guest": str(g["id"])})
		gave += orders.size()
		for e: Dictionary in sim.step(orders):
			if str(e["type"]) == "inn_guest_served" and str(e.get("by", "")) == HERO:
				served += 1
	check(served > 0, "the hero served by hand")
	var bills := 0
	for e: Dictionary in sim.state.ledger["entries"]:
		if str(e["ref"]) == "inn_bill" and str(e["building"]) == t:
			bills += int(e["amount"])
	check(bills > 0, "bills in the ledger (services)")
	check(Money.gold(sim.state, FAM) > gold0, "the purse grew")


func test_serve_refusals() -> void:
	var sim := _start()
	var t := _tavern(sim)
	eq(Orders.apply(sim, {"type": "inn_serve", "actor": HERO, "building": t, "guest": "gst_1"})["reason"], "not_waiting",
		"nobody waits before opening")
	eq(Orders.apply(sim, {"type": "inn_serve", "actor": "chr_0002", "building": t, "guest": "gst_1"})["reason"],
		"not_inside", "the rival is not inside")


func test_staff_serves_on_their_night_shift() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var cands := Staff.candidates(sim, HERO, t)
	var hired: Array = []
	for c: Dictionary in cands:
		if str(c["status"]) == "ok" and hired.size() < 2:
			check(Orders.apply(sim, {"type": "hire", "actor": HERO, "building": t, "candidate": str(c["character"])})["ok"], "hire")
			hired.append(str(c["character"]))
	check(Orders.apply(sim, {"type": "set_role", "actor": HERO, "employee": hired[0], "role": "bar"})["ok"], "barkeeper")
	check(Orders.apply(sim, {"type": "set_role", "actor": HERO, "employee": hired[1], "role": "tables"})["ok"], "waiter")
	eq(InnStaff.shift(sim, hired[0], t), "night", "the bar works the night")
	# day 1's turn (they start at the next dawn)
	_run_to(sim, Clock.MINUTES_PER_DAY + 9 * 60)
	check(str(sim.state.characters[hired[0]]["location"]) != t, "by day the barkeeper is not at work")
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	var ev := _run_to(sim, int(w[0]) + 120)
	eq(str(sim.state.characters[hired[0]]["location"]), t, "at night the barkeeper is in the tavern")
	var by_staff := _of(ev, "inn_guest_served").filter(func(e: Dictionary) -> bool: return str(e["by"]) in hired)
	check(by_staff.size() > 0, "the staff serves")
	_run_to(sim, int(w[1]) + 90)
	check(str(sim.state.characters[hired[0]]["location"]) != t, "after closing they go home")


# --- Beds ---------------------------------------------------------------------------------------------------------

func test_beds_paid_dirty_at_dawn_and_made() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var inn := Inn.state_of(sim, t)
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	_run_to(sim, int(w[0]) + 1)
	# a merchant comes and asks for a bed: forced through the arrivals hook
	var gid := Inn.arrive(sim, t, "pilgrims")
	check(gid != "", "seated")
	var occupied: int = (inn["beds"] as Array).filter(func(b: Dictionary) -> bool: return str(b["state"]) == "occupied").size()
	var paid: int = (sim.state.ledger["entries"] as Array).filter(func(e: Dictionary) -> bool: return str(e["ref"]) == "inn_bed").size()
	eq(occupied, paid, "every occupied bed was paid on arrival")
	if occupied == 0:
		Inn._take_bed(sim, t, inn, Inn.guest(sim, t, gid), false)
	check((inn["beds"] as Array).any(func(b: Dictionary) -> bool: return str(b["state"]) == "occupied"), "a bed taken")
	_run_to(sim, Clock.MINUTES_PER_DAY + 8 * 60)
	var dirty: Array = []
	for i: int in (inn["beds"] as Array).size():
		if str(inn["beds"][i]["state"]) == "dirty":
			dirty.append(i)
	check(not dirty.is_empty(), "at dawn the slept beds are dirty")
	eq(Inn.beds_free(sim, t), (inn["beds"] as Array).size() - dirty.size(), "a dirty bed is not free")
	check(Orders.apply(sim, {"type": "inn_make_bed", "actor": HERO, "building": t, "bed": int(dirty[0])})["ok"], "make it")
	eq(Orders.apply(sim, {"type": "inn_make_bed", "actor": HERO, "building": t, "bed": int(dirty[0])})["reason"],
		"not_dirty", "it is being made")
	_run(sim, int(Inn.rules(sim)["make_bed_minutes"]) + 1)
	eq(str(inn["beds"][int(dirty[0])]["state"]), "made", "made after make_bed_minutes")


func test_cooked_food_spoils_at_dawn_without_cold_pantry() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var inv: Dictionary = sim.state.buildings[t]["inventory"]
	var soup0 := Inventory.count(inv, "garlic_soup")
	var ale0 := Inventory.count(inv, "ale")
	sim.state.clock["minute"] = Clock.MINUTES_PER_DAY + 250
	Inn.state_of(sim, t)["last_turn"] = {"day": 0}  # no turn tonight in this test
	var ev := _run(sim, 120)
	check(_of(ev, "inn_spoiled").size() > 0, "spoiled at dawn")
	eq(Inventory.count(inv, "garlic_soup"), soup0 - int(floor(soup0 * float(Inn.rules(sim)["spoil_share"]))), "soup lost its share")
	eq(Inventory.count(inv, "ale"), ale0, "ale does not spoil")


# --- Clientele ----------------------------------------------------------------------------------------------------

func test_clientele_says_why_groups_do_not_come() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var o := InnClientele.outlook(sim, t)
	var keys: Callable = func(g: String) -> Array:
		return (InnClientele.outlook(sim, t)[g]["reasons"] as Array).map(func(r: Dictionary) -> String: return str(r["key"]))
	check("fame_low" in keys.call("nobles"), "nobles: fame")
	check("ambience_low" in keys.call("nobles"), "nobles: ambience")
	check("no_good_wine" in keys.call("nobles"), "nobles: good wine")
	check("fame_low" in keys.call("merchants"), "merchants: fame 0 of 1")
	check("no_gaming_table" in keys.call("gamblers") and "no_license" in keys.call("gamblers"), "gamblers: table and licence")
	check((o["comarca"]["reasons"] as Array).is_empty(), "the comarca comes")
	check(float(o["comarca"]["expected"]) > 0.0, "some of the comarca are expected")
	Orders.apply(sim, {"type": "inn_set_price", "actor": HERO, "building": t, "dish": "bed", "mult": 1.5})
	o = InnClientele.outlook(sim, t)
	check("beds_expensive" in keys.call("pilgrims"), "pilgrims: dear beds")
	Orders.apply(sim, {"type": "inn_set_menu", "actor": HERO, "building": t, "dishes": ["wine"]})
	o = InnClientele.outlook(sim, t)
	check("no_dish" in keys.call("soldiers"), "soldiers: no ale")
	Orders.apply(sim, {"type": "inn_set_price", "actor": HERO, "building": t, "dish": "wine", "mult": 2.0})
	o = InnClientele.outlook(sim, t)
	check("too_expensive" in keys.call("comarca"), "comarca: too dear")


func test_cheaper_menu_attracts_more() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var base := float(InnClientele.outlook(sim, t)["comarca"]["expected"])
	Orders.apply(sim, {"type": "inn_set_price", "actor": HERO, "building": t, "dish": "ale", "mult": 0.5})
	Orders.apply(sim, {"type": "inn_set_price", "actor": HERO, "building": t, "dish": "cider", "mult": 0.5})
	check(float(InnClientele.outlook(sim, t)["comarca"]["expected"]) > base, "cheaper: more from the comarca")


# --- Licence, upgrades --------------------------------------------------------------------------------------------

func test_licence_costs_and_lasts_a_year() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var g0 := Money.gold(sim.state, FAM)
	check(Orders.apply(sim, {"type": "inn_buy_license", "actor": HERO, "building": t})["ok"], "bought")
	eq(Money.gold(sim.state, FAM), g0 - 60, "60 gold")
	check(Inn.licensed(sim, t), "licensed")
	eq(Orders.apply(sim, {"type": "inn_buy_license", "actor": HERO, "building": t})["reason"], "already_licensed", "once")
	sim.state.clock["minute"] = 8 * Clock.MINUTES_PER_DAY + 600
	check(not Inn.licensed(sim, t), "a year later it has expired")


func test_upgrades_change_the_room() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var b: Dictionary = sim.state.buildings[t]
	eq(Inn.seats(sim, t), 8, "8 seats")
	eq(Inn.bed_count(sim, t), 4, "4 beds")
	eq(Inn.ambience(sim, t), 1, "ambience 1")
	(b["upgrades"] as Array).append_array(["tavern_inn_hall_1", "tavern_inn_hall_2", "tavern_inn_rooms_1",
		"tavern_inn_ambience_1", "tavern_inn_security_1"])
	eq(Inn.seats(sim, t), 12, "+4 seats")
	eq(Inn.bed_count(sim, t), 8, "+4 beds")
	eq(Inn.ambience(sim, t), 2, "the hearth: ambience +1")
	eq(Inn.menu_slots(sim, t), 8, "the menu board: +2 dishes")
	Inn.ensure(sim, t)
	eq((Inn.state_of(sim, t)["beds"] as Array).size(), 8, "the new beds exist")
	check(Upgrades.flag(sim, t, "inn_porter"), "the doorman")


# --- Shifts, save, determinism ------------------------------------------------------------------------------------

func test_night_shift_window() -> void:
	var sim := _start()
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	check(InnStaff.on_duty(sim, int(w[0])), "on duty at the opening")
	check(InnStaff.on_duty(sim, int(w[0]) - 20), "30 min before")
	check(not InnStaff.on_duty(sim, int(w[0]) - 60), "not an hour before")
	check(InnStaff.on_duty(sim, int(w[1]) - 1), "until 01:59")
	check(not InnStaff.on_duty(sim, int(w[1])), "not at 02:00")


func test_save_v19_round_trip_mid_turn() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	_run_to(sim, int(w[0]) + 150)
	check(Inn.is_open(sim, t), "mid turn")
	var text := JSON.stringify(sim.state.to_dict())
	var r := SaveFile.from_text(text)
	check(r["ok"], "loads")
	var sim2 := Sim.new(r["state"], cat)
	check(int(r["state"].version) >= 19, "v19 (or a later version chained behind it)")
	_run(sim, 300)
	_run(sim2, 300)
	eq(sim2.state_hash(), sim.state_hash(), "the loaded game plays the same turn")


func test_migration_to_v19_from_an_old_save() -> void:
	var text := FileAccess.get_file_as_string("res://tests/data/saves/v12_kin_trader_events.json")
	var r := SaveFile.from_text(text)
	check(r["ok"], "a v12 save loads through v16-v19")
	eq(int(r["state"].version), WorldState.VERSION, "up to date")
	var d := {"version": 18, "buildings": {"bld_0009": {"type": "tavern_inn", "inn": {"menu": ["ale"]}}}}
	var m := SaveFile.migrate(d)
	check(m["ok"], "v18 -> v19")
	var inn: Dictionary = m["data"]["buildings"]["bld_0009"]["inn"]
	eq(inn["menu"], ["ale"], "keeps what it had")
	check(inn.has("beds") and inn.has("night") and inn.has("fame") and inn.has("license_until"), "gets the rest")


func test_deterministic_with_the_bot() -> void:
	var a := _start()
	var b := _start()
	var ba := BotInnkeeper.new()
	var bb := BotInnkeeper.new()
	_run(a, 1800, ba)
	_run(b, 1800, bb)
	eq(a.state_hash(), b.state_hash(), "same seed, same orders, same tavern")


# --- Vida: visitors that sleep here, rumours at the bar -----------------------------------------------------------

func test_a_visitor_sleeps_at_the_inn_and_leaves_at_dawn() -> void:
	var sim := _start()
	var t := _tavern(sim)
	check(Life.on(sim), "the life block is on in a normal game")
	_run_to(sim, Clock.MINUTES_PER_DAY + 14 * 60)
	var alive := Visitors.alive(sim.state)
	check(not alive.is_empty(), "visitors in town on day 1")
	var v := str(alive[0])
	var vis: Dictionary = sim.state.characters[v]["visitor"]
	vis["kind"] = "pilgrim"  # pilgrims always ask for a bed (bed 1.0) and come with beds at ×0.9
	check(Inn.lodge(sim, v), "a pilgrim with a free bed stays")
	eq(str(vis["lodging"]), t, "at this inn")
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	var ev := _run_to(sim, int(w[0]) + 120)
	eq(_of(ev, "inn_lodger_in").size(), 1, "it came in when the inn opened")
	check(Life.offstage(sim.state, v), "asleep: off the map")
	var g := Inn.guest(sim, t, str(vis["guest"]))
	eq(str(g.get("chr", "")), v, "the guest is the visitor itself")
	check(int(g.get("bed", -1)) >= 0, "with its bed")
	eq(_of(ev, "visitor_left").filter(func(e: Dictionary) -> bool: return str(e["character"]) == v).size(), 0,
		"it did not leave at dusk")
	ev = _run_to(sim, 2 * Clock.MINUTES_PER_DAY + 8 * 60)
	eq(_of(ev, "inn_lodger_out").size(), 1, "out at dawn")
	check(_of(ev, "visitor_left").any(func(e: Dictionary) -> bool: return str(e["character"]) == v) \
		or not Life.offstage(sim.state, v), "back on the map, on its way out")


func test_no_bed_no_lodging() -> void:
	var sim := _start()
	var t := _tavern(sim)
	_run_to(sim, Clock.MINUTES_PER_DAY + 14 * 60)
	var v := str(Visitors.alive(sim.state)[0])
	sim.state.characters[v]["visitor"]["kind"] = "pilgrim"
	for b: Dictionary in Inn.state_of(sim, t)["beds"]:
		b["state"] = "dirty"
	check(not Inn.lodge(sim, v), "no made bed: it goes")
	sim.state.characters[v]["visitor"]["kind"] = "beggar"
	Inn.state_of(sim, t)["beds"][0]["state"] = "made"
	check(not Inn.lodge(sim, v), "a beggar does not take a room")


func test_the_bar_rumour_is_a_real_one_and_goes_to_the_book() -> void:
	var sim := _start()
	var t := _tavern(sim)
	_run(sim, 2 * Clock.MINUTES_PER_DAY)
	var cands := Rumors.candidates(sim, int(sim.state.clock["minute"]))
	var r := InnRumors.pick(sim, t, HERO)
	if cands.is_empty():
		eq(r, {}, "nothing true to tell: no rumour")
		return
	eq(str(r["kind"]), "life", "one of vida's rumours")
	check(Rumors.heard(sim.state).any(func(h: Dictionary) -> bool: return str(h["point"]) == "inn:" + t),
		"heard at the bar: in the book of rumours")
	check(InnTurnPage.rumor_text(sim, r) != "", "it has its text")



# --- 04g: two layers of customers -----------------------------------------------------------------------------------

func test_a_neighbour_whose_agenda_sends_it_comes_in_and_pays_from_its_purse() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	_run_to(sim, int(w[0]) + 5)
	check(Inn.is_open(sim, t), "open")
	var who := ""
	for id: Variant in sim.state.characters:
		if TownLife.is_townsperson(sim.state, str(id)) and TownLife.is_adult(sim.state, sim.catalog, str(id)) \
				and not Staff.works_at(sim.state, str(id), t) and str(sim.state.characters[id].get("location", "")) == "":
			who = str(id)
			break
	check(who != "", "a townsperson in the street")
	var ch: Dictionary = sim.state.characters[who]
	var door: Array = sim.state.buildings[t]["door"]
	Life.put_on(sim, who, [int(door[0]), int(door[1]) - 1])
	var tt: Dictionary = ch["town"]
	tt["activity"] = "tavern"
	var hh := str(ch["family"])
	sim.state.families[hh]["gold"] = 40
	check(Inn.neighbour_in(sim, who, tt), "at the door of the open tavern: in")
	check(Inn.hosting(sim.state, who) and Life.offstage(sim.state, who), "inside, off the map")
	var g := {}
	for x: Dictionary in Inn.guests(sim, t):
		if str(x.get("chr", "")) == who:
			g = x
	eq(str(g.get("group", "")), "neighbours", "a neighbour with its name")
	var gold0 := Money.gold(sim.state, hh)
	for i: int in 300:
		var orders: Array = []
		if str(g.get("state", "")) == "waiting":
			orders.append({"type": "inn_serve", "actor": HERO, "building": t, "guest": str(g["id"])})
		sim.step(orders)
		if str(g.get("state", "")) == "gone":
			break
	eq(str(g.get("state", "")), "gone", "it went")
	check(Money.gold(sim.state, hh) < gold0 or int(g.get("paid", 0)) == 0, "it paid from its household's purse")
	check(not Inn.hosting(sim.state, who) and not Life.offstage(sim.state, who), "back in the street")


func test_the_comarca_is_drawn_and_has_no_name_in_town() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var w := Inn.turn_window(sim, int(sim.state.clock["minute"]))
	_run_to(sim, int(w[0]) + 1)
	var arr: Array = Inn.state_of(sim, t)["night"]["arrivals"]
	check(arr.any(func(a: Dictionary) -> bool: return str(a["group"]) == "comarca"), "the comarca comes")
	check(arr.all(func(a: Dictionary) -> bool: return str(a.get("chr", "")) == ""), "nobody drawn is a townsperson")
	check(not arr.any(func(a: Dictionary) -> bool: return str(a["group"]) == "neighbours"), "the neighbours come by their agenda")


func test_a_client_does_not_pay_more_than_its_max_price() -> void:
	var sim := _start()
	var t := _tavern(sim)
	var g := {"group": "pilgrims", "chr": ""}
	var top := Inn.max_price(sim, t, g, "ale")
	eq(top, roundi(6.0 * 1.0 * 1.0 * 1.1), "ref 6 × quality 1 × fame 0 × pilgrims' 1.1")
	Orders.apply(sim, {"type": "inn_set_price", "actor": HERO, "building": t, "dish": "ale", "mult": 2.0})
	check(Inn.dish_price(sim, t, "ale", 0) > top, "at ×2 the ale is dearer than what a pilgrim pays")
