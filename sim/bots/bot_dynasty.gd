class_name BotDynasty
extends RefCounted
## Bot "dynasty" (GDD 07 §7.2, 10/H8): plays the family only, with the player's orders. The suitor (the head while it is
## single and has no heir; later the heir once it is an adult and single) courts a single person who can still have
## children with it (without a job first, then the most affinity, then the youngest): walks to them (move_to; the
## routine waits its manual grace), talks once a day when in range and proposes at 80. Then it waits for children, who grow, inherit and
## court in turn. It never works nor trades (the routine of the heir does).
## Measures (sim_runner reads measures()): wedding_day, first_child_days (wedding -> first child of the founder),
## inherited (1 if the family passed to an heir), inherit_day, generation_days (birth of the second head -> its first
## child; -1 if it did not happen), game_over (1 if the dynasty ended). Starts from dynasty_start (founder 40).

var fam: String = ""
var talked: Dictionary = {}       # suitor -> day of its last talk order
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
	# Far: walk there; once in range (next minutes, the routine waits manual_grace_minutes) it talks. The talk is not
	# queued behind the walk: the courted person may have moved by then (a refused order).
	if str(st.characters[suitor].get("location", "")) != "":
		return [{"type": "exit_building", "actor": suitor},
			{"type": "move_to", "actor": suitor, "tile": Courtship.spot(st, target), "queued": true}]
	return [{"type": "move_to", "actor": suitor, "tile": Courtship.spot(st, target)}]


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


## Who to court: someone who can still have children (the woman of the couple <= mother_max_age − 5), without a job
## first, the most affinity (ties: the youngest); else anyone.
func _target(sim: Sim, suitor: String) -> String:
	var max_age := int(sim.catalog.family.get("children", {}).get("mother_max_age", 45)) - 5
	var suitor_age := Kin.age(sim, suitor)
	var female := bool(sim.state.characters[suitor].get("female", false))
	var best := ""
	var best_key := []
	var fallback := ""
	for c: Dictionary in Courtship.candidates(sim, suitor):
		if not str(c["status"]) in ["", "too_far"]:
			continue
		if fallback == "":
			fallback = str(c["character"])
		var mother_age := suitor_age if female else int(c["age"])
		if mother_age > max_age:
			continue
		var key := [0 if sim.state.characters[str(c["character"])].get("job") == null else 1, -int(c["affinity"]),
			int(c["age"])]
		if best == "" or _before(key, best_key):  # candidates come sorted by id: ties keep the first
			best = str(c["character"])
			best_key = key
	return best if best != "" else fallback


## Whether the int key `a` sorts before `b`.
static func _before(a: Array, b: Array) -> bool:
	for i: int in a.size():
		if int(a[i]) != int(b[i]):
			return int(a[i]) < int(b[i])
	return false


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
