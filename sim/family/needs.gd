class_name Needs
extends RefCounted
## Needs and morale (GDD 4.2.6; docs/contratos/h14_ia_familiar.md): hunger, rest, social and fun (ints 0-100) of the
## adults of the human family change every hour by what they are doing (at home without working, working, socialising,
## at leisure...) and by the events of the hour (talking, greeting, trading). Morale = their mean; below
## morale.productivity.full_at a family member works slower (Production divides the cycle by productivity()). Notices:
## exhausted, low morale, the workshop short of materials with nobody trading. No randomness. Figures:
## data/family.json needs, morale, kin_notices [provisional].
## Sleep and food (2026-11-07, GDD 4.2.6): the controlled characters move only hunger and rest (controlled_ids); rest
## recovers only sleeping (at home at night, or a sleep in course), hunger with the dinner of a night at home or a meal
## (NeedsRoutine). States: tired and hungry slow the work down (work_mult), exhausted (rest 0) stops everything until
## rest is back at states.exhausted.until (NeedsRoutine drives it home to sleep). Memory: character.vitals
## {exhausted: bool, act: {...}} (absent in old games: not exhausted, nothing in course).


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.family.get("needs", {})


static func ids(sim: Sim) -> Array:
	return cfg(sim).get("ids", ["hunger", "rest", "social", "fun"])


## The needs of `chr` (created at needs.start the first time: births and newcomers have none yet).
static func of(sim: Sim, chr: String) -> Dictionary:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty():
		return {}
	if not ch.get("needs") is Dictionary or (ch["needs"] as Dictionary).is_empty():
		ch["needs"] = {}
		for k: Variant in ids(sim):
			ch["needs"][str(k)] = start_value(sim, str(k))
	return ch["needs"]


## The value a need starts at (needs.start_of, else needs.start).
static func start_value(sim: Sim, need: String) -> int:
	return int(cfg(sim).get("start_of", {}).get(need, cfg(sim).get("start", 80)))


## Whether `chr` is a character the player controls (controlled_by "human").
static func is_controlled(sim: Sim, chr: String) -> bool:
	return str(sim.state.characters.get(chr, {}).get("controlled_by", "")) == "human"


## The needs that move for `chr`: hunger and rest for a controlled character (controlled_ids), all of them for the AI.
static func moving_ids(sim: Sim, chr: String) -> Array:
	if is_controlled(sim, chr):
		return cfg(sim).get("controlled_ids", ["hunger", "rest"])
	return ids(sim)


## character.vitals (created empty when missing).
static func vitals(sim: Sim, chr: String) -> Dictionary:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty():
		return {}
	if not ch.get("vitals") is Dictionary:
		ch["vitals"] = {}
	return ch["vitals"]


## Rendido: rest reached states.exhausted.at and is not yet back at its until.
static func is_exhausted(st: WorldState, chr: String) -> bool:
	var v: Variant = st.characters.get(chr, {}).get("vitals")
	return v is Dictionary and bool((v as Dictionary).get("exhausted", false))


## The states of `chr` now, in this order: exhausted, tired, hungry (only the ones that apply; [] if not tracked).
static func states(sim: Sim, chr: String) -> Array:
	if not tracked(sim, chr):
		return []
	var out: Array = []
	var sc: Dictionary = cfg(sim).get("states", {})
	var n := of(sim, chr)
	if is_exhausted(sim.state, chr):
		out.append("exhausted")
	for s: String in ["tired", "hungry"]:
		var d: Dictionary = sc.get(s, {})
		if not d.is_empty() and int(n.get(str(d.get("need", "")), 100)) < int(d.get("below", 0)):
			out.append(s)
	return out


## Morale 0-100: the mean of the needs.
static func morale(sim: Sim, chr: String) -> int:
	var n := of(sim, chr)
	if n.is_empty():
		return 100
	var sum := 0
	var mv := moving_ids(sim, chr)
	for k: Variant in mv:
		sum += int(n.get(str(k), 0))
	return roundi(float(sum) / float(maxi(1, mv.size())))


## The work rate of a family member: the states' work_mult (tired, hungry) and, for the ones run by the AI, morale:
## 1 with morale >= full_at, down to min_mult at morale 0 (a controlled character has no morale penalty: only its
## hunger and rest count).
static func productivity(sim: Sim, chr: String) -> float:
	var mult := 1.0
	var sc: Dictionary = cfg(sim).get("states", {})
	for s: Variant in states(sim, chr):
		mult *= float(sc.get(str(s), {}).get("work_mult", 1.0))
	if is_controlled(sim, chr):
		return mult
	var p: Dictionary = sim.catalog.family.get("morale", {}).get("productivity", {})
	var full := float(p.get("full_at", 40))
	var m := float(morale(sim, chr))
	if m >= full or full <= 0.0:
		return mult
	var lo := float(p.get("min_mult", 0.8))
	return mult * (lo + (1.0 - lo) * m / full)


## The lowest need below `low` ("" if none): what the AI looks after first.
static func most_urgent(sim: Sim, chr: String, threshold: int = -1) -> String:
	var lim := threshold if threshold >= 0 else int(cfg(sim).get("low", 30))
	var n := of(sim, chr)
	var best := ""
	var best_v := 101
	for k: Variant in moving_ids(sim, chr):
		var v := int(n.get(str(k), 100))
		if v < lim and v < best_v:
			best = str(k)
			best_v = v
	return best


## Whose needs move: the living adults of the human families (not banished, not away): family members with AI (the
## spouse...) and the controlled ones (2026-11-07: also without a programmable routine, like the founder of a new
## game: they sleep and eat with the Rutina, NeedsRoutine).
static func tracked(sim: Sim, chr: String) -> bool:
	var st := sim.state
	var ch: Dictionary = st.characters.get(chr, {})
	if ch.is_empty() or not bool(ch.get("alive", true)) or not Kin.is_adult(sim, chr) or Tribunal.is_banished(st, chr) \
			or Region.is_away(st, chr):  # viajes: away (a trip, a caravan): no needs while off the map
		return false
	if str(st.families.get(str(ch.get("family", "")), {}).get("controlled_by", "")) != "human":
		return false
	if not bool(cfg(sim).get("controlled", true)):  # the H14 rule (tests of other systems: Pins.no_player_needs)
		return str(ch.get("controlled_by", "")) != "human" or ch.get("schedule") is Dictionary
	return true


static func change(sim: Sim, chr: String, need: String, amount: int) -> void:
	var n := of(sim, chr)
	if n.is_empty() or amount == 0:
		return
	n[need] = clampi(int(n.get(need, 0)) + amount, 0, 100)


## The events of the step (talking, greeting, trading) and, at every hour change, the hourly change of each need and
## the notices.
static func step(sim: Sim) -> void:
	var ev: Dictionary = cfg(sim).get("events", {})
	var hour := false
	var dawn := false
	for e: Dictionary in sim.events:
		var type := str(e.get("type", ""))
		if type == "hour_changed":
			hour = true
		elif type == "phase_changed" and str(e.get("phase", "")) == "dawn":
			dawn = true
		if not ev.has(type):
			continue
		var who: Array = []
		match type:
			"greeted":
				who = [str(e.get("a", "")), str(e.get("b", ""))]
			"npc_action":
				if bool(e.get("ok", true)) and str(e.get("action", "")) in ["talk", "gift", "flatter"]:
					who = [str(e.get("actor", ""))]
			_:
				who = [str(e.get("actor", ""))]
		for c: String in who:
			if tracked(sim, c):
				for k: String in ev[type]:
					change(sim, c, k, int(ev[type][k]))
	if not hour:
		return
	var st := sim.state
	var ids_c: Array = st.characters.keys()
	ids_c.sort()
	for id: Variant in ids_c:
		var c := str(id)
		if tracked(sim, c):
			_hour(sim, c)
	if dawn:
		_workshop_notices(sim)


## What `chr` is doing this hour for its needs: work / work_night, eat (a meal in course), sleep (NeedsRoutine.sleeping),
## social, leisure, home (at home, awake, not working), base.
static func situation(sim: Sim, chr: String) -> String:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	var loc := str(ch.get("location", ""))
	if loc != "" and Production.job_zone(sim, chr, loc) != "":
		return "work_night" if Clock.phase(int(st.clock["minute"]), sim.catalog.time) == "night" else "work"
	if NeedsRoutine.eating(sim, chr):
		return "eat"
	if NeedsRoutine.sleeping(sim, chr):
		return "sleep"
	var doing := str(ch.get("ai", {}).get("doing", "")) if ch.get("ai") is Dictionary else ""
	if doing == "socialize":
		return "social"
	if doing == "leisure" and str(ch.get("ai", {}).get("leisure_at", "")) != "":
		return "leisure"
	if loc != "" and loc == Kin.home_of(sim, chr):
		return "home"
	return "base"


static func _hour(sim: Sim, chr: String) -> void:
	var sit := situation(sim, chr)
	var per: Dictionary = cfg(sim).get("per_hour", {})
	for k: Variant in moving_ids(sim, chr):
		var rates: Dictionary = per.get(str(k), {})
		var d := int(rates.get("base", 0))
		if rates.has(sit):
			d = int(rates[sit])
		elif sit == "work_night" and rates.has("work"):
			d = int(rates["work"])
		change(sim, chr, str(k), d)
	sim.events.append({"type": "needs_changed", "character": chr, "situation": sit})
	if OS.is_debug_build():
		print("[Needs] %s hora en %s: %s" % [chr, sit, of(sim, chr)])
	_exhaustion(sim, chr)
	var n := of(sim, chr)
	var params := {"name": str(sim.state.characters[chr].get("name", ""))}
	if is_controlled(sim, chr):
		_controlled_notices(sim, chr, n, params)
		return
	var critical := int(cfg(sim).get("critical", 15))
	var worst := ""
	for k: Variant in ids(sim):
		if int(n.get(str(k), 100)) <= critical and (worst == "" or int(n[str(k)]) < int(n[worst])):
			worst = str(k)
	if worst != "":
		params["need"] = worst
		_notice(sim, chr, "kin_exhausted", params)
	elif morale(sim, chr) <= int(sim.catalog.family.get("morale", {}).get("low", 30)):
		params["morale"] = morale(sim, chr)
		_notice(sim, chr, "kin_low_morale", params)


## Rendido: rest at states.exhausted.at sets it (the character drops what it does, NeedsRoutine takes it home to
## sleep); back at until, it ends.
static func _exhaustion(sim: Sim, chr: String) -> void:
	var d: Dictionary = cfg(sim).get("states", {}).get("exhausted", {})
	if d.is_empty():
		return
	var v := vitals(sim, chr)
	var rest := int(of(sim, chr).get(str(d.get("need", "rest")), 100))
	var params := {"name": str(sim.state.characters[chr].get("name", ""))}
	if not bool(v.get("exhausted", false)) and rest <= int(d.get("at", 0)):
		v["exhausted"] = true
		sim.events.append({"type": "exhausted", "character": chr})
		_notice(sim, chr, "exhausted", params, Notices.URGENT)
		NeedsRoutine.collapse(sim, chr)
	elif bool(v.get("exhausted", false)) and rest >= int(d.get("until", 50)):
		v["exhausted"] = false
		sim.events.append({"type": "rested", "character": chr})
		if OS.is_debug_build():
			print("[Needs] %s ya no está rendido (descanso=%d)" % [chr, rest])


## The notices of a controlled character (once a day each): rest soon (warn), tired, hungry.
static func _controlled_notices(sim: Sim, chr: String, n: Dictionary, params: Dictionary) -> void:
	var sc: Dictionary = cfg(sim).get("states", {})
	var warn: Dictionary = cfg(sim).get("warn", {})
	var rest := int(n.get("rest", 100))
	if is_exhausted(sim.state, chr):
		return
	if rest < int(sc.get("tired", {}).get("below", 30)):
		_notice(sim, chr, "tired", params)
	elif rest < int(warn.get("rest", 40)):
		_notice(sim, chr, "rest_low", params)
	var hunger := int(n.get("hunger", 100))
	if hunger < int(sc.get("hungry", {}).get("below", 30)):
		_notice(sim, chr, "hungry", params)
	elif hunger < int(warn.get("hunger", 40)):
		_notice(sim, chr, "hunger_low", params)


## A notice of type `kind` about `chr` to its family, at most once per kin_notices.cooldown_days (memory in ai.notified).
static func _notice(sim: Sim, chr: String, kind: String, params: Dictionary, severity: String = Notices.WARNING) -> void:
	var ch: Dictionary = sim.state.characters[chr]
	if not ch.get("ai") is Dictionary:
		ch["ai"] = {}
	if not ch["ai"].get("notified") is Dictionary:
		ch["ai"]["notified"] = {}
	var today := Clock.day(int(sim.state.clock["minute"]))
	var cd := int(sim.catalog.family.get("kin_notices", {}).get("cooldown_days", 1))
	if today < int(ch["ai"]["notified"].get(kind, -100000)) + cd:
		return
	ch["ai"]["notified"][kind] = today
	Notices.add(sim, str(ch.get("family", "")), severity, "notice." + kind, params, chr)
	if OS.is_debug_build():
		print("[Needs] aviso %s de %s %s" % [kind, chr, params])


## At dawn: a human family whose workshop lacks a raw material of its recipes and has nobody trading gets a notice.
static func _workshop_notices(sim: Sim) -> void:
	var st := sim.state
	var fams: Array = st.families.keys()
	fams.sort()
	for fam: String in fams:
		if str(st.families[fam].get("controlled_by", "")) != "human":
			continue
		var bld := Kin.workplace(sim, fam)
		if bld == "":
			continue
		var short := Directives.shortages(sim, bld)
		if short.is_empty():
			continue
		var trading := false
		for m: Variant in st.families[fam].get("members", []):
			if tracked(sim, str(m)) and Directives.is_ready_listed(sim, str(m), "trade"):
				trading = true
		var head := Kin.head(st, fam)
		if not trading and head != "" and Kin.alive(st, head):
			_notice(sim, head, "forge_short", {"building": bld, "item": str(short[0])})


## The panel: {needs, moving (the ids that count for it), morale, productivity, situation, states, routine (the Rutina
## of a controlled character: on/off), act (a meal or sleep in course: kind)}.
static func view(sim: Sim, chr: String) -> Dictionary:
	if not sim.state.characters.has(chr):
		return {}
	var t := tracked(sim, chr)
	return {"needs": of(sim, chr).duplicate(), "moving": moving_ids(sim, chr).duplicate(), "morale": morale(sim, chr),
		"productivity": productivity(sim, chr), "situation": situation(sim, chr) if t else "",
		"states": states(sim, chr), "tracked": t, "routine": NeedsRoutine.on(sim, chr),
		"act": str(NeedsRoutine.act(sim, chr).get("kind", ""))}
