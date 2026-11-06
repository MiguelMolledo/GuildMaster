class_name Construction
extends RefCounted
## H6 · the works of the plots and the construction of the AI families (docs/gdd/04_diseno_de_juego.md §4.9;
## docs/gdd/04c_ia_rival.md §4.21.6.2; data/construction.json "ai" [balance]).
##
## step(): a building under works (state "construction", Plots) is finished at its end minute: it is "normal" again,
## its plot built, its owner told. At dawn, the AI families (controlled_by "ai" with an ai_profile) think about
## building: candidates() lists what each could raise or buy (a free plot of production with a workshop of its trades,
## or a building for sale), choose() takes the best that pays itself within horizon_days and that its gold over its
## reserve covers, and the head gives the order (a management order, like the player's). The title limit and the
## valve (4.9) are Plots'. The AI families' agenda (sim/ai, plantillas) may call candidates() / choose() / order_for()
## itself and set rules.ai.enabled false; until then ai_orders() runs here.

static func ai_rules(sim: Sim) -> Dictionary:
	return Plots.rules(sim).get("ai", {})


static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		var bld: Dictionary = st.buildings[b]
		if str(bld.get("state", "")) != "construction":
			continue
		var w: Dictionary = bld.get("construction", {})
		if now < int(w.get("end", 0)):
			continue
		bld["state"] = "normal"
		bld.erase("construction")
		var fam := str(bld.get("owner", ""))
		Chronicle.add(st, "building_finished", {"family": fam, "building": b, "type": str(bld.get("type", "")),
			"kind": str(w.get("kind", ""))})
		sim.events.append({"type": "construction_done", "building": b, "family": fam, "building_type": str(bld["type"]),
			"kind": str(w.get("kind", "")), "plot": str(w.get("plot", ""))})
		if fam != "" and Plots.is_human(sim, fam):
			Notices.add(sim, fam, Notices.INFO, "notice.plots.finished", {"building": b}, b)
		if OS.is_debug_build():
			print("[Construction] %s: termina la obra de %s (%s)" % [b, bld["type"], w.get("kind", "")])
	if Ledger.is_dawn(sim) and bool(ai_rules(sim).get("enabled", false)):
		for o: Dictionary in ai_orders(sim):
			sim.give(o)


## The orders of the AI families' construction this dawn (at most max_per_day in the town).
static func ai_orders(sim: Sim) -> Array:
	var out: Array = []
	var st := sim.state
	var cfg := ai_rules(sim)
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
		var last := int(f.get("ai_build_day", -999))
		if today - last < int(cfg.get("cooldown_days", 8)) and not _homeless(sim, fam):
			continue
		var c := choose(sim, fam)
		if c.is_empty():
			continue
		var o := order_for(sim, fam, c)
		if o.is_empty():
			continue
		f["ai_build_day"] = today
		out.append(o)
		if OS.is_debug_build():
			print("[Construction] %s decide %s %s (%s) puntuación %.2f" % [fam, c["kind"], c.get("building_type", ""),
				c.get("plot", c.get("building", "")), float(c["score"])])
	return out


## What the family has to spend on building: its gold over its reserve (reserve_days of its fixed costs, and its
## profile's gold_reserve).
static func budget(sim: Sim, fam: String) -> int:
	var profile: Dictionary = sim.catalog.ai_profiles().get(str(sim.state.families[fam].get("ai_profile", "")), {})
	var fixed := int(Upkeep.due_next_dawn(sim, fam).get("total", 0))
	var reserve := int(profile.get("gold_reserve", 0)) + int(ai_rules(sim).get("reserve_days", 4)) * fixed
	return int(sim.state.families[fam].get("gold", 0)) - reserve


## The building types the family works in: the one it has (its workshop) and those of its profile's trades.
static func trades(sim: Sim, fam: String) -> Array:
	var out: Array = []
	var after: Dictionary = sim.state.families[fam].get("after_sale", {})
	if not after.is_empty() and str(after.get("type", "")) != "":
		out.append(str(after["type"]))
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		var bld: Dictionary = sim.state.buildings[b]
		if str(bld.get("owner", "")) == fam and str(sim.catalog.buildings().get(str(bld["type"]), {}).get("category", "")) == "workshop":
			if not str(bld["type"]) in out:
				out.append(str(bld["type"]))
	var profile: Dictionary = sim.catalog.ai_profiles().get(str(sim.state.families[fam].get("ai_profile", "")), {})
	for pr: Variant in profile.get("preferred_professions", []):
		var t := str(sim.catalog.professions().get(str(pr), {}).get("building", ""))
		if t != "" and not t in out:
			out.append(t)
	return out


## Whether the family has no building with stations (it sold its workshop and puts one up elsewhere: 4.9).
static func _homeless(sim: Sim, fam: String) -> bool:
	for b: String in sim.state.buildings:
		var bld: Dictionary = sim.state.buildings[b]
		if str(bld.get("owner", "")) == fam and not (bld.get("zones", {}) as Dictionary).is_empty():
			return false
	return true


## What the family could do: [{kind "build" | "buy", plot, building_type, building, price, daily, score}], the best
## first. build: the 3 free plots of its zone with the best situation where a workshop of its trades fits; buy: a
## building of its trades for sale. score = (expected net over horizon_days × expansion) / price.
static func candidates(sim: Sim, fam: String) -> Array:
	var out: Array = []
	var st := sim.state
	var actor := Kin.head(st, fam)
	if actor == "" or not st.characters.has(actor):
		return out
	var profile: Dictionary = sim.catalog.ai_profiles().get(str(st.families[fam].get("ai_profile", "")), {})
	var expansion := float(profile.get("expansion", 1.0)) * _difficulty_expansion(sim)
	var horizon := float(ai_rules(sim).get("horizon_days", 16))
	var ts := trades(sim, fam)
	var free: Array = []
	for p: Dictionary in Plots.all(sim):
		if Plots.is_free(p) and str(p.get("zone", "")) == "production":
			free.append(p)
	free.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("location", 0)) > float(b.get("location", 0)) or (float(a.get("location", 0))
			== float(b.get("location", 0)) and str(a["id"]) < str(b["id"])))
	var seen := 0
	for p: Dictionary in free:
		if seen >= 3:
			break
		var any := false
		for t: String in ts:
			var r := Plots.can_build(sim, actor, str(p["id"]), t)
			if not r["ok"] and str(r["reason"]) != "not_enough_gold":
				continue
			any = true
			var daily := daily_net(sim, t)
			var price := int(r.get("price", 0))
			if price <= 0:
				continue
			out.append({"kind": "build", "plot": str(p["id"]), "building_type": t, "price": price, "daily": daily,
				"score": daily * horizon * expansion / float(price)})
		if any:
			seen += 1
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		var bld: Dictionary = st.buildings[b]
		if not bool(bld.get("for_sale", false)) or str(bld.get("owner", "")) != "" or not str(bld["type"]) in ts:
			continue
		var price := Inn.sale_price(sim, b)
		var daily := daily_net(sim, str(bld["type"]))
		if price > 0 and Plots.room_for(sim, fam, str(bld["type"])):
			out.append({"kind": "buy", "building": b, "building_type": str(bld["type"]), "price": price, "daily": daily,
				"score": daily * horizon * expansion / float(price)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]) or (float(a["score"]) == float(b["score"])
			and str(a.get("plot", a.get("building", ""))) < str(b.get("plot", b.get("building", "")))))
	return out


## The best candidate the family pays today and that clears min_score ({} if none). A family without a workshop
## (it sold it) takes the best it can pay, whatever its score: it needs a trade.
static func choose(sim: Sim, fam: String) -> Dictionary:
	var money := budget(sim, fam)
	var homeless := _homeless(sim, fam)
	var fate := str(sim.state.families[fam].get("after_sale", {}).get("fate", ""))
	if homeless and fate != "" and fate != "rebuilds":
		return {}   # it sold its workshop and stays on without one (stays) or is gone (leaves): it builds no more
	if not homeless and not bool(ai_rules(sim).get("expand", false)):
		return {}   # a second building waits for the AI's economy to run it (hire, queue, sell from it): ai.expand
	for c: Dictionary in candidates(sim, fam):
		if int(c["price"]) > money:
			continue
		if homeless or float(c["score"]) >= float(ai_rules(sim).get("min_score", 1.0)):
			return c
	return {}


static func order_for(sim: Sim, fam: String, c: Dictionary) -> Dictionary:
	var actor := Kin.head(sim.state, fam)
	if actor == "":
		return {}
	if str(c["kind"]) == "buy":
		return {"type": "buy_building", "actor": actor, "building": str(c["building"])}
	return {"type": "build", "actor": actor, "plot": str(c["plot"]), "building_type": str(c["building_type"])}


## The net a workshop of `type` is expected to make a day: the best margin of its recipes × units_per_day, shared
## with the other workshops of the type in the town (saturation), minus its upkeep and the wage of who works it
## (ai.staff_rank).
static func daily_net(sim: Sim, type: String) -> float:
	var best := 0
	for rid: String in sim.catalog.recipes():
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) == type:
			best = maxi(best, RivalAI.margin(sim, rid))
	var same := 0
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b].get("type", "")) == type:
			same += 1
	var units := float(ai_rules(sim).get("units_per_day", 4))
	var upkeep := float(sim.catalog.buildings().get(type, {}).get("upkeep", 0))
	var wage := float(sim.catalog.employees.get("ranks", {}).get(str(ai_rules(sim).get("staff_rank", "apprentice")), {}).get("wage", 0))
	return float(best) * units / float(1 + same) - upkeep - wage   # somebody works it: one employee's wage


static func _difficulty_expansion(sim: Sim) -> float:
	var lv: Dictionary = sim.catalog.difficulty_levels(sim.state.difficulty)
	return float(lv.get("ai_expansion", lv.get("expansion", 1.0)))
