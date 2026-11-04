class_name Incidents
extends RefCounted
## Incidents of the town (docs/gdd/04f_vida_y_fiestas.md §4.24.5; docs/contratos/vida.md): the brawl (altercation),
## the bandits' night raid (bandit_raid) and the kidnapping. Data: data/life/incidents.json; their own random stream
## (keys "events_city|<def>|..."; never state.rng) and off in the targets of before (_no_life). No deaths and no
## wounds (O4): losing leaves «scared» (emotion) and the purse. Fair risk: a raid is rumoured the day before (and a
## notice), the card lets the player choose, and nothing takes more than max_gold_share of the gold or max_items items.
## The fights are the duel's (Duel.auto, «Resolver sin jugar»: the same odds as playing well).
##
## state.town.incidents: active [incident], closed [the last 20], nests {route: day until it is «escarmentado»},
## last {def: day it last started; kidnapping_year}, warned {key: {until, place_key, def}}, planned [{def, at, key}],
## mult (a multiplier of the chances, a number or {def: mult}: scenarios and tests).
## An incident: {id, def, phase, started, tile, people [chr], card {family, choices, default, expires} | {}, ...}.
## Orders: resolve_incident {actor, incident, choice[, helpers]}.

const KEEP_CLOSED: int = 20


static func defs(sim: Sim) -> Dictionary:
	return sim.catalog.life_tables.get("incidents", {})


static func def(sim: Sim, id: String) -> Dictionary:
	var d: Variant = defs(sim).get(id, {})
	return d if d is Dictionary else {}


static func book(st: WorldState) -> Dictionary:
	var bi: Variant = st.town.get("incidents")
	if bi is Dictionary and (bi as Dictionary).has("planned"):
		return bi
	Life.ensure(st)
	var b: Dictionary = st.town["incidents"]
	if not b.get("planned") is Array:
		b["planned"] = []
	return b


static func active(st: WorldState) -> Array:
	var i: Variant = st.town.get("incidents")
	return (i as Dictionary).get("active", []) if i is Dictionary else []


static func find(st: WorldState, id: String) -> Dictionary:
	for i: Dictionary in active(st):
		if str(i.get("id", "")) == id:
			return i
	return {}


## Whether an incident holds `chr` now (a brawler, a watcher, a bandit, a captive): the agenda leaves it alone.
static func holds(st: WorldState, chr: String) -> bool:
	for i: Dictionary in active(st):
		if chr in (i.get("people", []) as Array) or chr in (i.get("watchers", []) as Array):
			return true
	return false


static func step(sim: Sim) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	var b := book(st)
	for e: Dictionary in sim.events:
		if str(e.get("type", "")) == "phase_changed" and str(e.get("phase", "")) == "dawn":
			_dawn(sim, now)
	for w: String in (b["warned"] as Dictionary).keys():
		if now >= int(b["warned"][w].get("until", 0)):
			b["warned"].erase(w)
	var keep: Array = []
	for p: Dictionary in b["planned"]:
		if now >= int(p["at"]):
			_start_planned(sim, p)
		else:
			keep.append(p)
	b["planned"] = keep
	if now % 60 == 0:
		_roll_altercation(sim, now)
	for i: Dictionary in active(st).duplicate():
		match str(i["def"]):
			"altercation":
				_altercation(sim, i, now)
			"bandit_raid":
				_raid(sim, i, now)
			"kidnapping":
				_kidnap(sim, i, now)
		var card: Dictionary = i.get("card", {})
		if not card.is_empty() and not bool(card.get("answered", false)) and now >= int(card.get("expires", 0)) \
				and find(st, str(i["id"])).size() > 0:
			_choose(sim, i, str(card.get("default", "")), Kin.head(st, str(card.get("family", ""))), {}, "timeout")


# --- Chances ----------------------------------------------------------------------------------------------------------

## The multiplier of every chance of `def` now: state (scenarios), the events in force (incident effects), the
## season and the war (raids).
static func mult(sim: Sim, id: String) -> float:
	var st := sim.state
	var sm: Variant = book(st).get("mult", 1.0)  # a number for all, or {def: mult} (scenarios, tests)
	var m := (float((sm as Dictionary).get(id, 1.0)) if sm is Dictionary else float(sm)) * Life.event_mult(sim, "incident", id)
	var d := def(sim, id)
	if Clock.season(int(st.clock["minute"]), sim.catalog.time) == "winter":
		m *= float(d.get("winter_mult", 1.0))
	if WorldEvents.is_active(sim, "war"):
		m *= float(d.get("war_mult", 1.0))
	return m


static func _hours(d: Dictionary) -> int:
	var h: Array = d.get("hours", [0, 24])
	return maxi(1, int(h[1]) - int(h[0]))


## At dawn: the raid of tomorrow night is rolled today (so it is rumoured the day before: fair risk), the kidnapping
## of tonight too (rumoured from the morning).
static func _dawn(sim: Sim, now: int) -> void:
	var st := sim.state
	var b := book(st)
	var today := Clock.day(now)
	for id: String in ["bandit_raid", "kidnapping"]:
		var d := def(sim, id)
		if d.is_empty():
			continue
		var day := today + (1 if id == "bandit_raid" else 0)
		if day < int(d.get("min_day", 0)) or day <= int(b["last"].get(id, -999)) + int(d.get("cooldown_days", 0)):
			continue
		if id == "kidnapping" and int(b["last"].get("kidnapping_year", -1)) == Clock.year(day * Clock.MINUTES_PER_DAY, sim.catalog.time):
			continue
		var p := clampf(float(d.get("chance", 0.0)) * mult(sim, id), 0.0, 1.0)
		if Kin.roll(st, "events_city|%s|%d" % [id, day]) >= p:
			continue
		var hours: Array = d.get("hours", [22, 28])
		var at := day * Clock.MINUTES_PER_DAY + Kin.randi_range(st, "events_city|%s|at|%d" % [id, day],
			int(hours[0]) * 60, int(hours[1]) * 60 - 30)
		var key := "%s|%d" % [id, day]
		b["planned"].append({"def": id, "at": at, "key": key})
		b["last"][id] = day
		if id == "kidnapping":
			b["last"]["kidnapping_year"] = Clock.year(day * Clock.MINUTES_PER_DAY, sim.catalog.time)
		var nest := nest_route(sim)
		b["warned"][key] = {"until": at + 60, "place_key": nest_key(sim, nest), "def": id}
		for f: String in Life.humans(st):
			Notices.add(sim, f, Notices.WARNING, "notice.life.bandits_seen", {"place": nest_key(sim, nest)}, "")
		sim.events.append({"type": "incident_warned", "def": id, "at": at})
		if OS.is_debug_build():
			print("[Incidents] %s previsto para el minuto %d (aviso: bandidos por %s)" % [id, at, nest])


## The route of the region with most risk out of the home town: where the bandits nest («escarmentado» routes skip).
static func nest_route(sim: Sim) -> String:
	var home := Region.home_id(sim)
	var day := Clock.day(int(sim.state.clock["minute"]))
	var best := ""
	var risk := -1
	for r: Dictionary in Region.routes(sim):
		if str(r.get("a", "")) != home and str(r.get("b", "")) != home:
			continue
		if int(book(sim.state)["nests"].get(str(r.get("id", "")), -1)) > day:
			continue
		if int(r.get("risk", 0)) > risk:
			risk = int(r.get("risk", 0))
			best = str(r["id"])
	return best


static func nest_key(sim: Sim, route: String) -> String:
	return str(defs(sim).get("nests", {}).get(route, "nest.road"))


## Whether the bandits are «escarmentados» (every nest of the home routes beaten this year).
static func nests_quiet(sim: Sim) -> bool:
	return nest_route(sim) == ""


static func _start_planned(sim: Sim, p: Dictionary) -> void:
	if nests_quiet(sim):
		if OS.is_debug_build():
			print("[Incidents] %s no llega: los nidos están escarmentados" % p["def"])
		return
	match str(p["def"]):
		"bandit_raid":
			_start_raid(sim, str(p["key"]), str(p.get("building", "")))
		"kidnapping":
			_start_kidnap(sim, str(p["key"]), str(p.get("victim", "")))
		"altercation":
			var d := def(sim, "altercation")
			var pick := _brawlers(sim, d, int(sim.state.clock["minute"]))
			if not pick.is_empty():
				_begin_altercation(sim, pick, int(sim.state.clock["minute"]))


static func _new(sim: Sim, id: String, extra: Dictionary) -> Dictionary:
	var st := sim.state
	var inc := {"id": Ids.next(st, "inc"), "def": id, "phase": "start", "started": int(st.clock["minute"]), "people": [],
		"watchers": [], "card": {}}
	inc.merge(extra, true)
	(book(st)["active"] as Array).append(inc)
	return inc


static func _close(sim: Sim, inc: Dictionary, outcome: String) -> void:
	var st := sim.state
	var b := book(st)
	(b["active"] as Array).erase(inc)
	inc["phase"] = "closed"
	inc["outcome"] = outcome
	inc["ended"] = int(st.clock["minute"])
	(b["closed"] as Array).append(inc)
	while (b["closed"] as Array).size() > KEEP_CLOSED:
		(b["closed"] as Array).pop_front()
	Watch.release(st, str(inc["id"]))
	for c: Variant in (inc.get("people", []) as Array) + (inc.get("watchers", []) as Array):
		var ch: Dictionary = st.characters.get(str(c), {})
		if ch.get("town") is Dictionary:
			Agenda._clear(ch["town"])
	sim.events.append({"type": "incident_ended", "incident": str(inc["id"]), "def": str(inc["def"]), "outcome": outcome})
	if OS.is_debug_build():
		print("[Incidents] %s (%s) termina: %s" % [inc["id"], inc["def"], outcome])


## The card of `inc` for the player's family `fam` (choices of the def; an AI family answers the default).
static func _card(sim: Sim, inc: Dictionary, fam: String, choices: Array = []) -> void:
	var st := sim.state
	if fam == "" or str(st.families.get(fam, {}).get("controlled_by", "")) != "human":
		return
	var d := def(sim, str(inc["def"]))
	var now := int(st.clock["minute"])
	inc["card"] = {"family": fam, "choices": choices if not choices.is_empty() else d.get("choices", []),
		"default": str(d.get("default", "")), "started": now,
		"expires": now + roundi(float(d.get("timeout_hours", 1)) * 60.0), "answered": false}
	Notices.add(sim, fam, Notices.URGENT, "notice.life." + str(inc["def"]), params(sim, inc), str(inc.get("building", "")))
	sim.events.append({"type": "incident_card", "incident": str(inc["id"]), "def": str(inc["def"]), "family": fam})


# --- Altercation -------------------------------------------------------------------------------------------------

static func _roll_altercation(sim: Sim, now: int) -> void:
	var st := sim.state
	var d := def(sim, "altercation")
	if d.is_empty():
		return
	var h := Clock.minute_of_day(now) / 60
	var win: Array = d.get("hours", [19, 26])
	if not Agenda._in_hours(h, int(win[0]), int(win[1])):
		return
	for i: Dictionary in active(st):
		if str(i["def"]) == "altercation":
			return
	var b := book(st)
	var today := Clock.day(now - int(win[0]) * 60)  # the evening's day (past midnight it is still last evening)
	if int(b["last"].get("altercation_pending", -1)) != today:
		var per_day := clampf(float(d.get("chance", 0.5)) * mult(sim, "altercation"), 0.0, 1.0)
		var p := 1.0 - pow(1.0 - per_day, 1.0 / float(_hours(d)))
		if Kin.roll(st, "events_city|altercation|%d" % now) >= p:
			return
		b["last"]["altercation_pending"] = today  # it will happen this evening, as soon as two are out to quarrel
	var pick := _brawlers(sim, d, now)
	if pick.is_empty():
		return
	b["last"]["altercation_pending"] = -1
	_begin_altercation(sim, pick, now)


static func _begin_altercation(sim: Sim, pick: Dictionary, now: int) -> void:
	var st := sim.state
	var inc := _new(sim, "altercation", {"phase": "gathering", "tile": pick["tile"], "point": pick["point"],
		"people": [pick["a"], pick["b"]], "instigator": pick["a"], "why": pick["why"], "deadline": now + 30})
	sim.events.append({"type": "incident_started", "incident": str(inc["id"]), "def": "altercation", "tile": pick["tile"]})
	if OS.is_debug_build():
		print("[Incidents] altercado %s en %s: %s contra %s (%s)" % [inc["id"], pick["point"], pick["a"], pick["b"], pick["why"]])
	_card(sim, inc, Life.player_family(st))


## Two people out near a meeting point (a tavern first): a pair with relation <= relation_max if there is one, else
## «one drunk and one offended». {a, b, tile, point, why} or {}.
static func _brawlers(sim: Sim, d: Dictionary, now: int) -> Dictionary:
	var st := sim.state
	var kinds: Array = d.get("where", ["tavern", "chat"])
	for kind: String in kinds:
		for p: Dictionary in Life.points(sim, [kind]):
			var tile: Array = (p.get("slots", [[0, 0]]) as Array)[0]
			var near: Array = []
			var ids: Array = st.characters.keys()
			ids.sort()
			for id: String in ids:
				var ch: Dictionary = st.characters[id]
				if not bool(ch.get("alive", true)) or str(ch.get("location", "")) != "" or Life.offstage(st, id) \
						or holds(st, id) or Watch.is_guard(st, id):
					continue
				var ok := TownLife.is_townsperson(st, id) and TownLife.is_adult(st, sim.catalog, id) \
					or str(ch.get("visitor", {}).get("kind", "")) == "soldier"
				if ok and Life.dist(Life.tile_of(st, id), tile) <= int(d.get("near_tiles", 8)):
					near.append(id)
			if near.size() < 2:
				continue
			for i: int in near.size():
				for j: int in range(i + 1, near.size()):
					if Emotions.relation(st, str(near[i]), str(near[j])) <= int(d.get("relation_max", -20)):
						return {"a": near[i], "b": near[j], "tile": tile, "point": str(p["id"]), "why": "grudge"}
			var a := Kin.randi_range(st, "events_city|alt|a|%d" % now, 0, near.size() - 1)
			var b := (a + 1 + Kin.randi_range(st, "events_city|alt|b|%d" % now, 0, near.size() - 2)) % near.size()
			return {"a": near[a], "b": near[b], "tile": tile, "point": str(p["id"]), "why": "drunk"}
	return {}


static func _altercation(sim: Sim, inc: Dictionary, now: int) -> void:
	var st := sim.state
	var d := def(sim, "altercation")
	var people: Array = inc["people"]
	for c: Variant in people:
		if not st.characters.has(str(c)):
			_close(sim, inc, "gone")
			return
	var a := str(people[0])
	var b := str(people[1])
	var tile: Array = inc["tile"]
	match str(inc["phase"]):
		"gathering":
			var ta := _walk(sim, a, tile, now)
			var tb := _walk(sim, b, Watch._near_free(sim, tile), now)
			if (ta and tb) or now >= int(inc.get("deadline", now)):
				if not (ta and tb) and Life.dist(Life.tile_of(st, a), Life.tile_of(st, b)) > 2:
					_close(sim, inc, "cooled")  # they never met
					return
				_fight(sim, inc, d, now)
		"fighting":
			for c: String in [a, b]:
				TownLife._set_state(sim, c, _t(st, c), "social", "brawl")
			for w: Variant in inc.get("watchers", []):
				if st.characters.has(str(w)):
					_walk(sim, str(w), _ring(sim, tile, str(w)), now)
					TownLife._set_state(sim, str(w), _t(st, str(w)), "social", "watch_fight")
			if not Watch.arrived(st, str(inc["id"])).is_empty():
				_end_fight(sim, inc, "watch")
			elif now >= int(inc.get("fight_until", now)):
				_end_fight(sim, inc, "")


static func _fight(sim: Sim, inc: Dictionary, d: Dictionary, now: int) -> void:
	var st := sim.state
	var a := str(inc["people"][0])
	var b := str(inc["people"][1])
	var w := str(d.get("weapon", "fists"))
	var res := Duel.auto(sim.catalog.combat, str(inc["id"]), st.world_seed, Duels.fighter_of(sim, a, w),
		Duels.fighter_of(sim, b, w), str(d.get("duel_kind", "first_blood")))
	var winner := a if int(res["winner"]) == 0 else (b if int(res["winner"]) == 1 else "")
	inc["winner"] = winner
	inc["phase"] = "fighting"
	inc["fight_until"] = now + int(d.get("fight_minutes", 25))
	var watchers: Array = []
	for id: String in Population.townsfolk(st):
		if watchers.size() >= int(d.get("watchers_max", 4)):
			break
		if id in [a, b] or holds(st, id) or str(st.characters[id].get("location", "")) != "":
			continue
		if Life.dist(Life.tile_of(st, id), inc["tile"]) <= int(d.get("watchers_tiles", 6)) and TownLife.is_adult(st, sim.catalog, id):
			watchers.append(id)
	inc["watchers"] = watchers
	Watch.respond(sim, inc["tile"], str(inc["id"]))
	sim.events.append({"type": "incident_fight", "incident": str(inc["id"]), "a": a, "b": b, "winner": winner,
		"watchers": watchers.size()})
	if OS.is_debug_build():
		print("[Incidents] %s: pelea %s contra %s (ganaría %s; %d mirones)" % [inc["id"], a, b, winner, watchers.size()])


## The brawl ends: separated by the watch (a fine to the one who started it: a «brawl» fact if a player's or rival's
## family), by the player (by: actor) or by itself (the loser is scared).
static func _end_fight(sim: Sim, inc: Dictionary, by: String) -> void:
	var st := sim.state
	var d := def(sim, "altercation")
	var a := str(inc["people"][0])
	var b := str(inc["people"][1])
	var winner := str(inc.get("winner", ""))
	var outcome := "fought"
	if by == "watch":
		outcome = "watch"
		var who := str(inc.get("instigator", a))
		var fam := str(st.characters.get(who, {}).get("family", ""))
		var span: Array = d.get("fine", [10, 20])
		var fine := mini(Money.gold(st, fam), Kin.randi_range(st, "events_city|fine|%s" % inc["id"], int(span[0]), int(span[1])))
		if fine > 0:
			Money.change(sim, fam, -fine, Money.FINES, str(inc["id"]), "", who)
		inc["fine"] = fine
		if not TownLife.is_household(st, fam) and not Life.is_service(st, fam):
			inc["fact"] = Tribunal.add_fact(sim, str(d.get("fact", "brawl")), fam, who, str(d.get("fact", "brawl")))
	elif by != "":
		outcome = "separated"
	if outcome in ["fought"] and winner != "":
		var loser := b if winner == a else a
		Emotions.add(sim, loser, "scared", str(st.characters.get(winner, {}).get("family", "")))
	Chronicle.add(st, "altercation", {"family": str(st.characters.get(a, {}).get("family", "")), "actor": a, "target": b,
		"winner": winner if outcome == "fought" else "", "outcome": outcome, "point": str(inc.get("point", "")),
		"by": by})
	var fam := str(inc.get("card", {}).get("family", ""))
	if fam != "":
		Notices.add(sim, fam, Notices.INFO, "notice.life.altercation_" + outcome, params(sim, inc), "")
	_close(sim, inc, outcome)


# --- Bandit raid ---------------------------------------------------------------------------------------------------

## A planned entry may name its building (scenarios): else the edge of the town decides (_raid_target).
static func _start_raid(sim: Sim, key: String, building: String = "") -> void:
	var st := sim.state
	var d := def(sim, "bandit_raid")
	var bld := building if st.buildings.has(building) else _raid_target(sim, d, key)
	if bld == "":
		return
	var door: Array = st.buildings[bld].get("door", Life.plaza(sim))
	var entry := _entry(sim, door)
	var span: Array = d.get("band", [2, 4])
	var n := Kin.randi_range(st, "events_city|band|" + key, int(span[0]), int(span[1]))
	Life.service_family(st, Life.FAMILY_BANDITS, "family.bandits", {"primary": "#2a2a2a", "secondary": "#5a4a3a"})
	var inc := _new(sim, "bandit_raid", {"phase": "approach", "building": bld, "tile": door.duplicate(), "entry": entry,
		"family": str(st.buildings[bld].get("owner", "")), "route": nest_route(sim), "deadline": int(st.clock["minute"]) + 180})
	var band: Array = []
	var stats: Dictionary = d.get("bandit_stats", {})
	for i: int in n:
		var k := "events_city|bandit|%s|%d" % [key, i]
		var s := {}
		for st_name: String in stats:
			var r: Array = stats[st_name]
			s[st_name] = Kin.randi_range(st, k + "|" + st_name, int(r[0]), int(r[1]))
		var look := Cast.newcomer(sim, k, false, 28)
		var id := Life.add_person(sim, Life.FAMILY_BANDITS, str(look.get("name", "?")), false, 28, s,
			{"tool": "sword"} if i == 0 else {}, entry, {"bandit": {"incident": str(inc["id"]), "leader": i == 0}})
		Life.put_on(sim, id, entry)
		band.append(id)
	inc["people"] = band
	sim.events.append({"type": "incident_started", "incident": str(inc["id"]), "def": "bandit_raid", "building": bld,
		"band": band.size()})
	if OS.is_debug_build():
		print("[Incidents] asalto %s: %d bandidos desde %s hacia %s (%s)" % [inc["id"], band.size(), entry, bld, inc["family"]])


## The building at the edge of the town (O-V4 a) the band goes for: among the edge_share farthest from the plaza,
## by weight 1 - its Security (lock and guard: Upgrades protection) [balance]. Houses, workshops and shops with an owner.
static func _raid_target(sim: Sim, d: Dictionary, key: String) -> String:
	var st := sim.state
	var centre := Life.plaza(sim)
	var all: Array = []
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		var bd: Dictionary = st.buildings[b]
		if str(bd.get("owner", "")) == "" or (bd.get("door", []) as Array).size() != 2:
			continue
		all.append([Life.dist(bd["door"], centre), b])
	if all.is_empty():
		return ""
	all.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) > int(y[0]) or (int(x[0]) == int(y[0]) and str(x[1]) < str(y[1])))
	var edge: Array = all.slice(0, maxi(1, ceili(float(all.size()) * float(d.get("edge_share", 0.34)))))
	var total := 0.0
	var weights: Array = []
	for e: Array in edge:
		var w := maxf(0.05, 1.0 - Upgrades.amount(sim, str(e[1]), "protection") * float(d.get("security_foil", 1.0)))
		weights.append(w)
		total += w
	var r := Kin.roll(st, "events_city|target|" + key) * total
	for i: int in edge.size():
		r -= float(weights[i])
		if r < 0.0:
			return str(edge[i][1])
	return str(edge[edge.size() - 1][1])


## Where the band comes in: the gate nearest to `door` («by a gate or by the fields»).
static func _entry(sim: Sim, door: Array) -> Array:
	var best: Array = Life.plaza(sim)
	var bd := 9999
	var gates := Life.gates(sim)
	var names: Array = gates.keys()
	names.sort()
	for g: String in names:
		var dd := Life.dist(gates[g], door)
		if dd < bd:
			bd = dd
			best = Agenda._inside(sim, gates[g])
	return best


static func _raid(sim: Sim, inc: Dictionary, now: int) -> void:
	var st := sim.state
	var d := def(sim, "bandit_raid")
	var band: Array = (inc["people"] as Array).filter(func(c: Variant) -> bool: return st.characters.has(str(c)))
	inc["people"] = band
	if band.is_empty():
		_close(sim, inc, str(inc.get("result", "fled")))
		return
	var door: Array = inc["tile"]
	if int(inc.get("alarm_at", -1)) >= 0 and now >= int(inc["alarm_at"]):
		inc["alarm_at"] = -1
		Watch.respond(sim, door, str(inc["id"]), true)
	match str(inc["phase"]):
		"approach":
			var there := false
			for i: int in band.size():
				var tile: Array = door if i == 0 else Watch._near_free(sim, door)
				there = _walk(sim, str(band[i]), tile, now) or there
				TownLife._set_state(sim, str(band[i]), _t(st, str(band[i])), "walking", "bandit")
			if there or now >= int(inc.get("deadline", now)):
				inc["phase"] = "breaking"
				inc["until"] = now + int(d.get("break_minutes", 30))
				Watch.respond(sim, door, str(inc["id"]))  # the dogs bark: a patrol near hears it
				sim.events.append({"type": "incident_raid_at_door", "incident": str(inc["id"]), "building": str(inc["building"])})
				_card(sim, inc, str(inc.get("family", "")))
		"breaking", "looting":
			for c: Variant in band:
				TownLife._set_state(sim, str(c), _t(st, str(c)), "social", "bandit")
			var guards := Watch.arrived(st, str(inc["id"]))
			if not guards.is_empty() and not bool(inc.get("fought_watch", false)):
				inc["fought_watch"] = true
				var won := _fights(sim, guards, band, str(inc["id"]) + "|watch", "")
				inc["watch_won"] = won
				if won:
					_repelled(sim, inc, "watch")
					return
			if now >= int(inc.get("until", now)):
				if str(inc["phase"]) == "breaking":
					inc["phase"] = "looting"
					inc["until"] = now + int(d.get("loot_minutes", 20))
				else:
					_loot(sim, inc, d)
					inc["phase"] = "leaving"
		"leaving":
			var out := true
			for c: Variant in band:
				if _walk(sim, str(c), inc["entry"], now):
					Life.remove_person(sim, str(c))
				else:
					out = false
					TownLife._set_state(sim, str(c), _t(st, str(c)), "walking", "bandit")
			if out:
				_close(sim, inc, str(inc.get("result", "robbed")))


## A chain of duels (Duel.auto: «Resolver sin jugar»): each side's fighters in order; the one who loses is out and the
## next one fights on. True if `side_a` beats every one of `side_b`. Losers of side_a get «scared» (source `fam_b`).
static func _fights(sim: Sim, side_a: Array, side_b: Array, key: String, fam_b: String) -> bool:
	var st := sim.state
	var i := 0
	var j := 0
	var n := 0
	while i < side_a.size() and j < side_b.size() and n < 12:
		var a := str(side_a[i])
		var b := str(side_b[j])
		var res := Duel.auto(sim.catalog.combat, "%s|%d" % [key, n], st.world_seed, Duels.fighter_of(sim, a),
			Duels.fighter_of(sim, b), "first_blood")
		n += 1
		if int(res["winner"]) == 0:
			j += 1
		elif int(res["winner"]) == 1:
			if fam_b != "" and st.characters.has(a):
				Emotions.add(sim, a, "scared", fam_b)
			i += 1
		else:
			i += 1
			j += 1
	var won := j >= side_b.size()
	if OS.is_debug_build():
		print("[Incidents] %s: %d combates, %s" % [key, n, "ganan los defensores" if won else "ganan los otros"])
	return won


## The band is beaten (by the watch or by the defenders): nothing taken; a nest beaten by the watch goes quiet.
static func _repelled(sim: Sim, inc: Dictionary, by: String) -> void:
	var st := sim.state
	var d := def(sim, "bandit_raid")
	inc["result"] = "repelled_" + by
	inc["phase"] = "leaving"
	if by == "watch" and str(inc.get("route", "")) != "":
		book(st)["nests"][str(inc["route"])] = Clock.day(int(st.clock["minute"])) + int(d.get("nest_years", 1)) * Clock.days_per_year(sim.catalog.time)
	Chronicle.add(st, "bandit_raid", {"family": str(inc.get("family", "")), "building": str(inc["building"]),
		"outcome": inc["result"], "place_key": nest_key(sim, str(inc.get("route", "")))})
	var fam := str(inc.get("family", ""))
	if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, fam, Notices.INFO, "notice.life.raid_" + by, params(sim, inc), str(inc["building"]))
	sim.events.append({"type": "incident_raid_repelled", "incident": str(inc["id"]), "by": by})


## What the band takes (fair risk): up to max_items units of the storage's most valuable products, else up to
## max_gold_share of the family's gold.
static func _loot(sim: Sim, inc: Dictionary, d: Dictionary) -> void:
	var st := sim.state
	var bld := str(inc["building"])
	var fam := str(inc.get("family", ""))
	var left := int(d.get("max_items", 3))
	var took: Array = []
	var inv: Dictionary = st.buildings.get(bld, {}).get("inventory", {})
	while left > 0 and not inv.is_empty():
		var best := Microevents._most_valuable(sim, bld)
		if best.is_empty():
			break
		var q := mini(left, Inventory.count(inv, str(best["item"]), int(best["quality"])))
		if q <= 0:
			break
		Inventory.remove(inv, str(best["item"]), int(best["quality"]), q)
		took.append({"item": str(best["item"]), "quality": int(best["quality"]), "qty": q})
		left -= q
	var gold := 0
	if took.is_empty() and fam != "":
		gold = floori(float(Money.gold(st, fam)) * float(d.get("max_gold_share", 0.1)))
		if gold > 0:
			Money.change(sim, fam, -gold, Money.LOOT, str(inc["id"]), bld)
	inc["took"] = took
	inc["gold"] = gold
	inc["result"] = "robbed"
	Chronicle.add(st, "bandit_raid", {"family": fam, "building": bld, "outcome": "robbed", "items": took.size(),
		"gold": gold, "place_key": nest_key(sim, str(inc.get("route", "")))})
	sim.events.append({"type": "incident_raid_loot", "incident": str(inc["id"]), "building": bld, "family": fam,
		"items": took.duplicate(true), "gold": gold})
	if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, fam, Notices.URGENT, "notice.life.raid_robbed", params(sim, inc), bld)
	if OS.is_debug_build():
		print("[Incidents] %s: los bandidos se llevan %s y %d de oro de %s" % [inc["id"], took, gold, bld])


# --- Kidnapping ----------------------------------------------------------------------------------------------------

## A planned entry may name its victim (scenarios): else _victim draws one.
static func _start_kidnap(sim: Sim, key: String, victim: String = "") -> void:
	var st := sim.state
	var d := def(sim, "kidnapping")
	var v := {"chr": victim, "kind": _kind_of(sim, victim)} if st.characters.has(victim) else _victim(sim, d, key)
	if v.is_empty():
		if OS.is_debug_build():
			print("[Incidents] secuestro %s: nadie a quien llevarse" % key)
		return
	var chr := str(v["chr"])
	var r: Array = d.get("ransom", {}).get(str(v["kind"]), [80, 160])
	var ransom := Kin.randi_range(st, "events_city|ransom|" + key, int(r[0]), int(r[1]))
	var fam := str(st.characters[chr].get("family", ""))
	var now := int(st.clock["minute"])
	var inc := _new(sim, "kidnapping", {"phase": "held", "victim": chr, "victim_kind": str(v["kind"]), "victim_family": fam,
		"ransom": ransom, "due": now + 2 * Clock.MINUTES_PER_DAY, "route": nest_route(sim), "negotiated": false,
		"rescued_tried": false, "tile": Life.tile_of(st, chr)})
	var ch: Dictionary = st.characters[chr]
	if str(ch.get("station", "")) != "":
		Orders.apply(sim, {"type": "stop_work", "actor": chr})
	ch["location"] = ""
	ch["path"] = []
	ch["captive"] = str(inc["id"])
	OrderQueue.clear_for(sim, chr)
	Chronicle.add(st, "kidnapping", {"family": fam, "victim": chr, "kind": str(v["kind"]), "ransom": ransom,
		"place_key": nest_key(sim, str(inc["route"]))})
	sim.events.append({"type": "incident_started", "incident": str(inc["id"]), "def": "kidnapping", "victim": chr,
		"kind": str(v["kind"])})
	var player := Life.player_family(st)
	if player != "":
		var choices: Array = ["pay", "negotiate", "rescue", "nothing"] if fam == player else ["rescue", "nothing"]
		_card(sim, inc, player, choices)
	if OS.is_debug_build():
		print("[Incidents] secuestro %s: se llevan a %s (%s), rescate %d" % [inc["id"], chr, v["kind"], ransom])


static func _kind_of(sim: Sim, chr: String) -> String:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.get("visitor") is Dictionary:
		return "visitor_noble"
	return "player_kin" if str(ch.get("family", "")) == Life.player_family(sim.state) else "patrician_child"


## The victim: a noble visitor, the child of a patrician (a family with a title >= patrician_title) or, rarely, one
## of the player's (never the head nor a child under player_kin_min_age): {chr, kind} or {}.
static func _victim(sim: Sim, d: Dictionary, key: String) -> Dictionary:
	var st := sim.state
	var pools := {"visitor_noble": [], "patrician_child": [], "player_kin": []}
	for v: String in Visitors.alive(st):
		if str(st.characters[v].get("visitor", {}).get("kind", "")) == "noble":
			pools["visitor_noble"].append(v)
	var ranks := _title_rank(sim)
	var min_rank := int(ranks.get(str(d.get("patrician_title", "citizen")), 1))
	var player := Life.player_family(st)
	var fams: Array = st.families.keys()
	fams.sort()
	for f: String in fams:
		var fd: Dictionary = st.families[f]
		if Life.is_service(st, f) or TownLife.is_household(st, f):
			continue
		var head := Kin.head(st, f)
		for m: Variant in fd.get("members", []):
			var id := str(m)
			var ch: Dictionary = st.characters.get(id, {})
			if ch.is_empty() or not bool(ch.get("alive", true)) or id == head or Region.is_away(st, id) \
					or Kin.age(sim, id) < int(d.get("player_kin_min_age", 8)):
				continue
			if f == player:
				pools["player_kin"].append(id)
			elif int(ranks.get(str(fd.get("title", "")), 0)) >= min_rank:
				pools["patrician_child"].append(id)
	var weights: Dictionary = d.get("victims", {})
	var total := 0.0
	var kinds: Array = weights.keys()
	kinds.sort()
	for k: String in kinds:
		total += float(weights[k])
	if total <= 0.0:
		return {}
	var r := Kin.roll(st, "events_city|victim|" + key) * total  # over every kind: a kind with nobody = nobody taken
	for k: String in kinds:
		r -= float(weights[k])
		if r < 0.0:
			var pool: Array = pools.get(k, [])
			if pool.is_empty():
				return {}
			return {"chr": pool[Kin.randi_range(st, "events_city|victim_pick|" + key, 0, pool.size() - 1)], "kind": k}
	return {}


## The rank of each title (data/titles "rank"): id -> rank.
static func _title_rank(sim: Sim) -> Dictionary:
	var out := {}
	for t: String in sim.catalog.tables.get("titles", {}):
		out[t] = int(sim.catalog.tables["titles"][t].get("rank", 0))
	return out


static func _kidnap(sim: Sim, inc: Dictionary, now: int) -> void:
	var st := sim.state
	var d := def(sim, "kidnapping")
	var chr := str(inc["victim"])
	if not st.characters.has(chr) or not bool(st.characters[chr].get("alive", true)):
		_close(sim, inc, "gone")
		return
	match str(inc["phase"]):
		"held":
			if now >= int(inc["due"]):
				_others_pay(sim, inc)
		"waiting":  # nobody paid for one of the player's: back after nothing_days, scared
			if now >= int(inc.get("back_at", now)):
				_free(sim, inc, "abandoned")
				Emotions.add(sim, chr, "scared", Life.FAMILY_BANDITS)
				Reputation.change(sim, str(inc["victim_family"]), int(d.get("nothing_reputation", -10)), "kidnap_unpaid")


## The ransom's day: the noble's house or the patrician family pay (if they can), else the victim comes back later.
static func _others_pay(sim: Sim, inc: Dictionary) -> void:
	var st := sim.state
	var d := def(sim, "kidnapping")
	var fam := str(inc["victim_family"])
	var player := Life.player_family(st)
	if fam == player:
		inc["phase"] = "waiting"
		inc["back_at"] = int(st.clock["minute"]) + (int(d.get("nothing_days", 4)) - 2) * Clock.MINUTES_PER_DAY
		return
	if str(inc["victim_kind"]) == "patrician_child" and Money.gold(st, fam) >= int(inc["ransom"]):
		Money.change(sim, fam, -int(inc["ransom"]), Money.EVENTS, str(inc["id"]))
	_free(sim, inc, "ransomed")


static func _free(sim: Sim, inc: Dictionary, outcome: String) -> void:
	var st := sim.state
	var chr := str(inc["victim"])
	var ch: Dictionary = st.characters.get(chr, {})
	if not ch.is_empty():
		ch.erase("captive")
		var tile := Region.gate_tile(sim)
		ch["position"] = tile.duplicate()
		ch["location"] = ""
		ch["path"] = []
		if ch.get("visitor") is Dictionary:
			ch["visitor"]["leaving"] = true  # a visitor set free goes home
	Chronicle.add(st, "kidnapping_end", {"family": str(inc["victim_family"]), "victim": chr, "outcome": outcome})
	var card: Dictionary = inc.get("card", {})
	if not card.is_empty():
		Notices.add(sim, str(card["family"]), Notices.INFO, "notice.life.kidnap_" + outcome, params(sim, inc), "")
	_close(sim, inc, outcome)


# --- Choosing ---------------------------------------------------------------------------------------------------

## {"type": "resolve_incident", "actor", "incident", "choice"[, "helpers": n]}: the actor is of the card's family.
static func order_resolve(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var inc := find(st, str(o.get("incident", "")))
	if inc.is_empty():
		return Orders.fail("unknown_incident")
	var card: Dictionary = inc.get("card", {})
	if card.is_empty() or str(st.characters[actor].get("family", "")) != str(card.get("family", "")):
		return Orders.fail("not_your_family")
	var choice := str(o.get("choice", ""))
	if not choice in (card.get("choices", []) as Array) or bool(card.get("answered", false)):
		return Orders.fail("unknown_choice")
	var why := choice_block(sim, inc, choice, actor, o)
	if why != "":
		return Orders.fail(why)
	_choose(sim, inc, choice, actor, o, "choice")
	return Orders.ok()


## Why `actor` cannot take `choice` now ("" if it can): too far to separate them, no gold for the ransom...
static func choice_block(sim: Sim, inc: Dictionary, choice: String, actor: String, o: Dictionary = {}) -> String:
	var st := sim.state
	var fam := str(st.characters.get(actor, {}).get("family", ""))
	match str(inc["def"]) + "|" + choice:
		"altercation|separate":
			var sd: Dictionary = def(sim, "altercation").get("separate", {})
			if str(inc["phase"]) != "fighting" and str(inc["phase"]) != "gathering":
				return "too_late"
			if Region.is_away(st, actor) or Life.dist(Life.tile_of(st, actor), inc["tile"]) > int(sd.get("range_tiles", 8)):
				return "too_far"
		"bandit_raid|defend":
			if Region.is_away(st, actor):
				return "away"
		"kidnapping|pay":
			if Money.gold(st, fam) < int(inc["ransom"]):
				return "not_enough_gold"
		"kidnapping|negotiate":
			if bool(inc.get("negotiated", false)):
				return "already_negotiated"
		"kidnapping|rescue":
			if bool(inc.get("rescued_tried", false)):
				return "already_tried"
			var cost := helper_cost(sim, inc, int(o.get("helpers", 2)))
			if Money.gold(st, fam) < cost:
				return "not_enough_gold"
	return ""


## The gold to hire `n` helpers (guards or mercenaries) for a rescue (helper_cost [min, max] each, drawn per incident).
static func helper_cost(sim: Sim, inc: Dictionary, n: int) -> int:
	var rc: Dictionary = def(sim, "kidnapping").get("rescue", {})
	var span: Array = rc.get("helper_cost", [15, 30])
	var each := Kin.randi_range(sim.state, "events_city|helper|%s" % inc["id"], int(span[0]), int(span[1]))
	return each * clampi(n, 0, int(rc.get("max_helpers", 3)))


static func _choose(sim: Sim, inc: Dictionary, choice: String, actor: String, o: Dictionary, by: String) -> void:
	var st := sim.state
	var card: Dictionary = inc.get("card", {})
	card["answered"] = true
	card["choice"] = choice
	card["by"] = by
	sim.events.append({"type": "incident_choice", "incident": str(inc["id"]), "def": str(inc["def"]), "choice": choice,
		"by": by, "actor": actor})
	if OS.is_debug_build():
		print("[Incidents] %s (%s): %s elige %s (%s)" % [inc["id"], inc["def"], actor, choice, by])
	match str(inc["def"]) + "|" + choice:
		"altercation|separate":
			var sd: Dictionary = def(sim, "altercation").get("separate", {})
			var best := 0
			for s: Variant in sd.get("stats", ["charisma", "martial"]):
				best = maxi(best, SkillCheck.stat(sim, actor, str(s)))
			var r := SkillCheck.roll(sim, "events_city|separate|%s" % inc["id"], best, int(sd.get("target", 6)))
			var fam := str(st.characters[actor].get("family", ""))
			if bool(r.get("success", false)):
				Reputation.change(sim, fam, int(sd.get("reputation", 3)), "separated_brawl")
				for c: Variant in inc["people"]:
					Emotions.change_relation(sim, actor, str(c), int(sd.get("relation", 5)), "separated_brawl")
				_end_fight(sim, inc, actor)
			else:
				for c: Variant in inc["people"]:
					Emotions.change_relation(sim, actor, str(c), int(sd.get("fail_relation", -3)), "separated_brawl")
				inc["separate_failed"] = true
		"bandit_raid|alarm":
			var span: Array = def(sim, "bandit_raid").get("alarm_minutes", [10, 20])
			inc["alarm_at"] = int(st.clock["minute"]) + Kin.randi_range(st, "events_city|alarm|%s" % inc["id"], int(span[0]), int(span[1]))
		"bandit_raid|defend":
			var fam := str(st.characters[actor].get("family", ""))
			var side: Array = [actor]
			for m: Variant in st.families[fam].get("members", []):
				var id := str(m)
				if id != actor and Kin.alive(st, id) and Kin.is_adult(sim, id) and not Region.is_away(st, id) \
						and Life.dist(Life.tile_of(st, id), inc["tile"]) <= 10:
					side.append(id)
			var blds: Array = st.buildings.keys()
			blds.sort()
			for bld: String in blds:
				if str(st.buildings[bld].get("owner", "")) != fam:
					continue
				for e: Variant in Staff.employees_of(st, bld):
					if not str(e) in side and Life.dist(Life.tile_of(st, str(e)), inc["tile"]) <= 10:
						side.append(str(e))
			var won := _fights(sim, side, inc["people"], str(inc["id"]) + "|defend", Life.FAMILY_BANDITS)
			if won:
				_repelled(sim, inc, "defenders")
			else:
				inc["defend_lost"] = true
		"kidnapping|pay":
			Money.change(sim, str(st.characters[actor].get("family", "")), -int(inc["ransom"]), Money.EVENTS, str(inc["id"]), "", actor)
			_free(sim, inc, "paid")
		"kidnapping|negotiate":
			var nd: Dictionary = def(sim, "kidnapping").get("negotiate", {})
			var r := SkillCheck.roll(sim, "events_city|negotiate|%s" % inc["id"], SkillCheck.stat(sim, actor, str(nd.get("stat", "rhetoric"))),
				int(nd.get("boss", 6)))
			inc["negotiated"] = true
			var m := float(nd.get("success_mult", 0.7)) if bool(r.get("success", false)) else float(nd.get("fail_mult", 1.5))
			inc["ransom"] = roundi(float(inc["ransom"]) * m)
			card["answered"] = false  # the card stays: now pay, rescue or let it be
			card["choices"] = (card["choices"] as Array).filter(func(c: Variant) -> bool: return str(c) != "negotiate")
			sim.events.append({"type": "incident_negotiated", "incident": str(inc["id"]), "ok": bool(r.get("success", false)),
				"ransom": int(inc["ransom"])})
		"kidnapping|rescue":
			var rc: Dictionary = def(sim, "kidnapping").get("rescue", {})
			var n := clampi(int(o.get("helpers", 2)), 0, int(rc.get("max_helpers", 3)))
			var fam := str(st.characters[actor].get("family", ""))
			var cost := helper_cost(sim, inc, n)
			if cost > 0:
				Money.change(sim, fam, -cost, Money.SERVICES, str(inc["id"]), "", actor)
			inc["rescued_tried"] = true
			var side: Array = [actor]
			var watch := Watch.guards(st)
			for i: int in n:
				side.append(watch[i % watch.size()] if not watch.is_empty() else actor)
			var fights_span: Array = rc.get("fights", [2, 3])
			var nb := Kin.randi_range(st, "events_city|rescue_n|%s" % inc["id"], int(fights_span[0]), int(fights_span[1]))
			var bandits: Array = []
			Life.service_family(st, Life.FAMILY_BANDITS, "family.bandits", {"primary": "#2a2a2a", "secondary": "#5a4a3a"})
			for i: int in nb:
				var bid := Life.add_person(sim, Life.FAMILY_BANDITS, "?", false, 30, rc.get("bandit_stats", {}), {}, [0, 0],
					{"bandit": {"incident": str(inc["id"]), "nest": true}})
				bandits.append(bid)
			var won := _fights(sim, side, bandits, str(inc["id"]) + "|rescue", Life.FAMILY_BANDITS)
			for bid: String in bandits:
				Life.remove_person(sim, bid)
			sim.events.append({"type": "incident_rescue", "incident": str(inc["id"]), "won": won, "helpers": n})
			if won:
				var vf := str(inc["victim_family"])
				if vf != fam:
					Reputation.change(sim, fam, int(def(sim, "kidnapping").get("rescue_reputation", 15)), "rescued")
					var head := Kin.head(st, vf)
					if head != "":
						Emotions.change_relation(sim, actor, head, int(def(sim, "kidnapping").get("rescue_relation", 30)), "rescued")
				if str(inc.get("route", "")) != "":
					book(st)["nests"][str(inc["route"])] = Clock.day(int(st.clock["minute"])) + Clock.days_per_year(sim.catalog.time)
				_free(sim, inc, "rescued")
			else:
				card["answered"] = false
				card["choices"] = (card["choices"] as Array).filter(func(c: Variant) -> bool: return str(c) != "rescue")
		"kidnapping|nothing":
			pass  # the ransom day decides (Incidents._others_pay)


# --- Helpers ------------------------------------------------------------------------------------------------------

static func _t(st: WorldState, chr: String) -> Dictionary:
	var ch: Dictionary = st.characters[chr]
	if not ch.get("town") is Dictionary:
		ch["town"] = {}
	return ch["town"]


## Walks `chr` to `tile` (true when it stands there).
static func _walk(sim: Sim, chr: String, tile: Array, now: int) -> bool:
	return TownLife._go_tile(sim, chr, _t(sim.state, chr), tile, now)


## A tile of the ring around `tile` for a watcher (by its id: they spread).
static func _ring(sim: Sim, tile: Array, chr: String) -> Array:
	var dirs := [[2, 0], [2, 2], [0, 2], [-2, 2], [-2, 0], [-2, -2], [0, -2], [2, -2]]
	var start := chr.get_slice("_", 1).to_int() % 8
	for i: int in 8:
		var dd: Array = dirs[(start + i) % 8]
		var c := int(tile[0]) + int(dd[0])
		var r := int(tile[1]) + int(dd[1])
		if TownLife._walkable(sim, c, r):
			return [c, r]
	return tile.duplicate()


# --- Queries for the UI ---------------------------------------------------------------------------------------------

## The parameters of the texts of incident `inc` (names, place, ransom...).
static func params(sim: Sim, inc: Dictionary) -> Dictionary:
	var st := sim.state
	var p := {"place": nest_key(sim, str(inc.get("route", ""))), "ransom": int(inc.get("ransom", 0)),
		"fine": int(inc.get("fine", 0)), "gold": int(inc.get("gold", 0)), "items": (inc.get("took", []) as Array).size()}
	var people: Array = inc.get("people", [])
	if str(inc["def"]) == "altercation" and people.size() == 2:
		p["a"] = str(st.characters.get(str(people[0]), {}).get("name", ""))
		p["b"] = str(st.characters.get(str(people[1]), {}).get("name", ""))
	if inc.has("victim"):
		p["name"] = str(st.characters.get(str(inc["victim"]), {}).get("name", ""))
		p["family"] = Rumors._family_name(st, str(inc.get("victim_family", "")))
	if inc.has("building"):
		p["building"] = str(inc["building"])
	p["band"] = people.size() if str(inc["def"]) == "bandit_raid" else 0
	return p


## The active incidents with a card for family `fam`, oldest first.
static func cards_for(st: WorldState, fam: String) -> Array:
	var out: Array = []
	for i: Dictionary in active(st):
		var c: Dictionary = i.get("card", {})
		if not c.is_empty() and str(c.get("family", "")) == fam and not bool(c.get("answered", false)):
			out.append(i)
	return out
