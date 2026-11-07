class_name VisitingMerchant
extends RefCounted
## Vida · the visiting merchant trades for real (04f 4.24.3 «compra y vende en la plaza»; manager 2026-11-06): a merchant
## from a city of the region (Visitors, kind merchant) arrives with his purse (gold he can really spend) and a few units
## of what is cheap in his city (data/world/region.json `cheap`), and he buys what his city pays dear (`dear`). Prices
## are his city's (Region.price) with his margin: he buys at buy_margin of what his city pays and sells at sell_margin of
## what it costs there, so the trip is always the better deal. Limits so he never breaks the market: his purse, at most
## max_units of each item per visit, and he trades only with whoever comes to him (the town's stalls and their demand
## are not touched). Figures: data/life/life.json visitors.kinds.merchant.trade. State: the visitor's `trade`
## {purse, bought {item: n}, wares [{item, price, qty}]}, gone with him at dusk.


static func cfg(sim: Sim) -> Dictionary:
	return (Visitors.cfg(sim).get("kinds", {}).get("merchant", {}) as Dictionary).get("trade", {})


## The trade a merchant of `city` brings (at his arrival; keyed by his arrival key): his purse and his wares.
static func setup(sim: Sim, vis: Dictionary, city: String, key: String) -> void:
	var c := cfg(sim)
	var wares: Array = []
	var cheap: Dictionary = Region.settlement(sim, city).get("cheap", {})
	var span: Array = c.get("stock", [2, 4])
	for item: String in Festivals._sorted_keys(cheap):
		var price := roundi(Region.price(sim, city, item, Inventory.NORMAL, "buy") * float(c.get("sell_margin", 1.15)))
		if price <= 0:
			continue
		wares.append({"item": item, "price": price,
			"qty": Kin.randi_range(sim.state, "%s|mtrade|%s" % [key, item], int(span[0]), int(span[1]))})
	vis["trade"] = {"purse": int(vis.get("purse", 0)), "bought": {}, "wares": wares}


static func _trade(st: WorldState, target: String) -> Dictionary:
	var v: Variant = st.characters.get(target, {}).get("visitor")
	return (v as Dictionary).get("trade", {}) if v is Dictionary else {}


## Whether `target` is a merchant who trades now.
static func is_merchant(st: WorldState, target: String) -> bool:
	return not _trade(st, target).is_empty()


## What he sells: [{item, price, qty}].
static func wares(st: WorldState, target: String) -> Array:
	return _trade(st, target).get("wares", [])


## The items he buys (his city's dear ones), sorted.
static func buys(sim: Sim, target: String) -> Array:
	var v: Dictionary = sim.state.characters.get(target, {}).get("visitor", {})
	return Festivals._sorted_keys(Region.settlement(sim, str(v.get("city", ""))).get("dear", {}))


## What he pays for one `item` of `quality` (0 if he does not buy it).
static func offer(sim: Sim, target: String, item: String, quality: int) -> int:
	if not item in buys(sim, target):
		return 0
	var city := str(sim.state.characters[target]["visitor"].get("city", ""))
	return roundi(Region.price(sim, city, item, quality, "sell") * float(cfg(sim).get("buy_margin", 0.8)))


## "" if `actor` may sell one `item` of `quality` from his bag to `target` now, else why: not_a_merchant, not_wanted,
## not_enough (not in the bag), merchant_full (he bought max_units already), merchant_purse (he has not the gold).
static func sell_reason(sim: Sim, actor: String, target: String, item: String, quality: int) -> String:
	var st := sim.state
	if not st.characters.has(actor) or not is_merchant(st, target):
		return "not_a_merchant"
	var price := offer(sim, target, item, quality)
	if price <= 0:
		return "not_wanted"
	if Inventory.count(st.characters[actor]["inventory"], item, quality) < 1:
		return "not_enough"
	var t := _trade(st, target)
	if int((t["bought"] as Dictionary).get(item, 0)) >= int(cfg(sim).get("max_units", 3)):
		return "merchant_full"
	if int(t["purse"]) < price:
		return "merchant_purse"
	return ""


## "" if `actor` may buy one `item` from `target` now, else why: not_a_merchant, sold_out, not_enough_gold, too_heavy.
static func buy_reason(sim: Sim, actor: String, target: String, item: String) -> String:
	var st := sim.state
	if not st.characters.has(actor) or not is_merchant(st, target):
		return "not_a_merchant"
	var w := _ware(st, target, item)
	if w.is_empty() or int(w["qty"]) <= 0:
		return "sold_out"
	if not Money.can_pay(st, str(st.characters[actor].get("family", "")), int(w["price"])):
		return "not_enough_gold"
	if not Inventory.can_add(st.characters[actor]["inventory"], sim.catalog, item, Inventory.NORMAL, 1):
		return "too_heavy"
	return ""


static func _ware(st: WorldState, target: String, item: String) -> Dictionary:
	for w: Dictionary in wares(st, target):
		if str(w["item"]) == item:
			return w
	return {}


## {"type": "sell_to_merchant", "actor", "target", "item", "quality"}: one unit from the bag, at his offer, within the
## NPC actions' range. The gold comes from his purse (from outside: market_sales).
static func order_sell(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var item := str(o.get("item", ""))
	var q := int(o.get("quality", Inventory.NORMAL))
	var why := sell_reason(sim, actor, target, item, q)
	if why != "":
		return Orders.fail(why)
	if not NpcActions.in_range(sim, actor, target):
		return Orders.fail("too_far")
	var price := offer(sim, target, item, q)
	var t := _trade(st, target)
	var fam := str(st.characters[actor].get("family", ""))
	Inventory.remove(st.characters[actor]["inventory"], item, q, 1)
	Money.change(sim, fam, price, Money.MARKET_SALES, "merchant:" + item, "", actor)
	t["purse"] = int(t["purse"]) - price
	(t["bought"] as Dictionary)[item] = int((t["bought"] as Dictionary).get(item, 0)) + 1
	sim.events.append({"type": "merchant_bought", "actor": actor, "family": fam, "merchant": target, "item": item,
		"quality": q, "price": price})
	if OS.is_debug_build():
		print("[Merchant] %s vende %s (q%d) al mercader %s por %d (le queda %d en la bolsa)" % [actor, item, q, target,
			price, int(t["purse"])])
	return Orders.ok()


## {"type": "buy_from_merchant", "actor", "target", "item"}: one unit of his wares (normal quality) into the bag.
static func order_buy(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var item := str(o.get("item", ""))
	var why := buy_reason(sim, actor, target, item)
	if why != "":
		return Orders.fail(why)
	if not NpcActions.in_range(sim, actor, target):
		return Orders.fail("too_far")
	var w := _ware(st, target, item)
	var fam := str(st.characters[actor].get("family", ""))
	Money.change(sim, fam, -int(w["price"]), Money.PURCHASES, "merchant:" + item, "", actor)
	Inventory.add(st.characters[actor]["inventory"], sim.catalog, item, Inventory.NORMAL, 1)
	w["qty"] = int(w["qty"]) - 1
	var t := _trade(st, target)
	t["purse"] = int(t["purse"]) + int(w["price"])
	sim.events.append({"type": "merchant_sold", "actor": actor, "family": fam, "merchant": target, "item": item,
		"price": int(w["price"])})
	if OS.is_debug_build():
		print("[Merchant] %s compra %s al mercader %s por %d" % [actor, item, target, int(w["price"])])
	return Orders.ok()
