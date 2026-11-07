class_name BotSpyNovice
extends RefCounted
## Bot spy_novice (docs/gdd/04d_otras_clases.md §4.22.6.5 «spy»; H12, the Rogue's second trade): the spy of a new game
## rogue_spy, playing like a careful novice through the same orders as the UI. By day he takes the town's spying jobs
## (the fence of his den passes them): to the door of a building of the job's family (the least guarded), two hours
## spying, back to the den to deliver the report. With no job open he spies the town's households for their secrets.
## A secret of medium charge or more he blackmails once a season. He never spies by night (the watch); he repays the
## debt when he can. Caught, he answers the arrest card: bribe if he can spare it, else surrender. Measures: spies,
## spies_ok, jobs, job_gold, blackmails, blackmail_gold, arrests, trials.

const ID: String = "spy_novice"
const DEBT_RESERVE: int = 20

var fam: String = ""
var me: String = ""
var m: Dictionary = {}
var _spied: Dictionary = {}   # family -> true: households already looked at (for their secrets)
var _target: String = ""      # the building he is walking to


func _add(k: String, n: int = 1) -> void:
	m[k] = int(m.get(k, 0)) + n


func measures(_sim: Sim) -> Dictionary:
	var out := {}
	for k: String in ["spies", "spies_ok", "jobs", "job_gold", "blackmails", "blackmail_gold", "arrests", "trials"]:
		out[k] = int(m.get(k, 0))
	return out


func orders(sim: Sim) -> Array:
	var st := sim.state
	if fam == "":
		fam = SimQuery.player_family(st)
		me = Kin.head(st, fam)
	_watch(sim)
	if me == "" or not Kin.alive(st, me) or Tribunal.is_banished(st, me) or Region.is_away(st, me):
		return []
	var arrest := Rogue.pending_arrest(st, me)
	if not arrest.is_empty():
		var odds := Rogue.arrest_odds(sim, me, str(arrest["guard"]))
		var bribe := Money.gold(st, fam) >= int(odds["bribe_price"]) + 60 and float(odds["bribe"]) >= 0.5
		return [{"type": "arrest_response", "actor": me, "choice": "bribe" if bribe else "surrender"}]
	if Spy.book(sim)["spying"].has(me):
		return []
	var ch: Dictionary = st.characters[me]
	var o := _repay(sim)
	if not o.is_empty():
		return [o]
	o = _blackmail(sim)
	if not o.is_empty():
		return [o]
	var den := Rogue.den_of(st, fam)
	for j: Dictionary in Spy.jobs_for(sim, fam):
		if not Spy.report_for_job(sim, fam, j).is_empty():  # a report to deliver: to the den
			if str(ch.get("location", "")) == den:
				return [{"type": "deliver_intel", "actor": me, "job": str(j["id"])}]
			return _to_den(sim, den)
	if not (ch.get("path", []) as Array).is_empty() or not (ch.get("order_queue", []) as Array).is_empty():
		return []
	var ph := Clock.phase(int(st.clock["minute"]), sim.catalog.time)
	if ph in ["dawn", "day"]:
		var bld := _pick(sim)
		if bld != "":
			return _spy_at(sim, bld)
	_target = ""
	return _to_den(sim, den) if str(ch.get("location", "")) != den else []


# --- What happened -----------------------------------------------------------------------------------------------------

func _watch(sim: Sim) -> void:
	for e: Dictionary in sim.events:
		if str(e.get("family", "")) != fam:
			continue
		match str(e.get("type", "")):
			"spy_done":
				_add("spies")
				_add("spies_ok")
			"spy_failed":
				_add("spies")
			"spy_job_done":
				_add("jobs")
				_add("job_gold", int(e.get("gold", 0)))
			"blackmail_done":
				_add("blackmails")
				_add("blackmail_gold", int(e.get("gold", 0)))
			"rogue_arrest_card":
				_add("arrests")
			"trial_opened":
				_add("trials")


# --- Debt ------------------------------------------------------------------------------------------------------------

func _repay(sim: Sim) -> Dictionary:
	var gold := Money.gold(sim.state, fam)
	for id: String in Loans.of_family(sim, fam):
		var s := Loans.status(sim, id)
		if not str(s["state"]) in ["active", "extended"]:
			continue
		var owed := int(s["outstanding"])
		if gold >= owed + DEBT_RESERVE:
			return {"type": "repay_loan", "actor": me, "loan": id, "amount": owed}
		if int(s["days_left"]) <= 1 and gold > 5:
			return {"type": "repay_loan", "actor": me, "loan": id, "amount": mini(owed, gold - 5)}
	return {}


# --- Secrets -----------------------------------------------------------------------------------------------------------

## A secret of medium charge or more not yet used this season: blackmail.
func _blackmail(sim: Sim) -> Dictionary:
	var min_sev := str(Spy._part(sim, "blackmail").get("min_severity", "medium"))
	for f: Dictionary in Spy.usable_facts(sim, fam):
		if Tribunal.severity_rank(sim, Tribunal.severity_of(sim, str(f["charge"]))) < Tribunal.severity_rank(sim, min_sev):
			continue
		if Spy.blackmail_reason(sim, me, str(f["id"])) == "":
			return {"type": "blackmail", "actor": me, "fact": str(f["id"])}
	return {}


# --- Spying ------------------------------------------------------------------------------------------------------------

## The building to spy now: one of the family of an open job with no report yet (the least guarded of its buildings),
## else a household not yet looked at; "" if none.
func _pick(sim: Sim) -> String:
	var st := sim.state
	if _target != "" and st.buildings.has(_target) and Spy.spy_reason(sim, me, _target) == "":
		return _target
	for j: Dictionary in Spy.jobs_for(sim, fam):
		var b := _best_building(sim, str(j["about"]))
		if b != "":
			return b
	for f: String in Festivals._sorted_keys(st.families):
		if Spy.is_household(st, f) and not _spied.has(f):
			var b := _best_building(sim, f)
			if b != "":
				return b
	return ""


func _best_building(sim: Sim, about: String) -> String:
	var best := ""
	var best_sec := 1 << 20
	for b: String in Festivals._sorted_keys(sim.state.buildings):
		if Money.family_of(sim.state, b) != about or Spy.spy_reason(sim, me, b) != "":
			continue
		if (sim.state.buildings[b].get("door", []) as Array).size() != 2:
			continue
		var sec := Rogue.security_level(sim, b)
		if sec < best_sec:
			best = b
			best_sec = sec
	return best


func _spy_at(sim: Sim, bld: String) -> Array:
	var st := sim.state
	_target = bld
	if str(st.characters[me].get("location", "")) != "":
		return [{"type": "exit_building", "actor": me}]
	if Spy.near(sim, me, bld):
		_target = ""
		_spied[Money.family_of(st, bld)] = true
		return [{"type": "spy", "actor": me, "building": bld}]
	var door: Array = st.buildings[bld]["door"]
	return [{"type": "move_to", "actor": me, "tile": [int(door[0]), int(door[1])]}]


func _to_den(sim: Sim, den: String) -> Array:
	var ch: Dictionary = sim.state.characters[me]
	if den == "" or str(ch.get("location", "")) == den:
		return []
	if str(ch.get("location", "")) != "":
		return [{"type": "exit_building", "actor": me}]
	if not (ch.get("path", []) as Array).is_empty():
		return []
	return [{"type": "enter_building", "actor": me, "building": den}]
