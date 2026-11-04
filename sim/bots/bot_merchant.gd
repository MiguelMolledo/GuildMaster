class_name BotMerchant
extends RefCounted
## Bot that travels and trades (docs/gdd/09b_region.md §9b.5; scenario travel_start: the forge with two employees,
## the family a citizen, 6 swords in the forge). On the first morning it buys a cart and sends a caravan with the first
## employee as carter to the quarry, escorted, to buy iron and coal cheap for the forge; afterwards, whenever the cart
## is back and the forge has CARAVAN_SWORDS swords, the caravan takes them to the capital (with a minimum price). The
## head takes the swords it can carry out of the forge and travels to the capital (weapons ×1.25, tariff 10 %) to open
## the market, and again only to deliver a contract it owes there or to sign a sword quota once its reputation there
## (mostly the caravans' sales) allows it: it delivers, sells the rest, accepts a contract of swords if the board has
## one, signs, and comes back. At home it keeps a queue of swords for
## the employees and works a free station itself until there are swords for another trip, and it goes again. Everything through the same orders and queries as the UI. Measures that travel, caravans,
## the city market, contracts and treaties hold up for days without refused orders.

const ID: String = "merchant"
const CITY: String = "capital"
const SUPPLY_CITY: String = "quarry"
const TRIP_SWORDS: int = 3      # swords it waits for before setting out again (what it can carry; test bot)
const CARAVAN_SWORDS: int = 3   # swords a caravan waits for in the forge (test bot, not a rule)
const MIN_PRICE: int = 30       # the caravan's minimum unit price for a sword in the capital (test bot)

var _sent: bool = false
var _hero: String = ""
var _forge: String = ""


func orders(sim: Sim) -> Array:
	var st := sim.state
	var fam := SimQuery.player_family(st)
	if fam == "":
		return []
	if _hero == "":
		_hero = str(st.families[fam].get("head", ""))
		for b: String in Region._sorted_keys(st.buildings):
			if str(st.buildings[b]["owner"]) == fam and str(st.buildings[b]["type"]) == "forge":
				_forge = b
				break
	if not Kin.alive(st, _hero) or _forge == "":
		return []
	var ch: Dictionary = st.characters[_hero]
	var o := _caravan(sim, fam)
	if not o.is_empty():
		return o
	var here := Travel.in_city(st, _hero)
	if here == CITY:
		return _in_city(sim, fam)
	if Region.is_away(st, _hero):
		return []   # on the road
	if not (ch.get("order_queue", []) as Array).is_empty() or not (ch.get("path", []) as Array).is_empty():
		return []
	var inv: Dictionary = ch["inventory"]
	var carried := Inventory.count(inv, "sword", Inventory.NORMAL)
	var in_forge := Inventory.count(st.buildings[_forge]["inventory"], "sword", Inventory.NORMAL)
	if _wants_trip(sim, fam) and carried + in_forge >= _swords_wanted(sim, fam) \
			and Travel.can_travel(sim, _hero, CITY) == "":
		if in_forge > 0:
			if str(ch.get("location", "")) != _forge:
				if str(ch.get("location", "")) != "":
					return [{"type": "exit_building", "actor": _hero}]
				return [{"type": "enter_building", "actor": _hero, "building": _forge}]
			if Production.job_zone(sim, _hero, _forge) != "":
				return [{"type": "stop_work", "actor": _hero}]
			var n := Inventory.fit_count(inv, sim.catalog, "sword", Inventory.NORMAL, in_forge)
			if n > 0:
				return [{"type": "transfer", "actor": _hero, "from": _forge, "to": _hero, "item": "sword",
					"quality": Inventory.NORMAL, "qty": n}]
		return [{"type": "travel", "actor": _hero, "to": CITY}]
	if (st.buildings[_forge].get("queue", {}).get("entries", []) as Array).is_empty():
		return [{"type": "queue_add", "actor": _hero, "building": _forge, "recipe": "forge_sword", "qty": -1}]
	return _work(sim)


## At home the head works too, at a free station of the forge: the anvil (swords) if it can, else the furnace
## (ingots); never on a station an employee holds.
func _work(sim: Sim) -> Array:
	var ch: Dictionary = sim.state.characters[_hero]
	if str(ch.get("location", "")) != _forge:
		if str(ch.get("location", "")) != "":
			return [{"type": "exit_building", "actor": _hero}]
		return [{"type": "enter_building", "actor": _hero, "building": _forge}]
	if Production.job_zone(sim, _hero, _forge) != "":
		return []
	var zones: Dictionary = sim.state.buildings[_forge].get("zones", {})
	for pair: Array in [["anvil", "forge_sword"], ["furnace", "forge_ingot"]]:
		var z: Dictionary = zones.get(pair[0], {})
		if str(z.get("occupant", "")) not in ["", _hero] or z.get("job") is Dictionary:
			continue
		for opt: Dictionary in Production.recipe_options(sim, _hero, _forge, str(pair[0])):
			if str(opt["recipe"]) == str(pair[1]) and str(opt["status"]) == "ok":
				return [{"type": "work_at", "actor": _hero, "building": _forge, "zone": pair[0], "recipe": pair[1],
					"mode": "normal"}]
	return []


## The head travels to open the market (its first trip), to deliver a contract it owes there, or to sign the
## quota once its reputation there (the caravans' sales) allows it; the rest of the time it works at home.
func _wants_trip(sim: Sim, fam: String) -> bool:
	if int((Region.ensure(sim)["stats"] as Dictionary).get(fam, {}).get("arrivals", 0)) == 0:
		return true
	for a: Dictionary in Region.ensure(sim)["contracts"]:
		if str(a["family"]) == fam and str(a["city"]) == CITY:
			return true
	return Treaties.quota_of(sim, CITY, fam, "sword").is_empty() \
		and Treaties.can_sign(sim, fam, CITY, "quota", "sword") == ""


## The swords to gather before a trip: TRIP_SWORDS for the first one, or the accepted contract's quantity; a trip only
## to sign the quota waits for none.
func _swords_wanted(sim: Sim, fam: String) -> int:
	var first := int((Region.ensure(sim)["stats"] as Dictionary).get(fam, {}).get("arrivals", 0)) == 0
	var need := TRIP_SWORDS if first else 0
	for a: Dictionary in Region.ensure(sim)["contracts"]:
		if str(a["family"]) == fam and str(a["city"]) == CITY and str(a["item"]) == "sword":
			need = maxi(need, int(a["qty"]))
	return need


## A cart (the first morning), then a caravan whenever one is free: first to the quarry for iron and coal
## (escorted), afterwards to the capital with the forge's swords.
func _caravan(sim: Sim, fam: String) -> Array:
	var st := sim.state
	if Caravans.carts(sim, fam) == 0:
		if not _sent and Money.can_pay(st, fam, int(sim.catalog.trade.get("caravans", {}).get("cart_price", 120))):
			return [{"type": "buy_cart", "actor": _home_actor(sim, fam)}]
		return []
	if Caravans.busy_carts(sim, fam) >= Caravans.carts(sim, fam):
		return []
	var driver := ""
	var staff: Array = Region._sorted_keys(st.characters).filter(func(c: String) -> bool:
		var job: Variant = st.characters[c].get("job")
		return job is Dictionary and str(job.get("building", "")) == _forge)
	if not staff.is_empty() and not Region.is_away(st, str(staff[-1])):
		driver = str(staff[-1])   # the last one carts; the first keeps the anvil
	if driver == "":
		return []
	var o := {}
	if not _sent:
		o = {"type": "caravan_send", "actor": _home_actor(sim, fam), "driver": driver, "building": _forge,
			"city": SUPPLY_CITY, "cargo": [], "buy": [{"item": "iron", "qty": 10, "max_price": 0},
			{"item": "coal", "qty": 6, "max_price": 0}], "escort": true}
	else:
		var n := Inventory.count(st.buildings[_forge]["inventory"], "sword", Inventory.NORMAL)
		if n < CARAVAN_SWORDS:
			return []
		o = {"type": "caravan_send", "actor": _home_actor(sim, fam), "driver": driver, "building": _forge, "city": CITY,
			"cargo": [{"item": "sword", "quality": Inventory.NORMAL, "qty": n, "min_price": MIN_PRICE}], "buy": [],
			"escort": false}
	if Caravans.can_send(sim, o) != "":
		return []
	_sent = true
	return [o]


## Who gives the management orders at home: the head if it is there, else the next of the group at home.
func _home_actor(sim: Sim, fam: String) -> String:
	if not Region.is_away(sim.state, _hero):
		return _hero
	for c: String in Kin.group(sim.state, fam):
		if not Region.is_away(sim.state, c):
			return c
	return ""


## In the capital: deliver what it can, sell the swords left, take a sword contract, sign a sword quota; then home.
func _in_city(sim: Sim, fam: String) -> Array:
	var st := sim.state
	var inv: Dictionary = st.characters[_hero]["inventory"]
	for a: Dictionary in Region.ensure(sim)["contracts"]:
		if str(a["family"]) == fam and str(a["city"]) == CITY and Inventory.count(inv, str(a["item"])) >= int(a["qty"]):
			return [{"type": "city_deliver", "actor": _hero, "contract": a["id"]}]
	var mine := false
	for a: Dictionary in Region.ensure(sim)["contracts"]:
		if str(a["family"]) == fam:
			mine = true
	if not mine:
		for off: Dictionary in Region.city(sim, CITY)["board"]:
			if str(off["item"]) == "sword":
				return [{"type": "city_accept", "actor": _hero, "contract": off["id"]}]
	var swords := Inventory.count(inv, "sword", Inventory.NORMAL)
	if swords > 0:
		return [{"type": "city_sell", "actor": _hero, "item": "sword", "quality": Inventory.NORMAL, "qty": swords}]
	if Treaties.quota_of(sim, CITY, fam, "sword").is_empty() and Treaties.can_sign(sim, fam, CITY, "quota", "sword") == "":
		return [{"type": "sign_treaty", "actor": _hero, "kind": "quota", "item": "sword"}]
	if Travel.can_travel(sim, _hero, Region.home(sim)) == "":
		return [{"type": "return", "actor": _hero}]
	return []
