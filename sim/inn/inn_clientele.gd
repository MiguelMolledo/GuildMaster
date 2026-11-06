class_name InnClientele
extends RefCounted
## Who comes to a Taberna-Posada tonight and why the others do not (docs/gdd/04f_vida_y_fiestas.md §4.27.2): the
## groups of data/inn/clientele.json, the provider choice of 4.22.3.2 (data/services.json) times the group's taste
## (menu, ambience, fame, season, upgrades) and the requirements of each group. Pure reads: nothing here writes the
## state. The arrivals themselves are drawn by Inn.open_turn with the keyed stream "inn|..." (never state.rng).
##
## The sources of each group: townsfolk (the town's adults × tavern.visits_per_adult), visitors (the visitors of the
## day: today the test generator of data/inn/inn.json test_visitors; when the life block arrives, state.town.visitors,
## 4.24.3) and base (per_night [min, max] at full attraction).


## {group -> {expected: float, came_ok: bool, reasons: [{key, args}], base: float, attraction: float, taste: float}}
## for building `bld` now. reasons are i18n keys of «why they do not come» (ui.inn.why.<key>), with their numbers.
static func outlook(sim: Sim, bld: String) -> Dictionary:
	var out := {}
	var cl: Dictionary = sim.catalog.inn.get("clientele", {})
	for g: Variant in cl.get("order", []):
		out[str(g)] = group_outlook(sim, bld, str(g))
	return out


static func group_outlook(sim: Sim, bld: String, g: String) -> Dictionary:
	var def: Dictionary = sim.catalog.inn.get("clientele", {}).get("groups", {}).get(g, {})
	var reasons: Array = _missing(sim, bld, def)
	var price := menu_price_mult(sim, bld, def)
	var liked := liked_on_menu(sim, bld, def)
	if liked.is_empty():
		reasons.append({"key": "nothing_liked", "args": []})
	elif price > float(def.get("max_price_mult", 2.0)) + 0.001:
		reasons.append({"key": "too_expensive", "args": [num(price), num(float(def.get("max_price_mult", 2.0)))]})
	var base := base_count(sim, def, bld)
	var attraction := provider_share(sim, bld, price)
	var taste := taste(sim, bld, g, def, liked)
	var expected := 0.0 if not reasons.is_empty() else base * attraction * taste
	if str(def.get("source", "")) == "agenda":
		expected = base  # they are the ones on their way: the agenda already chose
		if reasons.is_empty() and base <= 0.0:
			reasons.append({"key": "no_neighbours", "args": []})
	elif reasons.is_empty() and base <= 0.0:
		reasons.append({"key": "nobody_in_town", "args": []})
	return {"expected": expected, "came_ok": reasons.is_empty(), "reasons": reasons, "base": base,
		"attraction": attraction, "taste": taste, "price": price}


## What the group lacks to come: [{key, args}] (empty = it may come).
static func _missing(sim: Sim, bld: String, def: Dictionary) -> Array:
	var out: Array = []
	var b: Dictionary = sim.state.buildings.get(bld, {})
	var inn: Dictionary = b.get("inn", {})
	for r: Dictionary in def.get("requires", []):
		match str(r.get("kind", "")):
			"beds_free":
				if Inn.beds_free(sim, bld) <= 0:
					out.append({"key": "no_beds", "args": []})
			"bed_price":
				if float(inn.get("bed_price", 1.0)) > float(r.get("max", 1.0)) + 0.001:
					out.append({"key": "beds_expensive", "args": [num(float(inn.get("bed_price", 1.0))),
						num(float(r.get("max", 1.0)))]})
			"fame":
				if Inn.fame_level(sim, bld) < int(r.get("min", 0)):
					out.append({"key": "fame_low", "args": [Inn.fame_level(sim, bld), int(r.get("min", 0))]})
			"ambience":
				if Inn.ambience(sim, bld) < int(r.get("min", 0)):
					out.append({"key": "ambience_low", "args": [Inn.ambience(sim, bld), int(r.get("min", 0))]})
			"good_wine":
				if not "wine" in (inn.get("menu", []) as Array) or Inn.wine_quality(sim, bld) < 1:
					out.append({"key": "no_good_wine", "args": []})
			"dish":
				if not str(r.get("dish", "")) in (inn.get("menu", []) as Array):
					out.append({"key": "no_dish", "args": [str(r.get("dish", ""))]})
			"gaming_table":
				if not Upgrades.flag(sim, bld, "inn_gaming_table"):
					out.append({"key": "no_gaming_table", "args": []})
			"license":
				if not Inn.licensed(sim, bld):
					out.append({"key": "no_license", "args": []})
	return out


## The dishes of the group's list that are on the menu, in its order of taste.
static func liked_on_menu(sim: Sim, bld: String, def: Dictionary) -> Array:
	var menu: Array = sim.state.buildings.get(bld, {}).get("inn", {}).get("menu", [])
	var out: Array = []
	for d: Variant in (def.get("drinks", []) as Array) + (def.get("foods", []) as Array):
		if str(d) in menu and not str(d) in out:
			out.append(str(d))
	return out


## The mean price multiplier of the dishes the group likes that are on the menu (1.0 if none).
static func menu_price_mult(sim: Sim, bld: String, def: Dictionary) -> float:
	var liked := liked_on_menu(sim, bld, def)
	if liked.is_empty():
		return 1.0
	var s := 0.0
	for d: String in liked:
		s += Inn.price_mult(sim, bld, d)
	return s / float(liked.size())


## How many of the group there are tonight before the attraction (the town's adults, the visitors, or the base mean).
static func base_count(sim: Sim, def: Dictionary, bld_hint: String = "") -> float:
	match str(def.get("source", "base")):
		"agenda":  # 04g: the neighbours that their agenda sends here come in person (Inn.neighbour_in)
			return float(InnClientele.neighbours_coming(sim, bld_hint))
		"townsfolk":
			var visits := float(sim.catalog.services.get("services", {}).get("tavern", {}).get("visits_per_adult", 0.25))
			return float(town_adults(sim)) * visits
		"visitors":
			if Life.on(sim) and def.has("visitor_kinds"):  # vida: the real ones of its kinds still in town
				return float(lodger_candidates(sim, def).size()) * float(def.get("bed", 1.0))
			return float(visitors_today(sim)) * float(def.get("visitor_share", 0.0))
	var span: Array = def.get("per_night", [0, 0])
	return (float(span[0]) + float(span[1])) / 2.0


## The adult townsfolk (H7) of the town.
static func town_adults(sim: Sim) -> int:
	var n := 0
	for id: Variant in sim.state.characters:
		if TownLife.is_townsperson(sim.state, str(id)) and TownLife.is_adult(sim.state, sim.catalog, str(id)):
			n += 1
	return n


## The visitors that pass through the town today. Hook for the life block (4.24.3): when its generator is on, the
## test generator is switched off in data/inn/inn.json (test_visitors.enabled false) and the living visitors count.
static func visitors_today(sim: Sim) -> int:
	var tv: Dictionary = sim.catalog.inn.get("rules", {}).get("test_visitors", {})
	if Life.on(sim) or not bool(tv.get("enabled", true)):
		return Visitors.alive(sim.state).size()
	var span: Array = tv.get("per_day", [2, 4])
	var day := Clock.day(int(sim.state.clock["minute"]))
	return Kin.randi_range(sim.state, "inn|visitors|%d" % day, int(span[0]), int(span[1]))


## Vida (04g): the townsfolk whose agenda has the tavern as activity now (on their way, at its door or inside) and whose
## household can pay the cheapest dish of `bld`'s menu (the others chat at the door: Inn.neighbour_in).
static func neighbours_coming(sim: Sim, bld: String = "") -> int:
	if not Life.on(sim):
		return 0
	var cheapest := 0
	if bld != "":
		cheapest = -1
		for d: Variant in sim.state.buildings.get(bld, {}).get("inn", {}).get("menu", []):
			var pr := Inn.dish_price(sim, bld, str(d), 0)
			if cheapest < 0 or pr < cheapest:
				cheapest = pr
		if cheapest < 0:
			return 0
	var n := 0
	for id: Variant in sim.state.characters:
		var ch: Dictionary = sim.state.characters[id]
		var t: Variant = ch.get("town")
		if not t is Dictionary or str((t as Dictionary).get("activity", "")) != "tavern":
			continue
		if Inn.hosting(sim.state, str(id)) or Money.gold(sim.state, str(ch.get("family", ""))) >= cheapest:
			n += 1
	return n


## Vida: the visitors in town of the group's visitor_kinds that have not left (the ones already lodging count) (sorted).
static func lodger_candidates(sim: Sim, def: Dictionary) -> Array:
	var out: Array = []
	var kinds: Array = def.get("visitor_kinds", [])
	for v: String in Visitors.alive(sim.state):
		var vis: Variant = sim.state.characters[v].get("visitor")
		if vis is Dictionary and str((vis as Dictionary).get("kind", "")) in kinds \
				and (str((vis as Dictionary).get("lodging", "")) != "" or not bool((vis as Dictionary).get("leaving", false))):
			out.append(v)
	return out


## The group of the tavern's clientele a visitor of `kind` belongs to ("" if none: the beggar, the minstrel).
static func group_of_visitor(sim: Sim, kind: String) -> String:
	var groups: Dictionary = sim.catalog.inn.get("clientele", {}).get("groups", {})
	for g: Variant in sim.catalog.inn.get("clientele", {}).get("order", []):
		if kind in (groups.get(g, {}).get("visitor_kinds", []) as Array):
			return str(g)
	return ""


## The provider choice of 4.22.3.2 with one provider: P = a / (a + no_go), a = (1 / price)^elasticity × (1 + min(rep /
## divisor, cap)) × (1 + commerce bonus: the menu board).
static func provider_share(sim: Sim, bld: String, price: float) -> float:
	var a := Clientele.provider_appeal(sim, bld, price, "inn_customers")  # Equilibrio 14: one formula with the shops
	return a / (a + float(sim.catalog.services.get("no_go", 0.5)))


## The group's taste for the house: liked dishes (+10 % each after the first), fame, the special of the house, the
## dishes of the season, the stable (merchants), the hearth in winter, the events' customers effect (H13) and the
## scare of the pilgrims after a fight.
static func taste(sim: Sim, bld: String, g: String, def: Dictionary, liked: Array) -> float:
	if liked.is_empty():
		return 0.0
	var inn: Dictionary = sim.state.buildings.get(bld, {}).get("inn", {})
	var menu_cfg: Dictionary = sim.catalog.inn.get("menu", {})
	var t := 1.0 + 0.1 * float(liked.size() - 1)
	t *= 1.0 + float(def.get("likes_fame", 0.0)) * Inn.fame(sim, bld)
	var special := str(inn.get("special", ""))
	if special != "" and special in liked:
		t *= float(menu_cfg.get("special_mult", 1.15))
	var season := Clock.season(int(sim.state.clock["minute"]), sim.catalog.time)
	for d: String in liked:
		var dd: Dictionary = menu_cfg.get("dishes", {}).get(d, {})
		var feast := str(dd.get("festival", ""))
		var on := feast_today(sim, feast) if Festivals.enabled(sim) and feast != "" else str(dd.get("season", "")) == season
		if on:
			t *= float(menu_cfg.get("seasonal_mult", 1.5))
			break
	if def.has("stable_mult") and Upgrades.flag(sim, bld, "inn_stable"):
		t *= float(def["stable_mult"])
	if season == "winter" and Upgrades.flag(sim, bld, "inn_hearth"):
		t *= 1.3
	t *= maxf(WorldEvents.customers_mult(sim), 0.0)
	t *= maxf(Festivals.hook_mult(sim, "service", "tavern"), 0.0)  # fiestas: San Juan and Carnival ×2, the fair ×3
	var day := Clock.day(int(sim.state.clock["minute"]))
	if g == "pilgrims" and int(inn.get("pilgrims_scared_until", -1)) >= day:
		t *= float(sim.catalog.inn.get("rules", {}).get("incidents", {}).get("pilgrims_after_fight_mult", 0.3))
	return t


## A float as the reasons write it (1 decimal, no trailing .0).
static func num(v: float) -> String:
	var s := "%.1f" % v
	return s.trim_suffix(".0")


## Fiestas: whether the feast `id` of data/festivals.json is on today (running or to start today).
static func feast_today(sim: Sim, id: String) -> bool:
	for i: Dictionary in Festivals._today(sim):
		if str(i.get("def", "")) == id:
			return true
	return false
