class_name Reputation
extends RefCounted
## A family's reputation (GDD 4.12.1, ap. A; docs/contratos/h9_titulos.md): a global value (families[fam].reputation,
## an int that may go below 0) plus a modifier per social class (class_reputation: {class: int}); the reputation with
## a class is the sum. change() is the only way to move it: every system that gives or takes reputation calls it
## (contracts, wages, firing, rumours, the overdue debt, inspections, facades, microevents). step() reads the events
## of the step against the rules of data/politics.json (fair trade, quality sales, wages paid, actions on the
## townsfolk), with their caps, and at dawn gives the passive reputation of every operative workshop with staff.
## No randomness.

## The v9 fields of a family (NewGame and SaveFile 8 -> 9; the save has no catalog: "common" is the first title of
## data/titles, class modifiers are added when first used).
static func family_fields() -> Dictionary:
	return {"title": "common", "class_reputation": {}, "reputation_log": [], "reputation_caps": {}}


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.politics.get("reputation", {})


## The global reputation of a family (0 if unknown).
static func of(st: WorldState, fam: String) -> int:
	return int(st.families.get(fam, {}).get("reputation", 0))


## The reputation of `fam` with class `cls`: global + its class modifier.
static func with_class(st: WorldState, fam: String, cls: String) -> int:
	return of(st, fam) + class_mod(st, fam, cls)


static func class_mod(st: WorldState, fam: String, cls: String) -> int:
	var m: Variant = st.families.get(fam, {}).get("class_reputation", {})
	return int((m as Dictionary).get(cls, 0)) if m is Dictionary else 0


const NO_CLASS: int = -999999  # change(): no exact class amount given


## Adds `amount` to the family's reputation for `reason`. `cls` (or the reason's class in data reason_class) also
## moves that class's modifier by round(amount × class_share), or by exactly `class_amount` when given. Logs it
## (reputation_log) and emits reputation_changed {family, amount, reason, class, reputation}. Nothing happens for an
## unknown family or when both amounts are 0.

static func change(sim: Sim, fam: String, amount: int, reason: String, cls: String = "",
		class_amount: int = NO_CLASS) -> void:
	var st := sim.state
	if not st.families.has(fam):
		return
	var c := cfg(sim)
	if cls == "":
		cls = str(c.get("reason_class", {}).get(reason, ""))
	var cam := 0
	if cls != "":
		cam = class_amount if class_amount != NO_CLASS else roundi(float(amount) * float(c.get("class_share", 0.5)))
	if amount == 0 and cam == 0:
		return
	var f: Dictionary = st.families[fam]
	f["reputation"] = int(f.get("reputation", 0)) + amount
	if cam != 0:
		if not f.get("class_reputation") is Dictionary:
			f["class_reputation"] = {}
		f["class_reputation"][cls] = int(f["class_reputation"].get(cls, 0)) + cam
	if not f.get("reputation_log") is Array:
		f["reputation_log"] = []
	var log: Array = f["reputation_log"]
	log.append({"minute": int(st.clock["minute"]), "amount": amount, "reason": reason, "class": cls,
		"class_amount": cam})
	var keep := int(c.get("log_size", 12))
	while log.size() > keep:
		log.pop_front()
	sim.events.append({"type": "reputation_changed", "family": fam, "amount": amount, "reason": reason, "class": cls,
		"reputation": int(f["reputation"])})
	if OS.is_debug_build():
		print("[Reputation] %s %+d (%s%s) -> %d" % [fam, amount, reason,
			"" if cls == "" else ", %s %+d" % [cls, cam], int(f["reputation"])])


## The rules over the events of this step, then (at dawn) the passive reputation. After every system that emits
## the events it reads (Market, Counter, Staff, NpcActions) and before Dynasty and Objectives.
static func step(sim: Sim) -> void:
	var rules: Array = cfg(sim).get("rules", [])
	if not rules.is_empty():
		var n := sim.events.size()  # only the events there were: change() appends its own
		for i: int in n:
			var e: Dictionary = sim.events[i]
			var type := str(e.get("type", ""))
			for r: Dictionary in rules:
				if type in (r.get("events", []) as Array):
					_apply_rule(sim, r, e)
	if Ledger.is_dawn(sim):
		_passive(sim)


static func _apply_rule(sim: Sim, r: Dictionary, e: Dictionary) -> void:
	var st := sim.state
	var type := str(e["type"])
	var fam := ""
	var other := ""
	match type:
		"market_sold":
			fam = str(e.get("family", ""))
		"counter_sold":
			fam = str(e.get("family", ""))
			other = str(e.get("customer", ""))
		"wage_paid":
			fam = str(e.get("family", ""))
		"npc_action":
			fam = str(st.characters.get(str(e.get("actor", "")), {}).get("family", ""))
			other = str(e.get("target", ""))
			if str(e.get("action", "")) != str(r.get("action", "")):
				return
			if r.has("ok") and bool(e.get("ok", false)) != bool(r["ok"]):
				return
	if fam == "" or not st.families.has(fam):
		return
	if r.has("min_quality") and int(e.get("quality", 0)) < int(r["min_quality"]):
		return
	if not _take_cap(sim, fam, r):
		return
	var cls := str(r.get("class", "")) if r.get("class") != null else ""
	if cls == "target":
		cls = str(st.characters.get(other, {}).get("class", "")) if other != "" else ""
	var cam := int(r.get("class_amount", 0)) if cls != "" else 0
	change(sim, fam, int(r.get("amount", 0)), str(r.get("id", type)), cls, cam)


## Whether rule `r` may still give for `fam` in its current window (and counts it). cap 0 = no cap.
static func _take_cap(sim: Sim, fam: String, r: Dictionary) -> bool:
	var cap := int(r.get("cap", 0))
	if cap <= 0:
		return true
	var f: Dictionary = sim.state.families[fam]
	if not f.get("reputation_caps") is Dictionary:
		f["reputation_caps"] = {}
	var caps: Dictionary = f["reputation_caps"]
	var id := str(r.get("id", ""))
	var window := floori(float(Clock.day(int(sim.state.clock["minute"]))) / float(maxi(1, int(r.get("cap_days", 1)))))
	var c: Dictionary = caps.get(id, {"window": -1, "count": 0})
	if int(c.get("window", -1)) != window:
		c = {"window": window, "count": 0}
	if int(c["count"]) >= cap:
		caps[id] = c
		return false
	c["count"] = int(c["count"]) + 1
	caps[id] = c
	return true


## At dawn (after Staff: today's employees are known): +per_business_with_staff for each operative business of every
## family with at least one active employee (ap. A: «+1/día por negocio operativo con empleados»): its workshops and,
## since 2026-11-07 (the manager, the reputation that stopped Barón), its services (the tavern).
static func _passive(sim: Sim) -> void:
	var per := int(cfg(sim).get("passive", {}).get("per_business_with_staff", 0))
	if per == 0:
		return
	var fams: Array = sim.state.families.keys()
	fams.sort()
	for fam: String in fams:
		var n := 0
		for b: String in Titles.business_ids(sim, fam, true):   # the tavern with employees too (Barón, 2026-11-07)
			for c: String in Staff.employees_of(sim.state, b):
				if Staff.is_active(sim, c):
					n += 1
					break
		if n > 0:
			change(sim, fam, per * n, "passive")
