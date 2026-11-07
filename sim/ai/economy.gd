class_name AIEconomy
extends RefCounted
## H13 (04c 4.21.6.1, the economy with management): how an AI family runs its workshop like a real family, only on the
## maps of data/ai.json economy.maps (Bellcaire); everywhere else (Vilarrasa and its targets) RivalAI is as always.
## Same orders as the player (work_at, hire, fire, queue_add, queue_remove), checked first with the UI's queries, so
## none is refused. RivalAI.orders calls orders() after the head's own order, and RivalAI.buy_needs asks
## cycles_for() and hands_needs().
##
## - Hands: the family's other adults at home (the spouse) work in the work phases at the free station, the head's
##   recipe if its station is free, else what the head's recipe lacks (planks for the chests), else the best margin
##   they can make; never a piece the market will not take (cap).
## - Every tick_minutes (staggered by family), not every minute: the hands, the queue and the errands.
## - Management, at the family's own minute of dawn (staggered): the gold of the last dawns gives the trend. With the
##   trend not losing and gold for buffer_days of wages over its reserve (reserve(): the upkeep days too), it hires the cheapest apprentice (up to the
##   profile's max_employees, else economy.max_employees) and queues the head's recipe for the employees (changing
##   the queue when the recipe changes) if its recipe pays the wage (what one more hand adds a day, as far as the
##   market takes it, × its margin ≥ hire_pay × the wage); under its reserve (reserve()) it lets the last one go.
## - Credit (step(), at dawn after the upkeep): a family that cannot pay the next dawn's upkeep and wages borrows
##   economy.credit.amount plus the upkeep it owes (up to max_amount) from the moneylender (a loan of kind CREDIT
##   owing amount × (1 + interest) in term_days,
##   at most one open, every gap_days at most); at each dawn it repays what it has over its reserve. Due unpaid, the
##   loan runs Loans' extension and seizure; a CREDIT loan the seizure does not cover is written off, never a ruin
##   (the ruin ends the player's game).
## - Buying: the cycles of a recipe are capped by what the market takes of its piece in the next absorb_days (the
##   demand over the family's selling floor, plus its recovery) minus what the family already has of it: the gold no
##   longer sleeps in a store of unsold pieces.
## Memory in ai_state.economy: {gold: [gold at the last dawns], hand: recipe of the hands, hand_wait: {hand: minute
## it looks again for something to make}, errand_at, credit_day, managed_day, entry_recipe: the
## employees' recipe}.


const CREDIT: String = "ai_credit"


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.ai_rules.get("economy", {})


static func on(sim: Sim) -> bool:
	return sim.state.map_id in (cfg(sim).get("maps", []) as Array)


## Whether this minute is one of the family's ticks (every tick_minutes, staggered by the family's id).
static func _tick(sim: Sim, fam: String) -> bool:
	var t := maxi(1, int(cfg(sim).get("tick_minutes", 5)))
	return (int(sim.state.clock["minute"]) + absi(fam.hash())) % t == 0


static func _mem(sim: Sim, fam: String) -> Dictionary:
	var fd: Dictionary = sim.state.families[fam]
	if not fd.get("ai_state") is Dictionary:
		fd["ai_state"] = {}
	if not (fd["ai_state"] as Dictionary).get("economy") is Dictionary:
		fd["ai_state"]["economy"] = {"gold": []}
	return fd["ai_state"]["economy"]


## The orders of the family's hands and management this minute ([] off the economy maps).
static func orders(sim: Sim, fam: String, head: String, home: String, profile: Dictionary, head_order: Dictionary = {}) -> Array:
	var out: Array = []
	if not on(sim):
		return out
	var st := sim.state
	var now := int(st.clock["minute"])
	var today := Clock.day(now)
	var mem := _mem(sim, fam)
	if int(mem.get("managed_day", -1)) != today:  # its own minute of dawn (staggered: no two families hire at once)
		var d0 := Hostility._phase_start(sim, today, "dawn")
		var stagger := int(cfg(sim).get("stagger_minutes", 3))
		if now > d0 + stagger * 16:
			mem["managed_day"] = today
		elif now > d0 and now == d0 + stagger * Hostility._ai_families(st).find(fam) + 1:
			mem["managed_day"] = today
			out.append_array(_manage(sim, fam, head, home, profile, today))
	if not _tick(sim, fam):
		return out  # the hands, the queue and the errands every tick_minutes, not every minute
	var damaged := str(st.buildings[home].get("state", "normal")) != "normal"
	var q: Dictionary = st.buildings[home].get("queue", {})
	if not (q.get("entries", []) as Array).is_empty() and bool(q.get("paused", false)) != damaged:
		# a damaged workshop (sabotage, unpaid upkeep) cannot work: its queue waits until it is repaired
		out.append({"type": "queue_pause", "actor": head, "building": home, "on": damaged})
	var ph := Clock.phase(now, sim.catalog.time)
	if not ph in (profile.get("work_phases", ["day"]) as Array):
		return out
	if damaged:
		return out
	var taken := {}  # the stations already asked for this minute (the head's order is applied after this)
	if str(head_order.get("type", "")) == "work_at":
		taken[str(head_order.get("zone", ""))] = true
	var wait: Dictionary = _mem(sim, fam).get("hand_wait", {})
	for m: Variant in st.families[fam].get("members", []):
		var id := str(m)
		if id == head or now < int(wait.get(id, -1)):
			continue  # nothing to make a moment ago: it looks again after check_minutes
		if not Kin.alive(st, id):
			continue
		var ch: Dictionary = st.characters[id]
		if str(ch.get("location", "")) != home or ch.get("job") is Dictionary or not Kin.is_adult(sim, id):
			continue
		if Production.job_zone(sim, id, home) != "" or not OrderQueue.is_free(sim, id) \
				or OrderQueue.has_pending(sim, id) or Production.may_work(sim, id, home) != "":
			continue
		var rid := _hand_recipe(sim, fam, id, home, taken)
		if rid == "":
			wait[id] = now + int(cfg(sim).get("check_minutes", 15))
			_mem(sim, fam)["hand_wait"] = wait
		else:
			taken[str(sim.catalog.recipes()[rid]["zone"])] = true
			_mem(sim, fam)["hand"] = rid
			out.append(RivalAI._work(sim, id, home, rid, profile))
			if OS.is_debug_build():
				print("[AIEconomy] %s (%s) trabaja %s en %s" % [id, fam, rid, home])
	return out


## The recipe a hand works now: the head's (its station free), else one that makes what the head's recipe lacks,
## else the best margin it can make; only pieces the market still takes. "" if none.
static func _hand_recipe(sim: Sim, fam: String, hand: String, home: String, taken: Dictionary = {}) -> String:
	var ai: Dictionary = sim.state.families[fam].get("ai_state", {})
	var main := str(ai.get("recipe", ""))
	var storage := RivalAI._storage(sim, home)
	if main != "" and _free_ok(sim, hand, home, main, taken) and _room(sim, fam, home, main):
		return main
	if main != "":
		for inp: Dictionary in sim.catalog.recipes()[main].get("inputs", []):
			if Inventory.count(storage, str(inp["item"])) >= int(inp["qty"]) * 2:
				continue
			var sub := RivalAI._recipe_for(sim, hand, home, str(inp["item"]))
			if sub != "" and sub != main and _free_ok(sim, hand, home, sub, taken):
				return sub
	var best := ""
	var best_m := 0
	var btype := str(sim.state.buildings[home].get("type", ""))
	var ids: Array = sim.catalog.recipes().keys()
	ids.sort()
	for rid: String in ids:
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) != btype or RivalAI.stall_for(sim, str(r["output"]["item"])) == "":
			continue
		var mg := roundi(rate(sim, home, rid) * 100.0)
		if mg > best_m and _free_ok(sim, hand, home, rid, taken) and _room(sim, fam, home, rid):
			best = rid
			best_m = mg
	return best


## Whether `hand` can work `rid` now at a station nobody asked for this minute.
static func _free_ok(sim: Sim, hand: String, home: String, rid: String, taken: Dictionary) -> bool:
	return not taken.has(str(sim.catalog.recipes()[rid]["zone"])) and RivalAI._status(sim, hand, home, rid) == "ok"


## Whether the market still takes more of what `rid` makes than the family already has.
static func _room(sim: Sim, fam: String, home: String, rid: String) -> bool:
	return cycles_for(sim, fam, home, rid, 1) > 0


## How many of `cycles` cycles of `rid` are worth making now: capped by what the market takes of its piece in the next
## absorb_days (demand over the family's selling floor, then its daily recovery) minus what the family has of it.
static func cycles_for(sim: Sim, fam: String, home: String, rid: String, cycles: int) -> int:
	if not on(sim) or cycles <= 0:
		return cycles
	var r: Dictionary = sim.catalog.recipes()[rid]
	var item := str(r["output"]["item"])
	if RivalAI.stall_for(sim, item) == "":
		return cycles  # made to order (a contract piece): its contract says how many
	var profile: Dictionary = Hostility._profile(sim, fam)
	var thr := RivalAI.sell_min_demand(sim, profile)
	var dcfg: Dictionary = sim.catalog.market.get("demand", {})
	var drop := float(dcfg.get("drop_per_unit", 0.04))
	var takes := RivalAI.units_above(Market.demand(sim, item), thr, drop) \
		+ floori(float(dcfg.get("recover_per_day", 0.4)) * float(cfg(sim).get("absorb_days", 2)) / maxf(drop, 0.001))
	var head := Kin.head(sim.state, fam)
	var have := Inventory.count(RivalAI._storage(sim, home), item) + (Inventory.count(RivalAI._bag(sim, head), item)
		if head != "" else 0)
	var per := maxi(1, int(r["output"].get("qty", 1)))
	return clampi((takes - have) / per, 0, cycles)


## The inputs the family's other hands and employees will use in buy_days (RivalAI.buy_needs adds them).
static func hands_needs(sim: Sim, fam: String, home: String, profile: Dictionary, need: Dictionary) -> void:
	if not on(sim):
		return
	var m := _mem(sim, fam)
	var minutes := RivalAI.work_minutes_per_day(sim, profile) * int(profile.get("buy_days", 1))
	var hands := 0
	var head := Kin.head(sim.state, fam)
	for id: Variant in sim.state.families[fam].get("members", []):
		if str(id) != head and Kin.alive(sim.state, str(id)) and Kin.is_adult(sim, str(id)) \
				and not sim.state.characters[str(id)].get("job") is Dictionary:
			hands += 1
	var rid := str(m.get("hand", ""))
	if hands > 0 and rid != "":
		var c := minutes / Production.cycle_minutes(sim.catalog, sim.catalog.recipes()[rid], RivalAI._mode(profile))
		RivalAI._add_inputs(sim, need, rid, cycles_for(sim, fam, home, rid, c * hands))
	var staff := Staff.employees_of(sim.state, home).size()
	var er := str(m.get("entry_recipe", ""))
	if staff > 0 and er != "":
		var c2 := minutes / Production.cycle_minutes(sim.catalog, sim.catalog.recipes()[er], "normal")
		RivalAI._add_inputs(sim, need, er, cycles_for(sim, fam, home, er, c2 * staff))


# --- Management -------------------------------------------------------------------------------------------------------

static func _manage(sim: Sim, fam: String, head: String, home: String, profile: Dictionary, today: int) -> Array:
	var st := sim.state
	var c := cfg(sim)
	var m := _mem(sim, fam)
	var gold := Money.gold(st, fam)
	var hist: Array = m.get("gold", [])
	hist.append(gold)
	var keep := int(c.get("trend_days", 3)) + 1
	while hist.size() > keep:
		hist.pop_front()
	m["gold"] = hist
	var trend := gold - int(hist[0])
	var out: Array = []
	var staff := Staff.employees_of(st, home)
	if not staff.is_empty():
		if gold < reserve(sim, fam, profile):
			out.append({"type": "fire", "actor": head, "employee": str(staff.back())})
			if OS.is_debug_build():
				print("[AIEconomy] %s despide a %s (oro %d, tendencia %d)" % [fam, staff.back(), gold, trend])
			return out
	var rid := str(st.families[fam].get("ai_state", {}).get("recipe", ""))
	var maxe := int(profile.get("max_employees", c.get("max_employees", 1)))
	if staff.size() < maxe and today >= int(c.get("hire_after_days", 2)) and rid != "" \
			and (hist.size() < 2 or trend >= 0) and Staff.free_slots(st, home) > 0:
		var cand := _cheapest(sim, head, home)
		if cand != "" and gold >= reserve(sim, fam, profile) + Staff.wage(sim, cand) * int(c.get("buffer_days", 6)) \
				and _pays(sim, fam, home, profile, rid, Staff.wage(sim, cand)):
			out.append({"type": "hire", "actor": head, "building": home, "candidate": cand})
			if OS.is_debug_build():
				print("[AIEconomy] %s contrata a %s (oro %d, tendencia %d)" % [fam, cand, gold, trend])
	# the employees' queue: the head's recipe, endless (the entries of another recipe go)
	if (not staff.is_empty() or not out.is_empty()) and rid != "":
		var has := false
		for e: Dictionary in st.buildings[home].get("queue", {}).get("entries", []):
			if str(e.get("recipe", "")) == rid:
				has = true
			else:
				out.append({"type": "queue_remove", "actor": head, "building": home, "entry": str(e["id"])})
		if not has:
			out.append({"type": "queue_add", "actor": head, "building": home, "recipe": rid, "qty": WorkQueue.INFINITE})
		m["entry_recipe"] = rid
	return out


## The cheapest candidate `head` can hire at `home` now ("" if none).
static func _cheapest(sim: Sim, head: String, home: String) -> String:
	var best := ""
	var bw := 1 << 30
	for row: Dictionary in Staff.candidates(sim, head, home):
		if str(row.get("status", "")) != "ok":
			continue
		var w := int(row.get("wage", 0))
		if w < bw or (w == bw and str(row["character"]) < best):
			best = str(row["character"])
			bw = w
	return best


## H13: between phase changes, when the head is free at its workshop (not in a cycle) and the market is open: off to
## sell when the store holds a batch (sell_batch pieces) the market takes over its floor; off to buy when its recipe
## lacks inputs and its gold is over its reserve (once per hour at most). RivalAI then runs those tasks as always.
static func errands(sim: Sim, fam: String, head: String, home: String, profile: Dictionary, ai: Dictionary) -> void:
	if not on(sim) or not _tick(sim, fam):
		return
	var now := int(sim.state.clock["minute"])
	if now < int(_mem(sim, fam).get("errand_at", -1)) or not Market.is_open(sim):
		return
	var plan: Array = ai.get("plan", [])
	if not plan.is_empty() and not str(plan[0]) in ["work", "home"]:
		return
	if Production.job_zone(sim, head, home) != "":
		return
	var c := cfg(sim)
	var thr := RivalAI.sell_min_demand(sim, profile)
	var storage := RivalAI._storage(sim, home)
	var batch := 0
	for item: String in RivalAI._sellable_items(sim, fam, head, home, ai):
		if Market.demand(sim, item) >= thr:
			batch += mini(Inventory.count(storage, item), RivalAI.units_above(Market.demand(sim, item), thr,
				float(sim.catalog.market.get("demand", {}).get("drop_per_unit", 0.04))))
	var add: Array = []
	if batch >= int(c.get("sell_batch", 3)):
		add.append("sell")
	var rid := str(ai.get("recipe", ""))
	if rid != "" and Money.gold(sim.state, fam) > int(profile.get("gold_reserve", 20)) \
			and RivalAI._status(sim, head, home, rid) == "missing_inputs" \
			and not RivalAI.buy_needs(sim, fam, head, home, profile, ai).is_empty():
		add.append("buy")
	if add.is_empty():
		_mem(sim, fam)["errand_at"] = now + int(c.get("check_minutes", 15))  # nothing to go for: look again later
		return
	_mem(sim, fam)["errand_at"] = now + int(c.get("errand_every", 60))
	add.append("home")
	add.append_array(plan)
	ai["plan"] = add
	if OS.is_debug_build():
		print("[AIEconomy] %s sale al mercado: %s (lote %d)" % [fam, add, batch])


## H13: the recipe the head works when its own recipe's station is taken by one of its hands: the hands' choice for
## it (_hand_recipe), "" off the economy maps or if none.
static func other_station(sim: Sim, fam: String, head: String, home: String) -> String:
	if not on(sim):
		return ""
	return _hand_recipe(sim, fam, head, home)


## H13 (make or buy): an input of `need` the workshop makes from cheaper raw materials (the inputs of its recipe cost
## less than buying the piece) is bought as those raw materials instead; RivalAI's work makes it first (sub-recipe).
static func make_or_buy(sim: Sim, actor: String, home: String, need: Dictionary) -> void:
	if not on(sim):
		return
	for item: String in need.keys():
		var sub := RivalAI._recipe_for(sim, actor, home, item)
		if sub == "":
			continue
		var r: Dictionary = sim.catalog.recipes()[sub]
		var per := maxi(1, int(r["output"].get("qty", 1)))
		var raw := 0
		for inp: Dictionary in r.get("inputs", []):
			raw += Market.price(sim, str(inp["item"]), Inventory.NORMAL, "buy") * int(inp["qty"])
		if float(raw) / float(per) >= float(Market.price(sim, item, Inventory.NORMAL, "buy")):
			continue
		var qty := int(need[item])
		need.erase(item)
		var cycles := ceili(float(qty) / float(per))
		for inp: Dictionary in r.get("inputs", []):
			need[str(inp["item"])] = int(need.get(str(inp["item"]), 0)) + int(inp["qty"]) * cycles


## The gold a family keeps out of its price wars and the floor under which it lets an employee go: its gold_reserve;
## on the economy maps also reserve_days (04c 4.21.5.4, the profile's, else economy.reserve_days) of its fixed costs
## (the upkeep and wages due at the next dawn). Not for its inputs: they are its working capital (without them it
## would make nothing and sink).
static func reserve(sim: Sim, fam: String, profile: Dictionary) -> int:
	var base := int(profile.get("gold_reserve", 0))
	if not on(sim):
		return base
	var fixed := int(Upkeep.due_next_dawn(sim, fam)["total"])  # upkeep, wages and debt due at the next dawn
	return base + int(profile.get("reserve_days", cfg(sim).get("reserve_days", 2))) * fixed


## Whether one more hand on `rid` earns its wage: the extra pieces a day the market still takes (cycles_for of two
## hands' day minus one hand's) × the recipe's margin now ≥ hire_pay × wage.
static func _pays(sim: Sim, fam: String, home: String, profile: Dictionary, rid: String, wage: int) -> bool:
	var day := RivalAI.work_minutes_per_day(sim, profile) / maxi(1, Production.cycle_minutes(sim.catalog,
		sim.catalog.recipes()[rid], "normal"))
	var extra := cycles_for(sim, fam, home, rid, day * 2) - cycles_for(sim, fam, home, rid, day)
	return extra * unit_margin(sim, home, rid) >= float(cfg(sim).get("hire_pay", 1.5)) * wage


## H13 (austerity, 04c 4.21.6.3 in small): under its reserve a family sells its stock down to austerity_demand (if
## lower than its usual floor) to raise cash before it runs dry; `thr` otherwise and off the economy maps.
static func austerity_floor(sim: Sim, fam: String, profile: Dictionary, thr: float) -> float:
	if not on(sim) or Money.gold(sim.state, fam) >= reserve(sim, fam, profile):
		return thr
	return minf(thr, float(cfg(sim).get("austerity_demand", 0.6)))


## H13 (make or buy, the way a family counts): what one piece of `rid` leaves at `home`: its sell price now minus
## its inputs, each at the cheaper of buying it and making it there from bought raw materials (one level).
static func unit_margin(sim: Sim, home: String, rid: String) -> int:
	return int(_costing(sim, home, rid)["margin"])


## The same per hour of work (its own cycle plus the cycles of the inputs it makes itself).
static func rate(sim: Sim, home: String, rid: String) -> float:
	var c := _costing(sim, home, rid)
	return float(c["margin"]) / maxf(0.1, float(c["hours"]))


static func _costing(sim: Sim, home: String, rid: String) -> Dictionary:
	var r: Dictionary = sim.catalog.recipes().get(rid, {})
	var out: Dictionary = r.get("output", {})
	var per := maxi(1, int(out.get("qty", 1)))
	var m := Market.price(sim, str(out.get("item", "")), Inventory.NORMAL, "sell") * per
	var hours := float(r.get("duration_hours", 1.0))
	var btype := str(sim.state.buildings.get(home, {}).get("type", ""))
	for inp: Dictionary in r.get("inputs", []):
		var item := str(inp["item"])
		var q := int(inp["qty"])
		var buy := Market.price(sim, item, Inventory.NORMAL, "buy")
		var made := _made_cost(sim, btype, item)
		if made.is_empty() or int(made["cost"]) >= buy:
			m -= buy * q
		else:
			m -= int(made["cost"]) * q
			hours += float(made["hours"]) * q
	return {"margin": m / per, "hours": hours / per}


## What one `item` costs to make in a `btype` workshop from bought inputs ({cost, hours} per piece), {} if none makes it.
static func _made_cost(sim: Sim, btype: String, item: String) -> Dictionary:
	var ids: Array = sim.catalog.recipes().keys()
	ids.sort()
	for rid: String in ids:
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) != btype or str(r.get("output", {}).get("item", "")) != item:
			continue
		var per := maxi(1, int(r["output"].get("qty", 1)))
		var c := 0
		for inp: Dictionary in r.get("inputs", []):
			c += Market.price(sim, str(inp["item"]), Inventory.NORMAL, "buy") * int(inp["qty"])
		return {"cost": c / per, "hours": float(r.get("duration_hours", 1.0)) / per}
	return {}


## H13: what a family keeps under its spending on titles and offices on the economy maps (its reserve: a candidacy
## must not leave it without gold for its upkeep); 0 elsewhere (the spare_gold of the profile as always).
static func spare_floor(sim: Sim, fam: String, profile: Dictionary) -> int:
	return reserve(sim, fam, profile) if on(sim) else 0



## H13 (04c 4.21.6.3 in small: the loan before the bankruptcy): at dawn, after the upkeep, each AI family repays its
## credit with the gold over its reserve and, if it cannot pay the next dawn, borrows (see the header). Off the
## economy maps it does nothing.
static func step(sim: Sim) -> void:
	if not on(sim) or not Ledger.is_dawn(sim):
		return
	var c: Dictionary = cfg(sim).get("credit", {})
	if c.is_empty():
		return
	var st := sim.state
	var today := Clock.day(int(st.clock["minute"]))
	for fam: String in Hostility._ai_families(st):
		var profile := Hostility._profile(sim, fam)
		var open := ""
		for id: String in Loans.of_family(sim, fam):
			if str(st.loans[id].get("kind", "")) == CREDIT:
				open = id
		if open != "":
			_repay(sim, fam, open, Money.gold(st, fam) - reserve(sim, fam, profile))
			continue
		var gold := Money.gold(st, fam)
		var due := int(Upkeep.due_next_dawn(sim, fam)["total"])
		var mem := _mem(sim, fam)
		if gold >= due or today - int(mem.get("credit_day", -9999)) < int(c.get("gap_days", 4)):
			continue
		var debt := 0  # what it owes the town for upkeep: the credit clears it (a damaged workshop is repaired)
		for b: String in st.buildings:
			if Money.family_of(st, b) == fam:
				debt += int(st.buildings[b].get("upkeep_debt", 0))
		var amount := mini(int(c.get("amount", 120)) + debt, int(c.get("max_amount", 300)))
		var owed := roundi(amount * (1.0 + float(c.get("interest", 0.2))))
		var terms := {"lender": "moneylender", "overdue_reputation": int(c.get("overdue_reputation", -5)),
			"extension_seasons": int(c.get("extension_seasons", 1)),
			"extension_surcharge": float(c.get("extension_surcharge", 0.25))}
		var id := Loans.create(st, fam, terms, owed,
			int(st.clock["minute"]) + int(c.get("term_days", 8)) * Clock.MINUTES_PER_DAY, Hostility._workshop_of(st, fam))
		st.loans[id]["kind"] = CREDIT
		Money.change(sim, fam, amount, Money.LOANS, id)
		mem["credit_day"] = today
		var ids: Array = st.buildings.keys()
		ids.sort()
		for b: String in ids:  # the upkeep it owes first: the town is paid and a damaged workshop repaired
			if Money.family_of(st, b) == fam and int(st.buildings[b].get("upkeep_debt", 0)) > 0:
				Upkeep._charge(sim, b, fam, 0)
		sim.events.append({"type": "ai_credit_taken", "family": fam, "loan": id, "amount": amount, "owed": owed})
		if OS.is_debug_build():
			print("[AIEconomy] %s pide crédito: oro=%d < %d de mañana; recibe %d, devuelve %d en %d días (%s)" % [fam,
				gold, due, amount, owed, int(c.get("term_days", 8)), id])


static func _repay(sim: Sim, fam: String, id: String, spare: int) -> void:
	var loan: Dictionary = sim.state.loans[id]
	var pay := mini(spare, int(loan["outstanding"]))
	if pay <= 0:
		return
	Money.change(sim, fam, -pay, Money.LOANS, id)
	loan["outstanding"] = int(loan["outstanding"]) - pay
	sim.events.append({"type": "loan_payment", "actor": "", "family": fam, "loan": id, "amount": pay,
		"outstanding": int(loan["outstanding"])})
	if int(loan["outstanding"]) == 0:
		loan["state"] = Loans.PAID
		sim.events.append({"type": "loan_repaid", "actor": "", "family": fam, "loan": id,
			"extended": bool(loan["extended"])})
	if OS.is_debug_build():
		print("[AIEconomy] %s devuelve %d de su crédito %s: quedan %d" % [fam, pay, id, int(loan["outstanding"])])
