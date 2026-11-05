extends RefCounted
## The rest of the world while the full player plays (docs/contratos/informe_jugador_completo.md, docs/gdd/07_testing.md
## §7.4): the rival families (the AI families with an ai_profile, GDD 4.5.5 and the H9-H11 hooks; the agenda of 04c
## is H6 and not built yet: what it reports is the plan of tasks of RivalAI) and the town (townsfolk, visitors, the
## watch and the incidents). tools/full_player.gd calls step() every minute with the step's events, hour() every game
## hour and day() at every day's end; report() gives the "rivals" and "town" blocks and measures() the flat numbers.
## It only reads the state (never a query that writes, such as Courtship.relation).

const NPC_STALL_HOURS: int = 20     # a townsperson that neither moves nor changes activity this long is stalled
const RIVAL_STALL_HOURS: int = 16   # the same for the actor of an AI family
const HUNGRY: int = 25              # a need below this is "short" (data/life: urgency grows below ~30)
const BROKE: int = 10               # an AI family with less gold than this at dawn is broke that day

var fam: String = ""                # the player's family
var start_day: int = 0
var rivals: Dictionary = {}         # family -> its block (see _rival_block)
var _phase: Dictionary = {}         # family -> last ai_state.phase seen
var _plan_head: Dictionary = {}     # family -> plan[0] seen last minute
var _sig: Dictionary = {}           # character -> [signature, since minute]
var _npc_stalled: Dictionary = {}   # character -> index in npc_stalls
var npc_stalls: Array = []
var _calls: Dictionary = {}         # incident -> minute the watch was called
var guard: Dictionary = {"called": 0, "arrived": 0, "minutes": [], "outcomes": {}}
var incidents: Dictionary = {}      # "<season index>|<def>" -> n
var visitors: Dictionary = {"total": 0, "by_kind": {}, "by_day": {}}
var pop: Dictionary = {"weddings": 0, "births": 0, "deaths": 0, "newcomers": 0, "by_year": []}
var activities: Dictionary = {}     # activity -> hourly samples
var need_sum: Dictionary = {}       # need -> sum of the hourly samples
var need_n: int = 0
var _short: Dictionary = {}         # character -> [samples with a need short, samples]
var elections: Dictionary = {}      # election office|minute -> {player, ai}
var contested_elections: int = 0
var player_lost_races: int = 0


func begin(sim: Sim, player: String) -> void:
	fam = player
	start_day = Clock.day(int(sim.state.clock["minute"]))
	for f: String in _sorted(sim.state.families.keys()):
		var d: Dictionary = sim.state.families[f]
		if str(d.get("ai_profile", "")) != "" and str(d.get("controlled_by", "")) == "ai":
			rivals[f] = _rival_block(sim, f)
	pop["by_year"].append({"year": 0, "townsfolk": Population.townsfolk(sim.state).size()})


func _rival_block(sim: Sim, f: String) -> Dictionary:
	var d: Dictionary = sim.state.families[f]
	var trades: Array = []
	for b: String in _sorted(sim.state.buildings.keys()):
		if str(sim.state.buildings[b].get("owner", "")) == f:
			trades.append(str(sim.state.buildings[b]["type"]))
	return {"id": f, "name": str(d.get("name", "")), "profile": str(d.get("ai_profile", "")), "buildings_start": trades,
		"curve": [], "titles": [], "offices_run": [], "offices_won": [], "weddings": [], "births": [], "deaths": [],
		"sold_units": 0, "sold_gold": 0, "bought_gold": 0, "work_done": 0, "contracts_accepted": 0,
		"contracts_done": 0, "contracts_failed": 0, "festival_contracts_done": 0, "races_won_vs_player": 0,
		"accusations_vs_player": [], "accusations_other": 0, "refused": {}, "plan_chosen": {}, "task_ended": {},
		"task_minutes": {}, "idle_days": 0, "broke_days": 0, "stalls": [], "duels": 0, "inherited": 0,
		"_day_sold": 0, "_day_work": 0, "_stall_open": -1}


## Every minute, after Sim.step, with its events.
func step(sim: Sim, ev: Array, played: int) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	for f: String in rivals:
		var r: Dictionary = rivals[f]
		var ai: Variant = st.families.get(f, {}).get("ai_state")
		if not ai is Dictionary:
			continue
		var plan: Array = (ai as Dictionary).get("plan", [])
		var ph := str((ai as Dictionary).get("phase", ""))
		if ph != str(_phase.get(f, "")):  # RivalAI decided a plan at this phase change: what it chose
			_phase[f] = ph
			for t: Variant in plan:
				r["plan_chosen"][str(t)] = int(r["plan_chosen"].get(str(t), 0)) + 1
		var head := str(plan[0]) if not plan.is_empty() else ""
		var was := str(_plan_head.get(f, ""))
		if was != "" and was != head:
			r["task_ended"][was] = int(r["task_ended"].get(was, 0)) + 1
		_plan_head[f] = head
		if head != "":
			r["task_minutes"][head] = int(r["task_minutes"].get(head, 0)) + 1
	for e: Dictionary in ev:
		var t := str(e.get("type", ""))
		var ef := str(e.get("family", ""))
		if rivals.has(ef):
			_rival_event(sim, rivals[ef], e, t, played)
		match t:
			"order_refused":
				var af := str(st.characters.get(str(e.get("actor", "")), {}).get("family", ""))
				if rivals.has(af):
					var k := "%s|%s" % [e.get("order", ""), e.get("reason", "")]
					rivals[af]["refused"][k] = int(rivals[af]["refused"].get(k, 0)) + 1
			"work_done":
				var wf := str(st.characters.get(str(e.get("actor", "")), {}).get("family", ""))
				if rivals.has(wf):
					rivals[wf]["work_done"] = int(rivals[wf]["work_done"]) + 1
					rivals[wf]["_day_work"] = int(rivals[wf]["_day_work"]) + 1
			"trial_opened":
				var acc := str(e.get("accuser_family", ""))
				if rivals.has(acc):
					if ef == fam:
						rivals[acc]["accusations_vs_player"].append({"day": played, "charge": str(e.get("charge", "")),
							"source": str(e.get("source", ""))})
					else:
						rivals[acc]["accusations_other"] = int(rivals[acc]["accusations_other"]) + 1
			"contract_lost":
				if ef == fam and rivals.has(str(e.get("winner", ""))):
					player_lost_races += 1
					rivals[str(e["winner"])]["races_won_vs_player"] = int(rivals[str(e["winner"])]["races_won_vs_player"]) + 1
			"duel_finished":
				for side: String in [str(e.get("family", "")), str(e.get("target_family", ""))]:
					if rivals.has(side):
						rivals[side]["duels"] = int(rivals[side]["duels"]) + 1
			"office_candidate":
				var key := str(e.get("election", ""))
				if not elections.has(key):
					elections[key] = {"player": false, "ai": false}
				if ef == fam:
					elections[key]["player"] = true
				elif rivals.has(ef):
					elections[key]["ai"] = true
			"election_held":
				var k2 := str(e.get("election", ""))
				if elections.has(k2):
					if bool(elections[k2]["player"]) and bool(elections[k2]["ai"]):
						contested_elections += 1
					elections.erase(k2)
			"townsfolk_married":
				pop["weddings"] = int(pop["weddings"]) + 1
			"child_born":
				if ef != fam:
					pop["births"] = int(pop["births"]) + 1
			"character_died":
				if ef != fam:
					pop["deaths"] = int(pop["deaths"]) + 1
			"newcomer_arrived":
				pop["newcomers"] = int(pop["newcomers"]) + 1
			"visitor_arrived":
				visitors["total"] = int(visitors["total"]) + 1
				var kind := str(e.get("kind", ""))
				visitors["by_kind"][kind] = int(visitors["by_kind"].get(kind, 0)) + 1
				visitors["by_day"][str(played)] = int(visitors["by_day"].get(str(played), 0)) + 1
			"incident_started":
				var season := Clock.day(now) / int(sim.catalog.time.get("days_per_season", 2))
				var ik := "%d|%s" % [season, e.get("def", "")]
				incidents[ik] = int(incidents.get(ik, 0)) + 1
			"watch_called":
				var inc := str(e.get("incident", ""))
				if not _calls.has(inc):
					_calls[inc] = now
					guard["called"] = int(guard["called"]) + 1
			"guard_arrived":
				var inc2 := str(e.get("incident", ""))
				if _calls.has(inc2) and int(_calls[inc2]) >= 0:
					guard["arrived"] = int(guard["arrived"]) + 1
					(guard["minutes"] as Array).append(now - int(_calls[inc2]))
					_calls[inc2] = -1
			"incident_ended":
				var oc := "%s|%s" % [e.get("def", ""), e.get("outcome", "")]
				guard["outcomes"][oc] = int(guard["outcomes"].get(oc, 0)) + 1


func _rival_event(sim: Sim, r: Dictionary, e: Dictionary, t: String, played: int) -> void:
	match t:
		"market_sold":
			r["sold_units"] = int(r["sold_units"]) + int(e.get("qty", 0))
			r["sold_gold"] = int(r["sold_gold"]) + int(e.get("total", 0))
			r["_day_sold"] = int(r["_day_sold"]) + 1
		"market_bought":
			r["bought_gold"] = int(r["bought_gold"]) + int(e.get("cost", 0))
		"contract_accepted":
			r["contracts_accepted"] = int(r["contracts_accepted"]) + 1
		"contract_delivered":
			r["contracts_done"] = int(r["contracts_done"]) + 1
		"contract_failed":
			r["contracts_failed"] = int(r["contracts_failed"]) + 1
		"festival_contract_done":
			r["festival_contracts_done"] = int(r["festival_contracts_done"]) + 1
		"title_granted":
			r["titles"].append({"day": played, "title": str(e.get("title", ""))})
		"office_candidate":
			r["offices_run"].append({"day": played, "office": str(e.get("office", ""))})
		"office_taken":
			r["offices_won"].append({"day": played, "office": str(e.get("office", ""))})
		"wedding":
			r["weddings"].append({"day": played, "character": str(e.get("character", "")), "spouse": str(e.get("spouse", ""))})
		"child_born":
			r["births"].append({"day": played, "child": str(e.get("character", ""))})
		"character_died":
			r["deaths"].append({"day": played, "character": str(e.get("character", "")), "age": int(e.get("age", 0))})
		"inheritance":
			r["inherited"] = int(r["inherited"]) + 1


## Every game hour: the townsfolk's activity and needs, stalled townsfolk and AI actors.
func hour(sim: Sim, played: int) -> void:
	var st := sim.state
	var now := int(st.clock["minute"])
	for c: String in Population.townsfolk(st):
		var v := Agenda.view(sim, c)
		if v.is_empty():
			continue
		var a := str(v.get("activity", ""))
		activities[a if a != "" else "none"] = int(activities.get(a if a != "" else "none", 0)) + 1
		var kind := "staff" if st.characters[c].get("job") is Dictionary else ("child" if not Kin.is_adult(sim, c) else "adult")
		var row: Dictionary = _short.get(c, {"_n": 0, "_kind": kind})
		if kind == "staff" or str(row.get("_kind", "")) == "":
			row["_kind"] = kind  # employed at some point: measured apart; a child stays a child in the measure
		for n: String in (v.get("needs", {}) as Dictionary):
			var x := int(v["needs"][n])
			need_sum[n] = int(need_sum.get(n, 0)) + x
			if x < HUNGRY:
				row[n] = int(row.get(n, 0)) + 1
		row["_n"] = int(row["_n"]) + 1
		_short[c] = row
		need_n += 1
		var job: Variant = st.characters[c].get("job")
		if job is Dictionary and not Staff.is_active(sim, c):
			_sig.erase(c)  # an employee not started yet, sick or on a day off is not stalled
			continue
		_watch_still(sim, c, NPC_STALL_HOURS, now, played, npc_stalls, _npc_stalled, a)
	for f: String in rivals:
		var head := Kin.head(st, f)
		if head == "" or not Kin.alive(st, head):
			continue
		var r: Dictionary = rivals[f]
		var ch: Dictionary = st.characters[head]
		var loc := str(ch.get("location", ""))
		var z := Production.job_zone(sim, head, loc) if loc != "" else ""
		var js := ""
		if z != "":
			js = str(st.buildings[loc]["zones"][z].get("job", {}).get("start", ""))
		var sig := "%s|%s|%s|%s" % [ch.get("position", []), loc, z, js]
		var key := "rival|" + head
		if not _sig.has(key) or str(_sig[key][0]) != sig:
			_sig[key] = [sig, now]
			r["_stall_open"] = -1
			continue
		var h := (now - int(_sig[key][1])) / 60
		if h < RIVAL_STALL_HOURS:
			continue
		if int(r["_stall_open"]) >= 0:
			r["stalls"][int(r["_stall_open"])]["hours"] = h
		else:
			r["_stall_open"] = (r["stalls"] as Array).size()
			r["stalls"].append({"from_day": played, "hours": h, "where": loc if loc != "" else str(ch.get("position", [])),
				"task": str(_plan_head.get(f, "")), "gold": Money.gold(st, f)})


func _watch_still(sim: Sim, c: String, hours: int, now: int, played: int, out: Array, open: Dictionary, act: String) -> void:
	var ch: Dictionary = sim.state.characters[c]
	if not bool(ch.get("alive", true)) or Region.is_away(sim.state, c) or Life.offstage(sim.state, c):
		_sig.erase(c)
		return
	var sig := "%s|%s|%s" % [ch.get("position", []), ch.get("location", ""), act]
	if not _sig.has(c) or str(_sig[c][0]) != sig:
		_sig[c] = [sig, now]
		open.erase(c)
		return
	var h := (now - int(_sig[c][1])) / 60
	if h < hours:
		return
	if open.has(c):
		out[int(open[c])]["hours"] = h
		return
	if out.size() >= 200:
		return
	open[c] = out.size()
	out.append({"who": c, "name": str(ch.get("name", "")), "from_day": played, "hours": h, "activity": act,
		"where": str(ch.get("location", "")) if str(ch.get("location", "")) != "" else str(ch.get("position", []))})


## At the end of each day played: the rivals' curves and their idle and broke days; the population at a year's end.
func day(sim: Sim, played: int, year_days: int) -> void:
	var st := sim.state
	for f: String in rivals:
		var r: Dictionary = rivals[f]
		if not st.families.has(f):
			continue
		var blds := 0
		for b: String in st.buildings:
			if str(st.buildings[b].get("owner", "")) == f:
				blds += 1
		var members := 0
		for m: Variant in st.families[f].get("members", []):
			members += 1 if Kin.alive(st, str(m)) else 0
		var staff := 0
		for c: String in st.characters:
			var job: Variant = st.characters[c].get("job")
			if job is Dictionary and str(st.buildings.get(str(job.get("building", "")), {}).get("owner", "")) == f:
				staff += 1
		var gold := Money.gold(st, f)
		r["curve"].append({"day": played, "gold": gold, "title": Titles.current(sim, f),
			"title_rank": Titles.rank(sim, Titles.current(sim, f)), "reputation": Reputation.of(st, f),
			"buildings": blds, "members": members, "staff": staff})
		if int(r["_day_sold"]) == 0 and int(r["_day_work"]) == 0:
			r["idle_days"] = int(r["idle_days"]) + 1
		if gold < BROKE:
			r["broke_days"] = int(r["broke_days"]) + 1
		r["_day_sold"] = 0
		r["_day_work"] = 0
	if played > 1 and (played - 1) % year_days == 0:
		pop["by_year"].append({"year": (played - 1) / year_days, "townsfolk": Population.townsfolk(st).size()})


func report() -> Dictionary:
	var rv := {}
	for f: String in rivals:
		var r: Dictionary = (rivals[f] as Dictionary).duplicate(true)
		for k: String in ["_day_sold", "_day_work", "_stall_open"]:
			r.erase(k)
		rv[f] = r
	var needs := {}
	for n: String in need_sum:
		needs[n] = snappedf(float(need_sum[n]) / maxf(1.0, float(need_n)), 0.1)
	var acts := {}
	var total := 0
	for a: String in activities:
		total += int(activities[a])
	for a: String in activities:
		acts[a] = snappedf(float(activities[a]) / maxf(1.0, float(total)), 0.001)
	var mins: Array = (guard["minutes"] as Array).duplicate()
	mins.sort()
	return {"rivals": rv, "town": {"activity_share": acts, "needs_mean": needs, "short_share_max": _short_by_need(), "short_who": _short_who(),
		"npc_stalls": npc_stalls.duplicate(true), "population": pop.duplicate(true), "visitors": visitors.duplicate(true),
		"incidents_by_season": incidents.duplicate(), "watch": {"called": guard["called"], "arrived": guard["arrived"],
		"minutes_median": int(mins[mins.size() / 2]) if not mins.is_empty() else -1,
		"minutes_max": int(mins.back()) if not mins.is_empty() else -1, "outcomes": guard["outcomes"].duplicate()},
		"contested_elections": contested_elections, "player_lost_races": player_lost_races}}


## The worst share of hourly samples with need `n` short (< HUNGRY), over the townsfolk sampled at least a day;
## `kind`: "adult" (never employed), "staff" (employed by a family at some point) or "child".
func _short_max(n: String, kind: String = "adult") -> float:
	var worst := 0.0
	for c: String in _short:
		var row: Dictionary = _short[c]
		if int(row["_n"]) >= 24 and str(row.get("_kind", "adult")) == kind:
			worst = maxf(worst, float(row.get(n, 0)) / float(row["_n"]))
	return snappedf(worst, 0.001)


## {need: worst share} for every need seen.
func _short_by_need() -> Dictionary:
	var out := {}
	for n: String in need_sum:
		out[n] = _short_max(n)
		out["staff_" + n] = _short_max(n, "staff")
		out["child_" + n] = _short_max(n, "child")
	return out


## {need: the townsperson with the worst share} (who to look at).
func _short_who() -> Dictionary:
	var out := {}
	for n: String in need_sum:
		var worst := -1.0
		for c: String in _short:
			var row: Dictionary = _short[c]
			if int(row["_n"]) >= 24 and float(row.get(n, 0)) / float(row["_n"]) > worst:
				worst = float(row.get(n, 0)) / float(row["_n"])
				out[n] = c
	return out


## Flat numbers for the targets (data/targets.json full_player).
func measures(days: int, year_days: int) -> Dictionary:
	var m := {}
	var titled := 0
	var ups := 0
	var offices_run := 0
	var offices_won := 0
	var attacks := 0
	var refused := 0
	var idle_max := 0
	var broke_max := 0
	var stalls := 0
	var weddings := 0
	var births := 0
	var ai_contracts := 0
	for f: String in rivals:
		var r: Dictionary = rivals[f]
		ups += (r["titles"] as Array).size()
		titled += 1 if not (r["titles"] as Array).is_empty() else 0
		offices_run += (r["offices_run"] as Array).size()
		offices_won += (r["offices_won"] as Array).size()
		attacks += (r["accusations_vs_player"] as Array).size()
		for k: String in r["refused"]:
			refused += int(r["refused"][k])
		idle_max = maxi(idle_max, int(r["idle_days"]))
		broke_max = maxi(broke_max, int(r["broke_days"]))
		stalls += (r["stalls"] as Array).size()
		weddings += (r["weddings"] as Array).size()
		births += (r["births"] as Array).size()
		ai_contracts += int(r["contracts_accepted"])
	var years := maxf(1.0, float(days) / float(year_days))
	m["ai_families"] = rivals.size()
	m["ai_titled_families"] = titled
	m["ai_title_ups"] = ups
	m["ai_office_runs"] = offices_run
	m["ai_offices_won"] = offices_won
	m["ai_attacks_vs_player"] = attacks
	m["ai_refused"] = refused
	m["ai_refused_per_family_year"] = snappedf(float(refused) / maxf(1.0, float(rivals.size())) / years, 0.01)
	m["ai_idle_days_max"] = idle_max
	m["ai_broke_days_max"] = broke_max
	m["ai_stalls"] = stalls
	m["ai_weddings"] = weddings
	m["ai_births"] = births
	m["ai_contracts_accepted"] = ai_contracts
	m["ai_races_won_vs_player"] = player_lost_races
	m["contested_elections"] = contested_elections
	m["npc_stalls"] = npc_stalls.size()
	m["npc_hungry_share_max"] = _short_max("hunger")  # the hungriest adult townsperson (never employed): share of hours
	m["staff_hungry_share_max"] = _short_max("hunger", "staff")  # the same for townsfolk employed by a family
	m["child_hungry_share_max"] = _short_max("hunger", "child")  # and for the town's children
	for n: String in need_sum:
		m["npc_short_%s_max" % n] = _short_max(n)
	m["town_weddings"] = int(pop["weddings"])
	m["town_births"] = int(pop["births"])
	m["town_deaths"] = int(pop["deaths"])
	m["townsfolk_end"] = int(pop["by_year"].back()["townsfolk"]) if not (pop["by_year"] as Array).is_empty() else 0
	m["visitors_per_day"] = snappedf(float(visitors["total"]) / maxf(1.0, float(days)), 0.01)
	m["watch_called"] = int(guard["called"])
	m["watch_arrived_share"] = snappedf(float(guard["arrived"]) / maxf(1.0, float(guard["called"])), 0.001) \
		if int(guard["called"]) > 0 else 1.0
	var n_inc := 0
	for k: String in incidents:
		n_inc += int(incidents[k])
	m["incidents"] = n_inc
	return m


func _sorted(a: Array) -> Array:
	var out: Array = []
	for x: Variant in a:
		out.append(str(x))
	out.sort()
	return out
