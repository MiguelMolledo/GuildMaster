class_name Festivals
extends RefCounted
## 4.25 · the festival calendar (docs/gdd/04f_vida_y_fiestas.md). Data: data/festivals.json (the eight fixed feasts of
## the year and the variable ones, their sim effects and their view), data/contracts/festivals.json (the festival and
## wedding contracts, FestivalContracts) and data/world/region.json patron_feast / fair (the feasts of the other
## cities, which are a pure function of the calendar: no state).
##
## State (v18): state.festivals = {active: [inst], upcoming: [inst], history: [inst] (the last ones), cooldowns: {def:
## day of its last start}, offers: {fam: {couple, until}} (a wedding the player may celebrate), planned_day: the last
## day planned}. An instance: {id, def, day, start, end, announce, announced, cause, by, hosts: [fam], couple: [chr],
## patron, sponsors: {fam: [part]}, organized: {part: chr}, stalls: [{stall, group}], done: [spectacle hour keys],
## contracts: [ctr ids]}. Minutes are absolute; `day` is the day the feast belongs to (its hours count from its 00:00).
##
## The flow: every day (its first step) the feasts announced that day are planned: the fixed ones of tomorrow, a keyed
## roll over the variable ones (one at most, its own stream «fst|var|<day>», so no other roll moves) and the
## pilgrimage on the abbey's feast. At `announce` the town crier (event festival_eve, a notice, the card) and its
## contracts go up; at `start` it begins (festival_started, its start effects); its spectacles at their hour
## (festival_spectacle, for the games of 4.26); at `end` it is over (festival_ended, its end effects, the chronicle).
## Weddings (H8 «wedding», H7 «townsfolk_married») open their feast the next day.
##
## The effects are declarative (data/festivals.json _effects_doc). The ones that exist go through WorldEvents.event_mult
## (demand, price, customers, production; holy_day is production); the new ones live here (tariff, route_bonus, stalls,
## emotion, reputation, aguinaldo); the hooks of the other blocks (service, visitors, routine, need, spectacle,
## incident) are answered by hook_mult / hook_kinds / hook_amount, for the branches that will read them.
## Off (data enabled false, as sim_runner does for every target fixed before the festivals): nothing runs, nothing is
## written, every multiplier is 1.

const SIM_EFFECTS: Array[String] = ["demand", "price", "customers", "production", "holy_day", "tariff", "route_bonus",
	"stalls", "emotion", "reputation", "aguinaldo"]
const HOOK_EFFECTS: Array[String] = ["service", "visitors", "routine", "need", "spectacle", "incident"]
const GROUP_EFFECTS: Array[String] = ["demand", "price", "production"]
const SIZES: Array[String] = ["big", "small"]
const KINDS: Array[String] = ["fixed", "variable"]
const TRIGGERS: Array[String] = ["rich_wedding", "townsfolk_wedding", "organized", "city_feast"]
const MPD: int = 1440


# --- Data -----------------------------------------------------------------------------------------------------------

static func enabled(sim: Sim) -> bool:
	return bool(sim.catalog.festivals.get("enabled", false))


static func defs(sim: Sim) -> Dictionary:
	return sim.catalog.festivals.get("festivals", {})


static func def_of(sim: Sim, id: String) -> Dictionary:
	return defs(sim).get(id, {})


static func rules(sim: Sim) -> Dictionary:
	return sim.catalog.festivals.get("rules", {})


static func days_per_year(sim: Sim) -> int:
	return maxi(1, Clock.days_per_year(sim.catalog.time))


## The fixed feast of `day` ("" if none).
static func fixed_on(sim: Sim, day: int) -> String:
	var doy := posmod(day, days_per_year(sim))
	for id: String in _sorted_keys(defs(sim)):
		var d: Dictionary = defs(sim)[id]
		if str(d.get("kind", "")) == "fixed" and int(d.get("day_of_year", -1)) == doy:
			return id
	return ""


## The state block, created the first time (only when the festivals are on).
static func ensure(st: WorldState) -> Dictionary:
	if not st.festivals.get("active") is Array:
		st.festivals = new_block()
	return st.festivals


static func new_block() -> Dictionary:
	return {"active": [], "upcoming": [], "history": [], "cooldowns": {}, "offers": {}, "planned_day": -1}


# --- Step -----------------------------------------------------------------------------------------------------------

## Once per minute, after Courtship (it reads this step's weddings) and before the market and the contracts.
static func step(sim: Sim) -> void:
	if not enabled(sim):
		return
	var st := sim.state
	var f := ensure(st)
	var now := int(st.clock["minute"])
	var today := Clock.day(now)
	if int(f.get("planned_day", -1)) < today:
		var first := int(f.get("planned_day", -1)) < 0
		for d: int in range(maxi(int(f.get("planned_day", -1)) + 1, today), today + 1):
			_plan_day(sim, d, first)
			first = false
		f["planned_day"] = today
	for e: Dictionary in sim.events:
		match str(e.get("type", "")):
			"wedding":
				_on_wedding(sim, e)
			"townsfolk_married":
				_on_townsfolk_wedding(sim, e)
			"employee_bonus":
				_on_bonus(sim, e)
	if (f["upcoming"] as Array).is_empty() and (f["active"] as Array).is_empty():
		return
	_tick(sim, now)


static func _tick(sim: Sim, now: int) -> void:
	var f: Dictionary = sim.state.festivals
	var keep: Array = []
	for inst: Dictionary in f["upcoming"]:
		if not bool(inst.get("announced", false)) and now >= int(inst["announce"]):
			_announce(sim, inst)
		if now >= int(inst["start"]):
			_start(sim, inst)
			(f["active"] as Array).append(inst)
		else:
			keep.append(inst)
	f["upcoming"] = keep
	var still: Array = []
	for inst: Dictionary in f["active"]:
		_spectacles(sim, inst, now)
		if now >= int(inst["end"]):
			_end(sim, inst)
		else:
			still.append(inst)
	f["active"] = still
	FestivalContracts.expire(sim, now)


## The feasts announced on `day`: the fixed one of tomorrow (and, the first time, today's if it has not ended), the
## pilgrimage on the abbey's feast, the roll of the variable ones; the eve notices of the other cities' fairs.
static func _plan_day(sim: Sim, day: int, first: bool) -> void:
	if first:
		var today_fixed := fixed_on(sim, day)
		if today_fixed != "":
			_schedule(sim, today_fixed, day, "calendar")
	var fixed := fixed_on(sim, day + 1)
	if fixed != "":
		_schedule(sim, fixed, day + 1, "calendar")
	for id: String in _sorted_keys(defs(sim)):
		var d: Dictionary = defs(sim)[id]
		var trig: Dictionary = d.get("trigger", {})
		if str(trig.get("on", "")) == "city_feast":
			var feast: Dictionary = Region.settlement(sim, str(trig.get("city", ""))).get("patron_feast", {})
			if not feast.is_empty() and posmod(day + int(d.get("notice_days", 1)), days_per_year(sim)) \
					== int(feast.get("day_of_year", -1)):
				_schedule(sim, id, day + int(d.get("notice_days", 1)), "city")
	_roll_variable(sim, day)
	_city_eves(sim, day)
	if OS.is_debug_build():
		print("[Festivals] día %d planificado (fija mañana=%s, en cola=%d, en curso=%d)" % [day, fixed,
			(sim.state.festivals["upcoming"] as Array).size(), (sim.state.festivals["active"] as Array).size()])


## One keyed roll on `day` over the variable feasts with a chance that may start notice_days later: at most one.
static func _roll_variable(sim: Sim, day: int) -> void:
	var st := sim.state
	var options: Array = []
	var total := 0.0
	for id: String in _sorted_keys(defs(sim)):
		var d: Dictionary = defs(sim)[id]
		if str(d.get("kind", "")) != "variable":
			continue
		var trig: Dictionary = d.get("trigger", {})
		var p := float(trig.get("chance", 0.0))
		if p <= 0.0 or str(trig.get("on", "")) != "":
			continue
		var start_day := day + int(d.get("notice_days", 1))
		if start_day < int(trig.get("min_day", 0)) or start_day < int(rules(sim).get("first_day", 1)):
			continue
		if _cooling(sim, id, start_day) or _avoided(sim, d, start_day) or not _event_ok(sim, trig):
			continue
		options.append({"id": id, "p": p, "day": start_day})
		total += p
	if options.is_empty():
		return
	var roll := Kin.roll(st, "fst|var|%d" % day)
	if OS.is_debug_build():
		print("[Festivals] tirada de fiestas variables del día %d: %.3f contra %.3f entre %s" % [day, roll, total,
			options.map(func(o: Dictionary) -> String: return str(o["id"]))])
	for o: Dictionary in options:
		roll -= float(o["p"])
		if roll < 0.0:
			_schedule(sim, str(o["id"]), int(o["day"]), "roll")
			return


static func _cooling(sim: Sim, id: String, start_day: int) -> bool:
	var cd := int(def_of(sim, id).get("trigger", {}).get("cooldown_days", 0))
	var last := int(sim.state.festivals.get("cooldowns", {}).get(id, -100000))
	return start_day - last < cd


## Whether `d` must not fall on `day` (trigger.avoid: a fixed feast of that size, or a fair).
static func _avoided(sim: Sim, d: Dictionary, day: int) -> bool:
	var avoid: Array = d.get("trigger", {}).get("avoid", [])
	var fixed := fixed_on(sim, day)
	if fixed != "":
		var fd := def_of(sim, fixed)
		if str(fd.get("size", "")) in avoid or ("fair" in avoid and bool(fd.get("fair", false))):
			return true
	for inst: Dictionary in _all(sim):
		if int(inst.get("day", -1)) == day and str(def_of(sim, str(inst["def"])).get("kind", "")) == "variable":
			return true
	return false


static func _event_ok(sim: Sim, trig: Dictionary) -> bool:
	for ev: Variant in trig.get("requires_event", []):
		if not WorldEvents.is_active(sim, str(ev)):
			return false
	return true


## Puts feast `id` on `day` (unless it is already there). Returns the instance id ("" if not).
static func _schedule(sim: Sim, id: String, day: int, cause: String, extra: Dictionary = {}) -> String:
	var st := sim.state
	var d := def_of(sim, id)
	if d.is_empty() or day < int(rules(sim).get("first_day", 1)):
		return ""
	for inst: Dictionary in _all(sim):
		if str(inst["def"]) == id and int(inst["day"]) == day:
			return ""
	var start := day * MPD + int(d.get("start_hour", 0)) * 60
	var end := start + maxi(1, int(d.get("hours", 24))) * 60
	var now := int(st.clock["minute"])
	if end <= now:
		return ""
	var eve := (day - int(d.get("notice_days", 1))) * MPD + int(rules(sim).get("eve_hour", 12)) * 60
	var inst := {"id": Ids.next(st, "fst"), "def": id, "day": day, "start": start, "end": end,
		"announce": mini(maxi(eve, now), start), "announced": false, "cause": cause, "by": str(extra.get("by", "")),
		"hosts": extra.get("hosts", []), "couple": extra.get("couple", []), "patron": _is_patron(sim, day),
		"sponsors": {}, "organized": {}, "stalls": [], "done": [], "contracts": []}
	(st.festivals["upcoming"] as Array).append(inst)
	st.festivals["cooldowns"][id] = day
	if OS.is_debug_build():
		print("[Festivals] %s (%s) en el día %d: pregón min %d, de %d a %d (causa=%s, patronal=%s)" % [inst["id"], id,
			day, int(inst["announce"]), start, end, cause, inst["patron"]])
	return str(inst["id"])


## Whether `day` is the home town's patron feast (data/world/region.json, the home settlement's patron_feast).
static func _is_patron(sim: Sim, day: int) -> bool:
	var pf: Dictionary = Region.settlement(sim, Region.home_id(sim)).get("patron_feast", {})
	return not pf.is_empty() and posmod(day, days_per_year(sim)) == int(pf.get("day_of_year", -1))


## The town crier: festival_eve, a notice for the human families, the contracts.
static func _announce(sim: Sim, inst: Dictionary) -> void:
	inst["announced"] = true
	var d := def_of(sim, str(inst["def"]))
	FestivalContracts.post_for(sim, inst)
	sim.events.append({"type": "festival_eve", "id": str(inst["id"]), "def": str(inst["def"]), "day": int(inst["day"]),
		"start": int(inst["start"]), "end": int(inst["end"]), "contracts": (inst["contracts"] as Array).size()})
	var params := {"festival": str(inst["def"]), "when": _when_text(sim, inst), "contracts": (inst["contracts"] as Array).size()}
	for f: String in _humans(sim.state):
		Notices.add(sim, f, Notices.INFO, "notice.festival_eve", params)
	if OS.is_debug_build():
		print("[Festivals] pregón de %s (%s): %d encargos, tamaño %s" % [inst["id"], inst["def"],
			(inst["contracts"] as Array).size(), d.get("size", "")])


static func _start(sim: Sim, inst: Dictionary) -> void:
	if not bool(inst.get("announced", false)):
		_announce(sim, inst)
	var d := def_of(sim, str(inst["def"]))
	for e: Dictionary in d.get("effects", []):
		if str(e.get("kind", "")) == "stalls" and _part_ok(inst, e):
			var groups: Array = e.get("groups", [])
			for i: int in int(e.get("count", 0)):
				(inst["stalls"] as Array).append({"stall": str(e.get("stall", "fair")),
					"group": str(groups[i % groups.size()]) if not groups.is_empty() else ""})
	_apply_at(sim, inst, "start")
	_needs(sim, inst)
	sim.events.append({"type": "festival_started", "id": str(inst["id"]), "def": str(inst["def"]),
		"day": int(inst["day"]), "start": int(inst["start"]), "end": int(inst["end"]), "patron": bool(inst["patron"]),
		"sponsors": (inst["sponsors"] as Dictionary).keys()})
	var params := {"festival": str(inst["def"]), "sponsors": _sponsor_names(sim, inst)}
	var key := "notice.festival_started_sponsored" if not (inst["sponsors"] as Dictionary).is_empty() else "notice.festival_started"
	for f: String in _humans(sim.state):
		Notices.add(sim, f, Notices.INFO, key, params)
	if OS.is_debug_build():
		print("[Festivals] empieza %s (%s) min %d hasta %d (patrocinios=%s, organizado=%s, puestos=%d)" % [inst["id"],
			inst["def"], int(sim.state.clock["minute"]), int(inst["end"]), inst["sponsors"], inst["organized"],
			(inst["stalls"] as Array).size()])


static func _spectacles(sim: Sim, inst: Dictionary, now: int) -> void:
	var d := def_of(sim, str(inst["def"]))
	for e: Dictionary in d.get("effects", []):
		if str(e.get("kind", "")) != "spectacle":
			continue
		var at := int(inst["day"]) * MPD + int(e.get("hour", 0)) * 60
		var key := "%s@%d" % [str(e.get("id", "")), int(e.get("hour", 0))]
		if now >= at and not key in (inst["done"] as Array):
			(inst["done"] as Array).append(key)
			if not _part_ok(inst, e):
				continue
			sim.events.append({"type": "festival_spectacle", "festival": str(inst["id"]), "def": str(inst["def"]),
				"spectacle": str(e.get("id", "")), "at": at})
			FestivalGames.on_spectacle(sim, inst, str(e.get("id", "")))  # juegos (04f §4.26): the competitions are fought
			if Life.on(sim):  # vida (04f 4.24.1): the townsfolk go and watch it in the plaza (activity watch_show)
				Life.add_spectacle(sim, str(e.get("id", "")), Life.plaza(sim), at + int(rules(sim).get("spectacle_minutes",
					120)), str(inst["id"]))
			if OS.is_debug_build():
				print("[Festivals] espectáculo %s de %s a las %d:00" % [e.get("id", ""), inst["id"], int(e.get("hour", 0))])


static func _end(sim: Sim, inst: Dictionary) -> void:
	FestivalGames.on_end(sim, inst)  # juegos: an entry never played is resolved, a bet on what never came given back
	_apply_at(sim, inst, "end")
	var f: Dictionary = sim.state.festivals
	var h: Array = f["history"]
	h.append(inst)
	while h.size() > int(rules(sim).get("history_size", 16)):
		h.pop_front()
	Chronicle.add(sim.state, "festival", {"festival": str(inst["def"]), "day": int(inst["day"]),
		"sponsors": (inst["sponsors"] as Dictionary).keys(), "hosts": inst.get("hosts", [])})
	sim.events.append({"type": "festival_ended", "id": str(inst["id"]), "def": str(inst["def"])})
	for fam: String in _humans(sim.state):
		Notices.add(sim, fam, Notices.INFO, "notice.festival_ended", {"festival": str(inst["def"])})
	if OS.is_debug_build():
		print("[Festivals] acaba %s (%s) min %d" % [inst["id"], inst["def"], int(sim.state.clock["minute"])])


## The effects of `inst` that act once at `at` (start | end): reputation, emotion; and the sponsors' relation at the end.
static func _apply_at(sim: Sim, inst: Dictionary, at: String) -> void:
	var st := sim.state
	var d := def_of(sim, str(inst["def"]))
	for e: Dictionary in d.get("effects", []):
		var k := str(e.get("kind", ""))
		if str(e.get("at", "end" if k == "emotion" else "start")) != at or not _part_ok(inst, e):
			continue
		match k:
			"reputation":
				for fam: String in _who(sim, inst, str(e.get("who", ""))):
					Reputation.change(sim, fam, int(e.get("amount", 0)), "festival_" + str(e.get("why", inst["def"])))
			"emotion":
				var share := float(e.get("share", 0.0))
				for fam: String in _who(sim, inst, str(e.get("toward", "sponsors"))):
					var n := 0
					for c: String in Population.townsfolk(st):
						if Kin.roll(st, "fst|emo|%s|%s|%s" % [inst["id"], fam, c]) < share:
							Emotions.add(sim, c, str(e.get("id", "grateful")), fam)
							n += 1
					if OS.is_debug_build():
						print("[Festivals] %s: %d vecinos %s hacia %s" % [inst["id"], n, e.get("id", ""), fam])
	if at == "end":
		var sp: Dictionary = rules(sim).get("sponsor", {})
		for fam: String in _sorted_keys(inst["sponsors"]):
			var head := Kin.head(st, fam)
			if head == "":
				continue
			for c: String in Population.townsfolk(st):
				if Kin.roll(st, "fst|rel|%s|%s|%s" % [inst["id"], fam, c]) < float(sp.get("relation_share", 0.4)):
					Emotions.change_relation(sim, c, head, int(sp.get("relation", 2)), "festival_sponsor")


## vida (04f 4.24.1): the need effects (the preacher's faith +40) raise the townsfolk's needs when the feast starts.
static func _needs(sim: Sim, inst: Dictionary) -> void:
	if not Life.on(sim):
		return
	var raises := {}
	for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
		if str(e.get("kind", "")) == "need" and _part_ok(inst, e):
			raises[str(e.get("id", ""))] = int(raises.get(str(e.get("id", "")), 0)) + int(e.get("amount", 0))
	if raises.is_empty():
		return
	var now := int(sim.state.clock["minute"])
	var n := 0
	for c: String in Population.townsfolk(sim.state):
		var t: Variant = sim.state.characters[c].get("town")
		if t is Dictionary:
			Agenda.raise(sim, t, raises, now)
			n += 1
	if OS.is_debug_build():
		print("[Festivals] %s: necesidades %s a %d vecinos" % [inst["id"], raises, n])


## The families an effect names: mayor (the mayor's family), sponsors, hosts (the wedding's).
static func _who(sim: Sim, inst: Dictionary, who: String) -> Array:
	match who:
		"mayor":
			for o: String in sim.state.offices:
				if str(sim.catalog.offices().get(o, {}).get("rank", "")) == "mayor":
					var out: Array = []
					for h: String in Offices.holders(sim, o):
						var fam := str(sim.state.characters.get(h, {}).get("family", ""))
						if fam != "" and not fam in out:
							out.append(fam)
					return out
			return []
		"sponsors":
			return _sorted_keys(inst.get("sponsors", {}))
		"hosts":
			return (inst.get("hosts", []) as Array).duplicate()
	return []


## Whether an effect (or a schedule line, a contract) of `inst` applies: its `needs` part is sponsored or organized.
static func _part_ok(inst: Dictionary, e: Dictionary) -> bool:
	var need := str(e.get("needs", ""))
	return need == "" or part_on(inst, need)


static func part_on(inst: Dictionary, part: String) -> bool:
	if (inst.get("organized", {}) as Dictionary).has(part):
		return true
	for fam: Variant in inst.get("sponsors", {}):
		if part in (inst["sponsors"][fam] as Array):
			return true
	return false


# --- Weddings and the Christmas bonus -------------------------------------------------------------------------------

## H8: a wedding of a rich family (title >= rich_min_title, or an AI family) opens the noble wedding tomorrow; the
## player's own waits for festival_host_wedding (an offer for one day).
static func _on_wedding(sim: Sim, e: Dictionary) -> void:
	var st := sim.state
	var fam := str(e.get("family", ""))
	var f: Dictionary = st.families.get(fam, {})
	if f.is_empty():
		return
	var couple := [str(e.get("character", "")), str(e.get("spouse", ""))]
	var hosts := [fam]
	var other := str(e.get("from_family", ""))
	if other != "" and other != fam and st.families.has(other):
		hosts.append(other)
	var tomorrow := Clock.day(int(st.clock["minute"])) + 1
	if str(f.get("controlled_by", "")) == "human":
		st.festivals["offers"][fam] = {"couple": couple, "hosts": hosts, "until": int(st.clock["minute"]) + MPD}
		Notices.add(sim, fam, Notices.INFO, "notice.festival_wedding_offer", {"gold": int(rules(sim).get("wedding", {}).get(
			"player_feast_gold", 80))}, couple[0])
		sim.events.append({"type": "festival_wedding_offer", "family": fam, "couple": couple})
		return
	if not _rich(sim, fam):
		return
	_schedule(sim, "noble_wedding", tomorrow, "wedding", {"hosts": hosts, "couple": couple})


static func _on_townsfolk_wedding(sim: Sim, e: Dictionary) -> void:
	var tomorrow := Clock.day(int(sim.state.clock["minute"])) + 1
	_schedule(sim, "neighbours_wedding", tomorrow, "wedding", {"couple": [str(e.get("husband", "")),
		str(e.get("wife", ""))]})


static func _rich(sim: Sim, fam: String) -> bool:
	var f: Dictionary = sim.state.families.get(fam, {})
	if str(f.get("ai_profile", "")) != "":
		return true
	var ladder := sim.catalog.title_ladder()
	var want := ladder.find(str(rules(sim).get("wedding", {}).get("rich_min_title", "citizen")))
	return want >= 0 and ladder.find(str(f.get("title", ""))) >= want


## Christmas (aguinaldo): a bonus to an employee while the feast is on gives the extra loyalty.
static func _on_bonus(sim: Sim, e: Dictionary) -> void:
	for inst: Dictionary in sim.state.festivals.get("active", []):
		for fx: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			if str(fx.get("kind", "")) == "aguinaldo":
				Staff._add_loyalty(sim, str(e.get("employee", "")), int(fx.get("loyalty", 0)), "aguinaldo")
				if OS.is_debug_build():
					print("[Festivals] aguinaldo de %s a %s: lealtad %+d" % [e.get("family", ""), e.get("employee", ""),
						int(fx.get("loyalty", 0))])


# --- Orders ---------------------------------------------------------------------------------------------------------

## {"type": "festival_sponsor", "actor", "festival", "part"} (management): the actor's family pays a part of an
## announced or running feast (rules.sponsor.parts: banquet, music, bulls). Reasons: unknown_actor, dead, no_family,
## festivals_off, unknown_festival, festival_over, bad_part, already_sponsored, not_enough_gold.
static func order_sponsor(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var part := str(o.get("part", ""))
	var why := _actor_reason(sim, actor)
	if why != "":
		return Orders.fail(why)
	var inst := find(sim, str(o.get("festival", "")))
	if inst.is_empty():
		return Orders.fail("unknown_festival")
	if not bool(inst.get("announced", false)):
		return Orders.fail("unknown_festival")
	var def: Dictionary = rules(sim).get("sponsor", {}).get("parts", {}).get(part, {})
	if def.is_empty() or not part in sponsor_parts(sim, inst):
		return Orders.fail("bad_part")
	var fam := str(sim.state.characters[actor].get("family", ""))
	if part in (inst["sponsors"].get(fam, []) as Array):
		return Orders.fail("already_sponsored")
	var gold := int(def.get("gold", 0))
	if not Money.change(sim, fam, -gold, Money.DONATIONS, str(inst["id"]), "", actor):
		return Orders.fail("not_enough_gold")
	if not (inst["sponsors"] as Dictionary).has(fam):
		inst["sponsors"][fam] = []
	(inst["sponsors"][fam] as Array).append(part)
	Reputation.change(sim, fam, int(def.get("reputation", 0)), "festival_sponsor")
	FestivalContracts.post_for(sim, inst)  # the contracts this part opens (needs)
	sim.events.append({"type": "festival_sponsored", "festival": str(inst["id"]), "def": str(inst["def"]),
		"family": fam, "part": part, "gold": gold})
	var params := {"festival": str(inst["def"]), "family": str(sim.state.families[fam].get("name", "")), "part": part}
	for f: String in _humans(sim.state):
		Notices.add(sim, f, Notices.INFO, "notice.festival_sponsored", params, actor)
	if OS.is_debug_build():
		print("[Festivals] %s (%s) patrocina %s de %s por %d" % [actor, fam, part, inst["id"], gold])
	return Orders.ok()


## The parts of `inst` that may be sponsored: the banquet and the music always; the bulls where the feast has them.
static func sponsor_parts(sim: Sim, inst: Dictionary) -> Array:
	var out: Array = []
	var parts: Dictionary = rules(sim).get("sponsor", {}).get("parts", {})
	var needed := _needs_of(sim, inst)
	for p: String in _sorted_keys(parts):
		if p in ["banquet", "music"] or p in needed:
			out.append(p)
	return out


## Every `needs` named by the feast's effects, schedule and contracts.
static func _needs_of(sim: Sim, inst: Dictionary) -> Array:
	var d := def_of(sim, str(inst["def"]))
	var out: Array = []
	for list: Array in [d.get("effects", []), d.get("schedule", []), d.get("view", {}).get("decor", []),
			FestivalContracts.table(sim, str(d.get("contracts", "")))]:
		for e: Dictionary in list:
			var n := str(e.get("needs", ""))
			if n != "" and not n in out:
				out.append(n)
	return out


## {"type": "festival_host_wedding", "actor"} (management): the player pays the banquet of its family's wedding (an
## offer of one day): the noble wedding opens tomorrow with its contracts. Reasons: no_wedding, not_enough_gold.
static func order_host_wedding(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var why := _actor_reason(sim, actor)
	if why != "":
		return Orders.fail(why)
	var fam := str(sim.state.characters[actor].get("family", ""))
	var offer: Dictionary = sim.state.festivals.get("offers", {}).get(fam, {})
	if offer.is_empty() or int(offer.get("until", 0)) < int(sim.state.clock["minute"]):
		return Orders.fail("no_wedding")
	var w: Dictionary = rules(sim).get("wedding", {})
	if not Money.change(sim, fam, -int(w.get("player_feast_gold", 80)), Money.DONATIONS, "wedding_feast", "", actor):
		return Orders.fail("not_enough_gold")
	sim.state.festivals["offers"].erase(fam)
	Reputation.change(sim, fam, int(w.get("player_feast_reputation", 4)), "festival_wedding")
	var id := _schedule(sim, "noble_wedding", Clock.day(int(sim.state.clock["minute"])) + 1, "wedding",
		{"hosts": offer.get("hosts", [fam]), "couple": offer.get("couple", []), "by": actor})
	sim.events.append({"type": "festival_wedding_hosted", "family": fam, "festival": id})
	if OS.is_debug_build():
		print("[Festivals] %s paga el banquete de su boda: %s" % [fam, id])
	return Orders.ok()


## H10 power organize_festival {festival, part} of the mayor: the reason it may not be used ("" = it may).
static func organize_reason(sim: Sim, _actor: String, args: Dictionary) -> String:
	if not enabled(sim):
		return "festivals_off"
	var inst := find(sim, str(args.get("festival", "")))
	if inst.is_empty() or int(inst["end"]) <= int(sim.state.clock["minute"]):
		return "unknown_festival"
	var part := str(args.get("part", ""))
	if not part in (rules(sim).get("organize", {}).get("parts", []) as Array):
		return "bad_args"
	if not part in organizable(sim, inst):
		return "bad_args"
	if (inst["organized"] as Dictionary).has(part):
		return "already_organized"
	return ""


## What the mayor may organize in `inst`: its organizable list, and the joust on the patron feast.
static func organizable(sim: Sim, inst: Dictionary) -> Array:
	var out: Array = (def_of(sim, str(inst["def"])).get("organizable", []) as Array).duplicate()
	if bool(inst.get("patron", false)):
		for p: Variant in rules(sim).get("organize", {}).get("parts", []):
			if not str(p) in out:
				out.append(str(p))
	return out


## Uses organize_festival (Offices.order_power checked it): the concejo pays (rules.organize.cost, abstract: there is
## no town treasury yet); the joust opens the tournament on that day.
static func organize(sim: Sim, actor: String, args: Dictionary) -> void:
	var inst := find(sim, str(args.get("festival", "")))
	var part := str(args.get("part", ""))
	inst["organized"][part] = actor
	FestivalContracts.post_for(sim, inst)
	var opens := str(rules(sim).get("organize", {}).get("joust_opens", ""))
	if part == "joust" and opens != "":
		_schedule(sim, opens, int(inst["day"]), "organized", {"by": actor})
	sim.events.append({"type": "festival_organized", "festival": str(inst["id"]), "def": str(inst["def"]), "part": part,
		"actor": actor, "cost": int(rules(sim).get("organize", {}).get("cost", {}).get(part, 0))})
	for f: String in _humans(sim.state):
		Notices.add(sim, f, Notices.INFO, "notice.festival_organized", {"festival": str(inst["def"]), "part": part,
			"name": str(sim.state.characters.get(actor, {}).get("name", ""))}, actor)
	if OS.is_debug_build():
		print("[Festivals] %s organiza %s en %s" % [actor, part, inst["id"]])


# --- Multipliers (what the rules read) ------------------------------------------------------------------------------

## The product of the festivals' effects of `kind` (demand | price | customers | production) now; for the group ones,
## on `item`'s groups. holy_day counts as production on every item. 1 with the festivals off or none on.
static func mult(sim: Sim, kind: String, item: String = "") -> float:
	var act: Array = sim.state.festivals.get("active", []) if sim.state.festivals.get("active") is Array else []
	if act.is_empty() or not enabled(sim):
		return 1.0
	var now := int(sim.state.clock["minute"])
	var groups: Array = sim.catalog.goods_of(item) if item != "" and kind in GROUP_EFFECTS else []
	var m := 1.0
	for inst: Dictionary in act:
		for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			var k := str(e.get("kind", ""))
			if k == "holy_day" and kind == "production":
				if _effect_on(inst, e, now):
					m *= float(e.get("work_mult", 1.0))
				continue
			if k != kind or not _effect_on(inst, e, now):
				continue
			if kind in GROUP_EFFECTS and not str(e.get("group", "")) in groups:
				continue
			m *= float(e.get("mult", 1.0))
	return m


## Whether effect `e` of the running `inst` is on at `now` (its hour window and its needs).
static func _effect_on(inst: Dictionary, e: Dictionary, now: int) -> bool:
	if now < int(inst["start"]) or now >= int(inst["end"]) or not _part_ok(inst, e):
		return false
	var base := int(inst["day"]) * MPD
	if e.has("from_hour") and now < base + int(e["from_hour"]) * 60:
		return false
	if e.has("to_hour") and now >= base + int(e["to_hour"]) * 60:
		return false
	return true


## Why `item`'s price is not its base because of a festival: [{source: "festival", id, group, kind, mult}].
static func factors(sim: Sim, item: String) -> Array:
	var out: Array = []
	if not enabled(sim):
		return out
	var now := int(sim.state.clock["minute"])
	var groups: Array = sim.catalog.goods_of(item)
	for inst: Dictionary in sim.state.festivals.get("active", []):
		for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			var k := str(e.get("kind", ""))
			if k in ["price", "demand"] and str(e.get("group", "")) in groups and _effect_on(inst, e, now) \
					and absf(float(e.get("mult", 1.0)) - 1.0) > 0.0001:
				out.append({"source": "festival", "id": str(inst["def"]), "group": str(e["group"]), "kind": k,
					"mult": float(e["mult"])})
	return out


## The hooks of the other blocks (service tavern, visitors, routine <activity>, incident <id>): the product of the
## running festivals' `kind` effects whose id / activity is `key` ("" = any), and the unsponsored visitors' cut.
static func hook_mult(sim: Sim, kind: String, key: String = "") -> float:
	if not enabled(sim):
		return 1.0
	var now := int(sim.state.clock["minute"])
	var m := 1.0
	for inst: Dictionary in sim.state.festivals.get("active", []):
		var mi := 1.0
		for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			if str(e.get("kind", "")) != kind or not _effect_on(inst, e, now):
				continue
			var k := str(e.get("activity", e.get("id", "")))
			if key == "" or k == key:
				mi *= float(e.get("mult", 1.0))
		if kind == "visitors" and (inst["sponsors"] as Dictionary).is_empty() and mi != 1.0:
			mi *= float(rules(sim).get("unsponsored_visitors_mult", 1.0))
		m *= mi
	return m


## The festivals of today (running or still to start today), for the life block's plans made at the start of the day.
static func _today(sim: Sim) -> Array:
	if not enabled(sim):
		return []
	var today := Clock.day(int(sim.state.clock["minute"]))
	return _all(sim).filter(func(i: Dictionary) -> bool: return int(i.get("day", -1)) == today)


## Whether a feast of the calendar is on today (vida: the plaza guard, Life.festival).
static func on_today(sim: Sim) -> bool:
	return not _today(sim).is_empty()


## The product of today's festivals' `kind` effects (any hour), with the unsponsored cut for visitors (vida plans the
## day's visitors at its start: Visitors._plan_day through Life.event_mult).
static func today_mult(sim: Sim, kind: String) -> float:
	var m := 1.0
	for inst: Dictionary in _today(sim):
		var mi := 1.0
		for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			if str(e.get("kind", "")) == kind and _part_ok(inst, e):
				mi *= float(e.get("mult", 1.0))
		if kind == "visitors" and (inst["sponsors"] as Dictionary).is_empty() and mi != 1.0:
			mi *= float(rules(sim).get("unsponsored_visitors_mult", 1.0))
		m *= mi
	return m


## The visitor kinds today's festivals bring, sorted.
static func today_kinds(sim: Sim) -> Array:
	var out: Array = []
	for inst: Dictionary in _today(sim):
		for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			if str(e.get("kind", "")) == "visitors":
				for k: Variant in e.get("kinds", []):
					if not str(k) in out:
						out.append(str(k))
	out.sort()
	return out


## The visitor kinds the running festivals bring (4.24.3), sorted, [] if none.
static func hook_kinds(sim: Sim) -> Array:
	var out: Array = []
	if not enabled(sim):
		return out
	var now := int(sim.state.clock["minute"])
	for inst: Dictionary in sim.state.festivals.get("active", []):
		for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			if str(e.get("kind", "")) == "visitors" and _effect_on(inst, e, now):
				for k: Variant in e.get("kinds", []):
					if not str(k) in out:
						out.append(str(k))
	out.sort()
	return out


## The sum of the running festivals' need effects on `need` (4.24.1, e.g. faith +40 with the preacher).
static func hook_amount(sim: Sim, need: String) -> int:
	var n := 0
	if not enabled(sim):
		return n
	var now := int(sim.state.clock["minute"])
	for inst: Dictionary in sim.state.festivals.get("active", []):
		for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			if str(e.get("kind", "")) == "need" and str(e.get("id", "")) == need and _effect_on(inst, e, now):
				n += int(e.get("amount", 0))
	return n


## The spectacles of the running festivals still to come or on now: [{festival, def, spectacle, at}] (4.26).
static func spectacles(sim: Sim) -> Array:
	var out: Array = []
	if not enabled(sim):
		return out
	for inst: Dictionary in sim.state.festivals.get("active", []) + sim.state.festivals.get("upcoming", []):
		for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			if str(e.get("kind", "")) == "spectacle" and _part_ok(inst, e):
				out.append({"festival": str(inst["id"]), "def": str(inst["def"]), "spectacle": str(e.get("id", "")),
					"at": int(inst["day"]) * MPD + int(e.get("hour", 0)) * 60})
	return out


## Whether a holy day is on now (4.24.1: work ×0,3 in the routines of the townsfolk; the hook of the life block).
static func holy_day(sim: Sim) -> bool:
	return mult(sim, "production", "") < 0.999 and _holy_now(sim)


static func _holy_now(sim: Sim) -> bool:
	var now := int(sim.state.clock["minute"])
	for inst: Dictionary in sim.state.festivals.get("active", []):
		for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			if str(e.get("kind", "")) == "holy_day" and _effect_on(inst, e, now):
				return true
	return false


# --- The region (09b): the other cities' feasts and fairs; the home fair's taxes ------------------------------------

## The feasts of city `c` on `day`: [{kind: patron | fair, id, day_of_year, ...data}] (region.json; pure calendar).
static func city_feasts(sim: Sim, c: String, day: int) -> Array:
	var out: Array = []
	var s := Region.settlement(sim, c)
	var doy := posmod(day, days_per_year(sim))
	var pf: Dictionary = s.get("patron_feast", {})
	if not pf.is_empty() and int(pf.get("day_of_year", -1)) == doy:
		var p := pf.duplicate()
		p["kind"] = "patron"
		out.append(p)
	var fair: Dictionary = s.get("fair", {})
	if not fair.is_empty() and int(fair.get("day_of_year", -1)) == doy:
		var fd := fair.duplicate()
		fd["kind"] = "fair"
		fd["id"] = str(fair.get("festival", "fair"))
		out.append(fd)
	return out


## mod of the feasts of city `c` today on `item` (kind demand): the product of the patron feast's and the fair's
## demand entries that name the item or one of its groups. 1 with the festivals off.
static func city_mult(sim: Sim, c: String, kind: String, item: String) -> float:
	if kind != "demand" or not enabled(sim):
		return 1.0
	var m := 1.0
	var groups: Array = sim.catalog.goods_of(item)
	for feast: Dictionary in city_feasts(sim, c, Clock.day(int(sim.state.clock["minute"]))):
		var dem: Dictionary = feast.get("demand", {})
		for k: String in dem:
			if k == item or k in groups:
				m *= float(dem[k])
	return m


## The tariff multiplier of city `c` today (its fair: tariff_mult, 0 = feria franca).
static func city_tariff_mult(sim: Sim, c: String) -> float:
	if not enabled(sim):
		return 1.0
	var m := 1.0
	for feast: Dictionary in city_feasts(sim, c, Clock.day(int(sim.state.clock["minute"]))):
		if str(feast.get("kind", "")) == "fair":
			m *= float(feast.get("tariff_mult", 1.0))
	return m


## The toll of route `r` now: 0 while a city at either end has its fair within toll_free_days (the fair day and the
## days before it), else the route's own.
static func route_toll(sim: Sim, r: Dictionary) -> int:
	var toll := int(r.get("toll", 0))
	if toll == 0 or not enabled(sim):
		return toll
	var today := Clock.day(int(sim.state.clock["minute"]))
	for c: String in [str(r.get("a", "")), str(r.get("b", ""))]:
		var fair: Dictionary = Region.settlement(sim, c).get("fair", {})
		if fair.is_empty():
			continue
		var days := maxi(1, int(fair.get("toll_free_days", 1)))
		for k: int in days:
			if posmod(today + k, days_per_year(sim)) == int(fair.get("day_of_year", -1)):
				return 0
	return toll


## The home town's tax multiplier of the sales of `day` (a feast with tariff {city: home} that day: the feria franca).
static func home_tax_mult(sim: Sim, day: int) -> float:
	if not enabled(sim):
		return 1.0
	var m := 1.0
	for inst: Dictionary in _all(sim) + (sim.state.festivals.get("history", []) as Array):
		if int(inst.get("day", -1)) != day or int(inst.get("start", 0)) > int(sim.state.clock["minute"]):
			continue
		for e: Dictionary in def_of(sim, str(inst["def"])).get("effects", []):
			if str(e.get("kind", "")) == "tariff" and str(e.get("city", "")) in ["home", Region.home_id(sim)]:
				m *= float(e.get("mult", 1.0))
	return m


## On the eve of another city's fair, a notice for the human families (once: day_started runs once a day).
static func _city_eves(sim: Sim, day: int) -> void:
	for s: Dictionary in Region.settlements(sim):
		var c := str(s.get("id", ""))
		if c == Region.home_id(sim):
			continue
		for feast: Dictionary in city_feasts(sim, c, day + 1):
			if str(feast.get("kind", "")) != "fair":
				continue
			sim.events.append({"type": "city_fair_eve", "city": c, "day": day + 1})
			for f: String in _humans(sim.state):
				Notices.add(sim, f, Notices.INFO, "notice.city_fair_eve", {"city": str(s.get("name_key", c))})


# --- Queries ---------------------------------------------------------------------------------------------------------

## The instance `id` (upcoming, running or in the history), {} if unknown.
static func find(sim: Sim, id: String) -> Dictionary:
	var f: Dictionary = sim.state.festivals
	if f.is_empty():
		return {}
	for list: String in ["active", "upcoming", "history"]:
		for inst: Dictionary in f.get(list, []):
			if str(inst.get("id", "")) == id:
				return inst
	return {}


## Upcoming and running instances.
static func _all(sim: Sim) -> Array:
	var f: Dictionary = sim.state.festivals
	if f.is_empty():
		return []
	return (f.get("active", []) as Array) + (f.get("upcoming", []) as Array)


## The running festivals (for the view and the UI), oldest first.
static func active(sim: Sim) -> Array:
	return sim.state.festivals.get("active", []) if sim.state.festivals.get("active") is Array else []


## The announced ones that have not started yet.
static func announced(sim: Sim) -> Array:
	var out: Array = []
	for inst: Dictionary in sim.state.festivals.get("upcoming", []):
		if bool(inst.get("announced", false)):
			out.append(inst)
	return out


## The fixed feasts of the year in order: [{id, day_of_year, size}] (the calendar for the UI).
static func calendar(sim: Sim) -> Array:
	var out: Array = []
	for id: String in _sorted_keys(defs(sim)):
		var d: Dictionary = defs(sim)[id]
		if str(d.get("kind", "")) == "fixed":
			out.append({"id": id, "day_of_year": int(d.get("day_of_year", 0)), "size": str(d.get("size", ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["day_of_year"]) < int(b["day_of_year"]))
	return out


## The view's look of `inst` now: {decor: [{prop, where, count}] (the ones whose needs are met), clothes, music}.
static func view_of(sim: Sim, inst: Dictionary) -> Dictionary:
	var v: Dictionary = def_of(sim, str(inst["def"])).get("view", {})
	var decor: Array = []
	for dd: Dictionary in v.get("decor", []):
		if not _part_ok(inst, dd):
			continue
		var nc := str(dd.get("needs_contract", ""))
		if nc != "" and not FestivalContracts.done_item(sim, inst, nc):
			continue
		decor.append(dd)
	return {"decor": decor, "clothes": str(v.get("clothes", "")), "music": str(v.get("music", ""))}


static func _when_text(sim: Sim, inst: Dictionary) -> String:
	var s := int(inst["start"])
	return "%02d:%02d" % [Clock.hour(s), Clock.minute_of_day(s) % 60]


static func _sponsor_names(sim: Sim, inst: Dictionary) -> String:
	var names: Array = []
	for fam: String in _sorted_keys(inst.get("sponsors", {})):
		names.append(str(sim.state.families.get(fam, {}).get("name", fam)))
	return ", ".join(names)


static func _actor_reason(sim: Sim, actor: String) -> String:
	if not enabled(sim):
		return "festivals_off"
	var ch: Dictionary = sim.state.characters.get(actor, {})
	if ch.is_empty():
		return "unknown_actor"
	if not bool(ch.get("alive", true)):
		return "dead"
	if not sim.state.families.has(str(ch.get("family", ""))):
		return "no_family"
	return ""


static func _humans(st: WorldState) -> Array:
	var out: Array = []
	for f: String in _sorted_keys(st.families):
		if str(st.families[f].get("controlled_by", "")) == "human":
			out.append(f)
	return out


static func _sorted_keys(d: Dictionary) -> Array:
	var keys: Array = []
	for k: Variant in d.keys():
		keys.append(str(k))
	keys.sort()
	return keys
