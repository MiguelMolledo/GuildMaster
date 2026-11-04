class_name Courtship
extends RefCounted
## Courtship by affinity and the wedding (GDD 4.10.1, 4.10.2). Affinity 0-100 lives in
## state.relationships[Ids.pair_key(a, b)].affinity (beside the general relation of 4.11.4). Owner of the orders
## court_talk, court_gift and propose. Contract: docs/contratos/h8_familia.md. Figures: data/family.json "courtship".
##
## Rules: talk +talk[0..1] once per suitor, target and day; gift +value / gold_per_point within [min, max] (the item
## leaves the actor's inventory for the target's; its value is its sell price at the market); working at the same
## building at the same time +work_near per day (step, from the work_done events). Every gain × (1 + (charisma − 5)
## × charisma_step) of the actor and × same_title_mult when both families have the same title. A target with a
## blocking emotion towards the actor's family (4.11.5, H7) refuses. Range: the actor stands within range_tiles of the
## target on the map, or of the door of the building the target is in, or inside the same building.
## propose: both alive, single, >= majority_age, of different families, opposite sex (provisional) and affinity >=
## propose_min -> wedding (marry): the target moves into the actor's family and home.
## Pair memory in the relationship: {relation, affinity, talk_day, near_day}.


## {"type": "court_talk", "actor", "target"}.
static func order_talk(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var why := _reason(sim, actor, target, true)
	if why != "":
		return Orders.fail(why)
	var rel := relation(sim.state, actor, target)
	var today := Clock.day(int(sim.state.clock["minute"]))
	if int(rel.get("talk_day", -1)) == today:
		return Orders.fail("already_talked")
	var span: Array = sim.catalog.family.get("courtship", {}).get("talk", [3, 5])
	var base := Kin.randi_range(sim.state, "talk|%d|%s|%s" % [today, actor, target], int(span[0]), int(span[1]))
	rel["talk_day"] = today
	var gain := add_affinity(sim, actor, target, base, "talk")
	if OS.is_debug_build():
		print("[Courtship] %s conversa con %s: +%d (base=%d, afinidad=%d)" % [actor, target, gain, base,
			int(rel.get("affinity", 0))])
	return Orders.ok()


## {"type": "court_gift", "actor", "target", "item", "quality"}: one unit from the actor's inventory.
static func order_gift(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var why := _reason(sim, actor, target, true)
	if why != "":
		return Orders.fail(why)
	var item := str(o.get("item", ""))
	var q := int(o.get("quality", 0))
	var src: Dictionary = sim.state.characters[actor].get("inventory", {})
	if sim.catalog.item(item).is_empty():
		return Orders.fail("unknown_item")
	if Inventory.count(src, item, q) < 1:
		return Orders.fail("not_enough")
	var cfg: Dictionary = sim.catalog.family.get("courtship", {}).get("gift", {})
	var value := Market.price(sim, item, q, "sell")
	var base := clampi(roundi(float(value) / maxf(1.0, float(cfg.get("gold_per_point", 2)))), int(cfg.get("min", 5)),
		int(cfg.get("max", 15)))
	Inventory.remove(src, item, q, 1)
	var dst: Dictionary = sim.state.characters[target].get("inventory", {})
	if not dst.is_empty():
		Inventory.add(dst, sim.catalog, item, q, 1)  # what does not fit the target is lost (eaten, sold, shared)
	sim.events.append({"type": "items_moved", "actor": actor, "from": actor, "to": target, "item": item, "quality": q,
		"qty": 1})
	var gain := add_affinity(sim, actor, target, base, "gift")
	if OS.is_debug_build():
		print("[Courtship] %s regala %s (q%d, valor=%d) a %s: +%d" % [actor, item, q, value, target, gain])
	return Orders.ok()


## {"type": "propose", "actor", "target"}: the wedding, at once.
static func order_propose(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var why := _reason(sim, actor, target, true)
	if why != "":
		return Orders.fail(why)
	if affinity(sim.state, actor, target) < int(sim.catalog.family.get("courtship", {}).get("propose_min", 80)):
		return Orders.fail("low_affinity")
	marry(sim, actor, target)
	return Orders.ok()


## Why `actor` cannot court `target` now ("" = it can). near: check the range too.
static func _reason(sim: Sim, actor: String, target: String, near: bool) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not st.characters.has(target) or actor == target:
		return "unknown_target"
	if not Kin.alive(st, actor) or not Kin.alive(st, target):
		return "dead"
	var a: Dictionary = st.characters[actor]
	var t: Dictionary = st.characters[target]
	if not Kin.is_adult(sim, actor) or not Kin.is_adult(sim, target):
		return "too_young"
	if not Kin.is_single(st, actor) or not Kin.is_single(st, target):
		return "not_single"
	if str(a.get("family", "")) == str(t.get("family", "")):
		return "same_family"
	if Life.is_service(st, str(t.get("family", ""))) or Life.is_service(st, str(a.get("family", ""))):
		return "passing_through"  # vida (04f 4.24): a guard, a visitor or a bandit is not courted
	var cfg: Dictionary = sim.catalog.family.get("courtship", {})
	if bool(cfg.get("opposite_sex", true)) and bool(a.get("female", false)) == bool(t.get("female", false)):
		return "same_sex"
	if blocked(sim, actor, target):
		return "offended"
	if near and not in_range(sim, actor, target):
		return "too_far"
	return ""


## Whether `actor` can court `target` (the UI greys the buttons with the reason).
static func status(sim: Sim, actor: String, target: String) -> String:
	return _reason(sim, actor, target, true)


## A blocking emotion of `target` towards the actor's family or the actor (state.emotions, H7).
static func blocked(sim: Sim, actor: String, target: String) -> bool:
	var bad: Array = sim.catalog.family.get("courtship", {}).get("blocking_emotions", [])
	var fam := str(sim.state.characters[actor].get("family", ""))
	for e: Variant in sim.state.emotions.get(target, []):
		if e is Dictionary and str(e.get("state", "")) in bad and str(e.get("source", "")) in [actor, fam]:
			return true
	return false


## Range (data courtship.range_tiles): the actor inside the same building as the target, or on the map within range
## of the target (or of the door of the building the target is in).
static func in_range(sim: Sim, actor: String, target: String) -> bool:
	var st := sim.state
	var a: Dictionary = st.characters[actor]
	var t: Dictionary = st.characters[target]
	var la := str(a.get("location", ""))
	var lt := str(t.get("location", ""))
	if la != "":
		return la == lt
	var spot: Array = t.get("position", [0, 0])
	if lt != "":
		spot = st.buildings.get(lt, {}).get("door", spot)
	var pa: Array = a.get("position", [0, 0])
	var r := int(sim.catalog.family.get("courtship", {}).get("range_tiles", 3))
	return maxi(absi(int(pa[0]) - int(spot[0])), absi(int(pa[1]) - int(spot[1]))) <= r


## Where to stand to court `target`: the door of the building it is in, or its tile.
static func spot(st: WorldState, target: String) -> Array:
	var t: Dictionary = st.characters.get(target, {})
	var lt := str(t.get("location", ""))
	if lt != "":
		return (st.buildings.get(lt, {}).get("door", t.get("position", [0, 0])) as Array).duplicate()
	return (t.get("position", [0, 0]) as Array).duplicate()


## The pair's relationship entry (created on first use): {relation, affinity, ...}.
static func relation(st: WorldState, a: String, b: String) -> Dictionary:
	var k := Ids.pair_key(a, b)
	if not st.relationships.get(k) is Dictionary:
		st.relationships[k] = {"relation": 0, "affinity": 0}
	return st.relationships[k]


static func affinity(st: WorldState, a: String, b: String) -> int:
	var r: Variant = st.relationships.get(Ids.pair_key(a, b))
	return int((r as Dictionary).get("affinity", 0)) if r is Dictionary else 0


## Adds `base` × the actor's multipliers to the pair's affinity (capped). Returns the gain.
static func add_affinity(sim: Sim, actor: String, target: String, base: int, why: String) -> int:
	var cfg: Dictionary = sim.catalog.family.get("courtship", {})
	var mult := 1.0 + (int(sim.state.characters[actor].get("stats", {}).get("charisma", 5)) - 5) \
		* float(cfg.get("charisma_step", 0.1))
	var fa := str(sim.state.characters[actor].get("family", ""))
	var ft := str(sim.state.characters[target].get("family", ""))
	if Kin.title(sim, fa) == Kin.title(sim, ft):
		mult *= float(cfg.get("same_title_mult", 1.15))
	var gain := maxi(0, roundi(base * mult))
	var rel := relation(sim.state, actor, target)
	var before := int(rel.get("affinity", 0))
	rel["affinity"] = mini(int(cfg.get("affinity_max", 100)), before + gain)
	sim.events.append({"type": "affinity_changed", "actor": actor, "target": target, "amount": int(rel["affinity"]) - before,
		"affinity": int(rel["affinity"]), "reason": why})
	return int(rel["affinity"]) - before


## The wedding (GDD 4.10.1-4.10.2): spouses, the target leaves its family for the actor's, moves to its home (the
## family residence), leaves a job it had and keeps acting with AI (the spouse never takes a group place). Chronicle
## "wedding", event, notice.
static func marry(sim: Sim, actor: String, target: String) -> void:
	var st := sim.state
	var a: Dictionary = st.characters[actor]
	var t: Dictionary = st.characters[target]
	var fam := str(a.get("family", ""))
	var old := str(t.get("family", ""))
	var today := Clock.day(int(st.clock["minute"]))
	a["spouse"] = target
	t["spouse"] = actor
	for c: Dictionary in [a, t]:
		if not c.get("life") is Dictionary:
			c["life"] = {}
	var wife: Dictionary = t if bool(t.get("female", false)) else a
	wife["life"]["wedding_day"] = today
	wife["life"].erase("last_birth_day")
	if st.families.has(old):
		(st.families[old]["members"] as Array).erase(target)
		if str(st.families[old].get("head", "")) == target:
			st.families[old]["head"] = _first_alive(st, old)
	if not target in (st.families[fam]["members"] as Array):
		(st.families[fam]["members"] as Array).append(target)
	t["family"] = fam
	t["controlled_by"] = "ai"
	# The one who joins lives in the family's home (pulido-mvp): the actor's house for a household (a townsfolk
	# wedding), else "" = the family's residence (Kin.home_of); never the old house.
	t["home"] = str(a.get("home", "")) if TownLife.is_household(st, fam) else ""
	# H7: a walk queued before the wedding (a townsperson on the way to its old house) would be refused on arrival
	t["order_queue"] = []
	t["path"] = []
	t["move_progress"] = 0
	t["assigned"] = ""
	if t.get("job") is Dictionary:
		var bld := str(t["job"].get("building", ""))
		t["job"] = null
		sim.events.append({"type": "employee_left", "family": str(st.buildings.get(bld, {}).get("owner", "")),
			"building": bld, "employee": target, "reason": "married"})
	if (t.get("inventory", {}) as Dictionary).is_empty():
		t["inventory"] = Inventory.create("weight", float(sim.catalog.family.get("life", {}).get("adult_carry_weight", 30.0)))
	Chronicle.add(st, "wedding", {"family": fam, "character": actor, "spouse": target, "from_family": old})
	sim.events.append({"type": "wedding", "family": fam, "character": actor, "spouse": target, "from_family": old})
	if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, fam, "info", "notice.wedding", {"name": str(a.get("name", "")), "spouse": str(t.get("name", ""))},
			actor)
	if OS.is_debug_build():
		print("[Courtship] boda: %s (%s) y %s (de %s), día %d" % [actor, fam, target, old, today])


static func _first_alive(st: WorldState, fam: String) -> String:
	for m: Variant in st.families[fam].get("members", []):
		if Kin.alive(st, str(m)):
			return str(m)
	return ""


## Once per minute (after Production): +work_near per day to each pair of single adults of different families that
## worked at the same building at the same time (a work_done of one while the other holds a job there).
static func step(sim: Sim) -> void:
	var st := sim.state
	var today := -1
	var near := int(sim.catalog.family.get("courtship", {}).get("work_near", 1))
	for e: Dictionary in sim.events.duplicate():
		if str(e.get("type", "")) != "work_done":
			continue
		var a := str(e.get("actor", ""))
		var bld := str(e.get("building", ""))
		var zones: Dictionary = st.buildings.get(bld, {}).get("zones", {})
		var zs: Array = zones.keys()
		zs.sort()
		for z: String in zs:
			var job: Variant = zones[z].get("job")
			var b := str(job.get("actor", "")) if job is Dictionary else str(zones[z].get("occupant", ""))
			if b == "" or b == a or _reason(sim, a, b, false) != "":
				continue
			if today < 0:
				today = Clock.day(int(st.clock["minute"]))
			var rel := relation(st, a, b)
			if int(rel.get("near_day", -1)) == today:
				continue
			rel["near_day"] = today
			add_affinity(sim, a, b, near, "work_near")


## The courtship panel (UI): the single adults `actor` could court, best affinity first then id:
## [{character, name, female, family, age, affinity, status}] (status "" = can act now, else the reason).
static func candidates(sim: Sim, actor: String) -> Array:
	var st := sim.state
	var out: Array = []
	if not st.characters.has(actor):
		return out
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		var why := _reason(sim, actor, id, false)
		if why in ["unknown_target", "dead", "too_young", "not_single", "same_family", "same_sex", "passing_through"]:
			continue
		var ch: Dictionary = st.characters[id]
		out.append({"character": id, "name": str(ch.get("name", "")), "female": bool(ch.get("female", false)),
			"family": str(ch.get("family", "")), "age": Kin.age(sim, id), "affinity": affinity(st, actor, id),
			"status": _reason(sim, actor, id, true)})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["affinity"]) != int(y["affinity"]):
			return int(x["affinity"]) > int(y["affinity"])
		return str(x["character"]) < str(y["character"]))
	return out
