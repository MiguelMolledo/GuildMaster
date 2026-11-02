class_name Elections
extends RefCounted
## Elections (GDD 4.12.4, ap. A; docs/contratos/h10_cargos.md). An office votes at the year change when the term of
## a seat ends then (or a seat is vacant). Registering (run_for_office, a management order from the chart) is open in
## the last year of the term until winter starts; the campaign is that winter, the last season of the term
## (campaign_action, in person: visit, bribe, speech, defame). The vote is deterministic: every townsperson of a family
## titled to vote scores each candidate (relation, reputation, class modifier, campaign) and votes the best one; the
## most voted take the seats (Offices.take). The outgoing holder is a candidate by itself (basic level); with no more
## candidates than seats there is no vote. state.elections: [{id, office, day, campaign_day, status, candidates,
## result}]; bonuses in per mille, never floats in the state.


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.politics.get("elections", {})


static func _now(sim: Sim) -> int:
	return int(sim.state.clock["minute"])


## The open election of `office` ({} if none).
static func open_election(st: WorldState, office: String) -> Dictionary:
	for el: Dictionary in st.elections:
		if str(el.get("office", "")) == office and str(el.get("status", "")) == "open":
			return el
	return {}


## The open election and candidate record of `chr`: {election, candidate} or {}.
static func candidacy(st: WorldState, chr: String) -> Dictionary:
	for el: Dictionary in st.elections:
		if str(el.get("status", "")) != "open":
			continue
		for c: Dictionary in el.get("candidates", []):
			if str(c.get("character", "")) == chr:
				return {"election": el, "candidate": c}
	return {}


## The most recent closed election of `office` ({} if none).
static func last_result(st: WorldState, office: String) -> Dictionary:
	for i: int in range(st.elections.size() - 1, -1, -1):
		var el: Dictionary = st.elections[i]
		if str(el.get("office", "")) == office and str(el.get("status", "")) == "done":
			return el
	return {}


## Whether the campaign of `el` is on (from its campaign_day until the vote).
static func in_campaign(sim: Sim, el: Dictionary) -> bool:
	var d := Offices.today(sim)
	return not el.is_empty() and d >= int(el.get("campaign_day", 0)) and d < int(el.get("day", 0))


## The first title that opens the vote (unlocks.vote), "" if none.
static func vote_title(sim: Sim) -> String:
	for t: String in sim.catalog.title_ladder():
		if bool(sim.catalog.titles()[t].get("unlocks", {}).get("vote", false)):
			return t
	return ""


## Whether `chr` votes: alive, adult, not of a human family, its family's title opens the vote.
static func is_voter(sim: Sim, chr: String) -> bool:
	var st := sim.state
	var ch: Dictionary = st.characters.get(chr, {})
	if ch.is_empty() or not bool(ch.get("alive", true)) or not Kin.is_adult(sim, chr):
		return false
	var fam := str(ch.get("family", ""))
	if not st.families.has(fam) or str(st.families[fam].get("controlled_by", "")) == "human":
		return false
	var vt := vote_title(sim)
	return vt != "" and Titles.rank(sim, Titles.current(sim, fam)) >= Titles.rank(sim, vt)


## Every voter now, sorted (minus `exclude`).
static func voters(sim: Sim, exclude: Array = []) -> Array:
	var out: Array = []
	for id: Variant in sim.state.characters:
		var c := str(id)
		if not c in exclude and is_voter(sim, c):
			out.append(c)
	out.sort()
	return out


# --- Registering ------------------------------------------------------------------------------------------------------

## The refusal of run_for_office, "" if `actor` can run for `office` at `level` now.
static func run_status(sim: Sim, actor: String, office: String, level: String) -> String:
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
	if not sim.catalog.offices().has(office):
		return "unknown_office"
	if not Offices.title_allows(sim, fam, office):
		return "office_needs_title"
	var held := Offices.of_character(st, actor)
	if held != "" and held != office:
		return "holds_office"
	if not candidacy(st, actor).is_empty():
		return "already_candidate"
	var day := Offices.election_day(sim, office)
	if day < 0:
		return "no_election"
	if Offices.today(sim) >= day - int(sim.catalog.time.get("days_per_season", 2)):
		return "registration_closed"
	var lv: Dictionary = cfg(sim).get("levels", {}).get(level, {})
	if lv.is_empty():
		return "unknown_level"
	if not Money.can_pay(st, fam, int(lv.get("gold", 0))):
		return "not_enough_gold"
	return ""


## {"type": "run_for_office", "actor", "office", "level"}: registers as a candidate (GDD 4.12.4; management). Pays the
## level (ledger politics) and creates the office's election if it was not open. Reasons: see run_status.
static func order_run(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var office := str(o.get("office", ""))
	var level := str(o.get("level", "basic"))
	var why := run_status(sim, actor, office, level)
	if why != "":
		if OS.is_debug_build():
			print("[Elections] %s no puede presentarse a %s (%s): %s" % [actor, office, level, why])
		return Orders.fail(why)
	var st := sim.state
	var fam := str(st.characters[actor]["family"])
	var gold := int(cfg(sim)["levels"][level].get("gold", 0))
	if not Money.change(sim, fam, -gold, Money.POLITICS, "campaign_" + office, "", actor):
		return Orders.fail("not_enough_gold")
	var el := _ensure(sim, office)
	(el["candidates"] as Array).append(_candidate(sim, actor, level, false))
	sim.events.append({"type": "office_candidate", "election": str(el["id"]), "office": office, "character": actor,
		"family": fam, "level": level})
	var params := {"name": str(st.characters[actor].get("name", "")), "family": str(st.families[fam].get("name", "")),
		"office": office, "day": int(el["day"]) + 1, "campaign_day": int(el["campaign_day"]) + 1}
	if str(st.families[fam].get("controlled_by", "")) == "human":
		Notices.add(sim, fam, Notices.INFO, "notice.office_candidate", params, actor)
	elif str(st.families[fam].get("ai_profile", "")) != "":
		for f: String in Offices._humans(st):
			Notices.add(sim, f, Notices.INFO, "notice.rival_candidate", params, actor)
	if OS.is_debug_build():
		print("[Elections] %s (%s) se presenta a %s (%s, %d de oro); votación el día %d, campaña desde el %d" % [actor,
			fam, office, level, gold, int(el["day"]), int(el["campaign_day"])])
	return Orders.ok()


static func _ensure(sim: Sim, office: String) -> Dictionary:
	var el := open_election(sim.state, office)
	if not el.is_empty():
		return el
	var day := Offices.election_day(sim, office)
	el = {"id": Ids.next(sim.state, "ele"), "office": office, "day": day,
		"campaign_day": day - int(sim.catalog.time.get("days_per_season", 2)), "status": "open", "candidates": [],
		"result": {}}
	sim.state.elections.append(el)
	return el


static func _candidate(sim: Sim, chr: String, level: String, incumbent: bool) -> Dictionary:
	return {"character": chr, "family": str(sim.state.characters[chr].get("family", "")), "level": level,
		"incumbent": incumbent, "minute": _now(sim), "support": {}, "smear": 0, "secured": [], "busy_until": 0,
		"done": {}}


# --- Campaign ---------------------------------------------------------------------------------------------------------

const ACTIONS: Array[String] = ["visit", "bribe", "speech", "defame"]


## The refusal of campaign_action, "" if it would be done now.
static func action_status(sim: Sim, actor: String, kind: String, target: String) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not Kin.alive(st, actor):
		return "dead"
	if not kind in ACTIONS:
		return "unknown_campaign_action"
	var cc := candidacy(st, actor)
	if cc.is_empty():
		return "not_candidate"
	var el: Dictionary = cc["election"]
	var cand: Dictionary = cc["candidate"]
	if not in_campaign(sim, el):
		return "campaign_not_started"
	if int(cand.get("busy_until", 0)) > _now(sim):
		return "campaign_busy"
	var a: Dictionary = cfg(sim).get("actions", {}).get(kind, {})
	match kind:
		"visit", "bribe":
			if not st.characters.has(target) or not Kin.alive(st, target):
				return "unknown_target"
			if str(st.characters[target].get("family", "")) == str(st.characters[actor].get("family", "")):
				return "bad_args"
			if kind == "bribe":
				if not is_voter(sim, target):
					return "not_a_voter"
				if target in (cand.get("secured", []) as Array):
					return "already_bribed"
				if not Money.can_pay(st, str(st.characters[actor].get("family", "")), int(a.get("gold", 20))):
					return "not_enough_gold"
			if not NpcActions.in_range(sim, actor, target):
				return "too_far"
		"speech":
			if str(st.characters[actor].get("location", "")) != "":
				return "indoors"
			if int(cand.get("done", {}).get("speech", -1)) == Offices.today(sim):
				return "already_today"
		"defame":
			var other := _candidate_in(el, target)
			if target == actor or other.is_empty():
				return "not_a_candidate"
			if int(cand.get("done", {}).get("defame", -1)) == Offices.today(sim):
				return "already_today"
	return ""


static func _candidate_in(el: Dictionary, chr: String) -> Dictionary:
	for c: Dictionary in el.get("candidates", []):
		if str(c.get("character", "")) == chr:
			return c
	return {}


## {"type": "campaign_action", "actor", "kind", "target"}: an action of the campaign (GDD 4.12.4), in person.
## visit: +relation with every adult of the target's family, busy busy_hours; bribe: gold (politics), the target's
## vote secured, stealth vs empathy (failure: scandal reputation); speech: rhetoric vs target_value, success: bonus
## with the voters within range_tiles; defame: stealth vs target_value + modifier, success: the other candidate loses
## penalty_permil, failure: scandal reputation. Reasons: see action_status.
static func order_campaign(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var kind := str(o.get("kind", ""))
	var target := str(o.get("target", ""))
	var why := action_status(sim, actor, kind, target)
	if why != "":
		if OS.is_debug_build():
			print("[Elections] %s no puede hacer campaña (%s -> %s): %s" % [actor, kind, target, why])
		return Orders.fail(why)
	var st := sim.state
	var cc := candidacy(st, actor)
	var el: Dictionary = cc["election"]
	var cand: Dictionary = cc["candidate"]
	var a: Dictionary = cfg(sim).get("actions", {}).get(kind, {})
	var fam := str(st.characters[actor].get("family", ""))
	var today := Offices.today(sim)
	var ok := true
	match kind:
		"visit":
			var tf := str(st.characters[target].get("family", ""))
			for m: Variant in st.families.get(tf, {}).get("members", []):
				if Kin.alive(st, str(m)) and Kin.is_adult(sim, str(m)):
					Emotions.change_relation(sim, actor, str(m), int(a.get("relation", 5)), "campaign_visit")
			cand["busy_until"] = _now(sim) + roundi(float(a.get("busy_hours", 4)) * 60.0)
		"bribe":
			Money.change(sim, fam, -int(a.get("gold", 20)), Money.POLITICS, "bribe_" + str(el["office"]), "", actor)
			(cand["secured"] as Array).append(target)
			var r := SkillCheck.roll(sim, "bribe|%s|%s|%d" % [actor, target, today], SkillCheck.stat(sim, actor, "stealth"),
				SkillCheck.stat(sim, target, "empathy"))
			ok = bool(r["success"])
			if not ok:
				Reputation.change(sim, fam, int(a.get("scandal", -10)), "bribe_scandal")
				Tribunal.add_fact(sim, "bribe_scandal", fam, actor)  # H11: a public fact that can be taken to court
		"speech":
			var r := SkillCheck.roll(sim, "speech|%s|%d" % [actor, today], SkillCheck.stat(sim, actor, "rhetoric"),
				int(a.get("target_value", 5)))
			ok = bool(r["success"])
			cand["done"]["speech"] = today
			if ok:
				var pa: Array = st.characters[actor].get("position", [0, 0])
				var rng := int(a.get("range_tiles", 6))
				for v: String in voters(sim, [actor]):
					var cv: Dictionary = st.characters[v]
					if str(cv.get("location", "")) != "":
						continue
					var pv: Array = cv.get("position", [0, 0])
					if maxi(absi(int(pv[0]) - int(pa[0])), absi(int(pv[1]) - int(pa[1]))) <= rng:
						cand["support"][v] = int(cand["support"].get(v, 0)) + int(a.get("bonus_permil", 100))
		"defame":
			var r := SkillCheck.roll(sim, "defame|%s|%s|%d" % [actor, target, today], SkillCheck.stat(sim, actor, "stealth"),
				int(a.get("target_value", 5)), int(a.get("modifier", -20)))
			ok = bool(r["success"])
			cand["done"]["defame"] = today
			if ok:
				var other := _candidate_in(el, target)
				other["smear"] = int(other.get("smear", 0)) + int(a.get("penalty_permil", 100))
			else:
				Reputation.change(sim, fam, int(a.get("scandal", -20)), "defame_scandal")
	sim.events.append({"type": "campaign_action", "election": str(el["id"]), "actor": actor, "kind": kind,
		"target": target, "ok": ok})
	if OS.is_debug_build():
		print("[Elections] %s hace campaña: %s -> %s (%s)" % [actor, kind, target, "bien" if ok else "mal"])
	return Orders.ok()


## The campaign `actor` is in, for the UI: {} or {election, office, day, campaign_day, on, days_left, candidates:
## [{character, name, family, level, incumbent}]}.
static func campaign_of(sim: Sim, actor: String) -> Dictionary:
	var cc := candidacy(sim.state, actor)
	if cc.is_empty():
		return {}
	var el: Dictionary = cc["election"]
	var out := {"election": str(el["id"]), "office": str(el["office"]), "day": int(el["day"]),
		"campaign_day": int(el["campaign_day"]), "on": in_campaign(sim, el),
		"days_left": int(el["day"]) - Offices.today(sim), "candidates": []}
	for c: Dictionary in el.get("candidates", []):
		var ch: Dictionary = sim.state.characters.get(str(c["character"]), {})
		(out["candidates"] as Array).append({"character": str(c["character"]), "name": str(ch.get("name", "")),
			"family": str(c.get("family", "")), "level": str(c.get("level", "")), "incumbent": bool(c.get("incumbent", false))})
	return out


## At the start of winter: the human candidates of the elections whose campaign starts today get a notice.
static func campaign_started(sim: Sim) -> void:
	var st := sim.state
	var d := Offices.today(sim)
	for el: Dictionary in st.elections:
		if str(el.get("status", "")) != "open" or int(el.get("campaign_day", -1)) != d:
			continue
		for c: Dictionary in el.get("candidates", []):
			var fam := str(st.characters.get(str(c["character"]), {}).get("family", ""))
			if str(st.families.get(fam, {}).get("controlled_by", "")) == "human":
				Notices.add(sim, fam, Notices.INFO, "notice.campaign_started", {"office": str(el["office"]),
					"day": int(el["day"]) + 1, "name": str(st.characters[str(c["character"])].get("name", ""))},
					str(c["character"]))


# --- The vote ---------------------------------------------------------------------------------------------------------

## The year change for `office`: the seats `due` (term ended or vacant) are voted. Candidates = the registered ones
## that still can (alive, adult, title) + the outgoing holders of those seats (basic level). With no more candidates
## than seats nobody votes; else every voter scores them and votes the best. Winners keep (incumbents) or take the
## seats; the rest of the due seats are left vacant until the next year change. The election closes (election_held).
static func resolve(sim: Sim, office: String, due: Array) -> void:
	var st := sim.state
	var today := Offices.today(sim)
	var el := open_election(st, office)
	var cands: Array = []
	for c: Dictionary in el.get("candidates", []):
		if _can_stand(sim, str(c["character"]), office):
			cands.append(c)
	var ss: Array = Offices.seats(sim, office)
	for i: int in due:
		var h := str(ss[i].get("holder", ""))
		if h != "" and _can_stand(sim, h, office) and _candidate_in({"candidates": cands}, h).is_empty():
			cands.append(_candidate(sim, h, "basic", true))
			if not el.is_empty():
				(el["candidates"] as Array).append(cands[cands.size() - 1])
	var n_seats := due.size()
	var votes: Dictionary = {}
	var unopposed := cands.size() <= n_seats
	var n_voters := 0
	if not unopposed:
		var ids: Array = []
		for c: Dictionary in cands:
			ids.append(str(c["character"]))
			votes[str(c["character"])] = 0
		for v: String in voters(sim, ids):
			var pick := _choice(sim, cands, v)
			if pick != "":
				votes[pick] = int(votes[pick]) + 1
				n_voters += 1
	var order := cands.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _before(sim, votes, a, b))
	var winners: Array = []
	for c: Dictionary in order:
		if winners.size() < n_seats:
			winners.append(str(c["character"]))
	_seat(sim, office, due, winners, cands)
	var by_family: Dictionary = {}
	for c: Dictionary in cands:
		by_family[str(c.get("family", ""))] = int(by_family.get(str(c.get("family", "")), 0)) + int(votes.get(str(c["character"]), 0))
	if el.is_empty() and not cands.is_empty():
		el = {"id": Ids.next(st, "ele"), "office": office, "day": today, "campaign_day": today - int(sim.catalog.time.get(
			"days_per_season", 2)), "status": "open", "candidates": cands, "result": {}}
		st.elections.append(el)
	if not el.is_empty():
		el["status"] = "done"
		el["result"] = {"votes": votes, "winners": winners, "voters": n_voters, "unopposed": unopposed,
			"by_family": by_family}
		sim.events.append({"type": "election_held", "election": str(el["id"]), "office": office, "winners": winners,
			"votes": votes.duplicate(), "unopposed": unopposed})
		_trim(sim)
	if OS.is_debug_build():
		print("[Elections] %s, día %d: %d candidatos, %d votantes, votos %s -> %s%s" % [office, today, cands.size(),
			n_voters, votes, winners, " (sin rival)" if unopposed else ""])


static func _can_stand(sim: Sim, chr: String, office: String) -> bool:
	var st := sim.state
	if not Kin.alive(st, chr) or not Kin.is_adult(sim, chr):
		return false
	var held := Offices.of_character(st, chr)
	if held != "" and held != office:
		return false
	return Offices.title_allows(sim, str(st.characters[chr].get("family", "")), office)


## The order of the candidates: more votes, then more reputation, then id.
static func _before(sim: Sim, votes: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	var va := int(votes.get(str(a["character"]), 0))
	var vb := int(votes.get(str(b["character"]), 0))
	if va != vb:
		return va > vb
	var ra := Reputation.of(sim.state, str(a.get("family", "")))
	var rb := Reputation.of(sim.state, str(b.get("family", "")))
	if ra != rb:
		return ra > rb
	return str(a["character"]) < str(b["character"])


## Who `voter` votes among `cands` ("" = abstains): a secured vote (bribe) first; never a candidate whose family it
## feels an `against` emotion for; among the ones it feels a `favor` emotion for, if any; the best score, then more
## reputation, then id.
static func _choice(sim: Sim, cands: Array, voter: String) -> String:
	var v: Dictionary = cfg(sim).get("vote", {})
	var allowed: Array = []
	var favored: Array = []
	var secured: Array = []
	for c: Dictionary in cands:
		var fam := str(c.get("family", ""))
		if voter in (c.get("secured", []) as Array):
			secured.append(c)
		var against := false
		for e: String in v.get("against", []):
			if Emotions.has(sim, voter, e, fam):
				against = true
		if against:
			continue
		allowed.append(c)
		for e: String in v.get("favor", []):
			if Emotions.has(sim, voter, e, fam):
				favored.append(c)
				break
	var pool := secured if not secured.is_empty() else (favored if not favored.is_empty() else allowed)
	var best := ""
	var best_s := -INF
	var best_rep := 0
	for c: Dictionary in pool:
		var sc := score(sim, c, voter)
		var rep := Reputation.of(sim.state, str(c.get("family", "")))
		var id := str(c["character"])
		if best == "" or sc > best_s + 0.000001 or (absf(sc - best_s) <= 0.000001 and (rep > best_rep
				or (rep == best_rep and id < best))):
			best = id
			best_s = sc
			best_rep = rep
	return best


## ap. A: affinity × 0,3 + normalised reputation × 0,3 + class modifier × 0,2 + campaign × 0,2, each term in -1..1.
## Affinity = the H7 relation between voter and candidate; class modifier = the family's reputation with the voter's
## class (with its offices' passives) minus its global reputation; campaign = level + speech − defamation, per mille.
static func score(sim: Sim, cand: Dictionary, voter: String) -> float:
	var v: Dictionary = cfg(sim).get("vote", {})
	var st := sim.state
	var chr := str(cand["character"])
	var fam := str(cand.get("family", ""))
	var rel := _norm(Emotions.relation(st, voter, chr), float(v.get("relation_norm", 100)))
	var rep_v := Reputation.of(st, fam)
	var rep := _norm(rep_v, float(v.get("reputation_norm", 200)))
	var cls := str(st.characters[voter].get("class", "artisan"))
	var cm := _norm(Offices.reputation_with_class(sim, fam, cls) - rep_v, float(v.get("class_norm", 50)))
	var lv := int(cfg(sim).get("levels", {}).get(str(cand.get("level", "basic")), {}).get("bonus_permil", 0))
	var camp := _norm(lv + int(cand.get("support", {}).get(voter, 0)) - int(cand.get("smear", 0)),
		float(v.get("campaign_norm", 300)))
	return float(v.get("affinity", 0.3)) * rel + float(v.get("reputation", 0.3)) * rep + float(v.get("class", 0.2)) * cm \
		+ float(v.get("campaign", 0.2)) * camp


static func _norm(x: int, by: float) -> float:
	return clampf(float(x) / maxf(1.0, by), -1.0, 1.0)


## The winners into the due seats: an incumbent who wins keeps its seat (a new term); the others take the remaining
## due seats in order; whoever held a due seat and did not win leaves it (lost if it stood, else term).
static func _seat(sim: Sim, office: String, due: Array, winners: Array, cands: Array) -> void:
	var st := sim.state
	var ss: Array = Offices.seats(sim, office)
	var dpy := Offices.days_per_year(sim)
	var term := int(sim.catalog.offices()[office].get("term_years", 1)) * dpy
	var free: Array = []
	var placed: Array = []
	for i: int in due:
		var h := str(ss[i].get("holder", ""))
		if h != "" and h in winners and Kin.alive(st, h):
			ss[i]["until"] = Offices.today(sim) + term
			placed.append(h)
			if OS.is_debug_build():
				print("[Offices] %s sigue en %s hasta el día %d" % [h, office, int(ss[i]["until"])])
		else:
			free.append(i)
	for i: int in free:
		var h := str(ss[i].get("holder", ""))
		if h != "":
			var stood := not _candidate_in({"candidates": cands}, h).is_empty()
			Offices.leave(sim, office, i, "lost" if stood else ("died" if not Kin.alive(st, h) else "term"))
	var k := 0
	for w: String in winners:
		if w in placed:
			continue
		if k >= free.size():
			break
		Offices.take(sim, office, int(free[k]), w)
		k += 1
	while k < free.size():
		ss[int(free[k])]["until"] = Offices.today(sim) + dpy
		k += 1


static func _trim(sim: Sim) -> void:
	var keep := int(cfg(sim).get("keep", 12))
	var done := 0
	for el: Dictionary in sim.state.elections:
		if str(el.get("status", "")) == "done":
			done += 1
	while done > keep:
		for i: int in sim.state.elections.size():
			if str(sim.state.elections[i].get("status", "")) == "done":
				sim.state.elections.remove_at(i)
				done -= 1
				break
