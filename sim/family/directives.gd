class_name Directives
extends RefCounted
## The AI directives of family members (GDD 4.10.6; docs/contratos/h14_ia_familiar.md), run in a «Free» slot of the
## routine (or by family members with AI, Schedules). First the lowest need under needs.low (hunger, rest: home and
## still; social: socialise; fun: leisure) until it is back at needs.recover_to; else the first directive of the
## character's list, in its order, that has something to do: work (Schedules._work, normal mode, no master touch),
## trade (buys the raw materials of its workshop's recipes and sells the surplus of products), socialize (talks to the
## nearest townsperson in the street), leisure (an hour on a free bench of the plaza). Only the same orders as the
## player, through Sim.give. Memory in character.ai: {doing, why, need, leisure_at, leisure_until, talked}.


static func ready(sim: Sim, d: String) -> bool:
	var r: Variant = sim.catalog.family.get("directives", {}).get("ready", {}).get(d, false)
	return r is bool and bool(r)


## Whether `chr` has directive `d` in its list and it is ready.
static func is_ready_listed(sim: Sim, chr: String, d: String) -> bool:
	return d in (sim.state.characters.get(chr, {}).get("directives", []) as Array) and ready(sim, d)


static func _ai(sim: Sim, chr: String) -> Dictionary:
	var ch: Dictionary = sim.state.characters[chr]
	if not ch.get("ai") is Dictionary:
		ch["ai"] = {}
	return ch["ai"]


static func _note(sim: Sim, chr: String, doing: String, why: String) -> void:
	var ai := _ai(sim, chr)
	if str(ai.get("doing", "")) != doing or str(ai.get("why", "")) != why:
		ai["doing"] = doing
		ai["why"] = why
		sim.events.append({"type": "directive_task", "character": chr, "directive": doing, "task": why})
		if OS.is_debug_build():
			print("[Directives] %s: %s (%s)" % [chr, doing, why])


## A «Free» slot for `chr` now (Schedules._step_one): the urgent need, else its directives in order.
static func step_one(sim: Sim, chr: String, r: Dictionary, now: int) -> void:
	var ai := _ai(sim, chr)
	var nc: Dictionary = sim.catalog.family.get("needs", {})
	var need := str(ai.get("need", ""))
	if need != "" and int(Needs.of(sim, chr).get(need, 100)) >= int(nc.get("recover_to", 70)):
		ai.erase("need")
		need = ""
	if need == "" and Needs.tracked(sim, chr):
		need = Needs.most_urgent(sim, chr)
		if need != "":
			ai["need"] = need
	if need != "":
		_note(sim, chr, {"hunger": "home", "rest": "home", "social": "socialize", "fun": "leisure"}.get(need, "home"),
			"need_" + need)
		match need:
			"social":
				if _socialize(sim, chr, now):
					return
			"fun":
				if _leisure(sim, chr, now):
					return
		Schedules._rest(sim, chr, r, now)
		_note(sim, chr, "home", "need_" + need)
		return
	for d: Variant in sim.state.characters[chr].get("directives", []):
		var dir := str(d)
		if not ready(sim, dir):
			continue
		var did := false
		match dir:
			"work":
				did = _work(sim, chr, r, now)
			"trade":
				did = _trade(sim, chr, now)
			"socialize":
				did = _socialize(sim, chr, now)
			"leisure":
				did = _leisure(sim, chr, now)
		if did:
			_note(sim, chr, dir, "directive")
			return
	_note(sim, chr, "idle", "nothing")


# --- work -------------------------------------------------------------------------------------------------------------

static func _work(sim: Sim, chr: String, r: Dictionary, now: int) -> bool:
	var st := sim.state
	var bld := Kin.assigned_building(sim, chr)
	if bld == "" or str(st.buildings[bld].get("state", "normal")) != "normal":
		return false
	if Production.job_zone(sim, chr, bld) == "" and Schedules.pick_work(sim, chr, bld, "", "").is_empty():
		return false  # nothing it can make now (no materials): the next directive (trade) may fix it
	Schedules._work(sim, chr, r, {"action": "work", "mode": "normal"}, now)
	return true


# --- trade (the criterion of H14) -------------------------------------------------------------------------------------

static func _tc(sim: Sim) -> Dictionary:
	return sim.catalog.family.get("trade", {})


## The raw materials of `bld`'s recipes with less than min_stock units in its storage, sorted.
static func shortages(sim: Sim, bld: String) -> Array:
	var st := sim.state
	var b: Dictionary = st.buildings.get(bld, {})
	if b.is_empty():
		return []
	var need := {}
	for rid: String in sim.catalog.recipes():
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) != str(b.get("type", "")):
			continue
		for inp: Dictionary in r.get("inputs", []):
			var it := str(inp["item"])
			if str(sim.catalog.item(it).get("category", "")) == "raw" and RivalAI.stall_for(sim, it) != "":
				need[it] = true
	var out: Array = []
	var min_stock := int(_tc(sim).get("min_stock", 6))
	for it: String in need:
		if Inventory.count(b.get("inventory", {}), it) < min_stock:
			out.append(it)
	out.sort()
	return out


## Products of `bld` above keep_products: [{item, quality, qty}] (the surplus), sorted by item.
static func surplus(sim: Sim, bld: String) -> Array:
	var keep := int(_tc(sim).get("keep_products", 4))
	var per := {}
	for s: Dictionary in sim.state.buildings.get(bld, {}).get("inventory", {}).get("stacks", []):
		var it := str(s.get("item", ""))
		if str(sim.catalog.item(it).get("category", "")) != "product" or RivalAI.stall_for(sim, it) == "":
			continue
		per[it] = int(per.get(it, 0)) + int(s.get("qty", 0))
	var out: Array = []
	var items: Array = per.keys()
	items.sort()
	for it: String in items:
		if int(per[it]) > keep:
			out.append({"item": it, "qty": int(per[it]) - keep})
	return out


static func _trade(sim: Sim, chr: String, now: int) -> bool:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	var bld := Kin.assigned_building(sim, chr)
	if bld == "":
		return false
	if not Schedules._idle(sim, chr):
		return str(_ai(sim, chr).get("doing", "")) == "trade"  # on its way: keep at it
	var bag: Dictionary = ch.get("inventory", {})
	var loc := str(ch.get("location", ""))
	var fam := str(ch.get("family", ""))
	# 1. Raw materials in the bag: home and into the storage.
	for s: Dictionary in (bag.get("stacks", []) as Array).duplicate():
		var it := str(s.get("item", ""))
		if str(sim.catalog.item(it).get("category", "")) != "raw":
			continue
		if loc != bld:
			return _go_inside(sim, chr, bld)
		sim.give({"type": "transfer", "actor": chr, "from": chr, "to": bld, "item": it, "quality": int(s.get("quality", 0)),
			"qty": int(s.get("qty", 0))})
		Notices.add(sim, fam, Notices.INFO, "notice.kin_supplied", {"name": str(ch.get("name", "")), "item": it,
			"qty": int(s.get("qty", 0)), "building": bld}, chr)
		return true
	if not Market.is_open(sim):
		return false
	# 2. Products in the bag: to their stall and sell.
	for s: Dictionary in (bag.get("stacks", []) as Array).duplicate():
		var it := str(s.get("item", ""))
		if str(sim.catalog.item(it).get("category", "")) != "product":
			continue
		var stall := RivalAI.stall_for(sim, it)
		if stall == "" or not RivalAI._gets_there_open(sim, chr, stall):
			continue
		var go := RivalAI._go_stall(sim, chr, stall)
		if not go.is_empty():
			sim.give(go)
			return true
		sim.give({"type": "sell", "actor": chr, "stall": stall, "item": it, "quality": int(s.get("quality", 0)),
			"qty": int(s.get("qty", 0))})
		return true
	# 3. A raw material short in the workshop: to its stall and buy.
	for it: String in shortages(sim, bld):
		var stall := RivalAI.stall_for(sim, it)
		var have := Inventory.count(st.buildings[bld].get("inventory", {}), it)
		var price := maxi(1, Market.trade_price(sim, chr, stall, it, 0, "buy"))
		var afford := (Money.gold(st, fam) - int(_tc(sim).get("gold_reserve", 20))) / price
		var qty := mini(int(_tc(sim).get("buy_up_to", 10)) - have, afford)
		while qty > 0 and not Inventory.can_add(bag, sim.catalog, it, 0, qty):
			qty -= 1
		if qty <= 0 or not RivalAI._gets_there_open(sim, chr, stall):
			continue
		var go := RivalAI._go_stall(sim, chr, stall)
		if not go.is_empty():
			sim.give(go)
			return true
		sim.give({"type": "buy", "actor": chr, "stall": stall, "item": it, "quality": 0, "qty": qty})
		return true
	# 4. A surplus of products in the workshop: take it to sell.
	for x: Dictionary in surplus(sim, bld):
		if loc != bld:
			return _go_inside(sim, chr, bld)
		var it := str(x["item"])
		var q := _best_quality(sim, bld, it)
		var qty := mini(mini(int(x["qty"]), int(_tc(sim).get("max_carry_units", 10))), Inventory.count(
			st.buildings[bld]["inventory"], it, q))
		while qty > 0 and not Inventory.can_add(bag, sim.catalog, it, q, qty):
			qty -= 1
		if qty <= 0:
			continue
		sim.give({"type": "transfer", "actor": chr, "from": bld, "to": chr, "item": it, "quality": q, "qty": qty})
		return true
	return false


static func _best_quality(sim: Sim, bld: String, item: String) -> int:
	var best := 0
	for s: Dictionary in sim.state.buildings[bld].get("inventory", {}).get("stacks", []):
		if str(s.get("item", "")) == item:
			best = maxi(best, int(s.get("quality", 0)))
	return best


static func _go_inside(sim: Sim, chr: String, bld: String) -> bool:
	var loc := str(sim.state.characters[chr].get("location", ""))
	if loc != "" and loc != bld:
		sim.give({"type": "exit_building", "actor": chr})
	sim.give({"type": "enter_building", "actor": chr, "building": bld})
	return true


# --- socialize and leisure --------------------------------------------------------------------------------------------

## Talks to the nearest adult townsperson in the street it has not talked to today; walks to it if far.
static func _socialize(sim: Sim, chr: String, _now: int) -> bool:
	var st := sim.state
	if not Schedules._idle(sim, chr):
		return str(_ai(sim, chr).get("doing", "")) == "socialize"
	var best := ""
	var best_d := 1000000
	var me: Array = st.characters[chr].get("position", [0, 0])
	for c: String in Population.townsfolk(st):
		var t: Dictionary = st.characters[c]
		if str(t.get("location", "")) != "" or not Kin.is_adult(sim, c):
			continue
		var why := NpcActions.status(sim, chr, c, "talk")
		if why != "" and why != "too_far":
			continue
		var p: Array = t.get("position", [0, 0])
		var d := absi(int(p[0]) - int(me[0])) + absi(int(p[1]) - int(me[1]))
		if d < best_d or (d == best_d and c < best):
			best = c
			best_d = d
	if best == "":
		return false
	if str(st.characters[chr].get("location", "")) != "":
		sim.give({"type": "exit_building", "actor": chr})
		return true
	if NpcActions.in_range(sim, chr, best):
		sim.give({"type": "npc_talk", "actor": chr, "target": best})
	else:
		sim.give({"type": "move_to", "actor": chr, "tile": Courtship.spot(st, best)})
	return true


## An hour on a free bench seat of the map's social points (nobody standing on it); then done until the need asks.
static func _leisure(sim: Sim, chr: String, now: int) -> bool:
	var st := sim.state
	var ai := _ai(sim, chr)
	var at := str(ai.get("leisure_at", ""))
	if at != "":
		if now < int(ai.get("leisure_until", 0)):
			return true
		ai.erase("leisure_at")
		ai.erase("leisure_until")
		return false
	if not Schedules._idle(sim, chr):
		return str(ai.get("doing", "")) == "leisure"
	var seat := _free_bench(sim, chr)
	if seat.is_empty():
		return false
	var ch: Dictionary = st.characters[chr]
	if str(ch.get("location", "")) != "":
		sim.give({"type": "exit_building", "actor": chr})
		return true
	var pos: Array = ch.get("position", [0, 0])
	if int(pos[0]) == int(seat[0]) and int(pos[1]) == int(seat[1]):
		ai["leisure_at"] = "%d,%d" % [int(seat[0]), int(seat[1])]
		ai["leisure_until"] = now + int(sim.catalog.family.get("leisure", {}).get("minutes", 60))
		return true
	sim.give({"type": "move_to", "actor": chr, "tile": [int(seat[0]), int(seat[1])]})
	return true


static func _free_bench(sim: Sim, chr: String) -> Array:
	var st := sim.state
	var taken := {}
	for id: Variant in st.characters:
		var c: Dictionary = st.characters[id]
		if str(id) != chr and bool(c.get("alive", true)) and str(c.get("location", "")) == "":
			var p: Array = c.get("position", [0, 0])
			taken["%d,%d" % [int(p[0]), int(p[1])]] = true
	var me: Array = st.characters[chr].get("position", [0, 0])
	var best: Array = []
	var best_d := 1000000
	for sp: Dictionary in sim.catalog.maps().get(st.map_id, {}).get("social_points", []):
		if str(sp.get("kind", "")) != "bench":
			continue
		for s: Variant in sp.get("slots", []):
			var key := "%d,%d" % [int(s[0]), int(s[1])]
			if taken.has(key):
				continue
			var d := absi(int(s[0]) - int(me[0])) + absi(int(s[1]) - int(me[1]))
			if d < best_d:
				best = [int(s[0]), int(s[1])]
				best_d = d
	return best


# --- UI ---------------------------------------------------------------------------------------------------------------

## The panel: {directives, known: [{id, ready (true | milestone), on}], doing, why}.
static func view(sim: Sim, chr: String) -> Dictionary:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty():
		return {}
	var list: Array = ch.get("directives", [])
	var known: Array = []
	for d: Variant in sim.catalog.family.get("directives", {}).get("known", []):
		known.append({"id": str(d), "ready": sim.catalog.family.get("directives", {}).get("ready", {}).get(str(d), false),
			"on": str(d) in list})
	var ai: Dictionary = ch.get("ai", {}) if ch.get("ai") is Dictionary else {}
	return {"directives": list.duplicate(), "known": known, "doing": str(ai.get("doing", "")), "why": str(ai.get("why", ""))}
