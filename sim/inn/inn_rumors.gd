class_name InnRumors
extends RefCounted
## The useful rumour of the night (docs/gdd/04f_vida_y_fiestas.md §4.27.6): with a loyal barkeeper (or a family member
## who served at the bar), the turn summary brings one rumour about something true of the world. Hook for the life
## block (4.24.2, data/life/rumors.json and the book of rumours): until it arrives, three kinds read straight from the
## state, each as {kind, key, args}: the price of a good in another city of the region (region.cities demand), the
## next global event in force (events_active) or the debt of a rival family (its open loans). Pure read; the choice
## uses the keyed stream "inn|rumor|<bld>|<day>".


## A rumour for `bld` tonight, or {} if there is nothing true to tell. With the life block on (vida, 4.24.2) it is
## one of Rumors.candidates (the facts of the chronicle and the calendar), weighted by the topics of the «tavern» point
## (data/life/life.json meeting.kinds.tavern), the useful ones ×2 and the ones the family already heard ×heard_mult;
## it goes into the book of rumours (town.rumors.heard, point inn:<bld>) heard by `by`. Without the life block, the
## three kinds of before.
static func pick(sim: Sim, bld: String, by: String = "") -> Dictionary:
	if Life.on(sim):
		return _from_life(sim, bld, by)
	var cands: Array = []
	var st := sim.state
	# 1. A dear good in another city (09b): the highest demand of the region's cities.
	var cities: Variant = st.region.get("cities")
	if cities is Dictionary:
		var best := {}
		var ids: Array = (cities as Dictionary).keys()
		ids.sort()
		for c: Variant in ids:
			var dem: Variant = (cities[c] as Dictionary).get("demand")
			if not dem is Dictionary:
				continue
			var items: Array = (dem as Dictionary).keys()
			items.sort()
			for it: Variant in items:
				var v := float((dem as Dictionary)[it])
				if best.is_empty() or v > float(best["v"]):
					best = {"city": str(c), "item": str(it), "v": v}
		if not best.is_empty() and float(best["v"]) > 1.1:
			cands.append({"kind": "price", "key": "inn.rumor.price", "args": [str(best["item"]), str(best["city"])]})
	# 2. A global event in force.
	for ev: Variant in st.events_active:
		if ev is Dictionary and str((ev as Dictionary).get("def", "")) != "":
			cands.append({"kind": "event", "key": "inn.rumor.event", "args": [str(ev["def"])]})
			break
	# 3. A rival family in debt.
	var owner := str(st.buildings.get(bld, {}).get("owner", ""))
	var loans: Array = st.loans.keys()
	loans.sort()
	for l: Variant in loans:
		var ln: Dictionary = st.loans[l]
		var fam := str(ln.get("family", ""))
		if fam != owner and Loans.is_open(ln) and int(ln.get("outstanding", 0)) > 0 and st.families.has(fam) \
				and not TownLife.is_household(st, fam):
			cands.append({"kind": "debt", "key": "inn.rumor.debt", "args": [str(st.families[fam].get("name", fam)),
				int(ln.get("outstanding", 0))]})
			break
	if cands.is_empty():
		return {}
	var day := Clock.day(int(st.clock["minute"]))
	return cands[Kin.randi_range(st, "inn|rumor|%s|%d" % [bld, day], 0, cands.size() - 1)]


static func _from_life(sim: Sim, bld: String, by: String) -> Dictionary:
	var st := sim.state
	var now := int(st.clock["minute"])
	var cands := Rumors.candidates(sim, now)
	if cands.is_empty():
		return {}
	var mcfg: Dictionary = Rumors.cfg(sim)
	var topics: Array = mcfg.get("kinds", {}).get("tavern", {}).get("topics", [])
	var heard := {}
	for h: Dictionary in Rumors.heard(st):
		heard[str(h.get("key", ""))] = true
	var weights: Array = []
	var total := 0.0
	for c: Dictionary in cands:
		var w := float(c.get("weight", 1.0))
		if str(c.get("topic", "")) in topics:
			w *= float(mcfg.get("topic_mult", 3.0))
		if bool(c.get("useful", false)):
			w *= 2.0
		if heard.has(str(c.get("key", ""))):
			w *= float(mcfg.get("heard_mult", 0.25))
		weights.append(w)
		total += w
	var r := Kin.roll(st, "inn|rumor|%s|%d" % [bld, Clock.day(now)]) * total
	var pick: Dictionary = cands[cands.size() - 1]
	for i: int in cands.size():
		r -= float(weights[i])
		if r < 0.0:
			pick = cands[i]
			break
	var out := {"kind": "life", "key": str(pick["key"]), "rumor": str(pick["rumor"]), "text_key": str(pick["text_key"]),
		"params": (pick.get("params", {}) as Dictionary).duplicate(true), "useful": bool(pick.get("useful", false))}
	if by != "" and not heard.has(out["key"]):
		var entry := out.duplicate(true)
		entry.erase("kind")
		entry["minute"] = now
		entry["point"] = "inn:" + bld
		entry["by"] = by
		var b := Rumors.book(st)
		(b["heard"] as Array).append(entry)
		while (b["heard"] as Array).size() > int(mcfg.get("keep_heard", 60)):
			(b["heard"] as Array).pop_front()
		sim.events.append({"type": "rumor_heard", "character": by, "rumor": out["rumor"], "key": out["key"],
			"point": entry["point"], "useful": out["useful"]})
	return out
