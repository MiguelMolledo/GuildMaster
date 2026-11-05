class_name BotInnkeeper
extends RefCounted
## Bot innkeeper (docs/gdd/04f_vida_y_fiestas.md §4.28.4): runs the Taberna-Posada of the scenario innkeeper_start for
## 16 days with the same orders as the UI. By day the head walks to the market and buys by errand what the menu and
## the kitchen's queue need; the cook (role kitchen, day shift) cooks the queue; at dusk the head stands at the bar and
## serves by hand while the barkeeper and the waiter (night shift) serve too; the maid (role rooms) makes the beds in
## the morning. It hires as places open, buys the upgrades in a fixed order when the gold allows, buys the gaming
## licence once the table is built, adds dishes to the menu as the upgrades open them and repays the start debt.
## Its measures (sim_runner): inn_net_day (the tavern's ledger entries per day, without the purchase), inn_operating_day
## (without the upgrades and the licence), inn_fame, inn_bed_share (beds rented / beds × nights), inn_guests_night,
## inn_complaints_night, inn_fights, inn_upgrades, inn_licensed.

const ID: String = "innkeeper"
## Stock to keep in the storage, by dish (units), and how it comes: recipe (the kitchen) or bought at the market.
const KEEP: Dictionary = {"ale": 40, "cider": 10, "bread": 6, "garlic_soup": 12, "stew": 12, "wine": 10,
	"meat_pie": 10, "roast_lamb": 4, "sausage": 8, "sweets": 8}
const COOK: Dictionary = {"ale": "tavern_brew_ale", "garlic_soup": "tavern_garlic_soup", "stew": "tavern_stew",
	"meat_pie": "tavern_meat_pie", "roast_lamb": "tavern_roast_lamb", "sausage": "tavern_sausage", "sweets": "tavern_sweets"}
const UPGRADE_ORDER: Array = ["tavern_inn_ambience_1", "tavern_inn_security_1", "tavern_inn_hall_1",
	"tavern_inn_rooms_1", "tavern_inn_cellar_1", "tavern_inn_cellar_2", "tavern_inn_hall_2", "tavern_inn_kitchen_1",
	"tavern_inn_ambience_2", "tavern_inn_kitchen_2", "tavern_inn_rooms_2", "tavern_inn_hall_3", "tavern_inn_ambience_3"]
const ROLES: Array = ["kitchen", "bar", "rooms", "tables"]
const RESERVE: int = 80
## Days of running costs (upkeep of the family's buildings and wages) kept before repaying the debt or building.
const RESERVE_DAYS: int = 3
## Shopping order (lower first) when the purse does not reach for everything.
const BUY_FIRST: Dictionary = {"wheat": 0, "wood": 1, "meat": 2, "flour": 3, "wine": 20, "cider": 30, "bread": 40}

var _tavern: String = ""
var _hero: String = ""
var _fam: String = ""
var _set_up: bool = false
var _shop: Array = []         # [{stall, item, qty}] the trip in progress
var _shop_day: int = -1       # the half-day (day × 2 + afternoon) the last trip was planned
var _trip: String = ""        # "" | "going" | "back"
var _turns: Array = []        # the summaries of the closed turns
var _upgrades_bought: int = 0


func orders(sim: Sim) -> Array:
	var out: Array = []
	if not _find(sim):
		return out
	var st := sim.state
	var now := int(st.clock["minute"])
	for e: Dictionary in sim.events:
		if str(e.get("type", "")) == "inn_turn_closed" and str(e.get("building", "")) == _tavern:
			_turns.append(st.buildings[_tavern]["inn"]["last_turn"].duplicate(true))
	if not _set_up:
		_set_up = true
		out.append({"type": "inn_set_menu", "actor": _hero, "building": _tavern,
			"dishes": ["ale", "cider", "bread", "garlic_soup", "stew"]})
		out.append({"type": "inn_set_price", "actor": _hero, "building": _tavern, "dish": "bed", "mult": 0.9})
	if now % 60 == 7:
		out.append_array(_manage(sim, now))
	out.append_array(_act(sim, now))
	return out


func _find(sim: Sim) -> bool:
	if _tavern != "" and sim.state.buildings.has(_tavern):
		return true
	_fam = SimQuery.player_family(sim.state)
	if _fam == "":
		return false
	_hero = str(sim.state.families[_fam].get("head", ""))
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Inn.is_inn(sim, b) and str(sim.state.buildings[b].get("owner", "")) == _fam:
			_tavern = b
			return true
	return false


# --- Management (once an hour) --------------------------------------------------------------------------------------

func _manage(sim: Sim, now: int) -> Array:
	var st := sim.state
	var out: Array = []
	var gold := Money.gold(st, _fam)
	# staff: one per free place, in the order of ROLES; the roles of the ones that started
	var emps := Staff.employees_of(st, _tavern)
	var have := {}
	for e: String in emps:
		have[str(st.characters[e]["job"].get("role", ""))] = e
	for e: String in emps:
		var role := str(st.characters[e]["job"].get("role", ""))
		if role in ROLES:
			continue
		for r: String in ROLES:
			if not have.has(r):
				out.append({"type": "set_role", "actor": _hero, "employee": e, "role": r})
				have[r] = e
				break
	if Staff.free_slots(st, _tavern) > 0 and gold > RESERVE:
		# the cook first, and a journeyman (an apprentice gives half of each cycle, 4.7.2); the rest, apprentices
		var want_rank := "journeyman" if not have.has("kitchen") and emps.size() == 0 else "apprentice"
		var pick := ""
		for c: Dictionary in Staff.candidates(sim, _hero, _tavern):
			if str(c["status"]) != "ok":
				continue
			if pick == "":
				pick = str(c["character"])
			if str(c["rank"]) == want_rank:
				pick = str(c["character"])
				break
		if pick != "":
			out.append({"type": "hire", "actor": _hero, "building": _tavern, "candidate": pick})
	# the kitchen's queue: one entry per dish of the menu below its stock
	var q: Dictionary = st.buildings[_tavern].get("queue", {})
	var queued := {}
	for en: Variant in q.get("entries", []):
		queued[str((en as Dictionary).get("recipe", ""))] = true
	var menu: Array = st.buildings[_tavern]["inn"]["menu"]
	for d: String in COOK:
		var rid: String = COOK[d]
		if not d in menu or queued.has(rid) or Inn.stock(sim, _tavern, d) >= roundi(float(KEEP[d]) * maxf(1.0, Festivals.today_mult(sim, "service"))):
			continue
		if _has_inputs(sim, rid):
			out.append({"type": "queue_add", "actor": _hero, "building": _tavern, "recipe": rid, "qty": 1})
	# the start debt: never at the cost of the running costs. It keeps RESERVE_DAYS of upkeep and wages (the buildings
	# get damaged after 3 days of unpaid upkeep, D15); falling due, it pays what is above that reserve (the extension
	# takes the rest).
	var keep := RESERVE_DAYS * _running_costs(sim)
	for l: String in st.loans:
		var ln: Dictionary = st.loans[l]
		if str(ln.get("family", "")) != _fam or not Loans.is_open(ln):
			continue
		var owed := int(ln.get("outstanding", 0))
		var due_soon := int(ln.get("due_minute", 0)) - now <= Clock.MINUTES_PER_DAY
		var spare := gold - keep
		var pay := 0
		if spare >= owed + RESERVE:
			pay = owed
		elif due_soon and spare > 0:
			pay = mini(owed, spare)
		if pay > 0:
			out.append({"type": "repay_loan", "actor": _hero, "loan": l, "amount": pay})
			gold -= pay
	# upgrades in order, one works at a time
	var next := _next_upgrade(sim)
	if next != "" and Upgrades.status_of(sim, _hero, _tavern, next) == "available" \
			and gold >= int(sim.catalog.upgrade(next).get("cost", {}).get("gold", 0)) + maxi(3 * RESERVE, keep):
		out.append({"type": "buy_upgrade", "actor": _hero, "building": _tavern, "upgrade": next})
		_upgrades_bought += 1
	# the licence once the gaming table stands
	if Upgrades.flag(sim, _tavern, "inn_gaming_table") and not Inn.licensed(sim, _tavern) \
			and gold >= int(Inn.rules(sim).get("license", {}).get("cost", 60)) + RESERVE:
		out.append({"type": "inn_buy_license", "actor": _hero, "building": _tavern})
	# the menu grows with the upgrades
	var want: Array = ["ale", "cider", "bread", "garlic_soup", "stew"]
	if Inn.wine_quality(sim, _tavern) >= 1:
		want.append("wine")
	var season := Clock.season(now, sim.catalog.time)
	if season == "autumn":
		want.append("sausage")
	elif season == "winter":
		want.append("sweets")
	if Upgrades.has(st, _tavern, "tavern_inn_kitchen_2"):
		want.append("roast_lamb")
	want.append("meat_pie")
	while want.size() > Inn.menu_slots(sim, _tavern):
		want.pop_back()
	if want != menu:
		out.append({"type": "inn_set_menu", "actor": _hero, "building": _tavern, "dishes": want})
	return out


## What the family pays every day whatever it sells: the upkeep of its buildings and the wages of its employees.
func _running_costs(sim: Sim) -> int:
	var st := sim.state
	var total := 0
	for b: String in st.buildings:
		if str(st.buildings[b].get("owner", "")) != _fam:
			continue
		total += int(sim.catalog.buildings().get(str(st.buildings[b].get("type", "")), {}).get("upkeep", 0))
		var hired := Staff.employees_of(st, b)
		for e: String in hired:
			total += Staff.wage(sim, e)
		if b == _tavern:  # the places it will fill soon count at an apprentice's wage (the reserve before the hires)
			total += maxi(0, Staff.slots(st, b) - hired.size()) * int(sim.catalog.rank("apprentice").get("wage", 7))
	return total


func _next_upgrade(sim: Sim) -> String:
	for u: String in UPGRADE_ORDER:
		if not Upgrades.has(sim.state, _tavern, u):
			return u
	return ""


func _has_inputs(sim: Sim, rid: String) -> bool:
	var inv: Dictionary = sim.state.buildings[_tavern]["inventory"]
	for i: Dictionary in sim.catalog.recipes()[rid].get("inputs", []):
		if Inventory.count(inv, str(i["item"])) < int(i["qty"]):
			return false
	return true


# --- Walking, buying, serving ----------------------------------------------------------------------------------------

func _act(sim: Sim, now: int) -> Array:
	var st := sim.state
	var ch: Dictionary = st.characters[_hero]
	if not (ch.get("order_queue", []) as Array).is_empty() or not (ch.get("path", []) as Array).is_empty():
		return []  # walking or going in: let it arrive
	var phase := Clock.phase(now, sim.catalog.time)
	var day := Clock.day(now)
	var w := Inn.turn_window(sim, now)
	var before_open := int(w[0]) - now
	# plan the day's trip in the morning
	var slot := day * 2 + (1 if Clock.hour(now) >= 14 else 0)  # two trips a day: morning and afternoon
	if phase == "day" and _shop_day != slot and _trip == "":
		_shop_day = slot
		_shop = _shopping_list(sim)
		if not _shop.is_empty():
			_trip = "going"
	if _trip == "going" and (not phase in ["day"] or before_open < 90):
		_trip = "back"
		_shop = []
	if _trip == "going":
		return _shopping(sim)
	if str(ch.get("location", "")) != _tavern:
		_trip = ""
		return [{"type": "enter_building", "actor": _hero, "building": _tavern}]
	_trip = ""
	var out: Array = []
	if Inn.is_open(sim, _tavern):
		if str(ch.get("station", "")) != "bar":
			var occ := str(st.buildings[_tavern]["zones"]["bar"].get("occupant", ""))
			if occ == "" or occ == _hero:
				return [{"type": "go_to_station", "actor": _hero, "zone": "bar"}]
		var best: Dictionary = {}
		for g: Dictionary in Inn.guests(sim, _tavern):
			if str(g.get("state", "")) == "waiting" and Inn.stock(sim, _tavern, str(g["order"])) > 0 \
					and (best.is_empty() or int(g["since"]) < int(best["since"])):
				best = g
		if not best.is_empty() and int(st.buildings[_tavern]["inn"]["night"]["servers"].get(_hero, -1)) <= now:
			out.append({"type": "inn_serve", "actor": _hero, "building": _tavern, "guest": str(best["id"])})
		return out
	# by day, inside: make a dirty bed if no maid does
	var maid := false
	for e: String in Staff.employees_of(st, _tavern):
		if str(st.characters[e]["job"].get("role", "")) == "rooms" and Staff.is_active(sim, e):
			maid = true
	if not maid:
		var beds: Array = st.buildings[_tavern]["inn"]["beds"]
		var making := false
		for b: Dictionary in beds:
			if str(b.get("state", "")) == "making" and str(b.get("by", "")) == _hero:
				making = true
		if not making:
			for i: int in beds.size():
				if str(beds[i].get("state", "")) == "dirty":
					return [{"type": "inn_make_bed", "actor": _hero, "building": _tavern, "bed": i}]
	return out


## What to buy today: the market-bought dishes below their stock, the kitchen's inputs for the cooking it needs and the
## next upgrade's materials. [{stall, item, qty}] sorted by stall.
func _shopping_list(sim: Sim) -> Array:
	var st := sim.state
	var inv: Dictionary = st.buildings[_tavern]["inventory"]
	var need := {}
	var menu: Array = st.buildings[_tavern]["inn"]["menu"]
	for d: String in KEEP:
		if not d in menu:
			continue
		var feast := maxf(1.0, Festivals.today_mult(sim, "service"))  # fiestas: a feast day fills the house
		var deficit := roundi(float(KEEP[d]) * feast) - Inn.stock(sim, _tavern, d)
		if deficit <= 0:
			continue
		if COOK.has(d):
			var rec: Dictionary = sim.catalog.recipes()[COOK[d]]
			var cycles := int(ceil(float(deficit) / float(rec["output"]["qty"])))
			for i: Dictionary in rec.get("inputs", []):
				need[str(i["item"])] = int(need.get(str(i["item"]), 0)) + cycles * int(i["qty"])
		else:
			need[d] = int(need.get(d, 0)) + deficit
	var next := _next_upgrade(sim)
	if next != "":
		for c: Dictionary in sim.catalog.upgrade(next).get("cost", {}).get("items", []):
			need[str(c["item"])] = int(need.get(str(c["item"]), 0)) + int(c["qty"])  # on top of the kitchen's
	var out: Array = []
	var gold := Money.gold(st, _fam) - RESERVE / 2
	var items: Array = need.keys()
	# the best margin first (the ale's wheat and wood, then the kitchen's meat and flour); what is sold as bought (bread,
	# cider, wine) last: alphabetical order spent the purse on bread before the ale had its wheat
	items.sort_custom(func(a: String, b: String) -> bool:
		var pa := int(BUY_FIRST.get(a, 50))
		var pb := int(BUY_FIRST.get(b, 50))
		return pa < pb if pa != pb else a < b)
	for it: String in items:
		var qty := int(need[it]) - Inventory.count(inv, it)
		if qty <= 0:
			continue
		var stall := _stall_of(sim, it)
		if stall == "":
			continue
		var cost := int(Market.price(sim, it, Inventory.NORMAL, "buy")) * qty
		if cost > gold:
			qty = maxi(0, gold / maxi(1, int(Market.price(sim, it, Inventory.NORMAL, "buy"))))
		if qty <= 0:
			continue
		gold -= int(Market.price(sim, it, Inventory.NORMAL, "buy")) * qty
		out.append({"stall": stall, "item": it, "qty": qty})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["stall"]) < str(b["stall"]))
	return out


func _stall_of(sim: Sim, item: String) -> String:
	var ms := str(sim.catalog.item(item).get("market_stall", ""))
	var stalls: Dictionary = sim.catalog.maps().get(sim.state.map_id, {}).get("stalls", {})
	for s: String in sim.catalog.market.get("stalls", {}):
		if ms in (sim.catalog.market["stalls"][s].get("sells", []) as Array) and stalls.has(s):
			return s
	return ""


## The trip: to the first stall of the list, buy all of it there by errand to the tavern, then the next.
func _shopping(sim: Sim) -> Array:
	var st := sim.state
	var ch: Dictionary = st.characters[_hero]
	if _shop.is_empty():
		_trip = "back"
		return [{"type": "enter_building", "actor": _hero, "building": _tavern}]
	if str(ch.get("location", "")) != "":
		return [{"type": "exit_building", "actor": _hero}]
	var stall := str(_shop[0]["stall"])
	var tile: Array = sim.catalog.maps().get(st.map_id, {}).get("stalls", {}).get(stall, {}).get("service", [0, 0])
	var pos: Array = ch.get("position", [0, 0])
	if int(pos[0]) != int(tile[0]) or int(pos[1]) != int(tile[1]):
		return [{"type": "move_to", "actor": _hero, "tile": [int(tile[0]), int(tile[1])]}]
	# one purchase a minute, so each one sees the errands of the ones before (Market._fits counts them)
	var gold := Money.gold(st, _fam)
	var surcharge := 1.0 + float(sim.catalog.market.get("errand", {}).get("surcharge", 0.2))
	while not _shop.is_empty() and str(_shop[0]["stall"]) == stall:
		var s: Dictionary = _shop.pop_front()
		var unit := ceili(float(Market.trade_price(sim, _hero, stall, str(s["item"]), Inventory.NORMAL, "buy")) * surcharge) + 1
		var qty := mini(int(s["qty"]), gold / maxi(1, unit))  # what the purse pays now, errand included
		while qty > 0 and not Market._fits(sim, _hero, _tavern, str(s["item"]), Inventory.NORMAL, qty):
			qty -= 1  # and what fits in the storage with the errands on their way
		if qty > 0:
			return [{"type": "buy", "actor": _hero, "stall": stall, "item": str(s["item"]), "quality": Inventory.NORMAL,
				"qty": qty, "deliver_to": _tavern}]
	return []


# --- Measures --------------------------------------------------------------------------------------------------------

func measures(sim: Sim) -> Dictionary:
	var st := sim.state
	if not _find(sim):
		return {"inn_found": 0}
	var days := maxi(1, _turns.size())
	var net := 0
	var operating := 0
	for e: Dictionary in st.ledger.get("entries", []):
		if str(e.get("family", "")) != _fam or str(e.get("building", "")) != _tavern:
			continue
		var cat := str(e.get("category", ""))
		if cat == Money.PROPERTY:
			continue
		net += int(e["amount"])
		if cat != Money.UPGRADES and str(e.get("ref", "")) != "inn_license":
			operating += int(e["amount"])
	var guests := 0
	var complaints := 0
	var fights := 0
	var beds := 0
	var bed_slots := 0
	for t: Dictionary in _turns:
		guests += int(t.get("guests", 0))
		beds += int(t.get("beds", 0))
		for k: Variant in t.get("complaints", {}):
			complaints += int(t["complaints"][k])
		for i: Dictionary in t.get("incidents", []):
			if str(i.get("kind", "")) == "fight":
				fights += 1
	var inn: Dictionary = st.buildings[_tavern]["inn"]
	bed_slots = (inn["beds"] as Array).size() * days
	return {"inn_found": 1, "inn_turns": _turns.size(), "inn_net_day": snappedf(float(net) / days, 0.01),
		"inn_operating_day": snappedf(float(operating) / days, 0.01), "inn_fame": snappedf(float(inn["fame"]), 0.01),
		"inn_bed_share": snappedf(float(beds) / maxf(1.0, float(bed_slots)), 0.001),
		"inn_guests_night": snappedf(float(guests) / days, 0.01),
		"inn_complaints_night": snappedf(float(complaints) / days, 0.01), "inn_fights": fights,
		"inn_upgrades": Upgrades.owned(st, _tavern).size(), "inn_licensed": 1 if Inn.licensed(sim, _tavern) else 0,
		"inn_gold_end": Money.gold(st, _fam)}
