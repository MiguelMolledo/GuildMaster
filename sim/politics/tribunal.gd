class_name Tribunal
extends RefCounted
## The court (GDD 4.12.5, ap. A; docs/contratos/h11_tribunal.md). Facts (state.justice.facts) are what can be taken to
## court: a Secrets inspection, a bribe found out... (all public in H11). A trial (state.trials) opens from an
## inspection (automatic, the town accuses), an accusation (accuse: a public fact or fabricated proofs) or an arrest
## (the constable). Preparation of 1 season: the accused's family works the 3-5 witnesses in person (witness_action:
## convince, bribe, threaten). Then the hearing (hearing_hours): the accused questions the witnesses against
## (trial_cross) and rests (trial_rest); a human judge may rule (trial_verdict). Verdict by the formula of ap. A; the
## sentence of the worst charge: fine, confiscation of the goods for sale, office and a title, banishment of 1 year. Banished
## characters give no orders and leave the map until it ends. Randomness: SkillCheck and Kin (the town's stream), never
## state.rng (the economy's dice do not move).

const OPEN: Array[String] = ["preparation", "hearing"]


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.justice


static func _now(sim: Sim) -> int:
	return int(sim.state.clock["minute"])


static func _today(sim: Sim) -> int:
	return Clock.day(_now(sim))


static func severity_rank(sim: Sim, sev: String) -> int:
	return (cfg(sim).get("severities", []) as Array).find(sev)


static func severity_of(sim: Sim, charge: String) -> String:
	return str(cfg(sim).get("charges", {}).get(charge, {}).get("severity", "light"))


# --- Facts ------------------------------------------------------------------------------------------------------------

## A public fact against `fam` (what `actor` did); its charge from data facts[kind] unless given. Returns its id.
static func add_fact(sim: Sim, kind: String, fam: String, actor: String, charge: String = "") -> String:
	var st := sim.state
	if not st.justice.get("facts") is Array:
		st.justice["facts"] = []
	var ch := charge if charge != "" else str(cfg(sim).get("facts", {}).get(kind, "minor_fraud"))
	var id := Ids.next(st, "fct")
	(st.justice["facts"] as Array).append({"id": id, "kind": kind, "family": fam, "actor": actor, "charge": ch,
		"day": _today(sim), "public": true, "tried": false})
	sim.events.append({"type": "fact_added", "fact": id, "kind": kind, "family": fam, "charge": ch})
	if OS.is_debug_build():
		print("[Tribunal] hecho %s: %s contra %s (%s, cargo %s)" % [id, kind, fam, actor, ch])
	return id


static func fact(st: WorldState, id: String) -> Dictionary:
	for f: Dictionary in st.justice.get("facts", []):
		if str(f.get("id", "")) == id:
			return f
	return {}


## The public facts against `fam` not yet tried.
static func facts_against(sim: Sim, fam: String) -> Array:
	var out: Array = []
	for f: Dictionary in sim.state.justice.get("facts", []):
		if str(f.get("family", "")) == fam and bool(f.get("public", true)) and not bool(f.get("tried", false)):
			out.append(f)
	return out


# --- Queries ----------------------------------------------------------------------------------------------------------

static func trial(st: WorldState, id: String) -> Dictionary:
	for t: Dictionary in st.trials:
		if str(t.get("id", "")) == id:
			return t
	return {}


static func open_trials(sim: Sim) -> Array:
	return sim.state.trials.filter(func(t: Dictionary) -> bool: return str(t.get("status", "")) in OPEN)


## The open trial where `fam` is the accused (or, with `as_accuser`, either side); {} if none.
static func of_family(sim: Sim, fam: String, as_accuser: bool = false) -> Dictionary:
	for t: Dictionary in open_trials(sim):
		if str(t.get("family", "")) == fam or (as_accuser and str(t.get("accuser_family", "")) == fam):
			return t
	return {}


static func is_banished(st: WorldState, chr: String) -> bool:
	var u := int(st.characters.get(chr, {}).get("banished_until", -1))
	return u >= 0 and Clock.day(int(st.clock["minute"])) <= u


static func honesty(sim: Sim, fam: String) -> int:
	return Inspections.honesty_of(sim, fam)


static func change_honesty(sim: Sim, fam: String, amount: int, why: String) -> void:
	var f: Dictionary = sim.state.families.get(fam, {})
	if f.is_empty() or amount == 0:
		return
	if not f.get("attitudes") is Dictionary:
		f["attitudes"] = {"honesty": 0, "generosity": 0, "diplomacy": 0}
	f["attitudes"]["honesty"] = clampi(int(f["attitudes"].get("honesty", 0)) + amount, -100, 100)
	sim.events.append({"type": "attitude_changed", "family": fam, "attitude": "honesty", "amount": amount, "reason": why})
	if OS.is_debug_build():
		print("[Tribunal] honestidad de %s %+d (%s) -> %d" % [fam, amount, why, int(f["attitudes"]["honesty"])])


# --- Opening a trial --------------------------------------------------------------------------------------------------

## Opens a trial against `accused` for `charge`. accuser "" = the town (rhetoric: the inspector's or town_rhetoric).
## Marks the fact as tried, picks the witnesses and tells the families. Returns the trial id.
static func open(sim: Sim, accused: String, accuser: String, accuser_family: String, charge: String, source: String,
		fact_id: String, fabricated: bool, building: String = "") -> String:
	var st := sim.state
	var tc: Dictionary = cfg(sim).get("trial", {})
	var id := Ids.next(st, "tri")
	var fam := str(st.characters[accused].get("family", ""))
	var f := fact(st, fact_id)
	if not f.is_empty():
		f["tried"] = true
	var proofs := int(tc.get("proofs", {}).get("fabricated" if fabricated else ("inspection" if source == "inspection" \
		else "fact"), 1))
	var now := _now(sim)
	var t := {"id": id, "charge": charge, "severity": severity_of(sim, charge), "accused": accused, "family": fam,
		"accuser": accuser, "accuser_family": accuser_family, "source": source, "fact": fact_id, "fabricated": fabricated,
		"proofs": proofs, "building": building, "witnesses": [], "extra": [], "status": "preparation", "start": now,
		"prep_until": now + int(tc.get("prep_days", 2)) * Clock.MINUTES_PER_DAY, "hearing_until": -1, "verdict": "",
		"judge_verdict": "", "sentence": {}, "scale": {}}
	t["witnesses"] = _pick_witnesses(sim, t)
	st.trials.append(t)
	sim.events.append({"type": "trial_opened", "trial": id, "accused": accused, "family": fam,
		"accuser_family": accuser_family, "charge": charge, "source": source})
	var params := {"name": str(st.characters[accused].get("name", "")), "family": str(st.families.get(fam, {}).get("name", "")),
		"accuser": _accuser_name(sim, t), "charge": charge, "day": Clock.day(int(t["prep_until"])) + 1}
	if _human(st, fam):
		Notices.add(sim, fam, Notices.URGENT, "notice.trial_accused", params, accused)
	if _human(st, accuser_family):
		Notices.add(sim, accuser_family, Notices.INFO, "notice.trial_accuser", params, accused)
	for h: String in Offices._humans(st):
		if h != fam and h != accuser_family:
			Notices.add(sim, h, Notices.INFO, "notice.trial_other", params, accused)
	if OS.is_debug_build():
		print("[Tribunal] juicio %s: %s (%s) acusado de %s por %s (%s); testigos %s; vista el minuto %d" % [id, accused,
			fam, charge, accuser if accuser != "" else "la ciudad", source,
			(t["witnesses"] as Array).map(func(w: Dictionary) -> String: return "%s:%s" % [w["character"], w["disposition"]]),
			int(t["prep_until"])])
	return id


static func _human(st: WorldState, fam: String) -> bool:
	return fam != "" and str(st.families.get(fam, {}).get("controlled_by", "")) == "human"


static func _accuser_name(sim: Sim, t: Dictionary) -> String:
	var a := str(t.get("accuser", ""))
	if a != "":
		return str(sim.state.characters.get(a, {}).get("name", a))
	return "@town"  # the UI says «la ciudad» (SimQuery.notice_text)


## 3-5 witnesses (the town's dice): the accused family's employees, the adults of the accuser's family and the adult
## townsfolk, the strongest feelings first (|relation| with accused and accuser), then id. Disposition: the accuser's
## family is against; the rest by relation with the accused minus relation with the accuser (band).
static func _pick_witnesses(sim: Sim, t: Dictionary) -> Array:
	var st := sim.state
	var tc: Dictionary = cfg(sim).get("trial", {})
	var span: Array = tc.get("witnesses", [3, 5])
	var n := Kin.randi_range(st, "trial|" + str(t["id"]), int(span[0]), int(span[1]))
	var accused := str(t["accused"])
	var accuser := str(t["accuser"])
	var fam := str(t["family"])
	var afam := str(t["accuser_family"])
	var groups: Array = [[], [], []]
	for id: Variant in st.characters:
		var c := str(id)
		if c == accused or c == accuser or not Kin.alive(st, c) or not Kin.is_adult(sim, c) or is_banished(st, c):
			continue
		var cf := str(st.characters[c].get("family", ""))
		if cf == fam:
			continue
		if Staff.employer(st, c) != "" and Money.family_of(st, Staff.employer(st, c)) == fam:
			groups[0].append(c)
		elif afam != "" and cf == afam:
			groups[1].append(c)
		elif TownLife.is_townsperson(st, c):
			groups[2].append(c)
	var out: Array = []
	for g: Array in groups:
		g.sort_custom(func(a: String, b: String) -> bool:
			var sa := absi(Emotions.relation(st, a, accused)) + (absi(Emotions.relation(st, a, accuser)) if accuser != "" else 0)
			var sb := absi(Emotions.relation(st, b, accused)) + (absi(Emotions.relation(st, b, accuser)) if accuser != "" else 0)
			return sa > sb if sa != sb else a < b)
		for c: String in g:
			if out.size() >= n:
				break
			out.append({"character": c, "disposition": disposition(sim, c, accused, accuser, afam), "done": {},
				"cross": ""})
	return out


static func disposition(sim: Sim, w: String, accused: String, accuser: String, afam: String) -> String:
	var st := sim.state
	if afam != "" and str(st.characters[w].get("family", "")) == afam:
		return "against"
	var band := int(cfg(sim).get("trial", {}).get("disposition_band", 10))
	var d := Emotions.relation(st, w, accused) - (Emotions.relation(st, w, accuser) if accuser != "" else 0)
	if d >= band:
		return "favor"
	if d <= -band:
		return "against"
	return "neutral"


# --- Step -------------------------------------------------------------------------------------------------------------

## Inspections that caught somebody open their automatic trial; trials move from preparation to hearing to verdict;
## a dead accused drops the trial; at dawn, banishments that ended.
static func step(sim: Sim) -> void:
	var st := sim.state
	var n := sim.events.size()
	for i: int in n:
		var e: Dictionary = sim.events[i]
		match str(e.get("type", "")):
			"inspection":
				if bool(e.get("caught", false)):
					_from_inspection(sim, str(e.get("family", "")), str(e.get("building", "")))
			"character_died":
				var t := of_family(sim, str(e.get("family", "")))
				if not t.is_empty() and str(t["accused"]) == str(e.get("character", "")):
					t["status"] = "done"
					t["verdict"] = "dropped"
	if st.trials.is_empty() and not Ledger.is_dawn(sim):
		return
	var now := _now(sim)
	for t: Dictionary in st.trials:
		match str(t.get("status", "")):
			"preparation":
				if now >= int(t["prep_until"]):
					_start_hearing(sim, t)
			"hearing":
				if now >= int(t["hearing_until"]):
					rule(sim, t)
	if Ledger.is_dawn(sim):
		_end_banishments(sim)
		_trim(sim)


## GDD 4.8: «multa y juicio automático». The fact (smuggling with the contraband upgrade, else tax evasion) and, if
## the family is not already on trial, a trial against its head (the town accuses: the inspector if there is one).
static func _from_inspection(sim: Sim, fam: String, bld: String) -> void:
	var st := sim.state
	if fam == "" or not st.families.has(fam):
		return
	var kind := "inspection_smuggling" if Upgrades.amount(sim, bld, "illegal_profit") > 0.0 else "inspection"
	var fid := add_fact(sim, kind, fam, "", "")
	var open_t := of_family(sim, fam)
	if not open_t.is_empty():
		(open_t["extra"] as Array).append(str(fact(st, fid)["charge"]))
		fact(st, fid)["tried"] = true
		return
	var accused := Kin.head(st, fam)
	if accused == "" or not Kin.alive(st, accused) or is_banished(st, accused):
		return
	var insp: Array = Offices.holders(sim, "market_inspector")
	var accuser := str(insp[0]) if not insp.is_empty() and str(st.characters[str(insp[0])].get("family", "")) != fam else ""
	open(sim, accused, accuser, str(st.characters.get(accuser, {}).get("family", "")) if accuser != "" else "",
		str(fact(st, fid)["charge"]), "inspection", fid, false, bld)


static func _start_hearing(sim: Sim, t: Dictionary) -> void:
	t["status"] = "hearing"
	t["hearing_until"] = _now(sim) + roundi(float(cfg(sim).get("trial", {}).get("hearing_hours", 2)) * 60.0)
	sim.events.append({"type": "trial_hearing", "trial": str(t["id"]), "family": str(t["family"])})
	var params := {"name": str(sim.state.characters[str(t["accused"])].get("name", "")), "charge": str(t["charge"])}
	for f: String in [str(t["family"]), str(t["accuser_family"])]:
		if _human(sim.state, f):
			Notices.add(sim, f, Notices.URGENT, "notice.trial_hearing", params, str(t["accused"]))
	if OS.is_debug_build():
		print("[Tribunal] %s: empieza la vista (hasta el minuto %d)" % [t["id"], int(t["hearing_until"])])


# --- The scale (ap. A) ------------------------------------------------------------------------------------------------

## {defense, accusation, d: {rhetoric, favor, reputation}, a: {rhetoric, against, proofs}} of a trial now.
static func scale(sim: Sim, t: Dictionary) -> Dictionary:
	var st := sim.state
	var tc: Dictionary = cfg(sim).get("trial", {})
	var favor := 0
	var against := 0
	var cw: Dictionary = cfg(sim).get("cross", {})
	for w: Dictionary in t.get("witnesses", []):
		if not Kin.alive(st, str(w["character"])):
			continue
		match str(w.get("disposition", "")):
			"favor":
				favor += 1
			"against":
				match str(w.get("cross", "")):  # questioned at the hearing: data cross.ok_weight / fail_weight
					"ok":
						against += int(cw.get("ok_weight", 0))
					"fail":
						against += int(cw.get("fail_weight", 2))
					_:
						against += 1
	var r_acc := SkillCheck.stat(sim, str(t["accused"]), "rhetoric")
	var accuser := str(t.get("accuser", ""))
	var r_accuser := SkillCheck.stat(sim, accuser, "rhetoric") if accuser != "" else int(tc.get("town_rhetoric", 5))
	var rep := Reputation.of(st, str(t["family"]))
	var d := {"rhetoric": r_acc * int(tc.get("rhetoric", 2)), "favor": favor * int(tc.get("witness", 15)),
		"reputation": roundi(float(rep) * float(tc.get("reputation", 0.1)))}
	var a := {"rhetoric": r_accuser * int(tc.get("rhetoric", 2)), "against": against * int(tc.get("witness", 15)),
		"proofs": int(t.get("proofs", 0)) * int(tc.get("proof", 20))}
	return {"defense": int(d["rhetoric"]) + int(d["favor"]) + int(d["reputation"]),
		"accusation": int(a["rhetoric"]) + int(a["against"]) + int(a["proofs"]), "d": d, "a": a,
		"favor": favor, "against": against}


# --- Verdict and sentence ---------------------------------------------------------------------------------------------

## Rules the trial: the judge's verdict if given, else the scale (defense > accusation = innocent).
static func rule(sim: Sim, t: Dictionary) -> void:
	var st := sim.state
	var sc := scale(sim, t)
	var verdict := "innocent" if int(sc["defense"]) > int(sc["accusation"]) else "guilty"
	if str(t.get("judge_verdict", "")) != "":
		verdict = str(t["judge_verdict"])
	t["status"] = "done"
	t["verdict"] = verdict
	t["scale"] = {"defense": int(sc["defense"]), "accusation": int(sc["accusation"])}
	t["ruled"] = _now(sim)
	var fam := str(t["family"])
	var afam := str(t["accuser_family"])
	if verdict == "innocent":
		Chronicle.add(st, "trial_won", {"family": fam, "trial": str(t["id"])})
		if bool(t.get("fabricated", false)) and afam != "":
			var jc: Dictionary = cfg(sim).get("accuse", {})
			Reputation.change(sim, afam, int(jc.get("false_reputation", -50)), "false_accusation")
			add_fact(sim, "fabrication", afam, str(t["accuser"]))
			for h: String in [fam, afam]:
				if _human(st, h):
					Notices.add(sim, h, Notices.URGENT, "notice.false_accusation", {"family": str(st.families[afam].get("name",
						""))}, str(t["accuser"]))
	else:
		if afam != "":
			Chronicle.add(st, "trial_won", {"family": afam, "trial": str(t["id"])})
		_sentence(sim, t)
	sim.events.append({"type": "trial_verdict", "trial": str(t["id"]), "verdict": verdict, "family": fam,
		"defense": int(sc["defense"]), "accusation": int(sc["accusation"]), "sentence": (t["sentence"] as Dictionary).duplicate()})
	var params := {"name": str(st.characters[str(t["accused"])].get("name", "")), "charge": str(t["charge"])}
	for f: String in [fam, afam]:
		if _human(st, f):
			Notices.add(sim, f, Notices.URGENT if f == fam and verdict == "guilty" else Notices.INFO,
				"notice.trial_verdict_" + verdict, params, str(t["accused"]))
	if OS.is_debug_build():
		print("[Tribunal] %s: %s (defensa %d contra acusación %d%s) condena %s" % [t["id"], verdict, int(sc["defense"]),
			int(sc["accusation"]), ", el juez decide" if str(t.get("judge_verdict", "")) != "" else "", t["sentence"]])


## The sentence of the worst charge (the trial's and its extras): fine, confiscation, office and title, banishment;
## its reputation and the chronicle (dynasty score).
static func _sentence(sim: Sim, t: Dictionary) -> void:
	var st := sim.state
	var sev := str(t["severity"])
	for c: Variant in t.get("extra", []):
		var s2 := severity_of(sim, str(c))
		if severity_rank(sim, s2) > severity_rank(sim, sev):
			sev = s2
	var sd: Dictionary = cfg(sim).get("sentences", {}).get(sev, {})
	var fam := str(t["family"])
	var accused := str(t["accused"])
	var out := {"severity": sev, "kind": str(sd.get("kind", ""))}
	match str(sd.get("kind", "")):
		"fine":
			var span: Array = sd.get("fine", [10, 50])
			var amount := mini(Kin.randi_range(st, "fine|" + str(t["id"]), int(span[0]), int(span[1])), Money.gold(st, fam))
			Money.change(sim, fam, -amount, Money.JUSTICE, "sentence_" + str(t["id"]), "", accused)
			out["gold"] = amount
		"confiscation":
			var bld := str(t.get("building", ""))
			if bld == "" or not st.buildings.has(bld):
				var biz := Titles.business_ids(sim, fam)
				bld = str(biz[0]) if not biz.is_empty() else ""
			var taken := 0
			if bld != "":  # the goods for sale (products), like the night thief of H7: the raw materials stay
				var inv: Dictionary = st.buildings[bld].get("inventory", {})
				var keep: Array = []
				for s: Dictionary in inv.get("stacks", []):
					if str(sim.catalog.item(str(s.get("item", ""))).get("category", "")) == "product":
						taken += int(s.get("qty", 0))
					else:
						keep.append(s)
				inv["stacks"] = keep
			out["building"] = bld
			out["units"] = taken
		"office_loss":
			var where := Offices.seat_of(st, accused)
			if not where.is_empty():
				Offices.leave(sim, str(where["office"]), int(where["index"]), "sentence")
				out["office"] = str(where["office"])
			var ladder := sim.catalog.title_ladder()
			var i := ladder.find(Titles.current(sim, fam))
			var down := int(sd.get("titles_down", 1))
			if i > 0:
				st.families[fam]["title"] = str(ladder[maxi(0, i - down)])
				out["title"] = str(st.families[fam]["title"])
		"banishment":
			out["until"] = banish(sim, accused, int(cfg(sim).get("banishment_days", 8)))
	Reputation.change(sim, fam, int(sd.get("reputation", 0)), "sentence_" + sev)
	Chronicle.add(st, "sentence", {"family": fam, "severity": sev, "trial": str(t["id"]), "actor": accused})
	t["sentence"] = out


## Banishes `chr` for `days` days (the last day included is returned): out of its building and off the map, no queued
## orders, no work; Sim refuses its orders until it ends.
static func banish(sim: Sim, chr: String, days: int) -> int:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	var loc := str(ch.get("location", ""))
	if loc != "":
		var zone := Production.job_zone(sim, chr, loc)
		if zone != "":
			Production.interrupt(sim, loc, zone)
		var zones: Dictionary = st.buildings.get(loc, {}).get("zones", {})
		var station := str(ch.get("station", ""))
		if zones.has(station) and str(zones[station].get("occupant", "")) == chr:
			zones[station]["occupant"] = ""
		ch["position"] = (st.buildings.get(loc, {}).get("door", ch.get("position", [0, 0])) as Array).duplicate()
	ch["location"] = ""
	ch["station"] = ""
	ch["path"] = []
	ch["order_queue"] = []
	var until := _today(sim) + days - 1
	ch["banished_until"] = until
	var fam := str(ch.get("family", ""))
	sim.events.append({"type": "banished", "character": chr, "family": fam, "until": until})
	if _human(st, fam):
		Notices.add(sim, fam, Notices.URGENT, "notice.banished", {"name": str(ch.get("name", "")), "day": until + 1}, chr)
	if OS.is_debug_build():
		print("[Tribunal] %s desterrado hasta el día %d" % [chr, until])
	return until


static func _end_banishments(sim: Sim) -> void:
	var st := sim.state
	var d := _today(sim)
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: Variant in ids:
		var ch: Dictionary = st.characters[id]
		var u := int(ch.get("banished_until", -1))
		if u >= 0 and d > u:
			end_banishment(sim, str(id))


static func end_banishment(sim: Sim, chr: String) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	ch["banished_until"] = -1
	var home := Kin.home_of(sim, chr)
	if home != "" and st.buildings.has(home):
		ch["position"] = (st.buildings[home].get("door", ch.get("position", [0, 0])) as Array).duplicate()
	sim.events.append({"type": "banishment_ended", "character": chr, "family": str(ch.get("family", ""))})
	if _human(st, str(ch.get("family", ""))):
		Notices.add(sim, str(ch.get("family", "")), Notices.INFO, "notice.banishment_ended", {"name": str(ch.get("name",
			""))}, chr)


static func _trim(sim: Sim) -> void:
	var keep := int(cfg(sim).get("trial", {}).get("keep", 12))
	var done: Array = sim.state.trials.filter(func(t: Dictionary) -> bool: return str(t.get("status", "")) == "done")
	while done.size() > keep:
		sim.state.trials.erase(done.pop_front())


# --- Orders -----------------------------------------------------------------------------------------------------------

static func _actor_reason(sim: Sim, actor: String) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not Kin.alive(st, actor):
		return "dead"
	if not Kin.is_adult(sim, actor):
		return "too_young"
	var fam := str(st.characters[actor].get("family", ""))
	if fam == "" or not st.families.has(fam):
		return "no_family"
	return ""


## What `actor` can accuse `target`'s family of: {facts: [fact ids usable], charges: [charge ids], reason}.
static func accuse_options(sim: Sim, actor: String, target: String) -> Dictionary:
	var facts: Array = []
	var tf := str(sim.state.characters.get(target, {}).get("family", ""))
	for f: Dictionary in facts_against(sim, tf):
		facts.append(str(f["id"]))
	var charges: Array = (cfg(sim).get("charges", {}) as Dictionary).keys()
	charges.sort()
	return {"facts": facts, "charges": charges, "reason": accuse_status(sim, actor, target, "", "", false)}


## The refusal of accuse ("" if it would go ahead). With fact "" and fabricate false only the parties are checked.
static func accuse_status(sim: Sim, actor: String, target: String, fact_id: String, charge: String,
		fabricate: bool) -> String:
	var st := sim.state
	var why := _actor_reason(sim, actor)
	if why != "":
		return why
	if not st.characters.has(target) or not Kin.alive(st, target) or not Kin.is_adult(sim, target):
		return "unknown_target"
	var fam := str(st.characters[actor]["family"])
	var tf := str(st.characters[target].get("family", ""))
	if tf == fam or tf == "":
		return "bad_args"
	var need := str(cfg(sim).get("accuse", {}).get("min_title", "citizen"))
	if Titles.rank(sim, Titles.current(sim, fam)) < Titles.rank(sim, need):
		return "title_too_low"
	if not of_family(sim, tf).is_empty():
		return "already_on_trial"
	if fact_id != "":
		var f := fact(st, fact_id)
		if f.is_empty():
			return "unknown_fact"
		if str(f.get("family", "")) != tf or bool(f.get("tried", false)) or not bool(f.get("public", true)):
			return "fact_not_usable"
	elif fabricate:
		if not (cfg(sim).get("charges", {}) as Dictionary).has(charge):
			return "unknown_charge"
	return ""


## {"type": "accuse", "actor", "target", "fact"? | "charge" + "fabricate": true}: management (the sheet). Reasons: see
## accuse_status. Fabricated: SkillCheck (stealth vs target): success opens the trial with a fabricated proof; failure
## costs fail_reputation and leaves a fact against the accuser's family.
static func order_accuse(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var fact_id := str(o.get("fact", ""))
	var fabricate := bool(o.get("fabricate", false))
	var charge := str(o.get("charge", ""))
	if fact_id == "" and not fabricate:
		var why0 := accuse_status(sim, actor, target, "", "", false)
		return Orders.fail(why0 if why0 != "" else "needs_fact")
	var why := accuse_status(sim, actor, target, fact_id, charge, fabricate)
	if why != "":
		if OS.is_debug_build():
			print("[Tribunal] %s no puede acusar a %s: %s" % [actor, target, why])
		return Orders.fail(why)
	var st := sim.state
	var fam := str(st.characters[actor]["family"])
	if fact_id != "":
		open(sim, target, actor, fam, str(fact(st, fact_id)["charge"]), "accusation", fact_id, false)
		return Orders.ok()
	var fc: Dictionary = cfg(sim).get("accuse", {}).get("fabricate", {})
	change_honesty(sim, fam, int(cfg(sim).get("honesty", {}).get("fabricate", -10)), "fabricate")
	var r := SkillCheck.roll(sim, "fabricate|%s|%s|%d" % [actor, target, _today(sim)], SkillCheck.stat(sim, actor,
		str(fc.get("stat", "stealth"))), int(fc.get("target", 5)))
	if not bool(r["success"]):
		Reputation.change(sim, fam, int(fc.get("fail_reputation", -50)), "false_accusation")
		add_fact(sim, "fabrication", fam, actor)
		sim.events.append({"type": "accusation_failed", "actor": actor, "target": target})
		if _human(st, fam):
			Notices.add(sim, fam, Notices.URGENT, "notice.false_accusation", {"family": str(st.families[fam].get("name",
				""))}, actor)
		return Orders.ok()
	open(sim, target, actor, fam, charge, "accusation", "", true)
	return Orders.ok()


## The refusal of witness_action, "" if it would be done now.
static func witness_status(sim: Sim, actor: String, trial_id: String, witness: String, kind: String) -> String:
	var st := sim.state
	var why := _actor_reason(sim, actor)
	if why != "":
		return why
	var t := trial(st, trial_id)
	if t.is_empty():
		return "unknown_trial"
	if str(st.characters[actor]["family"]) != str(t["family"]):
		return "not_your_trial"
	if str(t["status"]) != "preparation":
		return "trial_not_preparing"
	var w := _witness(t, witness)
	if w.is_empty() or not Kin.alive(st, witness):
		return "unknown_witness"
	var wa: Dictionary = cfg(sim).get("witness_actions", {})
	if not wa.has(kind):
		return "bad_args"
	if int(w.get("done", {}).get(kind, -1)) == _today(sim):
		return "already_today"
	if kind == "bribe" and not Money.can_pay(st, str(t["family"]), bribe_gold(sim, witness)):
		return "not_enough_gold"
	if str(w["disposition"]) == "favor":
		return "already_favor"
	if not NpcActions.in_range(sim, actor, witness):
		return "too_far"
	return ""


static func _witness(t: Dictionary, chr: String) -> Dictionary:
	for w: Dictionary in t.get("witnesses", []):
		if str(w.get("character", "")) == chr:
			return w
	return {}


## The gold a witness asks for a bribe (GDD: «según codicia»): gold_base + gold_per_negotiation × its Negotiation.
static func bribe_gold(sim: Sim, witness: String) -> int:
	var b: Dictionary = cfg(sim).get("witness_actions", {}).get("bribe", {})
	return int(b.get("gold_base", 20)) + int(b.get("gold_per_negotiation", 5)) * SkillCheck.stat(sim, witness, "negotiation")


## {"type": "witness_action", "actor", "trial", "witness", "kind"}: convince / bribe / threaten a witness (GDD 4.12.5),
## in person. Reasons: see witness_status.
static func order_witness(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var tid := str(o.get("trial", ""))
	var witness := str(o.get("witness", ""))
	var kind := str(o.get("kind", ""))
	var why := witness_status(sim, actor, tid, witness, kind)
	if why != "":
		return Orders.fail(why)
	var st := sim.state
	var t := trial(st, tid)
	var w := _witness(t, witness)
	var a: Dictionary = cfg(sim).get("witness_actions", {}).get(kind, {})
	var key := "witness|%s|%s|%s|%d" % [kind, actor, witness, _today(sim)]
	var r := SkillCheck.roll(sim, key, SkillCheck.stat(sim, actor, str(a.get("stat", "rhetoric"))),
		SkillCheck.stat(sim, witness, str(a.get("against", "empathy"))))
	var ok := bool(r["success"])
	w["done"][kind] = _today(sim)
	match kind:
		"convince":
			if ok:
				w["disposition"] = "favor"
		"bribe":
			Money.change(sim, str(t["family"]), -bribe_gold(sim, witness), Money.JUSTICE, "witness_bribe_" + tid, "", actor)
			change_honesty(sim, str(t["family"]), int(cfg(sim).get("honesty", {}).get("bribe", -5)), "witness_bribe")
			w["disposition"] = "favor"
			if not ok:
				_denounced(sim, t, actor, "witness_bribe", str(a.get("extra_charge", "bribery")))
		"threaten":
			if ok:
				w["disposition"] = "favor"
			else:
				w["disposition"] = "against"
				_denounced(sim, t, actor, "witness_threat", str(a.get("extra_charge", "brawl")))
	sim.events.append({"type": "witness_action", "trial": tid, "actor": actor, "witness": witness, "kind": kind, "ok": ok})
	if OS.is_debug_build():
		print("[Tribunal] %s: %s %s al testigo %s -> %s (%s)" % [tid, actor, kind, witness, "bien" if ok else "mal",
			w["disposition"]])
	return Orders.ok()


static func _denounced(sim: Sim, t: Dictionary, actor: String, kind: String, charge: String) -> void:
	var fid := add_fact(sim, kind, str(t["family"]), actor, charge)
	fact(sim.state, fid)["tried"] = true
	(t["extra"] as Array).append(charge)
	if _human(sim.state, str(t["family"])):
		Notices.add(sim, str(t["family"]), Notices.URGENT, "notice.witness_denounced", {"charge": charge}, actor)


## The refusal of trial_cross / trial_rest for `actor` ("" = it would go).
static func hearing_status(sim: Sim, actor: String, trial_id: String) -> String:
	var why := _actor_reason(sim, actor)
	if why != "":
		return why
	var t := trial(sim.state, trial_id)
	if t.is_empty():
		return "unknown_trial"
	if str(sim.state.characters[actor]["family"]) != str(t["family"]):
		return "not_your_trial"
	if str(t["status"]) != "hearing":
		return "trial_not_in_hearing"
	return ""


static func cross_status(sim: Sim, actor: String, trial_id: String, witness: String) -> String:
	var why := hearing_status(sim, actor, trial_id)
	if why != "":
		return why
	var w := _witness(trial(sim.state, trial_id), witness)
	if w.is_empty() or not Kin.alive(sim.state, witness):
		return "unknown_witness"
	if str(w["disposition"]) != "against":
		return "not_against"
	if str(w.get("cross", "")) != "":
		return "already_crossed"
	return ""


## {"type": "trial_cross", "actor", "trial", "witness"}: questions a witness against at the hearing (management):
## SkillCheck rhetoric vs its empathy; success: it does not count; failure: it counts double.
static func order_cross(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var tid := str(o.get("trial", ""))
	var witness := str(o.get("witness", ""))
	var why := cross_status(sim, actor, tid, witness)
	if why != "":
		return Orders.fail(why)
	var c: Dictionary = cfg(sim).get("cross", {})
	var t := trial(sim.state, tid)
	var r := SkillCheck.roll(sim, "cross|%s|%s|%s" % [tid, actor, witness], SkillCheck.stat(sim, actor,
		str(c.get("stat", "rhetoric"))), SkillCheck.stat(sim, witness, str(c.get("against", "empathy"))))
	_witness(t, witness)["cross"] = "ok" if bool(r["success"]) else "fail"
	sim.events.append({"type": "trial_cross", "trial": tid, "witness": witness, "ok": bool(r["success"])})
	return Orders.ok()


## {"type": "trial_rest", "actor", "trial"}: the defense rests: the verdict now (management).
static func order_rest(sim: Sim, o: Dictionary) -> Dictionary:
	var why := hearing_status(sim, str(o.get("actor", "")), str(o.get("trial", "")))
	if why != "":
		return Orders.fail(why)
	rule(sim, trial(sim.state, str(o.get("trial", ""))))
	return Orders.ok()


## The refusal of trial_verdict for `actor`: the judge (power preside_trial), not a party, the trial in its hearing.
static func verdict_status(sim: Sim, actor: String, trial_id: String, verdict: String) -> String:
	var why := _actor_reason(sim, actor)
	if why != "":
		return why
	var t := trial(sim.state, trial_id)
	if t.is_empty():
		return "unknown_trial"
	if Offices.power_def(sim, Offices.of_character(sim.state, actor), "preside_trial").is_empty():
		return "not_the_judge"
	var fam := str(sim.state.characters[actor]["family"])
	if fam == str(t["family"]) or fam == str(t["accuser_family"]):
		return "party_to_trial"
	if str(t["status"]) != "hearing":
		return "trial_not_in_hearing"
	if not verdict in ["guilty", "innocent"]:
		return "bad_args"
	return ""


## {"type": "trial_verdict", "actor", "trial", "verdict"}: the judge rules (management). Against the scale: honesty
## −20 and a scandal check (stealth vs target): failure costs reputation and leaves a corruption fact.
static func order_verdict(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var tid := str(o.get("trial", ""))
	var verdict := str(o.get("verdict", ""))
	var why := verdict_status(sim, actor, tid, verdict)
	if why != "":
		return Orders.fail(why)
	var t := trial(sim.state, tid)
	var sc := scale(sim, t)
	var fair := "innocent" if int(sc["defense"]) > int(sc["accusation"]) else "guilty"
	var fam := str(sim.state.characters[actor]["family"])
	if verdict != fair:
		var j: Dictionary = cfg(sim).get("judge", {})
		change_honesty(sim, fam, int(j.get("manipulate_honesty", -20)), "manipulate_trial")
		var r := SkillCheck.roll(sim, "judge|%s|%s" % [tid, actor], SkillCheck.stat(sim, actor, "stealth"),
			int(j.get("scandal", {}).get("target", 5)))
		if not bool(r["success"]):
			Reputation.change(sim, fam, int(j.get("scandal", {}).get("reputation", -20)), "judge_scandal")
			add_fact(sim, "judge_scandal", fam, actor)
	t["judge_verdict"] = verdict
	t["judge"] = actor
	rule(sim, t)
	return Orders.ok()


# --- Constable and judge powers (Offices.order_power) -----------------------------------------------------------------

## The refusal of an H11 office power with `args` ("" = it would work).
static func power_reason(sim: Sim, actor: String, power: String, args: Dictionary) -> String:
	var st := sim.state
	var fam := str(st.characters[actor].get("family", ""))
	match power:
		"arrest":
			var f := fact(st, str(args.get("fact", "")))
			if f.is_empty():
				return "unknown_fact"
			if bool(f.get("tried", false)) or str(f.get("family", "")) == fam:
				return "fact_not_usable"
			var accused := Kin.head(st, str(f["family"]))
			if accused == "" or not Kin.alive(st, accused) or is_banished(st, accused):
				return "unknown_target"
			if not of_family(sim, str(f["family"])).is_empty():
				return "already_on_trial"
		"investigate":
			var tf := str(args.get("family", ""))
			if not st.families.has(tf) or tf == fam:
				return "bad_args"
		"pardon":
			var c := str(args.get("character", ""))
			if not is_banished(st, c):
				return "not_banished"
		"preside_trial":
			return verdict_status(sim, actor, str(args.get("trial", "")), str(args.get("verdict", "")))
	return ""


## Applies an H11 power (validated): returns false when it found nothing (investigate).
static func use_power(sim: Sim, actor: String, power: String, args: Dictionary) -> void:
	var st := sim.state
	var fam := str(st.characters[actor].get("family", ""))
	match power:
		"arrest":
			var f := fact(st, str(args["fact"]))
			open(sim, Kin.head(st, str(f["family"])), actor, fam, str(f["charge"]), "arrest", str(f["id"]), false)
		"investigate":
			var tf := str(args["family"])
			var found := false
			for b: String in Titles.business_ids(sim, tf):
				if Upgrades.amount(sim, b, "inspection_risk") > 0.0 or Upgrades.flag(sim, b, "inspection_escape"):
					found = true
			if found:
				add_fact(sim, "investigation", tf, "")
		"pardon":
			end_banishment(sim, str(args["character"]))
		"preside_trial":
			order_verdict(sim, {"actor": actor, "trial": str(args["trial"]), "verdict": str(args["verdict"])})


# --- UI ---------------------------------------------------------------------------------------------------------------

## How hard a check looks (data bands over the SkillCheck threshold of GDD 4.2.4): easy | doubtful | hard.
static func band(sim: Sim, actor_stat: int, target_stat: int) -> String:
	var sc: Dictionary = sim.catalog.town.get("skill_check", {})
	var th := int(sc.get("base", 50)) + (actor_stat - target_stat) * int(sc.get("step", 5))
	var b: Dictionary = cfg(sim).get("bands", {})
	if th >= int(b.get("easy", 65)):
		return "easy"
	return "doubtful" if th >= int(b.get("doubtful", 40)) else "hard"


## The trial panel's data for `viewer_fam`: the trial, its scale (the accuser's proofs hidden until the hearing for
## the accused side), the witnesses with their actions' reasons for `actor`, the time left.
static func view(sim: Sim, trial_id: String, actor: String) -> Dictionary:
	var st := sim.state
	var t := trial(st, trial_id)
	if t.is_empty():
		return {}
	var sc := scale(sim, t)
	var hidden := str(t["status"]) == "preparation"
	var ws: Array = []
	for w: Dictionary in t["witnesses"]:
		var c := str(w["character"])
		var acts := {}
		for k: String in ["convince", "bribe", "threaten"]:
			acts[k] = witness_status(sim, actor, trial_id, c, k)
		var ch: Dictionary = st.characters.get(c, {})
		var why := "townsperson"
		if Staff.employer(st, c) != "" and Money.family_of(st, Staff.employer(st, c)) == str(t["family"]):
			why = "employee"
		elif str(ch.get("family", "")) == str(t["accuser_family"]) and str(t["accuser_family"]) != "":
			why = "accuser_family"
		var wa: Dictionary = cfg(sim).get("witness_actions", {})
		var bands := {}
		if st.characters.has(actor):
			for k: String in ["convince", "threaten"]:
				bands[k] = band(sim, SkillCheck.stat(sim, actor, str(wa.get(k, {}).get("stat", "rhetoric"))),
					SkillCheck.stat(sim, c, str(wa.get(k, {}).get("against", "empathy"))))
			bands["cross"] = band(sim, SkillCheck.stat(sim, actor, "rhetoric"), SkillCheck.stat(sim, c, "empathy"))
		ws.append({"character": c, "name": str(ch.get("name", c)), "bands": bands, "family": str(st.families.get(str(ch.get("family",
			"")), {}).get("name", "")), "why": why, "disposition": str(w["disposition"]), "cross": str(w.get("cross", "")),
			"alive": Kin.alive(st, c), "actions": acts, "bribe_gold": bribe_gold(sim, c),
			"cross_reason": cross_status(sim, actor, trial_id, c)})
	var until := int(t["prep_until"]) if str(t["status"]) == "preparation" else int(t["hearing_until"])
	return {"trial": t, "scale": sc, "proofs_hidden": hidden, "witnesses": ws, "accuser_name": _accuser_name(sim, t),
		"accused_name": str(st.characters.get(str(t["accused"]), {}).get("name", "")),
		"minutes_left": maxi(0, until - _now(sim)), "rest_reason": hearing_status(sim, actor, trial_id),
		"judge": str(st.characters.get(str((Offices.holders(sim, "judge") + [""])[0]), {}).get("name", "")),
		"rhetoric": {"accused": SkillCheck.stat(sim, str(t["accused"]), "rhetoric"), "accuser": SkillCheck.stat(sim,
			str(t["accuser"]), "rhetoric") if str(t["accuser"]) != "" else int(cfg(sim).get("trial", {}).get("town_rhetoric", 5))},
		"reputation": Reputation.of(st, str(t["family"])),
		"verdict_reason": verdict_status(sim, actor, trial_id, "guilty")}
