class_name Households
extends RefCounted
## The purse of the townsfolk's houses (Equilibrio 15, docs/decisiones.json; 04f 4.24.1, 04g §4.6.5.7) and the meals of
## the people the agenda does not feed (Vida: the employees and the children). Figures: data/town.json "households"
## [balance]. Only with the living town on (Life.on).
##
## - **Jornal.** At the start of dusk, every adult townsperson with a trade of the map (occupation) and no job with a
##   family earns its day's wage into its house's purse (the family gold of the household): wages[occupation kind]
##   (the workplace's kind), else wages.default. Money from outside (P4, 4.19): category wages, ref "jornal".
##   The employees of a family already bring their wage home (Staff).
## - **Food.** At dawn every household pays its food: food.adult per adult and food.child per child of its townsfolk.
##   What it can pay is its fed share (0-1) for the day; the money leaves the economy (bread and pot bought outside).
## - **Meals of the employees and the children** (the agenda feeds the other adults: their night at home and «Comer en
##   casa»). At dawn they get the night at home (needs.night of data/life/life.json: rest, and the hunger × the fed
##   share); at meal_hour, the midday meal (meal.hunger × the fed share): the employee in its break at work, the child
##   at home.
## - **The tavern is a whim.** A neighbour only spends there what is left over the next dawn's food (spendable).
## State: families[hh].household {fed_day, fed, wage_day} (read with defaults: no save version).


static func _cfg(sim: Sim) -> Dictionary:
	return sim.catalog.town.get("households", {})


static func on(sim: Sim) -> bool:
	return Life.on(sim) and not _cfg(sim).is_empty() and bool(_cfg(sim).get("enabled", true))


static func _mem(st: WorldState, fam: String) -> Dictionary:
	var f: Dictionary = st.families[fam]
	if not f.get("household") is Dictionary:
		f["household"] = {"fed_day": -1, "fed": 1.0, "wage_day": -1}
	return f["household"]


## Once per minute, after TownLife and Life (the townsfolk's day has started).
static func step(sim: Sim) -> void:
	if not on(sim):
		return
	var st := sim.state
	var now := int(st.clock["minute"])
	var phase := ""
	var dawn := false
	for e: Dictionary in sim.events:
		match str(e["type"]):
			"phase_changed":
				phase = str(e.get("phase", e.get("to", "")))
			"day_started":
				pass
	dawn = Ledger.is_dawn(sim)
	var meal := Clock.minute_of_day(now) == int(_cfg(sim).get("meal_hour", 13)) * 60
	if not dawn and not meal and phase != "dusk":
		return
	var homes := _households(sim)
	var fams: Array = homes.keys()
	fams.sort()
	for hh: String in fams:
		if dawn:
			_food(sim, hh, homes[hh], now)
		if phase == "dusk":
			_wages(sim, hh, homes[hh], now)
		if meal:
			_midday(sim, hh, homes[hh], now)


## {household family: [its living townsfolk]} (the people in the town's houses).
static func _households(sim: Sim) -> Dictionary:
	var st := sim.state
	var out := {}
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		if not TownLife.is_townsperson(st, id) or Region.is_away(st, id):
			continue
		var fam := str(st.characters[id].get("family", ""))
		if not out.has(fam):
			out[fam] = []
		(out[fam] as Array).append(id)
	return out


static func _is_child(sim: Sim, chr: String) -> bool:
	return not TownLife.is_adult(sim.state, sim.catalog, chr)


## What the household's food costs a day.
static func food_cost(sim: Sim, members: Array) -> int:
	var f: Dictionary = _cfg(sim).get("food", {})
	var c := 0
	for m: Variant in members:
		c += int(f.get("child", 1)) if _is_child(sim, str(m)) else int(f.get("adult", 2))
	return c


static func _food(sim: Sim, hh: String, members: Array, now: int) -> void:
	var st := sim.state
	var mem := _mem(st, hh)
	var today := Clock.day(now)
	if int(mem.get("fed_day", -1)) == today:
		return
	var cost := food_cost(sim, members)
	var pay := mini(cost, maxi(0, Money.gold(st, hh)))
	if pay > 0:
		Money.change(sim, hh, -pay, Money.PURCHASES, "food")
	var fed := 1.0 if cost <= 0 else float(pay) / float(cost)
	mem["fed_day"] = today
	mem["fed"] = snappedf(fed, 0.01)
	var night: Dictionary = (Agenda.ncfg(sim).get("night", {}) as Dictionary).duplicate()
	night["hunger"] = roundi(float(night.get("hunger", 450)) * fed)
	for m: Variant in members:
		var c := str(m)
		if not _fed_here(sim, c):
			continue  # the other adults: the agenda's night at home
		var t := _town(st, c)
		Agenda.at_least(sim, t, night, now)
	if OS.is_debug_build():
		print("[Households] %s paga la comida: %d de %d (comen %.0f %%, bolsa=%d)" % [hh, pay, cost, fed * 100.0,
			Money.gold(st, hh)])


static func _wages(sim: Sim, hh: String, members: Array, now: int) -> void:
	var st := sim.state
	var mem := _mem(st, hh)
	var today := Clock.day(now)
	if int(mem.get("wage_day", -1)) == today:
		return
	mem["wage_day"] = today
	var w: Dictionary = _cfg(sim).get("wages", {})
	var total := 0
	for m: Variant in members:
		var c := str(m)
		var ch: Dictionary = st.characters[c]
		if ch.get("job") is Dictionary or _is_child(sim, c) or str(ch.get("occupation", "")) == "":
			continue
		var kind := str(TownLife.workplace(st, sim.catalog, str(ch["occupation"])).get("kind", ""))
		total += int(w.get(kind, w.get("default", 6)))
	if total <= 0:
		return
	Money.change(sim, hh, total, Money.WAGES, "jornal")
	sim.events.append({"type": "household_wage", "family": hh, "amount": total})
	if OS.is_debug_build():
		print("[Households] %s cobra el jornal: +%d (bolsa=%d)" % [hh, total, Money.gold(st, hh)])


static func _midday(sim: Sim, hh: String, members: Array, now: int) -> void:
	var st := sim.state
	var fed := float(_mem(st, hh).get("fed", 1.0))
	var raise := {"hunger": roundi(float(_cfg(sim).get("meal", {}).get("hunger", 45)) * fed)}
	for m: Variant in members:
		var c := str(m)
		if _fed_here(sim, c):
			Agenda.raise(sim, _town(st, c), raise, now)


## Whether this module feeds `chr` (an employee of a family, or a child); the agenda feeds the other adults.
static func _fed_here(sim: Sim, chr: String) -> bool:
	return sim.state.characters[chr].get("job") is Dictionary or _is_child(sim, chr)


static func _town(st: WorldState, chr: String) -> Dictionary:
	var ch: Dictionary = st.characters[chr]
	if not ch.get("town") is Dictionary:
		ch["town"] = {}
	return ch["town"]


## What household `fam` may spend on a whim now (the tavern): its purse less tomorrow's food (all of it without the
## figures or the living town).
static func spendable(sim: Sim, fam: String) -> int:
	var gold := Money.gold(sim.state, fam)
	if not on(sim):
		return gold
	var members: Array = _households(sim).get(fam, [])
	return maxi(0, gold - food_cost(sim, members) * int(_cfg(sim).get("reserve_days", 1)))
