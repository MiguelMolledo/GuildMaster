class_name Region
extends RefCounted
## The region away from home (docs/gdd/09b_region.md §9b.6): the settlements of data/world/region.json besides home,
## each with its own market demand, local events, contracts board and the reputation of each family; the regional
## events that cut routes (snow, flood); the treaties in force, the trips and the caravans (Travel, CityTrade,
## Caravans, Treaties). Rules in data/world/trade.json. State: state.region (v16):
##   {cities: {id: {demand: {item: x}, events: [{def, start, end}], board: [offer], reputation: {fam: n}}},
##    events: [{id, def, start, end}], treaties: [treaty], trips: {chr: trip}, caravans: [caravan], carts: {fam: n},
##    contracts: [accepted], stats: {fam: {...}}}
## No people, no buildings, no bots per tile away from home. Everything moves at day_started / dawn / season start
## with keyed streams of its own (Kin.roll "rgn|...", "rgev|..."): never state.rng, never a home roll. Home's market,
## events and reputation are not touched by any of this; a family that never travels meets none of it.

const DAWN: String = "dawn"


# --- State -----------------------------------------------------------------------------------------------------------

## Fills state.region the first time (a new game, or a save from before v16): the cities besides home, empty.
static func ensure(sim: Sim) -> Dictionary:
	var r: Dictionary = sim.state.region
	if r.has("cities"):
		return r
	var cities := {}
	var home := home_id(sim)
	for s: Dictionary in settlements(sim):
		var id := str(s["id"])
		if id != home:
			cities[id] = {"demand": {}, "events": [], "board": [], "reputation": {}}
	for k: String in ["events", "treaties", "caravans", "contracts"]:
		r[k] = []
	for k: String in ["trips", "carts", "stats"]:
		r[k] = {}
	r["cities"] = cities
	r["home"] = home
	if OS.is_debug_build():
		print("[Region] estado nuevo: casa=%s, ciudades=%s" % [home, _sorted_keys(cities)])
	return r


## The settlement that is home: the one whose map is the game's map; else region.json «home».
static func home_id(sim: Sim) -> String:
	for s: Dictionary in settlements(sim):
		if str(s.get("map", "")) == sim.state.map_id and sim.state.map_id != "":
			return str(s["id"])
	return str(sim.catalog.region.get("home", ""))


static func home(sim: Sim) -> String:
	return str(ensure(sim).get("home", home_id(sim)))


static func settlements(sim: Sim) -> Array:
	return sim.catalog.region.get("settlements", [])


static func settlement(sim: Sim, id: String) -> Dictionary:
	for s: Dictionary in settlements(sim):
		if str(s.get("id", "")) == id:
			return s
	return {}


static func is_city(sim: Sim, id: String) -> bool:
	return (ensure(sim)["cities"] as Dictionary).has(id)


static func city(sim: Sim, id: String) -> Dictionary:
	return (ensure(sim)["cities"] as Dictionary).get(id, {})


static func stat(sim: Sim, fam: String, key: String, add: int = 1) -> void:
	var s: Dictionary = ensure(sim)["stats"]
	if not s.has(fam):
		s[fam] = {}
	s[fam][key] = int(s[fam].get(key, 0)) + add


# --- Step ------------------------------------------------------------------------------------------------------------

## Once per minute, after the market. Trips and caravans move every minute (nothing to do without them); at dawn the
## cities' demand recovers and the carts' upkeep is paid; at day_started the cities roll their local events and post
## contracts, accepted contracts that are due fail; at a season start the regional events roll, the treaties are
## counted and the AI caravans go out.
static func step(sim: Sim) -> void:
	var r := ensure(sim)
	var now := int(sim.state.clock["minute"])
	if not (r["trips"] as Dictionary).is_empty():
		Travel.step(sim)
	if not (r["caravans"] as Array).is_empty():
		Caravans.step(sim)
	for e: Dictionary in sim.events:
		var t := str(e.get("type", ""))
		if t == "phase_changed" and str(e.get("phase", "")) == DAWN:
			_recover_demand(sim)
			Caravans.upkeep(sim)
		elif t == "day_started":
			var day := int(e.get("day", 0))
			_end_due(sim, now)
			if day % _days_per_season(sim) == 0:
				_roll_regional(sim, day)
				Treaties.season(sim, day)
				_ai_caravans(sim, day)
			for c: String in _sorted_keys(r["cities"]):
				_roll_city_event(sim, c, day)
				CityTrade.post_offer(sim, c, day)
			CityTrade.expire(sim, now)


static func _days_per_season(sim: Sim) -> int:
	return maxi(1, int(sim.catalog.time.get("days_per_season", 2)))


## The minute the season of `minute` ends (exclusive).
static func season_end(sim: Sim, minute: int) -> int:
	var dps := _days_per_season(sim)
	var d := Clock.day(minute)
	return (d - d % dps + dps) * Clock.MINUTES_PER_DAY


# --- Demand and prices of a city -------------------------------------------------------------------------------------

static func _demand_cfg(sim: Sim) -> Dictionary:
	return sim.catalog.market.get("demand", {})


static func demand(sim: Sim, c: String, item: String) -> float:
	return float(city(sim, c).get("demand", {}).get(item, _demand_cfg(sim).get("start", 1.0)))


static func set_demand(sim: Sim, c: String, item: String, value: float) -> void:
	var cfg := _demand_cfg(sim)
	var d: Dictionary = city(sim, c).get("demand", {})
	d[item] = clampf(value, float(cfg.get("min", 0.5)), float(cfg.get("max", 2.0)))


## Every unit sold there drops the city's demand of the item by drop_per_unit (as at home).
static func drop_demand(sim: Sim, c: String, item: String, units: int) -> void:
	set_demand(sim, c, item, demand(sim, c, item) - float(_demand_cfg(sim).get("drop_per_unit", 0.04)) * units)


static func _recover_demand(sim: Sim) -> void:
	var cfg := _demand_cfg(sim)
	var rest := float(cfg.get("rest", 1.0))
	var by := float(cfg.get("recover_per_day", 0.4))
	for c: String in _sorted_keys(ensure(sim)["cities"]):
		var d: Dictionary = city(sim, c)["demand"]
		for item: String in _sorted_keys(d):
			var v := float(d[item])
			d[item] = minf(v + by, rest) if v < rest else maxf(v - by, rest)


## mod_ciudad of `item` in city `c`: the product of its «cheap» and «dear» entries that name the item or one of its
## goods groups (region.json), 1 when none does.
static func city_mult(sim: Sim, c: String, item: String) -> float:
	var s := settlement(sim, c)
	var groups: Array = sim.catalog.goods_of(item)
	var m := 1.0
	for side: String in ["cheap", "dear"]:
		var t: Dictionary = s.get(side, {})
		for k: String in t:
			if k == item or k in groups:
				m *= float(t[k])
	return m


## The product of the effects of `kind` (price | demand) on `item` of the events in force there: home's season-scope
## events (regional: the war, a famine) and the city's own local events.
static func events_mult(sim: Sim, c: String, kind: String, item: String) -> float:
	var m := 1.0
	var groups: Array = sim.catalog.goods_of(item)
	var defs: Array = []
	for ev: Dictionary in sim.state.events_active:
		var def: Dictionary = sim.catalog.world_events().get(str(ev.get("def", "")), {})
		if str(def.get("scope", "")) == "season":
			defs.append(def)
	for ev: Dictionary in city(sim, c).get("events", []):
		defs.append(sim.catalog.world_events().get(str(ev.get("def", "")), {}))
	for def: Dictionary in defs:
		for e: Dictionary in def.get("effects", []):
			if str(e.get("kind", "")) == kind and str(e.get("group", "")) in groups:
				m *= float(e.get("mult", 1.0))
	return m


## The unit price of `item` at `quality` in city `c` (side buy | sell), before any tariff (9b.5):
## base × quality × demand_city (× its events' demand, clamped) × season × events × mod_ciudad × buy mult / sell ratio.
static func price(sim: Sim, c: String, item: String, quality: int, side: String) -> int:
	var def := sim.catalog.item(item)
	var qm: Array = sim.catalog.market.get("quality_mult", [])
	if def.is_empty() or quality < 0 or quality >= qm.size() or not is_city(sim, c):
		return 0
	var cfg := _demand_cfg(sim)
	var d := clampf(demand(sim, c, item) * events_mult(sim, c, "demand", item), float(cfg.get("min", 0.5)),
		float(cfg.get("max", 2.0)))
	var p := float(def.get("base_price", 0)) * float(qm[quality]) * d
	p *= WorldEvents.season_mult(sim, "price", item) * events_mult(sim, c, "price", item) * city_mult(sim, c, item)
	if side == "buy":
		p *= float(sim.catalog.difficulty_levels(sim.state.difficulty).get("buy_price_mult", 1.0))
	else:
		p *= float(sim.catalog.market.get("sell_ratio", 0.7))
	return maxi(1, roundi(p))


## Every item a city's market trades (the ones with a market stall), sorted.
static func traded_items(sim: Sim) -> Array:
	var out: Array = []
	for id: String in _sorted_keys(sim.catalog.items()):
		if str(sim.catalog.items()[id].get("market_stall", "")) != "":
			out.append(id)
	return out


## The tariff a family pays on what it sells in city `c` (0 with an exemption treaty, of the family or of its town).
static func tariff(sim: Sim, c: String, fam: String) -> float:
	if Treaties.exempt(sim, c, fam):
		return 0.0
	return float(settlement(sim, c).get("tariff", 0.0))


# --- Reputation ------------------------------------------------------------------------------------------------------

static func reputation(sim: Sim, c: String, fam: String) -> int:
	return int(city(sim, c).get("reputation", {}).get(fam, 0))


static func add_reputation(sim: Sim, c: String, fam: String, amount: int, reason: String) -> void:
	if amount == 0 or not is_city(sim, c):
		return
	var cfg: Dictionary = sim.catalog.trade.get("reputation", {})
	var rep: Dictionary = city(sim, c)["reputation"]
	var v := clampi(int(rep.get(fam, 0)) + amount, int(cfg.get("min", -100)), int(cfg.get("max", 100)))
	rep[fam] = v
	sim.events.append({"type": "city_reputation_changed", "city": c, "family": fam, "amount": amount, "reason": reason,
		"reputation": v})
	if OS.is_debug_build():
		print("[Region] reputación de %s en %s %+d por %s -> %d" % [fam, c, amount, reason, v])


# --- Routes ----------------------------------------------------------------------------------------------------------

static func routes(sim: Sim) -> Array:
	return sim.catalog.region.get("routes", [])


static func route(sim: Sim, id: String) -> Dictionary:
	for r: Dictionary in routes(sim):
		if str(r.get("id", "")) == id:
			return r
	return {}


## Why route `r` is closed now: the ids of the events in force that cut it (home's events in its cut_by, the regional
## events whose «cuts» take its terrain or that its cut_by names); [] = open.
static func cut_by(sim: Sim, r: Dictionary) -> Array:
	var out: Array = []
	var names: Array = r.get("cut_by", [])
	for ev: Dictionary in sim.state.events_active:
		var def := str(ev.get("def", ""))
		if def in names and not def in out:
			out.append(def)
	var regional: Dictionary = sim.catalog.trade.get("regional_events", {})
	for ev: Dictionary in ensure(sim)["events"]:
		var def := str(ev.get("def", ""))
		var cuts: Array = regional.get(def, {}).get("cuts", [])
		if (str(r.get("terrain", "")) in cuts or def in names) and not def in out:
			out.append(def)
	return out


static func is_open(sim: Sim, r: Dictionary) -> bool:
	return cut_by(sim, r).is_empty()


## Game minutes a leg on route `r` takes now: hours × the events' errands multiplier (the war's ×1.5).
static func leg_minutes(sim: Sim, r: Dictionary) -> int:
	return maxi(1, roundi(float(r.get("hours", 1)) * 60.0 * WorldEvents.errands_mult(sim)))


## The shortest way from `a` to `b` over the open routes (by hours): [route ids] in order, [] if none (or a == b).
static func path(sim: Sim, a: String, b: String) -> Array:
	if a == b:
		return []
	var dist := {a: 0.0}
	var via := {}
	var todo := [a]
	while not todo.is_empty():
		todo.sort_custom(func(x: String, y: String) -> bool:
			return float(dist[x]) < float(dist[y]) or (float(dist[x]) == float(dist[y]) and x < y))
		var at: String = todo.pop_front()
		if at == b:
			break
		for r: Dictionary in routes(sim):
			if not is_open(sim, r):
				continue
			var other := ""
			if str(r["a"]) == at:
				other = str(r["b"])
			elif str(r["b"]) == at:
				other = str(r["a"])
			if other == "":
				continue
			var d := float(dist[at]) + float(r.get("hours", 0))
			if not dist.has(other) or d < float(dist[other]):
				dist[other] = d
				via[other] = [at, str(r["id"])]
				if not other in todo:
					todo.append(other)
	if not via.has(b):
		return []
	var out: Array = []
	var at := b
	while at != a:
		out.push_front(str(via[at][1]))
		at = str(via[at][0])
	return out


## The settlement at the other end of route `rid` from `from`.
static func other_end(sim: Sim, rid: String, from: String) -> String:
	var r := route(sim, rid)
	return str(r["b"]) if str(r.get("a", "")) == from else str(r.get("a", ""))


## {hours, toll, risk (the highest of its legs)} of a path (route ids) now.
static func path_cost(sim: Sim, p: Array) -> Dictionary:
	var minutes := 0
	var toll := 0
	var risk := 0
	for rid: String in p:
		var r := route(sim, rid)
		minutes += leg_minutes(sim, r)
		toll += int(r.get("toll", 0))
		risk = maxi(risk, int(r.get("risk", 0)))
	return {"minutes": minutes, "toll": toll, "risk": risk, "legs": p.size()}


## Whether a leg on route `r` is ambushed: one keyed number against risk × ambush_per_risk (÷ escort_divisor with
## an escort).
static func ambushed(sim: Sim, r: Dictionary, escort: bool, key: String) -> bool:
	var cfg: Dictionary = sim.catalog.trade.get("travel", {})
	var p := float(r.get("risk", 0)) * float(cfg.get("ambush_per_risk", 0.04))
	if escort:
		p /= maxf(1.0, float(cfg.get("escort_divisor", 2.0)))
	var roll := Kin.roll(sim.state, key)
	if OS.is_debug_build():
		print("[Region] tirada de asalto %s en %s: %.3f contra %.3f (escolta=%s)" % [key, r.get("id", ""), roll, p, escort])
	return roll < p


# --- Events of the region --------------------------------------------------------------------------------------------

static func _end_due(sim: Sim, now: int) -> void:
	var r := ensure(sim)
	r["events"] = (r["events"] as Array).filter(func(ev: Dictionary) -> bool: return int(ev["end"]) > now)
	for c: String in _sorted_keys(r["cities"]):
		var cd: Dictionary = r["cities"][c]
		cd["events"] = (cd["events"] as Array).filter(func(ev: Dictionary) -> bool: return int(ev["end"]) > now)


## O-R8 a: at a season start, one keyed roll per regional event (snow, flood): it lasts the season.
static func _roll_regional(sim: Sim, day: int) -> void:
	var r := ensure(sim)
	var now := day * Clock.MINUTES_PER_DAY
	var season := Clock.season(now, sim.catalog.time)
	var defs: Dictionary = sim.catalog.trade.get("regional_events", {})
	for id: String in _sorted_keys(defs):
		if id.begins_with("_"):
			continue
		var def: Dictionary = defs[id]
		if day < int(def.get("min_day", 0)):
			continue
		var p := float(def.get("chance", {}).get(season, 0.0))
		if p <= 0.0 or Kin.roll(sim.state, "rgev|regional|%s|%d" % [id, day]) >= p:
			continue
		var ev := {"id": Ids.next(sim.state, "rev"), "def": id, "start": now, "end": season_end(sim, now)}
		(r["events"] as Array).append(ev)
		sim.events.append({"type": "regional_event_started", "def": id, "start": now, "end": ev["end"]})
		for f: String in _sorted_keys(sim.state.families):
			if involved(sim, f):
				Notices.add(sim, f, Notices.WARNING, "notice.region_event", {"what": str(def.get("text_key", id))})
		if OS.is_debug_build():
			print("[Region] evento regional %s del día %d al minuto %d" % [id, day, ev["end"]])


## Whether family `f` takes part in the region now (a trip, a cart, a caravan or a treaty): the regional notices go
## only to those, so a family that never travels gets none.
static func involved(sim: Sim, f: String) -> bool:
	var r := ensure(sim)
	if int((r["carts"] as Dictionary).get(f, 0)) > 0:
		return true
	for t: Dictionary in (r["trips"] as Dictionary).values():
		if str(t.get("family", "")) == f:
			return true
	for t: Dictionary in r["treaties"]:
		if str(t.get("family", "")) == f:
			return true
	return false


## Every day, one keyed roll per city over the local events of data/events.json (at most one in force per city);
## its effects touch only that city's market.
static func _roll_city_event(sim: Sim, c: String, day: int) -> void:
	var cd := city(sim, c)
	if not (cd["events"] as Array).is_empty() or not bool(sim.catalog.events.get("enabled", true)):
		return
	var now := day * Clock.MINUTES_PER_DAY
	var season := Clock.season(now, sim.catalog.time)
	var mult := float(sim.catalog.trade.get("city_events", {}).get("chance_mult", 1.0))
	var options: Array = []
	var total := 0.0
	for id: String in _sorted_keys(sim.catalog.world_events()):
		var def: Dictionary = sim.catalog.world_events()[id]
		var trig: Dictionary = def.get("trigger", {})
		if str(def.get("scope", "")) != "local" or not bool(def.get("enabled", false)) \
				or day < int(trig.get("min_day", 0)):
			continue
		var p := float(trig.get("chance", {}).get(season, 0.0)) * mult
		if p > 0.0:
			options.append([id, p])
			total += p
	if options.is_empty():
		return
	var x := Kin.roll(sim.state, "rgev|%s|%d" % [c, day])
	for o: Array in options:
		x -= float(o[1])
		if x < 0.0:
			var span: Array = sim.catalog.world_events()[o[0]].get("duration", {}).get("days", [1, 1])
			var n := Kin.randi_range(sim.state, "rgev|dur|%s|%s|%d" % [c, o[0], day], int(span[0]), int(span[1]))
			var end := mini(now + n * Clock.MINUTES_PER_DAY, season_end(sim, now))
			(cd["events"] as Array).append({"def": str(o[0]), "start": now, "end": end})
			if OS.is_debug_build():
				print("[Region] %s: evento local %s hasta el minuto %d" % [c, o[0], end])
			return


# --- AI caravans -----------------------------------------------------------------------------------------------------

## At a season start, each AI family with a production building rolls (keyed); a hit «sells» qty of what that building
## makes in a keyed city: its demand drops. No gold, no orders (04c's agenda is not touched).
static func _ai_caravans(sim: Sim, day: int) -> void:
	var cfg: Dictionary = sim.catalog.trade.get("ai_caravans", {})
	var cities: Array = _sorted_keys(ensure(sim)["cities"])
	if cities.is_empty():
		return
	for f: String in _sorted_keys(sim.state.families):
		var fam: Dictionary = sim.state.families[f]
		if str(fam.get("controlled_by", "")) != "ai" or str(fam.get("ai_profile", "")) == "":
			continue
		var item := _product_of(sim, f)
		if item == "" or Kin.roll(sim.state, "rgn|aic|%s|%d" % [f, day]) >= float(cfg.get("chance", 0.5)):
			continue
		var c: String = cities[Kin.randi_range(sim.state, "rgn|aic|city|%s|%d" % [f, day], 0, cities.size() - 1)]
		if Treaties.exclusive_holder(sim, c, item) not in ["", f]:
			if OS.is_debug_build():
				print("[Region] caravana IA de %s a %s: %s es exclusivo de otra familia, no descarga" % [f, c, item])
			continue
		var qty := int(cfg.get("qty", 4))
		drop_demand(sim, c, item, qty)
		sim.events.append({"type": "ai_caravan", "family": f, "city": c, "item": item, "qty": qty})
		if OS.is_debug_build():
			print("[Region] caravana IA de %s vende %s x%d en %s (demanda %.2f)" % [f, item, qty, c, demand(sim, c, item)])


## What the first production building of family `f` sells (the dearest sellable output of its type's recipes), "".
static func _product_of(sim: Sim, f: String) -> String:
	for b: String in _sorted_keys(sim.state.buildings):
		var bd: Dictionary = sim.state.buildings[b]
		if str(bd.get("owner", "")) != f:
			continue
		var best := ""
		for rid: String in _sorted_keys(sim.catalog.recipes()):
			var rec: Dictionary = sim.catalog.recipes()[rid]
			if str(rec.get("building", "")) != str(bd.get("type", "")):
				continue
			var out := str(rec.get("output", {}).get("item", ""))
			if out == "" or str(sim.catalog.item(out).get("market_stall", "")) == "":
				continue
			if best == "" or int(sim.catalog.item(out).get("base_price", 0)) > int(sim.catalog.item(best).get("base_price", 0)):
				best = out
		if best != "":
			return best
	return ""


# --- Who is away -----------------------------------------------------------------------------------------------------

## Whether character `chr` is away from home (on a trip, or the carter of a caravan): off the map, acts only through
## the region's orders.
static func is_away(st: WorldState, chr: String) -> bool:
	var r: Dictionary = st.region
	if r.is_empty():
		return false
	if (r.get("trips", {}) as Dictionary).has(chr):
		return true
	for c: Dictionary in r.get("caravans", []):
		if str(c.get("driver", "")) == chr:
			return true
	return false


## Takes `chr` off the map (a trip or a caravan starts): out of its building and station, no route, no queue.
static func take_off_map(sim: Sim, chr: String) -> void:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty():
		return
	if str(ch.get("station", "")) != "":
		Orders.apply(sim, {"type": "stop_work", "actor": chr})
	var loc := str(ch.get("location", ""))
	if loc != "" and sim.state.buildings.has(loc):
		ch["position"] = (sim.state.buildings[loc].get("door", ch.get("position", [0, 0])) as Array).duplicate()
	ch["location"] = ""
	ch["station"] = ""
	ch["path"] = []
	OrderQueue.clear_for(sim, chr)


## Puts `chr` back on the map at `tile` (back from a trip or a caravan).
static func put_on_map(sim: Sim, chr: String, tile: Array) -> void:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty():
		return
	ch["location"] = ""
	ch["position"] = tile.duplicate()
	ch["path"] = []


## The tile of the home map's gate (trade.json travel.gate), else the player spawn.
static func gate_tile(sim: Sim) -> Array:
	var spawns: Dictionary = sim.catalog.maps().get(sim.state.map_id, {}).get("spawns", {})
	var g := str(sim.catalog.trade.get("travel", {}).get("gate", "west_gate"))
	return (spawns.get(g, spawns.get("player", [0, 0])) as Array).duplicate()


static func _sorted_keys(d: Dictionary) -> Array:
	var k: Array = d.keys()
	k.sort()
	return k
