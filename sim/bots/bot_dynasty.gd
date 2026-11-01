class_name BotDynasty
extends RefCounted
## Bot "dynasty" (GDD 07 §7.2, 10/H8): plays the family only, with the player's orders. The suitor (the head while it is
## single and has no heir; later the heir once it is an adult and single) courts the single person with the most
## affinity (those without a job first): walks to them (move_to + the talk queued behind it, so the routine does not
## take it back before talking), talks once a day and proposes at 80. Then it waits for children, who grow, inherit and
## court in turn. It never works nor trades (the routine of the heir does).
## Measures (sim_runner reads measures()): wedding_day, first_child_days (wedding -> first child of the founder),
## inherited (1 if the family passed to an heir), inherit_day, generation_days (birth of the second head -> its first
## child; -1 if it did not happen), game_over (1 if the dynasty ended). Starts from dynasty_start (founder 40).

var fam: String = ""
var talked: Dictionary = {}       # suitor -> day of its last talk order
var sent: Dictionary = {}         # suitor -> minute it was sent walking (to wait for it)
var wedding_day: int = -1
var first_child_day: int = -1
var inherit_day: int = -1
var first_child_of: Dictionary = {}  # parent -> day of its first child


func orders(sim: Sim) -> Array:
	var st := sim.state
	if fam == "":
		fam = _player(st)
	_watch(sim)
	if fam == "" or not st.ending.is_empty():
		return []
	var suitor := _suitor(sim)
	if suitor == "":
		return []
	var today := Clock.day(int(st.clock["minute"]))
	if int(talked.get(suitor, -1)) == today:
		return []
	if not OrderQueue.is_free(sim, suitor) or OrderQueue.has_pending(sim, suitor):
		return []
	var target := _target(sim, suitor)
	if target == "":
		return []
	var min_aff := int(sim.catalog.family.get("courtship", {}).get("propose_min", 80))
	var act := "propose" if Courtship.affinity(st, suitor, target) >= min_aff else "court_talk"
	var status := Courtship.status(sim, suitor, target)
	if status == "":
		talked[suitor] = today
		return [{"type": act, "actor": suitor, "target": target}]
	if status != "too_far":
		return []
	var out: Array = []
	if str(st.characters[suitor].get("location", "")) != "":
		out.append({"type": "exit_building", "actor": suitor})
		out.append({"type": "move_to", "actor": suitor, "tile": Courtship.spot(st, target), "queued": true})
	else:
		out.append({"type": "move_to", "actor": suitor, "tile": Courtship.spot(st, target)})
	out.append({"type": act, "actor": suitor, "target": target, "queued": true})
	talked[suitor] = today
	return out


## Who courts now: the head while single and without heir, else the heir once adult, single and controlled.
func _suitor(sim: Sim) -> String:
	var st := sim.state
	var h := Kin.head(st, fam)
	if h != "" and Kin.is_single(st, h) and Kin.is_adult(sim, h) and Kin.heir(sim, fam) == "":
		return h
	var heir := Kin.heir(sim, fam) if h != "" else ""
	if heir != "" and Kin.is_adult(sim, heir) and Kin.is_single(st, heir) \
			and str(st.characters[heir].get("controlled_by", "")) == "human":
		return heir
	return ""


func _target(sim: Sim, suitor: String) -> String:
	var fallback := ""
	for c: Dictionary in Courtship.candidates(sim, suitor):
		if not str(c["status"]) in ["", "too_far"]:
			continue
		if fallback == "":
			fallback = str(c["character"])
		if sim.state.characters[str(c["character"])].get("job") == null:
			return str(c["character"])
	return fallback


## Reads the events of the last step.
func _watch(sim: Sim) -> void:
	var today := Clock.day(int(sim.state.clock["minute"]))
	for e: Dictionary in sim.events:
		if str(e.get("family", "")) != fam:
			continue
		match str(e["type"]):
			"wedding":
				if wedding_day < 0:
					wedding_day = today
			"child_born":
				if first_child_day < 0:
					first_child_day = today
				for p: String in [str(e.get("mother", "")), str(e.get("father", ""))]:
					if not first_child_of.has(p):
						first_child_of[p] = today
			"inheritance":
				if inherit_day < 0:
					inherit_day = today


func measures(sim: Sim) -> Dictionary:
	var st := sim.state
	var second := ""
	for e: Dictionary in st.chronicle:
		if str(e.get("kind", "")) == "inheritance" and str(e.get("family", "")) == fam:
			second = str(e.get("heir", ""))
			break
	if second == "" and fam != "":
		second = Kin.heir(sim, fam)
	var gen := -1
	if second != "" and first_child_of.has(second):
		gen = int(first_child_of[second]) - int(st.characters[second].get("birth_day", 0))
	return {"wedding_day": wedding_day, "first_child_days": first_child_day - wedding_day if first_child_day >= 0 else -1,
		"inherited": 1 if inherit_day >= 0 else 0, "inherit_day": inherit_day, "generation_days": gen,
		"game_over": 0 if st.ending.is_empty() else 1}


func _player(st: WorldState) -> String:
	var ids: Array = st.families.keys()
	ids.sort()
	for f: String in ids:
		if str(st.families[f].get("controlled_by", "")) == "human":
			return f
	return ""
