class_name Plots
extends RefCounted
## H6 · parcelas y construcción (docs/gdd/04_diseno_de_juego.md §4.9, §4.9.1; data/construction.json [balance]).
##
## The plots are the map's (data/maps/<map>.json "plots", made by tools/city/plots.py): a free lot (lot), a ruin
## (ruin) or the footprint of a business (business: the building whose origin is the plot's). Their state in the game
## lives in state.parcels, only what changed: {plot_id: {"state": "lot" | "ruin" | "built", "building": bld_id}}.
## A plot with no entry is as the map says, so an old save and a new game read the same (no save version).
##
## Orders (management: the head gives them from the build mode, no walking):
##   {"type": "build", "actor", "plot", "building_type"}   a lot: buy it and build; a ruin: buy and restore it
##   {"type": "demolish", "actor", "building"}              own, no employees, not the family's only home
##   {"type": "convert_building", "actor", "building", "building_type"}  another of its zone that fits, its upgrades lost
##   buy_building (Inn.order_buy_building) on a building of another family: Plots.order_buy_from (4.9 formula)
## A new building is under works (state "construction", construction {kind, start, end, by}): it does not produce, pays
## no upkeep, and Construction.step finishes it. The title limit (Titles.max_buildings) counts the family's buildings
## but the types of construction.json not_counted (the tavern, O-V11). The valve (4.9) keeps valve.min_free free
## plots of each zone for the AI families; the player may take the last one.

const ZONES: Array[String] = ["production", "housing", "rustic"]


static func rules(sim: Sim) -> Dictionary:
	return sim.catalog.construction


static func map_plots(sim: Sim) -> Array:
	return (sim.catalog.maps().get(sim.state.map_id, {}) as Dictionary).get("plots", []) as Array


## Every plot of the map with its state now: {id, zone, side, origin, size, front, location, kind (lot | ruin |
## building), building ("" or bld id), owner ("" or the building's owner), for_sale}. In the map's order.
static func all(sim: Sim) -> Array:
	var out: Array = []
	for p: Dictionary in map_plots(sim):
		out.append(_view(sim, p))
	return out


static func get_plot(sim: Sim, id: String) -> Dictionary:
	for p: Dictionary in map_plots(sim):
		if str(p.get("id", "")) == id:
			return _view(sim, p)
	return {}


static func _view(sim: Sim, p: Dictionary) -> Dictionary:
	var v := p.duplicate(true)
	var over: Dictionary = sim.state.parcels.get(str(p["id"]), {})
	var bld := ""
	var kind := str(p.get("state", "lot"))
	if not over.is_empty():
		kind = str(over.get("state", kind))
		bld = str(over.get("building", ""))
	elif kind == "business":
		bld = building_at(sim, p.get("origin", []))
	if bld != "" and not sim.state.buildings.has(bld):
		bld = ""
	if kind in ["business", "built"]:
		kind = "building" if bld != "" else "lot"
	v["kind"] = kind
	v["building"] = bld
	v["owner"] = str(sim.state.buildings[bld].get("owner", "")) if bld != "" else ""
	v["for_sale"] = bld != "" and (bool(sim.state.buildings[bld].get("for_sale", false)) or bool(p.get("for_sale", false)))
	return v


## The building whose origin is `origin` ("" if none).
static func building_at(sim: Sim, origin: Variant) -> String:
	if not origin is Array or (origin as Array).size() != 2:
		return ""
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		var o: Array = sim.state.buildings[b].get("origin", [])
		if o.size() == 2 and int(o[0]) == int(origin[0]) and int(o[1]) == int(origin[1]):
			return b
	return ""


## The plot a building stands on ("" if it is not on a plot of the map: the armory, the town hall...).
static func plot_of(sim: Sim, bld: String) -> String:
	for p: Dictionary in all(sim):
		if str(p["building"]) == bld:
			return str(p["id"])
	return ""


static func is_free(p: Dictionary) -> bool:
	return str(p.get("kind", "")) in ["lot", "ruin"]


## Free plots (lots and ruins) of `zone`.
static func free_count(sim: Sim, zone: String) -> int:
	var n := 0
	for p: Dictionary in all(sim):
		if str(p.get("zone", "")) == zone and is_free(p):
			n += 1
	return n


## The footprint `type` takes on plot `p`: as drawn or turned a quarter ([] if it does not fit).
static func footprint_on(sim: Sim, type: String, p: Dictionary) -> Array:
	var f: Array = sim.catalog.buildings().get(type, {}).get("footprint", [])
	var s: Array = p.get("size", [])
	if f.size() != 2 or s.size() != 2:
		return []
	if int(f[0]) <= int(s[0]) and int(f[1]) <= int(s[1]):
		return [int(f[0]), int(f[1])]
	if int(f[1]) <= int(s[0]) and int(f[0]) <= int(s[1]):
		return [int(f[1]), int(f[0])]
	return []


## The building types a family may raise on plot `p` (its zone, its size): workshops, services and houses; never the
## town's (government) ones. Sorted by id.
static func types_for(sim: Sim, p: Dictionary) -> Array:
	var out: Array = []
	var ids: Array = sim.catalog.buildings().keys()
	ids.sort()
	for t: String in ids:
		var def: Dictionary = sim.catalog.buildings()[t]
		if str(def.get("parcel_type", "")) != str(p.get("zone", "")) or bool(def.get("public", false)):
			continue
		if str(def.get("category", "")) not in ["workshop", "service", "residence"]:
			continue
		if build_cost(sim, t) <= 0 or footprint_on(sim, t, p).is_empty():
			continue
		out.append(t)
	return out


## What `type` costs to build from nothing (the house's figure is construction.json house_cost: its build_cost is 0).
static func build_cost(sim: Sim, type: String) -> int:
	var def: Dictionary = sim.catalog.buildings().get(type, {})
	if str(def.get("category", "")) == "residence":
		return int(rules(sim).get("house_cost", 0))
	return int(def.get("build_cost", 0))


static func _location_mult(sim: Sim, p: Dictionary) -> float:
	var lp: Dictionary = rules(sim).get("location_price", {})
	var lo := float(lp.get("min", 1.0))
	var hi := float(lp.get("max", 1.0))
	var m := lo + (hi - lo) * clampf(float(p.get("location", 0.5)), 0.0, 1.0)
	if str(p.get("side", "")) == "outside":
		m *= float(rules(sim).get("outside", 1.0))
	return m


## {price, days, kind}: what raising `type` on plot `p` costs and lasts. kind "build" on a lot (the lot and the works,
## by the plot's situation) or "restore" on a ruin (buy × cost + restore × cost, days × days_share).
static func quote(sim: Sim, p: Dictionary, type: String) -> Dictionary:
	var base := float(build_cost(sim, type)) * _location_mult(sim, p)
	var days := float(sim.catalog.buildings().get(type, {}).get("build_days", 1))
	if str(p.get("kind", "")) == "ruin":
		var r: Dictionary = rules(sim).get("ruin", {})
		return {"price": roundi(base * (float(r.get("buy", 0.3)) + float(r.get("restore", 0.5)))),
			"days": maxf(0.5, days * float(r.get("days_share", 0.5))), "kind": "restore"}
	return {"price": roundi(base), "days": days, "kind": "build"}


## The family's buildings that count for the title limit: all it owns but the not_counted types (the tavern, O-V11).
static func counted(sim: Sim, fam: String) -> int:
	var skip: Array = rules(sim).get("not_counted", [])
	var n := 0
	for b: String in sim.state.buildings:
		var bld: Dictionary = sim.state.buildings[b]
		if str(bld.get("owner", "")) == fam and not str(bld.get("type", "")) in skip:
			n += 1
	return n


## Whether `fam` may own one more building of `type` (its title's max_buildings; -1 = no limit).
static func room_for(sim: Sim, fam: String, type: String) -> bool:
	if str(type) in (rules(sim).get("not_counted", []) as Array):
		return true
	var cap := Titles.max_buildings(sim, fam)
	return cap < 0 or counted(sim, fam) < cap


## Whether the family is the player's (a human family): the valve does not stop it.
static func is_human(sim: Sim, fam: String) -> bool:
	return str(sim.state.families.get(fam, {}).get("controlled_by", "")) == "human"


## The valve (4.9): an AI family may take a free plot of `zone` only if min_free stay free after it.
static func valve_ok(sim: Sim, fam: String, zone: String) -> bool:
	if is_human(sim, fam):
		return true
	return free_count(sim, zone) - 1 >= int(rules(sim).get("valve", {}).get("min_free", 2))


## {"ok", "reason", "price", "days", "kind"} for `actor` raising `type` on plot `plot_id`. Reasons: unknown_actor,
## no_family, too_young, unknown_plot, plot_taken, wrong_type (zone, size or a town building), title_limit, valve,
## not_enough_gold.
static func can_build(sim: Sim, actor: String, plot_id: String, type: String) -> Dictionary:
	var st := sim.state
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var fam := str(st.characters[actor].get("family", ""))
	if fam == "" or not st.families.has(fam):
		return Orders.fail("no_family")
	if not Kin.is_adult(sim, actor):
		return Orders.fail("too_young")
	var p := get_plot(sim, plot_id)
	if p.is_empty():
		return Orders.fail("unknown_plot")
	if not is_free(p):
		return Orders.fail("plot_taken")
	if not type in types_for(sim, p):
		return Orders.fail("wrong_type")
	if not room_for(sim, fam, type):
		return Orders.fail("title_limit")
	if not valve_ok(sim, fam, str(p["zone"])):
		return Orders.fail("valve")
	var q := quote(sim, p, type)
	if not Money.can_pay(st, fam, int(q["price"])):
		var r := Orders.fail("not_enough_gold")
		r.merge(q)
		return r
	var ok := Orders.ok()
	ok.merge(q)
	return ok


## {"type": "build", "actor", "plot", "building_type"}.
static func order_build(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var plot_id := str(o.get("plot", ""))
	var type := str(o.get("building_type", ""))
	var r := can_build(sim, actor, plot_id, type)
	if not r["ok"]:
		return r
	var st := sim.state
	var fam := str(st.characters[actor]["family"])
	var p := get_plot(sim, plot_id)
	var price := int(r["price"])
	var bld := NewGame.make_building(st, sim.catalog, type, p["origin"], [int(p["front"][0]), int(p["front"][1])],
		fam, footprint_on(sim, type, p))
	Money.change(sim, fam, -price, Money.PROPERTY, str(r["kind"]), bld, actor)
	var now := int(st.clock["minute"])
	var end := now + roundi(float(r["days"]) * Clock.MINUTES_PER_DAY)
	st.buildings[bld]["state"] = "construction"
	st.buildings[bld]["construction"] = {"kind": str(r["kind"]), "start": now, "end": end, "by": actor, "plot": plot_id}
	st.parcels[plot_id] = {"state": "built", "building": bld}
	Chronicle.add(st, "building_started", {"family": fam, "building": bld, "type": type, "plot": plot_id,
		"kind": str(r["kind"]), "price": price})
	sim.events.append({"type": "construction_started", "building": bld, "plot": plot_id, "family": fam, "actor": actor,
		"building_type": type, "kind": str(r["kind"]), "price": price, "end": end})
	if OS.is_debug_build():
		print("[Plots] %s %s %s en %s por %d (hasta el minuto %d)" % [fam, "restaura" if str(r["kind"]) == "restore"
			else "construye", type, plot_id, price, end])
	return Orders.ok()


## {"ok", "reason", "refund"} for `actor` pulling down `bld`. Reasons: unknown_actor, unknown_building, not_yours,
## has_employees, someone_inside, only_home, under_construction.
static func can_demolish(sim: Sim, actor: String, bld: String) -> Dictionary:
	var st := sim.state
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	if not st.buildings.has(bld):
		return Orders.fail("unknown_building")
	var fam := str(st.characters[actor].get("family", ""))
	var b: Dictionary = st.buildings[bld]
	if fam == "" or str(b.get("owner", "")) != fam:
		return Orders.fail("not_yours")
	if plot_of(sim, bld) == "":
		return Orders.fail("not_on_plot")
	if str(b.get("state", "")) == "construction":
		return Orders.fail("under_construction")
	if not Staff.employees_of(st, bld).is_empty():
		return Orders.fail("has_employees")
	for c: String in st.characters:
		if str(st.characters[c].get("location", "")) == bld:
			return Orders.fail("someone_inside")
	if _only_home(sim, fam, bld):
		return Orders.fail("only_home")
	var r := Orders.ok()
	r["refund"] = roundi(float(build_cost(sim, str(b["type"]))) * float(rules(sim).get("demolish_refund", 0.4)))
	return r


## Whether `bld` gives the family a roof (it includes housing or somebody's home is it) and no other building of the
## family does (decided 2026-11-02: the only house cannot be pulled down).
static func _only_home(sim: Sim, fam: String, bld: String) -> bool:
	if not _houses(sim, bld):
		return false
	for b: String in sim.state.buildings:
		if b != bld and str(sim.state.buildings[b].get("owner", "")) == fam and _houses(sim, b):
			return false
	return true


static func _houses(sim: Sim, bld: String) -> bool:
	var t := str(sim.state.buildings[bld].get("type", ""))
	if bool(sim.catalog.buildings().get(t, {}).get("includes_housing", false)):
		return true
	for c: String in sim.state.characters:
		if str(sim.state.characters[c].get("home", "")) == bld:
			return true
	return false


## {"type": "demolish", "actor", "building"}: instant; refund × cost back, the upgrades and the stock are lost, the plot
## is a free lot again. The neighbours who like the family take it badly (4.9).
static func order_demolish(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var r := can_demolish(sim, actor, bld)
	if not r["ok"]:
		return r
	var st := sim.state
	var fam := str(st.characters[actor]["family"])
	var plot_id := plot_of(sim, bld)
	var type := str(st.buildings[bld]["type"])
	if int(r["refund"]) > 0:
		Money.change(sim, fam, int(r["refund"]), Money.PROPERTY, "demolish", bld, actor)
	for c: String in st.characters:
		if str(st.characters[c].get("home", "")) == bld:
			st.characters[c]["home"] = ""
	st.buildings.erase(bld)
	st.parcels[plot_id] = {"state": "lot", "building": ""}
	Reputation.change(sim, fam, int(rules(sim).get("demolish_reputation", -2)), "demolish")
	Chronicle.add(st, "building_demolished", {"family": fam, "building": bld, "type": type, "plot": plot_id})
	sim.events.append({"type": "building_demolished", "building": bld, "plot": plot_id, "family": fam, "actor": actor,
		"building_type": type, "refund": int(r["refund"])})
	if OS.is_debug_build():
		print("[Plots] %s derriba %s (%s) en %s: le devuelven %d" % [fam, bld, type, plot_id, int(r["refund"])])
	return Orders.ok()


## {"ok", "reason", "price", "days"} for `actor` converting own `bld` to `type` (same zone, fits its plot). Reasons:
## those of can_demolish's ownership, same_type, wrong_type, title_limit (a tavern into a counted type), not_enough_gold.
static func can_convert(sim: Sim, actor: String, bld: String, type: String) -> Dictionary:
	var st := sim.state
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	if not st.buildings.has(bld):
		return Orders.fail("unknown_building")
	var fam := str(st.characters[actor].get("family", ""))
	var b: Dictionary = st.buildings[bld]
	if fam == "" or str(b.get("owner", "")) != fam:
		return Orders.fail("not_yours")
	if str(b.get("state", "")) == "construction":
		return Orders.fail("under_construction")
	if str(b.get("type", "")) == type:
		return Orders.fail("same_type")
	var plot_id := plot_of(sim, bld)
	if plot_id == "":
		return Orders.fail("not_on_plot")
	var p := get_plot(sim, plot_id)
	if not type in types_for(sim, p):
		return Orders.fail("wrong_type")
	var skip: Array = rules(sim).get("not_counted", [])
	if str(b["type"]) in skip and not type in skip and not room_for(sim, fam, type):
		return Orders.fail("title_limit")
	if not Staff.employees_of(st, bld).is_empty():
		return Orders.fail("has_employees")
	var cv: Dictionary = rules(sim).get("convert", {})
	var price := roundi(float(build_cost(sim, type)) * float(cv.get("share", 0.4)))
	if not Money.can_pay(st, fam, price):
		var f := Orders.fail("not_enough_gold")
		f["price"] = price
		return f
	var r := Orders.ok()
	r["price"] = price
	r["days"] = float(cv.get("days", 1))
	return r


## {"type": "convert_building", "actor", "building", "building_type"}: works of convert.days; the building keeps its
## id, owner, stock (as far as it fits) and plot; its stations and upgrades are the new type's (none).
static func order_convert(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var type := str(o.get("building_type", ""))
	var r := can_convert(sim, actor, bld, type)
	if not r["ok"]:
		return r
	var st := sim.state
	var fam := str(st.characters[actor]["family"])
	var b: Dictionary = st.buildings[bld]
	var old := str(b["type"])
	Money.change(sim, fam, -int(r["price"]), Money.PROPERTY, "convert", bld, actor)
	for c: String in st.characters:
		if str(st.characters[c].get("location", "")) == bld:
			st.characters[c]["location"] = ""
			st.characters[c]["position"] = (b.get("door", [0, 0]) as Array).duplicate()
	var fresh := NewGame.building_fields(sim.catalog, type)
	for k: String in fresh:
		if k != "inventory":
			b[k] = fresh[k]
	b["type"] = type
	b["inventory"]["capacity"] = (fresh["inventory"] as Dictionary).get("capacity", b["inventory"].get("capacity", 0))
	var now := int(st.clock["minute"])
	b["state"] = "construction"
	b["construction"] = {"kind": "convert", "start": now, "end": now + roundi(float(r["days"]) * Clock.MINUTES_PER_DAY),
		"by": actor, "plot": plot_of(sim, bld), "from": old}
	Chronicle.add(st, "building_converted", {"family": fam, "building": bld, "from": old, "type": type})
	sim.events.append({"type": "construction_started", "building": bld, "plot": plot_of(sim, bld), "family": fam,
		"actor": actor, "building_type": type, "kind": "convert", "price": int(r["price"]), "from": old,
		"end": int(b["construction"]["end"])})
	if OS.is_debug_build():
		print("[Plots] %s reconvierte %s de %s a %s por %d" % [fam, bld, old, type, int(r["price"])])
	return Orders.ok()


## --- buying a business of a NPC (4.9) ----------------------------------------------------------------------------

## {"ok", "reason", "price", "seller"}: whether `actor` may buy `bld` from the family that has it (not the player's:
## a human family sells nothing it did not put up for sale). price = (cost + its upgrades' gold) × the relation's
## modifier (from mod_best at +60 to mod_worst at -60) × the plot's situation. Reasons: unknown_actor, no_family,
## too_young, unknown_building, own_building, not_for_sale (a town building, a human family's), under_construction,
## refuses (the seller's head dislikes the buyer below refuse_below), title_limit, not_enough_gold.
static func can_buy_from(sim: Sim, actor: String, bld: String) -> Dictionary:
	var st := sim.state
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var fam := str(st.characters[actor].get("family", ""))
	if fam == "" or not st.families.has(fam):
		return Orders.fail("no_family")
	if not Kin.is_adult(sim, actor):
		return Orders.fail("too_young")
	if not st.buildings.has(bld):
		return Orders.fail("unknown_building")
	var b: Dictionary = st.buildings[bld]
	var seller := str(b.get("owner", ""))
	if seller == fam:
		return Orders.fail("own_building")
	if seller == "" or not st.families.has(seller) or is_human(sim, seller) or plot_of(sim, bld) == "":
		return Orders.fail("not_for_sale")
	if str(b.get("state", "")) == "construction":
		return Orders.fail("under_construction")
	var rel := Emotions.relation(st, Kin.head(st, seller), actor)
	var ns: Dictionary = rules(sim).get("npc_sale", {})
	if rel < int(ns.get("refuse_below", -40)):
		var no := Orders.fail("refuses")
		no["relation"] = rel
		return no
	if not room_for(sim, fam, str(b["type"])):
		return Orders.fail("title_limit")
	var price := npc_price(sim, bld, rel)
	if not Money.can_pay(st, fam, price):
		var f := Orders.fail("not_enough_gold")
		f["price"] = price
		return f
	var r := Orders.ok()
	r["price"] = price
	r["seller"] = seller
	r["relation"] = rel
	return r


static func npc_price(sim: Sim, bld: String, rel: int) -> int:
	var b: Dictionary = sim.state.buildings[bld]
	var value := float(build_cost(sim, str(b["type"])))
	for u: Variant in b.get("upgrades", []):
		value += float(sim.catalog.upgrade(str(u)).get("cost", {}).get("gold", 0))
	var ns: Dictionary = rules(sim).get("npc_sale", {})
	var t := clampf((float(rel) + 60.0) / 120.0, 0.0, 1.0)  # 0 at -60 or worse, 1 at +60 or better
	var mod := lerpf(float(ns.get("mod_worst", 1.5)), float(ns.get("mod_best", 0.8)), t)
	var p := get_plot(sim, plot_of(sim, bld))
	return roundi(value * mod * (_location_mult(sim, p) if not p.is_empty() else 1.0))


## The purchase: the gold goes to the seller, its people leave the building (its employees go with it, decided
## 2026-11-02), and the seller's family, by the relation (after_sale.fate): stays in the town without a business and
## does not compete again (stays, from stay_from; GDD: «acepta trabajar para ti», [provisional]: the members of an AI
## family cannot be hired yet), puts up a business on another plot (rebuilds, from rebuild_from: its family's
## construction looks for a plot first) or is gone (leaves: it builds nothing more).
static func order_buy_from(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var r := can_buy_from(sim, actor, bld)
	if not r["ok"]:
		return r
	var st := sim.state
	var fam := str(st.characters[actor]["family"])
	var seller := str(r["seller"])
	var price := int(r["price"])
	var b: Dictionary = st.buildings[bld]
	Money.change(sim, fam, -price, Money.PROPERTY, "buy_building", bld, actor)
	Money.change(sim, seller, price, Money.PROPERTY, "sell_building", bld)
	for e: String in Staff.employees_of(st, bld):
		st.characters[e]["job"] = null
	for c: String in st.characters:
		if str(st.characters[c].get("location", "")) == bld:
			st.characters[c]["location"] = ""
			st.characters[c]["position"] = (b.get("door", [0, 0]) as Array).duplicate()
		if str(st.characters[c].get("home", "")) == bld and str(st.characters[c].get("family", "")) == seller:
			st.characters[c]["home"] = ""
	b["owner"] = fam
	b.erase("for_sale")
	b["queue"] = {"entries": [], "loop": false, "paused": false}
	var after: Dictionary = rules(sim).get("npc_sale", {}).get("after", {})
	var rel := int(r["relation"])
	var fate := "leaves"
	if rel >= int(after.get("stay_from", 20)):
		fate = "stays"
	elif rel >= int(after.get("rebuild_from", -20)):
		fate = "rebuilds"
	var fs: Dictionary = st.families[seller]
	fs["after_sale"] = {"fate": fate, "day": Clock.day(int(st.clock["minute"])), "building": bld, "buyer": fam,
		"type": str(b.get("type", ""))}
	Chronicle.add(st, "building_bought", {"family": fam, "building": bld, "type": str(b.get("type", "")), "price": price,
		"seller": seller, "fate": fate})
	sim.events.append({"type": "building_bought", "building": bld, "family": fam, "actor": actor, "price": price,
		"seller": seller, "fate": fate})
	Notices.add(sim, seller, Notices.INFO, "notice.plots.sold",
		{"building": bld, "price": price}, bld)
	if OS.is_debug_build():
		print("[Plots] %s compra %s (%s) a %s por %d (relación %d: %s)" % [fam, bld, b.get("type", ""), seller, price,
			rel, fate])
	return Orders.ok()
