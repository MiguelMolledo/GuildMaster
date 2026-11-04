class_name Caravans
extends RefCounted
## Caravans (docs/gdd/09b_region.md §9b.5, O-R4 c). A family buys carts (buy_cart: trade.json caravans.cart_price; at
## dawn cart_upkeep each) and sends one (caravan_send) with one of its employees as the carter: the cargo leaves one of
## its buildings' storage, the cart goes leg by leg along the shortest open way to a city (toll and escort per leg, an
## ambush roll per leg: it takes the cargo, never the cart), sells there each cargo line unit by unit while a unit
## gives at least its min_price after tariff, delivers the family's accepted contracts of that city it carries, buys
## its shopping list (each line up to qty while a unit costs at most max_price), stays stay_hours and comes back the
## same way to unload into that building (what does not fit waits in the cart at the door). The carter is away the
## whole time (Region.is_away); its wage goes on.
## State: state.region.carts {fam: n}; state.region.caravans [{id, family, driver, building, city, path, leg, at,
## leg_start, leg_end, dir "out" | "back", state "road" | "city" | "waiting" (no gold for a toll) | "unloading", until, escort, cargo [{item, quality,
## qty, min_price}], buy [{item, qty, max_price}], sold, bought}].


static func carts(sim: Sim, fam: String) -> int:
	return int((Region.ensure(sim)["carts"] as Dictionary).get(fam, 0))


static func busy_carts(sim: Sim, fam: String) -> int:
	var n := 0
	for c: Dictionary in Region.ensure(sim)["caravans"]:
		if str(c["family"]) == fam:
			n += 1
	return n


static func _cfg(sim: Sim) -> Dictionary:
	return sim.catalog.trade.get("caravans", {})


## {"type": "buy_cart", "actor"}: management. Reasons: unknown_actor, no_family, title_needed, too_many_carts,
## not_enough_gold.
static func order_buy_cart(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var fam := str(st.characters[actor].get("family", ""))
	if not st.families.has(fam):
		return Orders.fail("no_family")
	var why := Travel.unlock_reason(sim, fam)
	if why != "":
		return Orders.fail(why)
	if carts(sim, fam) >= int(_cfg(sim).get("max_carts", 2)):
		return Orders.fail("too_many_carts")
	var price := int(_cfg(sim).get("cart_price", 120))
	if not Money.can_pay(st, fam, price):
		return Orders.fail("not_enough_gold")
	Money.change(sim, fam, -price, Money.PROPERTY, "cart", "", actor)
	Region.ensure(sim)["carts"][fam] = carts(sim, fam) + 1
	sim.events.append({"type": "cart_bought", "family": fam, "carts": carts(sim, fam)})
	if OS.is_debug_build():
		print("[Caravans] %s compra un carro (%d oro, tiene %d)" % [fam, price, carts(sim, fam)])
	return Orders.ok()


## At dawn: the upkeep of every cart (without the gold, it is not paid and a notice says so).
static func upkeep(sim: Sim) -> void:
	var per := int(_cfg(sim).get("cart_upkeep", 2))
	var cs: Dictionary = Region.ensure(sim)["carts"]
	var fams: Array = cs.keys()
	fams.sort()
	for fam: String in fams:
		var due := per * int(cs[fam])
		if due <= 0:
			continue
		if not Money.change(sim, fam, -due, Money.UPKEEP, "cart_upkeep"):
			Notices.add(sim, fam, Notices.WARNING, "notice.cart_upkeep_unpaid", {"gold": due})


## "" if the caravan of order `o` may leave now, else why: unknown_actor, no_family, no_free_cart, unknown_driver,
## not_your_employee, driver_away, unknown_building, not_your_building, unknown_city, no_open_route, empty_caravan,
## bad_line, not_enough, too_many_stacks, not_enough_gold.
static func can_send(sim: Sim, o: Dictionary) -> String:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return "unknown_actor"
	var fam := str(st.characters[actor].get("family", ""))
	if not st.families.has(fam):
		return "no_family"
	if carts(sim, fam) - busy_carts(sim, fam) <= 0:
		return "no_free_cart"
	var driver := str(o.get("driver", ""))
	var dch: Dictionary = st.characters.get(driver, {})
	if dch.is_empty() or not Kin.alive(st, driver):
		return "unknown_driver"
	var job: Variant = dch.get("job")
	var bld := str(o.get("building", ""))
	if not job is Dictionary or str(st.buildings.get(str(job.get("building", "")), {}).get("owner", "")) != fam:
		return "not_your_employee"
	if Region.is_away(st, driver):
		return "driver_away"
	if not st.buildings.has(bld):
		return "unknown_building"
	if str(st.buildings[bld].get("owner", "")) != fam:
		return "not_your_building"
	var c := str(o.get("city", ""))
	if not Region.is_city(sim, c):
		return "unknown_city"
	var p := Region.path(sim, Region.home(sim), c)
	if p.is_empty():
		return "no_open_route"
	var cargo: Array = o.get("cargo", [])
	var buy: Array = o.get("buy", [])
	if cargo.is_empty() and buy.is_empty():
		return "empty_caravan"
	var inv: Dictionary = st.buildings[bld].get("inventory", {})
	var need := {}
	for l: Dictionary in cargo:
		if sim.catalog.item(str(l.get("item", ""))).is_empty() or int(l.get("qty", 0)) <= 0:
			return "bad_line"
		var k := "%s|%d" % [l["item"], int(l.get("quality", 0))]
		need[k] = int(need.get(k, 0)) + int(l["qty"])
	for k: String in need:
		var parts := k.split("|")
		if Inventory.count(inv, parts[0], int(parts[1])) < int(need[k]):
			return "not_enough"
	for l: Dictionary in buy:
		if sim.catalog.item(str(l.get("item", ""))).is_empty() or int(l.get("qty", 0)) <= 0:
			return "bad_line"
	if need.size() + buy.size() > int(_cfg(sim).get("capacity_stacks", 6)):
		return "too_many_stacks"
	if not Money.can_pay(st, fam, Travel.leg_cost(sim, Region.route(sim, str(p[0])), bool(o.get("escort", false)))):
		return "not_enough_gold"
	return ""


## {"type": "caravan_send", "actor", "driver", "building", "city", "cargo": [{item, quality, qty, min_price}],
## "buy": [{item, qty, max_price}], "escort"?: bool}: management. Reasons: can_send's.
static func order_send(sim: Sim, o: Dictionary) -> Dictionary:
	var why := can_send(sim, o)
	if why != "":
		return Orders.fail(why)
	var st := sim.state
	var fam := str(st.characters[str(o["actor"])].get("family", ""))
	var bld := str(o["building"])
	var inv: Dictionary = st.buildings[bld]["inventory"]
	var cargo: Array = []
	for l: Dictionary in o.get("cargo", []):
		Inventory.remove(inv, str(l["item"]), int(l.get("quality", 0)), int(l["qty"]))
		cargo.append({"item": str(l["item"]), "quality": int(l.get("quality", 0)), "qty": int(l["qty"]),
			"min_price": int(l.get("min_price", 0))})
	var buy: Array = []
	for l: Dictionary in o.get("buy", []):
		buy.append({"item": str(l["item"]), "qty": int(l["qty"]), "max_price": int(l.get("max_price", 0))})
	var driver := str(o["driver"])
	Region.take_off_map(sim, driver)
	var now := int(st.clock["minute"])
	var home := Region.home(sim)
	var c := {"id": Ids.next(st, "crv"), "family": fam, "driver": driver, "building": bld, "city": str(o["city"]),
		"path": Region.path(sim, home, str(o["city"])), "leg": 0, "at": home, "leg_start": now, "leg_end": now,
		"dir": "out", "state": "road", "until": 0, "escort": bool(o.get("escort", false)), "cargo": cargo,
		"buy": buy, "sold": 0, "bought": []}
	(Region.ensure(sim)["caravans"] as Array).append(c)
	Region.stat(sim, fam, "caravans_sent")
	sim.events.append({"type": "caravan_sent", "family": fam, "caravan": c["id"], "city": c["city"],
		"driver": driver})
	if OS.is_debug_build():
		print("[Caravans] %s manda la caravana %s a %s con %s (carretero %s, compra %s)" % [fam, c["id"], c["city"],
			cargo, driver, buy])
	_start_leg(sim, c)
	return Orders.ok()


static func _start_leg(sim: Sim, c: Dictionary) -> void:
	var r := Region.route(sim, str(c["path"][int(c["leg"])]))
	var cost := Travel.leg_cost(sim, r, bool(c["escort"]))
	var fam := str(c["family"])
	var now := int(sim.state.clock["minute"])
	if cost > 0 and not Money.can_pay(sim.state, fam, cost):
		# without the gold for the toll (and the escort) the cart waits where it is and tries again in an hour
		if str(c["state"]) != "waiting":
			Notices.add(sim, fam, Notices.WARNING, "notice.caravan_toll_unpaid", {"gold": cost})
		c["state"] = "waiting"
		c["until"] = now + 60
		return
	if int(r.get("toll", 0)) > 0:
		Money.change(sim, fam, -int(r["toll"]), Money.TAXES, "toll", "", str(c["driver"]))
	if bool(c["escort"]):
		Money.change(sim, fam, -(cost - int(r.get("toll", 0))), Money.SERVICES, "escort", "", str(c["driver"]))
	c["state"] = "road"
	c["leg_start"] = now
	c["leg_end"] = now + Region.leg_minutes(sim, r)


## Every minute: legs that end, the stay in the city that ends, unloading at home.
static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var list: Array = Region.ensure(sim)["caravans"]
	for c: Dictionary in list.duplicate():
		match str(c["state"]):
			"road":
				if now >= int(c["leg_end"]):
					_end_leg(sim, c)
			"city":
				if now >= int(c["until"]):
					_go_back(sim, c)
			"waiting":
				if now >= int(c["until"]):
					_start_leg(sim, c)
			"unloading":
				_unload(sim, c)


static func _end_leg(sim: Sim, c: Dictionary) -> void:
	var rid := str(c["path"][int(c["leg"])])
	var r := Region.route(sim, rid)
	if Region.ambushed(sim, r, bool(c["escort"]), "crv|%s|%s|%d|%s" % [c["id"], c["dir"], int(c["leg"]), rid]):
		var lost: Array = (c["cargo"] as Array) + (c["bought"] as Array)
		c["cargo"] = []
		c["bought"] = []
		Region.stat(sim, str(c["family"]), "caravan_ambushes")
		sim.events.append({"type": "caravan_ambushed", "family": c["family"], "caravan": c["id"], "route": rid,
			"lost": lost})
		Notices.add(sim, str(c["family"]), Notices.URGENT, "notice.caravan_ambushed", {"count": lost.size()})
		if OS.is_debug_build():
			print("[Caravans] ¡asalto a la caravana %s en %s! pierde %s" % [c["id"], rid, lost])
	c["at"] = Region.other_end(sim, rid, str(c["at"]))
	c["leg"] = int(c["leg"]) + 1
	if int(c["leg"]) < (c["path"] as Array).size():
		_start_leg(sim, c)
	elif str(c["dir"]) == "out":
		_trade(sim, c)
	else:
		c["state"] = "unloading"
		_unload(sim, c)


## In the city: contracts it can deliver, then the cargo (min prices), then the shopping list; then the stay.
static func _trade(sim: Sim, c: Dictionary) -> void:
	var fam := str(c["family"])
	var city := str(c["city"])
	var inv := _cart_inventory(sim, c)
	for a: Dictionary in (Region.ensure(sim)["contracts"] as Array).duplicate():
		if str(a["family"]) == fam and str(a["city"]) == city:
			CityTrade.deliver_from(sim, a, inv, str(c["driver"]))
	_from_inventory(c, inv)
	var total := 0
	for l: Dictionary in c["cargo"]:
		var r := CityTrade.sell_units(sim, city, fam, str(l["item"]), int(l["quality"]), int(l["qty"]),
			int(l.get("min_price", 0)))
		if int(r["sold"]) > 0:
			CityTrade._book_sale(sim, city, fam, str(c["driver"]), str(l["item"]), r)
			total += int(r["total"])
		l["qty"] = int(l["qty"]) - int(r["sold"])
	c["cargo"] = (c["cargo"] as Array).filter(func(l: Dictionary) -> bool: return int(l["qty"]) > 0)
	c["sold"] = total
	var stacks := (c["cargo"] as Array).size()
	var cap := int(_cfg(sim).get("capacity_stacks", 6))
	for l: Dictionary in c["buy"]:
		if stacks >= cap:
			break
		var r := CityTrade.buy_units(sim, city, fam, str(l["item"]), int(l["qty"]), int(l.get("max_price", 0)),
			func(_n: int) -> bool: return true)
		if int(r["bought"]) <= 0:
			continue
		Money.change(sim, fam, -int(r["cost"]), Money.PURCHASES, "caravan_buy:" + city, "", str(c["driver"]))
		(c["bought"] as Array).append({"item": str(l["item"]), "quality": Inventory.NORMAL, "qty": int(r["bought"])})
		Region.stat(sim, fam, "city_buys_gold", int(r["cost"]))
		stacks += 1
	c["state"] = "city"
	c["until"] = int(sim.state.clock["minute"]) + int(float(_cfg(sim).get("stay_hours", 2)) * 60.0)
	Region.stat(sim, fam, "caravans_arrived")
	sim.events.append({"type": "caravan_arrived", "family": fam, "caravan": c["id"], "city": city, "sold": total,
		"bought": c["bought"]})
	Notices.add(sim, fam, Notices.INFO, "notice.caravan_arrived", {"city": str(Region.settlement(sim, city).get("name_key",
		city)), "gold": total})
	if OS.is_debug_build():
		print("[Caravans] %s en %s: vende por %d, compra %s, le queda %s" % [c["id"], city, total, c["bought"], c["cargo"]])


## The cargo as an inventory (to deliver contracts from it).
static func _cart_inventory(sim: Sim, c: Dictionary) -> Dictionary:
	var inv := Inventory.create("stacks", 99)
	for l: Dictionary in c["cargo"]:
		Inventory.add(inv, sim.catalog, str(l["item"]), int(l["quality"]), int(l["qty"]))
	return inv


## Puts back into the cargo lines what is left in `inv` (after delivering contracts).
static func _from_inventory(c: Dictionary, inv: Dictionary) -> void:
	for l: Dictionary in c["cargo"]:
		l["qty"] = mini(int(l["qty"]), Inventory.count(inv, str(l["item"]), int(l["quality"])))
		Inventory.remove(inv, str(l["item"]), int(l["quality"]), int(l["qty"]))
	c["cargo"] = (c["cargo"] as Array).filter(func(l: Dictionary) -> bool: return int(l["qty"]) > 0)


static func _go_back(sim: Sim, c: Dictionary) -> void:
	var p := Region.path(sim, str(c["city"]), Region.home(sim))
	if p.is_empty():
		c["until"] = int(sim.state.clock["minute"]) + 60  # every way home is cut: it waits an hour more
		return
	c["path"] = p
	c["leg"] = 0
	c["dir"] = "back"
	_start_leg(sim, c)


## Back home: into the building's storage what fits; the rest waits in the cart (tried every minute). When empty, the
## carter is back at the building's door and the cart is free.
static func _unload(sim: Sim, c: Dictionary) -> void:
	var st := sim.state
	var bld := str(c["building"])
	var inv: Dictionary = st.buildings.get(bld, {}).get("inventory", {})
	var left: Array = []
	for l: Dictionary in (c["cargo"] as Array) + (c["bought"] as Array):
		var n := Inventory.fit_count(inv, sim.catalog, str(l["item"]), int(l["quality"]), int(l["qty"])) \
			if not inv.is_empty() else 0
		if n > 0:
			Inventory.add(inv, sim.catalog, str(l["item"]), int(l["quality"]), n)
		if int(l["qty"]) - n > 0:
			left.append({"item": l["item"], "quality": l["quality"], "qty": int(l["qty"]) - n})
	c["cargo"] = left
	c["bought"] = []
	if not left.is_empty():
		return
	var tile: Array = st.buildings.get(bld, {}).get("door", Region.gate_tile(sim))
	(Region.ensure(sim)["caravans"] as Array).erase(c)
	Region.put_on_map(sim, str(c["driver"]), tile)
	Region.stat(sim, str(c["family"]), "caravans_back")
	sim.events.append({"type": "caravan_back", "family": c["family"], "caravan": c["id"], "sold": c["sold"]})
	Notices.add(sim, str(c["family"]), Notices.INFO, "notice.caravan_back", {"gold": int(c["sold"])})
	if OS.is_debug_build():
		print("[Caravans] %s vuelve a %s (había vendido por %d)" % [c["id"], bld, int(c["sold"])])


## Where a caravan is, for the view: {state, at, next, route, progress, city, dir}.
static func progress(sim: Sim, c: Dictionary) -> Dictionary:
	if str(c["state"]) != "road":
		return {"state": c["state"], "at": c["at"], "city": c["city"], "dir": c["dir"]}
	var rid := str(c["path"][int(c["leg"])])
	var span := maxi(1, int(c["leg_end"]) - int(c["leg_start"]))
	var f := clampf(float(int(sim.state.clock["minute"]) - int(c["leg_start"])) / float(span), 0.0, 1.0)
	return {"state": "road", "route": rid, "from": c["at"], "next": Region.other_end(sim, rid, str(c["at"])),
		"progress": f, "city": c["city"], "dir": c["dir"]}
