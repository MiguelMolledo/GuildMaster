class_name Counter
extends RefCounted
## Sales at the counter of an own building (GDD 4.5.4): a building with counter_sales (forge_commerce_1) gets NPC
## customers during the counter phases; whoever holds the counter station (the family) or an active employee with role
## counter inside serves them and they take one product. Contract: docs/contratos/h7_ciudad.md. Figures: data/town.json
## "counter"; customer_bonus and price_multiplier from the building's upgrades (H5).
## state.town.counters[bld] = {next_at}. The customer is a townsperson whose town memory has customer = bld (TownLife
## walks it in); its own fields: customer_since (minute it got inside), served_at (minute the sale happens).


## Once per minute, after TownLife.
static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var cfg: Dictionary = sim.catalog.town.get("counter", {})
	var open := Clock.phase(now, sim.catalog.time) in (cfg.get("phases", ["day"]) as Array)
	var ids: Array = st.buildings.keys()
	ids.sort()
	var sellers: Array = []
	for bld: String in ids:
		if not _sells(sim, bld):
			continue
		sellers.append(bld)
		var c: Dictionary = st.town["counters"].get(bld, {})
		if not open:
			if not c.is_empty():
				st.town["counters"].erase(bld)  # tomorrow starts afresh
			continue
		if c.is_empty():
			c = {"next_at": now + _interval(sim, bld, now)}
			st.town["counters"][bld] = c
		_bring_server(sim, bld)
		if now >= int(c["next_at"]):
			c["next_at"] = now + _interval(sim, bld, now)
			_call_customer(sim, bld, now)
	_serve(sim, now, cfg)
	Clientele.step(sim, now, open, sellers)  # 04g 4.6.5.7: the countryside's customers (off by default)


## Whether `bld` sells at its counter (counter_sales and an owner family).
static func sells(sim: Sim, bld: String) -> bool:
	return _sells(sim, bld)


## Whether `bld` sells at its counter: counter_sales and an owner family.
static func _sells(sim: Sim, bld: String) -> bool:
	var b: Dictionary = sim.state.buildings[bld]
	if str(b.get("owner", "")) == "" or (b.get("upgrades", []) as Array).is_empty():
		return false  # (cheap check first: this runs for every building every minute)
	return Upgrades.flag(sim, bld, "counter_sales")


## Minutes until the next customer: interval_hours [min, max] / (1 + customer_bonus) / the events' customers effect (H13).
static func _interval(sim: Sim, bld: String, now: int) -> int:
	var span: Array = sim.catalog.town.get("counter", {}).get("interval_hours", [1, 2])
	var mins := Kin.randi_range(sim.state, "cnt|next|%s|%d" % [bld, now], int(float(span[0]) * 60.0), int(float(span[1]) * 60.0))
	var ev := maxf(WorldEvents.customers_mult(sim), 0.01)
	return maxi(10, roundi(float(mins) / (1.0 + Upgrades.amount(sim, bld, "customer_bonus")) / ev))


## An active employee with role counter inside goes to the counter station.
static func _bring_server(sim: Sim, bld: String) -> void:
	var zones: Dictionary = sim.state.buildings[bld].get("zones", {})
	if not zones.has("counter") or str(zones["counter"].get("occupant", "")) != "":
		return
	for e: String in Staff.employees_of(sim.state, bld):
		var ch: Dictionary = sim.state.characters[e]
		if str(ch["job"].get("role", "")) == "counter" and Staff.is_active(sim, e) and str(ch.get("location", "")) == bld \
				and str(ch.get("station", "")) != "counter":
			sim.give({"type": "go_to_station", "actor": e, "zone": "counter"})
			return


## A free townsperson becomes this counter's customer (TownLife walks it in).
static func _call_customer(sim: Sim, bld: String, now: int) -> void:
	var st := sim.state
	var cands: Array = []
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = st.characters[id]
		if not TownLife.is_townsperson(st, id) or ch.get("job") is Dictionary or not TownLife.is_adult(st, sim.catalog, id):
			continue
		var t: Variant = ch.get("town")
		if not t is Dictionary or str(t.get("customer", "")) != "" or str(ch.get("location", "")) == str(ch.get("home", "")):
			continue
		if Emotions.refuses_trade(sim, id, str(st.buildings[bld].get("owner", ""))):
			continue
		cands.append(id)
	if cands.is_empty():
		return
	var who: String = cands[Kin.randi_range(st, "cnt|who|%s|%d" % [bld, now], 0, cands.size() - 1)]
	var t: Dictionary = st.characters[who]["town"]
	t["customer"] = bld
	t.erase("customer_since")
	t.erase("served_at")
	sim.events.append({"type": "customer_arrived", "building": bld, "customer": who})
	if OS.is_debug_build():
		print("[Counter] %s va de cliente a %s" % [who, bld])


## Customers inside: served after serve_minutes by whoever is at the counter, or gone after patience_minutes.
static func _serve(sim: Sim, now: int, cfg: Dictionary) -> void:
	var st := sim.state
	var ids: Array = []
	for id: Variant in st.characters:
		var tt: Variant = st.characters[id].get("town")
		if tt is Dictionary and str(tt.get("customer", "")) != "":
			ids.append(str(id))
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = st.characters[id]
		var t: Dictionary = ch["town"]
		var bld := str(t["customer"])
		if not st.buildings.has(bld) or not _sells(sim, bld):
			leave(sim, id, "closed")
			continue
		if str(ch.get("location", "")) != bld:
			continue  # still walking there
		if Microevents.holding(sim, id):
			continue  # a haggling card is waiting for an answer
		if not t.has("customer_since"):
			t["customer_since"] = now
		var server := server_of(sim, bld)
		if server == "":
			t.erase("served_at")
			if now - int(t["customer_since"]) >= int(cfg.get("patience_minutes", 60)):
				leave(sim, id, "nobody")
			continue
		if not t.has("served_at"):
			t["served_at"] = now + int(cfg.get("serve_minutes", 10))
		if now < int(t["served_at"]):
			continue
		var item := best_product(sim, bld)
		if item.is_empty():
			leave(sim, id, "no_product")
			continue
		var fam := str(st.buildings[bld].get("owner", ""))
		if Emotions.refuses_trade(sim, id, fam):
			leave(sim, id, "refuses")
			continue
		if Microevents.haggle(sim, fam, bld, id, server, item):
			continue  # the card decides the sale
		sell(sim, bld, id, server, item, 0.0)


## Who serves at `bld`'s counter: the occupant of the counter station (family or employee) or an active employee with
## role counter inside ("" if nobody).
static func server_of(sim: Sim, bld: String) -> String:
	var st := sim.state
	var occ := str(st.buildings[bld].get("zones", {}).get("counter", {}).get("occupant", ""))
	if occ != "" and str(st.characters.get(occ, {}).get("location", "")) == bld:
		return occ
	for e: String in Staff.employees_of(st, bld):
		var ch: Dictionary = st.characters[e]
		if str(ch["job"].get("role", "")) == "counter" and Staff.is_active(sim, e) and str(ch.get("location", "")) == bld:
			return e
	return ""


## The product (category product) of most value in `bld`'s storage: {item, quality} or {}.
static func best_product(sim: Sim, bld: String) -> Dictionary:
	var best := {}
	var best_price := -1
	for s: Dictionary in sim.state.buildings[bld].get("inventory", {}).get("stacks", []):
		if int(s["qty"]) <= 0 or str(sim.catalog.item(str(s["item"])).get("category", "")) != "product":
			continue
		var p := price(sim, bld, "", str(s["item"]), int(s["quality"]), "")
		var better := p > best_price
		if p == best_price and not best.is_empty():
			better = str(s["item"]) < str(best["item"]) or (str(s["item"]) == str(best["item"]) and int(s["quality"]) < int(best["quality"]))
		if better:
			best = {"item": str(s["item"]), "quality": int(s["quality"])}
			best_price = p
	return best


## GDD 4.5.4: base × (1 + charisma/100 + rank bonus + (price_multiplier − 1) + reputation bonus) × the customer's
## sell_mult towards the owner family. base = counter.price_base: "market_sell" (what the market pays for it now:
## quality, demand and sell_ratio in; the counter is that plus its bonuses, H7 balance) or "base_price" (the item's
## base price × quality, the literal reading of 4.5.4, which sold at about twice the market).
static func price(sim: Sim, bld: String, server: String, item: String, quality: int, customer: String) -> int:
	var st := sim.state
	var cfg: Dictionary = sim.catalog.town.get("counter", {})
	var base := 0.0
	if str(cfg.get("price_base", "market_sell")) == "market_sell":
		base = float(Market.price(sim, item, quality, "sell"))  # what the market pays now (quality and demand in)
	else:
		var qm: Array = sim.catalog.market.get("quality_mult", [1.0])
		base = float(sim.catalog.item(item).get("base_price", 1)) * float(qm[clampi(quality, 0, qm.size() - 1)])
	var bonus := 0.0
	if server != "":
		bonus += float(SkillCheck.stat(sim, server, "charisma")) / 100.0
		if st.characters[server].get("job") is Dictionary:
			bonus += float(cfg.get("rank_bonus", {}).get(str(st.characters[server].get("rank", "")), 0.0))
	bonus += Upgrades.mult(sim, bld, "price_multiplier") - 1.0
	var fam := str(st.buildings[bld].get("owner", ""))
	var rep := float(st.families.get(fam, {}).get("reputation", 0))
	bonus += clampf(rep / 100.0 * float(cfg.get("reputation_mult", 0.15)), 0.0, float(cfg.get("reputation_cap", 0.15)))
	var m := 1.0
	if customer != "":
		m = Emotions.price_mult(sim, customer, fam, "sell")
	# Pulido del MVP [provisional]: the Secrets «contraband» (GDD 4.8: «beneficio ilegal ×2») doubles what this
	# building's counter takes (selling under the counter): the only sale that belongs to a building.
	m *= Upgrades.mult(sim, bld, "illegal_profit")
	return maxi(1, roundi(base * (1.0 + bonus) * m))


## The sale: one unit out of the storage, gold to the owner family (counter_sales), the customer leaves.
static func sell(sim: Sim, bld: String, customer: String, server: String, item: Dictionary, discount: float) -> void:
	var st := sim.state
	var fam := str(st.buildings[bld].get("owner", ""))
	var inv: Dictionary = st.buildings[bld]["inventory"]
	if Inventory.count(inv, str(item["item"]), int(item["quality"])) < 1:
		leave(sim, customer, "no_product")
		return
	var p := maxi(1, roundi(float(price(sim, bld, server, str(item["item"]), int(item["quality"]), customer)) * (1.0 - discount)))
	Inventory.remove(inv, str(item["item"]), int(item["quality"]), 1)
	Money.change(sim, fam, p, Money.COUNTER_SALES, "counter", bld, server)
	sim.events.append({"type": "counter_sold", "family": fam, "building": bld, "customer": customer, "seller": server,
		"item": str(item["item"]), "quality": int(item["quality"]), "price": p})
	if OS.is_debug_build():
		print("[Counter] %s compra %s (q%d) en %s por %d (vende %s, descuento %.0f %%)" % [customer, item["item"],
			int(item["quality"]), bld, p, server, discount * 100.0])
	leave(sim, customer, "bought")


## The customer is done: TownLife takes it back to its day (out of the building).
static func leave(sim: Sim, customer: String, reason: String) -> void:
	var ch: Dictionary = sim.state.characters.get(customer, {})
	var t: Variant = ch.get("town")
	if not t is Dictionary:
		return
	var bld := str(t.get("customer", ""))
	t.erase("customer")
	t.erase("customer_since")
	t.erase("served_at")
	if bld != "" and str(ch.get("location", "")) == bld:
		sim.give({"type": "exit_building", "actor": customer})
	if reason != "bought":
		sim.events.append({"type": "customer_left", "building": bld, "customer": customer, "reason": reason})
	if OS.is_debug_build() and reason != "bought":
		print("[Counter] %s se va de %s sin comprar (%s)" % [customer, bld, reason])


## Whether `chr` is on its way to / waiting at `bld`'s counter (Buildings.can_enter lets it in).
static func is_customer_of(st: WorldState, chr: String, bld: String) -> bool:
	var t: Variant = st.characters.get(chr, {}).get("town")
	return t is Dictionary and str(t.get("customer", "")) == bld


## The customers inside `bld` now (the interior view draws them at the counter).
static func customers(sim: Sim, bld: String) -> Array:
	var out: Array = []
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		if is_customer_of(sim.state, id, bld) and str(sim.state.characters[id].get("location", "")) == bld:
			out.append(id)
	return out
