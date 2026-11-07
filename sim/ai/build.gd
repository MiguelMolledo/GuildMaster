class_name AIBuild
extends RefCounted
## H6 + H13 (04c 4.21.6.2, 04 §4.9): the AI families' agenda for building and buying, at dawn. The candidates, the
## valve (>= 2 free plots of each zone) and the limit by title are H6's (Construction.candidates, Plots); the order is
## Construction.order_for, the same management order as the player's. What is the agenda's: when to look (from
## first_day, every cooldown_days, at most max_per_day in the town: data/construction.json "ai"), what it may spend
## (its gold over its reserve: AIEconomy.reserve on the economy maps, Construction.budget elsewhere) and which
## candidate it takes by its profile (data/ai_profiles "build": {"buy": weight, "build": weight, "min_score"}; without
## them, the best score over the rules' min_score, as H6 left it). Called from Sim.step right after
## Construction.step, whose own AI pass is off (construction.json ai.enabled false): the same minute, the same order.


static func step(sim: Sim) -> void:
	if not Ledger.is_dawn(sim):
		return
	for o: Dictionary in orders(sim):
		sim.give(o)


## The building orders of the AI families this dawn.
static func orders(sim: Sim) -> Array:
	var out: Array = []
	var st := sim.state
	var cfg := Construction.ai_rules(sim)
	var today := Clock.day(int(st.clock["minute"]))
	if today < int(cfg.get("first_day", 0)):
		return out
	var fams: Array = st.families.keys()
	fams.sort()
	for fam: String in fams:
		if out.size() >= int(cfg.get("max_per_day", 1)):
			break
		var f: Dictionary = st.families[fam]
		if str(f.get("controlled_by", "")) != "ai" or str(f.get("ai_profile", "")) == "":
			continue
		if today - int(f.get("ai_build_day", -999)) < int(cfg.get("cooldown_days", 8)) and not Construction._homeless(sim, fam):
			continue
		var c := choose(sim, fam)
		if c.is_empty():
			continue
		var o := Construction.order_for(sim, fam, c)
		if o.is_empty():
			continue
		f["ai_build_day"] = today
		out.append(o)
		if OS.is_debug_build():
			print("[AIBuild] %s decide %s %s (%s) puntuación %.2f, presupuesto %d" % [fam, c["kind"],
				c.get("building_type", ""), c.get("plot", c.get("building", "")), float(c["score"]), budget(sim, fam)])
	return out


## What the family may spend on a building: its gold over its reserve.
static func budget(sim: Sim, fam: String) -> int:
	if AIEconomy.on(sim):
		return Money.gold(sim.state, fam) - AIEconomy.reserve(sim, fam, Hostility._profile(sim, fam))
	return Construction.budget(sim, fam)


## The candidate the family takes today ({} if none): Construction.choose's rules (a family that sold its workshop
## needs one, whatever its score; a second building waits for ai.expand), with the scores weighed by its profile.
static func choose(sim: Sim, fam: String) -> Dictionary:
	var homeless := Construction._homeless(sim, fam)
	var fate := str(sim.state.families[fam].get("after_sale", {}).get("fate", ""))
	if homeless and fate != "" and fate != "rebuilds":
		return {}
	if not homeless and not bool(Construction.ai_rules(sim).get("expand", false)):
		return {}
	var pb: Dictionary = Hostility._profile(sim, fam).get("build", {})
	var min_score := float(pb.get("min_score", Construction.ai_rules(sim).get("min_score", 1.0)))
	var money := budget(sim, fam)
	var best := {}
	var best_s := -INF
	for c: Dictionary in Construction.candidates(sim, fam):  # the best score first; ties by plot or building id
		if int(c["price"]) > money:
			continue
		var s := float(c["score"]) * float(pb.get(str(c["kind"]), 1.0))
		if (homeless or s >= min_score) and s > best_s:
			best = c
			best_s = s
	return best
