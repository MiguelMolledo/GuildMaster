class_name Clientele
extends RefCounted
## The clientele of the countryside (docs/gdd/04g_interiores.md 4.6.5.7): people of the villages around, passers-by and
## travellers who come to a shop's counter because of its fame, not because a townsperson needs something. They are
## not characters (they do not live in the town, eat or sleep in it): a record per customer under
## state.town.clientele[bld] = {next_at, seq, waiting: [{id, item, since, served_at}]}. Their gold comes from outside
## (P4, 4.19); what is balanced is how many come and how much they accept to pay:
##
##   per_day(b)  = base(type) × fame(b) × season × festival × share(competition)
##   share(b)    = appeal(b) / (Σ appeal of the shops of its type + no_go)            (4.22.3.2)
##   appeal(b)   = (1 / price_multiplier(b)) ^ elasticity × (1 + min(reputation / 1000, rep_cap)) × (1 + customer_bonus(b))
##   max_price   = base_price(item) × quality_mult × (1 + fame(b) × fame_price) × taste
##
## fame(b) is 1 until the fame of a building is defined (only the tavern has one, 4.27; pending for the shops). The
## reputation of the family is inside appeal (not twice). Figures: data/town.json counter.clientele [balance], and the
## provider choice's of data/services.json (elasticity, no_go, reputation cap and divisor), shared with the inn. Off
## by default (enabled false): the targets of today run without it, like the living town (_no_life); measure it with
## --set=town.counter.clientele.enabled=true. Served by the counter's server like the townsfolk (Counter.server_of),
## after serve_minutes, gone after patience_minutes. Called by Counter.step once per minute.

static var _open_minutes: Dictionary = {}   # season -> minutes of the day the counter is open


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.town.get("counter", {}).get("clientele", {})


static func enabled(sim: Sim) -> bool:
	return bool(cfg(sim).get("enabled", false))


## The countryside customers waiting at `bld` now: [{id, item, since, served_at}] (the view draws them inside).
static func waiting(st: WorldState, bld: String) -> Array:
	var c: Variant = st.town.get("clientele", {}).get(bld)
	return (c as Dictionary).get("waiting", []) if c is Dictionary else []


## Once per minute, from Counter.step (`open`: the counter phase; `sells`: Counter._sells for each building).
static func step(sim: Sim, now: int, open: bool, sellers: Array) -> void:
	if not enabled(sim):
		return
	var st := sim.state
	if not st.town.has("clientele"):
		st.town["clientele"] = {}
	var all: Dictionary = st.town["clientele"]
	for bld: String in sellers:
		if not all.has(bld):
			all[bld] = {"next_at": -1, "seq": 0, "waiting": []}
		var c: Dictionary = all[bld]
		if not open:
			for w: Dictionary in (c["waiting"] as Array).duplicate():
				_leave(sim, bld, w, "closed")
			c["next_at"] = -1
			continue
		if int(c["next_at"]) < 0:
			c["next_at"] = now + _interval(sim, bld, now)
		if now >= int(c["next_at"]):
			c["next_at"] = now + _interval(sim, bld, now)
			_arrive(sim, bld, now)
		_serve(sim, bld, now)
	for bld: String in all.keys():
		if not sellers.has(bld):
			for w: Dictionary in (all[bld]["waiting"] as Array).duplicate():
				_leave(sim, bld, w, "closed")
			all.erase(bld)


## How many come a day to `bld` (the formula above).
static func per_day(sim: Sim, bld: String) -> float:
	var k := cfg(sim)
	var type := str(sim.state.buildings[bld].get("type", ""))
	var base := float((k.get("base_per_day", {}) as Dictionary).get(type, 0.0))
	if base <= 0.0:
		return 0.0
	var season := Clock.season(int(sim.state.clock["minute"]), sim.catalog.time)
	var season_mult := float(sim.catalog.seasons.get("customers", {}).get(season, 1.0))
	return base * fame(sim, bld) * season_mult * WorldEvents.customers_mult(sim) * share(sim, bld)


## fame(b): 1 until the fame of a shop is defined (4.6.5.7; only the tavern has one, 4.27).
static func fame(_sim: Sim, _bld: String) -> float:
	return 1.0


## The share of the countryside clientele of its trade that goes to `bld` (4.22.3.2).
static func share(sim: Sim, bld: String) -> float:
	var type := str(sim.state.buildings[bld].get("type", ""))
	var total := 0.0
	var mine := appeal(sim, bld)
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for id: String in ids:
		if str(sim.state.buildings[id].get("type", "")) == type and Counter.sells(sim, id):
			total += appeal(sim, id)
	return mine / maxf(0.0001, total + float(sim.catalog.services.get("no_go", 0.5)))


## The provider's appeal of 4.22.3.2 with the figures of data/services.json (the same as InnClientele.provider_share).
static func appeal(sim: Sim, bld: String) -> float:
	var sv: Dictionary = sim.catalog.services
	var fam := str(sim.state.buildings[bld].get("owner", ""))
	var rep := float(sim.state.families.get(fam, {}).get("reputation", 0))
	var price := maxf(0.1, Upgrades.mult(sim, bld, "price_multiplier"))
	return pow(1.0 / price, float(sv.get("elasticity", 1.5))) \
		* (1.0 + minf(rep / float(sv.get("reputation_divisor", 1000)), float(sv.get("reputation_cap", 0.3)))) \
		* (1.0 + Upgrades.amount(sim, bld, "customer_bonus"))


## The most a countryside customer pays for `item` of `quality` at `bld`.
static func max_price(sim: Sim, bld: String, item: String, quality: int) -> int:
	var k := cfg(sim)
	var qm: Array = sim.catalog.market.get("quality_mult", [1.0])
	var base := float(sim.catalog.item(item).get("base_price", 1)) * float(qm[clampi(quality, 0, qm.size() - 1)])
	return roundi(base * (1.0 + fame(sim, bld) * float(k.get("fame_price", 0.1))) * float(k.get("taste", 1.0)))


## Minutes until the next one: the day's open minutes over per_day, ×[0.5, 1.5] by its own random stream.
static func _interval(sim: Sim, bld: String, now: int) -> int:
	var n := per_day(sim, bld)
	if n <= 0.0:
		return 1440
	var mins := float(open_minutes(sim)) / n
	var f := float(Kin.randi_range(sim.state, "cmc|next|%s|%d" % [bld, now], 50, 150)) / 100.0
	return maxi(5, roundi(mins * f))


static func open_minutes(sim: Sim) -> int:
	var season := Clock.season(int(sim.state.clock["minute"]), sim.catalog.time)
	if not _open_minutes.has(season):
		var phases: Array = sim.catalog.town.get("counter", {}).get("phases", ["day"])
		var day0 := (int(sim.state.clock["minute"]) / 1440) * 1440
		var n := 0
		for m: int in 1440:
			if Clock.phase(day0 + m, sim.catalog.time) in phases:
				n += 1
		_open_minutes[season] = maxi(60, n)
	return int(_open_minutes[season])


## A customer arrives (if there is room to wait): it wants one of the products the building makes.
static func _arrive(sim: Sim, bld: String, now: int) -> void:
	var c: Dictionary = sim.state.town["clientele"][bld]
	var w: Array = c["waiting"]
	if w.size() >= int(cfg(sim).get("max_waiting", 4)):
		return
	var products := _products(sim, bld)
	if products.is_empty():
		return
	var item: String = products[Kin.randi_range(sim.state, "cmc|item|%s|%d" % [bld, now], 0, products.size() - 1)]
	c["seq"] = int(c["seq"]) + 1
	var rec := {"id": "cmc_%s_%d" % [bld, int(c["seq"])], "item": item, "since": now, "served_at": -1}
	w.append(rec)
	sim.events.append({"type": "customer_arrived", "building": bld, "customer": rec["id"], "clientele": true, "item": item})
	if OS.is_debug_build():
		print("[Clientele] %s llega a %s a por %s (%.1f al día)" % [rec["id"], bld, item, per_day(sim, bld)])


static func _products(sim: Sim, bld: String) -> Array:
	var type := str(sim.state.buildings[bld].get("type", ""))
	var out: Array = []
	var recipes: Dictionary = sim.catalog.recipes()
	var ids: Array = recipes.keys()
	ids.sort()
	for r: String in ids:
		var rec: Dictionary = recipes[r]
		if str(rec.get("building", "")) != type:
			continue
		var item := str(rec.get("output", {}).get("item", ""))
		if item != "" and str(sim.catalog.item(item).get("category", "")) == "product" and not out.has(item):
			out.append(item)
	return out


static func _serve(sim: Sim, bld: String, now: int) -> void:
	var tcfg: Dictionary = sim.catalog.town.get("counter", {})
	var server := Counter.server_of(sim, bld)
	for w: Dictionary in (sim.state.town["clientele"][bld]["waiting"] as Array).duplicate():
		if server == "":
			w["served_at"] = -1
			if now - int(w["since"]) >= int(tcfg.get("patience_minutes", 60)):
				_leave(sim, bld, w, "nobody")
			continue
		if int(w["served_at"]) < 0:
			w["served_at"] = now + int(tcfg.get("serve_minutes", 10))
		if now < int(w["served_at"]):
			return   # one at a time: the first in the queue is being served
		_sell(sim, bld, w, server)
		return


static func _sell(sim: Sim, bld: String, w: Dictionary, server: String) -> void:
	var st := sim.state
	var item := str(w["item"])
	var inv: Dictionary = st.buildings[bld]["inventory"]
	var best := -1
	for s: Dictionary in inv.get("stacks", []):
		if str(s["item"]) == item and int(s["qty"]) > 0 and int(s["quality"]) > best:
			best = int(s["quality"])
	if best < 0:
		_leave(sim, bld, w, "no_product")
		return
	var p := Counter.price(sim, bld, server, item, best, "")
	if p > max_price(sim, bld, item, best):
		_leave(sim, bld, w, "too_dear")
		return
	Inventory.remove(inv, item, best, 1)
	var fam := str(st.buildings[bld].get("owner", ""))
	Money.change(sim, fam, p, Money.COUNTER_SALES, "counter", bld, server)
	sim.events.append({"type": "counter_sold", "family": fam, "building": bld, "customer": str(w["id"]), "seller": server,
		"item": item, "quality": best, "price": p, "clientele": true})
	if OS.is_debug_build():
		print("[Clientele] %s compra %s (q%d) en %s por %d (vende %s)" % [w["id"], item, best, bld, p, server])
	_leave(sim, bld, w, "bought")


static func _leave(sim: Sim, bld: String, w: Dictionary, reason: String) -> void:
	var c: Dictionary = sim.state.town["clientele"].get(bld, {})
	(c.get("waiting", []) as Array).erase(w)
	if reason != "bought":
		sim.events.append({"type": "customer_left", "building": bld, "customer": str(w["id"]), "reason": reason,
			"clientele": true})
		if OS.is_debug_build():
			print("[Clientele] %s se va de %s sin comprar (%s)" % [w["id"], bld, reason])
