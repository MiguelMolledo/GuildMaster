class_name OpenGoals
extends RefCounted
## Always-open goals (docs/gdd/03b_diversion_y_ritmo.md §3b.5.1): the goals zone shows 2 or 3 goals, a short one
## (today), a medium one (this season) and a long one (this year or the dynasty's), on the objectives that already
## exist (data/objectives/, conditions as events, Objectives._matches).
##   short  = the current start objective (Objectives, GDD 4.16); when the chain is over, the short-horizon goal of an
##            unlock not done yet.
##   medium = the goal of the latest unlock (data/unlocks.json `goal`) not done yet and not the short one.
##   long   = the year's goal (data/unlocks.json year_goal: the debt in year 1) until it is done, in the chain or here;
##            then the first dynasty goal of data/goals.json not reached (GDD 4.17, read only).
## The goals of the unlocks count the family's events from the moment they open, apart from the chain:
## state.unlocks[fam]._goals = {objective: {have: [int per condition], done: bool, since: minute}}.
## Events: open_goal_done {family, objective}. A game from before v20 (everything open) shows the chain and the long
## goal, as before plus the dynasty's.


static func step(sim: Sim) -> void:
	var st := sim.state
	if sim.catalog.unlocks.is_empty() or sim.events.is_empty():
		return
	var n := sim.events.size()
	for fam: String in Unlocks._human_families(st):
		var u: Variant = st.unlocks.get(fam)
		if not u is Dictionary or (u as Dictionary).has(Unlocks.ALL):
			continue
		var goals := _goals(st, fam)
		for id: String in active_ids(sim, fam):
			if not goals.has(id):
				goals[id] = {"have": _zeros(sim, id), "done": false, "since": int(st.clock["minute"])}
			var g: Dictionary = goals[id]
			if bool(g["done"]):
				continue
			var conds: Array = sim.catalog.objectives().get(id, {}).get("conditions", [])
			var have: Array = g["have"]
			for i: int in n:
				var e: Dictionary = sim.events[i]
				if Unlocks._family_of(st, e) != fam:
					continue
				for c: int in conds.size():
					var cond: Dictionary = conds[c]
					if str(cond.get("event", "")) == str(e.get("type", "")) and Objectives._matches(e, cond.get("match", {})) \
							and c < have.size() and int(have[c]) < int(cond.get("count", 1)):
						have[c] = int(have[c]) + 1
			var all := not conds.is_empty()
			for c: int in conds.size():
				all = all and c < have.size() and int(have[c]) >= int(conds[c].get("count", 1))
			if all:
				g["done"] = true
				sim.events.append({"type": "open_goal_done", "family": fam, "objective": id})
				Notices.add(sim, fam, Notices.INFO, "notice.objective_done",
					{"objective": id, "name_key": str(sim.catalog.objectives().get(id, {}).get("name_key", ""))})
				if OS.is_debug_build():
					print("[OpenGoals] %s cumple la meta %s" % [fam, id])


## The objectives followed now for `fam`: the year goal and the goals of its unlocks (that exist as objectives).
static func active_ids(sim: Sim, fam: String) -> Array:
	var out: Array = []
	var yg := str(sim.catalog.unlocks.get("year_goal", ""))
	if yg != "" and sim.catalog.objectives().has(yg):
		out.append(yg)
	for e: Dictionary in Unlocks.list(sim, fam):
		var g := str((e["def"] as Dictionary).get("goal", ""))
		if g != "" and sim.catalog.objectives().has(g) and not g in out:
			out.append(g)
	return out


## Up to three goals for the HUD: [{horizon: short | medium | long, objective (or "" for a dynasty goal), name_key,
## progress: [{have, need}], from: chain | unlock | year | dynasty}].
static func view(sim: Sim, fam: String) -> Array:
	var st := sim.state
	var out: Array = []
	var ov := Objectives.view(sim, fam)
	var chain_done: Array = ov.get("done", []) if not ov.is_empty() else []
	var short := str(ov.get("current", "")) if not ov.is_empty() else ""
	if short != "":
		out.append({"horizon": "short", "objective": short, "from": "chain", "progress": ov.get("progress", []),
			"name_key": _name_key(sim, short)})
	var u: Variant = st.unlocks.get(fam)
	var goals: Dictionary = (u as Dictionary).get("_goals", {}) if u is Dictionary else {}  # read only: a view
	var listed := Unlocks.list(sim, fam)
	if short == "":
		for e: Dictionary in listed:
			var g := str((e["def"] as Dictionary).get("goal", ""))
			if str((e["def"] as Dictionary).get("horizon", "")) == "short" and _open(goals, g, chain_done):
				short = g
				out.append(_entry(sim, goals, g, "short", "unlock"))
				break
	var yg := str(sim.catalog.unlocks.get("year_goal", ""))
	var medium := ""
	for i: int in range(listed.size() - 1, -1, -1):
		var d: Dictionary = listed[i]["def"]
		var g := str(d.get("goal", ""))
		if g == "" or g == short or g == yg or str(d.get("horizon", "medium")) != "medium":
			continue
		if _open(goals, g, chain_done) and sim.catalog.objectives().has(g):
			medium = g
			out.append(_entry(sim, goals, g, "medium", "unlock"))
			break
	if yg != "" and sim.catalog.objectives().has(yg) and yg != short and _open(goals, yg, chain_done):
		out.append(_entry(sim, goals, yg, "long", "year"))
	else:
		var dyn := _dynasty_goal(sim, fam)
		if not dyn.is_empty():
			out.append(dyn)
	return out


static func _entry(sim: Sim, goals: Dictionary, id: String, horizon: String, from: String) -> Dictionary:
	var conds: Array = sim.catalog.objectives().get(id, {}).get("conditions", [])
	var have: Array = (goals.get(id, {}) as Dictionary).get("have", [])
	var progress: Array = []
	for c: int in conds.size():
		progress.append({"have": int(have[c]) if c < have.size() else 0, "need": int(conds[c].get("count", 1))})
	return {"horizon": horizon, "objective": id, "from": from, "progress": progress, "name_key": _name_key(sim, id)}


static func _open(goals: Dictionary, id: String, chain_done: Array) -> bool:
	if id == "" or id in chain_done:
		return false
	return not bool((goals.get(id, {}) as Dictionary).get("done", false))


## The first dynasty goal not reached (data/goals.json, GDD 4.17): {horizon: long, objective: "", name_key, from}.
static func _dynasty_goal(sim: Sim, fam: String) -> Dictionary:
	var done: Array = sim.state.families.get(fam, {}).get("goals_done", [])
	for g: Dictionary in sim.catalog.goals.get("goals", []):
		if not str(g.get("id", "")) in done:
			return {"horizon": "long", "objective": "", "from": "dynasty", "progress": [],
				"name_key": str(g.get("name_key", ""))}
	return {}


static func _name_key(sim: Sim, id: String) -> String:
	return str(sim.catalog.objectives().get(id, {}).get("name_key", "objective." + id))


static func _goals(st: WorldState, fam: String) -> Dictionary:
	var u: Dictionary = st.unlocks[fam]
	if not u.get("_goals") is Dictionary:
		u["_goals"] = {}
	return u["_goals"]


static func _zeros(sim: Sim, id: String) -> Array:
	var out: Array = []
	for c: Variant in sim.catalog.objectives().get(id, {}).get("conditions", []):
		out.append(0)
	return out
