class_name Travel
extends RefCounted
## Travelling between the settlements (docs/gdd/09b_region.md §9b.5; O-R2 a, O-R3 a). Abstract: the traveller leaves
## the home map, goes leg by leg along the shortest open way (each leg: its route's hours × the war's ×1.5, its toll
## and the escort if wanted, paid when the leg starts; its ambush roll when it ends) and, there, stays «in the city»
## (CityTrade, Treaties act on that city) until it travels on or comes back; back home it appears at the gate.
## While away: off the map (Region.is_away: the orders refused but the region's, no routine, no needs), the family's
## employees and directives go on as before; the view passes the control to the next one of the group.
## State: state.region.trips {chr: {id, actor, family, from, to, path [route ids], leg, at, leg_start, leg_end,
## escort, state "road" | "city", since}}.
## An ambush takes every item the traveller carries; no wound until the health of 4.22 arrives (H12.3).

## The orders an away character may give (Sim._apply_now refuses the rest).
const AWAY_ORDERS: Array[String] = ["travel", "return", "city_buy", "city_sell", "city_accept", "city_deliver",
	"sign_treaty", "cancel_treaty"]


static func trip(st: WorldState, chr: String) -> Dictionary:
	return (st.region.get("trips", {}) as Dictionary).get(chr, {})


## The city `chr` is in now ("" if at home or on the road).
static func in_city(st: WorldState, chr: String) -> String:
	var t := trip(st, chr)
	return str(t.get("at", "")) if str(t.get("state", "")) == "city" else ""


## "" if family `fam` may travel (its title is at least travel.unlock_title), else "title_needed".
static func unlock_reason(sim: Sim, fam: String) -> String:
	var need := str(sim.catalog.trade.get("travel", {}).get("unlock_title", "citizen"))
	if Upgrades.title_rank(sim, Upgrades.family_title(sim, fam)) < Upgrades.title_rank(sim, need):
		return "title_needed"
	return ""


## "" if `actor` may set out now for `to`, else why: unknown_actor, dead, banished, not_adult, employee, busy (a duel), no_family,
## title_needed, on_the_road, unknown_city, already_there, no_open_route, not_enough_gold.
static func can_travel(sim: Sim, actor: String, to: String, escort: bool = false) -> String:
	var st := sim.state
	var ch: Dictionary = st.characters.get(actor, {})
	if ch.is_empty():
		return "unknown_actor"
	if not Kin.alive(st, actor):
		return "dead"
	if Tribunal.is_banished(st, actor):
		return "banished"
	if not Kin.is_adult(sim, actor):
		return "not_adult"
	if ch.get("job") is Dictionary:
		return "employee"
	if not Duels.of_character(st, actor).is_empty():
		return "busy"  # duelo: a duel pending or under way keeps it at home
	var fam := str(ch.get("family", ""))
	if not st.families.has(fam):
		return "no_family"
	var why := unlock_reason(sim, fam)
	if why != "":
		return why
	var t := trip(st, actor)
	if not t.is_empty() and str(t.get("state", "")) != "city":
		return "on_the_road"
	if Region.settlement(sim, to).is_empty():
		return "unknown_city"
	var from := str(t.get("at", "")) if not t.is_empty() else Region.home(sim)
	if from == to:
		return "already_there"
	var p := Region.path(sim, from, to)
	if p.is_empty():
		return "no_open_route"
	if not Money.can_pay(st, fam, leg_cost(sim, Region.route(sim, str(p[0])), escort)):
		return "not_enough_gold"
	return ""


## Gold a leg on route `r` costs when it starts: its toll + the escort.
static func leg_cost(sim: Sim, r: Dictionary, escort: bool) -> int:
	return int(r.get("toll", 0)) + (int(sim.catalog.trade.get("travel", {}).get("escort_cost", 20)) if escort else 0)


## {"type": "travel", "actor", "to": settlement id, "escort"?: bool}: from home (or from the city where the actor is)
## to `to` by the shortest open way. Reasons: can_travel's.
static func order_travel(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var to := str(o.get("to", ""))
	var escort := bool(o.get("escort", false))
	var why := can_travel(sim, actor, to, escort)
	if why != "":
		return Orders.fail(why)
	_set_out(sim, actor, to, escort)
	return Orders.ok()


## {"type": "return", "actor", "escort"?: bool}: back home from the city where the actor is. Reasons: not_in_city and
## can_travel's.
static func order_return(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	if in_city(sim.state, actor) == "":
		return Orders.fail("not_in_city")
	var home := Region.home(sim)
	var why := can_travel(sim, actor, home, bool(o.get("escort", false)))
	if why != "":
		return Orders.fail(why)
	_set_out(sim, actor, home, bool(o.get("escort", false)))
	return Orders.ok()


static func _set_out(sim: Sim, actor: String, to: String, escort: bool) -> void:
	var st := sim.state
	var r := Region.ensure(sim)
	var old := trip(st, actor)
	var from := str(old.get("at", "")) if not old.is_empty() else Region.home(sim)
	if old.is_empty():
		Region.take_off_map(sim, actor)
	var fam := str(st.characters[actor].get("family", ""))
	var now := int(st.clock["minute"])
	var t := {"id": str(old.get("id", Ids.next(st, "trv"))), "actor": actor, "family": fam, "from": from, "to": to,
		"path": Region.path(sim, from, to), "leg": 0, "at": from, "leg_start": now, "leg_end": now, "escort": escort,
		"state": "road", "since": int(old.get("since", now))}
	r["trips"][actor] = t
	sim.events.append({"type": "trip_started", "actor": actor, "family": fam, "from": from, "to": to,
		"path": t["path"]})
	if OS.is_debug_build():
		print("[Travel] %s sale de %s hacia %s por %s (escolta=%s)" % [actor, from, to, t["path"], escort])
	_start_leg(sim, t)


## Starts the trip's current leg: pays its toll and escort (without the gold, the trip stops where it is).
static func _start_leg(sim: Sim, t: Dictionary) -> void:
	var r := Region.route(sim, str(t["path"][int(t["leg"])]))
	var cost := leg_cost(sim, r, bool(t["escort"]))
	var fam := str(t["family"])
	var now := int(sim.state.clock["minute"])
	if cost > 0 and not Money.can_pay(sim.state, fam, cost):
		_stop_at(sim, t, "not_enough_gold")
		return
	if int(r.get("toll", 0)) > 0:
		Money.change(sim, fam, -int(r["toll"]), Money.TAXES, "toll", "", str(t["actor"]))
	if bool(t["escort"]):
		Money.change(sim, fam, -(cost - int(r.get("toll", 0))), Money.SERVICES, "escort", "", str(t["actor"]))
	t["state"] = "road"
	t["leg_start"] = now
	t["leg_end"] = now + Region.leg_minutes(sim, r)
	if OS.is_debug_build():
		print("[Travel] %s: tramo %s de %s (%d min, peaje+escolta %d)" % [t["actor"], r["id"], t["at"],
			int(t["leg_end"]) - now, cost])


## A trip that cannot go on stays in the city where it is (at home: it comes back).
static func _stop_at(sim: Sim, t: Dictionary, reason: String) -> void:
	if str(t["at"]) == Region.home(sim):
		_arrive_home(sim, t)
		return
	t["state"] = "city"
	t["to"] = str(t["at"])
	sim.events.append({"type": "trip_stopped", "actor": t["actor"], "family": t["family"], "at": t["at"],
		"reason": reason})
	Notices.add(sim, str(t["family"]), Notices.WARNING, "notice.trip_stopped", {"name": _name(sim, str(t["actor"])),
		"city": _city_key(sim, str(t["at"]))}, str(t["actor"]))


## Every minute: legs that end now (ambush roll, arrival, next leg); travellers who died.
static func step(sim: Sim) -> void:
	var st := sim.state
	var trips: Dictionary = st.region["trips"]
	var now := int(st.clock["minute"])
	var ids: Array = trips.keys()
	ids.sort()
	for chr: String in ids:
		var t: Dictionary = trips[chr]
		if not Kin.alive(st, chr):
			trips.erase(chr)
			continue
		if str(t["state"]) != "road" or now < int(t["leg_end"]):
			continue
		var rid := str(t["path"][int(t["leg"])])
		var r := Region.route(sim, rid)
		if Region.ambushed(sim, r, bool(t["escort"]), "trv|%s|%d|%s" % [t["id"], int(t["leg"]), rid]):
			_ambush(sim, t, rid)
		t["at"] = Region.other_end(sim, rid, str(t["at"]))
		t["leg"] = int(t["leg"]) + 1
		if str(t["at"]) == str(t["to"]):
			if str(t["to"]) == Region.home(sim):
				_arrive_home(sim, t)
			else:
				_arrive(sim, t)
		else:
			_start_leg(sim, t)


## The bandits take every item the traveller carries (no wound yet: the health of 4.22, H12.3).
static func _ambush(sim: Sim, t: Dictionary, rid: String) -> void:
	var ch: Dictionary = sim.state.characters[str(t["actor"])]
	var inv: Dictionary = ch.get("inventory", {})
	var lost: Array = []
	for s: Dictionary in inv.get("stacks", []):
		lost.append({"item": s["item"], "quality": s["quality"], "qty": s["qty"]})
	inv["stacks"] = []
	Region.stat(sim, str(t["family"]), "ambushes")
	sim.events.append({"type": "trip_ambushed", "actor": t["actor"], "family": t["family"], "route": rid, "lost": lost})
	Notices.add(sim, str(t["family"]), Notices.URGENT, "notice.trip_ambushed", {"name": _name(sim, str(t["actor"])),
		"count": lost.size()}, str(t["actor"]))
	if OS.is_debug_build():
		print("[Travel] ¡asalto! %s en %s: pierde %s" % [t["actor"], rid, lost])


static func _arrive(sim: Sim, t: Dictionary) -> void:
	t["state"] = "city"
	t["path"] = []
	t["leg"] = 0
	Region.stat(sim, str(t["family"]), "arrivals")
	sim.events.append({"type": "trip_arrived", "actor": t["actor"], "family": t["family"], "city": t["at"]})
	Notices.add(sim, str(t["family"]), Notices.INFO, "notice.trip_arrived", {"name": _name(sim, str(t["actor"])),
		"city": _city_key(sim, str(t["at"]))}, str(t["actor"]))
	if OS.is_debug_build():
		print("[Travel] %s llega a %s" % [t["actor"], t["at"]])


static func _arrive_home(sim: Sim, t: Dictionary) -> void:
	var actor := str(t["actor"])
	(sim.state.region["trips"] as Dictionary).erase(actor)
	Region.put_on_map(sim, actor, Region.gate_tile(sim))
	Region.stat(sim, str(t["family"]), "returns")
	sim.events.append({"type": "trip_returned", "actor": actor, "family": t["family"]})
	Notices.add(sim, str(t["family"]), Notices.INFO, "notice.trip_returned", {"name": _name(sim, actor)}, actor)
	if OS.is_debug_build():
		print("[Travel] %s vuelve a casa por la puerta %s" % [actor, Region.gate_tile(sim)])


## How far along its leg a trip is (0..1) and where: {from, to, route, progress} for the view.
static func progress(sim: Sim, chr: String) -> Dictionary:
	var t := trip(sim.state, chr)
	if t.is_empty():
		return {}
	if str(t["state"]) == "city":
		return {"state": "city", "at": t["at"], "to": t["to"]}
	var rid := str(t["path"][int(t["leg"])])
	var span := maxi(1, int(t["leg_end"]) - int(t["leg_start"]))
	var f := clampf(float(int(sim.state.clock["minute"]) - int(t["leg_start"])) / float(span), 0.0, 1.0)
	return {"state": "road", "route": rid, "from": t["at"], "next": Region.other_end(sim, rid, str(t["at"])),
		"to": t["to"], "progress": f, "minutes_left": maxi(0, int(t["leg_end"]) - int(sim.state.clock["minute"]))}


static func _name(sim: Sim, chr: String) -> String:
	return str(sim.state.characters.get(chr, {}).get("name", chr))


static func _city_key(sim: Sim, id: String) -> String:
	return str(Region.settlement(sim, id).get("name_key", id))
