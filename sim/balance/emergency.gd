class_name Emergency
extends RefCounted
## A game never dies (Equilibrio 2, docs/decisiones.json; GDD 4.16 «Sin salida»). Figures: data/accounts.json
## "emergency".
##
## - **Offer.** A human family with less than gold_below of gold and goods worth less than stock_below (every stock of
##   its buildings, its members' bags and the errands on their way, at the market's sell price) and no emergency loan
##   open is offered an emergency loan by the moneylender: small (amount), dear (interest) and with a term (term_days).
##   The notice is said once a day while the offer stands. Order take_emergency_loan {actor}: the gold comes in
##   (category loans) and a loan of kind "emergency" opens (Loans: warnings, the extension with its surcharge, then the
##   seizure). At most max_per_year a year.
## - **Seizure of a good.** When the upkeep the family owes to the town reaches seize_upkeep_debt (checked at dawn), or
##   when an emergency loan's extension falls due and its gold and goods do not cover it, the most valuable good that is
##   not the home is seized: a building other than the home (it goes back on sale; its employees leave), a cart or a
##   piece of equipment. Its value × seize_rate pays the upkeep debt and the emergency loan; what is left comes to the
##   family (category property). Without goods, ruin: the game ends (D18), with its end screen.
## Only the human families: the AI's bankruptcy and austerity are 04c's (H6).
## State: families[fam].emergency {offer_day, last_notice_day, taken: [day]} (read with defaults: no save version).

const KIND: String = "emergency"


static func _cfg(sim: Sim) -> Dictionary:
	return sim.catalog.accounts.get("emergency", {})


static func _year_days(sim: Sim) -> int:
	return maxi(1, Clock.days_per_year(sim.catalog.time))


static func _today(sim: Sim) -> int:
	return Clock.day(int(sim.state.clock["minute"]))


static func _mem(st: WorldState, fam: String) -> Dictionary:
	var f: Dictionary = st.families[fam]
	if not f.get("emergency") is Dictionary:
		f["emergency"] = {"offer_day": -1, "last_notice_day": -1, "taken": []}
	return f["emergency"]


## Every hour on the hour: the offer of the human families with nothing left; at dawn, the seizure for upkeep debt.
static func step(sim: Sim) -> void:
	var st := sim.state
	if not st.ending.is_empty() or _cfg(sim).is_empty():
		return
	var dawn := Ledger.is_dawn(sim)
	if not dawn and int(st.clock["minute"]) % 60 != 0:
		return
	for fam: String in Life.humans(st):
		if dawn:
			_check_upkeep_seizure(sim, fam)
			if not st.ending.is_empty():
				return
		var offer := offer_of(sim, fam)
		if offer.is_empty():
			continue
		var mem := _mem(st, fam)
		if int(mem.get("last_notice_day", -1)) == _today(sim):
			continue
		mem["last_notice_day"] = _today(sim)
		mem["offer_day"] = _today(sim)
		Notices.add(sim, fam, Notices.URGENT, "notice.emergency_offer", {"amount": int(offer["amount"]),
			"owed": int(offer["owed"]), "days": int(offer["term_days"])})
		sim.events.append({"type": "emergency_offered", "family": fam, "amount": int(offer["amount"])})
		if OS.is_debug_build():
			print("[Emergency] %s sin salida (oro=%d, bienes=%d): el prestamista ofrece %d (devuelve %d en %d días)" % [
				fam, Money.gold(st, fam), stock_value(sim, fam), int(offer["amount"]), int(offer["owed"]),
				int(offer["term_days"])])


## {} if `fam` has no emergency loan to take now; else {amount, owed, term_days}. Read only (the UI and the bots ask).
static func offer_of(sim: Sim, fam: String) -> Dictionary:
	var st := sim.state
	var cfg := _cfg(sim)
	if cfg.is_empty() or not st.families.has(fam) or not st.ending.is_empty():
		return {}
	if Money.gold(st, fam) >= int(cfg.get("gold_below", 15)):
		return {}
	if stock_value(sim, fam) >= int(cfg.get("stock_below", 20)):
		return {}
	for id: String in Loans.of_family(sim, fam):
		if str(st.loans[id].get("kind", "")) == KIND:
			return {}
	var year := _today(sim) / _year_days(sim)
	var n := 0
	for d: Variant in _mem(st, fam).get("taken", []):
		if int(d) / _year_days(sim) == year:
			n += 1
	if n >= int(cfg.get("max_per_year", 2)):
		return {}
	var amount := int(cfg.get("amount", 60))
	return {"amount": amount, "owed": roundi(amount * (1.0 + float(cfg.get("interest", 0.5)))),
		"term_days": int(cfg.get("term_days", 4))}


## {"type": "take_emergency_loan", "actor"}: the moneylender's emergency loan. Reasons: unknown_actor, no_family,
## too_young, no_emergency (the family is not out of gold and goods, or already has one).
static func order_take(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var fam := str(st.characters[actor].get("family", ""))
	if fam == "" or not st.families.has(fam):
		return Orders.fail("no_family")
	if not Kin.is_adult(sim, actor):
		return Orders.fail("too_young")
	var offer := offer_of(sim, fam)
	if offer.is_empty():
		return Orders.fail("no_emergency")
	var cfg := _cfg(sim)
	var due := int(st.clock["minute"]) + int(offer["term_days"]) * Clock.MINUTES_PER_DAY
	var terms := {"lender": "moneylender", "overdue_reputation": int(cfg.get("overdue_reputation", -5)),
		"extension_seasons": int(cfg.get("extension_seasons", 1)),
		"extension_surcharge": float(cfg.get("extension_surcharge", 0.25))}
	var id := Loans.create(st, fam, terms, int(offer["owed"]), due, _home_of(st, fam))
	st.loans[id]["kind"] = KIND
	Money.change(sim, fam, int(offer["amount"]), Money.LOANS, id, "", actor)
	(_mem(st, fam)["taken"] as Array).append(_today(sim))
	sim.events.append({"type": "emergency_loan", "family": fam, "actor": actor, "loan": id,
		"amount": int(offer["amount"]), "owed": int(offer["owed"])})
	Notices.add(sim, fam, Notices.WARNING, "notice.emergency_taken", {"amount": int(offer["amount"]),
		"owed": int(offer["owed"]), "days": int(offer["term_days"])})
	if OS.is_debug_build():
		print("[Emergency] %s toma el préstamo de urgencia %s: +%d, debe %d (vence el minuto %d)" % [fam, id,
			int(offer["amount"]), int(offer["owed"]), due])
	return Orders.ok()


## What the goods of `fam` would fetch at the market now: its buildings' storage, its members' bags and its errands.
static func stock_value(sim: Sim, fam: String) -> int:
	var st := sim.state
	var v := 0
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Money.family_of(st, b) == fam:
			v += _inv_value(sim, st.buildings[b].get("inventory", {}))
	for c: Variant in st.families[fam].get("members", []):
		if st.characters.has(str(c)):
			v += _inv_value(sim, st.characters[str(c)].get("inventory", {}))
	for d: Dictionary in st.deliveries:
		if Money.family_of(st, str(d.get("to", d.get("building", "")))) == fam:
			v += Market.price(sim, str(d.get("item", "")), int(d.get("quality", 0)), "sell") * int(d.get("qty", 0))
	return v


static func _inv_value(sim: Sim, inv: Dictionary) -> int:
	var v := 0
	for s: Dictionary in inv.get("stacks", []):
		v += Market.price(sim, str(s["item"]), int(s["quality"]), "sell") * int(s["qty"])
	return v


## The home of `fam`: the home of its head (else of its first member), else its first building.
static func _home_of(st: WorldState, fam: String) -> String:
	var f: Dictionary = st.families.get(fam, {})
	var head := str(f.get("head", ""))
	if st.characters.has(head) and str(st.characters[head].get("home", "")) != "":
		return str(st.characters[head]["home"])
	for c: Variant in f.get("members", []):
		if st.characters.has(str(c)) and str(st.characters[str(c)].get("home", "")) != "":
			return str(st.characters[str(c)]["home"])
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Money.family_of(st, b) == fam:
			return b
	return ""


## The goods of `fam` that can be seized, the most valuable first: [{kind: building|cart|equipment, id, value, ...}].
## Never the home (nor a building someone of the family lives in).
static func goods(sim: Sim, fam: String) -> Array:
	var st := sim.state
	var homes := {_home_of(st, fam): true}
	for c: Variant in st.families[fam].get("members", []):
		if st.characters.has(str(c)):
			homes[str(st.characters[str(c)].get("home", ""))] = true
	var out: Array = []
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Money.family_of(st, b) != fam or homes.has(b):
			continue
		var def: Dictionary = sim.catalog.buildings().get(str(st.buildings[b].get("type", "")), {})
		out.append({"kind": "building", "id": b, "value": int(def.get("sale_price", def.get("build_cost", 0)))})
	var carts := Caravans.carts(sim, fam) - Caravans.busy_carts(sim, fam)
	var cart_price := int(sim.catalog.trade.get("caravans", {}).get("cart_price", 120))
	for i: int in carts:
		out.append({"kind": "cart", "id": "cart_%d" % i, "value": cart_price})
	var members: Array = (st.families[fam].get("members", []) as Array).duplicate()
	members.sort()
	for c: Variant in members:
		var ch: Dictionary = st.characters.get(str(c), {})
		var eqd: Dictionary = ch.get("equipment", {}) if ch.get("equipment") is Dictionary else {}
		var slots: Array = eqd.keys()
		slots.sort()
		for slot: Variant in slots:
			var piece: Variant = eqd[slot]
			if not piece is Dictionary or str((piece as Dictionary).get("item", "")) == "":
				continue
			var item := str(piece["item"])
			var q := int((piece as Dictionary).get("quality", 0))
			out.append({"kind": "equipment", "id": "%s|%s" % [str(c), str(slot)], "character": str(c),
				"slot": str(slot), "item": item, "quality": q, "value": Market.price(sim, item, q, "sell")})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["value"]) > int(b["value"]) or (int(a["value"]) == int(b["value"]) and str(a["id"]) < str(b["id"])))
	return out.filter(func(g: Dictionary) -> bool: return int(g["value"]) > 0)


## The upkeep `fam` owes to the town, over all its buildings.
static func upkeep_debt(st: WorldState, fam: String) -> int:
	var d := 0
	for b: String in st.buildings:
		if Money.family_of(st, b) == fam:
			d += int(st.buildings[b].get("upkeep_debt", 0))
	return d


static func _check_upkeep_seizure(sim: Sim, fam: String) -> void:
	var debt := upkeep_debt(sim.state, fam)
	if debt < int(_cfg(sim).get("seize_upkeep_debt", 100)):
		return
	if OS.is_debug_build():
		print("[Emergency] %s debe %d de mantenimiento (umbral %d): embargo de un bien" % [fam, debt,
			int(_cfg(sim).get("seize_upkeep_debt", 100))])
	if not seize_good(sim, fam, "upkeep"):
		ruin(sim, fam, "upkeep", debt)


## Seizes the most valuable good of `fam` that is not the home: its value × seize_rate pays the upkeep debt, then the
## open emergency loan, and the rest comes to the family. false if there is nothing to seize.
static func seize_good(sim: Sim, fam: String, why: String) -> bool:
	var st := sim.state
	var list := goods(sim, fam)
	if list.is_empty():
		return false
	var g: Dictionary = list[0]
	var proceeds := roundi(float(g["value"]) * float(_cfg(sim).get("seize_rate", 0.75)))
	match str(g["kind"]):
		"building":
			var b := str(g["id"])
			for c: Variant in Staff.employees_of(st, b):
				Staff._leave(sim, str(c), "seized")
			st.buildings[b]["owner"] = ""
			st.buildings[b]["for_sale"] = true
			st.buildings[b]["upkeep_debt"] = 0
		"cart":
			var carts: Dictionary = Region.ensure(sim)["carts"]
			carts[fam] = maxi(0, int(carts.get(fam, 0)) - 1)
		"equipment":
			var ch: Dictionary = st.characters[str(g["character"])]
			(ch["equipment"] as Dictionary).erase(str(g["slot"]))
	Money.change(sim, fam, proceeds, Money.PROPERTY, "seizure", str(g["id"]) if str(g["kind"]) == "building" else "")
	# the upkeep owed first, then the emergency loan
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Money.family_of(st, b) == fam and int(st.buildings[b].get("upkeep_debt", 0)) > 0:
			Upkeep._charge(sim, b, fam, 0)
	for id: String in Loans.of_family(sim, fam):
		var loan: Dictionary = st.loans[id]
		if str(loan.get("kind", "")) != KIND:
			continue
		var pay := mini(int(loan["outstanding"]), maxi(0, Money.gold(st, fam)))
		if pay > 0:
			Money.change(sim, fam, -pay, Money.LOANS, id)
			loan["outstanding"] = int(loan["outstanding"]) - pay
		if int(loan["outstanding"]) <= 0:
			loan["state"] = Loans.PAID
	Chronicle.add(st, "seizure", {"family": fam, "kind": str(g["kind"]), "good": str(g["id"]), "value": int(g["value"]),
		"why": why})
	sim.events.append({"type": "good_seized", "family": fam, "kind": str(g["kind"]), "good": str(g["id"]),
		"value": int(g["value"]), "proceeds": proceeds, "why": why})
	var params := {"value": proceeds, "gold": Money.gold(st, fam)}
	if str(g["kind"]) == "building":
		params["building"] = str(g["id"])
	if str(g["kind"]) == "equipment":
		params["item"] = str(g["item"])
	Notices.add(sim, fam, Notices.URGENT, "notice.seized_" + str(g["kind"]), params,
		str(g["id"]) if str(g["kind"]) == "building" else "")
	if OS.is_debug_build():
		print("[Emergency] embargo (%s) de %s: %s %s (valor=%d, cobra=%d, oro ahora=%d)" % [why, fam, g["kind"],
			g["id"], int(g["value"]), proceeds, Money.gold(st, fam)])
	return true


## The end of the game by ruin (D18): nothing left to seize.
static func ruin(sim: Sim, fam: String, why: String, missing: int) -> void:
	var st := sim.state
	Notices.add(sim, fam, Notices.URGENT, "notice.ruin_goods", {"missing": missing, "why": why})
	if st.ending.is_empty() and str(st.families.get(fam, {}).get("controlled_by", "")) == "human":  # only the player's
		st.ending = {"kind": "ruin", "family": fam, "minute": int(st.clock["minute"]), "why": why}
		sim.events.append({"type": "game_over", "kind": "ruin", "family": fam})
		if OS.is_debug_build():
			print("[Emergency] RUINA: %s no tiene bienes que embargar (%s, faltan %d). Fin de la partida." % [fam, why,
				missing])
