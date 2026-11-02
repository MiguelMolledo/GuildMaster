class_name BotArtisanExpert
extends BotArtisanNovice
## Bot that plays years 2-3 of a new game as a sensible expert blacksmith (GDD 07 §7.2, 4.7, 4.8, 4.19; H5). It starts
## from a real new game (NewGame.from_start) and plays the start phase like artisan_novice (the parent class) until
## the start debt is paid; from then on it also runs the forge as a business, only with real orders and the same
## queries as the UI (Staff.candidates / employees, WorkQueue, Upgrades.status_of, Market, Contracts):
##   staff:    hires the best allowed candidate (journeyman before apprentice, then craft; it waits for the gold of the
##             best one) up to max_employees, the second only once the forge has a second furnace (with one furnace
##             three workers wait for ingots, measured in H5); bonuses an employee below the loyal band (once a day);
##             accepts the promotions it is allowed to; with two employees, anvil + furnace roles.
##   queue:    keeps one entry for the employees (qty = active employees) of the anvil recipe with the best margin per
##             hour that they can make and that is not overstocked; buys their raw materials on its trips.
##   upgrades: buys the next one of UPGRADE_PLAN (production first; the second anvil and another place only with the
##             employees that use them) when the family has its gold plus a reserve, WORKS_GAP_DAYS of work between two
##             works; carries the materials home in the bag (or by errand) and buys the minute they are there.
##   market:   sells while the demand is >= EXPERT_MIN_DEMAND (what is made is sunk; holding it fills the storage).
##   contracts: as the novice, counting the employees' hands for the deadline.
##   titles (H9, docs/contratos/h9_titulos.md): two hooks that leave the H5 play as it was until they fire. When its
##             upgrade plan is done and the family meets its next title's requirements and keeps its reserve after
##             paying it, the trip gets a town_hall stop (request_title on its service tile). When the next title
##             asks for more employees than it has and the reputation is at TITLE_STAFF_REP_SHARE of what it needs,
##             it wants that many employees (the second-furnace rule gives way, within max_employees).
## Wages and upkeep are charged by the sim at dawn. Choices at the start (bot_choices): none. tools/sim_runner.gd runs
## it as artisan_expert (max 2, the rule above) and artisan_expert_<n> (exactly n employees, to measure what they add).

const EXPERT_ID: String = "artisan_expert"
const UPGRADE_PLAN: Array = ["forge_production_1", "forge_capacity_1", "forge_staff_1", "forge_production_2"]
## Upgrades that only pay with that many employees: the second anvil, another place, and the quality ones (they lift
## a craftsman of 5-6 into the 7-9 band of the quality table; the protagonist's 7 stays in it).
const STAFF_UPGRADES: Dictionary = {"forge_capacity_1": 1, "forge_staff_1": 2}
const WORKS_GAP_DAYS: int = 3         # days of production between the end of one works and the start of the next
const MATERIAL_STALL: String = "materials"
const LOYAL: int = 70                 # bonus below this loyalty (band "loyal" of data/employees.json)
const HIRE_RESERVE_DAYS: int = 4      # wages it wants in hand (on top of RESERVE) before hiring
const RESERVE: int = 60               # gold kept for raw materials before hiring or buying an upgrade
const EXPERT_MIN_DEMAND: float = 0.6  # sells while the demand is at least this (the novice: 0.7)
const EXPERT_HELD: int = 6            # unsold pieces of one product before choosing another recipe
const EXPERT_HELD_SINGLE: int = 2     # the same for products of one piece per storage stack (armor, hammer)
const STAFF_PIECES: int = 2           # pieces per active employee it buys raw materials for ahead
const INGOTS_PER_EXTRA_HAND: int = 3  # with 2+ employees the single furnace is short: ingots kept bought, per hand
const MANAGE_EVERY: int = 10          # minutes between two looks at staff, queue and upgrades
const IDLE_EVERY: int = 5             # minutes between two looks for work or a trip when idle at home
const TOWN_HALL: String = "town_hall"  # H9: trip stop to ask for the next title
const TITLE_STAFF_REP_SHARE: float = 0.5  # H9: share of the next title's reputation before hiring for its employees

var owner_sells: bool = false        # with employees, the protagonist sells instead of working in market hours
var split_roles: bool = true         # with two employees: anvil + furnace (else both "any")
var second_needs_furnace: bool = true  # a second employee only with a second furnace (forge_capacity_3)
var max_employees: int = 2           # employees it hires at most (sim_runner: artisan_expert_<n> sets it)
var asks_titles: int = 1             # H9: 0 = plays as in H5, never asks for a title (BOT_VARS=asks_titles=0)
var counter_shop: int = 0            # H7 balance trial (BOT_VARS=counter_shop=1): buys the sales counter first and
                                     # puts its least skilled employee at it (GDD 4.5.4: customers come to the forge)
var _bonus_day: Dictionary = {}       # employee -> last day it got a bonus
var _in_business: bool = false
var _works_end: int = -1000000       # minute the last works of the forge ended (or will end)
var _idle_until: int = -1             # minute until which an idle protagonist does not look for work or trips


func bot_choices() -> Dictionary:
	return {}


func orders(sim: Sim) -> Array:
	var st := sim.state
	if not st.characters.has(ACTOR) or not st.buildings.has(FORGE) or not st.ending.is_empty():
		return []
	var out: Array = []
	if _business(sim):
		if _now(sim) % MANAGE_EVERY == 0:
			out.append_array(_manage(sim))
		else:
			var up := _buy_upgrade(sim)  # as soon as the materials are in (errands): before anybody uses them
			if not up.is_empty():
				out.append(up)
		var batch := _upgrade_at_home(sim)
		if not batch.is_empty():
			out.append_array(batch)
			return out
	if _idle_until > _now(sim) and _trip.is_empty():
		return out  # idle at home a moment ago: looks again every IDLE_EVERY minutes (cost of the bot)
	var mine := super.orders(sim)
	if mine.is_empty() and _trip.is_empty() and not _busy(sim) \
			and str(st.characters[ACTOR].get("location", "")) == FORGE:
		_idle_until = _now(sim) + IDLE_EVERY
	out.append_array(mine)
	return out


## Business mode: the start debt is paid (or no loan left open). Once on, it stays on.
func _business(sim: Sim) -> bool:
	if _in_business:
		return true
	for id: String in Loans.of_family(sim, _fam(sim)):
		if str(Loans.status(sim, id)["state"]) in ["active", "extended"]:
			return false
	_in_business = true
	if OS.is_debug_build():
		print("[BotExpert] día %d: deuda saldada, empieza a llevar el negocio (oro=%d)" % [_today(sim),
			Money.gold(sim.state, _fam(sim))])
	return true


# --- Management (orders that do not walk: Orders.MANAGEMENT) ---------------------------------------------------------

func _manage(sim: Sim) -> Array:
	var out: Array = []
	var o := _promotion(sim)
	if not o.is_empty():
		out.append(o)
	o = _hire(sim)
	if not o.is_empty():
		out.append(o)
	o = _bonus(sim)
	if not o.is_empty():
		out.append(o)
	o = _roles(sim)
	if not o.is_empty():
		out.append(o)
	o = _queue(sim)
	if not o.is_empty():
		out.append(o)
	o = _buy_upgrade(sim)
	if not o.is_empty():
		out.append(o)
	return out


func _promotion(sim: Sim) -> Dictionary:
	for e: Dictionary in Staff.employees(sim, FORGE):
		if bool(e["promotion_offered"]):
			var next := str(sim.catalog.rank(str(e["rank"])).get("next", ""))
			if next != "" and Upgrades.rank_ok(sim, FORGE, next):
				return {"type": "promote", "actor": ACTOR, "employee": str(e["character"]), "accept": true}
	return {}


func _hire(sim: Sim) -> Dictionary:
	if Staff.free_slots(sim.state, FORGE) <= 0 or Staff.employees_of(sim.state, FORGE).size() >= _max_staff(sim):
		return {}
	if Upgrades.under_works(sim.state, FORGE):
		return {}
	var gold := Money.gold(sim.state, _fam(sim))
	var best := {}
	var best_score := -INF
	var order: Array = sim.catalog.employees.get("rank_order", [])
	for c: Dictionary in Staff.candidates(sim, ACTOR, FORGE):
		if str(c["status"]) not in ["ok", "not_enough_gold"]:
			continue
		var craft := int(c["stats"]["craft"])
		if craft < _min_anvil_craft(sim):
			continue
		var score := float(mini(order.find(str(c["rank"])), 1)) * 100.0 + craft  # journeyman (or better) first
		if score > best_score:
			best_score = score
			best = c
	# It waits for the gold of the best one rather than taking a worse one now.
	if best.is_empty() or str(best["status"]) != "ok" \
			or gold < RESERVE + HIRE_RESERVE_DAYS * (int(best["wage"]) + _wages(sim)):
		return {}
	if OS.is_debug_build():
		print("[BotExpert] día %d: contrata a %s (%s, artesanía %d, salario %d, oro=%d)" % [_today(sim),
			best["character"], best["rank"], int(best["stats"]["craft"]), int(best["wage"]), gold])
	return {"type": "hire", "actor": ACTOR, "building": FORGE, "candidate": str(best["character"])}


## Employees it wants now: max_employees, but the second one only once the forge has a second furnace (measured in H5:
## with one furnace the protagonist and two employees wait for ingots and the second does not pay its wage). H9: or the
## employees its next title asks for (within max_employees), once its reputation is on the way (_title_staff).
func _max_staff(sim: Sim) -> int:
	if second_needs_furnace and Upgrades.zone_kind(sim, FORGE, "furnace_2") != "furnace":
		return maxi(mini(max_employees, 1), mini(max_employees, _title_staff(sim)))
	return max_employees


## H9: the employees the next title requires, once the family has TITLE_STAFF_REP_SHARE of its reputation (0 if it
## asks for none, or not yet).
func _title_staff(sim: Sim) -> int:
	var fam := _fam(sim)
	var nx := Titles.next_of(sim, fam)
	if nx == "" or asks_titles != 1:
		return 0
	var def: Dictionary = sim.catalog.titles()[nx]
	var need := int(def.get("requires", {}).get("employees", 0))
	if need <= 0 or Reputation.of(sim.state, fam) < roundi(float(def.get("reputation", 0)) * TITLE_STAFF_REP_SHARE):
		return 0
	return need


func _bonus(sim: Sim) -> Dictionary:
	var fam := _fam(sim)
	for e: Dictionary in Staff.employees(sim, FORGE):
		var c := str(e["character"])
		if not bool(e["active"]) or int(e["loyalty"]) >= LOYAL or int(_bonus_day.get(c, -1)) == _today(sim):
			continue
		if Money.gold(sim.state, fam) < RESERVE + int(sim.catalog.employees.get("bonus_gold", 5)):
			return {}
		_bonus_day[c] = _today(sim)
		return {"type": "bonus", "actor": ACTOR, "employee": c}
	return {}


## Alone, an employee does everything ("any"); with two, the better craftsman takes the anvil and the other the
## furnace (the queue makes the ingots of each piece first, BUG-023 roles).
func _roles(sim: Sim) -> Dictionary:
	var staff := _active_staff(sim)
	var want := {}
	if staff.size() == 1 or not split_roles:
		for c: String in staff:
			want[c] = "any"
	elif staff.size() >= 2:
		staff.sort_custom(func(a: String, b: String) -> bool:
			var ca := int(sim.state.characters[a]["stats"].get("craft", 0))
			var cb := int(sim.state.characters[b]["stats"].get("craft", 0))
			return ca > cb or (ca == cb and a < b))
		want[staff[0]] = ANVIL
		for i: int in range(1, staff.size()):
			want[staff[i]] = FURNACE
	if counter_shop == 1 and not staff.is_empty() and Upgrades.flag(sim, FORGE, "counter_sales"):
		var low: String = staff[staff.size() - 1] if staff.size() >= 2 else staff[0]
		want[low] = "counter"  # the least skilled hand serves the customers
	for c: String in want:
		if str(sim.state.characters[c]["job"].get("role", "")) != str(want[c]):
			return {"type": "set_role", "actor": ACTOR, "employee": c, "role": want[c]}
	return {}


## One queue entry for the employees at a time: the best anvil recipe they can make, qty = active employees.
func _queue(sim: Sim) -> Dictionary:
	var hands := _active_staff(sim).size()
	if hands == 0:
		return {}
	var q: Dictionary = sim.state.buildings[FORGE].get("queue", {})
	for e: Dictionary in q.get("entries", []):
		if int(e["qty"]) == WorkQueue.INFINITE or int(e["done"]) < int(e["qty"]):
			return {}
	var rid := _staff_recipe(sim)
	if rid == "":
		return {}
	if OS.is_debug_build():
		print("[BotExpert] día %d min %d: cola %s ×%d" % [_today(sim), Clock.minute_of_day(_now(sim)), rid, hands])
	return {"type": "queue_add", "actor": ACTOR, "building": FORGE, "recipe": rid, "qty": hands}


func _staff_recipe(sim: Sim) -> String:
	var craft := 0
	for c: String in _active_staff(sim):
		craft = maxi(craft, int(sim.state.characters[c]["stats"].get("craft", 0)))
	var best := ""
	var best_rate := 0.0
	var ids: Array = sim.catalog.recipes().keys()
	ids.sort()
	for rid: String in ids:
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) != "forge" or str(r.get("zone", "")) != ANVIL:
			continue
		if int(r.get("min_craft", 0)) > craft or str(r.get("requires_upgrade", "")) != "" \
				and not Upgrades.has(sim.state, FORGE, str(r["requires_upgrade"])):
			continue
		if _held(sim, _output(sim, rid)) >= _max_held(sim, rid):
			continue
		var rate := _margin(sim, rid) / _hours(sim, rid, "normal")
		if rate > best_rate + 0.000001:
			best_rate = rate
			best = rid
	return best


func _buy_upgrade(sim: Sim) -> Dictionary:
	var id := _next_upgrade(sim)
	if id == "" or Upgrades.status_of(sim, ACTOR, FORGE, id) != "available":
		return {}
	if Money.gold(sim.state, _fam(sim)) < _upgrade_gold(sim, id) + _reserve(sim):
		return {}
	if OS.is_debug_build():
		print("[BotExpert] día %d: compra la mejora %s (oro=%d)" % [_today(sim), id, Money.gold(sim.state, _fam(sim))])
	_works_end = _now(sim) + roundi(float(sim.catalog.upgrade(id).get("build_days", 1.0)) * Clock.MINUTES_PER_DAY)
	return {"type": "buy_upgrade", "actor": ACTOR, "building": FORGE, "upgrade": id}


## When the protagonist is home with the materials of the next upgrade in the bag and the purse can pay: the
## transfers of those materials and buy_upgrade in the same minute (nobody takes them in between).
func _upgrade_at_home(sim: Sim) -> Array:
	var id := _next_upgrade(sim)
	if id == "":
		return []
	var st := sim.state
	var ch: Dictionary = st.characters[ACTOR]
	if str(ch.get("location", "")) != FORGE or not (ch.get("order_queue", []) as Array).is_empty() \
			or not (ch.get("path", []) as Array).is_empty():
		return []
	var status := Upgrades.status_of(sim, ACTOR, FORGE, id)
	if status != "missing_materials" or Money.gold(st, _fam(sim)) < _upgrade_gold(sim, id) + _reserve(sim):
		return []
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	var bag: Dictionary = ch["inventory"]
	var moves: Array = []
	var trial := inv.duplicate(true)
	for c: Dictionary in sim.catalog.upgrade(id).get("cost", {}).get("items", []):
		var item := str(c["item"])
		var short := int(c["qty"]) - Inventory.count(inv, item)
		if short <= 0:
			continue
		if Inventory.count(bag, item) < short:
			return []
		for q: int in Inventory.QUALITIES:
			var n := mini(short, Inventory.count(bag, item, q))
			if n <= 0:
				continue
			if not Inventory.add(trial, sim.catalog, item, q, n):
				return []
			moves.append({"type": "transfer", "actor": ACTOR, "from": ACTOR, "to": FORGE, "item": item, "quality": q,
				"qty": n})
			short -= n
	if moves.is_empty():
		return []
	moves.append({"type": "buy_upgrade", "actor": ACTOR, "building": FORGE, "upgrade": id})
	_works_end = _now(sim) + roundi(float(sim.catalog.upgrade(id).get("build_days", 1.0)) * Clock.MINUTES_PER_DAY)
	if OS.is_debug_build():
		print("[BotExpert] día %d: deja los materiales de %s y la compra (oro=%d)" % [_today(sim), id,
			Money.gold(st, _fam(sim))])
	return moves


## The first upgrade of UPGRADE_PLAN not owned whose requirements (upgrades, attribute, title) hold; "" if none or
## works are under way.
func _next_upgrade(sim: Sim) -> String:
	if Upgrades.under_works(sim.state, FORGE) or _now(sim) < _works_end + WORKS_GAP_DAYS * Clock.MINUTES_PER_DAY:
		return ""
	var plan: Array = (["forge_commerce_1"] if counter_shop == 1 else []) + UPGRADE_PLAN
	for id: String in plan:
		if id in STAFF_UPGRADES and _max_staff(sim) < int(STAFF_UPGRADES[id]):
			continue  # a second anvil or another place only pay with that many employees
		var s := Upgrades.status_of(sim, ACTOR, FORGE, id)
		if s == "owned":
			continue
		if s in ["available", "missing_materials", "not_enough_gold"]:
			return id
	return ""


func _upgrade_gold(sim: Sim, id: String) -> int:
	return int(sim.catalog.upgrade(id).get("cost", {}).get("gold", 0))


## Materials of the next upgrade still missing (storage + bag): {item: qty}, only once the purse can pay it.
func _upgrade_needs(sim: Sim) -> Dictionary:
	var id := _next_upgrade(sim)
	if id == "" or Money.gold(sim.state, _fam(sim)) < _upgrade_gold(sim, id) + _reserve(sim) + _upgrade_items_cost(sim, id):
		return {}
	var out := {}
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	var bag: Dictionary = sim.state.characters[ACTOR]["inventory"]
	for c: Dictionary in sim.catalog.upgrade(id).get("cost", {}).get("items", []):
		var item := str(c["item"])
		var short := int(c["qty"]) - Inventory.count(inv, item) - Inventory.count(bag, item)
		if short > 0:
			out[item] = short
	return out


func _upgrade_items_cost(sim: Sim, id: String) -> int:
	var cost := 0
	for c: Dictionary in sim.catalog.upgrade(id).get("cost", {}).get("items", []):
		cost += Market.price(sim, str(c["item"]), Inventory.NORMAL, "buy") * int(c["qty"])
	return cost


## Gold it keeps before buying an upgrade: raw materials + the wages of HIRE_RESERVE_DAYS.
func _reserve(sim: Sim) -> int:
	return RESERVE + _wages(sim) * HIRE_RESERVE_DAYS


func _wages(sim: Sim) -> int:
	var w := 0
	for c: String in Staff.employees_of(sim.state, FORGE):
		w += Staff.wage(sim, c)
	return w


func _active_staff(sim: Sim) -> Array:
	var out: Array = []
	for c: String in Staff.employees_of(sim.state, FORGE):
		if Staff.is_active(sim, c):
			out.append(c)
	return out


func _min_anvil_craft(sim: Sim) -> int:
	var lo := 10
	for rid: String in sim.catalog.recipes():
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) == "forge" and str(r.get("zone", "")) == ANVIL:
			lo = mini(lo, int(r.get("min_craft", 0)))
	return lo


# --- Trips: the materials of the next upgrade ------------------------------------------------------------------------

## H9: the H5 trip, with a stop at the town hall when the next title is ready (see _wants_title).
func _plan_trip(sim: Sim) -> Array:
	var t := _plan_trip_h5(sim)
	if not _wants_title(sim):
		return t
	if t.is_empty():
		t = ["home"]
	t.insert(maxi(0, t.find("home")), TOWN_HALL)
	if OS.is_debug_build():
		print("[BotExpert] día %d: va al Ayuntamiento a pedir %s (reputación=%d, oro=%d) → %s" % [_today(sim),
			Titles.next_of(sim, _fam(sim)), Reputation.of(sim.state, _fam(sim)), Money.gold(sim.state, _fam(sim)), t])
	return t


## H9: in business, and the family meets its next title's requirements keeping its reserve after the ceremony.
func _wants_title(sim: Sim) -> bool:
	return asks_titles == 1 and _business(sim) and _plan_done(sim) and Titles.ready(sim, _fam(sim), _reserve(sim))


## H9: every upgrade of its plan it wants now is owned (the business first, the title after: paying a title in the
## middle of the plan delays the upgrades the H5 targets of days 9-24 measure).
func _plan_done(sim: Sim) -> bool:
	var plan: Array = (["forge_commerce_1"] if counter_shop == 1 else []) + UPGRADE_PLAN
	for id: String in plan:
		if id in STAFF_UPGRADES and _max_staff(sim) < int(STAFF_UPGRADES[id]):
			continue
		if Upgrades.status_of(sim, ACTOR, FORGE, id) != "owned":
			return false
	return true


func _plan_trip_h5(sim: Sim) -> Array:
	var t := super._plan_trip(sim)
	var need := _upgrade_needs(sim) if _business(sim) else {}
	if _ingots_to_buy(sim) > 0:
		need["iron_ingot"] = int(need.get("iron_ingot", 0)) + _ingots_to_buy(sim)
	if need.is_empty():
		return t
	var at_materials := false
	for item: String in need:
		if _stall_of(sim, item) == MATERIAL_STALL:
			at_materials = true
	if t.is_empty():
		t = ["resources", "home"]
	if at_materials and not t.has(MATERIAL_STALL):
		t.insert(t.find("resources"), MATERIAL_STALL)
	if OS.is_debug_build():
		print("[BotExpert] día %d: viaje con materiales de mejora %s → %s" % [_today(sim), need, t])
	return t


func _stop(sim: Sim, stop: String) -> Dictionary:
	if stop == TOWN_HALL:  # H9
		if not _wants_title(sim):
			return {}
		var loc := str(sim.state.characters[ACTOR].get("location", ""))
		if loc != "":
			return {"type": "exit_building", "actor": ACTOR}
		if not Titles.at_town_hall(sim, ACTOR):
			return {"type": "move_to", "actor": ACTOR, "tile": Titles.service(sim)}
		return {"type": "request_title", "actor": ACTOR}
	if stop in [MATERIAL_STALL, "resources"] and Market.is_open(sim):
		var o := _buy_upgrade_items(sim, stop)
		if not o.is_empty():
			return o
		if stop == MATERIAL_STALL:
			return _buy_ingots(sim)
		if _business(sim):
			return _buy_raw(sim)
	return super._stop(sim, stop)


## The novice's resources stop with the lightest raw material first (coal before iron: the bag fills with iron and
## the storage may have no room for an errand) and errands only when the bag is full.
func _buy_raw(sim: Sim) -> Dictionary:
	var need := _raw_needs(sim)
	if need.is_empty():
		return {}
	var loc := str(sim.state.characters[ACTOR].get("location", ""))
	if Market.stall_at(sim, ACTOR) != RAW_STALL:
		if loc != "":
			return {"type": "exit_building", "actor": ACTOR}
		return {"type": "move_to", "actor": ACTOR, "tile": _service(sim, RAW_STALL)}
	var items: Array = RAW.duplicate()
	items.sort_custom(func(a: String, b: String) -> bool:
		return float(sim.catalog.item(a).get("weight", 1.0)) < float(sim.catalog.item(b).get("weight", 1.0)))
	for item: String in items:
		if not need.has(item):
			continue
		var hand := mini(int(need[item]), Market.max_buy(sim, ACTOR, RAW_STALL, item, Inventory.NORMAL))
		if hand > 0:
			return {"type": "buy", "actor": ACTOR, "stall": RAW_STALL, "item": item, "quality": Inventory.NORMAL,
				"qty": hand}
	for item: String in items:
		if not need.has(item):
			continue
		var sent := mini(int(need[item]), Market.max_buy(sim, ACTOR, RAW_STALL, item, Inventory.NORMAL, FORGE))
		if sent > 0:
			return {"type": "buy", "actor": ACTOR, "stall": RAW_STALL, "item": item, "quality": Inventory.NORMAL,
				"qty": sent, "deliver_to": FORGE}
	return {}


## Buys at `stall` the next upgrade's materials it sells: in the bag (what fits), the rest by errand only for items no
## recipe uses (they wait in the storage safely).
func _buy_upgrade_items(sim: Sim, stall: String) -> Dictionary:
	var need := _upgrade_needs(sim) if _business(sim) else {}
	var loc := str(sim.state.characters[ACTOR].get("location", ""))
	for item: String in need:
		if _stall_of(sim, item) != stall:
			continue
		if Market.stall_at(sim, ACTOR) != stall:
			if loc != "":
				return {"type": "exit_building", "actor": ACTOR}
			return {"type": "move_to", "actor": ACTOR, "tile": _service(sim, stall)}
		var want := int(need[item])
		var hand := mini(want, Market.max_buy(sim, ACTOR, stall, item, Inventory.NORMAL))
		if hand > 0:
			return {"type": "buy", "actor": ACTOR, "stall": stall, "item": item, "quality": Inventory.NORMAL, "qty": hand}
		if true:  # the rest by errand: buy_upgrade goes the minute they arrive (_buy_upgrade every minute)
			var sent := mini(want, Market.max_buy(sim, ACTOR, stall, item, Inventory.NORMAL, FORGE))
			if sent > 0:
				return {"type": "buy", "actor": ACTOR, "stall": stall, "item": item, "quality": Inventory.NORMAL,
					"qty": sent, "deliver_to": FORGE}
	return {}


## With two or more employees the one furnace cannot make the ingots of three workers: it keeps
## INGOTS_PER_EXTRA_HAND × (hands − 1) ingots in the storage, bought at the materials stall (by errand when the bag is
## full). 0 when it has them.
func _ingots_to_buy(sim: Sim) -> int:
	if not _business(sim) or _active_staff(sim).size() < 2:
		return 0
	var want := INGOTS_PER_EXTRA_HAND * (_active_staff(sim).size() - 1)
	var have := Inventory.count(sim.state.buildings[FORGE]["inventory"], "iron_ingot") \
		+ Inventory.count(sim.state.characters[ACTOR]["inventory"], "iron_ingot")
	for d: Dictionary in Market.pending(sim, _fam(sim)):
		if str(d["item"]) == "iron_ingot":
			have += int(d["qty"])
	var price := Market.price(sim, "iron_ingot", Inventory.NORMAL, "buy")
	if Money.gold(sim.state, _fam(sim)) < _reserve(sim) + price * (want - have):
		return 0
	return maxi(0, want - have)


func _buy_ingots(sim: Sim) -> Dictionary:
	var n := _ingots_to_buy(sim)
	if n <= 0:
		return {}
	var loc := str(sim.state.characters[ACTOR].get("location", ""))
	if Market.stall_at(sim, ACTOR) != MATERIAL_STALL:
		if loc != "":
			return {"type": "exit_building", "actor": ACTOR}
		return {"type": "move_to", "actor": ACTOR, "tile": _service(sim, MATERIAL_STALL)}
	var sent := mini(n, Market.max_buy(sim, ACTOR, MATERIAL_STALL, "iron_ingot", Inventory.NORMAL, FORGE))
	if sent > 0:
		return {"type": "buy", "actor": ACTOR, "stall": MATERIAL_STALL, "item": "iron_ingot",
			"quality": Inventory.NORMAL, "qty": sent, "deliver_to": FORGE}
	return {}


func _stall_of(sim: Sim, item: String) -> String:
	var kind := str(sim.catalog.item(item).get("market_stall", ""))
	for s: String in sim.catalog.market.get("stalls", {}):
		if kind in (sim.catalog.market["stalls"][s].get("sells", []) as Array):
			return s
	return ""


func _used_by_recipes(sim: Sim, item: String) -> bool:
	for rid: String in sim.catalog.recipes():
		for inp: Dictionary in sim.catalog.recipes()[rid].get("inputs", []):
			if str(inp["item"]) == item:
				return true
	return false


# --- Hooks of the novice ---------------------------------------------------------------------------------------------

## Sells while the demand is at least EXPERT_MIN_DEMAND (in business mode; before, the novice's habit). What is made
## is sunk: holding it only fills the storage and stops the queue.
func _sell_ok(sim: Sim, item: String, q: int) -> bool:
	if not _business(sim):
		return super._sell_ok(sim, item, q)
	return Market.demand(sim, item) >= EXPERT_MIN_DEMAND - 0.000001


func _want_buy(sim: Sim, idle: bool) -> bool:
	if _business(sim) and not _active_staff(sim).is_empty() and not _raw_needs(sim).is_empty():
		return true
	return super._want_buy(sim, idle)


## Raw materials for the employees' next pieces: what the queue still has to make, plus STAFF_PIECES per active
## employee of the recipe they would get.
func _extra_plan(sim: Sim) -> Array:
	var out: Array = []
	if not _business(sim):
		return out
	var hands := _active_staff(sim).size() + (1 if Staff.employees_of(sim.state, FORGE).size() > _active_staff(sim).size() else 0)
	if hands == 0:
		return out
	var q: Dictionary = sim.state.buildings[FORGE].get("queue", {})
	for e: Dictionary in q.get("entries", []):
		if int(e["qty"]) != WorkQueue.INFINITE:
			for i: int in maxi(0, int(e["qty"]) - int(e["done"])):
				out.append(str(e["recipe"]))
	var rid := _staff_recipe(sim)
	if rid == "":
		var anyr: Array = out.duplicate()
		rid = str(anyr[0]) if not anyr.is_empty() else ""
	while rid != "" and out.size() < hands * STAFF_PIECES:
		out.append(rid)
	return out


## Its own pieces come on top of the employees' (the novice's BATCH counts everything).
func _batch(sim: Sim, planned: int) -> int:
	return BATCH + planned if _business(sim) else super._batch(sim, planned)


func _capacity(sim: Sim) -> float:
	return 1.0 + 0.5 * _active_staff(sim).size() if _business(sim) else 1.0


## In business mode EXPERT_HELD, or EXPERT_HELD_SINGLE for products that take a storage stack each (max_stack 1).
func _max_held(sim: Sim, rid: String) -> int:
	if not _business(sim):
		return super._max_held(sim, rid)
	if int(sim.catalog.item(_output(sim, rid)).get("max_stack", 1)) <= 1:
		return EXPERT_HELD_SINGLE
	return EXPERT_HELD


## Work by hand at a free station of the right kind (employees may hold the others; upgrades add copies such as
## anvil_2); nothing while the forge is under works.
func _make(sim: Sim, rid: String, mode: String) -> Dictionary:
	if rid == "" or Upgrades.under_works(sim.state, FORGE):
		return {}
	var anvil := _free_zone(sim, ANVIL)
	var st := _status(sim, anvil, rid) if anvil != "" else ""
	if st == "ok":
		return {"zone": anvil, "recipe": rid, "mode": mode}
	var furnace := _free_zone(sim, FURNACE)
	if furnace == "":
		return {}
	if (st == "missing_inputs" or anvil == "") and _status(sim, furnace, INGOT_RECIPE) == "ok" \
			and _status(sim, ANVIL, rid) != "locked":
		if anvil == "" and _status(sim, ANVIL, rid) == "ok":
			return {}  # the anvil is taken but the ingots are there: no need for more
		return {"zone": furnace, "recipe": INGOT_RECIPE, "mode": "normal"}
	return {}


## The station of `kind` the protagonist may take now: the one it holds, else the first one nobody else holds.
func _free_zone(sim: Sim, kind: String) -> String:
	var zones: Dictionary = sim.state.buildings[FORGE].get("zones", {})
	var mine := str(sim.state.characters[ACTOR].get("station", ""))
	if zones.has(mine) and Upgrades.zone_kind(sim, FORGE, mine) == kind:
		return mine
	var ids: Array = zones.keys()
	ids.sort()
	for z: String in ids:
		if Upgrades.zone_kind(sim, FORGE, z) != kind:
			continue
		var occ := str(zones[z].get("occupant", ""))
		var job: Variant = zones[z].get("job")
		if (occ == "" or occ == ACTOR) and not (job is Dictionary and str(job.get("actor", "")) != ACTOR):
			return z
	return ""


## With employees at work the protagonist is the salesman: during market hours it starts work by hand only when it
## has nothing to sell, deliver or buy (contract pieces still come first, as for the novice).
func _work(sim: Sim) -> Dictionary:
	if owner_sells and _business(sim) and not _active_staff(sim).is_empty() and _may_leave(sim) \
			and _contracts_by_due(sim).is_empty():
		if not _to_sell(sim).is_empty() or not _raw_needs(sim).is_empty():
			return {}
	return super._work(sim)
