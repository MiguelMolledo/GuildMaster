class_name InnRumors
extends RefCounted
## The useful rumour of the night (docs/gdd/04f_vida_y_fiestas.md §4.27.6): with a loyal barkeeper (or a family member
## who served at the bar), the turn summary brings one rumour about something true of the world. Hook for the life
## block (4.24.2, data/life/rumors.json and the book of rumours): until it arrives, three kinds read straight from the
## state, each as {kind, key, args}: the price of a good in another city of the region (region.cities demand), the
## next global event in force (events_active) or the debt of a rival family (its open loans). Pure read; the choice
## uses the keyed stream "inn|rumor|<bld>|<day>".


## A rumour for `bld` tonight, or {} if there is nothing true to tell.
static func pick(sim: Sim, bld: String) -> Dictionary:
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
