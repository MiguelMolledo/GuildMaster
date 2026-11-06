class_name Titles
extends RefCounted
## Social titles and the ceremony at the town hall (GDD 4.12.2, 4.9; docs/contratos/h9_titulos.md). The title is
## the family's (families[fam].title, an id of data/titles/): it is inherited with the family. request_title asks
## for the next one in person, on the service tile of the map's town_hall: requirements (reputation, businesses,
## employees, special event), the gold (ledger category titles, GDD 4.19) and the approval of the office that
## grants it (none until H10: vacant, approved by itself). The ceremony is at once: the title, the chronicle fact
## (dynasty score), title_granted and the notices.


## The family's title id (the first of the ladder if it has none).
static func current(sim: Sim, fam: String) -> String:
	var t := str(sim.state.families.get(fam, {}).get("title", ""))
	if t == "" or not sim.catalog.titles().has(t):
		var ladder := sim.catalog.title_ladder()
		return str(ladder[0]) if not ladder.is_empty() else ""
	return t


## Rank of a title id (0 = the first), -1 if unknown.
static func rank(sim: Sim, title: String) -> int:
	return int(sim.catalog.titles().get(title, {}).get("rank", -1))


## The next title of the family, "" if it has the last one.
static func next_of(sim: Sim, fam: String) -> String:
	var ladder := sim.catalog.title_ladder()
	var i := ladder.find(current(sim, fam))
	return str(ladder[i + 1]) if i >= 0 and i + 1 < ladder.size() else ""


## The family's operative businesses: its own workshops (building category "workshop"), sorted.
static func business_ids(sim: Sim, fam: String) -> Array:
	var out: Array = []
	if fam == "":
		return out
	for b: String in sim.state.buildings:
		var bld: Dictionary = sim.state.buildings[b]
		if str(bld.get("owner", "")) != fam:
			continue
		if str(sim.catalog.buildings().get(str(bld.get("type", "")), {}).get("category", "")) == "workshop":
			out.append(b)
	out.sort()
	return out


static func businesses(sim: Sim, fam: String) -> int:
	return business_ids(sim, fam).size()


## Employees hired by the family in any of its buildings that are not leaving.
static func employees(sim: Sim, fam: String) -> int:
	var n := 0
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b].get("owner", "")) != fam:
			continue
		for c: String in Staff.employees_of(sim.state, b):
			if int(sim.state.characters[c]["job"].get("end_day", -1)) < 0:
				n += 1
	return n


## Own buildings the family's title allows (GDD 4.9: unlocks.max_buildings), -1 = no limit. Ready for H6.
static func max_buildings(sim: Sim, fam: String) -> int:
	var v: Variant = sim.catalog.titles().get(current(sim, fam), {}).get("unlocks", {}).get("max_buildings", 1)
	return -1 if v == null else int(v)


## The requirements of title `t` for `fam`: [{kind, need, have, ok}] in a fixed order (reputation, businesses,
## employees, event, gold).
static func requirements(sim: Sim, fam: String, t: String) -> Array:
	var def: Dictionary = sim.catalog.titles().get(t, {})
	var out: Array = []
	var rep := Reputation.of(sim.state, fam)
	var fav := FestivalCourt.title_mults(sim.state, fam)  # fiestas: the marquis's favour (title_favour)
	var rep_need := roundi(float(def.get("reputation", 0)) * float(fav.get("reputation_mult", 1.0)))
	out.append({"kind": "reputation", "need": rep_need, "have": rep, "ok": rep >= rep_need})
	var req: Dictionary = def.get("requires", {})
	if req.has("businesses"):
		var b := businesses(sim, fam)
		out.append({"kind": "businesses", "need": int(req["businesses"]), "have": b, "ok": b >= int(req["businesses"])})
	if req.has("employees"):
		var e := employees(sim, fam)
		out.append({"kind": "employees", "need": int(req["employees"]), "have": e, "ok": e >= int(req["employees"])})
	if req.has("event"):
		var done := str(req["event"]) in (sim.state.families.get(fam, {}).get("events_done", []) as Array)
		out.append({"kind": "event", "need": 1, "have": 1 if done else 0, "ok": done, "event": str(req["event"])})
	var gold := Money.gold(sim.state, fam)
	var cost := cost_of(sim, fam, t)
	out.append({"kind": "gold", "need": cost, "have": gold, "ok": gold >= cost})
	return out


## What title `t` costs `fam` (its cost_gold, × the marquis's favour if it has it).
static func cost_of(sim: Sim, fam: String, t: String) -> int:
	return roundi(float(sim.catalog.titles().get(t, {}).get("cost_gold", 0))
		* float(FestivalCourt.title_mults(sim.state, fam).get("gold_mult", 1.0)))


const REQ_REASON: Dictionary = {"reputation": "title_needs_reputation", "businesses": "title_needs_businesses",
	"employees": "title_needs_employees", "event": "title_needs_event", "gold": "not_enough_gold"}


## Whether the family meets every requirement of its next title and keeps `spare` gold after paying it (the AI and
## the bots ask this before walking to the town hall).
static func ready(sim: Sim, fam: String, spare: int = 0) -> bool:
	var t := next_of(sim, fam)
	if t == "":
		return false
	for r: Dictionary in requirements(sim, fam, t):
		if not bool(r["ok"]):
			return false
	return Money.gold(sim.state, fam) >= cost_of(sim, fam, t) + spare


## The town hall's service tile of the current map ([] if it has none).
static func service(sim: Sim) -> Array:
	return sim.catalog.maps().get(sim.state.map_id, {}).get("town_hall", {}).get("service", [])


## Whether `actor` stands still on the town hall's service tile.
static func at_town_hall(sim: Sim, actor: String) -> bool:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	var svc := service(sim)
	if ch.is_empty() or svc.size() != 2 or str(ch.get("location", "")) != "" \
			or not (ch.get("path", []) as Array).is_empty():
		return false
	var pos: Array = ch.get("position", [])
	return pos.size() == 2 and int(pos[0]) == int(svc[0]) and int(pos[1]) == int(svc[1])


## What the town hall panel shows for `actor`: {family, current, next, cost, requirements, at_town_hall, reason}
## (reason "" = it can ask now; else the refusal request_title would give).
static func status(sim: Sim, actor: String) -> Dictionary:
	var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
	var nx := next_of(sim, fam)
	return {"family": fam, "current": current(sim, fam), "next": nx,
		"cost": cost_of(sim, fam, nx),
		"requirements": requirements(sim, fam, nx) if nx != "" else [],
		"at_town_hall": at_town_hall(sim, actor), "reason": _reason(sim, actor, "")}


## The refusal reason of request_title for `actor` (asking for `title`, "" = the next one), "" if it would be granted.
static func _reason(sim: Sim, actor: String, title: String) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not bool(st.characters[actor].get("alive", true)):
		return "dead"
	if not Kin.is_adult(sim, actor):
		return "too_young"
	var fam := str(st.characters[actor].get("family", ""))
	if fam == "" or not st.families.has(fam):
		return "no_family"
	var nx := next_of(sim, fam)
	if nx == "":
		return "max_title"
	if title != "" and title != nx:
		return "wrong_title"
	if not at_town_hall(sim, actor):
		return "not_at_town_hall"
	for r: Dictionary in requirements(sim, fam, nx):
		if not bool(r["ok"]):
			return str(REQ_REASON[str(r["kind"])])
	if not approved(sim, actor):
		return "title_not_approved"
	return ""


## GDD 4.12.2: the first holder of the ceremony's approvers (Mayor, then a Councillor) approves if its affinity with
## the actor is >= min_affinity; with no holder (vacant: every office until H10) it is approved by itself.
## H10: the holders are the living ones of the office's seats (Offices.holders, docs/contratos/h10_cargos.md).
static func approved(sim: Sim, actor: String) -> bool:
	var cer: Dictionary = sim.catalog.politics.get("ceremony", {})
	for office: String in cer.get("approvers", []):
		for h: String in Offices.holders(sim, office):
			if h == actor:
				return true
			var rel: Dictionary = sim.state.relationships.get(Ids.pair_key(h, actor), {})
			return int(rel.get("affinity", 0)) >= int(cer.get("min_affinity", 30))
	return true


## For the UI (a read, the same rule as approved): who approves `actor`'s title now: {office, character, affinity,
## need, ok}; {} when every approver office is vacant (it is approved by itself).
static func approver(sim: Sim, actor: String) -> Dictionary:
	var cer: Dictionary = sim.catalog.politics.get("ceremony", {})
	for office: String in cer.get("approvers", []):
		for h: String in Offices.holders(sim, office):
			var rel: Dictionary = sim.state.relationships.get(Ids.pair_key(h, actor), {})
			var aff := int(rel.get("affinity", 0))
			var need := int(cer.get("min_affinity", 30))
			return {"office": office, "character": h, "affinity": aff, "need": need, "ok": h == actor or aff >= need}
	return {}


## {"type": "request_title", "actor", "title"?}: asks for the family's next title at the town hall (GDD 4.12.2).
## Reasons: unknown_actor, dead, too_young, no_family, max_title, wrong_title, not_at_town_hall,
## title_needs_reputation / businesses / employees / event, not_enough_gold, title_not_approved.
static func order_request(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var why := _reason(sim, actor, str(o.get("title", "")))
	if why != "":
		if OS.is_debug_build():
			print("[Titles] %s no puede pedir título: %s" % [actor, why])
		return Orders.fail(why)
	var st := sim.state
	var fam := str(st.characters[actor]["family"])
	var from := current(sim, fam)
	var t := next_of(sim, fam)
	var cost := cost_of(sim, fam, t)
	if not Money.change(sim, fam, -cost, Money.TITLES, "title_" + t, "", actor):
		return Orders.fail("not_enough_gold")
	FestivalCourt.spend_title_favour(st, fam)  # fiestas: the marquis's favour is spent on this title
	st.families[fam]["title"] = t
	Chronicle.add(st, "title", {"family": fam, "title": t, "actor": actor})
	sim.events.append({"type": "title_granted", "family": fam, "actor": actor, "title": t, "from": from})
	var params := {"name": str(st.characters[actor].get("name", "")), "family": str(st.families[fam].get("name", "")),
		"title": t}
	Notices.add(sim, fam, Notices.INFO, "notice.title_granted", params, actor)
	var fams: Array = st.families.keys()
	fams.sort()
	for f: String in fams:
		if f != fam and str(st.families[f].get("controlled_by", "")) == "human":
			Notices.add(sim, f, Notices.INFO, "notice.rival_title", params, actor)
	if OS.is_debug_build():
		print("[Titles] %s (%s) sube de %s a %s por %d de oro (reputación=%d, negocios=%d, empleados=%d)" % [fam,
			actor, from, t, cost, Reputation.of(st, fam), businesses(sim, fam), employees(sim, fam)])
	return Orders.ok()
