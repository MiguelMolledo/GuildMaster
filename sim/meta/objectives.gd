class_name Objectives
extends RefCounted
## The start objectives (GDD 4.16): a chain per family, read from data/objectives/ (each one with its condition as
## data: event and parameters). Watches the events of the step; each one done goes to the notices log.
## Owner: subgrim «cuentas». Contract: docs/contratos/h3_mercado.md.
##
## state.objectives[fam] = {chain: [obj_id], index: int (the current one; chain.size() when all are done),
##                          done: [obj_id], have: [int per condition of the current one]}.
## A condition {event, match, count} counts the events of type `event` of the family (the event's `family`, or its
## `actor`'s family) whose fields match `match` (a plain value is equality; {"gte"|"lte"|"ne": v} compares).
## H5 (GDD 4.16, «no bloquean nada»): an objective tied to a scripted contract (a condition matching `script`) fails
## when that contract can no longer be delivered by the family — it expired or was abandoned, or another family took
## it —: event objective_failed {family, objective, reason: expired | abandoned | gone}, a warning notice
## (notice.objective_failed) and the chain goes on to the next one. A failed objective is not added to `done`.


## A fresh chain for `fam` (NewGame.from_start).
static func start(state: WorldState, catalog: Catalog, fam: String, chain: Array) -> void:
	var ids: Array = []
	for id: Variant in chain:
		ids.append(str(id))
	state.objectives[fam] = {"chain": ids, "index": 0, "done": [], "have": _zeros(catalog, ids, 0)}


## Reads sim.events of this step (it runs after every system that emits) and advances the chains.
static func step(sim: Sim) -> void:
	var st := sim.state
	if st.objectives.is_empty() or sim.events.is_empty():
		return
	var n := sim.events.size()  # what this step adds (notices, objective_done) is not read again
	var fams: Array = st.objectives.keys()
	fams.sort()
	for fam: String in fams:
		var prog: Dictionary = st.objectives[fam]
		var chain: Array = prog.get("chain", [])
		if int(prog.get("index", 0)) >= chain.size():
			continue
		var failed_reason := ""   # why a contract of the family failed this step (the likely cause of a loss)
		for i: int in n:
			var e: Dictionary = sim.events[i]
			if _family_of_event(st, e) != fam:
				continue
			if str(e.get("type", "")) == "contract_failed":
				failed_reason = str(e.get("reason", ""))
			_count(sim, fam, e)
		_drop_lost(sim, fam, failed_reason)


## {} | {current: obj_id | "", done: [obj_id], progress: [{have, need}]} of `fam`, for the HUD.
static func view(sim: Sim, fam: String) -> Dictionary:
	var prog: Dictionary = sim.state.objectives.get(fam, {})
	if prog.is_empty():
		return {}
	var chain: Array = prog.get("chain", [])
	var idx := int(prog.get("index", 0))
	var current := str(chain[idx]) if idx < chain.size() else ""
	var progress: Array = []
	if current != "":
		var conds: Array = sim.catalog.objectives().get(current, {}).get("conditions", [])
		var have: Array = prog.get("have", [])
		for c: int in conds.size():
			progress.append({"have": int(have[c]) if c < have.size() else 0, "need": int(conds[c].get("count", 1))})
	return {"current": current, "done": (prog.get("done", []) as Array).duplicate(), "progress": progress}


static func _count(sim: Sim, fam: String, e: Dictionary) -> void:
	var prog: Dictionary = sim.state.objectives[fam]
	var chain: Array = prog["chain"]
	var idx := int(prog["index"])
	if idx >= chain.size():
		return
	var id := str(chain[idx])
	var conds: Array = sim.catalog.objectives().get(id, {}).get("conditions", [])
	var have: Array = prog.get("have", [])
	var changed := false
	for c: int in conds.size():
		var cond: Dictionary = conds[c]
		if str(cond.get("event", "")) != str(e["type"]) or not _matches(e, cond.get("match", {})):
			continue
		var need := int(cond.get("count", 1))
		if int(have[c]) < need:
			have[c] = int(have[c]) + 1
			changed = true
	if not changed:
		return
	if OS.is_debug_build():
		print("[Objectives] %s · %s: progreso %s (evento %s)" % [fam, id, str(have), e["type"]])
	for c: int in conds.size():
		if int(have[c]) < int(conds[c].get("count", 1)):
			return
	(prog["done"] as Array).append(id)
	prog["index"] = idx + 1
	prog["have"] = _zeros(sim.catalog, chain, idx + 1)
	sim.events.append({"type": "objective_done", "family": fam, "objective": id})
	Notices.add(sim, fam, Notices.INFO, "notice.objective_done",
		{"objective": id, "name_key": str(sim.catalog.objectives().get(id, {}).get("name_key", ""))})
	if OS.is_debug_build():
		var next := str(chain[idx + 1]) if idx + 1 < chain.size() else "(fin de la cadena)"
		print("[Objectives] %s cumple %s; siguiente: %s" % [fam, id, next])


## While the current objective of `fam` waits for a scripted contract that is gone (not on the board and not accepted
## by `fam`), it fails and the chain moves on (the next one may be lost too). `reason`: the reason of a contract of
## the family that failed this step ("expired" | "abandoned"), "" if none (then "gone": another family took it).
static func _drop_lost(sim: Sim, fam: String, reason: String) -> void:
	var prog: Dictionary = sim.state.objectives[fam]
	var chain: Array = prog["chain"]
	while int(prog["index"]) < chain.size():
		var idx := int(prog["index"])
		var id := str(chain[idx])
		var script := lost_script(sim, fam, id)
		if script == "":
			return
		var why := reason if reason in ["expired", "abandoned"] else "gone"
		prog["index"] = idx + 1
		prog["have"] = _zeros(sim.catalog, chain, idx + 1)
		sim.events.append({"type": "objective_failed", "family": fam, "objective": id, "reason": why})
		Notices.add(sim, fam, Notices.WARNING, "notice.objective_failed", {"objective": id, "contract_reason": why,
			"name_key": str(sim.catalog.objectives().get(id, {}).get("name_key", ""))})
		if OS.is_debug_build():
			var next := str(chain[idx + 1]) if idx + 1 < chain.size() else "(fin de la cadena)"
			print("[Objectives] %s pierde %s: el encargo %s ya no se puede cumplir (%s); siguiente: %s" % [fam, id,
				script, why, next])


## The scripted contract that objective `id` of `fam` waits for and that is gone ("" if it has none, if it is still
## on the board or accepted by `fam`, or if its conditions are already met).
static func lost_script(sim: Sim, fam: String, id: String) -> String:
	var prog: Dictionary = sim.state.objectives.get(fam, {})
	var have: Array = prog.get("have", [])
	var conds: Array = sim.catalog.objectives().get(id, {}).get("conditions", [])
	for c: int in conds.size():
		var m: Variant = conds[c].get("match", {})
		if not m is Dictionary or not (m as Dictionary).has("script") or (m as Dictionary)["script"] is Dictionary:
			continue
		if c < have.size() and int(have[c]) >= int(conds[c].get("count", 1)):
			continue
		var script := str(m["script"])
		var alive := false
		for k: Dictionary in sim.state.contracts.get("board", []):
			alive = alive or str(k.get("script", "")) == script
		for k: Dictionary in sim.state.contracts.get("accepted", []):
			alive = alive or (str(k.get("script", "")) == script and str(k.get("family", "")) == fam)
		if not alive:
			return script
	return ""


static func _family_of_event(st: WorldState, e: Dictionary) -> String:
	var fam := str(e.get("family", ""))
	if fam != "":
		return fam
	return Money.family_of(st, str(e.get("actor", "")))


static func _matches(e: Dictionary, m: Dictionary) -> bool:
	for k: String in m:
		if not e.has(k):
			return false
		var want: Variant = m[k]
		var got: Variant = e[k]
		if want is Dictionary:
			var w: Dictionary = want
			if w.has("gte") and not (_num(got) and float(got) >= float(w["gte"])):
				return false
			if w.has("lte") and not (_num(got) and float(got) <= float(w["lte"])):
				return false
			if w.has("ne") and _same(got, w["ne"]):
				return false
		elif not _same(got, want):
			return false
	return true


static func _same(a: Variant, b: Variant) -> bool:
	if _num(a) and _num(b):
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return str(a) == str(b) and not (a is bool or b is bool)
	return a == b


static func _num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _zeros(catalog: Catalog, chain: Array, idx: int) -> Array:
	var out: Array = []
	if idx < chain.size():
		for c: Variant in catalog.objectives().get(str(chain[idx]), {}).get("conditions", []):
			out.append(0)
	return out
