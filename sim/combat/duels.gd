class_name Duels
extends RefCounted
## Duels of honour in the game (docs/gdd/04e_combate.md §4e.3-§4e.5, decisions O-C1..O-C12 of 2026-11-04; figures:
## data/combat.json "challenge", "ai_answer", "consequences"). The lance rules are CombatRules / Duel; this system
## keeps the duels of the town in state.duels (save v15) and runs their life:
##   pending  -> the challenge is made (duel_challenge); the challenged answers before the next dawn (duel_answer).
##               NPCs answer at once (O-C7 b: they never challenge). No answer by then = refused.
##   accepted -> the duel is at `hour` of the day after accepting, at the map's duel ground (or the plaza); call_before
##               minutes before, both are sent there (move_to, like a routine: the player may change it).
##   fighting -> at the hour, whoever is not there loses by no-show. With both there: a duel without anybody of a
##               human family is played by the AI at once (Duel.auto); with one, it waits for the orders duel_move
##               (one lance each) or duel_auto («Resolver sin jugar»), at most fight_timeout minutes.
##   closed   -> the consequences (§4e.5): reputation as honour, relation, courtship affinity, the end of the offense,
##               a chronicle fact and notices; the record goes to state.duels.closed (cooldowns, the book).
## duel_brawl fights at once outside the rules: no honour, a public brawl fact when somebody saw it.
## Orders (Orders.apply): duel_challenge {actor, target, cause, kind}, duel_answer {actor, duel, answer accept|refuse},
## duel_withdraw {actor, duel}, duel_move {actor, duel, action}, duel_auto {actor, duel}, duel_brawl {actor, target}.
## Deterministic: the lance rolls are keyed by (world seed, duel id, lance) and the NPC's estimate by (duel id, sample):
## nothing here touches state.rng. Contract: docs/contratos/duelo.md.

const PENDING: String = "pending"
const ACCEPTED: String = "accepted"
const FIGHTING: String = "fighting"


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.combat.get("challenge", {})


static func _cons(sim: Sim) -> Dictionary:
	return sim.catalog.combat.get("consequences", {})


static func _now(sim: Sim) -> int:
	return int(sim.state.clock["minute"])


## state.duels with its two lists (a state from before v15 gets them).
static func book(st: WorldState) -> Dictionary:
	if not st.duels.get("open") is Dictionary:
		st.duels["open"] = {}
	if not st.duels.get("closed") is Array:
		st.duels["closed"] = []
	return st.duels


static func open_duels(st: WorldState) -> Dictionary:
	return book(st)["open"]


static func duel_of(st: WorldState, id: String) -> Dictionary:
	var o: Dictionary = open_duels(st)
	if o.has(id):
		return o[id]
	for r: Dictionary in book(st)["closed"]:
		if str(r.get("id", "")) == id:
			return r
	return {}


## The open duel `chr` is in ({} if none).
static func of_character(st: WorldState, chr: String) -> Dictionary:
	var o: Dictionary = open_duels(st)
	var ids: Array = o.keys()
	ids.sort()
	for id: String in ids:
		var r: Dictionary = o[id]
		if str(r["challenger"]) == chr or str(r["challenged"]) == chr:
			return r
	return {}


## Whether `chr` is held by a duel: from the call to the ground until it closes. The systems' orders (rival AI,
## family AI, routines, directives, townsfolk) are not given to them meanwhile (Sim.give and Sim.step); the player's own
## orders are (going elsewhere is not showing up). The duel's own orders carry "by_duel": true.
static func holds(st: WorldState, chr: String) -> bool:
	if not st.duels.get("open") is Dictionary or (st.duels["open"] as Dictionary).is_empty():
		return false
	var r := of_character(st, chr)
	return not r.is_empty() and (str(r["status"]) == FIGHTING or (str(r["status"]) == ACCEPTED and bool(r["called"])))


## The open duels of a family's people, sorted by id.
static func of_family(st: WorldState, fam: String) -> Array:
	var out: Array = []
	var o: Dictionary = open_duels(st)
	var ids: Array = o.keys()
	ids.sort()
	for id: String in ids:
		var r: Dictionary = o[id]
		if str(r["challenger_family"]) == fam or str(r["challenged_family"]) == fam:
			out.append(r)
	return out


static func _fam(st: WorldState, chr: String) -> String:
	return str(st.characters.get(chr, {}).get("family", ""))


static func _human(st: WorldState, fam: String) -> bool:
	return str(st.families.get(fam, {}).get("controlled_by", "")) == "human"


## A fighter for the lance rules from a character: stats, weapon (a weapons id; "" = what it has equipped) and armour.
static func fighter_of(sim: Sim, chr: String, weapon: String = "") -> Dictionary:
	var combat: Dictionary = sim.catalog.combat
	var ch: Dictionary = sim.state.characters.get(chr, {})
	var eq: Dictionary = ch.get("equipment", {}) if ch.get("equipment") is Dictionary else {}
	var w := weapon if weapon != "" else CombatRules.weapon_for(combat, eq)
	var wounded := false
	var h: Variant = ch.get("health")
	if h is Dictionary:  # 4.22.3.3 (v17): nobody has it today
		wounded = int((h as Dictionary).get("wounded_until", -1)) > _now(sim)
	return CombatRules.fighter(chr, ch.get("stats", {}), w, CombatRules.armored(combat, eq), wounded)


## O-C5: the challenged chooses the weapons among the ones both carry (weapons_order: the first both have).
static func weapons_for(sim: Sim, a: String, b: String) -> String:
	var combat: Dictionary = sim.catalog.combat
	var wa := str(fighter_of(sim, a)["weapon"])
	var wb := str(fighter_of(sim, b)["weapon"])
	for w: String in cfg(sim).get("weapons_order", ["sword", "tool", "fists"]):
		if wa == w and wb == w:
			return w
	return "fists" if (combat.get("weapons", {}) as Dictionary).has("fists") else wa


# --- causes and checks ---------------------------------------------------------------------------------------------

## The causes `actor` has now to challenge `target`: [{cause, about}] in the order of data causes.
static func causes(sim: Sim, actor: String, target: String) -> Array:
	var out: Array = []
	var st := sim.state
	if not st.characters.has(actor) or not st.characters.has(target):
		return out
	var c := cfg(sim)
	for cause: String in c.get("causes", []):
		match cause:
			"offense":
				if _offended(sim, _fam(st, actor), _fam(st, target)):
					out.append({"cause": cause, "about": ""})
			"courtship":
				var who := courted_by_both(sim, actor, target)
				if who != "":
					out.append({"cause": cause, "about": who})
			"rivalry":
				if trade_rivals(sim, _fam(st, actor), _fam(st, target)):
					out.append({"cause": cause, "about": ""})
	return out


## Whether an adult of family `fam` holds an offense state (an insult, a threat: H7) towards family `other`.
static func _offended(sim: Sim, fam: String, other: String) -> bool:
	if fam == "" or other == "":
		return false
	var states: Array = cfg(sim).get("offense_states", ["offended", "angry"])
	var members: Array = sim.state.families.get(fam, {}).get("members", [])
	for m: String in members:
		if not Kin.alive(sim.state, m):
			continue
		for e: Dictionary in Emotions.active(sim, m, other):
			if str(e.get("state", "")) in states:
				return true
	return false


## The single adult both court with affinity >= courtship_min_affinity (the highest of the two lower ones; "" none).
static func courted_by_both(sim: Sim, a: String, b: String) -> String:
	var st := sim.state
	var min_aff := int(cfg(sim).get("courtship_min_affinity", 40))
	var best := ""
	var best_v := -1
	var ids: Array = st.characters.keys()
	ids.sort()
	for x: String in ids:
		if x == a or x == b or not Kin.alive(st, x) or not Kin.is_single(st, x) or not Kin.is_adult(sim, x):
			continue
		var v := mini(Courtship.affinity(st, a, x), Courtship.affinity(st, b, x))
		if v >= min_aff and v > best_v:
			best = x
			best_v = v
	return best


## Whether two families own a building of the same type (the rival of the trade, 4.5.5).
static func trade_rivals(sim: Sim, fa: String, fb: String) -> bool:
	if fa == "" or fb == "" or fa == fb:
		return false
	var types := {}
	for id: String in sim.state.buildings:
		var b: Dictionary = sim.state.buildings[id]
		if str(b.get("owner", "")) == fa:
			types[str(b.get("type", ""))] = true
	for id: String in sim.state.buildings:
		var b: Dictionary = sim.state.buildings[id]
		if str(b.get("owner", "")) == fb and types.has(str(b.get("type", ""))):
			return true
	return false


## Why `actor` cannot challenge `target` for `cause` with `kind` now ("" if it can; "" cause = any cause it has).
## Order of the checks: who they are, age, wounds, an open duel, the cooldown, the kind, the cause, the distance.
static func challenge_status(sim: Sim, actor: String, target: String, cause: String = "", kind: String = "first_blood",
		check_range: bool = true) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not st.characters.has(target) or actor == target:
		return "unknown_target"
	if not Kin.alive(st, actor) or not Kin.alive(st, target):
		return "dead"
	if _fam(st, actor) == "" or _fam(st, actor) == _fam(st, target):
		return "same_family"
	var c := cfg(sim)
	var min_age := int(c.get("min_age", 16))
	if Kin.age(sim, actor) < min_age or Kin.age(sim, target) < min_age:
		return "too_young"
	if bool(fighter_of(sim, actor)["wounded"]) or bool(fighter_of(sim, target)["wounded"]):
		return "wounded"
	if not of_character(st, actor).is_empty() or not of_character(st, target).is_empty():
		return "busy"
	if on_cooldown(sim, actor, target):
		return "cooldown"
	var k: Dictionary = (sim.catalog.combat.get("kinds", {}) as Dictionary).get(kind, {})
	if k.is_empty() or bool(k.get("locked", false)) or not kind in (c.get("kinds_allowed", ["first_blood"]) as Array):
		return "kind_locked"
	var have := causes(sim, actor, target)
	if have.is_empty():
		return "no_cause"
	if cause != "" and not have.any(func(x: Dictionary) -> bool: return str(x["cause"]) == cause):
		return "no_cause"
	if check_range and not NpcActions.in_range(sim, actor, target):
		return "too_far"
	return ""


## Whether the pair closed a duel less than cooldown_days ago.
static func on_cooldown(sim: Sim, a: String, b: String) -> bool:
	var span := int(cfg(sim).get("cooldown_days", 2)) * Clock.MINUTES_PER_DAY
	var now := _now(sim)
	for r: Dictionary in book(sim.state)["closed"]:
		var pair := [str(r["challenger"]), str(r["challenged"])]
		if a in pair and b in pair and now - int(r.get("closed_at", -span)) < span:
			return true
	return false


# --- orders --------------------------------------------------------------------------------------------------------

static func order_challenge(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var cause := str(o.get("cause", ""))
	var kind := str(o.get("kind", "first_blood"))
	var why := challenge_status(sim, actor, target, cause, kind)
	if why != "":
		return Orders.fail(why)
	var have := causes(sim, actor, target)
	var pick: Dictionary = have[0]
	for x: Dictionary in have:
		if str(x["cause"]) == cause:
			pick = x
	var c := cfg(sim)
	var now := _now(sim)
	var id := Ids.next(st, "duel")
	var rec := {"id": id, "challenger": actor, "challenged": target, "challenger_family": _fam(st, actor),
		"challenged_family": _fam(st, target), "cause": str(pick["cause"]), "about": str(pick["about"]), "kind": kind,
		"status": PENDING, "created": now, "answer_by": _next_at(now, int(c.get("answer_hour", 360))), "at": -1,
		"place": [], "weapon": "", "challenge_witnesses": witnesses(sim, actor, int(c.get("witness_tiles", 8))).size(),
		"witnesses": [], "called": false, "started": -1, "duel": {}, "player_side": -1}
	open_duels(st)[id] = rec
	sim.events.append({"type": "duel_challenged", "duel": id, "actor": actor, "target": target,
		"family": rec["challenger_family"], "target_family": rec["challenged_family"], "cause": rec["cause"],
		"about": rec["about"], "kind": kind})
	for fam: String in [str(rec["challenged_family"])]:
		if _human(st, fam):
			Notices.add(sim, fam, Notices.URGENT, "notice.duel_challenged", {"rival": _name(st, actor),
				"cause": rec["cause"]}, actor)
	_log("%s reta a %s (%s%s, %s, testigos del reto %d)" % [actor, target, rec["cause"],
		"" if str(rec["about"]) == "" else " por " + str(rec["about"]), kind, int(rec["challenge_witnesses"])])
	return Orders.ok()


static func order_answer(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var rec: Dictionary = open_duels(st).get(str(o.get("duel", "")), {})
	if rec.is_empty():
		return Orders.fail("unknown_duel")
	if str(rec["challenged"]) != actor:
		return Orders.fail("not_challenged")
	if str(rec["status"]) != PENDING:
		return Orders.fail("already_answered")
	var answer := str(o.get("answer", ""))
	if not answer in ["accept", "refuse"]:
		return Orders.fail("bad_answer")
	_answered(sim, rec, answer)
	return Orders.ok()


static func order_withdraw(sim: Sim, o: Dictionary) -> Dictionary:
	var rec: Dictionary = open_duels(sim.state).get(str(o.get("duel", "")), {})
	if rec.is_empty():
		return Orders.fail("unknown_duel")
	if str(rec["challenger"]) != str(o.get("actor", "")):
		return Orders.fail("not_challenger")
	if str(rec["status"]) == FIGHTING:
		return Orders.fail("already_fighting")
	_close(sim, rec, "withdrawn", -1)
	return Orders.ok()


## One lance of the side the player's family plays.
static func order_move(sim: Sim, o: Dictionary) -> Dictionary:
	var r := _fighting(sim, o)
	if not bool(r["ok"]):
		return r
	var rec: Dictionary = r["rec"]
	var du := Duel.wrap(sim.catalog.combat, rec["duel"])
	var res := du.choose(int(rec["player_side"]), str(o.get("action", "")))
	if not bool(res["ok"]):
		return Orders.fail(str(res["reason"]))
	sim.events.append({"type": "duel_lance", "duel": rec["id"], "family": _side_family(rec, int(rec["player_side"])),
		"lances": du.lances_log().size()})
	if du.over():
		_finish(sim, rec)
	return Orders.ok()


## «Resolver sin jugar»: the AI plays the rest of the player's side.
static func order_auto(sim: Sim, o: Dictionary) -> Dictionary:
	var r := _fighting(sim, o)
	if not bool(r["ok"]):
		return r
	var rec: Dictionary = r["rec"]
	Duel.wrap(sim.catalog.combat, rec["duel"]).auto_finish()
	_finish(sim, rec)
	return Orders.ok()


static func _fighting(sim: Sim, o: Dictionary) -> Dictionary:
	var rec: Dictionary = open_duels(sim.state).get(str(o.get("duel", "")), {})
	if rec.is_empty():
		return {"ok": false, "reason": "unknown_duel"}
	if str(rec["status"]) != FIGHTING or int(rec["player_side"]) < 0:
		return {"ok": false, "reason": "not_fighting"}
	var me := str(rec["challenger"]) if int(rec["player_side"]) == 0 else str(rec["challenged"])
	if str(o.get("actor", "")) != me:
		return {"ok": false, "reason": "not_your_side"}
	return {"ok": true, "reason": "", "rec": rec}


## Why `actor` cannot fight `target` here and now outside the rules ("" if it can).
static func brawl_status(sim: Sim, actor: String, target: String) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not st.characters.has(target) or actor == target or not Kin.alive(st, target):
		return "unknown_target"
	if _fam(st, actor) == _fam(st, target):
		return "same_family"
	var min_age := int(cfg(sim).get("min_age", 16))
	if Kin.age(sim, actor) < min_age or Kin.age(sim, target) < min_age:
		return "too_young"
	if not of_character(st, actor).is_empty() or not of_character(st, target).is_empty():
		return "busy"
	if not NpcActions.in_range(sim, actor, target):
		return "too_far"
	return ""


## A fight right now, outside the rules (no challenge accepted): played by the AI, no honour, a brawl fact.
static func order_brawl(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var target := str(o.get("target", ""))
	var why := brawl_status(sim, actor, target)
	if why != "":
		return Orders.fail(why)
	var b: Dictionary = _cons(sim).get("brawl", {})
	var id := Ids.next(st, "duel")
	var seen := witnesses(sim, actor, int(cfg(sim).get("witness_tiles", 8)))
	seen.erase(target)
	var res := Duel.auto(sim.catalog.combat, id, st.world_seed, fighter_of(sim, actor), fighter_of(sim, target),
		"first_blood")
	var fam := _fam(st, actor)
	Reputation.change(sim, fam, int(b.get("reputation", -5)), "duel_brawl")
	Emotions.change_relation(sim, actor, target, int(b.get("relation", -15)), "duel_brawl")
	var fact := ""
	if not seen.is_empty():
		fact = Tribunal.add_fact(sim, "brawl", fam, actor, str(b.get("charge", "brawl")))
	var winner := actor if int(res["winner"]) == 0 else (target if int(res["winner"]) == 1 else "")
	Chronicle.add(st, "brawl", {"family": fam, "actor": actor, "target": target, "winner": winner, "fact": fact})
	sim.events.append({"type": "duel_brawl", "duel": id, "actor": actor, "target": target, "family": fam,
		"target_family": _fam(st, target), "winner": winner, "witnesses": seen.size(), "fact": fact})
	for f: String in [fam, _fam(st, target)]:
		if _human(st, f):
			Notices.add(sim, f, Notices.WARNING, "notice.duel_brawl", {"rival": _name(st, target if f == fam else actor),
				"result": "won" if winner != "" and _fam(st, winner) == f else ("draw" if winner == "" else "lost"),
				"witnesses": seen.size()}, target if f == fam else actor)
	_log("%s pelea con %s fuera de las reglas: gana %s, testigos %d%s" % [actor, target, winner if winner != "" else
		"nadie", seen.size(), (", hecho " + fact) if fact != "" else ""])
	return Orders.ok()


# --- the day of the duels ------------------------------------------------------------------------------------------

## Every minute, only over the open duels: the NPC answers, the deadline, the call to the ground, the start, the
## timeout of a played duel.
static func step(sim: Sim) -> void:
	var o: Dictionary = open_duels(sim.state)
	if o.is_empty():
		return
	var ids: Array = o.keys()
	ids.sort()
	var now := _now(sim)
	var c := cfg(sim)
	for id: String in ids:
		if not o.has(id):
			continue
		var rec: Dictionary = o[id]
		match str(rec["status"]):
			PENDING:
				if not _human(sim.state, str(rec["challenged_family"])):
					sim.give({"type": "duel_answer", "actor": rec["challenged"], "duel": id,
						"answer": ai_answer(sim, rec), "duel_ai": true})
				elif now >= int(rec["answer_by"]):
					_answered(sim, rec, "refuse")
			ACCEPTED:
				if not bool(rec["called"]) and now >= int(rec["at"]) - int(c.get("call_before", 30)):
					_call(sim, rec)
				if now >= int(rec["at"]):
					_start(sim, rec)
			FIGHTING:
				if now >= int(rec["started"]) + int(c.get("fight_timeout", 120)):
					Duel.wrap(sim.catalog.combat, rec["duel"]).auto_finish()
					_finish(sim, rec)


## The NPC's answer (O-C7 b, O-C8): refuse for free far above in title; accept with a fair chance (its risk aversion
## moves the bar), or a little under it when refusing would cost it reputation.
static func ai_answer(sim: Sim, rec: Dictionary) -> String:
	var a: Dictionary = sim.catalog.combat.get("ai_answer", {})
	var st := sim.state
	var gap := Titles.rank(sim, Titles.current(sim, str(rec["challenged_family"]))) \
		- Titles.rank(sim, Titles.current(sim, str(rec["challenger_family"])))
	if gap >= int(a.get("title_gap_free", 2)):
		return "refuse"
	var p := win_chance(sim, str(rec["challenged"]), str(rec["challenger"]), str(rec["id"]), str(rec["kind"]))
	var prof: Dictionary = sim.catalog.ai_profiles().get(str(st.families.get(str(rec["challenged_family"]), {}).get(
		"ai_profile", "")), {})
	var bar := float(a.get("accept_min", 0.4)) + (float(prof.get("risk_aversion", 0.5)) - 0.5) * float(a.get("risk_step", 0.4))
	var costly := int(rec.get("challenge_witnesses", 0)) > 0
	var answer := "accept" if p >= bar or (costly and p >= bar - float(a.get("near_miss", 0.1))) else "refuse"
	_log("%s estima %.2f de ganar contra %s (listón %.2f%s) -> %s" % [rec["challenged"], p, rec["challenger"], bar,
		", rechazar le costaría" if costly else "", answer])
	return answer


## The chance `chr` beats `other` (wins, not draws) in `samples` automatic duels keyed by `key`: the NPC's estimate.
static func win_chance(sim: Sim, chr: String, other: String, key: String, kind: String = "first_blood") -> float:
	var n := maxi(1, int(sim.catalog.combat.get("ai_answer", {}).get("samples", 40)))
	var w := weapons_for(sim, other, chr)
	var me := fighter_of(sim, chr, w)
	var them := fighter_of(sim, other, w)
	var wins := 0
	var was := Duel.verbose
	Duel.verbose = false
	for i: int in n:
		var r := Duel.auto(sim.catalog.combat, "%s|est|%d" % [key, i], sim.state.world_seed, them, me, kind)
		wins += int(int(r["winner"]) == 1)
	Duel.verbose = was
	return float(wins) / float(n)


static func _answered(sim: Sim, rec: Dictionary, answer: String) -> void:
	var st := sim.state
	sim.events.append({"type": "duel_answered", "duel": rec["id"], "answer": answer, "actor": rec["challenged"],
		"family": rec["challenger_family"], "target_family": rec["challenged_family"]})
	if answer == "refuse":
		_close(sim, rec, "refused", -1)
		return
	var c := cfg(sim)
	rec["status"] = ACCEPTED
	rec["at"] = _next_at(_now(sim), int(c.get("hour", 360)))
	rec["place"] = ground(sim)
	rec["weapon"] = weapons_for(sim, str(rec["challenger"]), str(rec["challenged"]))
	for fam: String in [str(rec["challenger_family"]), str(rec["challenged_family"])]:
		if _human(st, fam):
			var rival := str(rec["challenged"]) if fam == str(rec["challenger_family"]) else str(rec["challenger"])
			Notices.add(sim, fam, Notices.WARNING, "notice.duel_accepted", {"rival": _name(st, rival),
				"day": Clock.day(int(rec["at"])) + 1, "time": "%02d:%02d" % [Clock.hour(int(rec["at"])),
				Clock.minute_of_day(int(rec["at"])) % 60]}, rival)
	_log("%s acepta el duelo %s: el %d a las %02d:00 en %s, arma %s" % [rec["challenged"], rec["id"],
		Clock.day(int(rec["at"])) + 1, Clock.hour(int(rec["at"])), rec["place"], rec["weapon"]])


## The first minute `minute_of_day` after `now` on a later day (the next dawn).
static func _next_at(now: int, minute_of_day: int) -> int:
	return (Clock.day(now) + 1) * Clock.MINUTES_PER_DAY + minute_of_day


## The tile of the duel ground of the map: the first spawn of challenge.ground that exists ([0, 0] without a map).
static func ground(sim: Sim) -> Array:
	var spawns: Dictionary = sim.catalog.maps().get(sim.state.map_id, {}).get("spawns", {})
	for g: String in cfg(sim).get("ground", ["market"]):
		if spawns.has(g):
			return [int(spawns[g][0]), int(spawns[g][1])]
	return [0, 0]


## The living people in the street within `tiles` of `chr` (or of the tile `at`), sorted.
static func witnesses(sim: Sim, chr: String, tiles: int, at: Array = []) -> Array:
	var st := sim.state
	var p: Array = at if not at.is_empty() else st.characters.get(chr, {}).get("position", [0, 0])
	var out: Array = []
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = st.characters[id]
		if id == chr or not bool(ch.get("alive", true)) or str(ch.get("location", "")) != "":
			continue
		var q: Array = ch.get("position", [-99, -99])
		if maxi(absi(int(q[0]) - int(p[0])), absi(int(q[1]) - int(p[1]))) <= tiles:
			out.append(id)
	return out


static func _call(sim: Sim, rec: Dictionary) -> void:
	rec["called"] = true
	var st := sim.state
	for chr: String in [str(rec["challenger"]), str(rec["challenged"])]:
		if not Kin.alive(st, chr):
			continue
		if str(st.characters[chr].get("location", "")) != "":
			sim.give({"type": "exit_building", "actor": chr, "by_duel": true})
			sim.give({"type": "move_to", "actor": chr, "tile": rec["place"], "queued": true, "by_duel": true})
		else:
			sim.give({"type": "move_to", "actor": chr, "tile": rec["place"], "by_duel": true})
	for fam: String in [str(rec["challenger_family"]), str(rec["challenged_family"])]:
		if _human(st, fam):
			var rival := str(rec["challenged"]) if fam == str(rec["challenger_family"]) else str(rec["challenger"])
			Notices.add(sim, fam, Notices.URGENT, "notice.duel_call", {"rival": _name(st, rival), "time": "%02d:%02d" % [
				Clock.hour(int(rec["at"])), Clock.minute_of_day(int(rec["at"])) % 60]}, rival)
	sim.events.append({"type": "duel_called", "duel": rec["id"], "family": rec["challenger_family"],
		"target_family": rec["challenged_family"], "place": rec["place"]})
	_log("%s: a la plaza (%s) %s y %s" % [rec["id"], rec["place"], rec["challenger"], rec["challenged"]])


static func _present(sim: Sim, chr: String, place: Array) -> bool:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty() or not bool(ch.get("alive", true)) or str(ch.get("location", "")) != "":
		return false
	var q: Array = ch.get("position", [-99, -99])
	return maxi(absi(int(q[0]) - int(place[0])), absi(int(q[1]) - int(place[1]))) <= int(cfg(sim).get("present_tiles", 3))


static func _start(sim: Sim, rec: Dictionary) -> void:
	var st := sim.state
	var a := str(rec["challenger"])
	var b := str(rec["challenged"])
	var pa := _present(sim, a, rec["place"])
	var pb := _present(sim, b, rec["place"])
	if not pa or not pb:
		_close(sim, rec, "no_show", -1 if pa == pb else (0 if not pa else 1))
		return
	var seen := witnesses(sim, a, int(cfg(sim).get("witness_tiles", 8)), rec["place"])
	seen.erase(b)
	rec["witnesses"] = seen
	var side := -1
	if _human(st, str(rec["challenger_family"])):
		side = 0
	elif _human(st, str(rec["challenged_family"])):
		side = 1
	rec["player_side"] = side
	rec["status"] = FIGHTING
	rec["started"] = _now(sim)
	var w := str(rec["weapon"])
	var du := Duel.create(sim.catalog.combat, str(rec["id"]), st.world_seed, fighter_of(sim, a, w), fighter_of(sim, b, w),
		str(rec["kind"]), side)
	rec["duel"] = du.d
	sim.events.append({"type": "duel_started", "duel": rec["id"], "family": _side_family(rec, maxi(side, 0)),
		"target_family": _side_family(rec, 1 - maxi(side, 0)), "witnesses": seen.size(), "player_side": side})
	_log("%s empieza: %s contra %s, %d testigos, jugador en el lado %d" % [rec["id"], a, b, seen.size(), side])
	if side < 0:
		_finish(sim, rec)


static func _side_family(rec: Dictionary, side: int) -> String:
	return str(rec["challenger_family"]) if side == 0 else str(rec["challenged_family"])


static func _finish(sim: Sim, rec: Dictionary) -> void:
	var r := Duel.wrap(sim.catalog.combat, rec["duel"]).result()
	if int(r["yielded"]) >= 0:
		_close(sim, rec, "yielded", int(r["yielded"]))
	elif int(r["winner"]) < 0:
		_close(sim, rec, "draw", -1)
	else:
		_close(sim, rec, "fought", int(r["winner"]))


# --- consequences --------------------------------------------------------------------------------------------------

## Closes a duel with its consequences. outcome: fought (side = winner), draw, yielded (side = who yielded),
## no_show (side = who did not come, -1 = neither), refused, withdrawn.
static func _close(sim: Sim, rec: Dictionary, outcome: String, side: int) -> void:
	var st := sim.state
	var k := _cons(sim)
	var who: Array = [str(rec["challenger"]), str(rec["challenged"])]
	var fams: Array = [str(rec["challenger_family"]), str(rec["challenged_family"])]
	var public := (rec["witnesses"] as Array).size() >= int(cfg(sim).get("public_witnesses", 3))
	var mult := int(k.get("public_mult", 2)) if public else 1
	var winner := -1
	match outcome:
		"fought":
			winner = side
			_honour(sim, rec, side, "win", mult)
			_honour(sim, rec, 1 - side, "lose", mult)
			_court(sim, rec, side, "winner")
			_court(sim, rec, 1 - side, "loser_fought")
			_relation(sim, rec, "win")
			_offense_settled(sim, rec, side)
		"draw":
			_honour(sim, rec, 0, "draw", mult)
			_honour(sim, rec, 1, "draw", mult)
			_court(sim, rec, 0, "draw")
			_court(sim, rec, 1, "draw")
			_relation(sim, rec, "draw")
		"yielded":
			winner = 1 - side
			_honour(sim, rec, winner, "win", mult)
			_honour(sim, rec, side, "yield", mult)
			_court(sim, rec, winner, "winner")
			_court(sim, rec, side, "yield_or_refuse")
			_relation(sim, rec, "yield")
			_offense_settled(sim, rec, winner)
		"no_show":
			if side >= 0:
				winner = 1 - side
				_honour(sim, rec, side, "no_show", 1)
				_court(sim, rec, side, "yield_or_refuse")
				_relation(sim, rec, "no_show")
				Reputation.change(sim, fams[winner], int(k.get("refuse", {}).get("challenger", 2)), "duel_no_show_rival")
		"refused":
			var cost := int(rec.get("challenge_witnesses", 0)) > 0
			if cost:
				_honour(sim, rec, 1, "refuse", 1)
			_relation(sim, rec, "refuse")
			Reputation.change(sim, fams[0], int(k.get("refuse", {}).get("challenger", 2)), "duel_challenge_refused")
			_court(sim, rec, 1, "yield_or_refuse")
		"withdrawn":
			_honour(sim, rec, 0, "withdraw", 1)
	rec["status"] = "closed"
	rec["outcome"] = outcome
	rec["winner"] = who[winner] if winner >= 0 else ""
	rec["closed_at"] = _now(sim)
	var res: Dictionary = Duel.wrap(sim.catalog.combat, rec["duel"]).result() if not (rec["duel"] as Dictionary).is_empty() \
		else {}
	rec["touches"] = res.get("touches", [0, 0])
	rec["lances"] = int(res.get("lances", 0))
	open_duels(st).erase(str(rec["id"]))
	var closed: Array = book(st)["closed"]
	var slim := rec.duplicate(true)
	slim["duel"] = {}  # the lances are not kept once closed: the result and the touches are
	closed.append(slim)
	while closed.size() > int(cfg(sim).get("keep_closed", 20)):
		closed.pop_front()
	for i: int in 2:  # one fact per family (the book, the ending, the dynasty score read them by family)
		var result := "draw"
		if winner >= 0:
			result = "won" if winner == i else "lost"
		elif outcome in ["refused", "withdrawn", "no_show"]:
			result = outcome
		Chronicle.add(st, "duel", {"family": fams[i], "duel": rec["id"], "character": who[i], "rival": who[1 - i],
			"cause": rec["cause"], "outcome": outcome, "result": result, "touches": rec["touches"], "public": public})
	sim.events.append({"type": "duel_finished", "duel": rec["id"], "outcome": outcome, "winner": rec["winner"],
		"family": fams[0], "target_family": fams[1], "touches": rec["touches"], "lances": rec["lances"],
		"public": public, "absent": who[side] if outcome == "no_show" and side >= 0 else ""})
	for i: int in 2:
		if _human(st, fams[i]):
			var res_key := "cancelled" if outcome == "no_show" and side < 0 else outcome
			if outcome in ["fought", "yielded"] or (outcome == "no_show" and side >= 0):
				res_key = "won" if winner == i else "lost"
				if outcome == "yielded" and side == i:
					res_key = "yielded"
				if outcome == "no_show":
					res_key = "no_show_rival" if winner == i else "no_show_you"
			Notices.add(sim, fams[i], Notices.INFO if res_key == "won" else Notices.WARNING, "notice.duel_" + res_key,
				{"rival": _name(st, who[1 - i]), "touches": "%d–%d" % [int(rec["touches"][i]), int(rec["touches"][1 - i])]},
				who[1 - i])
	_log("%s se cierra: %s, gana %s, toques %s, %s" % [rec["id"], outcome, rec["winner"] if rec["winner"] != "" else
		"nadie", rec["touches"], "público" if public else "sin público"])


## Reputation (honour) of side `i` for `what` (win, lose, draw, yield, refuse, no_show, withdraw); a gain weighted by
## the rival's title above.
static func _honour(sim: Sim, rec: Dictionary, i: int, what: String, mult: int) -> void:
	var k := _cons(sim)
	var fams: Array = [str(rec["challenger_family"]), str(rec["challenged_family"])]
	var amount := int(k.get(what, {}).get("reputation", 0)) * mult
	if amount > 0:
		var gap := Titles.rank(sim, Titles.current(sim, fams[1 - i])) - Titles.rank(sim, Titles.current(sim, fams[i]))
		var weight := minf(float(k.get("title_weight_max", 2.0)), 1.0 + float(k.get("title_weight_step", 0.5)) * maxi(0, gap))
		amount = roundi(amount * weight)
	Reputation.change(sim, fams[i], amount, "duel_" + what)


## The permanent relation between the two duellists after `what` (once per duel: it is one figure for the pair).
static func _relation(sim: Sim, rec: Dictionary, what: String) -> void:
	var rel := int(_cons(sim).get(what, {}).get("relation", 0))
	if rel != 0:
		Emotions.change_relation(sim, str(rec["challenger"]), str(rec["challenged"]), rel, "duel_" + what)


## Courtship affinity of side `i` with the courted one (cause courtship), by `what` of consequences.courtship.
static func _court(sim: Sim, rec: Dictionary, i: int, what: String) -> void:
	if str(rec["cause"]) != "courtship" or str(rec["about"]) == "":
		return
	var who := str(rec["challenger"]) if i == 0 else str(rec["challenged"])
	var amount := int(_cons(sim).get("courtship", {}).get(what, 0))
	if amount == 0:
		return
	var rel := Courtship.relation(sim.state, who, str(rec["about"]))
	var before := int(rel.get("affinity", 0))
	rel["affinity"] = clampi(before + amount, 0, int(sim.catalog.family.get("courtship", {}).get("affinity_max", 100)))
	sim.events.append({"type": "affinity_changed", "actor": who, "target": rec["about"], "amount": int(rel["affinity"]) - before,
		"affinity": rel["affinity"], "reason": "duel_" + what})
	_log("afinidad %s con %s %+d (duelo, %s)" % [who, rec["about"], int(rel["affinity"]) - before, what])


## Cause offense: the winner's side lets go of the offense states towards the loser's family.
static func _offense_settled(sim: Sim, rec: Dictionary, winner: int) -> void:
	if str(rec["cause"]) != "offense":
		return
	var st := sim.state
	var fam := str(rec["challenger_family"]) if winner == 0 else str(rec["challenged_family"])
	var other := str(rec["challenged_family"]) if winner == 0 else str(rec["challenger_family"])
	var states: Array = cfg(sim).get("offense_states", ["offended", "angry"])
	for m: String in st.families.get(fam, {}).get("members", []):
		var keep: Array = []
		for e: Dictionary in st.emotions.get(m, []):
			if str(e.get("source", "")) == other and str(e.get("state", "")) in states:
				Emotions._ended(sim, m, e, "duel")
			else:
				keep.append(e)
		if st.emotions.has(m):
			st.emotions[m] = keep


static func _name(st: WorldState, chr: String) -> String:
	return str(st.characters.get(chr, {}).get("name", chr))


static func _log(msg: String) -> void:
	if OS.is_debug_build():
		print("[Duels] " + msg)
