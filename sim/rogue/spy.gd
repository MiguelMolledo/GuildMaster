class_name Spy
extends RefCounted
## The Rogue's second trade, the spy (docs/gdd/04d_otras_clases.md §4.22.6.5): spying a building of another family,
## the reports of his family (families[fam].intel), the town's spying jobs (passed by the fence of his den), blackmail
## and exposing a secret. Figures in data/rogue.json `spy`; rolls with their own keys (`rogue|spy...`), so nothing
## else's dice move.
##
## - spy {actor, building}: from `range` tiles of its door, outdoors, for `minutes`. By night (dusk too) a guard who sees
##   him arrests him for trespass. At the end, SkillCheck(stealth, check_base + Security level) + the difficulty's
##   check_mod: a report {id, about, building, day, gold (± gold_error), stock, secrets}. Each Secrets upgrade of the
##   building is a hidden fact (tax_evasion, or smuggling with illegal profit) seen by the spy; a household of the town
##   (a family nobody plays) keeps a secret with secrets.share (secrets.kinds; adultery is never tried).
## - deliver_intel {actor, job}: at his den, a report of the job's family made after the job was posted: its pay.
## - blackmail {actor, fact}: a hidden fact his family saw against another family, once a season each: the demand is
##   max(min ; share of their gold). A household pays with household_pays when the charge is min_severity or more; an AI
##   family when its honesty < 0 and the same. Who pays keeps quiet (the «extortion» fact nobody saw); who does not saw
##   it and may denounce it at dawn (Rogue._dawn).
## - expose_fact {actor, fact}: the secret goes public; that family loses expose.reputation.
## State (read with defaults, no save version): families[fam].intel; state.town.spy {spying, jobs, posted, n}; facts
## {secret: true, seen_by, blackmailed: "<year>|<season>"}.


static func cfg(sim: Sim) -> Dictionary:
	return Rogue._c(sim, "spy")


static func _part(sim: Sim, k: String) -> Dictionary:
	return (cfg(sim).get(k, {}) as Dictionary)


static func _now(sim: Sim) -> int:
	return int(sim.state.clock["minute"])


static func _today(sim: Sim) -> int:
	return Clock.day(_now(sim))


## state.town.spy: {spying: {actor: {building, start, end, next_check}}, jobs: [job], posted: day, n: counter}.
static func book(sim: Sim) -> Dictionary:
	var st := sim.state
	if not st.town.get("spy") is Dictionary:
		st.town["spy"] = {}
	var b: Dictionary = st.town["spy"]
	if not b.get("spying") is Dictionary:
		b["spying"] = {}
	if not b.get("jobs") is Array:
		b["jobs"] = []
	return b


# --- Reports -----------------------------------------------------------------------------------------------------------

## The reports of `fam`, newest last.
static func intel(st: WorldState, fam: String) -> Array:
	var f: Dictionary = st.families.get(fam, {})
	return f.get("intel", []) if f.get("intel") is Array else []


static func report(st: WorldState, fam: String, id: String) -> Dictionary:
	for r: Dictionary in intel(st, fam):
		if str(r.get("id", "")) == id:
			return r
	return {}


static func _keep_report(sim: Sim, fam: String, r: Dictionary) -> void:
	var f: Dictionary = sim.state.families[fam]
	if not f.get("intel") is Array:
		f["intel"] = []
	(f["intel"] as Array).append(r)
	while (f["intel"] as Array).size() > int(cfg(sim).get("reports_kept", 30)):
		(f["intel"] as Array).pop_front()


# --- Secrets -----------------------------------------------------------------------------------------------------------

## Whether `fam` is a household of the town (a family nobody plays: no person, no AI profile).
static func is_household(st: WorldState, fam: String) -> bool:
	var f: Dictionary = st.families.get(fam, {})
	return not f.is_empty() and str(f.get("controlled_by", "")) != "human" and str(f.get("ai_profile", "")) == ""


## The secret a household keeps (a charge of secrets.kinds) or "": rolled once per family with its own key, so it is
## the same all game long and needs no state.
static func household_secret(sim: Sim, fam: String) -> String:
	if not is_household(sim.state, fam):
		return ""
	var sc := _part(sim, "secrets")
	if Kin.roll(sim.state, "rogue|secret|" + fam) >= float(sc.get("share", 0.25)):
		return ""
	var r := Kin.roll(sim.state, "rogue|secret_kind|" + fam)
	var acc := 0.0
	var kinds: Array = sc.get("kinds", [["tax_evasion", 1.0]])
	for k: Variant in kinds:
		acc += float((k as Array)[1])
		if r < acc:
			return str((k as Array)[0])
	return str((kinds[kinds.size() - 1] as Array)[0])


## The hidden fact of `charge` against `fam` already seen by somebody of `by_fam` (so a second look adds nothing), or {}.
static func _known(sim: Sim, fam: String, charge: String, by_fam: String) -> Dictionary:
	for f: Dictionary in sim.state.justice.get("facts", []):
		if str(f.get("family", "")) != fam or str(f.get("charge", "")) != charge or not bool(f.get("secret", false)):
			continue
		for w: Variant in f.get("seen_by", []):
			if Rogue._fam(sim.state, str(w)) == by_fam:
				return f
	return {}


## The secrets `actor` finds at `bld` (hidden facts seen by him; created once per family and charge). Returns their ids.
static func _secrets(sim: Sim, actor: String, bld: String) -> Array:
	var st := sim.state
	var tf := Money.family_of(st, bld)
	var fam := Rogue._fam(st, actor)
	var charges: Array = []
	for u: Variant in Upgrades.owned(st, bld):
		if str(sim.catalog.upgrade(str(u)).get("branch", "")) == "secrets":
			var c := "smuggling" if Upgrades.amount(sim, bld, "illegal_profit") > 0.0 else "tax_evasion"
			if not c in charges:
				charges.append(c)
	var hs := household_secret(sim, tf)
	if hs != "" and not hs in charges:
		charges.append(hs)
	var out: Array = []
	for c: String in charges:
		var f := _known(sim, tf, c, fam)
		if f.is_empty():
			var fid := Tribunal.add_fact(sim, "secret", tf, Kin.head(st, tf), c)
			f = Tribunal.fact(st, fid)
			f["public"] = false
			f["secret"] = true
			f["seen_by"] = [actor]
			f["building"] = bld
		out.append(str(f["id"]))
	return out


# --- Spying ------------------------------------------------------------------------------------------------------------

## "" if `actor` may spy `bld` now (the distance aside: too_far is the order's), else why.
static func spy_reason(sim: Sim, actor: String, bld: String) -> String:
	var st := sim.state
	if not st.characters.has(actor) or not Kin.alive(st, actor):
		return "unknown_actor"
	if not st.buildings.has(bld):
		return "unknown_building"
	var tf := Money.family_of(st, bld)
	var fam := Rogue._fam(st, actor)
	if tf == "":
		return "bad_target"
	if tf == fam:
		return "own_building"
	if Rogue.den_of(st, fam) == "":
		return "no_den"
	if book(sim)["spying"].has(actor) or not Rogue.pending_arrest(st, actor).is_empty():
		return "busy"
	return ""


## Whether `actor` is close enough to `bld`'s door to spy it, in the street.
static func near(sim: Sim, actor: String, bld: String) -> bool:
	var st := sim.state
	var door: Array = st.buildings.get(bld, {}).get("door", [])
	return Rogue._outdoors(st, actor) and door.size() == 2 \
		and Life.dist(Life.tile_of(st, actor), door) <= int(cfg(sim).get("range", 2))


## The chance (0-1) that spying `bld` gives a report.
static func chance(sim: Sim, actor: String, bld: String) -> float:
	return SkillCheck.chance(sim, SkillCheck.stat(sim, actor, "stealth"), int(cfg(sim).get("check_base", 5))
		+ Rogue.security_level(sim, bld), int(Rogue._lever(sim, "check_mod", 0)))


## {"type": "spy", "actor", "building"}: from range tiles of its door, for minutes.
static func order_spy(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var bld := str(o.get("building", ""))
	var why := spy_reason(sim, actor, bld)
	if why != "":
		return Orders.fail(why)
	if not near(sim, actor, bld):
		return Orders.fail("too_far")
	var now := _now(sim)
	(book(sim)["spying"] as Dictionary)[actor] = {"building": bld, "start": now,
		"end": now + int(cfg(sim).get("minutes", 120)), "next_check": now + 60}
	st.characters[actor]["path"] = []
	sim.events.append({"type": "spy_started", "actor": actor, "family": Rogue._fam(st, actor), "building": bld,
		"about": Money.family_of(st, bld)})
	if OS.is_debug_build():
		print("[Spy] %s espía %s (de %s) hasta el minuto %d" % [actor, bld, Money.family_of(st, bld),
			now + int(cfg(sim).get("minutes", 120))])
	return Orders.ok()


static func _step_spying(sim: Sim) -> void:
	var st := sim.state
	var now := _now(sim)
	var spying: Dictionary = book(sim)["spying"]
	for actor: String in Festivals._sorted_keys(spying):
		var j: Dictionary = spying[actor]
		var bld := str(j["building"])
		if not Kin.alive(st, actor) or not st.buildings.has(bld) or not near(sim, actor, bld):
			spying.erase(actor)
			sim.events.append({"type": "spy_interrupted", "actor": actor, "family": Rogue._fam(st, actor),
				"building": bld})
			continue
		if now >= int(j["next_check"]):
			j["next_check"] = int(j["next_check"]) + 60
			if Rogue._phase(sim) in ["night", "dusk"]:  # loitering by a door at night: a guard who sees him
				var g := Rogue.guard_in_view(sim, Life.tile_of(st, actor))
				if g != "":
					spying.erase(actor)
					var fid := Tribunal.add_fact(sim, "spy", Rogue._fam(st, actor), actor,
						str(Rogue._c(sim, "charges").get("spy", "trespass")))
					sim.events.append({"type": "spy_caught", "actor": actor, "family": Rogue._fam(st, actor),
						"building": bld, "guard": g})
					Rogue.caught(sim, actor, g, str(Tribunal.fact(st, fid)["charge"]), fid)
					continue
		if now >= int(j["end"]):
			spying.erase(actor)
			_finish(sim, actor, bld, int(j["start"]))


static func _finish(sim: Sim, actor: String, bld: String, start: int) -> void:
	var st := sim.state
	var fam := Rogue._fam(st, actor)
	var tf := Money.family_of(st, bld)
	var r := SkillCheck.roll(sim, "rogue|spy|%s|%s|%d" % [actor, bld, start], SkillCheck.stat(sim, actor, "stealth"),
		int(cfg(sim).get("check_base", 5)) + Rogue.security_level(sim, bld), int(Rogue._lever(sim, "check_mod", 0)))
	if not bool(r["success"]):
		sim.events.append({"type": "spy_failed", "actor": actor, "family": fam, "building": bld, "about": tf})
		if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
			Notices.add(sim, fam, Notices.WARNING, "notice.spy_failed", {"name": str(st.characters[actor].get("name", "")),
				"family": str(st.families.get(tf, {}).get("name", ""))}, bld)
		return
	var err := float(cfg(sim).get("gold_error", 0.05))
	var gold := roundi(Money.gold(st, tf) * (1.0 + (Kin.roll(st, "rogue|spy_gold|%s|%d" % [bld, start]) * 2.0 - 1.0) * err))
	var stock: Array = []
	var stacks: Array = (st.buildings[bld].get("inventory", {}).get("stacks", []) as Array).duplicate()
	stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["qty"]) > int(b["qty"]) or (int(a["qty"]) == int(b["qty"]) and str(a["item"]) < str(b["item"])))
	for s: Dictionary in stacks.slice(0, int(cfg(sim).get("stock_shown", 5))):
		stock.append({"item": Rogue.clean(str(s["item"])), "qty": int(s["qty"])})
	var b := book(sim)
	b["n"] = int(b.get("n", 0)) + 1
	var rep := {"id": "int_%04d" % int(b["n"]), "about": tf, "building": bld, "day": _today(sim), "by": actor,
		"gold": gold, "stock": stock, "secrets": _secrets(sim, actor, bld), "used": ""}
	_keep_report(sim, fam, rep)
	Rogue.add_underworld(sim, fam, int(_part(sim, "underworld").get("report", 1)), "spy")
	sim.events.append({"type": "spy_done", "actor": actor, "family": fam, "building": bld, "about": tf,
		"report": str(rep["id"]), "secrets": (rep["secrets"] as Array).size()})
	if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, fam, Notices.INFO, "notice.spy_done", {"name": str(st.characters[actor].get("name", "")),
			"family": str(st.families.get(tf, {}).get("name", "")), "secrets": (rep["secrets"] as Array).size()}, bld)
	if OS.is_debug_build():
		print("[Spy] informe %s de %s sobre %s: oro≈%d, %d secretos" % [rep["id"], actor, tf, gold,
			(rep["secrets"] as Array).size()])


# --- Spying jobs -------------------------------------------------------------------------------------------------------

## The underworld that counts for the jobs: the family's fame, plus den_underworld if it has a den (its contacts).
static func job_underworld(st: WorldState, catalog_spy: Dictionary, fam: String) -> int:
	var j: Dictionary = catalog_spy.get("jobs", {})
	return Rogue.underworld(st, fam) + (int(j.get("den_underworld", 10)) if Rogue.den_of(st, fam) != "" else 0)


## The open jobs `fam` may take (none without the underworld they ask).
static func jobs_for(sim: Sim, fam: String) -> Array:
	if job_underworld(sim.state, cfg(sim), fam) < int(_part(sim, "jobs").get("min_underworld", 10)):
		return []
	return (book(sim)["jobs"] as Array).filter(func(j: Dictionary) -> bool: return str(j.get("about", "")) != fam)


## At dawn: the jobs that ran out go; posted_per_day new ones while fewer than open_max are open. Each asks for a report
## on a family with a building (the town's households and the workshops; never one played by a person).
static func _post_jobs(sim: Sim) -> void:
	var st := sim.state
	var jc := _part(sim, "jobs")
	var b := book(sim)
	var today := _today(sim)
	if int(b.get("posted", -1)) == today:
		return
	b["posted"] = today
	b["jobs"] = (b["jobs"] as Array).filter(func(j: Dictionary) -> bool: return int(j["until"]) >= today)
	var any_den := false
	for f: String in st.families:
		if Rogue.den_of(st, f) != "":
			any_den = true
	if not any_den:
		return
	var targets: Array = []
	for bld: String in Festivals._sorted_keys(st.buildings):
		var tf := Money.family_of(st, bld)
		if tf == "" or tf in targets or str(st.families.get(tf, {}).get("controlled_by", "")) == "human" \
				or Rogue.den_of(st, tf) != "":
			continue
		targets.append(tf)
	var pay: Array = jc.get("pay", [35, 70])
	for k: int in int(jc.get("posted_per_day", 1)):
		if (b["jobs"] as Array).size() >= int(jc.get("open_max", 2)) or targets.is_empty():
			break
		var open: Array = (b["jobs"] as Array).map(func(j: Dictionary) -> String: return str(j["about"]))
		var free := targets.filter(func(t: String) -> bool: return not t in open)
		if free.is_empty():
			break
		var about := str(free[Kin.randi_range(st, "rogue|spy_job|%d|%d" % [today, k], 0, free.size() - 1)])
		b["n"] = int(b.get("n", 0)) + 1
		var p := roundi(Kin.randi_range(st, "rogue|spy_pay|%d|%d" % [today, k], int(pay[0]), int(pay[1]))
			* Rogue._lever(sim, "intel_mult", 1.0))
		var job := {"id": "spj_%04d" % int(b["n"]), "about": about, "pay": p, "posted": today,
			"until": today + int(jc.get("days", 3)) - 1}
		(b["jobs"] as Array).append(job)
		sim.events.append({"type": "spy_job_posted", "job": str(job["id"]), "about": about, "pay": p})
		if OS.is_debug_build():
			print("[Spy] encargo %s: un informe de %s por %d de oro (hasta el día %d)" % [job["id"], about, p, job["until"]])


static func job(sim: Sim, id: String) -> Dictionary:
	for j: Dictionary in book(sim)["jobs"]:
		if str(j["id"]) == id:
			return j
	return {}


## The report of `fam` that serves job `j` (about its family, made on or after the day it was posted, not used), or {}.
static func report_for_job(sim: Sim, fam: String, j: Dictionary) -> Dictionary:
	for r: Dictionary in intel(sim.state, fam):
		if str(r.get("about", "")) == str(j.get("about", "")) and int(r.get("day", -1)) >= int(j.get("posted", 0)) \
				and str(r.get("used", "")) == "":
			return r
	return {}


## "" if `actor` may deliver job `id` now, else why.
static func deliver_reason(sim: Sim, actor: String, id: String) -> String:
	var st := sim.state
	if not st.characters.has(actor) or not Kin.alive(st, actor):
		return "unknown_actor"
	var fam := Rogue._fam(st, actor)
	var j := job(sim, id)
	if j.is_empty() or not jobs_for(sim, fam).any(func(x: Dictionary) -> bool: return str(x["id"]) == id):
		return "unknown_job"
	var den := Rogue.den_of(st, fam)
	if den == "" or str(st.characters[actor].get("location", "")) != den:
		return "not_at_den"
	if report_for_job(sim, fam, j).is_empty():
		return "no_report"
	return ""


## {"type": "deliver_intel", "actor", "job"}: at his den, the report goes to the client; its pay.
static func order_deliver(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var id := str(o.get("job", ""))
	var why := deliver_reason(sim, actor, id)
	if why != "":
		return Orders.fail(why)
	var fam := Rogue._fam(st, actor)
	var j := job(sim, id)
	var r := report_for_job(sim, fam, j)
	r["used"] = id
	book(sim)["jobs"] = (book(sim)["jobs"] as Array).filter(func(x: Dictionary) -> bool: return str(x["id"]) != id)
	Money.change(sim, fam, int(j["pay"]), Money.CONTRACTS, "spy_job:" + id, Rogue.den_of(st, fam), actor)
	Rogue.add_underworld(sim, fam, int(_part(sim, "underworld").get("job", 2)), "spy_job")
	sim.events.append({"type": "spy_job_done", "actor": actor, "family": fam, "job": id, "about": str(j["about"]),
		"gold": int(j["pay"])})
	if OS.is_debug_build():
		print("[Spy] %s entrega el encargo %s (%s): +%d" % [actor, id, j["about"], j["pay"]])
	return Orders.ok()


# --- Blackmail and exposing ---------------------------------------------------------------------------------------------

static func _season_key(sim: Sim) -> String:
	return "%d|%s" % [Clock.year(_now(sim), sim.catalog.time), Clock.season(_now(sim), sim.catalog.time)]


## The hidden facts `fam` saw against other families that it may use (blackmail or expose).
static func usable_facts(sim: Sim, fam: String) -> Array:
	var out: Array = []
	for f: Dictionary in sim.state.justice.get("facts", []):
		if not bool(f.get("secret", false)) or bool(f.get("public", true)) or bool(f.get("tried", false)) \
				or str(f.get("family", "")) == fam:
			continue
		for w: Variant in f.get("seen_by", []):
			if Rogue._fam(sim.state, str(w)) == fam:
				out.append(f)
				break
	return out


static func _usable(sim: Sim, fam: String, fid: String) -> bool:
	return usable_facts(sim, fam).any(func(f: Dictionary) -> bool: return str(f["id"]) == fid)


static func demand(sim: Sim, f: Dictionary) -> int:
	var bc := _part(sim, "blackmail")
	return roundi(maxf(float(bc.get("min", 20)), float(bc.get("share", 0.1)) * Money.gold(sim.state, str(f["family"])))
		* Rogue._lever(sim, "intel_mult", 1.0))


## "" if `actor` may blackmail with fact `fid` now, else why.
static func blackmail_reason(sim: Sim, actor: String, fid: String) -> String:
	var st := sim.state
	if not st.characters.has(actor) or not Kin.alive(st, actor):
		return "unknown_actor"
	var f := Tribunal.fact(st, fid)
	if f.is_empty() or not _usable(sim, Rogue._fam(st, actor), fid):
		return "fact_not_usable"
	if str(f.get("blackmailed", "")) == _season_key(sim):
		return "blackmailed_this_season"
	if Kin.head(st, str(f["family"])) == "":
		return "unknown_target"
	if Money.gold(st, str(f["family"])) <= 0:
		return "nothing_to_pay"
	return ""


## Whether the family of fact `f` pays (a household: household_pays with a charge min_severity or more; an AI family:
## honesty < 0 and the same; a person's family: no, for now).
static func _pays(sim: Sim, f: Dictionary) -> bool:
	var st := sim.state
	var bc := _part(sim, "blackmail")
	var tf := str(f["family"])
	var heavy := Tribunal.severity_rank(sim, Tribunal.severity_of(sim, str(f["charge"]))) \
		>= Tribunal.severity_rank(sim, str(bc.get("min_severity", "medium")))
	if not heavy or str(st.families.get(tf, {}).get("controlled_by", "")) == "human":
		return false
	if is_household(st, tf):
		return Kin.roll(st, "rogue|blackmail|%s|%s" % [f["id"], _season_key(sim)]) < float(bc.get("household_pays", 0.7))
	return Tribunal.honesty(sim, tf) < 0


## {"type": "blackmail", "actor", "fact"}: the victim pays (and keeps quiet) or not (it saw it: an «extortion» fact it
## may denounce at dawn). Once a season each secret.
static func order_blackmail(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var fid := str(o.get("fact", ""))
	var why := blackmail_reason(sim, actor, fid)
	if why != "":
		return Orders.fail(why)
	var fam := Rogue._fam(st, actor)
	var f := Tribunal.fact(st, fid)
	var tf := str(f["family"])
	var victim := Kin.head(st, tf)
	f["blackmailed"] = _season_key(sim)
	var ask := demand(sim, f)
	var paid := 0
	var ef := Tribunal.add_fact(sim, "blackmail", fam, actor, str(Rogue._c(sim, "charges").get("blackmail", "extortion")))
	var e := Tribunal.fact(st, ef)
	e["public"] = false
	if _pays(sim, f):
		paid = mini(ask, Money.gold(st, tf))
		Money.change(sim, tf, -paid, Money.LOOT, "blackmail:" + fid, "", victim)
		Money.change(sim, fam, paid, Money.LOOT, "blackmail:" + fid, "", actor)
		Rogue.add_underworld(sim, fam, int(_part(sim, "underworld").get("blackmail", 2)), "blackmail")
		e["seen_by"] = []  # who pays keeps quiet: denouncing would bring his own secret out
	else:
		e["seen_by"] = [victim]
	Emotions.change_relation(sim, victim, actor, int(_part(sim, "blackmail").get("relation", -20)), "blackmail")
	sim.events.append({"type": "blackmail_done", "actor": actor, "family": fam, "fact": fid, "about": tf, "ask": ask,
		"gold": paid, "paid": paid > 0})
	if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
		Notices.add(sim, fam, Notices.INFO if paid > 0 else Notices.WARNING,
			"notice.blackmail_paid" if paid > 0 else "notice.blackmail_refused",
			{"family": str(st.families.get(tf, {}).get("name", "")), "gold": paid}, victim)
	if OS.is_debug_build():
		print("[Spy] %s chantajea a %s con %s (%s): pide %d, paga %d" % [actor, tf, fid, f["charge"], ask, paid])
	return Orders.ok()


## "" if `actor` may make fact `fid` public now, else why.
static func expose_reason(sim: Sim, actor: String, fid: String) -> String:
	var st := sim.state
	if not st.characters.has(actor) or not Kin.alive(st, actor):
		return "unknown_actor"
	var f := Tribunal.fact(st, fid)
	if f.is_empty() or not _usable(sim, Rogue._fam(st, actor), fid):
		return "fact_not_usable"
	return ""


## {"type": "expose_fact", "actor", "fact"}: the secret is told around: public (it can be taken to court if its charge
## is tried) and its family loses expose.reputation.
static func order_expose(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var fid := str(o.get("fact", ""))
	var why := expose_reason(sim, actor, fid)
	if why != "":
		return Orders.fail(why)
	var f := Tribunal.fact(st, fid)
	f["public"] = true
	f["denounced_by"] = actor
	Reputation.change(sim, str(f["family"]), int(_part(sim, "expose").get("reputation", -10)), "secret_exposed")
	sim.events.append({"type": "secret_exposed", "actor": actor, "family": Rogue._fam(st, actor), "fact": fid,
		"about": str(f["family"]), "charge": str(f["charge"])})
	if OS.is_debug_build():
		print("[Spy] %s destapa %s contra %s (%s)" % [actor, fid, f["family"], f["charge"]])
	return Orders.ok()


## Every minute: the spies at their posts; at dawn, the town's jobs.
static func step(sim: Sim) -> void:
	_step_spying(sim)
	for e: Dictionary in sim.events:
		if str(e.get("type", "")) == "phase_changed" and str(e.get("phase", "")) == "dawn":
			_post_jobs(sim)
			break
