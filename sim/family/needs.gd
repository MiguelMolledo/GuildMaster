class_name Needs
extends RefCounted
## Needs and morale (GDD 4.2.6; docs/contratos/h14_ia_familiar.md): hunger, rest, social and fun (ints 0-100) of the
## adults of the human family change every hour by what they are doing (at home without working, working, socialising,
## at leisure...) and by the events of the hour (talking, greeting, trading). Morale = their mean; below
## morale.productivity.full_at a family member works slower (Production divides the cycle by productivity()). Notices:
## exhausted, low morale, the workshop short of materials with nobody trading. No randomness. Figures:
## data/family.json needs, morale, kin_notices [provisional].


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
			ch["needs"][str(k)] = int(cfg(sim).get("start", 80))
	return ch["needs"]


## Morale 0-100: the mean of the needs.
static func morale(sim: Sim, chr: String) -> int:
	var n := of(sim, chr)
	if n.is_empty():
		return 100
	var sum := 0
	for k: Variant in ids(sim):
		sum += int(n.get(str(k), 0))
	return roundi(float(sum) / float(maxi(1, ids(sim).size())))


## The work rate of a family member: 1 with morale >= full_at, down to min_mult at morale 0.
static func productivity(sim: Sim, chr: String) -> float:
	var p: Dictionary = sim.catalog.family.get("morale", {}).get("productivity", {})
	var full := float(p.get("full_at", 40))
	var m := float(morale(sim, chr))
	if m >= full or full <= 0.0:
		return 1.0
	var lo := float(p.get("min_mult", 0.8))
	return lo + (1.0 - lo) * m / full


## The lowest need below `low` ("" if none): what the AI looks after first.
static func most_urgent(sim: Sim, chr: String, threshold: int = -1) -> String:
	var lim := threshold if threshold >= 0 else int(cfg(sim).get("low", 30))
	var n := of(sim, chr)
	var best := ""
	var best_v := 101
	for k: Variant in ids(sim):
		var v := int(n.get(str(k), 100))
		if v < lim and v < best_v:
			best = str(k)
			best_v = v
	return best


## Whose needs move: the living adults of the human families (not banished) whose day is run by the AI or a routine:
## family members with AI (the spouse...) and controlled ones with a routine. A controlled member without a routine
## (only manual orders, like the founder of a new game) has no order to eat or sleep: its needs stay still
## [provisional, like H8's founder without routine: it keeps the balance of H3-H11].
static func tracked(sim: Sim, chr: String) -> bool:
	var st := sim.state
	var ch: Dictionary = st.characters.get(chr, {})
	if ch.is_empty() or not bool(ch.get("alive", true)) or not Kin.is_adult(sim, chr) or Tribunal.is_banished(st, chr):
		return false
	if str(st.families.get(str(ch.get("family", "")), {}).get("controlled_by", "")) != "human":
		return false
	return str(ch.get("controlled_by", "")) != "human" or ch.get("schedule") is Dictionary


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


## What `chr` is doing this hour for its needs: home (at home, not working), work / work_night, social, leisure, base.
static func situation(sim: Sim, chr: String) -> String:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	var loc := str(ch.get("location", ""))
	if loc != "" and Production.job_zone(sim, chr, loc) != "":
		return "work_night" if Clock.phase(int(st.clock["minute"]), sim.catalog.time) == "night" else "work"
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
	for k: Variant in ids(sim):
		var rates: Dictionary = per.get(str(k), {})
		var d := int(rates.get("base", 0))
		if rates.has(sit):
			d = int(rates[sit])
		elif sit == "work_night" and rates.has("work"):
			d = int(rates["work"])
		change(sim, chr, str(k), d)
	sim.events.append({"type": "needs_changed", "character": chr, "situation": sit})
	var n := of(sim, chr)
	var critical := int(cfg(sim).get("critical", 15))
	var worst := ""
	for k: Variant in ids(sim):
		if int(n.get(str(k), 100)) <= critical and (worst == "" or int(n[str(k)]) < int(n[worst])):
			worst = str(k)
	var params := {"name": str(sim.state.characters[chr].get("name", ""))}
	if worst != "":
		params["need"] = worst
		_notice(sim, chr, "kin_exhausted", params)
	elif morale(sim, chr) <= int(sim.catalog.family.get("morale", {}).get("low", 30)):
		params["morale"] = morale(sim, chr)
		_notice(sim, chr, "kin_low_morale", params)


## A notice of type `kind` about `chr` to its family, at most once per kin_notices.cooldown_days (memory in ai.notified).
static func _notice(sim: Sim, chr: String, kind: String, params: Dictionary) -> void:
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
	Notices.add(sim, str(ch.get("family", "")), Notices.WARNING, "notice." + kind, params, chr)
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


## The panel: {needs, morale, productivity, situation}.
static func view(sim: Sim, chr: String) -> Dictionary:
	if not sim.state.characters.has(chr):
		return {}
	return {"needs": of(sim, chr).duplicate(), "morale": morale(sim, chr), "productivity": productivity(sim, chr),
		"situation": situation(sim, chr) if tracked(sim, chr) else ""}
