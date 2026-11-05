class_name Inn
extends RefCounted
## The Taberna-Posada (docs/gdd/04f_vida_y_fiestas.md §4.27; brings forward 4.22.4.5 of 04d): a second business any
## family can buy (O-V7 a), with its menu, its clientele by groups, the night turn (dusk to 02:00), the rooms, the
## incidents, the turn summary and the fame. Figures: data/inn/inn.json (rules), menu.json, clientele.json and
## data/services.json; the upgrade tree data/upgrades/tavern_inn/ (effects inn_*). Pure rules, deterministic: every
## roll uses the keyed stream "inn|<what>|<bld>|<day>|..." (Kin.roll), never state.rng (principle 3 of 04f).
##
## State (save v19): buildings[bld].inn =
##   {menu: [dish], prices: {dish: mult}, bed_price: mult, special: dish | "", fame: float 0-5, license_until: day
##    (-1 = none), broken_until: day, pilgrims_scared_until: day, beds: [{state: made | occupied | dirty | making,
##    guest, until, by}], night: {} | turn, last_turn: {} | summary, history: [{day, guests, income, tips, fame,
##    beds}], rumors: [{day, kind, key, args}], seq: int}
## A turn (night): {day, open_at, close_at, arrivals: [{at, group, chr}], next: int, guests: [guest], servers: {chr:
##   free_at}, minstrel: bool, fight_at: int, offer_at: int, stats: {...}, outlook: {group: {expected, reasons}}}
## A guest: {id, group, chr, name_n, seat, state: seated | waiting | eating | gone, next_at, order, since, until,
##   rounds_left, bed: int (-1), quality, served_by, paid, tips}
## The buildings for sale: buildings[bld].for_sale = true (no owner) until buy_building.
## Guests are not characters: they live in the turn (chr links the neighbours that come in person, 04g, and the lodging
## visitors). The life block
## (4.24.1) will send real townsfolk through arrive().

const TYPE: String = "tavern_inn"


# --- Reads ---------------------------------------------------------------------------------------------------------

static func is_inn(sim: Sim, bld: String) -> bool:
	return str(sim.state.buildings.get(bld, {}).get("type", "")) == TYPE


static func rules(sim: Sim) -> Dictionary:
	return sim.catalog.inn.get("rules", {})


static func dish(sim: Sim, id: String) -> Dictionary:
	return sim.catalog.inn.get("menu", {}).get("dishes", {}).get(id, {})


static func dishes(sim: Sim) -> Array:
	var ids: Array = sim.catalog.inn.get("menu", {}).get("dishes", {}).keys()
	ids.sort()
	return ids


static func state_of(sim: Sim, bld: String) -> Dictionary:
	return sim.state.buildings.get(bld, {}).get("inn", {})


static func fame(sim: Sim, bld: String) -> float:
	return float(state_of(sim, bld).get("fame", 0.0))


static func fame_level(sim: Sim, bld: String) -> int:
	return int(floor(fame(sim, bld) + 0.0001))


## Ambience 0-5: base + the upgrades (inn_ambience) − a fight without porter still broken today.
static func ambience(sim: Sim, bld: String) -> int:
	var a: Dictionary = rules(sim).get("ambience", {})
	var v := int(a.get("base", 1)) + int(Upgrades.amount(sim, bld, "inn_ambience"))
	if int(state_of(sim, bld).get("broken_until", -1)) >= Clock.day(int(sim.state.clock["minute"])):
		v -= int(a.get("fight_penalty", 1))
	return clampi(v, 0, int(a.get("max", 5)))


static func seats(sim: Sim, bld: String) -> int:
	return int(rules(sim).get("seats", 8)) + int(Upgrades.amount(sim, bld, "inn_seats"))


static func bed_count(sim: Sim, bld: String) -> int:
	return int(rules(sim).get("beds", 4)) + int(Upgrades.amount(sim, bld, "inn_beds"))


static func menu_slots(sim: Sim, bld: String) -> int:
	return int(rules(sim).get("menu_slots", 6)) + int(Upgrades.amount(sim, bld, "inn_menu_slots"))


## The quality the cellar adds to the wine served (0 without Bodega).
static func wine_quality(sim: Sim, bld: String) -> int:
	return int(Upgrades.amount(sim, bld, "inn_wine_quality"))


static func licensed(sim: Sim, bld: String) -> bool:
	return int(state_of(sim, bld).get("license_until", -1)) >= Clock.day(int(sim.state.clock["minute"]))


static func price_mult(sim: Sim, bld: String, d: String) -> float:
	return float(state_of(sim, bld).get("prices", {}).get(d, 1.0))


## The price of one dish at quality q: ref × the owner's multiplier × quality_mult[q], at least 1.
static func dish_price(sim: Sim, bld: String, d: String, q: int) -> int:
	var qm: Array = rules(sim).get("quality_mult", [1.0, 1.15, 1.3])
	return maxi(1, roundi(float(dish(sim, d).get("ref_price", 1)) * price_mult(sim, bld, d) * float(qm[clampi(q, 0, qm.size() - 1)])))


## The price of a bed (good room: double).
static func bed_price(sim: Sim, bld: String, good: bool) -> int:
	var ref := float(sim.catalog.services.get("services", {}).get("inn", {}).get("ref_price", 12))
	return maxi(1, roundi(ref * float(state_of(sim, bld).get("bed_price", 1.0)) * (2.0 if good else 1.0)))


static func beds_free(sim: Sim, bld: String) -> int:
	var n := 0
	for b: Dictionary in state_of(sim, bld).get("beds", []):
		if str(b.get("state", "")) == "made":
			n += 1
	return n


## Units of the dish's item in the storage (any quality).
static func stock(sim: Sim, bld: String, d: String) -> int:
	var item := str(dish(sim, d).get("item", d))
	return Inventory.count(sim.state.buildings.get(bld, {}).get("inventory", {}), item)


## Whether the turn is running at `bld` now.
static func is_open(sim: Sim, bld: String) -> bool:
	return not (state_of(sim, bld).get("night", {}) as Dictionary).is_empty()


## The guests inside now (not gone).
static func guests(sim: Sim, bld: String) -> Array:
	var out: Array = []
	for g: Dictionary in state_of(sim, bld).get("night", {}).get("guests", []):
		if str(g.get("state", "")) != "gone":
			out.append(g)
	return out


static func guest(sim: Sim, bld: String, gid: String) -> Dictionary:
	for g: Dictionary in state_of(sim, bld).get("night", {}).get("guests", []):
		if str(g.get("id", "")) == gid:
			return g
	return {}


## The minutes of today's turn: [open, close] (absolute).
static func turn_window(sim: Sim, minute: int) -> Array:
	var hours: Dictionary = rules(sim).get("hours", {})
	var day := Clock.day(minute)
	var starts: Dictionary = sim.catalog.time["phase_starts"][Clock.season(minute, sim.catalog.time)]
	var open := day * Clock.MINUTES_PER_DAY + int(starts.get(str(hours.get("open_phase", "dusk")), 1140))
	var close := (day + 1) * Clock.MINUTES_PER_DAY + int(hours.get("close_hour", 2)) * 60
	return [open, close]


# --- State ---------------------------------------------------------------------------------------------------------

## The inn state of a building of type tavern_inn (created the first time).
static func ensure(sim: Sim, bld: String) -> Dictionary:
	var b: Dictionary = sim.state.buildings[bld]
	if not b.get("inn") is Dictionary:
		b["inn"] = fresh_state(sim.catalog)
	var inn: Dictionary = b["inn"]
	var want := bed_count(sim, bld)
	var beds: Array = inn["beds"]
	while beds.size() < want:
		beds.append({"state": "made", "guest": "", "until": -1, "by": ""})
	return inn


static func fresh_state(catalog: Catalog) -> Dictionary:
	var r: Dictionary = catalog.inn.get("rules", {})
	var beds: Array = []
	for i: int in int(r.get("beds", 4)):
		beds.append({"state": "made", "guest": "", "until": -1, "by": ""})
	return {"menu": (r.get("default_menu", []) as Array).duplicate(), "prices": {}, "bed_price": 1.0, "special": "",
		"fame": float(r.get("fame", {}).get("start", 0.0)), "license_until": -1, "broken_until": -1,
		"pilgrims_scared_until": -1, "beds": beds, "night": {}, "last_turn": {}, "history": [], "rumors": [], "seq": 0}


# --- Step ----------------------------------------------------------------------------------------------------------

## Once per minute, after Production (the kitchen's cycles) and before Market. Only owned taverns run.
static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var dawn := false
	for e: Dictionary in sim.events:
		if str(e.get("type", "")) == "phase_changed" and str(e.get("phase", "")) == "dawn":
			dawn = true
	InnGames.hear(sim)  # the games played at a tavern's table this step (the orders came before the systems)
	var ids: Array = st.buildings.keys()
	ids.sort()
	for bld: String in ids:
		var b: Dictionary = st.buildings[bld]
		if str(b.get("type", "")) != TYPE or str(b.get("owner", "")) == "":
			continue
		var inn := ensure(sim, bld)
		if dawn:
			_dawn(sim, bld, inn)
		_rooms(sim, bld, inn, now)
		var night: Dictionary = inn["night"]
		if night.is_empty():
			var w := turn_window(sim, now)
			if now >= int(w[0]) and now < int(w[1]) and int(inn.get("last_turn", {}).get("day", -1)) != Clock.day(now) \
					and str(b.get("state", "normal")) == "normal":
				open_turn(sim, bld, int(w[0]), int(w[1]))
			continue
		_turn_minute(sim, bld, inn, now)
		if now >= int(night["close_at"]):
			close_turn(sim, bld)


## Opens tonight's turn: the clientele outlook, the arrivals of each group (keyed draws), the minstrel, the fight and
## the game offer.
static func open_turn(sim: Sim, bld: String, open_at: int, close_at: int) -> void:
	var st := sim.state
	var inn: Dictionary = ensure(sim, bld)
	var r := rules(sim)
	var day := Clock.day(open_at)
	var outlook := InnClientele.outlook(sim, bld)
	var minstrel := Upgrades.flag(sim, bld, "inn_minstrel") \
		and Kin.roll(st, "inn|minstrel|%s|%d" % [bld, day]) < float(r.get("incidents", {}).get("minstrel", {}).get("chance", 0.35))
	var mult := float(r.get("incidents", {}).get("minstrel", {}).get("arrivals_mult", 1.2)) if minstrel else 1.0
	var last := close_at - int(r.get("hours", {}).get("last_arrival_before_close", 60))
	var span := maxi(1, last - open_at)
	var arrivals: Array = []
	var counts := {}
	var groups_def: Dictionary = sim.catalog.inn.get("clientele", {}).get("groups", {})
	for g: String in outlook:
		if str(groups_def.get(g, {}).get("source", "")) == "agenda" or (Life.on(sim) \
				and str(groups_def.get(g, {}).get("source", "")) == "visitors"):
			counts[g] = 0
			continue  # vida: the visitors come in person (lodge), not drawn here
		var want_n := float(outlook[g]["expected"]) * mult
		var n := int(floor(want_n))
		if Kin.roll(st, "inn|frac|%s|%d|%s" % [bld, day, g]) < want_n - float(n):
			n += 1
		var party: Array = sim.catalog.inn.get("clientele", {}).get("groups", {}).get(g, {}).get("party", [1, 1])
		var people := 0
		for k: int in n:
			var u := _triangular(Kin.roll(st, "inn|at|%s|%d|%s|%d" % [bld, day, g, k]),
				float(r.get("hours", {}).get("arrival_peak", 0.35)))
			var size := Kin.randi_range(st, "inn|party|%s|%d|%s|%d" % [bld, day, g, k], int(party[0]), int(party[1]))
			for p: int in size:
				var chr := ""  # the comarca and the travellers drawn here have no name in town (04g)
				arrivals.append({"at": open_at + int(float(span) * u) + p, "group": g, "chr": chr, "k": k * 10 + p})
				people += 1
		counts[g] = people
	arrivals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["at"]) != int(b["at"]):
			return int(a["at"]) < int(b["at"])
		if str(a["group"]) != str(b["group"]):
			return str(a["group"]) < str(b["group"])
		return int(a["k"]) < int(b["k"]))
	var fight_cfg: Dictionary = r.get("incidents", {}).get("fight", {})
	var soldiers := int(counts.get("soldiers", 0))
	var gamblers := int(counts.get("gamblers", 0))
	var chance := float(fight_cfg.get("base", 0.06)) + float(fight_cfg.get("per_soldier", 0.05)) * soldiers \
		+ float(fight_cfg.get("per_gambler", 0.02)) * gamblers
	if Upgrades.flag(sim, bld, "inn_night_watch"):
		chance *= float(fight_cfg.get("night_watch_mult", 0.5))
	var fight_at := -1
	var after := day * Clock.MINUTES_PER_DAY + int(fight_cfg.get("after_hour", 22)) * 60
	if arrivals.size() >= 3 and Kin.roll(st, "inn|fight|%s|%d" % [bld, day]) < chance:
		fight_at = after + Kin.randi_range(st, "inn|fight_at|%s|%d" % [bld, day], 0, maxi(1, close_at - after - 30))
	var offer_at := -1
	if gamblers > 0 and Kin.roll(st, "inn|offer|%s|%d" % [bld, day]) < float(r.get("incidents", {}).get("game_offer", {}).get("chance", 0.5)):
		offer_at = after + Kin.randi_range(st, "inn|offer_at|%s|%d" % [bld, day], 0, maxi(1, close_at - after - 30))
	var dirty := 0
	for bd: Dictionary in inn["beds"]:
		if str(bd.get("state", "")) in ["dirty", "making"]:
			dirty += 1
	var view_outlook := {}
	for g: String in outlook:
		view_outlook[g] = {"expected": snappedf(float(outlook[g]["expected"]), 0.01), "reasons": outlook[g]["reasons"],
			"price": snappedf(float(outlook[g]["price"]), 0.01)}
	inn["night"] = {"day": day, "open_at": open_at, "close_at": close_at, "arrivals": arrivals, "next": 0,
		"guests": [], "servers": {}, "minstrel": minstrel, "fight_at": fight_at, "offer_at": offer_at,
		"outlook": view_outlook, "stats": {"by_group": {}, "dishes": {}, "income": 0, "tips": 0, "beds_income": 0,
		"house_cut": 0, "complaints": {}, "satisfied": 0, "excellent": 0, "fights": 0, "fight_stopped": 0,
		"dashes": 0, "dash_caught": 0, "beds": 0, "dirty_beds": dirty, "served_by_kin": 0, "incidents": []}}
	sim.events.append({"type": "inn_turn_opened", "building": bld, "day": day, "arrivals": arrivals.size(),
		"minstrel": minstrel})
	if OS.is_debug_build():
		print("[Inn] %s abre el turno del día %d: %d llegadas %s, juglar=%s, pelea=%s, camas sin hacer=%d" % [bld, day,
			arrivals.size(), counts, minstrel, fight_at, dirty])


## The inverse of a triangular distribution on [0, 1] with its mode at `peak`, for a uniform `u`.
static func _triangular(u: float, peak: float) -> float:
	var c := clampf(peak, 0.01, 0.99)
	if u < c:
		return sqrt(u * c)
	return 1.0 - sqrt((1.0 - u) * (1.0 - c))


## One minute of the turn: arrivals, the guests' states, the staff serving, the incidents.
static func _turn_minute(sim: Sim, bld: String, inn: Dictionary, now: int) -> void:
	var night: Dictionary = inn["night"]
	var arrivals: Array = night["arrivals"]
	while int(night["next"]) < arrivals.size() and int(arrivals[int(night["next"])]["at"]) <= now:
		var a: Dictionary = arrivals[int(night["next"])]
		night["next"] = int(night["next"]) + 1
		arrive(sim, bld, str(a["group"]), str(a.get("chr", "")))
	for g: Dictionary in night["guests"]:
		match str(g.get("state", "")):
			"seated":
				if now >= int(g["next_at"]):
					_decide(sim, bld, inn, g, now)
			"waiting":
				if now >= int(g["until"]):
					_leave(sim, bld, g, "slow", true)
			"eating":
				if now >= int(g["until"]):
					_pay(sim, bld, inn, g, now)
	_staff_serve(sim, bld, inn, now)
	if int(night.get("fight_at", -1)) >= 0 and now == int(night["fight_at"]):
		_fight(sim, bld, inn, now)
	if int(night.get("offer_at", -1)) >= 0 and now == int(night["offer_at"]):
		_game_offer(sim, bld, inn)


## A guest of `group` comes in (the turn's arrivals; the life block's townsfolk later): sits at a free seat or leaves
## («full»); asks for a bed at once if it wants one (paid on arrival, 4.22.4.5). Returns the guest id ("" if it left).
static func arrive(sim: Sim, bld: String, group: String, chr: String = "", wants_bed: bool = false) -> String:
	var st := sim.state
	var inn := ensure(sim, bld)
	var night: Dictionary = inn["night"]
	if night.is_empty():
		return ""
	var now := int(st.clock["minute"])
	var def: Dictionary = sim.catalog.inn.get("clientele", {}).get("groups", {}).get(group, {})
	inn["seq"] = int(inn.get("seq", 0)) + 1
	var gid := "gst_%d" % int(inn["seq"])
	var by_group: Dictionary = night["stats"]["by_group"]
	if not by_group.has(group):
		by_group[group] = {"came": 0, "served": 0, "left": 0, "income": 0}
	by_group[group]["came"] = int(by_group[group]["came"]) + 1
	var taken := {}
	for g: Dictionary in night["guests"]:
		if str(g.get("state", "")) != "gone":
			taken[int(g.get("seat", -1))] = true
	var seat := -1
	for i: int in seats(sim, bld):
		if not taken.has(i):
			seat = i
			break
	var day := int(night["day"])
	var rr: Array = def.get("rounds", [1, 1])
	var g := {"id": gid, "group": group, "chr": chr, "name_n": int(inn["seq"]), "seat": seat, "state": "seated",
		"next_at": now + Kin.randi_range(st, "inn|dec|%s|%s" % [bld, gid], int(rules(sim)["guest"]["decide_minutes"][0]),
			int(rules(sim)["guest"]["decide_minutes"][1])), "order": "", "since": now, "until": -1,
		"rounds_left": Kin.randi_range(st, "inn|rounds|%s|%d|%s" % [bld, day, gid], int(rr[0]), int(rr[1])),
		"bed": -1, "quality": 0, "served_by": "", "paid": 0, "tips": 0, "arrived": now}
	(night["guests"] as Array).append(g)
	sim.events.append({"type": "inn_guest_arrived", "building": bld, "guest": gid, "group": group, "chr": chr})
	if seat < 0:
		_leave(sim, bld, g, "full", true)
		return ""
	if wants_bed or Kin.roll(st, "inn|bed|%s|%s" % [bld, gid]) < float(def.get("bed", 0.0)):
		_take_bed(sim, bld, inn, g, bool(def.get("good_room", false)))
	return gid


## Picks the order: a drink or a food (food_share); among the dishes of that list on the menu with stock, one drawn
## with weight 3-2-1 by the group's order of taste; if that list has none, the other list. Nothing on the menu =
## not_on_menu; on the menu but out of stock = sold_out (both leave without paying, with a complaint).
static func _decide(sim: Sim, bld: String, inn: Dictionary, g: Dictionary, now: int) -> void:
	var def: Dictionary = sim.catalog.inn.get("clientele", {}).get("groups", {}).get(str(g["group"]), {})
	var menu: Array = inn.get("menu", [])
	var key := "%s|%s|%d" % [bld, g["id"], int(g["rounds_left"])]
	var food := Kin.roll(sim.state, "inn|kind|" + key) < float(def.get("food_share", 0.4))
	var lists: Array = [def.get("foods", []), def.get("drinks", [])] if food else [def.get("drinks", []), def.get("foods", [])]
	var on_menu := false
	for lst: Variant in lists:
		var cands: Array = []
		var weights: Array = []
		var total := 0
		for d: Variant in lst:
			if not str(d) in menu:
				continue
			on_menu = true
			if stock(sim, bld, str(d)) > 0 and dish_price(sim, bld, str(d), best_quality(sim, bld, str(d))) <= max_price(sim, bld, g, str(d)):
				var wgt := maxi(1, 3 - cands.size())
				cands.append(str(d))
				weights.append(wgt)
				total += wgt
		if cands.is_empty():
			continue
		var x := Kin.randi_range(sim.state, "inn|dish|" + key, 0, total - 1)
		var pick := str(cands[0])
		for i: int in cands.size():
			x -= int(weights[i])
			if x < 0:
				pick = str(cands[i])
				break
		g["order"] = pick
		g["state"] = "waiting"
		g["since"] = now
		var pat := float(def.get("patience", 30)) * (1.0 + 0.05 * float(ambience(sim, bld)))
		g["until"] = now + roundi(pat)
		sim.events.append({"type": "inn_guest_ordered", "building": bld, "guest": g["id"], "dish": pick})
		return
	var why := "not_on_menu"
	if on_menu:
		why = "sold_out"
		for lst: Variant in lists:
			for d: Variant in lst:
				if str(d) in menu and stock(sim, bld, str(d)) > 0:
					why = "too_expensive"  # there was some, but dearer than what this client pays
	_leave(sim, bld, g, why, why != "too_expensive" or not bool(g.get("neighbour", false)))


## The quality the guest would get of `d` now (the best in the storage, with the cellar's bonus for the wine).
static func best_quality(sim: Sim, bld: String, d: String) -> int:
	var item := str(dish(sim, d).get("item", d))
	var inv: Dictionary = sim.state.buildings[bld]["inventory"]
	for q: int in [Inventory.EXCELLENT, Inventory.GOOD, Inventory.NORMAL]:
		if Inventory.count(inv, item, q) > 0:
			return mini(Inventory.EXCELLENT, q + (wine_quality(sim, bld) if bool(dish(sim, d).get("cellar", false)) else 0))
	return Inventory.NORMAL


## The most a guest pays for one `d` (04g §4.6.5.7): ref × the quality it would get × (1 + fame × max_price_fame) ×
## the group's max_price_mult; a neighbour, besides, no more than its household's purse.
static func max_price(sim: Sim, bld: String, g: Dictionary, d: String) -> int:
	var cl: Dictionary = sim.catalog.inn.get("clientele", {})
	var def: Dictionary = cl.get("groups", {}).get(str(g.get("group", "")), {})
	var qm: Array = rules(sim).get("quality_mult", [1.0, 1.15, 1.3])
	var q := best_quality(sim, bld, d)
	var m := float(dish(sim, d).get("ref_price", 1)) * float(qm[clampi(q, 0, qm.size() - 1)]) \
		* (1.0 + fame(sim, bld) * float(cl.get("max_price_fame", 0.1))) * float(def.get("max_price_mult", 2.0))
	var top := roundi(m)
	if bool(def.get("purse", false)):
		top = mini(top, Households.spendable(sim, _purse_family(sim, g)))  # Equilibrio 15: a whim, not the food
	return top


## The household that pays for a neighbour ("" for anybody else).
static func _purse_family(sim: Sim, g: Dictionary) -> String:
	if not bool(g.get("neighbour", false)):
		return ""
	return str(sim.state.characters.get(str(g.get("chr", "")), {}).get("family", ""))


## The employees on shift and the non-player family members at the bar serve the waiting guests, one each per
## serve_*_minutes / pace. bar serves drinks first, tables food first; alone, either serves both (× both_roles_mult).
static func _staff_serve(sim: Sim, bld: String, inn: Dictionary, now: int) -> void:
	var night: Dictionary = inn["night"]
	var waiting: Array = []
	for g: Dictionary in night["guests"]:
		if str(g.get("state", "")) == "waiting":
			waiting.append(g)
	if waiting.is_empty():
		return
	var servers := servers_of(sim, bld)
	if servers.is_empty():
		return
	var roles := {}
	for s: Dictionary in servers:
		roles[str(s["role"])] = true
	var cfg: Dictionary = rules(sim).get("staff", {})
	var free: Dictionary = night["servers"]
	for s: Dictionary in servers:
		var who := str(s["chr"])
		if int(free.get(who, -1)) > now:
			continue
		var want := "drink" if str(s["role"]) == "bar" else "food"
		var alone := not roles.has("tables" if want == "drink" else "bar")
		var pick: Dictionary = {}
		for g: Dictionary in waiting:
			if str(g.get("state", "")) != "waiting":
				continue
			var gk := str(dish(sim, str(g["order"])).get("kind", "drink"))
			if gk == want:
				pick = g
				break
			if alone and pick.is_empty():
				pick = g
		if pick.is_empty():
			continue
		var kind := str(dish(sim, str(pick["order"])).get("kind", "drink"))
		var base := float(cfg.get("serve_drink_minutes" if kind == "drink" else "serve_food_minutes", 6))
		if alone:
			base *= float(cfg.get("both_roles_mult", 1.5))
		if serve(sim, bld, str(pick["id"]), who):
			free[who] = now + maxi(1, roundi(base / InnStaff.pace(sim, who)))


## Who serves on their own now: employees with role bar or tables inside, active and on shift; and family members of
## the owner (not the player's own characters, who serve by hand) at the bar station. [{chr, role}] sorted by id.
static func servers_of(sim: Sim, bld: String) -> Array:
	var st := sim.state
	var out: Array = []
	for e: String in Staff.employees_of(st, bld):
		var ch: Dictionary = st.characters[e]
		var role := str(ch["job"].get("role", ""))
		if role in ["bar", "tables"] and Staff.is_active(sim, e) and str(ch.get("location", "")) == bld \
				and InnStaff.in_shift(sim, e, bld):
			out.append({"chr": e, "role": role})
	var occ := str(st.buildings[bld].get("zones", {}).get("bar", {}).get("occupant", ""))
	if occ != "" and not Staff.works_at(st, occ, bld) and str(st.characters.get(occ, {}).get("location", "")) == bld \
			and str(st.characters[occ].get("controlled_by", "")) != "human":
		out.append({"chr": occ, "role": "bar"})
	return out


## Serves guest `gid` its order: one unit of the dish's item from the storage (the best quality there is), the guest
## starts eating. By hand (inn_serve) or by the staff. false if it cannot (no such guest waiting, no stock).
static func serve(sim: Sim, bld: String, gid: String, by: String) -> bool:
	var g := guest(sim, bld, gid)
	if g.is_empty() or str(g.get("state", "")) != "waiting":
		return false
	var d := str(g["order"])
	var item := str(dish(sim, d).get("item", d))
	var inv: Dictionary = sim.state.buildings[bld]["inventory"]
	var q := -1
	for qq: int in [Inventory.EXCELLENT, Inventory.GOOD, Inventory.NORMAL]:
		if Inventory.count(inv, item, qq) > 0:
			q = qq
			break
	if q < 0:
		return false
	Inventory.remove(inv, item, q, 1)
	if bool(dish(sim, d).get("cellar", false)):
		q = mini(Inventory.EXCELLENT, q + wine_quality(sim, bld))
	var now := int(sim.state.clock["minute"])
	var gr: Dictionary = rules(sim).get("guest", {})
	var span: Array = gr.get("food_minutes" if str(dish(sim, d).get("kind", "")) == "food" else "drink_minutes", [15, 25])
	g["quality"] = q
	g["wait"] = now - int(g["since"])
	g["patience"] = maxi(1, int(g["until"]) - int(g["since"]))
	g["state"] = "eating"
	g["served_by"] = by
	g["until"] = now + Kin.randi_range(sim.state, "inn|eat|%s|%s|%d" % [bld, gid, int(g["rounds_left"])], int(span[0]), int(span[1]))
	var night: Dictionary = state_of(sim, bld)["night"]
	var dd: Dictionary = night["stats"]["dishes"]
	dd[d] = int(dd.get(d, 0)) + 1
	if not bool(g.get("served_once", false)):  # the panel counts people, not rounds
		g["served_once"] = true
		night["stats"]["by_group"][str(g["group"])]["served"] = int(night["stats"]["by_group"][str(g["group"])]["served"]) + 1
	if q == Inventory.EXCELLENT:
		night["stats"]["excellent"] = int(night["stats"]["excellent"]) + 1
	if by != "" and not Staff.works_at(sim.state, by, bld):
		night["stats"]["served_by_kin"] = int(night["stats"]["served_by_kin"]) + 1
	sim.events.append({"type": "inn_guest_served", "building": bld, "guest": gid, "dish": d, "quality": q, "by": by})
	return true


## A round eaten: the bill (and its tip, by satisfaction) or the dine-and-dash; another round or goodbye.
static func _pay(sim: Sim, bld: String, inn: Dictionary, g: Dictionary, now: int) -> void:
	var st := sim.state
	var night: Dictionary = inn["night"]
	var stats: Dictionary = night["stats"]
	var def: Dictionary = sim.catalog.inn.get("clientele", {}).get("groups", {}).get(str(g["group"]), {})
	var d := str(g["order"])
	var price := dish_price(sim, bld, d, int(g.get("quality", 0)))
	var s := satisfaction(sim, bld, g)
	var tip := roundi(float(price) * float(rules(sim).get("satisfaction", {}).get("tip_rate", 0.25)) * s)
	var fam := str(st.buildings[bld].get("owner", ""))
	var dash := float(def.get("dash", 0.0))
	if Upgrades.flag(sim, bld, "inn_night_watch") and bool(rules(sim).get("incidents", {}).get("dash", {}).get("night_watch_stops", true)):
		dash = 0.0
	var key := "%s|%s|%d" % [bld, g["id"], int(g["rounds_left"])]
	if Kin.roll(st, "inn|dash|" + key) < dash:
		stats["dashes"] = int(stats["dashes"]) + 1
		var chaser := _chaser(sim, bld)
		var dc: Dictionary = rules(sim).get("incidents", {}).get("dash", {})
		var dex := int(st.characters.get(chaser, {}).get("stats", {}).get("dexterity", 0))
		if chaser != "" and Kin.roll(st, "inn|chase|" + key) < float(dc.get("chase_base", 0.35)) + float(dc.get("chase_per_dexterity", 0.05)) * dex:
			stats["dash_caught"] = int(stats["dash_caught"]) + 1
			_incident(sim, bld, "dash_caught", {"group": str(g["group"]), "by": chaser})
			tip = 0
		else:
			_incident(sim, bld, "dash", {"group": str(g["group"])})
			_leave(sim, bld, g, "dash", false)
			return
	var purse := _purse_family(sim, g)
	if purse != "":  # 04g: a neighbour pays from its household's purse (the tip only if it has it)
		tip = mini(tip, maxi(0, Money.gold(st, purse) - price))
		if not Money.change(sim, purse, -(price + tip), Money.SERVICES, "inn_bill", bld, str(g["chr"])):
			_leave(sim, bld, g, "no_money", false)
			return
		if s >= float(rules(sim).get("fame", {}).get("satisfied_at", 0.6)) and int(def.get("relation", 0)) != 0:
			var head := str(st.families.get(fam, {}).get("head", ""))
			if head != "":
				Emotions.change_relation(sim, str(g["chr"]), head, int(def["relation"]), "inn_served")
	Money.change(sim, fam, price + tip, Money.SERVICES, "inn_bill", bld)
	stats["income"] = int(stats["income"]) + price
	stats["tips"] = int(stats["tips"]) + tip
	g["paid"] = int(g["paid"]) + price
	g["tips"] = int(g["tips"]) + tip
	stats["by_group"][str(g["group"])]["income"] = int(stats["by_group"][str(g["group"])]["income"]) + price + tip
	if s >= float(rules(sim).get("fame", {}).get("satisfied_at", 0.6)):
		stats["satisfied"] = int(stats["satisfied"]) + 1
	# Equilibrio (owner, 2026-11-05): for the fame only the guest who is really pleased counts: the wait (not
	# complaining) weighs fame.wait_share instead of the satisfaction's, so the quality and the ambience matter more
	if satisfaction(sim, bld, g, float(rules(sim).get("fame", {}).get("wait_share", -1.0))) \
			>= float(rules(sim).get("fame", {}).get("satisfied_at", 0.6)):
		stats["fame_satisfied"] = int(stats.get("fame_satisfied", 0)) + 1
	if bool(def.get("gambles", false)) and licensed(sim, bld) and Upgrades.flag(sim, bld, "inn_gaming_table"):
		var hc: Array = rules(sim).get("incidents", {}).get("game_offer", {}).get("house_cut", [2, 6])
		var cut := Kin.randi_range(st, "inn|cut|" + key, int(hc[0]), int(hc[1]))
		Money.change(sim, fam, cut, Money.SERVICES, "inn_house_cut", bld)
		stats["house_cut"] = int(stats["house_cut"]) + cut
	g["rounds_left"] = int(g["rounds_left"]) - 1
	if int(g["rounds_left"]) > 0:
		var br: Array = rules(sim).get("guest", {}).get("between_rounds_minutes", [3, 8])
		g["state"] = "seated"
		g["order"] = ""
		g["next_at"] = now + Kin.randi_range(st, "inn|next|" + key, int(br[0]), int(br[1]))
		return
	_leave(sim, bld, g, "done", false)


## Satisfaction 0-1 of a served round: how little it waited, the quality, the ambience, the minstrel, and the nobles'
## dislike of a room full of soldiers.
static func satisfaction(sim: Sim, bld: String, g: Dictionary, wait_share: float = -1.0) -> float:
	var cfg: Dictionary = rules(sim).get("satisfaction", {})
	var wait := float(g.get("wait", 0))
	var pat := maxf(1.0, float(g.get("patience", 30)))
	var ws := float(cfg.get("wait_share", 0.6)) if wait_share < 0.0 else wait_share  # the fame's own weight
	var s := ws * clampf(1.0 - wait / pat, 0.0, 1.0)
	s += float(cfg.get("quality_share", 0.25)) * float(g.get("quality", 0)) / 2.0
	s += float(cfg.get("ambience_share", 0.15)) * float(ambience(sim, bld)) / 5.0
	var night: Dictionary = state_of(sim, bld).get("night", {})
	if bool(night.get("minstrel", false)):
		s += float(cfg.get("minstrel_bonus", 0.1))
	var def: Dictionary = sim.catalog.inn.get("clientele", {}).get("groups", {}).get(str(g.get("group", "")), {})
	if def.has("dislikes_soldiers"):
		var n := 0
		for o: Dictionary in guests(sim, bld):
			if str(o.get("group", "")) == "soldiers":
				n += 1
		if n > int(def["dislikes_soldiers"]):
			s -= 0.2
	return clampf(s, 0.0, 1.0)


## Who runs after a dine-and-dash: an employee with role tables on shift, else anyone serving ("" if nobody).
static func _chaser(sim: Sim, bld: String) -> String:
	var best := ""
	for s: Dictionary in servers_of(sim, bld):
		if str(s["role"]) == "tables":
			return str(s["chr"])
		if best == "":
			best = str(s["chr"])
	if best == "":
		var occ := str(sim.state.buildings[bld].get("zones", {}).get("bar", {}).get("occupant", ""))
		if occ != "" and str(sim.state.characters.get(occ, {}).get("location", "")) == bld:
			best = occ
	return best


## The guest goes; a complaint counts against the fame (reasons: full, slow, sold_out, not_on_menu, no_bed).
static func _leave(sim: Sim, bld: String, g: Dictionary, reason: String, complaint: bool) -> void:
	g["state"] = "gone"
	g["left"] = reason
	var night: Dictionary = state_of(sim, bld)["night"]
	if complaint:
		var c: Dictionary = night["stats"]["complaints"]
		c[reason] = int(c.get(reason, 0)) + 1
		var bg: Dictionary = night["stats"]["by_group"].get(str(g["group"]), {})
		if not bg.is_empty():
			bg["left"] = int(bg.get("left", 0)) + 1
	sim.events.append({"type": "inn_guest_left", "building": bld, "guest": str(g["id"]), "group": str(g["group"]),
		"reason": reason})
	if bool(g.get("neighbour", false)):
		_neighbour_out(sim, bld, g, reason)


## Vida hook (04g §4.6.5.7, the neighbours' layer; Agenda._go): townsperson `chr`, whose agenda chose the tavern and
## has reached its meeting point at the door of an open Taberna-Posada, comes in as a guest with its name (leaves the
## map while inside). True if it came in (the agenda waits for it: hosted).
static func neighbour_in(sim: Sim, chr: String, t: Dictionary) -> bool:
	if t.has("inn"):
		return true
	var st := sim.state
	var now := int(st.clock["minute"])
	if now < int(t.get("inn_after", -1)) or t.has("inn_tried"):
		return false  # one try per outing, and a while after coming out (it chats at the door, vida's corrillo)
	t["inn_tried"] = true
	var at := Life.tile_of(st, chr)
	var ids: Array = st.buildings.keys()
	ids.sort()
	for bld: String in ids:
		if not is_inn(sim, bld) or not is_open(sim, bld) or str(st.buildings[bld].get("owner", "")) == "":
			continue
		var door: Array = st.buildings[bld].get("door", [])
		if door.size() != 2 or Life.dist(at, door) > 4 or Staff.works_at(st, chr, bld):
			continue
		if guests(sim, bld).size() >= seats(sim, bld):
			return false  # full: it stays at the door with the others (vida's corrillo)
		var cheapest := -1
		for d: Variant in state_of(sim, bld).get("menu", []):
			var pr := dish_price(sim, bld, str(d), 0)
			if cheapest < 0 or pr < cheapest:
				cheapest = pr
		if cheapest < 0 or Households.spendable(sim, str(st.characters[chr].get("family", ""))) < cheapest:
			return false  # no money for anything on the menu (Equilibrio 15: over tomorrow's food): chats at the door
		var gid := arrive(sim, bld, "neighbours", chr)
		if gid == "":
			return false
		guest(sim, bld, gid)["neighbour"] = true
		t["inn"] = "%s|%s" % [bld, gid]
		Life.take_off(sim, chr)
		return true
	return false


## Minutes a neighbour does not come back in after leaving (it has had its night out).
const NEIGHBOUR_REST: int = 120


## Whether townsperson `chr` is inside a Taberna-Posada as a guest now (its agenda waits).
static func hosting(st: WorldState, chr: String) -> bool:
	var t: Variant = st.characters.get(chr, {}).get("town")
	return t is Dictionary and (t as Dictionary).has("inn")


## A neighbour leaves: back on the map at the door; the tavern is done for its agenda (its raises applied).
static func _neighbour_out(sim: Sim, bld: String, g: Dictionary, reason: String) -> void:
	var chr := str(g.get("chr", ""))
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty():
		return
	Life.put_on(sim, chr, (sim.state.buildings[bld].get("door", [0, 0]) as Array).duplicate())
	var t: Variant = ch.get("town")
	if t is Dictionary:
		(t as Dictionary).erase("inn")
		(t as Dictionary)["inn_after"] = int(sim.state.clock["minute"]) + NEIGHBOUR_REST
		if reason in ["done", "closing"]:
			Agenda.raise(sim, t, Agenda.acts(sim).get("tavern", {}).get("raises", {}), int(sim.state.clock["minute"]))
			sim.events.append({"type": "activity_done", "character": chr, "activity": "tavern"})
		Agenda._clear(t)


## A bed for the guest (the good room for whom asks for it, if built): paid at once; no bed = complaint no_bed.
static func _take_bed(sim: Sim, bld: String, inn: Dictionary, g: Dictionary, wants_good: bool) -> void:
	var beds: Array = inn["beds"]
	var good_room := Upgrades.flag(sim, bld, "inn_good_room")
	var idx := -1
	if wants_good and good_room and str(beds[0].get("state", "")) == "made":
		idx = 0
	else:
		for i: int in beds.size():
			if str(beds[i].get("state", "")) == "made" and not (good_room and i == 0 and not wants_good):
				idx = i
				break
		if idx < 0 and good_room and str(beds[0].get("state", "")) == "made":
			idx = 0
	var night: Dictionary = inn["night"]
	if idx < 0:
		var c: Dictionary = night["stats"]["complaints"]
		c["no_bed"] = int(c.get("no_bed", 0)) + 1
		sim.events.append({"type": "inn_no_bed", "building": bld, "guest": str(g["id"])})
		return
	var good := good_room and idx == 0
	var price := bed_price(sim, bld, good)
	beds[idx] = {"state": "occupied", "guest": str(g["id"]), "group": str(g["group"]), "until": -1, "by": ""}
	g["bed"] = idx
	Money.change(sim, str(sim.state.buildings[bld].get("owner", "")), price, Money.SERVICES, "inn_bed", bld)
	night["stats"]["beds"] = int(night["stats"]["beds"]) + 1
	night["stats"]["beds_income"] = int(night["stats"]["beds_income"]) + price
	sim.events.append({"type": "inn_bed_taken", "building": bld, "guest": str(g["id"]), "bed": idx, "price": price})


## A fight (4.27.4): the porter stops it; without one, furniture breaks (ambience −1 tomorrow), one or two leave
## without paying, the pilgrims stay away for a while and the fame drops.
static func _fight(sim: Sim, bld: String, inn: Dictionary, now: int) -> void:
	var here := guests(sim, bld)
	if here.size() < 2:
		return
	var night: Dictionary = inn["night"]
	var stats: Dictionary = night["stats"]
	var cfg: Dictionary = rules(sim).get("incidents", {}).get("fight", {})
	var day := int(night["day"])
	if Upgrades.flag(sim, bld, "inn_porter") and bool(cfg.get("porter_stops", true)):
		stats["fight_stopped"] = int(stats["fight_stopped"]) + 1
		_incident(sim, bld, "fight_stopped", {})
		return
	stats["fights"] = int(stats["fights"]) + 1
	inn["broken_until"] = day + int(rules(sim).get("ambience", {}).get("broken_days", 1))
	inn["pilgrims_scared_until"] = day + int(rules(sim).get("incidents", {}).get("pilgrims_after_fight_days", 2))
	var span: Array = cfg.get("leave_unpaid", [1, 2])
	var n := Kin.randi_range(sim.state, "inn|fightn|%s|%d" % [bld, day], int(span[0]), int(span[1]))
	for g: Dictionary in here:
		if n <= 0:
			break
		if str(g.get("state", "")) in ["waiting", "eating"]:
			_leave(sim, bld, g, "fight", false)
			n -= 1
	_incident(sim, bld, "fight", {})


## A visitor proposes a game (4.27.4): a stranger of games.offer (InnGames.make_offer) waits at the table until the turn
## closes; the owner's family may play it (InnOfferCard, the Mesa tab: the games' screen). The gamblers' own games
## among themselves are the house's cut of their bills (_pay).
static func _game_offer(sim: Sim, bld: String, inn: Dictionary) -> void:
	if not licensed(sim, bld) or not Upgrades.flag(sim, bld, "inn_gaming_table"):
		return
	var offer := InnGames.make_offer(sim, bld, inn)
	_incident(sim, bld, "game_offer", {"preset": str(offer["preset"]), "game": str(offer["game"])})
	sim.events.append({"type": "inn_game_offer", "building": bld, "day": int(inn["night"]["day"]),
		"family": str(sim.state.buildings[bld].get("owner", "")), "preset": str(offer["preset"]),
		"game": str(offer["game"]), "stake": int(offer["stake"])})


static func _incident(sim: Sim, bld: String, kind: String, data: Dictionary) -> void:
	var night: Dictionary = state_of(sim, bld)["night"]
	var e := {"kind": kind, "minute": int(sim.state.clock["minute"])}
	e.merge(data)
	(night["stats"]["incidents"] as Array).append(e)
	sim.events.append({"type": "inn_incident", "building": bld, "kind": kind})
	if OS.is_debug_build():
		print("[Inn] %s suceso %s %s" % [bld, kind, data])


## Closes the turn (02:00): whoever is still inside leaves; the fame moves; the summary card and the history.
static func close_turn(sim: Sim, bld: String) -> void:
	var st := sim.state
	var inn := ensure(sim, bld)
	var night: Dictionary = inn["night"]
	if night.is_empty():
		return
	for g: Dictionary in night["guests"]:
		if str(g.get("state", "")) != "gone":
			_leave(sim, bld, g, "closing", false)
	var stats: Dictionary = night["stats"]
	var fc: Dictionary = rules(sim).get("fame", {})
	var complaints := 0
	var ignored: Array = fc.get("complaints_not_fame", [])
	for k: String in stats["complaints"]:
		if not k in ignored:
			complaints += int(stats["complaints"][k])
	var gain := float(fc.get("per_satisfied", 0.03)) * int(stats.get("fame_satisfied", stats["satisfied"])) \
		+ float(fc.get("per_excellent", 0.02)) * int(stats["excellent"]) \
		+ float(fc.get("per_complaint", -0.04)) * complaints + float(fc.get("per_fight", -0.3)) * int(stats["fights"]) \
		+ float(fc.get("per_dirty_bed", -0.05)) * int(stats["dirty_beds"])
	gain = minf(gain, float(fc.get("max_gain_per_night", 0.4)))
	var before := float(inn.get("fame", 0.0))
	inn["fame"] = snappedf(clampf(before + gain, 0.0, float(fc.get("max", 5.0))), 0.001)
	var rumor := {}
	if _hears_rumor(sim, bld, stats):
		rumor = InnRumors.pick(sim, bld, str(st.families.get(str(st.buildings[bld].get("owner", "")), {}).get("head", "")))
		if not rumor.is_empty():
			var rr := rumor.duplicate()
			rr["day"] = int(night["day"])
			(inn["rumors"] as Array).append(rr)
			while (inn["rumors"] as Array).size() > 10:
				(inn["rumors"] as Array).pop_front()
	var guests_n := 0
	for g: String in stats["by_group"]:
		guests_n += int(stats["by_group"][g]["came"])
	var summary := {"day": int(night["day"]), "by_group": stats["by_group"], "dishes": stats["dishes"],
		"income": int(stats["income"]), "tips": int(stats["tips"]), "beds": int(stats["beds"]),
		"beds_income": int(stats["beds_income"]), "house_cut": int(stats["house_cut"]), "complaints": stats["complaints"],
		"fame_before": snappedf(before, 0.001), "fame_after": float(inn["fame"]), "guests": guests_n,
		"incidents": stats["incidents"], "rumor": rumor, "outlook": night["outlook"], "minstrel": bool(night["minstrel"]),
		"satisfied": int(stats["satisfied"]), "dirty_beds": int(stats["dirty_beds"]),
		"games": stats.get("games", []), "offer": night.get("offer", {})}
	inn["last_turn"] = summary
	var hist: Array = inn["history"]
	hist.append({"day": int(night["day"]), "guests": guests_n, "income": int(stats["income"]) + int(stats["beds_income"])
		+ int(stats["house_cut"]), "tips": int(stats["tips"]), "fame": float(inn["fame"]), "beds": int(stats["beds"])})
	while hist.size() > int(rules(sim).get("history_keep", 16)):
		hist.pop_front()
	inn["night"] = {}
	sim.events.append({"type": "inn_turn_closed", "building": bld, "day": int(summary["day"]), "guests": guests_n,
		"income": int(summary["income"]), "tips": int(summary["tips"]), "family": str(st.buildings[bld].get("owner", ""))})
	if OS.is_debug_build():
		print("[Inn] %s cierra el turno del día %d: %d clientes, %d de oro + %d de propinas, camas %d, quejas %s, fama %.2f -> %.2f" % [
			bld, int(summary["day"]), guests_n, int(summary["income"]), int(summary["tips"]), int(summary["beds"]),
			stats["complaints"], before, float(inn["fame"])])


## A loyal barkeeper (loyalty ≥ min_loyalty) or a family member who served enough tonight hears a useful rumour.
static func _hears_rumor(sim: Sim, bld: String, stats: Dictionary) -> bool:
	var cfg: Dictionary = rules(sim).get("incidents", {}).get("rumor", {})
	if int(stats.get("served_by_kin", 0)) >= int(cfg.get("min_served_by_kin", 4)):
		return true
	for e: String in Staff.employees_of(sim.state, bld):
		var job: Dictionary = sim.state.characters[e]["job"]
		if str(job.get("role", "")) == "bar" and int(job.get("loyalty", 0)) >= int(cfg.get("min_loyalty", 60)):
			return true
	return false


## Dawn: the guests in the rooms leave (occupied -> dirty) and the cooked food spoils without a cold pantry.
static func _dawn(sim: Sim, bld: String, inn: Dictionary) -> void:
	for b: Dictionary in inn["beds"]:
		if str(b.get("state", "")) == "occupied":
			b["state"] = "dirty"
			b["guest"] = ""
	_wake_lodgers(sim, bld)
	if Upgrades.flag(sim, bld, "inn_cold_pantry"):
		return
	var inv: Dictionary = sim.state.buildings[bld]["inventory"]
	var share := float(rules(sim).get("spoil_share", 0.25))
	for d: String in dishes(sim):
		if not bool(dish(sim, d).get("spoils", false)):
			continue
		var item := str(dish(sim, d).get("item", d))
		for q: int in Inventory.QUALITIES:
			var n := Inventory.count(inv, item, q)
			var lost := int(floor(float(n) * share))
			if lost > 0:
				Inventory.remove(inv, item, q, lost)
				sim.events.append({"type": "inn_spoiled", "building": bld, "item": item, "quality": q, "qty": lost})


## The rooms: a bed being made is done at its minute (if who makes it is still inside); a room maid (role rooms,
## active, on shift, inside) starts the next dirty bed.
static func _rooms(sim: Sim, bld: String, inn: Dictionary, now: int) -> void:
	var beds: Array = inn["beds"]
	for i: int in beds.size():
		var b: Dictionary = beds[i]
		if str(b.get("state", "")) != "making":
			continue
		if str(sim.state.characters.get(str(b.get("by", "")), {}).get("location", "")) != bld:
			b["state"] = "dirty"
			b["by"] = ""
			continue
		if now >= int(b.get("until", 0)):
			b["state"] = "made"
			b["by"] = ""
			sim.events.append({"type": "inn_bed_made", "building": bld, "bed": i})
	for e: String in Staff.employees_of(sim.state, bld):
		var ch: Dictionary = sim.state.characters[e]
		if str(ch["job"].get("role", "")) != "rooms" or not Staff.is_active(sim, e) or str(ch.get("location", "")) != bld \
				or not InnStaff.in_shift(sim, e, bld):
			continue
		var busy := false
		for b: Dictionary in beds:
			if str(b.get("state", "")) == "making" and str(b.get("by", "")) == e:
				busy = true
		if busy:
			continue
		for i: int in beds.size():
			if str(beds[i].get("state", "")) == "dirty":
				_start_bed(sim, bld, inn, i, e, InnStaff.pace(sim, e))
				break


static func _start_bed(sim: Sim, bld: String, inn: Dictionary, i: int, by: String, pace: float) -> void:
	var mins := maxi(1, roundi(float(rules(sim).get("make_bed_minutes", 20)) / maxf(pace, 0.25)))
	inn["beds"][i] = {"state": "making", "guest": "", "until": int(sim.state.clock["minute"]) + mins, "by": by}
	sim.events.append({"type": "inn_bed_making", "building": bld, "bed": i, "by": by})


## Vida (Life.points): whether a «tavern» meeting point of the map stands at the site of a Taberna-Posada that nobody
## owns (for sale, or not in this game: a scenario from before has no such building): then the townsfolk do not gather
## there (an empty house), and the life of a game where nobody bought it is the one of vida. A point at no tavern_inn
## site is left alone.
static func closed_for_sale(sim: Sim, point: Dictionary) -> bool:
	var slots: Array = point.get("slots", [])
	if slots.is_empty():
		return false
	var at: Array = slots[0]
	var near := func(door: Array) -> bool:
		return door.size() == 2 and absi(int(door[0]) - int(at[0])) + absi(int(door[1]) - int(at[1])) <= 3
	var site_door: Array = []
	var sites: Dictionary = Life.map(sim).get("buildings", {})
	for k: Variant in sites:
		var m: Dictionary = sites[k]
		if str(m.get("type", "")) == TYPE and near.call(m.get("door", [])):
			site_door = m["door"]
	if site_door.is_empty():
		return false  # a tavern point that is not at a Taberna-Posada's site
	for b: Variant in sim.state.buildings.values():
		var bd: Dictionary = b
		if str(bd.get("type", "")) == TYPE and near.call(bd.get("door", [])) and str(bd.get("owner", "")) != "":
			return false
	return true  # for sale, or not in this game (a scenario from before)


# --- Lodgers: the visitors of vida that sleep here ------------------------------------------------------------------

## Vida hook (docs/contratos/vida.md «Posada»; Visitors._step_one at dusk): `v`, a visitor about to leave town, stays
## to sleep in an owned Taberna-Posada if its kind belongs to a group of the clientele that asks for a bed (bed, keyed
## roll «inn|lodge|v|day»), the group may come (InnClientele: fame, bed price...) and there is a made bed. Then it walks
## to the door (lodger_step) instead of to its gate. True if it stays.
static func lodge(sim: Sim, v: String) -> bool:
	var st := sim.state
	var vis: Variant = st.characters.get(v, {}).get("visitor")
	if not vis is Dictionary:
		return false
	var g := InnClientele.group_of_visitor(sim, str((vis as Dictionary).get("kind", "")))
	if g == "":
		return false
	var def: Dictionary = sim.catalog.inn.get("clientele", {}).get("groups", {}).get(g, {})
	var day := Clock.day(int(st.clock["minute"]))
	if Kin.roll(st, "inn|lodge|%s|%d" % [v, day]) >= float(def.get("bed", 0.0)):
		return false
	var ids: Array = st.buildings.keys()
	ids.sort()
	for bld: String in ids:
		if not is_inn(sim, bld) or str(st.buildings[bld].get("owner", "")) == "" or beds_free(sim, bld) <= 0:
			continue
		if not InnClientele._missing(sim, bld, def).is_empty():
			continue
		vis["lodging"] = bld
		vis["lodging_group"] = g
		var t: Variant = st.characters[v].get("town")
		if t is Dictionary:
			for k: String in ["spot", "slot", "activity"]:
				(t as Dictionary).erase(k)
		sim.events.append({"type": "inn_lodger_coming", "building": bld, "visitor": v, "group": g})
		if OS.is_debug_build():
			print("[Inn] el forastero %s (%s) se queda a dormir en %s" % [v, g, bld])
		return true
	return false


## A lodger on its way: walks to the door; there, once the turn is open, it comes in as a guest with its bed (paid on
## arrival) and leaves the map until dawn. No bed by then (taken meanwhile): it goes after all. True while it is the
## inn's (Visitors leaves it alone).
static func lodger_step(sim: Sim, v: String, now: int) -> bool:
	var st := sim.state
	var ch: Dictionary = st.characters[v]
	var vis: Dictionary = ch["visitor"]
	var bld := str(vis.get("lodging", ""))
	if bld == "" or not st.buildings.has(bld):
		return false
	if bool(vis.get("lodged", false)):
		return true  # asleep (offstage) until dawn
	if not ch.get("town") is Dictionary:
		ch["town"] = {}
	var door: Array = st.buildings[bld].get("door", [])
	if not TownLife._go_tile(sim, v, ch["town"], door, now):
		TownLife._set_state(sim, v, ch["town"], "walking", "")
		return true
	if not is_open(sim, bld):
		return true  # waits at the door for the opening
	if beds_free(sim, bld) <= 0:
		vis["lodging"] = ""
		return false
	var gid := arrive(sim, bld, str(vis.get("lodging_group", "merchants")), v, true)
	if gid == "":
		vis["lodging"] = ""
		return false
	vis["lodged"] = true
	vis["guest"] = gid
	Life.take_off(sim, v)
	sim.events.append({"type": "inn_lodger_in", "building": bld, "visitor": v, "guest": gid})
	return true


## Dawn: the lodgers of `bld` come out of its door and take the road to their gate (Visitors walks them out).
static func _wake_lodgers(sim: Sim, bld: String) -> void:
	var st := sim.state
	for v: String in Visitors.alive(st):
		var vis: Variant = st.characters[v].get("visitor")
		if not vis is Dictionary or str((vis as Dictionary).get("lodging", "")) != bld:
			continue
		if bool((vis as Dictionary).get("lodged", false)):
			Life.put_on(sim, v, (st.buildings[bld].get("door", [0, 0]) as Array).duplicate())
		vis["lodging"] = ""
		vis["lodged"] = false
		vis["leaving"] = true
		sim.events.append({"type": "inn_lodger_out", "building": bld, "visitor": v})


# --- Orders --------------------------------------------------------------------------------------------------------

## Management orders of the inn (Orders.MANAGEMENT): they act at once from the panel.
const MANAGEMENT: Array[String] = ["buy_building", "inn_set_menu", "inn_set_price", "inn_set_special", "inn_buy_license"]


static func _manager_reason(sim: Sim, actor: String, bld: String) -> String:
	if not sim.state.characters.has(actor):
		return "unknown_actor"
	if not sim.state.buildings.has(bld) or not is_inn(sim, bld):
		return "not_an_inn"
	if not Buildings.owns(sim.state, actor, bld):
		return "not_your_building"
	return ""


## {"type": "buy_building", "actor", "building"}: a building for sale (for_sale, no owner) becomes the actor's
## family's for the sale_price of its type (ledger property). Reasons: not_for_sale, not_enough_gold, too_young.
static func order_buy_building(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var b: Dictionary = st.buildings.get(bld, {})
	if b.is_empty() or not bool(b.get("for_sale", false)) or str(b.get("owner", "")) != "":
		return Orders.fail("not_for_sale")
	var fam := str(st.characters[actor].get("family", ""))
	if fam == "" or not st.families.has(fam):
		return Orders.fail("no_family")
	if not Kin.is_adult(sim, actor):
		return Orders.fail("too_young")
	var price := sale_price(sim, bld)
	if not Money.can_pay(st, fam, price):
		return Orders.fail("not_enough_gold")
	Money.change(sim, fam, -price, Money.PROPERTY, "buy_building", bld, actor)
	b["owner"] = fam
	b.erase("for_sale")
	if is_inn(sim, bld):
		ensure(sim, bld)
	Chronicle.add(st, "building_bought", {"family": fam, "building": bld, "type": str(b.get("type", "")), "price": price})
	sim.events.append({"type": "building_bought", "building": bld, "family": fam, "actor": actor, "price": price})
	if OS.is_debug_build():
		print("[Inn] %s compra %s (%s) por %d" % [fam, bld, b.get("type", ""), price])
	return Orders.ok()


static func sale_price(sim: Sim, bld: String) -> int:
	var def: Dictionary = sim.catalog.buildings().get(str(sim.state.buildings.get(bld, {}).get("type", "")), {})
	return int(def.get("sale_price", def.get("build_cost", 0)))


## {"type": "inn_set_menu", "actor", "building", "dishes": [dish]}: known dishes, no repeats, at most menu_slots.
static func order_set_menu(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var why := _manager_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	var list: Variant = o.get("dishes", [])
	if not list is Array:
		return Orders.fail("bad_menu")
	var out: Array = []
	for d: Variant in list:
		if dish(sim, str(d)).is_empty() or str(d) in out:
			return Orders.fail("bad_menu")
		out.append(str(d))
	if out.size() > menu_slots(sim, bld):
		return Orders.fail("menu_full")
	var inn := ensure(sim, bld)
	inn["menu"] = out
	if not str(inn.get("special", "")) in out:
		inn["special"] = ""
	sim.events.append({"type": "inn_menu_changed", "building": bld, "menu": out.duplicate()})
	return Orders.ok()


## {"type": "inn_set_price", "actor", "building", "dish", "mult"}: dish = a dish id or "bed"; mult in price_range.
static func order_set_price(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var why := _manager_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	var d := str(o.get("dish", ""))
	var m := snappedf(float(o.get("mult", 1.0)), 0.05)
	var rng: Array = sim.catalog.services.get("price_range", [0.5, 2.0])
	if m < float(rng[0]) - 0.001 or m > float(rng[1]) + 0.001:
		return Orders.fail("bad_price")
	var inn := ensure(sim, bld)
	if d == "bed":
		inn["bed_price"] = m
	elif dish(sim, d).is_empty():
		return Orders.fail("unknown_dish")
	else:
		inn["prices"][d] = m
	sim.events.append({"type": "inn_price_changed", "building": bld, "dish": d, "mult": m})
	return Orders.ok()


## {"type": "inn_set_special", "actor", "building", "dish"}: the special of the house (a dish of the menu, or "").
static func order_set_special(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var why := _manager_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	var d := str(o.get("dish", ""))
	var inn := ensure(sim, bld)
	if d != "" and not d in (inn["menu"] as Array):
		return Orders.fail("not_on_menu")
	inn["special"] = d
	return Orders.ok()


## {"type": "inn_buy_license", "actor", "building"}: the gaming licence of the council (license.cost, license.days).
static func order_buy_license(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var why := _manager_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	if licensed(sim, bld):
		return Orders.fail("already_licensed")
	var lc: Dictionary = rules(sim).get("license", {})
	var fam := str(sim.state.buildings[bld].get("owner", ""))
	if not Money.can_pay(sim.state, fam, int(lc.get("cost", 60))):
		return Orders.fail("not_enough_gold")
	Money.change(sim, fam, -int(lc.get("cost", 60)), Money.TAXES, "inn_license", bld, actor)
	var inn := ensure(sim, bld)
	inn["license_until"] = Clock.day(int(sim.state.clock["minute"])) + int(lc.get("days", 8)) - 1
	sim.events.append({"type": "inn_license_bought", "building": bld, "until": int(inn["license_until"])})
	return Orders.ok()


## {"type": "inn_serve", "actor", "building", "guest"}: serving by hand (4.27.4): the actor is inside, of the owner's
## family, and the guest waits. Reasons: not_inside, not_your_building, not_waiting, sold_out, busy (served just now).
static func order_serve(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	if not st.buildings.has(bld) or not is_inn(sim, bld):
		return Orders.fail("not_an_inn")
	if str(st.characters[actor].get("location", "")) != bld:
		return Orders.fail("not_inside")
	if not Buildings.owns(st, actor, bld) and not Staff.works_at(st, actor, bld):
		return Orders.fail("not_your_building")
	var g := guest(sim, bld, str(o.get("guest", "")))
	if g.is_empty() or str(g.get("state", "")) != "waiting":
		return Orders.fail("not_waiting")
	var night: Dictionary = state_of(sim, bld)["night"]
	var now := int(st.clock["minute"])
	if int(night["servers"].get(actor, -1)) > now:
		return Orders.fail("busy")
	if stock(sim, bld, str(g["order"])) <= 0:
		return Orders.fail("sold_out")
	serve(sim, bld, str(g["id"]), actor)
	night["servers"][actor] = now + int(rules(sim).get("staff", {}).get("hand_serve_minutes", 2))
	return Orders.ok()


## {"type": "inn_make_bed", "actor", "building", "bed"}: the actor (inside, of the family or an employee) makes a dirty
## bed (make_bed_minutes). Reasons: not_inside, not_dirty, busy.
static func order_make_bed(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	if not st.buildings.has(bld) or not is_inn(sim, bld):
		return Orders.fail("not_an_inn")
	if str(st.characters[actor].get("location", "")) != bld:
		return Orders.fail("not_inside")
	if not Buildings.owns(st, actor, bld) and not Staff.works_at(st, actor, bld):
		return Orders.fail("not_your_building")
	var inn := ensure(sim, bld)
	var i := int(o.get("bed", -1))
	if i < 0 or i >= (inn["beds"] as Array).size() or str(inn["beds"][i].get("state", "")) != "dirty":
		return Orders.fail("not_dirty")
	for b: Dictionary in inn["beds"]:
		if str(b.get("state", "")) == "making" and str(b.get("by", "")) == actor:
			return Orders.fail("busy")
	_start_bed(sim, bld, inn, i, actor, 1.0)
	return Orders.ok()
