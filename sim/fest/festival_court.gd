class_name FestivalCourt
extends RefCounted
## Fiestas (owner's decisions of 2026-11-05, 04f 4.25.2 and 4.25.5): what a feast asks the families to bring and who
## judges it. Driven by the feast's effects (data/festivals.json), with the figures in rules:
##   town_gift {hour}: the town's gift for the marquis. Families offer a piece (rules.gift.items) until `hour`; the mayor
##     chooses it (the player if the office is the player's, order festival_choose_gift; else, or if nobody chose, the
##     best by quality and then value). The town pays pay_mult of its value, reputation, relation with the council and
##     the chronicle (town_gift). The other offers go back when the feast ends.
##   audience {hour}: families with title >= rules.audience.min_title ask the marquis with a gift (kept by him) and a
##     Rhetoric roll; on success the privilege they asked (title_favour, exemption, minor_office); the chronicle.
##   contest {id, hour, prize, reputation}: the quality contest of the fair. Artisans present their best piece; the
##     highest quality wins (then value, then the first one in): prize, reputation, the chronicle (contest_won).
## And the AI families' sponsoring (rules.ai_sponsor): at most per_year big feasts a year, when their gold allows.
## State: in each instance, gift_offers [{family, actor, item, quality, from}], gift_choice (offer index, -1 = none),
## audience [{family, actor, item, quality, from, privilege}], contest [{family, actor, item, quality, from}], held
## [{family, item, quality, from}] (pieces to give back at the end); in festivals, ai_sponsored {fam: year}; in a
## family, privileges {title_favour {reputation_mult, gold_mult} | exemption {city, until}}. All of it optional fields
## of v18 (absent = empty).

const PRIV: Array[String] = ["title_favour", "exemption", "minor_office"]


static func _r(sim: Sim, k: String) -> Dictionary:
	return Festivals.rules(sim).get(k, {})


## The effect of `kind` of feast `inst` ({} if it has none).
static func effect(sim: Sim, inst: Dictionary, kind: String) -> Dictionary:
	for e: Dictionary in Festivals.def_of(sim, str(inst.get("def", ""))).get("effects", []):
		if str(e.get("kind", "")) == kind:
			return e
	return {}


static func _deadline(inst: Dictionary, e: Dictionary) -> int:
	return int(inst["day"]) * Festivals.MPD + int(e.get("hour", 12)) * 60


# --- Pieces -----------------------------------------------------------------------------------------------------------

## The value of a piece: base_price × the market's quality multiplier.
static func value(sim: Sim, item: String, quality: int) -> int:
	var qm: Array = sim.catalog.market.get("quality_mult", [1.0, 1.25, 1.6])
	return roundi(float(sim.catalog.item(item).get("base_price", 0)) * float(qm[clampi(quality, 0, qm.size() - 1)]))


## Where the family keeps pieces: the actor's bag first, then the family's buildings (sorted).
static func _sources(sim: Sim, fam: String, actor: String) -> Array:
	var out: Array = []
	if actor != "" and sim.state.characters.has(actor):
		out.append(actor)
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: Variant in ids:
		if Money.family_of(sim.state, str(b)) == fam and sim.state.buildings[b].get("inventory") is Dictionary:
			out.append(str(b))
	return out


## The best piece (quality, then value) of `fam` among `allowed` items ([] = any product or equipment with a market
## price): {item, quality, from} or {} if none. With item / quality given, that one (from the first source holding it).
static func best_piece(sim: Sim, fam: String, actor: String, allowed: Array, item: String = "", quality: int = -1) -> Dictionary:
	var best := {}
	var best_key := -1
	for src: String in _sources(sim, fam, actor):
		var inv := sim.state.inventory_of(src)
		for s: Dictionary in inv.get("stacks", []):
			var it := str(s.get("item", ""))
			var q := int(s.get("quality", 0))
			if int(s.get("qty", 0)) <= 0 or (item != "" and it != item) or (quality >= 0 and q != quality):
				continue
			if not allowed.is_empty() and not it in allowed:
				continue
			var cat := str(sim.catalog.item(it).get("category", ""))
			if allowed.is_empty() and not cat in ["product", "equipment"]:
				continue
			var key := q * 1000000 + value(sim, it, q)
			if key > best_key:
				best_key = key
				best = {"item": it, "quality": q, "from": src}
	return best


## Takes the piece out of its source into the feast (held until it ends). False if it is not there any more.
static func _hold(sim: Sim, inst: Dictionary, fam: String, p: Dictionary) -> bool:
	var inv := sim.state.inventory_of(str(p.get("from", "")))
	if inv.is_empty() or Inventory.count(inv, str(p["item"]), int(p["quality"])) < 1:
		return false
	Inventory.remove(inv, str(p["item"]), int(p["quality"]), 1)
	if not inst.get("held") is Array:
		inst["held"] = []
	(inst["held"] as Array).append({"family": fam, "item": str(p["item"]), "quality": int(p["quality"]),
		"from": str(p["from"])})
	return true


## A held piece leaves for good (the chosen gift, the audience's gift): it is not given back.
static func _consume(inst: Dictionary, fam: String, item: String, quality: int) -> void:
	var held: Array = inst.get("held", [])
	for i: int in held.size():
		var h: Dictionary = held[i]
		if str(h["family"]) == fam and str(h["item"]) == item and int(h["quality"]) == quality:
			held.remove_at(i)
			return


## At the end of the feast the pieces still held go back where they came from (or to the family's first building).
static func give_back(sim: Sim, inst: Dictionary) -> void:
	for h: Dictionary in inst.get("held", []):
		var fam := str(h["family"])
		var dest := str(h["from"])
		var inv := sim.state.inventory_of(dest)
		if inv.is_empty() or not Inventory.can_add(inv, sim.catalog, str(h["item"]), int(h["quality"]), 1):
			for src: String in _sources(sim, fam, ""):
				var other := sim.state.inventory_of(src)
				if Inventory.can_add(other, sim.catalog, str(h["item"]), int(h["quality"]), 1):
					inv = other
					break
		if not inv.is_empty() and Inventory.can_add(inv, sim.catalog, str(h["item"]), int(h["quality"]), 1):
			Inventory.add(inv, sim.catalog, str(h["item"]), int(h["quality"]), 1)
	inst["held"] = []


# --- Orders -----------------------------------------------------------------------------------------------------------

static func _common(sim: Sim, o: Dictionary, kind: String) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var why := Festivals._actor_reason(sim, actor)
	if why != "":
		return {"fail": why}
	var inst := Festivals.find(sim, str(o.get("festival", "")))
	if inst.is_empty() or not bool(inst.get("announced", false)) or int(inst["end"]) <= int(sim.state.clock["minute"]):
		return {"fail": "unknown_festival"}
	var e := effect(sim, inst, kind)
	if e.is_empty():
		return {"fail": "not_in_this_festival"}
	if int(sim.state.clock["minute"]) >= _deadline(inst, e):
		return {"fail": "too_late"}
	return {"actor": actor, "fam": str(sim.state.characters[actor].get("family", "")), "inst": inst, "e": e}


static func _entered(list: Array, fam: String) -> bool:
	for x: Dictionary in list:
		if str(x.get("family", "")) == fam:
			return true
	return false


## {"type": "festival_offer_gift", "actor", "festival", "item"?, "quality"?}: offers a piece for the town's gift (the
## best the family has of rules.gift.items without item). Reasons: festivals_off, unknown_festival,
## not_in_this_festival, too_late, already_offered, no_piece.
static func order_offer_gift(sim: Sim, o: Dictionary) -> Dictionary:
	var c := _common(sim, o, "town_gift")
	if c.has("fail"):
		return Orders.fail(str(c["fail"]))
	var inst: Dictionary = c["inst"]
	if not inst.get("gift_offers") is Array:
		inst["gift_offers"] = []
	if _entered(inst["gift_offers"], str(c["fam"])):
		return Orders.fail("already_offered")
	var p := best_piece(sim, str(c["fam"]), str(c["actor"]), _r(sim, "gift").get("items", []), str(o.get("item", "")),
		int(o.get("quality", -1)))
	if p.is_empty() or not _hold(sim, inst, str(c["fam"]), p):
		return Orders.fail("no_piece")
	(inst["gift_offers"] as Array).append({"family": str(c["fam"]), "actor": str(c["actor"]), "item": str(p["item"]),
		"quality": int(p["quality"]), "value": value(sim, str(p["item"]), int(p["quality"]))})
	sim.events.append({"type": "festival_gift_offered", "festival": str(inst["id"]), "family": str(c["fam"]),
		"item": str(p["item"]), "quality": int(p["quality"])})
	if OS.is_debug_build():
		print("[FestivalCourt] %s ofrece %s (calidad %d) como regalo de la villa en %s" % [c["fam"], p["item"],
			int(p["quality"]), inst["id"]])
	return Orders.ok()


## {"type": "festival_choose_gift", "actor", "festival", "offer"}: the mayor chooses the town's gift (an index of the
## offers) before its hour. Reasons: not_the_mayor, bad_offer and the common ones.
static func order_choose_gift(sim: Sim, o: Dictionary) -> Dictionary:
	var c := _common(sim, o, "town_gift")
	if c.has("fail"):
		return Orders.fail(str(c["fail"]))
	if mayor(sim) != str(c["actor"]):
		return Orders.fail("not_the_mayor")
	var inst: Dictionary = c["inst"]
	var i := int(o.get("offer", -1))
	if i < 0 or i >= (inst.get("gift_offers", []) as Array).size():
		return Orders.fail("bad_offer")
	inst["gift_choice"] = i
	sim.events.append({"type": "festival_gift_picked", "festival": str(inst["id"]), "offer": i})
	return Orders.ok()


## {"type": "festival_audience", "actor", "festival", "privilege", "item"?, "quality"?}: asks the marquis for an
## audience with a gift. Reasons: title_too_low, bad_privilege, already_asked, no_piece and the common ones.
static func order_audience(sim: Sim, o: Dictionary) -> Dictionary:
	var c := _common(sim, o, "audience")
	if c.has("fail"):
		return Orders.fail(str(c["fail"]))
	var fam := str(c["fam"])
	if not title_ok(sim, fam):
		return Orders.fail("title_too_low")
	var priv := str(o.get("privilege", ""))
	if not priv in privileges_open(sim):
		return Orders.fail("bad_privilege")
	var inst: Dictionary = c["inst"]
	if not inst.get("audience") is Array:
		inst["audience"] = []
	if _entered(inst["audience"], fam):
		return Orders.fail("already_asked")
	var p := best_piece(sim, fam, str(c["actor"]), _r(sim, "gift").get("items", []), str(o.get("item", "")),
		int(o.get("quality", -1)))
	if p.is_empty() or not _hold(sim, inst, fam, p):
		return Orders.fail("no_piece")
	(inst["audience"] as Array).append({"family": fam, "actor": str(c["actor"]), "item": str(p["item"]),
		"quality": int(p["quality"]), "privilege": priv})
	sim.events.append({"type": "festival_audience_asked", "festival": str(inst["id"]), "family": fam, "privilege": priv})
	return Orders.ok()


## {"type": "festival_enter_contest", "actor", "festival", "item"?, "quality"?}: presents a piece to the quality
## contest. Reasons: already_entered, no_piece and the common ones.
static func order_enter_contest(sim: Sim, o: Dictionary) -> Dictionary:
	var c := _common(sim, o, "contest")
	if c.has("fail"):
		return Orders.fail(str(c["fail"]))
	var inst: Dictionary = c["inst"]
	if not inst.get("contest") is Array:
		inst["contest"] = []
	if _entered(inst["contest"], str(c["fam"])):
		return Orders.fail("already_entered")
	var trade := trade_items(sim, str(c["fam"]))  # a piece of its own trade (owner: «cada oficio presenta una pieza»)
	var p := {} if trade.is_empty() else best_piece(sim, str(c["fam"]), str(c["actor"]), trade, str(o.get("item", "")),
		int(o.get("quality", -1)))
	if p.is_empty() or not _hold(sim, inst, str(c["fam"]), p):
		return Orders.fail("no_piece")
	(inst["contest"] as Array).append({"family": str(c["fam"]), "actor": str(c["actor"]), "item": str(p["item"]),
		"quality": int(p["quality"]), "value": value(sim, str(p["item"]), int(p["quality"]))})
	sim.events.append({"type": "festival_contest_entered", "festival": str(inst["id"]), "family": str(c["fam"]),
		"item": str(p["item"]), "quality": int(p["quality"])})
	return Orders.ok()


# --- Who and what ---------------------------------------------------------------------------------------------------

## The pieces of the family's trade: the outputs of the recipes of the workshops it owns (not houses), sorted.
static func trade_items(sim: Sim, fam: String) -> Array:
	var types := {}
	for b: Variant in sim.state.buildings:
		if Money.family_of(sim.state, str(b)) == fam:
			types[str(sim.state.buildings[b].get("type", ""))] = true
	var out: Array = []
	for rid: String in Festivals._sorted_keys(sim.catalog.recipes()):
		var r: Dictionary = sim.catalog.recipes()[rid]
		var it := str(r.get("output", {}).get("item", ""))
		if types.has(str(r.get("building", ""))) and it != "" and not it in out \
				and str(sim.catalog.item(it).get("category", "")) in ["product", "equipment", "tool"]:
			out.append(it)
	out.sort()
	return out


## The mayor's character ("" if the office is vacant or there is none).
static func mayor(sim: Sim) -> String:
	for o: String in Festivals._sorted_keys(sim.state.offices):
		if str(sim.catalog.offices().get(o, {}).get("rank", "")) == "mayor":
			var h := Offices.holders(sim, o)
			return str(h[0]) if not h.is_empty() else ""
	return ""


static func title_ok(sim: Sim, fam: String) -> bool:
	var ladder := sim.catalog.title_ladder()
	var want := ladder.find(str(_r(sim, "audience").get("min_title", "citizen")))
	return want >= 0 and ladder.find(Titles.current(sim, fam)) >= want


## The privileges the marquis may grant now: title_favour and exemption always, minor_office while a minor seat is free.
static func privileges_open(sim: Sim) -> Array:
	var out: Array = []
	var cfg: Dictionary = _r(sim, "audience").get("privileges", {})
	for p: String in PRIV:
		if not cfg.has(p):
			continue
		if p == "minor_office" and _vacant_minor(sim).is_empty():
			continue
		out.append(p)
	return out


static func _vacant_minor(sim: Sim) -> Dictionary:
	for o: String in sim.catalog.office_chart():
		if str(sim.catalog.offices()[o].get("rank", "")) != "minor" or not sim.state.offices.has(o):
			continue
		var seats: Array = sim.state.offices[o].get("seats", [])
		for i: int in seats.size():
			if str(seats[i].get("holder", "")) == "":
				return {"office": o, "index": i}
	return {}


# --- Resolution (Festivals._tick, at each effect's hour) --------------------------------------------------------------

static func tick(sim: Sim, inst: Dictionary, now: int) -> void:
	var g := effect(sim, inst, "town_gift")  # an hour before, the mayor is asked to choose (the card)
	if not g.is_empty() and now >= _deadline(inst, g) - 60 and not "gift_call" in (inst["done"] as Array):
		(inst["done"] as Array).append("gift_call")
		if not (inst.get("gift_offers", []) as Array).is_empty():
			sim.events.append({"type": "festival_gift_offers", "festival": str(inst["id"]), "def": str(inst["def"]),
				"mayor": mayor(sim), "offers": (inst["gift_offers"] as Array).size()})
	var cq := effect(sim, inst, "contest")  # a workshop that had no piece at the start brings one when it has it
	if not cq.is_empty() and now % 60 == 0 and now > int(inst.get("start", 0)) and now < _deadline(inst, cq):
		ai_entries(sim, inst, "start")
	for kind: String in ["town_gift", "audience", "contest"]:
		var e := effect(sim, inst, kind)
		if e.is_empty():
			continue
		var key := "%s@%d" % [kind, int(e.get("hour", 12))]
		if now < _deadline(inst, e) or key in (inst["done"] as Array):
			continue
		(inst["done"] as Array).append(key)
		match kind:
			"town_gift":
				_choose_gift(sim, inst)
			"audience":
				_audiences(sim, inst)
			"contest":
				_judge(sim, inst, e)


## The AI families bring their pieces: the gift and the audience's gift when the feast is announced, the contest's
## piece when the feast starts (`at`: eve | start), so a workshop's stock is not held longer than the feast, or later
## (every hour until the judging, tick) when it had none then.
static func ai_entries(sim: Sim, inst: Dictionary, at: String = "eve") -> void:
	var kinds: Array = []
	for k: String in (["town_gift", "audience"] if at == "eve" else ["contest"]):
		if not effect(sim, inst, k).is_empty():
			kinds.append(k)
	if kinds.is_empty():
		return
	for fam: String in Festivals._sorted_keys(sim.state.families):
		var f: Dictionary = sim.state.families[fam]
		if str(f.get("ai_profile", "")) == "" or str(f.get("controlled_by", "")) == "human":
			continue
		var head := Kin.head(sim.state, fam)
		if head == "" or Region.is_away(sim.state, head):
			continue
		var gifts: Array = _r(sim, "gift").get("items", [])
		for k: String in kinds:  # only what it can bring: a refused order is a bug, not a choice
			match k:
				"town_gift":
					if not best_piece(sim, fam, head, gifts).is_empty():
						sim.give({"type": "festival_offer_gift", "actor": head, "festival": str(inst["id"])})
				"audience":
					if title_ok(sim, fam) and not privileges_open(sim).is_empty() \
							and not best_piece(sim, fam, head, gifts).is_empty():
						sim.give({"type": "festival_audience", "actor": head, "festival": str(inst["id"]),
							"privilege": str(privileges_open(sim)[0])})
				"contest":
					if not _entered(inst.get("contest", []), fam) and not trade_items(sim, fam).is_empty() \
							and not best_piece(sim, fam, head, trade_items(sim, fam)).is_empty():
						sim.give({"type": "festival_enter_contest", "actor": head, "festival": str(inst["id"])})


static func _rank_key(o: Dictionary) -> int:
	return int(o.get("quality", 0)) * 1000000 + int(o.get("value", 0))


static func _choose_gift(sim: Sim, inst: Dictionary) -> void:
	var offers: Array = inst.get("gift_offers", [])
	if offers.is_empty():
		return
	var pick := int(inst.get("gift_choice", -1))
	var by := "best"
	if pick < 0 or pick >= offers.size():
		pick = 0
		for i: int in offers.size():
			if _rank_key(offers[i]) > _rank_key(offers[pick]):
				pick = i
	else:
		by = "mayor"
	var o: Dictionary = offers[pick]
	var fam := str(o["family"])
	var cfg := _r(sim, "gift")
	var pay := roundi(float(o.get("value", 0)) * float(cfg.get("pay_mult", 1.5)))
	_consume(inst, fam, str(o["item"]), int(o["quality"]))
	Money.change(sim, fam, pay, Money.EVENTS, str(inst["id"]), "", str(o.get("actor", "")))
	Reputation.change(sim, fam, int(cfg.get("reputation", 8)), "festival_town_gift")
	var rel: Dictionary = sim.state.contracts["relations"]
	var key := "%s|town_council" % fam
	rel[key] = int(rel.get(key, 0)) + int(cfg.get("relation", 15))
	inst["gift_winner"] = pick
	Chronicle.add(sim.state, "town_gift", {"family": fam, "character": str(o.get("actor", "")), "item": str(o["item"]),
		"quality": int(o["quality"]), "festival": str(inst["def"]), "by": by})
	sim.events.append({"type": "festival_gift_chosen", "festival": str(inst["id"]), "def": str(inst["def"]),
		"family": fam, "item": str(o["item"]), "quality": int(o["quality"]), "pay": pay, "by": by,
		"offers": offers.size()})
	for f: String in Festivals._humans(sim.state):
		Notices.add(sim, f, Notices.INFO, "notice.festival_gift_chosen", {"family": str(sim.state.families.get(fam, {}).get(
			"name", "")), "item": str(o["item"])})
	if OS.is_debug_build():
		print("[FestivalCourt] regalo de la villa: %s de %s (calidad %d, %d ofertas, elige %s), paga %d" % [o["item"], fam,
			int(o["quality"]), offers.size(), by, pay])


static func _audiences(sim: Sim, inst: Dictionary) -> void:
	var cfg := _r(sim, "audience")
	for a: Dictionary in inst.get("audience", []):
		var fam := str(a["family"])
		var actor := str(a.get("actor", ""))
		var rh := int(sim.state.characters.get(actor, {}).get("stats", {}).get("rhetoric", 0))
		var v := value(sim, str(a["item"]), int(a["quality"]))
		var p := clampf(float(cfg.get("base", 0.2)) + float(cfg.get("per_rhetoric", 0.06)) * rh
			+ float(cfg.get("per_value", 0.0015)) * v, 0.0, float(cfg.get("max", 0.9)))
		var roll := Kin.roll(sim.state, "fst|aud|%s|%s" % [inst["id"], fam])
		var ok := roll < p
		_consume(inst, fam, str(a["item"]), int(a["quality"]))  # the marquis keeps the gift
		var got := ""
		if ok:
			got = _grant(sim, fam, actor, str(a.get("privilege", "")))
			Reputation.change(sim, fam, int(cfg.get("success_reputation", 5)), "festival_audience")
		else:
			Reputation.change(sim, fam, int(cfg.get("fail_reputation", 0)), "festival_audience")
		Chronicle.add(sim.state, "audience", {"family": fam, "character": actor, "festival": str(inst["def"]),
			"granted": got, "item": str(a["item"])})
		sim.events.append({"type": "festival_audience", "festival": str(inst["id"]), "def": str(inst["def"]),
			"family": fam, "actor": actor, "chance": p, "granted": got, "asked": str(a.get("privilege", ""))})
		if str(sim.state.families.get(fam, {}).get("controlled_by", "")) == "human":
			Notices.add(sim, fam, Notices.INFO, "notice.festival_audience_ok" if got != "" else "notice.festival_audience_no",
				{"privilege": got if got != "" else str(a.get("privilege", ""))}, actor)
		if OS.is_debug_build():
			print("[FestivalCourt] audiencia de %s: %.2f contra %.2f -> %s" % [fam, roll, p, got if got != "" else "nada"])


## Grants privilege `priv` (falls back to title_favour if it cannot be given now). Returns what was granted.
static func _grant(sim: Sim, fam: String, actor: String, priv: String) -> String:
	var cfg: Dictionary = _r(sim, "audience").get("privileges", {})
	var f: Dictionary = sim.state.families[fam]
	if not f.get("privileges") is Dictionary:
		f["privileges"] = {}
	if priv == "minor_office":
		var seat := _vacant_minor(sim)
		if not seat.is_empty() and sim.state.characters.has(actor):
			Offices.take(sim, str(seat["office"]), int(seat["index"]), actor)
			return priv
		priv = "title_favour"
	if priv == "exemption":
		var e: Dictionary = cfg.get("exemption", {})
		f["privileges"]["exemption"] = {"city": str(e.get("city", "capital")),
			"until": int(sim.state.clock["minute"]) + int(e.get("days", 8)) * Festivals.MPD}
		return priv
	var t: Dictionary = cfg.get("title_favour", {})
	f["privileges"]["title_favour"] = {"reputation_mult": float(t.get("reputation_mult", 0.8)),
		"gold_mult": float(t.get("gold_mult", 0.5))}
	return "title_favour"


static func _judge(sim: Sim, inst: Dictionary, e: Dictionary) -> void:
	var entries: Array = inst.get("contest", [])
	if entries.is_empty():
		return
	var win := 0
	for i: int in entries.size():
		if _rank_key(entries[i]) > _rank_key(entries[win]):
			win = i
	var w: Dictionary = entries[win]
	var fam := str(w["family"])
	if int(e.get("prize", 0)) > 0:
		Money.change(sim, fam, int(e.get("prize", 0)), Money.EVENTS, str(inst["id"]), "", str(w.get("actor", "")))
	# The prize is fame and reputation (owner, 2026-11-05): reputation, the fame among the artisans (the class modifier
	# of 4.12.1) and a contest won on the workshop (what the workshop's fame of 04g 4.6.5.7 will count).
	Reputation.change(sim, fam, int(e.get("reputation", 6)), "festival_contest", str(e.get("fame_class", "artisan")),
		int(e.get("fame", 10)))
	var src := str(w.get("from", ""))
	for h: Dictionary in inst.get("held", []):
		if str(h["family"]) == fam and str(h["item"]) == str(w["item"]) and int(h["quality"]) == int(w["quality"]):
			src = str(h["from"])
	if not sim.state.buildings.has(src):
		for b: String in Titles.business_ids(sim, fam):
			src = b
			break
	if sim.state.buildings.has(src):
		sim.state.buildings[src]["contests_won"] = int(sim.state.buildings[src].get("contests_won", 0)) + 1
	inst["contest_winner"] = win
	Chronicle.add(sim.state, "contest_won", {"family": fam, "character": str(w.get("actor", "")), "item": str(w["item"]),
		"quality": int(w["quality"]), "festival": str(inst["def"]), "entries": entries.size()})
	sim.events.append({"type": "festival_contest", "festival": str(inst["id"]), "def": str(inst["def"]), "family": fam,
		"item": str(w["item"]), "quality": int(w["quality"]), "prize": int(e.get("prize", 0)), "fame": int(e.get("fame", 10)),
		"reputation": int(e.get("reputation", 6)), "entries": entries.size()})
	for f: String in Festivals._humans(sim.state):
		Notices.add(sim, f, Notices.INFO, "notice.festival_contest_won", {"family": str(sim.state.families.get(fam, {}).get(
			"name", "")), "item": str(w["item"])})
	if OS.is_debug_build():
		print("[FestivalCourt] concurso: gana %s con %s (calidad %d) entre %d" % [fam, w["item"], int(w["quality"]),
			entries.size()])


# --- The AI's sponsoring (04c's reputation use) ------------------------------------------------------------------------

## On the crier of a big feast: each AI family with a profile that has not sponsored this year, whose gold allows it,
## rolls; if it goes, it pays the first part nobody pays yet (the same order as the player's).
static func ai_sponsor(sim: Sim, inst: Dictionary) -> void:
	var d := Festivals.def_of(sim, str(inst["def"]))
	if str(d.get("size", "")) != "big":
		return
	var cfg := _r(sim, "ai_sponsor")
	var year := Clock.year(int(sim.state.clock["minute"]), sim.catalog.time)
	var book: Dictionary = sim.state.festivals.get("ai_sponsored", {})
	for fam: String in Festivals._sorted_keys(sim.state.families):
		var f: Dictionary = sim.state.families[fam]
		var prof := str(f.get("ai_profile", ""))
		if prof == "" or str(f.get("controlled_by", "")) == "human":
			continue
		if int(book.get(fam + "|" + str(year), 0)) >= int(cfg.get("per_year", 1)):
			continue
		var part := ""
		for p: Variant in cfg.get("parts", []):
			if str(p) in Festivals.sponsor_parts(sim, inst) and Festivals.part_taken_by(inst, str(p)) == "":
				part = str(p)
				break
		if part == "":
			return
		var cost := int(Festivals.rules(sim).get("sponsor", {}).get("parts", {}).get(part, {}).get("gold", 0))
		var reserve := RivalAI.upkeep_reserve(sim, fam, sim.catalog.ai_profiles().get(prof, {})) \
			+ int(cfg.get("spare", 150))  # the same reserve as a festival contract (4.25.4), and a spare
		if Money.gold(sim.state, fam) - cost < reserve:
			continue
		if Kin.roll(sim.state, "fst|aisp|%s|%s" % [inst["id"], fam]) >= float(cfg.get("chance", 0.6)):
			continue
		var head := Kin.head(sim.state, fam)
		if head == "":
			continue
		sim.give({"type": "festival_sponsor", "actor": head, "festival": str(inst["id"]), "part": part})
		if Festivals.part_taken_by(inst, part) == fam:
			book[fam + "|" + str(year)] = int(book.get(fam + "|" + str(year), 0)) + 1
			sim.state.festivals["ai_sponsored"] = book
			for h: String in Festivals._humans(sim.state):  # the player sees it and may bid (owner, 2026-11-05)
				Notices.add(sim, h, Notices.INFO, "notice.festival_ai_sponsored", {"family": str(f.get("name", "")),
					"part": part, "festival": str(inst["def"]), "gold": Festivals.bid_price(sim, inst, part)})
			if OS.is_debug_build():
				print("[FestivalCourt] %s (IA) patrocina %s de %s" % [fam, part, inst["id"]])


# --- Privileges read by other systems -----------------------------------------------------------------------------------

## The title favour of `fam` (title_favour privilege): {reputation_mult, gold_mult}, both 1 without it.
static func title_mults(st: WorldState, fam: String) -> Dictionary:
	var p: Variant = st.families.get(fam, {}).get("privileges", {})
	if p is Dictionary and (p as Dictionary).get("title_favour") is Dictionary:
		return p["title_favour"]
	return {"reputation_mult": 1.0, "gold_mult": 1.0}


## The title favour is spent on the next title.
static func spend_title_favour(st: WorldState, fam: String) -> void:
	var p: Variant = st.families.get(fam, {}).get("privileges", {})
	if p is Dictionary:
		(p as Dictionary).erase("title_favour")


## Whether `fam` has the marquis's exemption in city `c` now.
static func exempt(sim: Sim, c: String, fam: String) -> bool:
	var p: Variant = sim.state.families.get(fam, {}).get("privileges", {})
	if not p is Dictionary or not (p as Dictionary).get("exemption") is Dictionary:
		return false
	var e: Dictionary = p["exemption"]
	return str(e.get("city", "")) == c and int(e.get("until", 0)) > int(sim.state.clock["minute"])
