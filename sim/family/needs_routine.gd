class_name NeedsRoutine
extends RefCounted
## Sleep and food of the human family (GDD 4.2.6, 2026-11-07; figures: data/family.json needs.states, meal, routine).
## - Sleeping: at home at night without working (or eating), or with a sleep in course (Rendido, the AI going to rest).
##   Without a home, wherever it stands. The dinner comes with a night at home (needs.per_hour.hunger.sleep).
## - Eating: the order «eat» {actor, place: "home" | "tavern"}: an hour (meal.minutes) at home (free) or at the door of
##   a Taberna-Posada (meal.tavern_price gold to its owner family, +meal.tavern_social social); at the end +meal.hunger.
##   Leaving the place cancels it.
## - Rendido (Needs: rest at 0): drops what it does (stop_work, the queue cleared), goes home and sleeps; refuses the
##   orders from outside (exhausted) and work (Production.may_work) until rest is back at states.exhausted.until.
## - The Rutina of a controlled character (character.needs_routine, true when missing): at night home to sleep, at
##   midday home to eat when hungry. A manual order rules (Schedules.note_manual): the routine waits while the order
##   given during the want is being carried out, and a work cycle started before the want ends without repeating.
## Memory: character.vitals.act {kind: "eat" | "sleep", at, place, tile, until, until_rest}; character.routine
## {want, want_since, last_manual, lunch_day}. Only real orders through Sim.give.


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.family.get("needs", {})


## Whether the Rutina drives `chr`: a controlled character with needs_routine on (the default).
static func on(sim: Sim, chr: String) -> bool:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	return str(ch.get("controlled_by", "")) == "human" and bool(ch.get("needs_routine", true)) \
		and bool(cfg(sim).get("controlled", true))


## The meal or sleep in course ({} if none).
static func act(sim: Sim, chr: String) -> Dictionary:
	var v: Variant = sim.state.characters.get(chr, {}).get("vitals")
	if v is Dictionary and (v as Dictionary).get("act") is Dictionary:
		return v["act"]
	return {}


static func eating(sim: Sim, chr: String) -> bool:
	return str(act(sim, chr).get("kind", "")) == "eat"


## Asleep now: at home (or anywhere without a home, standing still) without working nor eating, and it is night, or a
## sleep is in course, or it is Rendido.
static func sleeping(sim: Sim, chr: String) -> bool:
	var st := sim.state
	var ch: Dictionary = st.characters.get(chr, {})
	if ch.is_empty() or eating(sim, chr):
		return false
	var loc := str(ch.get("location", ""))
	var home := Kin.home_of(sim, chr)
	if home != "":
		if loc != home or Production.job_zone(sim, chr, home) != "":
			return false
	elif loc != "" or not (ch.get("path", []) as Array).is_empty():
		return false
	if str(act(sim, chr).get("kind", "")) == "sleep" or Needs.is_exhausted(st, chr):
		return true
	return Clock.phase(int(st.clock["minute"]), sim.catalog.time) == "night"


## What the Rutina wants for `chr` now: "sleep" (night, unless its programmable routine works the night), "eat" (the
## lunch hours of the day with hunger under lunch_below, once a day) or "".
static func want(sim: Sim, chr: String, phase: String, now: int) -> String:
	if not on(sim, chr) or not Needs.tracked(sim, chr):
		return ""
	var ch: Dictionary = sim.state.characters[chr]
	if phase == "night":
		var sched: Variant = ch.get("schedule")
		if sched is Dictionary and str((sched as Dictionary).get("night", {}).get("action", "")) == "work":
			return ""
		return "sleep"
	if phase == "day":
		var rc: Dictionary = cfg(sim).get("routine", {})
		var h := Clock.hour(now)
		var r: Dictionary = ch.get("routine", {}) if ch.get("routine") is Dictionary else {}
		if h >= int(rc.get("lunch_from_hour", 12)) and h < int(rc.get("lunch_to_hour", 15)) \
				and int(Needs.of(sim, chr).get("hunger", 100)) < int(rc.get("lunch_below", 60)) \
				and int(r.get("lunch_day", -1)) != Clock.day(now):
			return "eat"
	return ""


## Schedules._step_one, every minute: keeps routine.want and the minute it started.
static func update_want(sim: Sim, chr: String, r: Dictionary, phase: String, now: int) -> void:
	var w := want(sim, chr, phase, now)
	if w != str(r.get("want", "")):
		if str(r.get("want", "")) == "sleep" and sleeping(sim, chr) and act(sim, chr).is_empty():
			var wake := int(cfg(sim).get("routine", {}).get("wake_at", 70))
			if int(Needs.of(sim, chr).get("rest", 100)) < wake:  # dawn, still tired: it sleeps on until wake_at
				Needs.vitals(sim, chr)["act"] = {"kind": "sleep", "at": Kin.home_of(sim, chr), "until_rest": wake,
					"since": now}
				if OS.is_debug_build():
					print("[NeedsRoutine] %s amanece cansado: sigue durmiendo hasta descanso %d" % [chr, wake])
		if w == "":
			r.erase("want")
			r.erase("want_since")
		else:
			r["want"] = w
			r["want_since"] = now
			sim.events.append({"type": "routine_wants", "character": chr, "want": w})
			if OS.is_debug_build():
				print("[NeedsRoutine] %s: la rutina quiere %s (%s)" % [chr, w, Routines._hhmm(now)])


## A manual order given since the want started rules over it while the character carries it out.
static func overridden(r: Dictionary) -> bool:
	return bool(r.get("manual", false)) and int(r.get("last_manual", -1)) >= int(r.get("want_since", 0))


## The want takes over a manual override older than it (the character is idle again: Schedules checks it).
static func supersedes(sim: Sim, chr: String, r: Dictionary) -> bool:
	return on(sim, chr) and str(r.get("want", "")) != "" and int(r.get("last_manual", -1)) < int(r.get("want_since", 0))


## For the bots that play like a player with the Rutina on: whether the needs have `chr` now (Rendido, a meal or a
## sleep in course, or a want of the Rutina the player has not overridden). A bot gives no orders to it meanwhile.
static func busy(sim: Sim, chr: String) -> bool:
	var st := sim.state
	if not st.characters.has(chr) or not Needs.tracked(sim, chr):
		return false
	if Needs.is_exhausted(st, chr) or not act(sim, chr).is_empty():
		return true
	var now := int(st.clock["minute"])
	var w := want(sim, chr, Clock.phase(now, sim.catalog.time), now)
	if w == "":
		return false
	var ch: Dictionary = st.characters[chr]
	var r: Dictionary = ch.get("routine", {}) if ch.get("routine") is Dictionary else {}
	var since := int(r.get("want_since", now)) if str(r.get("want", "")) == w else now
	return not (bool(r.get("manual", false)) and int(r.get("last_manual", -1)) >= since)


## The orders of a bot that plays like a player with the Rutina on: the ones for a character the needs have now
## (busy) are dropped, except management orders that do not move it (a trip does) and the ones the bot marks
## "manual": true (a deliberate order of the player over the Rutina, like the thief's burglary at night: it rules).
static func bot_filter(sim: Sim, orders: Array) -> Array:
	if orders.is_empty():
		return orders
	var out: Array = []
	var memo := {}
	for o: Variant in orders:
		if not o is Dictionary:
			continue
		var t := str(o.get("type", ""))
		var a0 := str(o.get("actor", ""))
		if t in ["", "wait"] or (Orders.is_management(t) and t != "travel") \
				or (bool(o.get("manual", false)) and not Needs.is_exhausted(sim.state, a0)):
			out.append(o)
			continue
		var a := str(o.get("actor", ""))
		if not memo.has(a):
			memo[a] = busy(sim, a)
		if not bool(memo[a]):
			out.append(o)
	return out


## The first minute of the night that is now or comes next (the night of today's season).
static func night_start(sim: Sim, now: int) -> int:
	var starts: Dictionary = sim.catalog.time["phase_starts"][Clock.season(now, sim.catalog.time)]
	var day0 := Clock.day(now) * Clock.MINUTES_PER_DAY
	var m := Clock.minute_of_day(now)
	if m < int(starts["dawn"]):
		return day0 - Clock.MINUTES_PER_DAY + int(starts["night"])  # after midnight: the night that began yesterday
	return day0 + int(starts["night"])


## Production._repeat_or_idle: why a family member's cycle does not repeat ("" = it may): exhausted, a want of the
## Rutina not overridden by a manual order (routine_sleep, routine_eat), or (with the Rutina on, before the night) a
## cycle of `cycle_minutes` that would end later than the night + routine.finish_minutes (routine_sleep).
static func stop_repeat(sim: Sim, actor: String, cycle_minutes: int = -1) -> String:
	var st := sim.state
	if not Needs.tracked(sim, actor):
		return ""
	if Needs.is_exhausted(st, actor):
		return "exhausted"
	var ch: Dictionary = st.characters[actor]
	var r: Dictionary = ch.get("routine", {}) if ch.get("routine") is Dictionary else {}
	var w := str(r.get("want", ""))
	if w != "" and on(sim, actor) and not overridden(r):
		return "routine_" + w
	if cycle_minutes > 0 and w == "" and on(sim, actor):  # a repeat is not a manual order
		var now := int(st.clock["minute"])
		var ph := Clock.phase(now, sim.catalog.time)
		if ph in ["day", "dusk"] and now + cycle_minutes > night_start(sim, now) \
				+ int(cfg(sim).get("routine", {}).get("finish_minutes", 60)):
			return "routine_sleep"
	return ""


## Sim.step: an order from outside for a Rendido character is refused (exhausted), except management ones that do
## not move it (a trip moves it).
static func refuses(sim: Sim, o: Dictionary) -> bool:
	var type := str(o.get("type", ""))
	if type in ["", "wait"] or not Needs.is_exhausted(sim.state, str(o.get("actor", ""))):
		return false
	return not Orders.is_management(type) or type == "travel"


## Rendido now (Needs._exhaustion): the queue is cleared, a meal ends, a cycle in course stops (D11 gives back its
## inputs). Schedules takes it home.
static func collapse(sim: Sim, chr: String) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	OrderQueue.clear_for(sim, chr)
	var v := Needs.vitals(sim, chr)
	v.erase("act")
	var loc := str(ch.get("location", ""))
	if loc != "" and Production.job_zone(sim, chr, loc) != "":
		sim.give({"type": "stop_work", "actor": chr})
	if ch.get("routine") is Dictionary:
		ch["routine"]["manual"] = false
		ch["routine"].erase("manual_until")
	if ch.get("ai") is Dictionary:
		ch["ai"]["doing"] = "sleep"
		ch["ai"]["why"] = "exhausted"
	if OS.is_debug_build():
		print("[NeedsRoutine] %s rendido: deja lo que hacía y va a casa a dormir" % chr)


## Schedules._step_one, before the manual override: what the needs impose. Rendido: home and sleep. A meal or sleep in
## course: kept (or ended). true = the minute is taken.
static func forced(sim: Sim, chr: String, r: Dictionary, now: int) -> bool:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	if not Needs.tracked(sim, chr):
		return false
	var a := act(sim, chr)
	var kind := str(a.get("kind", ""))
	if kind == "eat":
		if not _in_place(sim, chr, a):
			Needs.vitals(sim, chr).erase("act")
			sim.events.append({"type": "meal_cancelled", "character": chr})
			if OS.is_debug_build():
				print("[NeedsRoutine] %s deja de comer (se ha movido)" % chr)
		elif now >= int(a.get("until", 0)):
			_meal_done(sim, chr, a)
		else:
			return true
	elif kind == "sleep":
		var loc := str(ch.get("location", ""))
		var home := Kin.home_of(sim, chr)
		var working := loc != "" and Production.job_zone(sim, chr, loc) != ""
		if (home != "" and loc != home) or working:
			if not Needs.is_exhausted(st, chr):
				Needs.vitals(sim, chr).erase("act")  # sent somewhere else: the sleep ends
		elif int(Needs.of(sim, chr).get("rest", 0)) >= int(a.get("until_rest", 100)) and not Needs.is_exhausted(st, chr):
			Needs.vitals(sim, chr).erase("act")
			sim.events.append({"type": "woke_up", "character": chr})
			if OS.is_debug_build():
				print("[NeedsRoutine] %s se despierta (descanso=%d)" % [chr, int(Needs.of(sim, chr).get("rest", 0))])
		else:
			return true
	if Needs.is_exhausted(st, chr):
		_to_bed(sim, chr, r, now, int(cfg(sim).get("states", {}).get("exhausted", {}).get("until", 50)))
		return true
	return false


## The Rutina's want, when nothing manual rules (Schedules._step_one, after the manual override). true = taken.
static func drive(sim: Sim, chr: String, r: Dictionary, now: int) -> bool:
	var w := str(r.get("want", ""))
	if w == "" or not on(sim, chr) or overridden(r):
		return false
	var ch: Dictionary = sim.state.characters[chr]
	var sched: Variant = ch.get("schedule")
	var phase := Clock.phase(now, sim.catalog.time)
	if w == "sleep" and sched is Dictionary \
			and str((sched as Dictionary).get(phase, {}).get("action", "")) == "rest":
		return false  # its programmable routine already rests now (Schedules._rest: home, and stops at once)
	var loc := str(ch.get("location", ""))
	var zone := Production.job_zone(sim, chr, loc) if loc != "" else ""
	if zone != "":
		var job: Variant = sim.state.buildings[loc]["zones"][zone].get("job")
		if w == "sleep" and job is Dictionary and int(job.get("end", now)) - now \
				> int(cfg(sim).get("routine", {}).get("finish_minutes", 60)) and not (job as Dictionary).get("result") is Dictionary:
			sim.give({"type": "stop_work", "actor": chr})  # too long to finish: stopped, its inputs back (D11)
			if OS.is_debug_build():
				print("[NeedsRoutine] %s deja el ciclo a medias para dormir (quedaban %d min)" % [chr, int(job["end"]) - now])
			return true
		return true  # the cycle in course ends: Production does not repeat it (stop_repeat)
	if ch.get("ai") is Dictionary:
		ch["ai"]["doing"] = w
		ch["ai"]["why"] = "routine"
	match w:
		"sleep":
			var home := Kin.home_of(sim, chr)
			if home != "" and loc != home:
				Schedules._go(sim, chr, r, home, now)
			return true
		"eat":
			go_eat(sim, chr, r, now)
			if eating(sim, chr) or Kin.home_of(sim, chr) == "":
				r["lunch_day"] = Clock.day(now)
			return true
	return false


## Home and a meal there (the Rutina at midday, the AI with hunger). Refused (no home...): the lunch of the day is over.
static func go_eat(sim: Sim, chr: String, r: Dictionary, now: int) -> void:
	var home := Kin.home_of(sim, chr)
	if home == "":
		return
	var ch: Dictionary = sim.state.characters[chr]
	var loc := str(ch.get("location", ""))
	if loc != home:
		Schedules._go(sim, chr, r, home, now)
		return
	if Production.job_zone(sim, chr, home) != "":
		sim.give({"type": "stop_work", "actor": chr})
	if not eating(sim, chr):
		sim.give({"type": "eat", "actor": chr, "place": "home"})
		if not eating(sim, chr):
			r["lunch_day"] = Clock.day(now)


## Home and a sleep there until rest reaches `until_rest` (the AI with rest low; Rendido).
static func go_sleep(sim: Sim, chr: String, r: Dictionary, now: int, until_rest: int) -> void:
	_to_bed(sim, chr, r, now, until_rest)


static func _to_bed(sim: Sim, chr: String, r: Dictionary, now: int, until_rest: int) -> void:
	var ch: Dictionary = sim.state.characters[chr]
	var loc := str(ch.get("location", ""))
	var home := Kin.home_of(sim, chr)
	if loc != "" and Production.job_zone(sim, chr, loc) != "":
		sim.give({"type": "stop_work", "actor": chr})
	if home != "" and loc != home:
		Schedules._go(sim, chr, r, home, now)
		return
	var v := Needs.vitals(sim, chr)
	if not v.get("act") is Dictionary:
		v["act"] = {"kind": "sleep", "at": home, "until_rest": until_rest, "since": now}
		sim.events.append({"type": "fell_asleep", "character": chr})
		if OS.is_debug_build():
			print("[NeedsRoutine] %s se acuesta hasta descanso %d" % [chr, until_rest])


static func _in_place(sim: Sim, chr: String, a: Dictionary) -> bool:
	var ch: Dictionary = sim.state.characters[chr]
	if str(a.get("place", "")) == "tavern":
		var pos: Array = ch.get("position", [])
		var t: Array = a.get("tile", [])
		return str(ch.get("location", "")) == "" and (ch.get("path", []) as Array).is_empty() and pos.size() == 2 \
			and t.size() == 2 and int(pos[0]) == int(t[0]) and int(pos[1]) == int(t[1])
	return str(ch.get("location", "")) == str(a.get("at", "")) \
		and Production.job_zone(sim, chr, str(a.get("at", ""))) == ""


static func _meal_done(sim: Sim, chr: String, a: Dictionary) -> void:
	var m: Dictionary = cfg(sim).get("meal", {})
	Needs.change(sim, chr, "hunger", int(m.get("hunger", 60)))
	if str(a.get("place", "")) == "tavern":
		Needs.change(sim, chr, "social", int(m.get("tavern_social", 10)))
	Needs.vitals(sim, chr).erase("act")
	sim.events.append({"type": "meal_eaten", "character": chr, "place": str(a.get("place", ""))})
	if OS.is_debug_build():
		print("[NeedsRoutine] %s ha comido en %s (hambre=%d)" % [chr, a.get("place", ""),
			int(Needs.of(sim, chr).get("hunger", 0))])


## The Taberna-Posada whose door is within meal.tavern_tiles of `chr` on the map ("" if none), lowest id first.
static func tavern_near(sim: Sim, chr: String) -> String:
	var st := sim.state
	var ch: Dictionary = st.characters.get(chr, {})
	if ch.is_empty() or str(ch.get("location", "")) != "":
		return ""
	var pos: Array = ch.get("position", [0, 0])
	var lim := int(cfg(sim).get("meal", {}).get("tavern_tiles", 3))
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if not Inn.is_inn(sim, b):
			continue
		var door: Array = st.buildings[b].get("door", [])
		if door.size() == 2 and maxi(absi(int(door[0]) - int(pos[0])), absi(int(door[1]) - int(pos[1]))) <= lim:
			return b
	return ""


## The nearest Taberna-Posada to `chr` ("" if the map has none): where the UI sends it to eat.
static func nearest_tavern(sim: Sim, chr: String) -> String:
	var st := sim.state
	var me: Array = st.characters.get(chr, {}).get("position", [0, 0])
	var best := ""
	var best_d := 1000000
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if not Inn.is_inn(sim, b):
			continue
		var door: Array = st.buildings[b].get("door", [])
		if door.size() != 2:
			continue
		var d := absi(int(door[0]) - int(me[0])) + absi(int(door[1]) - int(me[1]))
		if d < best_d:
			best = b
			best_d = d
	return best


# --- Orders ----------------------------------------------------------------------------------------------------------

## {"type": "eat", "actor", "place": "home" | "tavern"}: an hour of meal at home (inside it) or at the door of a
## Taberna-Posada (within meal.tavern_tiles, paying meal.tavern_price). Refusals: not_family (not of the human family),
## working, no_home, not_home, not_at_tavern, not_enough_gold, bad_place.
static func order_eat(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not Kin.alive(st, actor):
		return Orders.fail("unknown_actor")
	if not Needs.tracked(sim, actor):
		return Orders.fail("not_family")
	var ch: Dictionary = st.characters[actor]
	var loc := str(ch.get("location", ""))
	if loc != "" and Production.job_zone(sim, actor, loc) != "":
		return Orders.fail("working")
	var m: Dictionary = cfg(sim).get("meal", {})
	var now := int(st.clock["minute"])
	var a := {"kind": "eat", "until": now + int(m.get("minutes", 60)), "since": now}
	match str(o.get("place", "home")):
		"home":
			var home := Kin.home_of(sim, actor)
			if home == "":
				return Orders.fail("no_home")
			if loc != home:
				return Orders.fail("not_home")
			a.merge({"place": "home", "at": home})
		"tavern":
			var bld := tavern_near(sim, actor)
			if bld == "" or not (ch.get("path", []) as Array).is_empty():
				return Orders.fail("not_at_tavern")
			var fam := str(ch.get("family", ""))
			var owner := str(st.buildings[bld].get("owner", ""))
			var price := int(m.get("tavern_price", 1))
			if owner != fam:
				if not Money.can_pay(st, fam, price):
					return Orders.fail("not_enough_gold")
				Money.change(sim, fam, -price, Money.FAMILY, "meal", bld, actor)
				if owner != "" and st.families.has(owner):
					Money.change(sim, owner, price, Money.SERVICES, "meal", bld, actor)
			var pos: Array = ch.get("position", [0, 0])
			a.merge({"place": "tavern", "at": bld, "tile": [int(pos[0]), int(pos[1])]})
		_:
			return Orders.fail("bad_place")
	Needs.vitals(sim, actor)["act"] = a
	if ch.get("ai") is Dictionary:
		ch["ai"]["doing"] = "eat"
	sim.events.append({"type": "meal_started", "character": actor, "place": str(a["place"]), "building": str(a["at"])})
	if OS.is_debug_build():
		print("[NeedsRoutine] %s empieza a comer en %s hasta %s" % [actor, a["at"], Routines._hhmm(int(a["until"]))])
	return Orders.ok()


## {"type": "set_needs_routine", "actor", "character", "on": bool}: switches the Rutina of a controlled member of the
## actor's family. Management order.
static func order_set_routine(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var who := str(o.get("character", actor))
	if not Kin.alive(st, actor):
		return Orders.fail("unknown_actor")
	if not Kin.alive(st, who) or str(st.characters[who].get("family", "")) != str(st.characters[actor].get("family", "")):
		return Orders.fail("not_family")
	if str(st.characters[who].get("controlled_by", "")) != "human":
		return Orders.fail("not_controlled")
	var v := bool(o.get("on", true))
	st.characters[who]["needs_routine"] = v
	if not v and st.characters[who].get("routine") is Dictionary:
		st.characters[who]["routine"].erase("want")
		st.characters[who]["routine"].erase("want_since")
	sim.events.append({"type": "needs_routine_changed", "actor": actor, "character": who, "on": v})
	if OS.is_debug_build():
		print("[NeedsRoutine] %s pone la Rutina de %s en %s" % [actor, who, v])
	return Orders.ok()
