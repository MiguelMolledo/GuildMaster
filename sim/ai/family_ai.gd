class_name FamilyAI
extends RefCounted
## The family module of the AI families (GDD 4.21, H8) [provisional: 4.21 is not closed, this is the minimum]. Only
## families with controlled_by "ai" and an ai_profile (the rival smith today). Same orders as the player.
## - Need first: a single adult head without a valid heir courts. During court_phase (night, when RivalAI rests) it
##   visits once per night the candidate with the most affinity (Courtship.candidates): walks to their door (move_to),
##   talks (court_talk), proposes when the affinity reaches propose_min, and walks home (enter_building).
## - The other adult members (a spouse who moved in) go home to the family residence if they are elsewhere.
## Children are born by Births with the same rules as the player's. The heir is Kin.heir (the default rule).
## Memory in families[fam].ai_state.family: {night: int (the night of the last visit), target: chr, step: str}.
## Contract: docs/contratos/h8_familia.md.


## The orders of this minute (Sim.step, after RivalAI.orders), families sorted by id.
static func orders(sim: Sim) -> Array:
	var out: Array = []
	var st := sim.state
	var fams: Array = st.families.keys()
	fams.sort()
	for fam: String in fams:
		var f: Dictionary = st.families[fam]
		if str(f.get("controlled_by", "")) != "ai" or str(f.get("ai_profile", "")) == "":
			continue
		out.append_array(_family(sim, fam))
	return out


static func _family(sim: Sim, fam: String) -> Array:
	var st := sim.state
	var f: Dictionary = st.families[fam]
	var out: Array = []
	var h := Kin.head(st, fam)
	var home := Kin.residence(sim, fam)
	for m: Variant in f.get("members", []):
		var id := str(m)
		if id == h or not Kin.alive(st, id) or not Kin.is_adult(sim, id) or home == "":
			continue
		var ch: Dictionary = st.characters[id]
		if str(ch.get("location", "")) != home and OrderQueue.is_free(sim, id) and not OrderQueue.has_pending(sim, id):
			if str(ch.get("location", "")) != "":
				out.append({"type": "exit_building", "actor": id})
			out.append({"type": "enter_building", "actor": id, "building": home})
	if h == "" or not Kin.is_single(st, h) or not Kin.is_adult(sim, h) or Kin.heir(sim, fam) != "":
		return out
	var o := _court(sim, fam, h, home)
	if not o.is_empty():
		out.append(o)
	return out


static func _court(sim: Sim, fam: String, h: String, home: String) -> Dictionary:
	var st := sim.state
	var cfg: Dictionary = sim.catalog.family.get("ai_family", {})
	var now := int(st.clock["minute"])
	if Clock.phase(now, sim.catalog.time) != str(cfg.get("court_phase", "night")):
		return {}
	if Clock.day(now) < int(cfg.get("court_from_day", 0)):
		return {}
	if not OrderQueue.is_free(sim, h) or OrderQueue.has_pending(sim, h):
		return {}
	var f: Dictionary = st.families[fam]
	if not f.get("ai_state") is Dictionary:
		f["ai_state"] = {}
	if not f["ai_state"].get("family") is Dictionary:
		f["ai_state"]["family"] = {}
	var mem: Dictionary = f["ai_state"]["family"]
	var night := Clock.day(now - 600)  # 21:00-05:00 belong to the same night
	if int(mem.get("night", -1)) == night:
		if str(mem.get("step", "")) == "home" or str(st.characters[h].get("location", "")) == home:
			return {}
		mem["step"] = "home"
		return {"type": "enter_building", "actor": h, "building": home}
	var target := str(mem.get("target", ""))
	var best := ""  # the most affinity among those without a job (not to take a worker from anybody), else anyone
	var fallback := ""
	for c: Dictionary in Courtship.candidates(sim, h):
		if not str(c["status"]) in ["", "too_far", "already_talked"]:
			continue
		if fallback == "":
			fallback = str(c["character"])
		if st.characters[str(c["character"])].get("job") == null:
			best = str(c["character"])
			break
	if best == "":
		best = fallback
	if target == "" or Courtship._reason(sim, h, target, false) != "":
		target = best
	if target == "":
		return {}
	mem["target"] = target
	var min_aff := int(sim.catalog.family.get("courtship", {}).get("propose_min", 80))
	if Courtship.in_range(sim, h, target):
		mem["night"] = night
		mem["step"] = "talked"
		if Courtship.affinity(st, h, target) >= min_aff:
			return {"type": "propose", "actor": h, "target": target}
		if int((st.relationships.get(Ids.pair_key(h, target), {}) as Dictionary).get("talk_day", -1)) == Clock.day(now):
			return {}  # already talked today (a visit at the end of last night): home next minute
		return {"type": "court_talk", "actor": h, "target": target}
	if str(st.characters[h].get("location", "")) != "":
		return {"type": "exit_building", "actor": h}
	mem["step"] = "visit"
	return {"type": "move_to", "actor": h, "tile": Courtship.spot(st, target)}
