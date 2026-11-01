class_name Dynasty
extends RefCounted
## Dynasty score, goals and the end-of-game summary (GDD 4.17). The score comes out of the chronicle only
## (data/score.json: points per kind of fact, by value for titles/offices/sentences, and the highest wealth_peak): it can
## be recomputed and audited. Every dawn the family's wealth (gold + build cost of its buildings + gold cost of their
## finished upgrades) writes a wealth_peak when it beats the last one by `step`; the goals of data/goals.json are checked
## (goal_done in the chronicle, notice, family.goals_done). Contract: docs/contratos/h8_familia.md.


## At dawn, after Births: wealth peaks and goals of every family that plays (human or with an AI profile).
static func step(sim: Sim) -> void:
	if not Ledger.is_dawn(sim):
		return
	var fams: Array = sim.state.families.keys()
	fams.sort()
	for fam: String in fams:
		var f: Dictionary = sim.state.families[fam]
		if str(f.get("controlled_by", "")) != "human" and str(f.get("ai_profile", "")) == "":
			continue
		record_peak(sim, fam)
		check_goals(sim, fam)


## Gold + the build cost of the family's buildings + the gold cost of their finished upgrades.
static func wealth(sim: Sim, fam: String) -> int:
	var total := Money.gold(sim.state, fam)
	for b: String in sim.state.buildings:
		var bld: Dictionary = sim.state.buildings[b]
		if str(bld.get("owner", "")) != fam:
			continue
		total += int(sim.catalog.buildings().get(str(bld.get("type", "")), {}).get("build_cost", 0))
		for u: Variant in bld.get("upgrades", []):
			total += int(sim.catalog.upgrade(str(u)).get("cost", {}).get("gold", 0))
	return total


## A wealth_peak in the chronicle when the family's wealth beats its last peak by `step` (the first one always).
static func record_peak(sim: Sim, fam: String) -> void:
	var w := wealth(sim, fam)
	var last := peak(sim.state, fam)
	var step := int(sim.catalog.score.get("wealth", {}).get("step", 100))
	if w >= last + step or (last == 0 and w > 0 and not _has_peak(sim.state, fam)):
		Chronicle.add(sim.state, "wealth_peak", {"family": fam, "value": w})


static func _has_peak(st: WorldState, fam: String) -> bool:
	for e: Dictionary in st.chronicle:
		if str(e.get("kind", "")) == "wealth_peak" and str(e.get("family", "")) == fam:
			return true
	return false


## The highest wealth_peak of the family in the chronicle (0 if none).
static func peak(st: WorldState, fam: String) -> int:
	var best := 0
	for e: Dictionary in st.chronicle:
		if str(e.get("kind", "")) == "wealth_peak" and str(e.get("family", "")) == fam:
			best = maxi(best, int(e.get("value", 0)))
	return best


## The goals of data/goals.json the family meets now and has not met before: chronicle goal_done (+ notice).
static func check_goals(sim: Sim, fam: String) -> void:
	var f: Dictionary = sim.state.families.get(fam, {})
	if f.is_empty():
		return
	if not f.get("goals_done") is Array:
		f["goals_done"] = []
	for g: Dictionary in sim.catalog.goals.get("goals", []):
		var id := str(g.get("id", ""))
		if id in (f["goals_done"] as Array) or not _meets(sim, fam, g):
			continue
		(f["goals_done"] as Array).append(id)
		Chronicle.add(sim.state, "goal_done", {"family": fam, "goal": id})
		sim.events.append({"type": "goal_done", "family": fam, "goal": id})
		if str(f.get("controlled_by", "")) == "human":
			Notices.add(sim, fam, "info", "notice.goal_done", {"goal": id})
		if OS.is_debug_build():
			print("[Dynasty] %s cumple la meta %s" % [fam, id])


static func _meets(sim: Sim, fam: String, g: Dictionary) -> bool:
	match str(g.get("kind", "")):
		"generation":
			return int(sim.state.families[fam].get("generation", 1)) >= int(g.get("min", 5))
		"wealth":
			return wealth(sim, fam) >= int(g.get("min", 0))
		"office":
			return false  # H10: offices do not exist yet
	return false


## The score of a family from the chronicle: {total, by_kind: {kind: points}, facts: {kind: count}, peak}.
static func score(sim: Sim, fam: String) -> Dictionary:
	var cfg: Dictionary = sim.catalog.score
	var points: Dictionary = cfg.get("points", {})
	var by_value: Dictionary = cfg.get("by_value", {})
	var by_kind := {}
	var facts := {}
	for e: Dictionary in sim.state.chronicle:
		if str(e.get("family", "")) != fam:
			continue
		var kind := str(e.get("kind", ""))
		var p := 0
		var counts := false
		if points.has(kind):
			p = int(points[kind])
			counts = true
		elif by_value.has(kind):
			var bv: Dictionary = by_value[kind]
			var v := str(e.get(str(bv.get("field", "")), "")) if str(bv.get("field", "")) != "" else ""
			p = int(bv.get("points", {}).get(v, 0))
			counts = true
		if counts:
			by_kind[kind] = int(by_kind.get(kind, 0)) + p
			facts[kind] = int(facts.get(kind, 0)) + 1
	var pk := peak(sim.state, fam)
	var wp := floori(float(pk) / maxf(1.0, float(cfg.get("wealth", {}).get("gold_per_point", 100))))
	if wp > 0:
		by_kind["wealth_peak"] = wp
		facts["wealth_peak"] = 1
	var total := 0
	for k: String in by_kind:
		total += int(by_kind[k])
	return {"total": total, "by_kind": by_kind, "facts": facts, "peak": pk}


## The end-of-game summary (GDD 4.17): generations, the heads with their dates, the goals met, the highest wealth and
## the score. {family, name, generation, heads: [{character, name, from_day, to_day}], goals_done, peak, score}.
static func summary(sim: Sim, fam: String) -> Dictionary:
	var st := sim.state
	var f: Dictionary = st.families.get(fam, {})
	var heads: Array = []
	var founder := str(f.get("founder", ""))
	var since := 0
	var cur := founder
	for e: Dictionary in st.chronicle:
		if str(e.get("family", "")) == fam and str(e.get("kind", "")) == "inheritance":
			var d := Clock.day(int(e.get("minute", 0)))
			heads.append({"character": cur, "name": str(st.characters.get(cur, {}).get("name", "")), "from_day": since,
				"to_day": d})
			cur = str(e.get("heir", ""))
			since = d
	if cur != "":
		var ch: Dictionary = st.characters.get(cur, {})
		heads.append({"character": cur, "name": str(ch.get("name", "")), "from_day": since,
			"to_day": int(ch.get("death_day", -1))})
	return {"family": fam, "name": str(f.get("name", "")), "generation": int(f.get("generation", 1)), "heads": heads,
		"goals_done": (f.get("goals_done", []) as Array).duplicate(), "peak": peak(st, fam), "score": score(sim, fam)}


## The goals panel: [{id, name_key, kind, done, since}].
static func goals_view(sim: Sim, fam: String) -> Array:
	var done: Array = sim.state.families.get(fam, {}).get("goals_done", [])
	var out: Array = []
	for g: Dictionary in sim.catalog.goals.get("goals", []):
		out.append({"id": str(g["id"]), "name_key": str(g.get("name_key", "")), "kind": str(g.get("kind", "")),
			"done": str(g["id"]) in done, "since": str(g.get("since", ""))})
	return out
