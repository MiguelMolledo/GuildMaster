class_name Bankruptcy
extends RefCounted
## H6 · the bankruptcy of an AI family (docs/gdd/04c_ia_rival.md §4.21.6.3, Q9 b; data/construction.json
## "bankruptcy" [balance]). Evaluated at dawn (Construction.step), for the AI families with a profile, on the maps of
## the AI's economy (data/ai.json economy.maps: the families that run their money there; elsewhere nothing changes):
##   normal    -> austerity  the workshop's net of the last negative_days days is under 0 and its gold under its
##                           reserve (Construction.budget < 0) («neto negativo durante 2 años y la familia en
##                           austeridad»; the moneylender's credit comes first): no construction (Construction asks
##                           stage()), it lets its least efficient employee go.
##   austerity -> normal     after season_days, the season's net is >= 0 or its gold over the reserve again;
##             -> for_sale   else: the «Se vende» sign, public: price = (build cost + its upgrades' gold) × sale_share;
##                           the player buys it with buy_building (Plots.order_buy_from at that price, no refusal) and
##                           so may another AI family (Construction's candidates).
##   for_sale  -> sold       somebody bought it (the gold went to the family);
##             -> pulled     after season_days unsold: its employees go, it is pulled down (demolish_refund of its cost
##                           back), the plot is a free lot again.
##   then, with no business left: «venida a menos» (Q9 b): the family keeps its title and reputation, its adults can be
##   hired by anybody (Staff.is_unemployed), they lodge in a house of the town (characters.home) and, with gold again,
##   the family puts up a workshop (Construction, after_sale.fate «rebuilds»). With a business left, normal.
## Only the human family's ruin ends the game (forja, Loans._seize / Emergency.ruin); the moneylender's credit before
## all this is the AI's economy's (plantillas, ai_credit). Memory in families[f].ai_state.bankruptcy {stage, since,
## building}. Chronicle and notices: the sign («La forja de los Ferrer está en venta») and the fall.

const NORMAL: String = ""
const AUSTERITY: String = "austerity"
const FOR_SALE: String = "for_sale"


static func cfg(sim: Sim) -> Dictionary:
	return Plots.rules(sim).get("bankruptcy", {})


## Whether the bankruptcy runs on this map: its own list (data/construction.json bankruptcy.maps) if it has one, else
## the maps of the AI's economy (data/ai.json economy.maps).
static func on(sim: Sim) -> bool:
	var maps: Variant = cfg(sim).get("maps", null)
	if not maps is Array:
		maps = sim.catalog.ai_rules.get("economy", {}).get("maps", [])
	return sim.state.map_id in (maps as Array)


static func mem(sim: Sim, fam: String) -> Dictionary:
	var fd: Dictionary = sim.state.families[fam]
	if not fd.get("ai_state") is Dictionary:
		fd["ai_state"] = {}
	if not (fd["ai_state"] as Dictionary).get("bankruptcy") is Dictionary:
		fd["ai_state"]["bankruptcy"] = {"stage": NORMAL, "since": -1, "building": ""}
	return fd["ai_state"]["bankruptcy"]


## The family's stage ("" normal, austerity, for_sale), "" for a family that never went through any.
static func stage(sim: Sim, fam: String) -> String:
	var fd: Dictionary = sim.state.families.get(fam, {})
	var a: Variant = fd.get("ai_state")
	if not a is Dictionary or not (a as Dictionary).get("bankruptcy") is Dictionary:
		return NORMAL
	return str(a["bankruptcy"].get("stage", NORMAL))


## The family's workshop: its first building with stations (sorted by id), "" if none.
static func workshop_of(sim: Sim, fam: String) -> String:
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		var x: Dictionary = sim.state.buildings[b]
		if str(x.get("owner", "")) == fam and not (x.get("zones", {}) as Dictionary).is_empty() \
				and str(x.get("state", "")) != "construction":
			return b
	return ""


## The building's net in the family's book over days [from, to] (every entry tagged with the building).
static func net(sim: Sim, fam: String, bld: String, from_day: int, to_day: int) -> int:
	var n := 0
	for e: Dictionary in Ledger.entries(sim, fam, from_day, to_day):
		if str(e.get("building", "")) == bld:
			n += int(e.get("amount", 0))
	return n


static func step(sim: Sim) -> void:
	if not on(sim) or not Ledger.is_dawn(sim):
		return
	var st := sim.state
	var today := Clock.day(int(st.clock["minute"]))
	var fams: Array = st.families.keys()
	fams.sort()
	for fam: String in fams:
		var f: Dictionary = st.families[fam]
		if str(f.get("controlled_by", "")) != "ai" or str(f.get("ai_profile", "")) == "":
			continue
		var m := mem(sim, fam)
		match str(m["stage"]):
			NORMAL:
				_normal(sim, fam, m, today)
			AUSTERITY:
				_austerity(sim, fam, m, today)
			FOR_SALE:
				_for_sale(sim, fam, m, today)


static func _normal(sim: Sim, fam: String, m: Dictionary, today: int) -> void:
	var bld := workshop_of(sim, fam)
	if bld == "":
		return
	var days := int(cfg(sim).get("negative_days", 16))
	var losing := today >= days and net(sim, fam, bld, today - days, today - 1) < 0
	if not losing or Construction.budget(sim, fam) >= 0:
		return   # «neto negativo durante 2 años y la familia en austeridad» (04c): both; the credit comes first
	m["stage"] = AUSTERITY
	m["since"] = today
	m["building"] = bld
	m["type"] = str(sim.state.buildings[bld].get("type", ""))
	_let_go_worst(sim, bld)
	sim.events.append({"type": "ai_austerity", "family": fam, "building": bld})
	if OS.is_debug_build():
		print("[Bankruptcy] %s entra en austeridad (%s: neto %d en %d días, presupuesto %d)" % [fam, bld,
			net(sim, fam, bld, today - days, today - 1), days, Construction.budget(sim, fam)])


static func _austerity(sim: Sim, fam: String, m: Dictionary, today: int) -> void:
	var season := int(cfg(sim).get("season_days", 2))
	if today - int(m["since"]) < season:
		return
	var bld := str(m["building"])
	if not sim.state.buildings.has(bld) or str(sim.state.buildings[bld].get("owner", "")) != fam:
		_reset(m)
		return
	if net(sim, fam, bld, int(m["since"]), today - 1) >= 0 or Construction.budget(sim, fam) >= 0:
		_reset(m)
		sim.events.append({"type": "ai_recovered", "family": fam, "building": bld})
		return
	var b: Dictionary = sim.state.buildings[bld]
	b["for_sale"] = true
	b["sale_price"] = sale_price(sim, bld)
	m["stage"] = FOR_SALE
	m["since"] = today
	Chronicle.add(sim.state, "ai_for_sale", {"family": fam, "building": bld, "type": str(b["type"]),
		"price": int(b["sale_price"])})
	sim.events.append({"type": "ai_for_sale", "family": fam, "building": bld, "price": int(b["sale_price"])})
	for h: String in sim.state.families:
		if Plots.is_human(sim, h):
			Notices.add(sim, h, Notices.INFO, "notice.plots.ai_for_sale", {"building": bld, "family": fam,
				"price": int(b["sale_price"])}, bld)
	if OS.is_debug_build():
		print("[Bankruptcy] %s pone %s en venta por %d" % [fam, bld, int(b["sale_price"])])


static func _for_sale(sim: Sim, fam: String, m: Dictionary, today: int) -> void:
	var st := sim.state
	var bld := str(m["building"])
	if not st.buildings.has(bld) or str(st.buildings[bld].get("owner", "")) != fam:
		_reset(m)   # sold (Plots.order_buy_from wrote after_sale) or gone
		_after(sim, fam, today)
		return
	if today - int(m["since"]) < int(cfg(sim).get("season_days", 2)):
		return
	for e: String in Staff.employees_of(st, bld):
		st.characters[e]["job"] = null
		sim.events.append({"type": "employee_left", "family": fam, "building": bld, "employee": e, "reason": "closed"})
	var refund := roundi(float(Plots.build_cost(sim, str(st.buildings[bld]["type"]))) *
		float(cfg(sim).get("demolish_refund", 0.4)))
	var plot := Plots.plot_of(sim, bld)
	var door: Array = st.buildings[bld].get("door", [0, 0])
	for c: String in st.characters:
		if str(st.characters[c].get("location", "")) == bld:
			st.characters[c]["location"] = ""
			st.characters[c]["position"] = door.duplicate()
		if str(st.characters[c].get("home", "")) == bld:
			st.characters[c]["home"] = ""
	var type := str(st.buildings[bld]["type"])
	st.buildings.erase(bld)
	if plot != "":
		st.parcels[plot] = {"state": "lot", "building": ""}
	if refund > 0:
		Money.change(sim, fam, refund, Money.PROPERTY, "demolish", bld)
	Chronicle.add(st, "ai_closed", {"family": fam, "building": bld, "type": type})
	sim.events.append({"type": "building_demolished", "building": bld, "plot": plot, "family": fam, "actor": "",
		"building_type": type, "refund": refund})
	if OS.is_debug_build():
		print("[Bankruptcy] %s: nadie compró %s; lo derriba (le devuelven %d)" % [fam, bld, refund])
	_reset(m)
	_after(sim, fam, today)


## After a sale or a closure: with a workshop left, normal; with none, «venida a menos» (Q9 b).
static func _after(sim: Sim, fam: String, today: int) -> void:
	if workshop_of(sim, fam) != "":
		return
	fall(sim, fam, today)


## «Venida a menos»: the family keeps title and reputation; its adults get a rank (by their craft) and can be hired by
## anybody; those without a roof lodge in the emptiest house of the town; it will put up a workshop again (after_sale
## fate rebuilds: Construction).
static func fall(sim: Sim, fam: String, today: int) -> void:
	var st := sim.state
	var f: Dictionary = st.families[fam]
	f["fallen"] = {"day": today}
	var after: Dictionary = f.get("after_sale", {}) if f.get("after_sale") is Dictionary else {}
	after["fate"] = "rebuilds"
	after["day"] = today
	if str(after.get("type", "")) == "":
		after["type"] = str(mem(sim, fam).get("type", ""))
	f["after_sale"] = after
	var cap := int(sim.catalog.town.get("population", {}).get("house_capacity", 5))
	for c: Variant in f.get("members", []):
		var ch: Dictionary = st.characters.get(str(c), {})
		if ch.is_empty() or not bool(ch.get("alive", true)):
			continue
		if str(ch.get("rank", "")) == "" and Kin.is_adult(sim, str(c)):
			ch["rank"] = "journeyman" if int(ch.get("stats", {}).get("craft", 0)) >= 4 else "apprentice"
		if str(ch.get("home", "")) == "" or not st.buildings.has(str(ch.get("home", ""))):
			var house := Population._emptiest_house(sim, cap)
			if house != "":
				ch["home"] = house
	Chronicle.add(st, "ai_fallen", {"family": fam})
	sim.events.append({"type": "ai_fallen", "family": fam})
	for h: String in st.families:
		if Plots.is_human(sim, h):
			Notices.add(sim, h, Notices.INFO, "notice.plots.ai_fallen", {"family": str(f.get("name", fam))})
	if OS.is_debug_build():
		print("[Bankruptcy] %s queda venida a menos: sin negocio, sus miembros se pueden contratar" % fam)


## Whether a fallen family has a workshop again (it is no longer fallen).
static func rose(sim: Sim, fam: String) -> void:
	var f: Dictionary = sim.state.families[fam]
	if f.has("fallen") and workshop_of(sim, fam) != "":
		f.erase("fallen")


static func sale_price(sim: Sim, bld: String) -> int:
	var b: Dictionary = sim.state.buildings[bld]
	var value := float(Plots.build_cost(sim, str(b["type"])))
	for u: Variant in b.get("upgrades", []):
		value += float(sim.catalog.upgrade(str(u)).get("cost", {}).get("gold", 0))
	return roundi(value * float(cfg(sim).get("sale_share", 0.8)))


static func _reset(m: Dictionary) -> void:
	m["stage"] = NORMAL
	m["since"] = -1
	m["building"] = ""


## The least efficient employee of `bld` goes (austerity), if it has any.
static func _let_go_worst(sim: Sim, bld: String) -> void:
	var worst := ""
	var worst_e := INF
	for e: String in Staff.employees_of(sim.state, bld):
		var eff := Staff.efficiency(sim, e)
		if eff < worst_e:
			worst_e = eff
			worst = e
	if worst != "":
		sim.state.characters[worst]["job"]["end_day"] = Clock.day(int(sim.state.clock["minute"]))
		sim.events.append({"type": "ai_let_go", "building": bld, "employee": worst})
