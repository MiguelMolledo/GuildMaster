class_name Services
extends RefCounted
## Clients of a service (docs/gdd/04d_otras_clases.md 4.22.3.2), first for the physician's Consulta (4.22.5.1): the
## patients. Like the countryside clientele (Clientele) they are records, not characters: townsfolk with an ailment and
## people of the villages around, under state.town.services[bld] = {next_at, seq, waiting: [{id, service, severity,
## since, claimed}]} (read with defaults: no save version). Their gold comes from outside (P4, 4.19).
##
##   per_day(b) = (visits_per_adult × the town's adults + countryside_per_day × fame(b)) × season × events × share(b)
##   share(b)   = appeal(b) / (Σ appeal of the providers of the service + no_go)          (4.22.3.2, data/services.json)
##   appeal(b)  = Clientele.provider_appeal(b, price(b) / ref_price, customer_bonus): the same formula as the shops
##
## They come during the service's open_phases (at most max_waiting at once), wait at the service station until
## patience_minutes and leave unattended (event service_client_left, a complaint for the workshop's fame). A service
## recipe (Production, kind "service") at the station claims the oldest one whose severity it treats (max_severity),
## works duration_hours on it and calls finish: the patient pays price(b) × the recipe's price_mult × the building's
## price_multiplier (category services) and the doctor rolls SkillCheck(stat + quality_bonus, severity): cured or not
## (cure_reputation for the family when cured; the workshop's fame either way). The owner sets the price with
## set_service_price (price_range × ref_price), kept in buildings[b].services {service → price} (default: ref_price).
## Figures: data/services.json services.<id> [balance].

static var _open: Dictionary = {}   # "service|season" -> minutes of the day the service is open


static func cfg(sim: Sim, service: String) -> Dictionary:
	return sim.catalog.services.get("services", {}).get(service, {})


## The services a building type offers (the services whose providers name it), sorted.
static func of_type(sim: Sim, type: String) -> Array:
	var out: Array = []
	var all: Dictionary = sim.catalog.services.get("services", {})
	for s: String in all:
		var c: Dictionary = all[s]
		if c.has("visits_per_adult") and c.has("ref_price") and type in (c.get("providers", []) as Array) \
				and c.has("open_phases"):
			out.append(s)
	out.sort()
	return out


## The buildings that give `service` now: of a provider type, with an owner family, not for sale.
static func providers(sim: Sim, service: String) -> Array:
	var types: Array = cfg(sim, service).get("providers", [])
	var out: Array = []
	for b: String in sim.state.buildings:
		var bd: Dictionary = sim.state.buildings[b]
		if str(bd.get("type", "")) in types and str(bd.get("owner", "")) != "" and not bool(bd.get("for_sale", false)):
			out.append(b)
	out.sort()
	return out


## The clients waiting at `bld` now: [{id, service, severity, since, claimed}] (the view draws them inside).
static func waiting(st: WorldState, bld: String) -> Array:
	var c: Variant = st.town.get("services", {}).get(bld)
	return (c as Dictionary).get("waiting", []) if c is Dictionary else []


## The price `bld` asks for `service` (its owner's, else the reference).
static func price(sim: Sim, bld: String, service: String) -> int:
	var ref := int(cfg(sim, service).get("ref_price", 0))
	var p: Variant = sim.state.buildings.get(bld, {}).get("services", {}).get(service)
	return int(p) if p != null else ref


## [min, max] the owner may ask for `service`.
static func price_range(sim: Sim, service: String) -> Array:
	var ref := float(cfg(sim, service).get("ref_price", 0))
	var r: Array = sim.catalog.services.get("price_range", [0.5, 2.0])
	return [ceili(ref * float(r[0]) - 0.0001), floori(ref * float(r[1]) + 0.0001)]


## What a client pays at the end of `recipe` at `bld`.
static func charge(sim: Sim, bld: String, recipe: Dictionary) -> int:
	var base := float(price(sim, bld, str(recipe.get("service", ""))))
	return roundi(base * float(recipe.get("price_mult", 1.0)) * Upgrades.mult(sim, bld, "price_multiplier"))


## The appeal of 4.22.3.2: the price over the reference, the family's reputation and the customer_bonus upgrades.
static func appeal(sim: Sim, bld: String, service: String) -> float:
	var ref := maxf(float(cfg(sim, service).get("ref_price", 1)), 1.0)
	return Clientele.provider_appeal(sim, bld, float(price(sim, bld, service)) / ref, "customer_bonus")


## The share of the clients of `service` that go to `bld`.
static func share(sim: Sim, bld: String, service: String) -> float:
	var total := 0.0
	for b: String in providers(sim, service):
		total += appeal(sim, b, service)
	return appeal(sim, bld, service) / maxf(0.0001, total + float(sim.catalog.services.get("no_go", 0.5)))


## How many clients of `service` come a day to `bld` (the formula above).
static func per_day(sim: Sim, bld: String, service: String) -> float:
	var c := cfg(sim, service)
	var base := float(c.get("visits_per_adult", 0.0)) * float(_adults(sim)) \
		+ float(c.get("countryside_per_day", 0.0)) * WorkshopFame.of(sim, bld)
	if base <= 0.0:
		return 0.0
	var season := Clock.season(int(sim.state.clock["minute"]), sim.catalog.time)
	var season_mult := float(sim.catalog.seasons.get("customers", {}).get(season, 1.0))
	return base * season_mult * WorldEvents.customers_mult(sim) * share(sim, bld, service)


## Once per minute: arrivals while open, the clients that run out of patience, everybody out when it closes.
static func step(sim: Sim) -> void:
	var st := sim.state
	var all: Dictionary = sim.catalog.services.get("services", {})
	if all.is_empty() or st.buildings.is_empty():
		return
	var now := int(st.clock["minute"])
	var phase := Clock.phase(now, sim.catalog.time)
	var names: Array = all.keys()
	names.sort()
	for service: String in names:
		var c: Dictionary = all[service]
		if not c.has("open_phases") or not c.has("ref_price"):
			continue  # the tavern's and the inn's have their own clients (Inn, InnClientele)
		var open := phase in (c["open_phases"] as Array)
		for bld: String in providers(sim, service):
			_step_building(sim, bld, service, now, open)
	if st.town.get("services") is Dictionary:
		for bld: String in (st.town["services"] as Dictionary).keys():
			if not st.buildings.has(bld) or str(st.buildings[bld].get("owner", "")) == "":
				st.town["services"].erase(bld)


static func _mem(st: WorldState, bld: String) -> Dictionary:
	if not st.town.get("services") is Dictionary:
		st.town["services"] = {}
	var all: Dictionary = st.town["services"]
	if not all.get(bld) is Dictionary:
		all[bld] = {"next_at": -1, "seq": 0, "waiting": []}
	return all[bld]


static func _step_building(sim: Sim, bld: String, service: String, now: int, open: bool) -> void:
	var st := sim.state
	if not open:
		var cur: Variant = st.town.get("services", {}).get(bld)
		if cur is Dictionary:
			for w: Dictionary in ((cur as Dictionary)["waiting"] as Array).duplicate():
				if str(w["service"]) == service and str(w.get("claimed", "")) == "":
					_leave(sim, bld, w, "closed")
			(cur as Dictionary)["next_at"] = -1
		return
	var m := _mem(st, bld)
	if int(m["next_at"]) < 0:
		m["next_at"] = now + _interval(sim, bld, service, now)
	if now >= int(m["next_at"]):
		m["next_at"] = now + _interval(sim, bld, service, now)
		_arrive(sim, bld, service, now)
	var patience := int(cfg(sim, service).get("patience_minutes", 60))
	for w: Dictionary in (m["waiting"] as Array).duplicate():
		if str(w["service"]) == service and str(w.get("claimed", "")) == "" and now - int(w["since"]) >= patience:
			_leave(sim, bld, w, "nobody")


## Minutes until the next client: the service's open minutes of the day over per_day, ×[0.5, 1.5] by its own stream.
static func _interval(sim: Sim, bld: String, service: String, now: int) -> int:
	var n := per_day(sim, bld, service)
	if n <= 0.0:
		return 1440
	var f := float(Kin.randi_range(sim.state, "svc|next|%s|%s|%d" % [bld, service, now], 50, 150)) / 100.0
	return maxi(5, roundi(float(open_minutes(sim, service)) / n * f))


static func open_minutes(sim: Sim, service: String) -> int:
	var season := Clock.season(int(sim.state.clock["minute"]), sim.catalog.time)
	var key := "%s|%s" % [service, season]
	if not _open.has(key):
		var phases: Array = cfg(sim, service).get("open_phases", ["day"])
		var day0 := (int(sim.state.clock["minute"]) / 1440) * 1440
		var n := 0
		for m: int in 1440:
			if Clock.phase(day0 + m, sim.catalog.time) in phases:
				n += 1
		_open[key] = maxi(60, n)
	return int(_open[key])


static func _adults(sim: Sim) -> int:
	var n := 0
	for id: String in sim.state.characters:
		if TownLife.is_townsperson(sim.state, id) and TownLife.is_adult(sim.state, sim.catalog, id) \
				and bool(sim.state.characters[id].get("alive", true)):
			n += 1
	return n


## A client arrives (if there is room to wait), with a severity drawn by the service's weights.
static func _arrive(sim: Sim, bld: String, service: String, now: int) -> void:
	var st := sim.state
	var m := _mem(st, bld)
	var w: Array = m["waiting"]
	var c := cfg(sim, service)
	if w.size() >= int(c.get("max_waiting", 4)):
		return
	var sev := 0
	var table: Array = c.get("severity", [])
	var total := 0
	for row: Dictionary in table:
		total += int(row.get("weight", 0))
	if total > 0:
		var r := Kin.randi_range(st, "svc|sev|%s|%d" % [bld, now], 1, total)
		for row: Dictionary in table:
			r -= int(row.get("weight", 0))
			if r <= 0:
				sev = int(row.get("severity", 0))
				break
	m["seq"] = int(m["seq"]) + 1
	var rec := {"id": "svc_%s_%d" % [bld, int(m["seq"])], "service": service, "severity": sev, "since": now,
		"claimed": ""}
	w.append(rec)
	sim.events.append({"type": "service_client_arrived", "building": bld, "service": service, "client": rec["id"],
		"severity": sev})
	if OS.is_debug_build():
		print("[Services] %s llega a %s (%s, gravedad %d; %.1f al día)" % [rec["id"], bld, service, sev,
			per_day(sim, bld, service)])


static func _leave(sim: Sim, bld: String, w: Dictionary, reason: String) -> void:
	var m := _mem(sim.state, bld)
	(m["waiting"] as Array).erase(w)
	if reason == "served":
		return
	sim.events.append({"type": "service_client_left", "building": bld, "service": str(w["service"]),
		"client": str(w["id"]), "reason": reason, "family": str(sim.state.buildings[bld].get("owner", ""))})
	if reason == "nobody":
		WorkshopFame.add(sim, bld, "complaint")
		Notices.add(sim, str(sim.state.buildings[bld].get("owner", "")), Notices.INFO, "notice.patient_left",
			{"service": str(w["service"])}, bld)
	if OS.is_debug_build():
		print("[Services] %s se va de %s sin atender (%s)" % [w["id"], bld, reason])


## The oldest client of `recipe`'s service at `bld` that it treats (severity <= max_severity) and nobody else has
## taken: it is taken by `zone` and its id returned ("" if none).
static func claim(sim: Sim, bld: String, zone: String, recipe: Dictionary) -> String:
	var service := str(recipe.get("service", ""))
	var top := int(recipe.get("max_severity", 99))
	for w: Dictionary in waiting(sim.state, bld):
		if str(w["service"]) == service and str(w.get("claimed", "")) == "" and int(w.get("severity", 0)) <= top:
			w["claimed"] = zone
			return str(w["id"])
	return ""


## Whether a client of `recipe` waits at `bld` (unclaimed, of a severity it treats): for the bots and the UI.
static func has_client(sim: Sim, bld: String, recipe: Dictionary) -> bool:
	var service := str(recipe.get("service", ""))
	var top := int(recipe.get("max_severity", 99))
	for w: Dictionary in waiting(sim.state, bld):
		if str(w["service"]) == service and str(w.get("claimed", "")) == "" and int(w.get("severity", 0)) <= top:
			return true
	return false


## A claimed client goes back to waiting (the job was interrupted): its patience goes on from where it was.
static func release(sim: Sim, bld: String, client: String) -> void:
	for w: Dictionary in waiting(sim.state, bld):
		if str(w["id"]) == client:
			w["claimed"] = ""


## The end of a service at `bld`: the client pays, the roll says cured or not, it leaves. Returns the result
## {client, severity, price, cured, roll, threshold} (empty if the client is gone).
static func finish(sim: Sim, bld: String, zone: String, actor: String, recipe_id: String, client: String) -> Dictionary:
	var st := sim.state
	var rec: Dictionary = {}
	for w: Dictionary in waiting(st, bld):
		if str(w["id"]) == client:
			rec = w
	if rec.is_empty():
		return {}
	var recipe: Dictionary = sim.catalog.recipes().get(recipe_id, {})
	var service := str(recipe.get("service", ""))
	var fam := str(st.buildings[bld].get("owner", ""))
	var pay := charge(sim, bld, recipe)
	if pay > 0 and fam != "":
		Money.change(sim, fam, pay, Money.SERVICES, recipe_id, bld, actor)
	var stat := str(recipe.get("stat", "craft"))
	var skill := SkillCheck.stat(sim, actor, stat) + roundi(Upgrades.amount(sim, bld, "quality_bonus"))
	var sev := int(rec.get("severity", 0))
	var r := SkillCheck.roll(sim, "svc|cure|%s|%s" % [bld, client], skill, sev)
	var cured := bool(r.get("success", false))
	var c := cfg(sim, service)
	if cured:
		Reputation.change(sim, fam, int(c.get("cure_reputation", 0)), "patient_cured")
		WorkshopFame.add(sim, bld, "patient_cured")
	else:
		Reputation.change(sim, fam, int(c.get("fail_reputation", 0)), "patient_not_cured")
	_leave(sim, bld, rec, "served")
	var out := {"client": client, "severity": sev, "price": pay, "cured": cured, "roll": int(r.get("roll", 0)),
		"threshold": int(r.get("threshold", 0))}
	sim.events.append({"type": "service_done", "family": fam, "actor": actor, "building": bld, "zone": zone,
		"service": service, "recipe": recipe_id, "client": client, "severity": sev, "price": pay, "cured": cured})
	if OS.is_debug_build():
		print("[Services] %s atiende a %s en %s/%s (%s, gravedad %d): paga %d, %s (tirada %d/%d)" % [actor, client, bld,
			zone, recipe_id, sev, pay, "curado" if cured else "sin curar", out["roll"], out["threshold"]])
	return out


## {"type": "set_service_price", "actor", "building", "service", "price"}: the owner family sets what it asks.
## Reasons: unknown_actor, unknown_building, not_owner, unknown_service, bad_price.
static func order_set_price(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var bld := str(o.get("building", ""))
	if not st.buildings.has(bld):
		return Orders.fail("unknown_building")
	var fam := str(st.characters[actor].get("family", ""))
	if fam == "" or str(st.buildings[bld].get("owner", "")) != fam:
		return Orders.fail("not_owner")
	var service := str(o.get("service", ""))
	if not service in of_type(sim, str(st.buildings[bld].get("type", ""))):
		return Orders.fail("unknown_service")
	var p := int(o.get("price", -1))
	var r := price_range(sim, service)
	if p < int(r[0]) or p > int(r[1]):
		return Orders.fail("bad_price")
	if not st.buildings[bld].get("services") is Dictionary:
		st.buildings[bld]["services"] = {}
	st.buildings[bld]["services"][service] = p
	sim.events.append({"type": "service_price_set", "family": fam, "actor": actor, "building": bld, "service": service,
		"price": p})
	if OS.is_debug_build():
		print("[Services] %s fija el precio de %s en %s: %d" % [actor, service, bld, p])
	return Orders.ok()
