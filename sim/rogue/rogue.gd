class_name Rogue
extends RefCounted
## The Rogue's first trade, the thief (docs/gdd/04d_otras_clases.md §4.22.6.4; O2 a): picking a purse by day, robbing
## a storage at night, stolen goods (<item>@stolen), the fence, laundering and the fame in the underworld. Figures in
## data/rogue.json; rolls with SkillCheck and their own keys (`rogue|...`), so nothing else's dice move.
##
## - pickpocket {actor, target}: DAY or DUSK, at `range` of a person of another family (not a guard), once a day each
##   victim. Success: the purse (a townsperson or a visitor: loot from outside; a playing family: min(base + dexterity;
##   share of its gold), taken from it). Failure: the victim sees him (relation, a public fact «petty_theft» against his
##   family) and cries; a guard in view arrests him (a trial, source «arrest»).
## - burgle {actor, building}: NIGHT, at the door of a building of another family with a storage. Lock = base + per level
##   of its Security; success = SkillCheck(stealth, lock) + lockpicks. Loot: the most valuable units into his bag as
##   <item>@stolen, up to units_base + dexterity / 2 and his weight. Failure: noise; a guard in view arrests him.
## - fence_sell {actor, item, quality, qty}: stolen goods sold to the fence (his own den, or the tavern at night) at a
##   share of the market's price, up to the town's daily cap (state.town.rogue.fence).
## - launder {actor, building, item, quality}: at his den, one unit loses its mark after launder.minutes.
## State (read with defaults, no save version): families[fam].underworld; buildings[b].burgled_until and .laundering;
## state.town.rogue {day, picked: [victims], fails, fence_paid}.


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.rogue


static func _c(sim: Sim, part: String) -> Dictionary:
	return (cfg(sim).get(part, {}) as Dictionary)


# --- Stolen goods ------------------------------------------------------------------------------------------------------

static func stolen(item: String) -> String:
	return item if item.ends_with(Catalog.STOLEN) else item + Catalog.STOLEN


static func is_stolen(item: String) -> bool:
	return item.ends_with(Catalog.STOLEN)


static func clean(item: String) -> String:
	return item.trim_suffix(Catalog.STOLEN)


# --- The underworld ----------------------------------------------------------------------------------------------------

static func underworld(st: WorldState, fam: String) -> int:
	return int(st.families.get(fam, {}).get("underworld", 0))


static func add_underworld(sim: Sim, fam: String, amount: int, why: String) -> void:
	if not sim.state.families.has(fam) or amount == 0:
		return
	var f: Dictionary = sim.state.families[fam]
	f["underworld"] = clampi(int(f.get("underworld", 0)) + amount, 0, 100)
	sim.events.append({"type": "underworld_changed", "family": fam, "amount": amount, "underworld": int(f["underworld"]),
		"reason": why})


## The family's den (the first building of type den it owns, sorted), or "".
static func den_of(st: WorldState, fam: String) -> String:
	for b: String in Festivals._sorted_keys(st.buildings):
		if str(st.buildings[b].get("type", "")) == "den" and Money.family_of(st, b) == fam:
			return b
	return ""


# --- Day book of the town ----------------------------------------------------------------------------------------------

static func _book(sim: Sim) -> Dictionary:
	var st := sim.state
	if not st.town.get("rogue") is Dictionary:
		st.town["rogue"] = {}
	var b: Dictionary = st.town["rogue"]
	var today := Clock.day(int(st.clock["minute"]))
	if int(b.get("day", -1)) != today:
		b["day"] = today
		b["picked"] = []
		b["fails"] = 0
		b["fence_paid"] = 0
	return b


static func _phase(sim: Sim) -> String:
	return Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time)


static func _fam(st: WorldState, chr: String) -> String:
	return str(st.characters.get(chr, {}).get("family", ""))


static func _playing(st: WorldState, fam: String) -> bool:
	var f: Dictionary = st.families.get(fam, {})
	return str(f.get("controlled_by", "")) == "human" or str(f.get("ai_profile", "")) != ""


static func _outdoors(st: WorldState, chr: String) -> bool:
	var ch: Dictionary = st.characters.get(chr, {})
	return not ch.is_empty() and bool(ch.get("alive", true)) and str(ch.get("location", "")) == "" \
		and not Region.is_away(st, chr)


# --- Witnesses ---------------------------------------------------------------------------------------------------------

## The guard on duty who sees `tile` now (the nearest within view: view_day by day, view_night by night), or "".
static func guard_in_view(sim: Sim, tile: Array) -> String:
	var st := sim.state
	var w := _c(sim, "witness")
	var view := int(w.get("view_night", 5)) if _phase(sim) in ["night", "dusk"] else int(w.get("view_day", 8))
	var best := ""
	var best_d := 1 << 20
	for g: String in Watch.guards(st):
		if not _outdoors(st, g):
			continue
		var d := Life.dist(Life.tile_of(st, g), tile)
		if d <= view and (d < best_d or (d == best_d and g < best)):
			best = g
			best_d = d
	return best


## A guard caught `actor` (crime `charge`, fact `fact_id`). A family played by a person gets the arrest card
## (4.22.6.3: arrest_response within arrest.minutes; unanswered, surrender); anybody else surrenders at once. Returns
## the trial id when tried now ("" while the card waits).
static func caught(sim: Sim, actor: String, guard: String, charge: String, fact_id: String) -> String:
	var st := sim.state
	var fam := _fam(st, actor)
	if str(st.families.get(fam, {}).get("controlled_by", "")) != "human":
		return arrest(sim, actor, guard, charge, fact_id)
	var b := _book(sim)
	if not b.get("arrests") is Dictionary:
		b["arrests"] = {}
	var until := int(st.clock["minute"]) + int(_c(sim, "arrest").get("minutes", 30))
	(b["arrests"] as Dictionary)[actor] = {"guard": guard, "charge": charge, "fact": fact_id, "until": until}
	sim.events.append({"type": "rogue_arrest_card", "actor": actor, "family": fam, "guard": guard, "charge": charge,
		"until": until})
	Notices.add(sim, fam, Notices.URGENT, "notice.rogue_caught", {"name": str(st.characters[actor].get("name", "")),
		"charge": charge}, actor)
	return ""


## The arrest waiting for `actor`'s answer ({} if none).
static func pending_arrest(st: WorldState, actor: String) -> Dictionary:
	var b: Variant = st.town.get("rogue")
	return ((b as Dictionary).get("arrests", {}) as Dictionary).get(actor, {}) if b is Dictionary else {}


## The chance (0-1) of each answer to the arrest of `actor` by `guard`: flee (dexterity against the guard's), bribe
## (negotiation against arrest.bribe_against) and its price; fight is a duel (its odds are the duel's).
static func arrest_odds(sim: Sim, actor: String, guard: String) -> Dictionary:
	var a := _c(sim, "arrest")
	var price := int(a.get("bribe_base", 20)) + int(a.get("bribe_per_negotiation", 5)) * SkillCheck.stat(sim, guard, "negotiation")
	return {"flee": SkillCheck.chance(sim, SkillCheck.stat(sim, actor, "dexterity"), SkillCheck.stat(sim, guard, "dexterity")),
		"bribe": SkillCheck.chance(sim, SkillCheck.stat(sim, actor, "negotiation"), int(a.get("bribe_against", 5))),
		"bribe_price": price}


## {"type": "arrest_response", "actor", "choice": surrender | flee | fight | bribe} (4.22.6.3).
static func order_arrest_response(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var p := pending_arrest(st, actor)
	if p.is_empty():
		return Orders.fail("no_arrest")
	var choice := str(o.get("choice", "surrender"))
	if not choice in ["surrender", "flee", "fight", "bribe"]:
		return Orders.fail("bad_choice")
	var fam := _fam(st, actor)
	var guard := str(p["guard"])
	var a := _c(sim, "arrest")
	var odds := arrest_odds(sim, actor, guard)
	if choice == "bribe" and not Money.can_pay(st, fam, int(odds["bribe_price"])):
		return Orders.fail("not_enough_gold")
	((st.town["rogue"] as Dictionary)["arrests"] as Dictionary).erase(actor)
	var now := int(st.clock["minute"])
	var out := "tried"
	match choice:
		"surrender":
			arrest(sim, actor, guard, str(p["charge"]), str(p["fact"]))
		"flee":
			var r := SkillCheck.roll(sim, "rogue|flee|%s|%d" % [actor, now], SkillCheck.stat(sim, actor, "dexterity"),
				SkillCheck.stat(sim, guard, "dexterity"))
			if bool(r["success"]):
				out = "escaped"  # the fact stays public: he may be accused of it
			else:
				Tribunal.add_fact(sim, "resisting", fam, actor, "resisting")
				arrest(sim, actor, guard, str(p["charge"]), str(p["fact"]))
		"fight":
			var res := Duel.auto(sim.catalog.combat, "rogue|fight|%s|%d" % [actor, now], st.world_seed,
				Duels.fighter_of(sim, actor), Duels.fighter_of(sim, guard), str(a.get("duel_kind", "first_blood")))
			if int(res["winner"]) == 0:
				out = "escaped"
				Tribunal.add_fact(sim, "violent_crime", fam, actor, "violent_crime")
			else:
				Emotions.add(sim, actor, "scared", "arrest")
				arrest(sim, actor, guard, str(p["charge"]), str(p["fact"]))
		"bribe":
			Money.change(sim, fam, -int(odds["bribe_price"]), Money.FINES, "bribe", "", actor)
			var r := SkillCheck.roll(sim, "rogue|bribe|%s|%d" % [actor, now], SkillCheck.stat(sim, actor, "negotiation"),
				int(a.get("bribe_against", 5)))
			if bool(r["success"]):
				out = "bribed"  # he lets him go and does not report it: the fact leaves the book
				var f := Tribunal.fact(st, str(p["fact"]))
				if not f.is_empty():
					f["public"] = false
					f["tried"] = true
			else:
				Tribunal.add_fact(sim, "bribery", fam, actor, "bribery")
				arrest(sim, actor, guard, str(p["charge"]), str(p["fact"]))
	sim.events.append({"type": "arrest_answered", "actor": actor, "family": fam, "choice": choice, "outcome": out})
	if OS.is_debug_build():
		print("[Rogue] %s responde a la detención: %s -> %s" % [actor, choice, out])
	return Orders.ok()


## Every minute: an arrest card unanswered in time is a surrender.
static func _arrest_timeouts(sim: Sim) -> void:
	var b: Variant = sim.state.town.get("rogue")
	if not b is Dictionary or not (b as Dictionary).get("arrests") is Dictionary:
		return
	var now := int(sim.state.clock["minute"])
	for actor: String in Festivals._sorted_keys((b as Dictionary)["arrests"]):
		var p: Dictionary = (b as Dictionary)["arrests"][actor]
		if now >= int(p["until"]):
			order_arrest_response(sim, {"actor": actor, "choice": "surrender"})


## A guard saw `actor` commit `charge` (fact `fact_id`): he is arrested and tried (source «arrest»; the guard the
## witness). What he carries stolen is seized. Returns the trial id.
static func arrest(sim: Sim, actor: String, guard: String, charge: String, fact_id: String) -> String:
	var st := sim.state
	var fam := _fam(st, actor)
	var inv: Dictionary = st.characters[actor].get("inventory", {})
	var seized := 0
	for s: Dictionary in (inv.get("stacks", []) as Array).duplicate():
		if is_stolen(str(s["item"])):
			seized += int(s["qty"])
			Inventory.remove(inv, str(s["item"]), int(s["quality"]), int(s["qty"]))
	var tid := Tribunal.open(sim, actor, "", "", charge, "arrest", fact_id, false)
	var t := Tribunal.trial(st, tid)
	if not t.is_empty() and guard != "" and not (t["witnesses"] as Array).any(func(w: Dictionary) -> bool:
			return str(w.get("character", "")) == guard):
		(t["witnesses"] as Array).push_front({"character": guard, "disposition": "against", "done": {}, "cross": ""})
	sim.events.append({"type": "rogue_arrested", "actor": actor, "family": fam, "guard": guard, "charge": charge,
		"trial": tid, "seized": seized})
	if _playing(st, fam) and str(st.families[fam].get("controlled_by", "")) == "human":
		Notices.add(sim, fam, Notices.URGENT, "notice.rogue_arrested", {"name": str(st.characters[actor].get("name", "")),
			"charge": charge, "seized": seized}, actor)
	if OS.is_debug_build():
		print("[Rogue] la guardia (%s) detiene a %s por %s; juicio %s; requisa %d piezas robadas" % [guard, actor, charge,
			tid, seized])
	return tid


# --- Pickpocket --------------------------------------------------------------------------------------------------------

## "" if `actor` may pick `target`'s purse now (range aside: too_far is the order's), else why.
static func pickpocket_reason(sim: Sim, actor: String, target: String) -> String:
	var st := sim.state
	var p := _c(sim, "pickpocket")
	if not _outdoors(st, actor):
		return "unknown_actor"
	if not _outdoors(st, target) or target == actor:
		return "bad_target"
	if _fam(st, target) == _fam(st, actor) or Watch.is_guard(st, target):
		return "bad_target"
	if not _phase(sim) in (p.get("phases", ["day", "dusk"]) as Array):
		return "wrong_time"
	if target in (_book(sim)["picked"] as Array):
		return "already_picked"
	return ""


static func _crowd(sim: Sim, tile: Array, actor: String, target: String) -> int:
	var p := _c(sim, "pickpocket")
	var n := 0
	for c: String in sim.state.characters:
		if c == actor or c == target or not _outdoors(sim.state, c):
			continue
		if Life.dist(Life.tile_of(sim.state, c), tile) <= int(p.get("crowd_tiles", 4)):
			n += 1
	return int(p.get("crowd", 10)) if n >= int(p.get("crowd_people", 3)) else 0


## {"type": "pickpocket", "actor", "target"}.
static func order_pickpocket(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var why := pickpocket_reason(sim, actor, target)
	if why != "":
		return Orders.fail(why)
	var p := _c(sim, "pickpocket")
	var tile := Life.tile_of(st, actor)
	if Life.dist(tile, Life.tile_of(st, target)) > int(p.get("range", 1)):
		return Orders.fail("too_far")
	var b := _book(sim)
	(b["picked"] as Array).append(target)
	var fam := _fam(st, actor)
	var now := int(st.clock["minute"])
	var mods := _crowd(sim, tile, actor, target) - int(b.get("fails", 0)) * int(p.get("fail_penalty", 10))
	var r := SkillCheck.roll(sim, "rogue|pick|%s|%s|%d" % [actor, target, now], SkillCheck.stat(sim, actor, "dexterity"),
		SkillCheck.stat(sim, target, "empathy"), mods)
	if bool(r["success"]):
		var tfam := _fam(st, target)
		var gold := 0
		if _playing(st, tfam):
			gold = mini(int(p.get("family_base", 5)) + SkillCheck.stat(sim, actor, "dexterity"),
				floori(Money.gold(st, tfam) * float(p.get("family_share", 0.05))))
			if gold > 0:
				Money.change(sim, tfam, -gold, Money.LOOT, "pickpocket", "", target)
		else:
			var lo: Array = p.get("loot", [5, 12])
			gold = Kin.randi_range(st, "rogue|pick|loot|%s|%d" % [target, now], int(lo[0]), int(lo[1]))
		if gold > 0:
			Money.change(sim, fam, gold, Money.LOOT, "pickpocket", "", actor)
		add_underworld(sim, fam, int(_c(sim, "underworld").get("success", 2)), "pickpocket")
		sim.events.append({"type": "pickpocket_done", "actor": actor, "family": fam, "target": target, "gold": gold,
			"victim_family": tfam})
		if _playing(st, tfam) and str(st.families[tfam].get("controlled_by", "")) == "human":
			Notices.add(sim, tfam, Notices.WARNING, "notice.rogue_purse", {"gold": gold}, target)
		if OS.is_debug_build():
			print("[Rogue] %s le roba la bolsa a %s: %d de oro (tirada %d ≤ %d)" % [actor, target, gold, int(r["roll"]),
				int(r["threshold"])])
		return Orders.ok()
	b["fails"] = int(b.get("fails", 0)) + 1
	sim.events.append({"type": "pickpocket_failed", "actor": actor, "family": fam, "target": target})
	_seen(sim, actor, target, "pickpocket", true)
	return Orders.ok()


## The victim saw it: relation, a public fact against his family, a cry; a guard in view arrests him.
static func _seen(sim: Sim, actor: String, victim: String, crime: String, cry: bool) -> void:
	var st := sim.state
	var fam := _fam(st, actor)
	var charge := str(_c(sim, "charges").get(crime, "petty_theft"))
	if victim != "":
		Emotions.change_relation(sim, victim, actor, int(_c(sim, "witness").get("victim_relation", -30)), "rogue_" + crime)
	var fid := Tribunal.add_fact(sim, crime, fam, actor, charge)
	var tile := Life.tile_of(st, actor)
	if cry:
		Watch.respond(sim, tile, "rogue|" + fid)
	var g := guard_in_view(sim, tile)
	sim.events.append({"type": "rogue_seen", "actor": actor, "family": fam, "crime": crime, "victim": victim,
		"fact": fid, "guard": g})
	if OS.is_debug_build():
		print("[Rogue] %s visto (%s) por %s%s" % [actor, crime, victim if victim != "" else "nadie",
			" y por el guardia %s" % g if g != "" else ""])
	if g != "":
		caught(sim, actor, g, charge, fid)


# --- Burglary ----------------------------------------------------------------------------------------------------------

## The Security level (0-3) of a building: its protection upgrades (0.2 each, 4.20).
static func security_level(sim: Sim, bld: String) -> int:
	return clampi(roundi(Upgrades.amount(sim, bld, "protection") / 0.2), 0, 3)


static func lock_of(sim: Sim, bld: String) -> int:
	var c := _c(sim, "burgle")
	var lock := int(c.get("lock_base", 2)) + int(c.get("lock_per_level", 2)) * security_level(sim, bld)
	if int(sim.state.buildings[bld].get("burgled_until", -1)) > int(sim.state.clock["minute"]):
		lock += 2
	return lock


## "" if `actor` may burgle `bld` now (at its door: too_far is the order's), else why.
static func burgle_reason(sim: Sim, actor: String, bld: String) -> String:
	var st := sim.state
	var c := _c(sim, "burgle")
	if not _outdoors(st, actor):
		return "unknown_actor"
	var b: Dictionary = st.buildings.get(bld, {})
	if b.is_empty() or (b.get("inventory", {}).get("stacks", []) as Array).is_empty():
		return "nothing_to_steal"
	var owner := Money.family_of(st, bld)
	if owner == "" or owner == _fam(st, actor):
		return "bad_target"
	if not _phase(sim) in (c.get("phases", ["night"]) as Array):
		return "wrong_time"
	if int(b.get("burgled_until", -1)) > int(st.clock["minute"]):
		return "recently_robbed"
	return ""


## {"type": "burgle", "actor", "building"}: at its door, at night.
static func order_burgle(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var why := burgle_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	var door: Array = st.buildings[bld].get("door", [])
	if door.size() != 2 or Life.dist(Life.tile_of(st, actor), door) > 1:
		return Orders.fail("too_far")
	var c := _c(sim, "burgle")
	var fam := _fam(st, actor)
	var now := int(st.clock["minute"])
	var inv: Dictionary = st.characters[actor]["inventory"]
	var picks := str(c.get("lockpick_item", "lockpicks"))
	var eq: Dictionary = st.characters[actor].get("equipment", {}) if st.characters[actor].get("equipment") is Dictionary else {}
	var mods := int(c.get("lockpicks", 10)) if Inventory.count(inv, picks) > 0 or str(eq.get("tool", "")) == picks else 0
	var den := den_of(st, fam)
	if den != "":  # the den's Quality branch: fine lockpicks, a lock collection
		mods += roundi(Upgrades.amount(sim, den, "lock_bonus"))
	var r := SkillCheck.roll(sim, "rogue|burgle|%s|%s|%d" % [actor, bld, now], SkillCheck.stat(sim, actor, "stealth"),
		lock_of(sim, bld), mods)
	st.buildings[bld]["burgled_until"] = now + int(c.get("cooldown_days", 2)) * Clock.MINUTES_PER_DAY
	if not bool(r["success"]):
		sim.events.append({"type": "burgle_failed", "actor": actor, "family": fam, "building": bld})
		var g := guard_in_view(sim, Life.tile_of(st, actor))
		if g != "":  # the noise brings the watch
			_seen(sim, actor, "", "burgle", true)
		elif OS.is_debug_build():
			print("[Rogue] %s no abre la cerradura de %s (cerradura %d); nadie le ve" % [actor, bld, lock_of(sim, bld)])
		return Orders.ok()
	var units := int(c.get("units_base", 2)) + SkillCheck.stat(sim, actor, "dexterity") / 2
	var taken: Array = []
	var store: Dictionary = st.buildings[bld]["inventory"]
	while units > 0:
		var best := _most_valuable(sim, store)
		if best.is_empty():
			break
		var it := str(best["item"])
		var q := int(best["quality"])
		if not Inventory.can_add(inv, sim.catalog, stolen(it), q, 1):
			break
		Inventory.remove(store, it, q, 1)
		Inventory.add(inv, sim.catalog, stolen(it), q, 1)
		taken.append({"item": it, "quality": q})
		units -= 1
	add_underworld(sim, fam, int(_c(sim, "underworld").get("success", 2)), "burgle")
	var owner := Money.family_of(st, bld)
	sim.events.append({"type": "burgle_done", "actor": actor, "family": fam, "building": bld, "victim_family": owner,
		"taken": taken})
	if str(st.families.get(owner, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, owner, Notices.URGENT, "notice.rogue_burgled", {"count": taken.size()}, bld)
	if OS.is_debug_build():
		print("[Rogue] %s roba en %s: %s (sigilo contra cerradura %d)" % [actor, bld, taken, lock_of(sim, bld)])
	return Orders.ok()


## The most valuable unit of an inventory by the market's sell price ({item, quality} or {}); never stolen goods.
static func _most_valuable(sim: Sim, inv: Dictionary) -> Dictionary:
	var best := {}
	var best_p := -1
	for s: Dictionary in inv.get("stacks", []):
		var it := str(s["item"])
		if int(s["qty"]) <= 0 or is_stolen(it):
			continue
		var p := int(sim.catalog.item(it).get("base_price", 0))
		if p > best_p or (p == best_p and it < str(best.get("item", "~"))):
			best = {"item": it, "quality": int(s["quality"])}
			best_p = p
	return best


# --- The fence -----------------------------------------------------------------------------------------------------------

## Whether `actor` is at a fence: inside a den of his family, or in the tavern at night.
static func at_fence(sim: Sim, actor: String) -> bool:
	var st := sim.state
	var loc := str(st.characters.get(actor, {}).get("location", ""))
	if loc == "" or not st.buildings.has(loc):
		return false
	var t := str(st.buildings[loc].get("type", ""))
	if t == "den" and Money.family_of(st, loc) == _fam(st, actor):
		return true
	return t == "tavern_inn" and _phase(sim) == "night"


## What the fence pays for one `item@stolen` of `quality` (the market's sell price of the clean piece × share).
static func fence_price(sim: Sim, fam: String, item: String, quality: int) -> int:
	var f := _c(sim, "fence")
	var share := float(f.get("share", 0.5))
	if underworld(sim.state, fam) >= int(f.get("underworld_min", 50)):
		share += float(f.get("underworld_bonus", 0.1))
	var den := den_of(sim.state, fam)
	if den != "":  # the den's Commerce branch: the fence's table, known buyers
		share += Upgrades.amount(sim, den, "fence_bonus")
	return maxi(1, roundi(Market.price(sim, clean(item), quality, "sell") * share))


## {"type": "fence_sell", "actor", "item", "quality", "qty"}: stolen goods (from the bag) to the fence.
static func order_fence(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var item := stolen(str(o.get("item", "")))
	var q := int(o.get("quality", 0))
	var qty := maxi(1, int(o.get("qty", 1)))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	if not at_fence(sim, actor):
		return Orders.fail("no_fence")
	var inv: Dictionary = st.characters[actor]["inventory"]
	if Inventory.count(inv, item, q) < qty:
		return Orders.fail("not_enough")
	var fam := _fam(st, actor)
	var b := _book(sim)
	var cap := int(_c(sim, "fence").get("cap", 150))
	var unit := fence_price(sim, fam, item, q)
	var n := mini(qty, (cap - int(b.get("fence_paid", 0))) / unit)
	if n <= 0:
		return Orders.fail("fence_full")
	Inventory.remove(inv, item, q, n)
	Money.change(sim, fam, unit * n, Money.LOOT, "fence:" + clean(item), str(st.characters[actor].get("location", "")), actor)
	b["fence_paid"] = int(b.get("fence_paid", 0)) + unit * n
	sim.events.append({"type": "fence_sold", "actor": actor, "family": fam, "item": clean(item), "quality": q, "qty": n,
		"gold": unit * n})
	if OS.is_debug_build():
		print("[Rogue] %s le vende al perista %d × %s por %d (hoy %d de %d)" % [actor, n, item, unit * n,
			int(b["fence_paid"]), cap])
	return Orders.ok()


# --- Laundering ----------------------------------------------------------------------------------------------------------

## {"type": "launder", "actor", "building", "item", "quality"}: at his den, one unit loses its mark after
## launder.minutes (the den's `laundering` job; the unit waits in the den's storage, marked, until then).
static func order_launder(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var item := stolen(str(o.get("item", "")))
	var q := int(o.get("quality", 0))
	var lc := _c(sim, "launder")
	if not st.characters.has(actor) or str(st.characters[actor].get("location", "")) != bld:
		return Orders.fail("not_inside")
	if str(st.buildings.get(bld, {}).get("type", "")) != "den" or Money.family_of(st, bld) != _fam(st, actor):
		return Orders.fail("no_den")
	if SkillCheck.stat(sim, actor, "dexterity") < int(lc.get("min_dexterity", 5)):
		return Orders.fail("low_dexterity")
	if st.buildings[bld].get("laundering") is Dictionary:
		return Orders.fail("busy")
	var inv: Dictionary = st.characters[actor]["inventory"]
	var store: Dictionary = st.buildings[bld]["inventory"]
	var src := inv if Inventory.count(inv, item, q) > 0 else store
	if Inventory.count(src, item, q) < 1:
		return Orders.fail("not_enough")
	Inventory.remove(src, item, q, 1)
	var now := int(st.clock["minute"])
	st.buildings[bld]["laundering"] = {"actor": actor, "item": clean(item), "quality": q,
		"end": now + maxi(1, roundi(int(lc.get("minutes", 30)) / maxf(Upgrades.mult(sim, bld, "production_speed"), 0.01)))}
	sim.events.append({"type": "launder_started", "actor": actor, "building": bld, "item": clean(item), "quality": q})
	return Orders.ok()


## Every minute: laundering jobs that end leave the clean unit in the den's storage.
static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	_arrest_timeouts(sim)
	for bld: String in st.buildings:
		var job: Variant = st.buildings[bld].get("laundering")
		if not job is Dictionary or now < int((job as Dictionary)["end"]):
			continue
		var j: Dictionary = job
		var store: Dictionary = st.buildings[bld]["inventory"]
		if not Inventory.add(store, sim.catalog, str(j["item"]), int(j["quality"]), 1):
			Inventory.add(st.characters[str(j["actor"])]["inventory"], sim.catalog, str(j["item"]), int(j["quality"]), 1)
		st.buildings[bld].erase("laundering")
		sim.events.append({"type": "launder_done", "actor": str(j["actor"]), "building": bld, "item": str(j["item"]),
			"quality": int(j["quality"])})
		if OS.is_debug_build():
			print("[Rogue] %s: %s blanqueado" % [bld, j["item"]])
