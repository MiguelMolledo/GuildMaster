class_name Herds
extends RefCounted
## The livestock of a farm (H12 Patrón, docs/gdd/04d_otras_clases.md 4.22.4.2): the animals are items in the storage
## of a building with a pen (a zone of kind "pen"); nothing apart: they are bought, sold and carried like any item, and
## the pen counts them. Animals: data/animals/<id>.json (the item of the same id), figures [balance].
##
## Each dawn (in building id order, animals in id order): an animal that eats this season (feed[season] = {item, qty}
## per head) eats from the storage; if there is not enough for the whole herd of that kind, the pen goes unfed
## (unfed_days += 1, nothing produced and no breeding that day; at unfed_days >= starve_days the least valuable animal
## dies, urgent notice, and the count goes on); fed, unfed_days = 0. Then every animal produces (produce = {item, qty})
## into the storage (what does not fit is lost, notice); the ones that breed add per_pair young per pair every
## every_days days, up to the pen's capacity (data/buildings/<type>.json "pen_capacity" + the pen_capacity upgrades).
## A notice one day before the feed runs out in winter.
## State: buildings[bld].pen = {unfed_days, breed: {animal: days since the last litter}} (read with defaults: no save
## version).

const PEN: String = "pen"


## Whether `bld` has a pen.
static func has_pen(sim: Sim, bld: String) -> bool:
	var b: Dictionary = sim.state.buildings.get(bld, {})
	for z: String in (b.get("zones", {}) as Dictionary).keys():
		if Upgrades.zone_kind(sim, bld, z) == PEN:
			return true
	return false


## How many animals fit in the pen of `bld`.
static func capacity(sim: Sim, bld: String) -> int:
	var t := str(sim.state.buildings.get(bld, {}).get("type", ""))
	return int(sim.catalog.buildings().get(t, {}).get("pen_capacity", 0)) + roundi(Upgrades.amount(sim, bld, "pen_capacity"))


## {animal id: count} in the storage of `bld`.
static func herd(sim: Sim, bld: String) -> Dictionary:
	var out := {}
	var inv: Dictionary = sim.state.buildings.get(bld, {}).get("inventory", {})
	for a: String in _sorted(sim.catalog.animals()):
		var n := Inventory.count(inv, a)
		if n > 0:
			out[a] = n
	return out


static func head_count(sim: Sim, bld: String) -> int:
	var n := 0
	var h := herd(sim, bld)
	for a: Variant in h:
		n += int(h[a])
	return n


static func _mem(st: WorldState, bld: String) -> Dictionary:
	var b: Dictionary = st.buildings[bld]
	if not b.get("pen") is Dictionary:
		b["pen"] = {"unfed_days": 0, "breed": {}}
	var p: Dictionary = b["pen"]
	if not p.get("breed") is Dictionary:
		p["breed"] = {}
	return p


## What the herd of `bld` eats per day in `season`: {item: qty}.
static func feed_per_day(sim: Sim, bld: String, season: String) -> Dictionary:
	var out := {}
	var h := herd(sim, bld)
	for a: String in _sorted(h):
		var f: Variant = sim.catalog.animals()[a].get("feed", {}).get(season)
		if f is Dictionary and int(f.get("qty", 0)) > 0:
			var it := str(f["item"])
			out[it] = int(out.get(it, 0)) + int(f["qty"]) * int(h[a])
	return out


## The days of winter feed in the storage of `bld` (the scarcest feed item; -1 if the herd eats nothing in winter).
static func winter_feed_days(sim: Sim, bld: String) -> int:
	var need := feed_per_day(sim, bld, "winter")
	if need.is_empty():
		return -1
	var inv: Dictionary = sim.state.buildings[bld]["inventory"]
	var days := 1 << 30
	for it: String in need:
		days = mini(days, Inventory.count(inv, it) / maxi(1, int(need[it])))
	return days


# --- Dawn ------------------------------------------------------------------------------------------------------------

static func step(sim: Sim) -> void:
	if not Ledger.is_dawn(sim):
		return
	var st := sim.state
	var ids: Array = st.buildings.keys()
	ids.sort()
	for bld: String in ids:
		if has_pen(sim, bld) and head_count(sim, bld) > 0:
			_dawn(sim, bld)


static func _dawn(sim: Sim, bld: String) -> void:
	var st := sim.state
	var b: Dictionary = st.buildings[bld]
	var inv: Dictionary = b["inventory"]
	var fam := str(b.get("owner", ""))
	var season := Clock.season(int(st.clock["minute"]), sim.catalog.time)
	var pen := _mem(st, bld)
	var need := feed_per_day(sim, bld, season)
	var fed := true
	for it: String in need:
		if Inventory.count(inv, it) < int(need[it]):
			fed = false
	if fed:
		for it: String in need:
			_take(inv, it, int(need[it]))
		pen["unfed_days"] = 0
		if not need.is_empty():
			sim.events.append({"type": "herd_fed", "building": bld, "family": fam, "feed": need})
	else:
		pen["unfed_days"] = int(pen.get("unfed_days", 0)) + 1
		sim.events.append({"type": "herd_unfed", "building": bld, "family": fam, "days": int(pen["unfed_days"])})
		if int(pen["unfed_days"]) >= int(_rules(sim).get("starve_days", 2)):
			_starve(sim, bld, fam)
		else:
			var it0: String = need.keys()[0] if not need.is_empty() else "wheat"
			_notice(sim, fam, Notices.URGENT, "notice.herd_hungry", {"building": bld, "item": it0,
				"qty": int(need.get(it0, 0))}, bld)
		if OS.is_debug_build():
			print("[Herds] %s: el ganado no come hoy (%s, días sin comer=%d)" % [bld, str(need), int(pen["unfed_days"])])
		return
	_produce(sim, bld, fam)
	_breed(sim, bld, fam, pen)
	_feed_warning(sim, bld, fam, season)


static func _produce(sim: Sim, bld: String, fam: String) -> void:
	var inv: Dictionary = sim.state.buildings[bld]["inventory"]
	var h := herd(sim, bld)
	var made := {}
	var lost := {}
	for a: String in _sorted(h):
		var p: Variant = sim.catalog.animals()[a].get("produce")
		if not p is Dictionary or int(p.get("qty", 0)) <= 0:
			continue
		var it := str(p["item"])
		var qty := int(p["qty"]) * int(h[a])
		var fit := Inventory.fit_count(inv, sim.catalog, it, Inventory.NORMAL, qty)
		if fit > 0:
			Inventory.add(inv, sim.catalog, it, Inventory.NORMAL, fit)
			made[it] = int(made.get(it, 0)) + fit
		if fit < qty:
			lost[it] = int(lost.get(it, 0)) + qty - fit
	if not made.is_empty():
		sim.events.append({"type": "herd_produced", "building": bld, "family": fam, "items": made})
	if not lost.is_empty():
		sim.events.append({"type": "herd_lost", "building": bld, "family": fam, "items": lost})
		var it1: String = lost.keys()[0]
		_notice(sim, fam, Notices.WARNING, "notice.herd_lost", {"building": bld, "item": it1, "qty": int(lost[it1])}, bld)
	if OS.is_debug_build():
		print("[Herds] %s produce %s (perdido=%s)" % [bld, str(made), str(lost)])


static func _breed(sim: Sim, bld: String, fam: String, pen: Dictionary) -> void:
	var inv: Dictionary = sim.state.buildings[bld]["inventory"]
	var breed: Dictionary = pen["breed"]
	for a: String in _sorted(sim.catalog.animals()):
		var rule: Variant = sim.catalog.animals()[a].get("breed")
		var n := Inventory.count(inv, a)
		if not rule is Dictionary or n < 2:
			breed.erase(a)
			continue
		breed[a] = int(breed.get(a, 0)) + 1
		if int(breed[a]) < int(rule.get("every_days", 2)):
			continue
		breed[a] = 0
		var room := capacity(sim, bld) - head_count(sim, bld)
		var young := mini(int(n / 2) * int(rule.get("per_pair", 1)), room)
		young = mini(young, Inventory.fit_count(inv, sim.catalog, a, Inventory.NORMAL, young))
		if young <= 0:
			continue
		Inventory.add(inv, sim.catalog, a, Inventory.NORMAL, young)
		sim.events.append({"type": "herd_born", "building": bld, "family": fam, "animal": a, "qty": young})
		if OS.is_debug_build():
			print("[Herds] %s: nacen %d de %s (ahora %d, corral %d/%d)" % [bld, young, a, Inventory.count(inv, a),
				head_count(sim, bld), capacity(sim, bld)])


## The least valuable animal dies (base price, then id); the unfed count goes on.
static func _starve(sim: Sim, bld: String, fam: String) -> void:
	var inv: Dictionary = sim.state.buildings[bld]["inventory"]
	var pick := ""
	for a: String in _sorted(herd(sim, bld)):
		if pick == "" or int(sim.catalog.item(a).get("base_price", 0)) < int(sim.catalog.item(pick).get("base_price", 0)):
			pick = a
	if pick == "":
		return
	_take(inv, pick, 1)
	sim.events.append({"type": "animal_died", "building": bld, "family": fam, "animal": pick, "reason": "hunger"})
	_notice(sim, fam, Notices.URGENT, "notice.animal_starved", {"building": bld, "item": pick}, bld)
	if OS.is_debug_build():
		print("[Herds] %s: muere de hambre un %s" % [bld, pick])


## The evening before the feed runs out (winter, or the day before it starts): urgent notice.
static func _feed_warning(sim: Sim, bld: String, fam: String, season: String) -> void:
	var time := sim.catalog.time
	var tomorrow := Clock.season((Clock.day(int(sim.state.clock["minute"])) + 1) * Clock.MINUTES_PER_DAY, time)
	if tomorrow != "winter" and season != "winter":
		return
	var need := feed_per_day(sim, bld, tomorrow)
	var inv: Dictionary = sim.state.buildings[bld]["inventory"]
	for it: String in need:
		if Inventory.count(inv, it) < int(need[it]):
			_notice(sim, fam, Notices.URGENT, "notice.herd_feed_low", {"building": bld, "item": it, "qty": int(need[it])},
				bld)
			return


static func _take(inv: Dictionary, item: String, qty: int) -> void:
	var left := qty
	for q: int in Inventory.QUALITIES:
		var n := mini(left, Inventory.count(inv, item, q))
		if n > 0:
			Inventory.remove(inv, item, q, n)
			left -= n
		if left <= 0:
			return


static func _rules(sim: Sim) -> Dictionary:
	return sim.catalog.market.get("livestock", {})


static func _notice(sim: Sim, fam: String, sev: String, key: String, params: Dictionary, target: String) -> void:
	if fam != "" and sim.state.families.has(fam):
		Notices.add(sim, fam, sev, key, params, target)


# --- View ------------------------------------------------------------------------------------------------------------

## The pen for the UI and the bots: {herd {animal: n}, heads, capacity, unfed_days, winter_feed_days, need_today
## {item: qty}, young_in {animal: days to the next litter}}.
static func view(sim: Sim, bld: String) -> Dictionary:
	var pen: Dictionary = sim.state.buildings.get(bld, {}).get("pen", {}) if sim.state.buildings.get(bld, {}).get("pen") is Dictionary else {}
	var season := Clock.season(int(sim.state.clock["minute"]), sim.catalog.time)
	var young := {}
	var h := herd(sim, bld)
	for a: String in _sorted(h):
		var rule: Variant = sim.catalog.animals()[a].get("breed")
		if rule is Dictionary and int(h[a]) >= 2:
			young[a] = int(rule.get("every_days", 2)) - int(pen.get("breed", {}).get(a, 0))
	return {"herd": h, "heads": head_count(sim, bld), "capacity": capacity(sim, bld),
		"unfed_days": int(pen.get("unfed_days", 0)), "winter_feed_days": winter_feed_days(sim, bld),
		"need_today": feed_per_day(sim, bld, season), "young_in": young}


static func _sorted(d: Dictionary) -> Array:
	var k: Array = d.keys()
	k.sort()
	return k
