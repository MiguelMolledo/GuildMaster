class_name AIAscent
extends RefCounted
## 04c 4.21.6.5 and 4.21.10: how an AI family climbs. «El avance de título empuja a las demás candidatas (Fachada,
## reputación...)»: while the reputation of its next title is short, a family whose profile asks for titles works
## towards the next Facade of its workshop (the upgrades of the facade branch give reputation): it buys its materials
## with its other inputs and orders the works (buy_upgrade, a management order like the player's) when it keeps its
## gold after paying them. And the difficulty's scale (data/difficulty.json ai.ascent): spare_mult multiplies the gold
## the family keeps after a title, a candidacy or a facade (Easy > 1: it climbs later; Hard < 1: sooner), as the
## attacks already scale (threshold_offset, cooldown). The same rules as the player: the title's requirements are
## not lowered.


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.difficulty_levels(sim.state.difficulty).get("ai", {}).get("ascent", {})


## What the family keeps after a title, a candidacy or a facade is multiplied by this (1 without the block).
static func spare_mult(sim: Sim) -> float:
	return float(cfg(sim).get("spare_mult", 1.0))


## The facade upgrade the family works towards now ("" if none): its profile asks for titles, the reputation of its
## next title is short, the next facade of its workshop's tree is not owned and can be had (its requirements met; only
## its materials or gold may be missing), and after paying it (gold and the materials at the market's price) it keeps
## its next title's price + gold_reserve + its spare floor + facade_keep × spare_mult (the title's own spare_gold
## it gathers again afterwards).
static func facade(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary) -> String:
	if not bool(profile.get("title_rule", {}).get("requests", false)) or home == "":
		return ""
	var st := sim.state
	var t := Titles.next_of(sim, fam)
	if t == "":
		return ""
	for r: Dictionary in Titles.requirements(sim, fam, t):
		if str(r["kind"]) == "reputation" and bool(r["ok"]):
			return ""  # its reputation is enough: the title waits for the rest
	var tree := Upgrades.tree_of(sim, home)
	for level: int in [1, 2, 3]:
		var id := "%s_facade_%d" % [tree, level]
		var u := sim.catalog.upgrade(id)
		if u.is_empty():
			return ""
		if Upgrades.has(st, home, id):
			continue
		if not Upgrades.status_of(sim, actor, home, id) in ["available", "missing_materials", "not_enough_gold"]:
			return ""  # in works, another works going on, or a requirement it cannot meet (a title): later
		# after the facade it still has its next title's price: it brings the title closer, it does not put it off
		var keep := Titles.cost_of(sim, fam, t) + int(profile.get("gold_reserve", 20)) \
			+ AIEconomy.spare_floor(sim, fam, profile) + roundi(float(cfg(sim).get("facade_keep", 20)) * spare_mult(sim))
		return id if Money.gold(st, fam) - cost(sim, home, id) >= keep else ""
	return ""


## The gold a facade costs the family now: its gold plus the materials it lacks in the workshop at the market's price.
static func cost(sim: Sim, home: String, id: String) -> int:
	var u := sim.catalog.upgrade(id)
	var c := int(u.get("cost", {}).get("gold", 0))
	var inv: Dictionary = sim.state.buildings[home].get("inventory", {})
	for m: Dictionary in u.get("cost", {}).get("items", []):
		var lack := maxi(0, int(m["qty"]) - Inventory.count(inv, str(m["item"])))
		c += lack * Market.price(sim, str(m["item"]), Inventory.NORMAL, "buy")
	return c


## The materials of `id` the workshop still lacks ({item: qty}).
static func materials(sim: Sim, home: String, id: String) -> Dictionary:
	var out := {}
	var inv: Dictionary = sim.state.buildings[home].get("inventory", {})
	for m: Dictionary in sim.catalog.upgrade(id).get("cost", {}).get("items", []):
		var lack := int(m["qty"]) - Inventory.count(inv, str(m["item"]))
		if lack > 0:
			out[str(m["item"])] = lack
	return out
