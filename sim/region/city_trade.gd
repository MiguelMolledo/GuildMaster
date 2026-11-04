class_name CityTrade
extends RefCounted
## Trading in a city away from home (docs/gdd/09b_region.md §9b.5): its market (Region.price: demand_city,
## mod_ciudad, its events), the tariff on what an outsider sells (O-R5 a: none with an exemption treaty; the units of a
## quota treaty go at its fixed price, without tariff) and the city's contracts board («encargos de fuera»). The
## traveller trades in person (city_buy, city_sell, city_accept, city_deliver); a caravan sells and buys through the
## same sell_units / buy_units. Gold through Money.change: market_sales, purchases, taxes (tariff), contracts.
## Offers: state.region.cities[c].board [{id, item, qty, reward, days}]; accepted: state.region.contracts
## [{id, city, family, item, qty, reward, due}].


## "" if `actor` can trade in city `c` now (it is there), else not_in_city / unknown_city.
static func _here(sim: Sim, actor: String) -> String:
	return Travel.in_city(sim.state, actor)


## Sells `qty` of `item` at `quality` for family `fam` in city `c`, unit by unit (each at the demand the one before
## left), while a unit gives at least `min_price` after tariff (0 = any). The units a quota treaty of the family still
## takes this season go first, at its price and without tariff. {sold, total (net), tariff, quota}.
static func sell_units(sim: Sim, c: String, fam: String, item: String, quality: int, qty: int,
		min_price: int = 0) -> Dictionary:
	var tar := Region.tariff(sim, c, fam)
	var out := {"sold": 0, "total": 0, "tariff": 0, "quota": 0}
	var q := Treaties.quota_of(sim, c, fam, item)
	for n: int in qty:
		if not q.is_empty() and int(q["delivered"]) < int(q["qty"]):
			var qp := int(q["price"])
			if qp < min_price:
				break
			q["delivered"] = int(q["delivered"]) + 1
			out["quota"] = int(out["quota"]) + 1
			out["total"] = int(out["total"]) + qp
			out["sold"] = int(out["sold"]) + 1
			continue
		var gross := Region.price(sim, c, item, quality, "sell")
		var cut := roundi(float(gross) * tar)
		if gross - cut < min_price:
			break
		out["total"] = int(out["total"]) + gross - cut
		out["tariff"] = int(out["tariff"]) + cut
		out["sold"] = int(out["sold"]) + 1
		Region.drop_demand(sim, c, item, 1)
	return out


## {"type": "city_sell", "actor", "item", "quality", "qty"}: in the city where the actor is. Reasons: not_in_city,
## unknown_item, not_traded, bad_quality, bad_quantity, not_enough.
static func order_sell(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var c := _here(sim, actor)
	if c == "":
		return Orders.fail("not_in_city")
	var item := str(o.get("item", ""))
	var quality := int(o.get("quality", Inventory.NORMAL))
	var qty := int(o.get("qty", 0))
	if sim.catalog.item(item).is_empty():
		return Orders.fail("unknown_item")
	if not item in Region.traded_items(sim):
		return Orders.fail("not_traded")
	if not quality in Inventory.QUALITIES:
		return Orders.fail("bad_quality")
	if qty <= 0:
		return Orders.fail("bad_quantity")
	var inv: Dictionary = st.characters[actor]["inventory"]
	if Inventory.count(inv, item, quality) < qty:
		return Orders.fail("not_enough")
	var fam := str(st.characters[actor].get("family", ""))
	var r := sell_units(sim, c, fam, item, quality, qty)
	Inventory.remove(inv, item, quality, qty)
	_book_sale(sim, c, fam, actor, item, r)
	return Orders.ok()


static func _book_sale(sim: Sim, c: String, fam: String, actor: String, item: String, r: Dictionary) -> void:
	Money.change(sim, fam, int(r["total"]) + int(r["tariff"]), Money.MARKET_SALES, "city_sell:" + c, "", actor)
	if int(r["tariff"]) > 0:
		Money.change(sim, fam, -int(r["tariff"]), Money.TAXES, "tariff:" + c, "", actor, true)
	Region.stat(sim, fam, "city_sales_gold", int(r["total"]))
	Region.stat(sim, fam, "city_sales_units", int(r["sold"]))
	# every sale_units units sold there (counted across sales) give «sale» reputation
	var cfg: Dictionary = sim.catalog.trade.get("reputation", {})
	var per := maxi(1, int(cfg.get("sale_units", 4)))
	var key := "units_" + c
	var before := int((Region.ensure(sim)["stats"] as Dictionary).get(fam, {}).get(key, 0))
	Region.stat(sim, fam, key, int(r["sold"]))
	var steps := (before + int(r["sold"])) / per - before / per
	Region.add_reputation(sim, c, fam, steps * int(cfg.get("sale", 0)), "sale")
	sim.events.append({"type": "city_sold", "actor": actor, "family": fam, "city": c, "item": item, "qty": r["sold"],
		"total": r["total"], "tariff": r["tariff"], "quota": r["quota"]})
	if OS.is_debug_build():
		print("[CityTrade] %s vende %s x%d en %s por %d (arancel %d, cuota %d, demanda %.2f)" % [actor, item,
			int(r["sold"]), c, int(r["total"]), int(r["tariff"]), int(r["quota"]), Region.demand(sim, c, item)])


## Buys for family `fam` in city `c` up to `qty` of `item` while a unit costs at most `max_price` (0 = any), the gold
## lasts and `fits`(units) says it fits. {bought, cost}. Buying does not move the demand (as at home).
static func buy_units(sim: Sim, c: String, fam: String, item: String, qty: int, max_price: int, fits: Callable) -> Dictionary:
	var unit := Region.price(sim, c, item, Inventory.NORMAL, "buy")
	var n := 0
	if max_price <= 0 or unit <= max_price:
		while n < qty and Money.can_pay(sim.state, fam, unit * (n + 1)) and bool(fits.call(n + 1)):
			n += 1
	return {"bought": n, "cost": unit * n, "unit": unit}


## {"type": "city_buy", "actor", "item", "qty"}: normal quality, into the actor's inventory. Reasons: not_in_city,
## unknown_item, not_traded, bad_quantity, not_enough_gold, too_heavy.
static func order_buy(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var c := _here(sim, actor)
	if c == "":
		return Orders.fail("not_in_city")
	var item := str(o.get("item", ""))
	var qty := int(o.get("qty", 0))
	if sim.catalog.item(item).is_empty():
		return Orders.fail("unknown_item")
	if not item in Region.traded_items(sim):
		return Orders.fail("not_traded")
	if qty <= 0:
		return Orders.fail("bad_quantity")
	var fam := str(st.characters[actor].get("family", ""))
	var inv: Dictionary = st.characters[actor]["inventory"]
	var unit := Region.price(sim, c, item, Inventory.NORMAL, "buy")
	if not Money.can_pay(st, fam, unit * qty):
		return Orders.fail("not_enough_gold")
	if not Inventory.can_add(inv, sim.catalog, item, Inventory.NORMAL, qty):
		return Orders.fail("too_heavy")
	Money.change(sim, fam, -unit * qty, Money.PURCHASES, "city_buy:" + c, "", actor)
	Inventory.add(inv, sim.catalog, item, Inventory.NORMAL, qty)
	Region.stat(sim, fam, "city_buys_gold", unit * qty)
	sim.events.append({"type": "city_bought", "actor": actor, "family": fam, "city": c, "item": item, "qty": qty,
		"cost": unit * qty})
	if OS.is_debug_build():
		print("[CityTrade] %s compra %s x%d en %s por %d" % [actor, item, qty, c, unit * qty])
	return Orders.ok()


# --- The contracts of a city -----------------------------------------------------------------------------------------

## Every item a city pays dear for (its «dear» entries: items, and the sellable items of its goods groups), sorted.
static func dear_items(sim: Sim, c: String) -> Array:
	var out: Array = []
	var dear: Dictionary = Region.settlement(sim, c).get("dear", {})
	for item: String in Region.traded_items(sim):
		if dear.has(item):
			out.append(item)
			continue
		for g: String in sim.catalog.goods_of(item):
			if dear.has(g):
				out.append(item)
				break
	return out


## At day_started: city `c` may post a contract (one keyed roll) while it has fewer than board.max_open.
static func post_offer(sim: Sim, c: String, day: int) -> void:
	var cfg: Dictionary = sim.catalog.trade.get("board", {})
	var cd := Region.city(sim, c)
	var board: Array = cd["board"]
	if board.size() >= int(cfg.get("max_open", 2)):
		return
	if Kin.roll(sim.state, "rgn|board|%s|%d" % [c, day]) >= float(cfg.get("chance", 0.5)):
		return
	var items := dear_items(sim, c)
	if items.is_empty():
		return
	var item: String = items[Kin.randi_range(sim.state, "rgn|board|item|%s|%d" % [c, day], 0, items.size() - 1)]
	var qty := Kin.randi_range(sim.state, "rgn|board|qty|%s|%d" % [c, day], int(cfg.get("qty_min", 2)),
		int(cfg.get("qty_max", 6)))
	var days := Kin.randi_range(sim.state, "rgn|board|days|%s|%d" % [c, day], int(cfg.get("days_min", 2)),
		int(cfg.get("days_max", 4)))
	var reward := roundi(float(sim.catalog.item(item).get("base_price", 0)) * qty * float(cfg.get("reward_mult", 1.4)))
	board.append({"id": Ids.next(sim.state, "rct"), "item": item, "qty": qty, "reward": reward, "days": days})
	if OS.is_debug_build():
		print("[CityTrade] %s publica un encargo: %s x%d por %d en %d días" % [c, item, qty, reward, days])


## {"type": "city_accept", "actor", "contract"}: takes an offer of the city where the actor is. Reasons: not_in_city,
## unknown_contract.
static func order_accept(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var c := _here(sim, actor)
	if c == "":
		return Orders.fail("not_in_city")
	var board: Array = Region.city(sim, c)["board"]
	var id := str(o.get("contract", ""))
	for i: int in board.size():
		var off: Dictionary = board[i]
		if str(off["id"]) != id:
			continue
		board.remove_at(i)
		var fam := str(sim.state.characters[actor].get("family", ""))
		var due := int(sim.state.clock["minute"]) + int(off["days"]) * Clock.MINUTES_PER_DAY
		var acc := {"id": id, "city": c, "family": fam, "item": off["item"], "qty": off["qty"], "reward": off["reward"],
			"due": due}
		(Region.ensure(sim)["contracts"] as Array).append(acc)
		sim.events.append({"type": "city_contract_accepted", "family": fam, "city": c, "contract": id})
		if OS.is_debug_build():
			print("[CityTrade] %s acepta el encargo %s de %s (%s x%d)" % [actor, id, c, off["item"], int(off["qty"])])
		return Orders.ok()
	return Orders.fail("unknown_contract")


## The accepted contract `id` of family `fam` ({} if none).
static func accepted(sim: Sim, fam: String, id: String) -> Dictionary:
	for a: Dictionary in Region.ensure(sim)["contracts"]:
		if str(a["id"]) == id and str(a["family"]) == fam:
			return a
	return {}


## Delivers contract `a` from inventory `inv` (any quality: the best last): pays, reputation there. True if done.
static func deliver_from(sim: Sim, a: Dictionary, inv: Dictionary, actor: String) -> bool:
	var item := str(a["item"])
	var need := int(a["qty"])
	if Inventory.count(inv, item) < need:
		return false
	for q: int in Inventory.QUALITIES:
		var take := mini(need, Inventory.count(inv, item, q))
		if take > 0:
			Inventory.remove(inv, item, q, take)
			need -= take
	var fam := str(a["family"])
	Money.change(sim, fam, int(a["reward"]), Money.CONTRACTS, "city_contract:" + str(a["id"]), "", actor)
	Region.add_reputation(sim, str(a["city"]), fam, int(sim.catalog.trade.get("reputation", {}).get("contract_done", 3)),
		"contract_done")
	(Region.ensure(sim)["contracts"] as Array).erase(a)
	Region.stat(sim, fam, "city_contracts_done")
	sim.events.append({"type": "city_contract_done", "family": fam, "city": a["city"], "contract": a["id"],
		"reward": a["reward"]})
	if OS.is_debug_build():
		print("[CityTrade] encargo %s entregado en %s: %d de oro" % [a["id"], a["city"], int(a["reward"])])
	return true


## {"type": "city_deliver", "actor", "contract"}: from the actor's inventory, in the contract's city. Reasons:
## not_in_city, unknown_contract, wrong_city, not_enough.
static func order_deliver(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var c := _here(sim, actor)
	if c == "":
		return Orders.fail("not_in_city")
	var fam := str(sim.state.characters[actor].get("family", ""))
	var a := accepted(sim, fam, str(o.get("contract", "")))
	if a.is_empty():
		return Orders.fail("unknown_contract")
	if str(a["city"]) != c:
		return Orders.fail("wrong_city")
	if not deliver_from(sim, a, sim.state.characters[actor]["inventory"], actor):
		return Orders.fail("not_enough")
	return Orders.ok()


## At day_started: accepted contracts past their due fail (reputation there).
static func expire(sim: Sim, now: int) -> void:
	var keep: Array = []
	for a: Dictionary in Region.ensure(sim)["contracts"]:
		if now < int(a["due"]):
			keep.append(a)
			continue
		Region.add_reputation(sim, str(a["city"]), str(a["family"]),
			int(sim.catalog.trade.get("reputation", {}).get("contract_failed", -2)), "contract_failed")
		sim.events.append({"type": "city_contract_failed", "family": a["family"], "city": a["city"], "contract": a["id"]})
		Notices.add(sim, str(a["family"]), Notices.WARNING, "notice.city_contract_failed",
			{"city": str(Region.settlement(sim, str(a["city"])).get("name_key", a["city"]))})
	Region.ensure(sim)["contracts"] = keep
