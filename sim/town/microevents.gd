class_name Microevents
extends RefCounted
## Microevents (GDD 4.20): small happenings of a building that ask for a quick decision. Data: data/microevents/<id>.json
## (trigger, cooldown, choices with declarative effects, default, timeout); figures in data/town.json "microevents" and
## the difficulty's microevent_chance. Contract: docs/contratos/h7_ciudad.md.
##
## At dawn each playing family (human, or AI with a profile) that owns buildings rolls base_chance × microevent_chance
## (town stream, never state.rng); at most one a day. A hit picks an eligible microevent (its conditions hold for one of
## the family's buildings, not on cooldown there) by its weight (chance_per_day) and plans it: sick_employee starts at
## once, night_thief comes during the night, haggling_customer waits for the next customer with Negotiation >= 6 served
## that day. Started: an active card (state.microevents.active) until the family chooses (resolve_microevent) or the
## timeout passes (the default choice applies). AI families choose the default at once [provisional, 4.21 open].

const DAWN: String = "dawn"


## Once per minute, after Staff (the wages of the day are paid before a sick employee is known).
static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var phase := Clock.phase(now, sim.catalog.time)
	for e: Dictionary in sim.events:
		if str(e.get("type", "")) == "phase_changed" and str(e.get("phase", "")) == DAWN:
			_dawn(sim, now)
	var pending: Array = st.microevents.get("pending", [])
	if not pending.is_empty():
		var keep: Array = []
		for p: Dictionary in pending:
			match str(p.get("def", "")):
				"night_thief":
					if now >= int(p.get("at", 0)):
						_thief(sim, p)
						continue
				"haggling_customer":
					if Clock.day(now) != int(p.get("day", -1)) or phase in ["dusk", "night"]:  # the counter day is over
						if OS.is_debug_build():
							print("[Microevents] el regateo de %s no llegó (sin cliente)" % p.get("family", ""))
						continue
			keep.append(p)
		st.microevents["pending"] = keep
	var active: Array = st.microevents.get("active", [])
	for m: Dictionary in active.duplicate():
		if now >= int(m.get("expires", 0)):
			_resolve(sim, m, str(m.get("default", "")), "timeout")


## The dawn roll of every playing family.
static func _dawn(sim: Sim, now: int) -> void:
	var st := sim.state
	var today := Clock.day(now)
	var cfg: Dictionary = sim.catalog.town.get("microevents", {})
	var lever := float(sim.catalog.difficulty_levels(st.difficulty).get("microevent_chance", 1.0))
	var fams: Array = st.families.keys()
	fams.sort()
	for fam: String in fams:
		if not plays(st, fam):
			continue
		if int(st.microevents["last_day"].get(fam, -1)) == today:
			continue
		var r := Kin.roll(st, "mev|day|%s|%d" % [fam, today])
		var chance := float(cfg.get("base_chance", 0.35)) * lever
		if r >= chance:
			continue
		var options := eligible(sim, fam, today)
		if options.is_empty():
			continue
		var total := 0.0
		for o: Dictionary in options:
			total += float(o["weight"])
		var x := Kin.roll(st, "mev|pick|%s|%d" % [fam, today]) * total
		var pick: Dictionary = options[options.size() - 1]
		for o: Dictionary in options:
			x -= float(o["weight"])
			if x < 0.0:
				pick = o
				break
		st.microevents["last_day"][fam] = today
		if OS.is_debug_build():
			print("[Microevents] %s: sale microevento el día %d (tirada %.3f < %.3f): %s en %s" % [fam, today, r, chance,
				pick["def"], pick["building"]])
		_plan(sim, str(pick["def"]), fam, str(pick["building"]), today)


## Whether `fam` plays (gets microevents): the human family or an AI one with a profile.
static func plays(st: WorldState, fam: String) -> bool:
	var f: Dictionary = st.families.get(fam, {})
	return str(f.get("controlled_by", "")) == "human" or str(f.get("ai_profile", "")) != ""


## The microevents `fam` may get today: [{def, building, weight}] (conditions hold, not on cooldown).
static func eligible(sim: Sim, fam: String, today: int) -> Array:
	var st := sim.state
	var out: Array = []
	var defs: Array = sim.catalog.microevents().keys()
	defs.sort()
	var blds: Array = st.buildings.keys()
	blds.sort()
	for d: String in defs:
		var def: Dictionary = sim.catalog.microevents()[d]
		for b: String in blds:
			if str(st.buildings[b].get("owner", "")) != fam:
				continue
			if int(st.microevents["cooldowns"].get("%s|%s" % [d, b], -1)) >= today:
				continue
			if not _conditions(sim, def.get("trigger", {}).get("conditions", []), b):
				continue
			out.append({"def": d, "building": b, "weight": float(def.get("trigger", {}).get("chance_per_day", 1.0))})
			break
	return out


static func _conditions(sim: Sim, conds: Array, bld: String) -> bool:
	for c: Variant in conds:
		match str(c):
			"counter_sales":
				if not Upgrades.flag(sim, bld, "counter_sales"):
					return false
			"has_employees":
				if _active_employees(sim, bld).is_empty():
					return false
			"has_goods":
				if _most_valuable(sim, bld).is_empty():
					return false
			"has_products":  # something to sell at the counter (a haggle without goods makes no sense)
				if Counter.best_product(sim, bld).is_empty():
					return false
	return true


static func _active_employees(sim: Sim, bld: String) -> Array:
	return Staff.employees_of(sim.state, bld).filter(func(e: String) -> bool: return Staff.is_active(sim, e))


## Plans the chosen microevent for today.
static func _plan(sim: Sim, def: String, fam: String, bld: String, today: int) -> void:
	var st := sim.state
	match def:
		"sick_employee":
			var emps := _active_employees(sim, bld)
			if emps.is_empty():
				return
			var who: String = emps[Kin.randi_range(st, "mev|sick|%s|%d" % [bld, today], 0, emps.size() - 1)]
			start(sim, def, fam, bld, who)
		"night_thief":
			var span: Array = sim.catalog.town.get("microevents", {}).get("thief_start_hours", [1, 5])
			var starts: Dictionary = sim.catalog.time["phase_starts"][Clock.season(today * Clock.MINUTES_PER_DAY, sim.catalog.time)]
			var at := today * Clock.MINUTES_PER_DAY + int(starts.get("night", 1260)) \
				+ Kin.randi_range(st, "mev|thief|%s|%d" % [bld, today], int(span[0]) * 60, int(span[1]) * 60)
			(st.microevents["pending"] as Array).append({"def": def, "family": fam, "building": bld, "day": today, "at": at})
		_:
			(st.microevents["pending"] as Array).append({"def": def, "family": fam, "building": bld, "day": today, "at": -1})


## Starts a microevent card: {id, def, family, building, target, actor, started, expires, choices, default, context}.
## Cooldown for that building, notice (human family), event. An AI family chooses the default at once. Returns its id.
static func start(sim: Sim, def: String, fam: String, bld: String, target: String, actor: String = "",
		context: Dictionary = {}) -> String:
	var st := sim.state
	var d: Dictionary = sim.catalog.microevents().get(def, {})
	if d.is_empty():
		return ""
	var now := int(st.clock["minute"])
	var today := Clock.day(now)
	var hours := float(d.get("timeout_hours", sim.catalog.town.get("microevents", {}).get("timeout_hours", 2)))
	var ids: Array = []
	for c: Dictionary in d.get("choices", []):
		ids.append(str(c["id"]))
	var id := Ids.next(st, "mev")
	var m := {"id": id, "def": def, "family": fam, "building": bld, "target": target, "actor": actor, "started": now,
		"expires": now + roundi(hours * 60.0), "choices": ids, "default": str(d.get("default_choice", "")),
		"context": context.duplicate()}
	if def == "sick_employee" and st.characters.get(target, {}).get("job") is Dictionary:
		st.characters[target]["job"]["absent_until"] = today  # sick today, whatever is chosen
	(st.microevents["active"] as Array).append(m)
	_cooldown(sim, def, bld, today, d)
	st.microevents["last_day"][fam] = today
	sim.events.append({"type": "microevent_started", "id": id, "def": def, "family": fam, "building": bld,
		"target": target})
	if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, fam, Notices.URGENT, "notice.microevent." + def, _params(sim, m), bld)
	if OS.is_debug_build():
		print("[Microevents] empieza %s (%s) en %s para %s: objetivo %s, caduca a los %d min" % [id, def, bld, fam,
			target, roundi(hours * 60.0)])
	if not str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		sim.give({"type": "resolve_microevent", "actor": _family_actor(sim, fam, bld), "microevent": id,
			"choice": str(m["default"])})
	return id


static func _cooldown(sim: Sim, def: String, bld: String, today: int, d: Dictionary) -> void:
	var days := int(d.get("cooldown_days", sim.catalog.town.get("microevents", {}).get("cooldown_days", 8)))
	sim.state.microevents["cooldowns"]["%s|%s" % [def, bld]] = today + days - 1


## Who acts for family `fam` at `bld`: a member inside, else the head.
static func _family_actor(sim: Sim, fam: String, bld: String) -> String:
	var inside := _member_inside(sim, fam, bld)
	return inside if inside != "" else Kin.head(sim.state, fam)


static func _member_inside(sim: Sim, fam: String, bld: String) -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = sim.state.characters[id]
		if str(ch.get("family", "")) == fam and bool(ch.get("alive", true)) and str(ch.get("location", "")) == bld:
			return id
	return ""


# --- The three microevents --------------------------------------------------------------------------------------

## The night thief arrives: nobody of the family inside → no card, Security may foil it, else it steals; somebody
## inside → the card (confront / let him).
static func _thief(sim: Sim, p: Dictionary) -> void:
	var st := sim.state
	var fam := str(p["family"])
	var bld := str(p["building"])
	if not st.buildings.has(bld) or str(st.buildings[bld].get("owner", "")) != fam or _most_valuable(sim, bld).is_empty():
		return
	var inside := _member_inside(sim, fam, bld)
	if inside != "":
		start(sim, "night_thief", fam, bld, "", inside, {"name": str(st.characters[inside].get("name", ""))})
		return
	var d: Dictionary = sim.catalog.microevents().get("night_thief", {})
	var today := Clock.day(int(st.clock["minute"]))
	_cooldown(sim, "night_thief", bld, today, d)
	var id := Ids.next(st, "mev")
	sim.events.append({"type": "microevent_started", "id": id, "def": "night_thief", "family": fam, "building": bld,
		"target": ""})
	var m := {"id": id, "def": "night_thief", "family": fam, "building": bld, "target": "", "actor": "",
		"started": int(st.clock["minute"]), "expires": int(st.clock["minute"]), "choices": [], "default": "",
		"context": {}}
	_apply(sim, m, d.get("unattended_effects", []), "unattended")
	sim.events.append({"type": "microevent_resolved", "id": id, "def": "night_thief", "family": fam,
		"choice": "", "by": "unattended"})


## Called by Counter before a sale: a planned haggling_customer for this family and building starts with this customer
## (Negotiation >= haggle_min_negotiation). True if the card now holds the sale.
static func haggle(sim: Sim, fam: String, bld: String, customer: String, server: String, item: Dictionary) -> bool:
	var st := sim.state
	var pending: Array = st.microevents.get("pending", [])
	var plan := {}
	for p: Dictionary in pending:
		if str(p["def"]) == "haggling_customer" and str(p["family"]) == fam and str(p["building"]) == bld:
			plan = p
			break
	if plan.is_empty():
		return false
	if SkillCheck.stat(sim, customer, "negotiation") < int(sim.catalog.town.get("counter", {}).get("haggle_min_negotiation", 6)):
		return false
	pending.erase(plan)
	var price := Counter.price(sim, bld, server, str(item["item"]), int(item["quality"]), customer)
	var id := start(sim, "haggling_customer", fam, bld, customer, server, {"item": str(item["item"]),
		"quality": int(item["quality"]), "price": price, "name": str(st.characters[customer].get("name", ""))})
	return id != "" and holding(sim, customer)


## Whether `customer` waits for a haggling card to be decided.
static func holding(sim: Sim, customer: String) -> bool:
	for m: Dictionary in sim.state.microevents.get("active", []):
		if str(m.get("def", "")) == "haggling_customer" and str(m.get("target", "")) == customer:
			return true
	return false


# --- Choosing ---------------------------------------------------------------------------------------------------

## {"type": "resolve_microevent", "actor", "microevent", "choice"}: the actor is of the microevent's family.
static func order_resolve(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var m := _find(sim, str(o.get("microevent", "")))
	if m.is_empty():
		return Orders.fail("unknown_microevent")
	if str(st.characters[actor].get("family", "")) != str(m["family"]):
		return Orders.fail("not_your_family")
	var choice := str(o.get("choice", ""))
	if not choice in (m.get("choices", []) as Array):
		return Orders.fail("unknown_choice")
	if str(m.get("actor", "")) == "":
		m["actor"] = actor
	_resolve(sim, m, choice, "choice")
	return Orders.ok()


static func _find(sim: Sim, id: String) -> Dictionary:
	for m: Dictionary in sim.state.microevents.get("active", []):
		if str(m.get("id", "")) == id:
			return m
	return {}


## Applies `choice` of active microevent `m` and closes it (by: "choice" | "timeout").
static func _resolve(sim: Sim, m: Dictionary, choice: String, by: String) -> void:
	var st := sim.state
	(st.microevents["active"] as Array).erase(m)
	var d: Dictionary = sim.catalog.microevents().get(str(m["def"]), {})
	var effects: Array = []
	var text_key := ""
	for c: Dictionary in d.get("choices", []):
		if str(c["id"]) == choice:
			effects = c.get("effects", [])
			text_key = str(c.get("text_key", ""))
	_apply(sim, m, effects, choice)
	sim.events.append({"type": "microevent_resolved", "id": str(m["id"]), "def": str(m["def"]), "family": str(m["family"]),
		"choice": choice, "by": by})
	if str(st.families.get(str(m["family"]), {}).get("controlled_by", "")) == "human":
		Notices.add(sim, str(m["family"]), Notices.INFO, "notice.microevent_done", {"choice": text_key, "by": by},
			str(m["building"]))
	if OS.is_debug_build():
		print("[Microevents] %s (%s) se resuelve: %s (%s)" % [m["id"], m["def"], choice, by])


## The declarative effects (data/microevents) on microevent `m`.
static func _apply(sim: Sim, m: Dictionary, effects: Array, why: String) -> void:
	var st := sim.state
	var fam := str(m["family"])
	var bld := str(m["building"])
	var target := str(m.get("target", ""))
	var actor := str(m.get("actor", ""))
	if actor == "":
		actor = _family_actor(sim, fam, bld)
	var today := Clock.day(int(st.clock["minute"]))
	var ctx: Dictionary = m.get("context", {})
	for e: Dictionary in effects:
		match str(e.get("kind", "")):
			"sell":
				Counter.sell(sim, bld, target, actor, {"item": str(ctx.get("item", "")), "quality": int(ctx.get("quality", 0))},
					float(e.get("discount", 0.0)))
			"skill_check":
				var tv := int(e["target_value"]) if e.has("target_value") else SkillCheck.stat(sim, target, str(e.get("target_stat", "")))
				var r := SkillCheck.roll(sim, "mev|%s|%s|%d|%d" % [m["id"], why, int(m.get("started", 0)), int(st.clock["minute"])], SkillCheck.stat(sim, actor, str(e.get("actor_stat", ""))), tv)
				_apply(sim, m, e.get("success" if bool(r["success"]) else "fail", []), why)
			"leave":
				Counter.leave(sim, target, "haggle")
			"emotion":
				Emotions.add(sim, target, str(e.get("state", "")), fam)
			"relation":
				if actor != "" and target != "":
					Emotions.change_relation(sim, actor, target, int(e.get("amount", 0)), "microevent")
			"pay":
				var gold := int(e.get("gold", 0))
				if Money.can_pay(st, fam, gold):
					Money.change(sim, fam, -gold, str(e.get("category", Money.EVENTS)), str(m["id"]), bld, actor)
			"loyalty":
				if st.characters.get(target, {}).get("job") is Dictionary:
					Staff._add_loyalty(sim, target, int(e.get("amount", 0)), "microevent")
			"absent":
				var span: Array = e.get("days", [0, 0])
				if st.characters.get(target, {}).get("job") is Dictionary:
					st.characters[target]["job"]["absent_until"] = today + Kin.randi_range(st, "mev|absent|%s" % m["id"],
						int(span[0]), int(span[1]))
			"refund_wage":
				var w := Staff.wage(sim, target)
				var hh := str(st.characters.get(target, {}).get("family", ""))
				if w > 0 and hh != "" and Money.can_pay(st, hh, w):
					Money.change(sim, hh, -w, Money.WAGES, str(m["id"]), "", target)
					Money.change(sim, fam, w, Money.WAGES, str(m["id"]), bld, target)
			"steal":
				_steal(sim, m, e)
			"nothing":
				pass


## Whether the building's Security foils a thief: a roll under its protection (0.2 / 0.4 / 0.6, GDD 4.20).
static func security_foils(sim: Sim, bld: String, key: String) -> bool:
	var p := Upgrades.amount(sim, bld, "protection")
	return p > 0.0 and Kin.roll(sim.state, "mev|sec|" + key) < p


static func _steal(sim: Sim, m: Dictionary, e: Dictionary) -> void:
	var st := sim.state
	var fam := str(m["family"])
	var bld := str(m["building"])
	if bool(e.get("security", false)) and security_foils(sim, bld, str(m["id"])):
		sim.events.append({"type": "theft", "family": fam, "building": bld, "item": "", "qty": 0, "frustrated": true})
		if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
			Notices.add(sim, fam, Notices.INFO, "notice.theft_frustrated", {"building": bld}, bld)
		if OS.is_debug_build():
			print("[Microevents] la seguridad de %s frustra al ladrón (protección %.1f)" % [bld,
				Upgrades.amount(sim, bld, "protection")])
		return
	var best := _most_valuable(sim, bld)
	if best.is_empty():
		return
	var units: Array = e.get("units", [1, 3])
	var inv: Dictionary = st.buildings[bld]["inventory"]
	var qty := mini(Kin.randi_range(st, "mev|units|%s" % m["id"], int(units[0]), int(units[1])),
		Inventory.count(inv, str(best["item"]), int(best["quality"])))
	Inventory.remove(inv, str(best["item"]), int(best["quality"]), qty)
	sim.events.append({"type": "theft", "family": fam, "building": bld, "item": str(best["item"]), "qty": qty,
		"frustrated": false})
	if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, fam, Notices.URGENT, "notice.theft", {"building": bld, "item": str(best["item"]), "qty": qty}, bld)
	if OS.is_debug_build():
		print("[Microevents] un ladrón roba %d × %s de %s" % [qty, best["item"], bld])


## The most valuable stack of `bld`'s storage by market sell price ({item, quality} or {}); ties by item id, quality.
static func _most_valuable(sim: Sim, bld: String) -> Dictionary:
	var best := {}
	var best_price := -1
	for s: Dictionary in sim.state.buildings.get(bld, {}).get("inventory", {}).get("stacks", []):
		if int(s["qty"]) <= 0:
			continue
		var p := Market.price(sim, str(s["item"]), int(s["quality"]), "sell")
		var better := p > best_price
		if p == best_price and not best.is_empty():
			better = str(s["item"]) < str(best["item"]) or (str(s["item"]) == str(best["item"]) and int(s["quality"]) < int(best["quality"]))
		if better:
			best = {"item": str(s["item"]), "quality": int(s["quality"])}
			best_price = p
	return best


# --- Queries for the UI -----------------------------------------------------------------------------------------

## The active microevents of `fam`, oldest first.
static func active_for(sim: Sim, fam: String) -> Array:
	return (sim.state.microevents.get("active", []) as Array).filter(func(m: Dictionary) -> bool: return str(m["family"]) == fam)


## {id, def, text_key, params, choices: [{id, text_key}], default, minutes_left} of an active microevent ({} if none).
static func view(sim: Sim, id: String) -> Dictionary:
	var m := _find(sim, id)
	if m.is_empty():
		return {}
	var d: Dictionary = sim.catalog.microevents().get(str(m["def"]), {})
	var choices: Array = []
	for c: Dictionary in d.get("choices", []):
		choices.append({"id": str(c["id"]), "text_key": str(c.get("text_key", ""))})
	return {"id": id, "def": str(m["def"]), "text_key": str(d.get("text_key", "")), "params": _params(sim, m),
		"choices": choices, "default": str(m["default"]), "building": str(m["building"]),
		"minutes_left": maxi(0, int(m["expires"]) - int(sim.state.clock["minute"]))}


static func _params(sim: Sim, m: Dictionary) -> Dictionary:
	var ctx: Dictionary = m.get("context", {})
	var target := str(m.get("target", ""))
	var p := {"building": str(m["building"]), "item": str(ctx.get("item", "")), "price": int(ctx.get("price", 0))}
	p["name"] = str(ctx.get("name", sim.state.characters.get(target, {}).get("name", "")))
	return p
