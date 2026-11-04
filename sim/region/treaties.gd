class_name Treaties
extends RefCounted
## Trade treaties with the cities away from home (docs/gdd/09b_region.md §9b.5, O-R6 c). Kinds (trade.json
## treaties.kinds): exemption (no tariff there), exclusivity of an item (only the family sells it there: the AI
## caravans leave it) and quota of an item (the city buys qty units a season at a fixed price, no tariff). Each with
## the signer family's title, its reputation in that city, a fee and a length in seasons.
##   Family treaty: sign_treaty by the family's head (or regent) in the city.
##   Town treaty (scope «town», exemption only): propose_town_treaty by the Mayor at home; the council votes (the mayor
##   and the councillors: a councillor votes yes if its affinity with the mayor is >= council_yes_affinity, the mayor
##   breaks ties); it covers every family of home and gives the mayor town_reputation at home.
## At each season start: a quota with fewer units delivered than due is broken (penalty, reputation treaty_broken, it
## ends); every other one in force is kept (reputation treaty_kept); the ones whose time is up end. cancel_treaty ends
## one early as broken.
## State: state.region.treaties [{id, kind, scope family | town, city, family, item, qty, price, start, end, delivered,
## first (the first season start that counts it)}].


static func _kinds(sim: Sim) -> Dictionary:
	return sim.catalog.trade.get("treaties", {}).get("kinds", {})


static func in_force(sim: Sim) -> Array:
	return Region.ensure(sim)["treaties"]


## Whether family `fam` pays no tariff in city `c` (an exemption of its own, or of its town if it is a home family).
static func exempt(sim: Sim, c: String, fam: String) -> bool:
	for t: Dictionary in in_force(sim):
		if str(t["kind"]) != "exemption" or str(t["city"]) != c:
			continue
		if str(t["family"]) == fam or (str(t["scope"]) == "town" and is_home_family(sim, fam)):
			return true
	return false


## Every family of the home town is: the player's, the AI ones, the townsfolk (all the state has).
static func is_home_family(sim: Sim, fam: String) -> bool:
	return sim.state.families.has(fam)


## The family holding the exclusivity of `item` in city `c` ("" if none).
static func exclusive_holder(sim: Sim, c: String, item: String) -> String:
	for t: Dictionary in in_force(sim):
		if str(t["kind"]) == "exclusivity" and str(t["city"]) == c and str(t["item"]) == item:
			return str(t["family"])
	return ""


## The quota treaty of `fam` for `item` in city `c` ({} if none).
static func quota_of(sim: Sim, c: String, fam: String, item: String) -> Dictionary:
	for t: Dictionary in in_force(sim):
		if str(t["kind"]) == "quota" and str(t["city"]) == c and str(t["family"]) == fam and str(t["item"]) == item:
			return t
	return {}


## "" if family `fam` may sign a treaty of `kind` (on `item`) in city `c` now, else why: unknown_kind, unknown_city,
## title_needed, reputation_needed, needs_item, not_a_dear_item, already_signed, item_taken, not_enough_gold.
static func can_sign(sim: Sim, fam: String, c: String, kind: String, item: String = "", scope: String = "family") -> String:
	var k: Dictionary = _kinds(sim).get(kind, {})
	if k.is_empty():
		return "unknown_kind"
	if not Region.is_city(sim, c):
		return "unknown_city"
	if Upgrades.title_rank(sim, Upgrades.family_title(sim, fam)) < Upgrades.title_rank(sim, str(k.get("title", ""))):
		return "title_needed"
	if scope == "family" and Region.reputation(sim, c, fam) < int(k.get("reputation", 0)):
		return "reputation_needed"
	if kind in ["exclusivity", "quota"]:
		if item == "":
			return "needs_item"
		if not item in CityTrade.dear_items(sim, c):
			return "not_a_dear_item"
	for t: Dictionary in in_force(sim):
		if str(t["kind"]) != kind or str(t["city"]) != c:
			continue
		if str(t["family"]) == fam and str(t["scope"]) == scope and str(t.get("item", "")) == item:
			return "already_signed"
		if kind == "exclusivity" and str(t["item"]) == item:
			return "item_taken"
	if not Money.can_pay(sim.state, fam, int(k.get("fee", 0))):
		return "not_enough_gold"
	return ""


## {"type": "sign_treaty", "actor", "kind", "item"?}: in the city where the actor is; the actor heads the family (or is
## its regent). Reasons: not_in_city, not_the_head and can_sign's.
static func order_sign(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var c := Travel.in_city(sim.state, actor)
	if c == "":
		return Orders.fail("not_in_city")
	var fam := str(sim.state.characters[actor].get("family", ""))
	if not _leads(sim, fam, actor):
		return Orders.fail("not_the_head")
	var kind := str(o.get("kind", ""))
	var item := str(o.get("item", ""))
	var why := can_sign(sim, fam, c, kind, item)
	if why != "":
		return Orders.fail(why)
	_sign(sim, fam, c, kind, item, "family", actor)
	return Orders.ok()


static func _leads(sim: Sim, fam: String, actor: String) -> bool:
	var f: Dictionary = sim.state.families.get(fam, {})
	return actor == str(f.get("head", "")) or actor == str(f.get("regent", ""))


static func _sign(sim: Sim, fam: String, c: String, kind: String, item: String, scope: String, actor: String) -> Dictionary:
	var k: Dictionary = _kinds(sim)[kind]
	var now := int(sim.state.clock["minute"])
	var dps := maxi(1, int(sim.catalog.time.get("days_per_season", 2)))
	var start_day := Clock.day(now) - Clock.day(now) % dps
	var end := (start_day + int(k.get("seasons", 1)) * dps) * Clock.MINUTES_PER_DAY
	Money.change(sim, fam, -int(k.get("fee", 0)), Money.POLITICS, "treaty:" + kind, "", actor)
	var t := {"id": Ids.next(sim.state, "tre"), "kind": kind, "scope": scope, "city": c, "family": fam, "item": item,
		"qty": int(k.get("qty", 0)), "price": roundi(float(sim.catalog.item(item).get("base_price", 0))
		* float(k.get("price_mult", 1.0))) if item != "" else 0, "start": now, "end": end, "delivered": 0,
		"first": Region.season_end(sim, now)}
	in_force(sim).append(t)
	Region.stat(sim, fam, "treaties_signed")
	sim.events.append({"type": "treaty_signed", "family": fam, "city": c, "kind": kind, "item": item, "scope": scope,
		"treaty": t["id"], "end": end})
	Notices.add(sim, fam, Notices.INFO, "notice.treaty_signed", {"city": str(Region.settlement(sim, c).get("name_key", c)),
		"treaty": "treaty." + kind}, actor)
	if OS.is_debug_build():
		print("[Treaties] %s firma %s (%s, %s) en %s hasta el minuto %d" % [fam, kind, scope, item, c, end])
	return t


## {"type": "propose_town_treaty", "actor", "city", "kind"}: the Mayor at home, for the whole town; the council votes.
## Reasons: not_the_mayor, away, not_a_town_kind, council_said_no and can_sign's (the town treaty does not need
## reputation there).
static func order_propose_town(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not actor in Offices.holders(sim, "mayor"):
		return Orders.fail("not_the_mayor")
	if Region.is_away(st, actor):
		return Orders.fail("away")
	var kind := str(o.get("kind", ""))
	if not kind in (sim.catalog.trade.get("treaties", {}).get("town_kinds", []) as Array):
		return Orders.fail("not_a_town_kind")
	var fam := str(st.characters[actor].get("family", ""))
	var c := str(o.get("city", ""))
	var why := can_sign(sim, fam, c, kind, "", "town")
	if why != "":
		return Orders.fail(why)
	var v := council_vote(sim, actor)
	sim.events.append({"type": "council_voted", "actor": actor, "city": c, "kind": kind, "yes": v["yes"],
		"no": v["no"], "passed": v["passed"]})
	if not bool(v["passed"]):
		return Orders.fail("council_said_no")
	_sign(sim, fam, c, kind, "", "town", actor)
	Reputation.change(sim, fam, int(sim.catalog.trade.get("treaties", {}).get("town_reputation", 5)), "town_treaty")
	return Orders.ok()


## The council's vote on a mayor's treaty: the mayor yes; each councillor yes if its affinity with the mayor is at
## least council_yes_affinity. {yes, no, passed (yes >= no: the mayor breaks ties)}.
static func council_vote(sim: Sim, mayor: String) -> Dictionary:
	var need := int(sim.catalog.trade.get("treaties", {}).get("council_yes_affinity", 0))
	var yes := 1
	var no := 0
	for c: String in Offices.holders(sim, "councillor"):
		if c == mayor or c == "":
			continue
		if Courtship.affinity(sim.state, c, mayor) >= need:
			yes += 1
		else:
			no += 1
	if OS.is_debug_build():
		print("[Treaties] el concejo vota el tratado del alcalde %s: %d sí, %d no" % [mayor, yes, no])
	return {"yes": yes, "no": no, "passed": yes >= no}


## {"type": "cancel_treaty", "actor", "treaty"}: the head (or regent) ends one of its family's treaties early: broken.
## Reasons: unknown_treaty, not_the_head.
static func order_cancel(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
	for t: Dictionary in in_force(sim):
		if str(t["id"]) == str(o.get("treaty", "")) and str(t["family"]) == fam:
			if not _leads(sim, fam, actor) and not (str(t["scope"]) == "town" and actor in Offices.holders(sim, "mayor")):
				return Orders.fail("not_the_head")
			_break(sim, t, "cancelled")
			return Orders.ok()
	return Orders.fail("unknown_treaty")


## At a season start: quotas counted (broken if short), the rest kept, the expired ones end.
static func season(sim: Sim, day: int) -> void:
	var now := day * Clock.MINUTES_PER_DAY
	var rep: Dictionary = sim.catalog.trade.get("reputation", {})
	for t: Dictionary in in_force(sim).duplicate():
		if now <= int(t.get("first", t["start"])):
			continue  # the season it was signed in is not counted: its deliveries go to the first whole one
		if str(t["kind"]) == "quota" and int(t["delivered"]) < int(t["qty"]):
			_break(sim, t, "quota_short")
			continue
		t["delivered"] = 0
		if str(t["scope"]) == "family":
			Region.add_reputation(sim, str(t["city"]), str(t["family"]), int(rep.get("treaty_kept", 2)), "treaty_kept")
		if now >= int(t["end"]):
			in_force(sim).erase(t)
			sim.events.append({"type": "treaty_ended", "family": t["family"], "city": t["city"], "kind": t["kind"],
				"treaty": t["id"]})
			Notices.add(sim, str(t["family"]), Notices.INFO, "notice.treaty_ended", {"city":
				str(Region.settlement(sim, str(t["city"])).get("name_key", t["city"])), "treaty": "treaty." + str(t["kind"])})


static func _break(sim: Sim, t: Dictionary, reason: String) -> void:
	var fam := str(t["family"])
	var k: Dictionary = _kinds(sim).get(str(t["kind"]), {})
	var penalty := mini(int(k.get("penalty", 0)), maxi(0, Money.gold(sim.state, fam)))
	if penalty > 0:
		Money.change(sim, fam, -penalty, Money.FINES, "treaty_broken:" + str(t["id"]))
	if str(t["scope"]) == "family":
		Region.add_reputation(sim, str(t["city"]), fam,
			int(sim.catalog.trade.get("reputation", {}).get("treaty_broken", -10)), "treaty_broken")
	in_force(sim).erase(t)
	Region.stat(sim, fam, "treaties_broken")
	sim.events.append({"type": "treaty_broken", "family": fam, "city": t["city"], "kind": t["kind"], "treaty": t["id"],
		"reason": reason, "penalty": penalty})
	Notices.add(sim, fam, Notices.WARNING, "notice.treaty_broken", {"city":
		str(Region.settlement(sim, str(t["city"])).get("name_key", t["city"])), "treaty": "treaty." + str(t["kind"])})
	if OS.is_debug_build():
		print("[Treaties] se rompe %s (%s) de %s en %s: multa %d" % [t["id"], reason, fam, t["city"], penalty])
