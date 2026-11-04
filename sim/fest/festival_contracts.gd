class_name FestivalContracts
extends RefCounted
## 4.25.4 · the festival and wedding contracts (data/contracts/festivals.json, Catalog.festival_contracts). They go up
## on the board with the town crier (Festivals._announce) and live in state.contracts like the others, with these
## fields more: festival (the instance id), festival_def, race true, due_at (the fixed due minute: due_hour of the
## feast's day), what (what it is at the feast: festival_contract.<what>), reputation, relation, fail_reputation,
## chronicle, hosts (the wedding's families: they cannot take their own).
##
## A race (4.25.4 «un solo ganador»): several families may accept the same contract (each gets its own copy in
## accepted, the board keeps the original); the first to deliver it with the quality asked wins: it is paid
## (Contracts.order_deliver), gets the reputation and the relation of the entry (and with the hosts' heads), a line in
## the chronicle when the entry says so, and the others lose it without penalty (contract_lost, a notice). Unclaimed
## at due_at, it leaves the board; a copy still accepted then fails like any contract (fail_reputation, small).

## The rows of table `id` ([] if unknown).
static func table(sim: Sim, id: String) -> Array:
	if id == "":
		return []
	return sim.catalog.festival_contracts.get("tables", {}).get(id, [])


static func _defaults(sim: Sim) -> Dictionary:
	return sim.catalog.festival_contracts.get("defaults", {})


## Posts the rows of the feast's table that are not posted yet and may be: their `needs` met, a maker in town (a
## family, human or with an AI profile, that owns the workshop of the row's profession; «any» always), and time left.
static func post_for(sim: Sim, inst: Dictionary) -> void:
	var st := sim.state
	var d := Festivals.def_of(sim, str(inst["def"]))
	var rows := table(sim, str(d.get("contracts", "")))
	if rows.is_empty():
		return
	var now := int(st.clock["minute"])
	var r: Dictionary = Festivals.rules(sim).get("contracts", {})
	var due := maxi(int(inst["day"]) * Festivals.MPD + int(r.get("due_hour", 17)) * 60, int(inst["start"]))
	due = mini(due, int(inst["end"]))
	if due <= now + 60:
		return
	var posted: Array = inst.get("posted_rows", [])
	for i: int in rows.size():
		var row: Dictionary = rows[i]
		if i in posted or not Festivals._part_ok(inst, row) or not _maker_exists(sim, str(row.get("profession", ""))):
			continue
		posted.append(i)
		var id := _post(sim, inst, row, due)
		(inst["contracts"] as Array).append(id)
	inst["posted_rows"] = posted


static func _post(sim: Sim, inst: Dictionary, row: Dictionary, due: int) -> String:
	var st := sim.state
	var dft := _defaults(sim)
	var now := int(st.clock["minute"])
	var item := str(row.get("item", ""))
	var qty := int(row.get("qty", 1))
	var min_q := int(row.get("min_quality", 0))
	var premium := float(row.get("premium", dft.get("premium", 0.6)))
	var c := {"id": Ids.next(st, "ctr"), "client": str(row.get("client", "town_council")), "item": item, "qty": qty,
		"min_quality": min_q, "deadline_days": maxi(1, ceili(float(due - now) / float(Festivals.MPD))),
		"pay": Contracts.pay_for(sim, item, min_q, qty, premium), "posted": now, "script": "", "family": "",
		"actor": "", "accepted": -1, "due": -1, "warned": [],
		"festival": str(inst["id"]), "festival_def": str(inst["def"]), "race": true, "due_at": due,
		"what": str(row.get("what", "")), "profession": str(row.get("profession", "")),
		"reputation": int(row.get("reputation", dft.get("reputation", 2))),
		"relation": int(row.get("relation", dft.get("relation", 8))),
		"fail_reputation": int(row.get("fail_reputation", dft.get("fail_reputation", -3))),
		"chronicle": bool(row.get("chronicle", false)), "hosts": (inst.get("hosts", []) as Array).duplicate()}
	(st.contracts["board"] as Array).append(c)
	sim.events.append({"type": "contract_posted", "contract": str(c["id"]), "festival": str(inst["id"])})
	if OS.is_debug_build():
		print("[FestivalContracts] %s para %s: %s pide %d× %s calidad>=%d, paga %d, vence min %d (%s)" % [c["id"],
			inst["def"], c["client"], qty, item, min_q, int(c["pay"]), due, c["what"]])
	return str(c["id"])


## Whether somebody in town can make a row of `prof`: «any», or a family (human, or AI with a profile) owning a
## building of that profession's workshop type.
static func _maker_exists(sim: Sim, prof: String) -> bool:
	if prof == "any" or prof == "":
		return true
	var btype := str(sim.catalog.professions().get(prof, {}).get("building", ""))
	if btype == "":
		return false
	for bid: Variant in sim.state.buildings:
		if str(sim.state.buildings[bid].get("type", "")) != btype:
			continue
		var fam := Money.family_of(sim.state, str(bid))
		var f: Dictionary = sim.state.families.get(fam, {})
		if str(f.get("controlled_by", "")) == "human" or str(f.get("ai_profile", "")) != "":
			return true
	return false


## Unclaimed contracts whose due_at has come leave the board (contract_expired_unclaimed). The accepted copies fail in
## Contracts.step at their due (the same minute).
static func expire(sim: Sim, now: int) -> void:
	var board: Array = sim.state.contracts.get("board", [])
	for i: int in range(board.size() - 1, -1, -1):
		var c: Dictionary = board[i]
		if bool(c.get("race", false)) and now >= int(c.get("due_at", 0)):
			board.remove_at(i)
			sim.events.append({"type": "festival_contract_expired", "contract": str(c["id"]),
				"festival": str(c.get("festival", ""))})
			if OS.is_debug_build():
				print("[FestivalContracts] %s (%s) vence sin entregar" % [c["id"], c.get("festival_def", "")])


# --- What Contracts asks -------------------------------------------------------------------------------------------

## "" if family `fam` may accept race contract `c` now, else why: contract_mine (it already did), own_festival (its
## own wedding), too_many_festival_contracts.
static func status(sim: Sim, fam: String, c: Dictionary) -> String:
	for a: Dictionary in sim.state.contracts.get("accepted", []):
		if str(a.get("id", "")) == str(c.get("id", "")) and str(a.get("family", "")) == fam:
			return "contract_mine"
	if fam in (c.get("hosts", []) as Array):
		return "own_festival"
	var n := 0
	for a: Dictionary in sim.state.contracts.get("accepted", []):
		if str(a.get("family", "")) == fam and bool(a.get("race", false)):
			n += 1
	if n >= int(Festivals.rules(sim).get("contracts", {}).get("max_accepted_per_family", 2)):
		return "too_many_festival_contracts"
	return ""


## accept_contract on a race contract (Contracts.order_accept checked the actor and the board): a copy for the family.
static func accept(sim: Sim, actor: String, fam: String, c: Dictionary) -> Dictionary:
	var why := status(sim, fam, c)
	if why != "":
		return Orders.fail(why)
	var copy := c.duplicate(true)
	var now := int(sim.state.clock["minute"])
	copy["family"] = fam
	copy["actor"] = actor
	copy["accepted"] = now
	copy["due"] = int(c.get("due_at", now + Festivals.MPD))
	copy["warned"] = []
	(sim.state.contracts["accepted"] as Array).append(copy)
	sim.events.append({"type": "contract_accepted", "actor": actor, "family": fam, "contract": str(c["id"]),
		"festival": str(c.get("festival", ""))})
	if OS.is_debug_build():
		print("[FestivalContracts] %s (%s) entra en la carrera de %s (%d× %s, vence min %d)" % [actor, fam, c["id"],
			int(c["qty"]), c["item"], int(copy["due"])])
	return Orders.ok()


## The winner delivered race contract `c` (already paid and its pieces taken): rewards, chronicle, the rest lose it.
static func delivered(sim: Sim, c: Dictionary, fam: String, actor: String) -> void:
	var st := sim.state
	var id := str(c["id"])
	Reputation.change(sim, fam, int(c.get("reputation", 0)), "festival_contract")
	var rel: Dictionary = st.contracts["relations"]
	var key := "%s|%s" % [fam, str(c.get("client", ""))]
	rel[key] = int(rel.get(key, 0)) + int(c.get("relation", 0))
	var head := Kin.head(st, fam)
	for h: Variant in c.get("hosts", []):
		var other := Kin.head(st, str(h))
		if head != "" and other != "" and other != head:
			Emotions.change_relation(sim, head, other, int(c.get("relation", 0)), "festival_contract")
	if bool(c.get("chronicle", false)):
		Chronicle.add(st, "festival_contract", {"family": fam, "character": actor, "festival": str(c.get("festival_def", "")),
			"item": str(c.get("item", "")), "what": str(c.get("what", "")), "client": str(c.get("client", ""))})
	var board: Array = st.contracts["board"]
	for i: int in range(board.size() - 1, -1, -1):
		if str(board[i].get("id", "")) == id:
			board.remove_at(i)
	var accepted: Array = st.contracts["accepted"]
	for i: int in range(accepted.size() - 1, -1, -1):
		var a: Dictionary = accepted[i]
		if str(a.get("id", "")) != id:
			continue
		var loser := str(a.get("family", ""))
		accepted.remove_at(i)
		sim.events.append({"type": "contract_lost", "family": loser, "contract": id, "winner": fam})
		if str(st.families.get(loser, {}).get("controlled_by", "")) == "human":
			Notices.add(sim, loser, Notices.WARNING, "notice.festival_contract_lost", {"item": str(c.get("item", "")),
				"family": str(st.families.get(fam, {}).get("name", ""))}, str(a.get("actor", "")))
	var inst := Festivals.find(sim, str(c.get("festival", "")))
	if not inst.is_empty():
		if not inst.get("done_items") is Array:
			inst["done_items"] = []
		(inst["done_items"] as Array).append(str(c.get("item", "")))
	sim.events.append({"type": "festival_contract_done", "family": fam, "contract": id, "festival": str(c.get("festival", "")),
		"festival_def": str(c.get("festival_def", "")), "item": str(c.get("item", "")), "chronicle": bool(c.get("chronicle", false))})
	if OS.is_debug_build():
		print("[FestivalContracts] %s gana %s (%s para %s): reputación %+d, relación %+d" % [fam, id, c.get("item", ""),
			c.get("festival_def", ""), int(c.get("reputation", 0)), int(c.get("relation", 0))])


## The penalty table of a race contract that fails (expired or abandoned): no client cooldown.
static func fail_table(c: Dictionary) -> Dictionary:
	return {"fail_reputation": int(c.get("fail_reputation", -3)), "fail_relation": 0, "client_cooldown_days": 0}


## Whether race contract of `item` of feast `inst` was delivered (the view shows the arch or the tribune then).
static func done_item(sim: Sim, inst: Dictionary, item: String) -> bool:
	return item in (inst.get("done_items", []) as Array)


## The race contracts on the board of feast `inst` (open), for its card.
static func open_of(sim: Sim, inst: Dictionary) -> Array:
	var out: Array = []
	for c: Dictionary in sim.state.contracts.get("board", []):
		if str(c.get("festival", "")) == str(inst.get("id", "")):
			out.append(c)
	return out
