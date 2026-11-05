class_name Contracts
extends RefCounted
## NPC contracts (GDD 4.5.6): the board in the square, accepting, delivering, abandoning, deadlines.
## Owner: subgrim «rival». Contract: docs/contratos/h3_mercado.md. Figures in data/contracts/<profession>.json and
## data/market.json "board". Gold through Money.change (category contracts); it does not touch market demand.
##
## State (state.contracts): {board: [contract], accepted: [contract], cooldowns: {client: until_day},
## relations: {"fam|client": int}}. A contract:
##   {id: "ctr_0001", client, item, qty, min_quality, deadline_days, pay, posted (minute), script: "" | id,
##    family: "", actor: "", accepted: -1 (minute), due: -1 (minute), warned: [hours already warned]}
## Closed contracts (delivered, expired, abandoned) leave the lists. «At dawn» = this step has a phase_changed event
## with phase "dawn".


# --- Orders ----------------------------------------------------------------------------------------------------------

## {"type": "accept_contract", "actor", "contract"}: at the board, an open contract, at most max_accepted_per_family
## accepted per family at a time. The first one who accepts keeps it.
static func order_accept(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var id := str(o.get("contract", ""))
	var why := _actor_reason(sim, actor)
	if why != "":
		return Orders.fail(why)
	var i := _index(sim.state.contracts.get("board", []), id)
	if i < 0:
		return Orders.fail("contract_taken" if _index(sim.state.contracts.get("accepted", []), id) >= 0 \
			else "unknown_contract")
	if not at_board(sim, actor):
		return Orders.fail("not_at_board")
	var fam := str(sim.state.characters[actor].get("family", ""))
	if bool(sim.state.contracts["board"][i].get("race", false)):  # 4.25.4: festival contracts, a race (FestivalContracts)
		return FestivalContracts.accept(sim, actor, fam, sim.state.contracts["board"][i])
	if _plain_count(accepted_of(sim, fam)) >= int(_board_cfg(sim).get("max_accepted_per_family", 2)):
		return Orders.fail("too_many_contracts")
	var board: Array = sim.state.contracts["board"]
	var c: Dictionary = board[i]
	board.remove_at(i)
	var now := _now(sim)
	c["family"] = fam
	c["actor"] = actor
	c["accepted"] = now
	c["due"] = now + int(c.get("deadline_days", 1)) * Clock.MINUTES_PER_DAY
	c["warned"] = []
	(sim.state.contracts["accepted"] as Array).append(c)
	sim.events.append({"type": "contract_accepted", "actor": actor, "family": fam, "contract": id})
	if OS.is_debug_build():
		print("[Contracts] %s (%s) acepta %s: %d× %s calidad>=%d, paga %d, vence min %d" % [actor, fam, id,
			int(c["qty"]), c["item"], int(c["min_quality"]), int(c["pay"]), int(c["due"])])
	return Orders.ok()


## {"type": "deliver_contract", "actor", "contract"}: at the board, accepted by the actor's family, the pieces
## (quality >= minimum) in the actor's bag. Takes them (lowest valid quality first), pays `pay` (Money, contracts),
## reputation + reward_reputation, relation with the client + reward_relation. Market demand does not change.
static func order_deliver(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var id := str(o.get("contract", ""))
	var why := _actor_reason(sim, actor)
	if why != "":
		return Orders.fail(why)
	var accepted: Array = sim.state.contracts.get("accepted", [])
	var fam := str(sim.state.characters[actor].get("family", ""))
	var i := _index_of(accepted, id, fam)
	if i < 0:
		return Orders.fail("not_your_contract" if _index(sim.state.contracts.get("board", []), id) >= 0 \
			else "unknown_contract")
	var c: Dictionary = accepted[i]
	if str(c.get("family", "")) != fam:
		return Orders.fail("not_your_contract")
	if not at_board(sim, actor):
		return Orders.fail("not_at_board")
	var bag: Dictionary = sim.state.characters[actor]["inventory"]
	var item := str(c["item"])
	var qty := int(c["qty"])
	var min_q := int(c.get("min_quality", 0))
	if count_valid(bag, item, min_q) < qty:
		return Orders.fail("missing_items")
	if not Money.change(sim, fam, int(c["pay"]), Money.CONTRACTS, id, "", actor):
		return Orders.fail("unknown_family")
	var left := qty
	for q: int in Inventory.QUALITIES:
		if q < min_q or left == 0:
			continue
		var take := mini(left, Inventory.count(bag, item, q))
		if take > 0:
			Inventory.remove(bag, item, q, take)
			left -= take
	accepted.remove_at(i)
	if bool(c.get("race", false)):  # 4.25.4: the winner of a festival contract (rewards, chronicle, the others lose it)
		FestivalContracts.delivered(sim, c, fam, actor)
	else:
		var t := table_for_item(sim.catalog, item)
		_reputation(sim, fam, int(t.get("reward_reputation", 0)), "contract_done")
		_relation(sim, fam, str(c["client"]), int(t.get("reward_relation", 0)))
	sim.events.append({"type": "contract_delivered", "actor": actor, "family": fam, "contract": id,
		"client": str(c["client"]), "item": item, "qty": qty, "min_quality": min_q, "pay": int(c["pay"]),
		"script": str(c.get("script", ""))})
	if OS.is_debug_build():
		print("[Contracts] %s (%s) entrega %s: %d× %s, cobra %d" % [actor, fam, id, qty, item, int(c["pay"])])
	return Orders.ok()


## {"type": "abandon_contract", "actor", "contract"}: accepted by the actor's family, from anywhere. Counts as failed.
static func order_abandon(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	var id := str(o.get("contract", ""))
	var why := _actor_reason(sim, actor)
	if why != "":
		return Orders.fail(why)
	var accepted: Array = sim.state.contracts.get("accepted", [])
	var i := _index_of(accepted, id, str(sim.state.characters[actor].get("family", "")))
	if i < 0:
		return Orders.fail("not_your_contract" if _index(sim.state.contracts.get("board", []), id) >= 0 \
			else "unknown_contract")
	if str(accepted[i].get("family", "")) != str(sim.state.characters[actor].get("family", "")):
		return Orders.fail("not_your_contract")
	_fail(sim, i, "abandoned")
	return Orders.ok()


# --- Step ------------------------------------------------------------------------------------------------------------

## Expiries, deadline warnings (warn_hours before the due minute) and, at dawn, a new contract if the board has room.
static func step(sim: Sim) -> void:
	var now := _now(sim)
	var accepted: Array = sim.state.contracts.get("accepted", [])
	for i: int in range(accepted.size() - 1, -1, -1):
		if now >= int(accepted[i].get("due", -1)):
			_fail(sim, i, "expired")
	for c: Dictionary in sim.state.contracts.get("accepted", []):
		_warn(sim, c, now)
	var dawn := false
	for e: Dictionary in sim.events:
		if str(e.get("type", "")) == "phase_changed" and str(e.get("phase", "")) == "dawn":
			dawn = true
			break
	if dawn:
		var cfg := _board_cfg(sim)
		for n: int in int(cfg.get("new_per_dawn", 1)):
			if _plain_count(sim.state.contracts.get("board", [])) >= int(cfg.get("max_open", 3)):
				break
			post_random(sim)


## Posts a contract drawn from the tables of data/contracts/ (state.rng): a client off cooldown, an item with qty in
## [min, max], a minimum quality in min_quality_chance of them (one of min_qualities), a deadline in deadline_days.
## Returns its id, "" if no client is available.
## H12: the tables are those of the professions of the heads of the human families (the player's trade: a carpenter
## gets carpentry contracts); all of them if none matches.
static func post_random(sim: Sim) -> String:
	var st := sim.state
	var tables := board_tables(sim)
	if tables.is_empty():
		return ""
	var t: Dictionary = sim.catalog.contracts()[str(tables[st.rng.randi_range(0, tables.size() - 1)])]
	var today := Clock.day(_now(sim))
	var clients: Array = []
	for cl: Dictionary in t.get("clients", []):
		if int(st.contracts.get("cooldowns", {}).get(str(cl["id"]), -1)) <= today:
			clients.append(str(cl["id"]))
	var items: Array = t.get("items", [])
	if clients.is_empty() or items.is_empty():
		if OS.is_debug_build():
			print("[Contracts] amanecer: no hay cliente libre en %s" % t.get("id", ""))
		return ""
	var client := str(clients[st.rng.randi_range(0, clients.size() - 1)])
	var it: Dictionary = items[st.rng.randi_range(0, items.size() - 1)]
	var qr: Array = it.get("qty", [1, 1])
	var qty := st.rng.randi_range(int(qr[0]), int(qr[1]))
	var min_q := 0
	var mqs: Array = t.get("min_qualities", [])
	if st.rng.randf() < float(it.get("min_quality_chance", 0.0)) and not mqs.is_empty():
		min_q = int(mqs[st.rng.randi_range(0, mqs.size() - 1)])
	var dr: Array = t.get("deadline_days", [1, 1])
	var days := st.rng.randi_range(int(dr[0]), int(dr[1]))
	return post(sim, {"client": client, "item": str(it["item"]), "qty": qty, "min_quality": min_q,
		"deadline_days": days})


## Puts a contract on the board: `def` = {client, item, qty, min_quality, deadline_days, script?}. The pay is fixed
## now: round(qty × Market.price(item, min_quality, "sell") × (1 + premium)). Emits contract_posted. Returns its id.
## The scripted contracts of a start (data/starts "contracts") go through here (see post_scripted).
static func post(sim: Sim, def: Dictionary) -> String:
	var st := sim.state
	var item := str(def.get("item", ""))
	var qty := int(def.get("qty", 1))
	var min_q := int(def.get("min_quality", 0))
	var premium := float(table_for_item(sim.catalog, item).get("premium", 0.0))
	var c := {"id": Ids.next(st, "ctr"), "client": str(def.get("client", "")), "item": item, "qty": qty,
		"min_quality": min_q, "deadline_days": int(def.get("deadline_days", 1)),
		"pay": pay_for(sim, item, min_q, qty, premium), "posted": _now(sim), "script": str(def.get("script", "")),
		"family": "", "actor": "", "accepted": -1, "due": -1, "warned": []}
	(st.contracts["board"] as Array).append(c)
	sim.events.append({"type": "contract_posted", "contract": str(c["id"])})
	if OS.is_debug_build():
		print("[Contracts] publica %s: %s pide %d× %s calidad>=%d en %d días, paga %d (guion=%s)" % [c["id"],
			c["client"], qty, item, min_q, int(c["deadline_days"]), int(c["pay"]), c["script"]])
	return str(c["id"])


## For NewGame.from_start: posts the scripted contracts of a start on the board of `state` (prices of that state).
static func post_scripted(state: WorldState, catalog: Catalog, defs: Array) -> Array:
	var sim := Sim.new(state, catalog)
	var ids: Array = []
	for d: Dictionary in defs:
		ids.append(post(sim, d))
	return ids


## qty × sell price of the item at that quality now × (1 + premium), rounded.
static func pay_for(sim: Sim, item: String, quality: int, qty: int, premium: float) -> int:
	return roundi(qty * Market.price(sim, item, quality, "sell") * (1.0 + premium))


# --- Queries (UI, AI) ------------------------------------------------------------------------------------------------

## What the board shows to `actor`: {at_board: bool, open: [contract + {status}], accepted: [contract + {status,
## hours_left}]} (status "ok" | a refusal reason). `accepted` holds only the actor's family's.
static func board_view(sim: Sim, actor: String) -> Dictionary:
	var out := {"at_board": at_board(sim, actor), "open": [], "accepted": []}
	var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
	var why := _actor_reason(sim, actor)
	var full := _plain_count(accepted_of(sim, fam)) >= int(_board_cfg(sim).get("max_accepted_per_family", 2))
	for c: Dictionary in sim.state.contracts.get("board", []):
		var v := c.duplicate(true)
		var s := why
		if s == "" and not out["at_board"]:
			s = "not_at_board"
		if s == "" and bool(c.get("race", false)):  # 4.25.4: festival contracts have their own rules
			s = FestivalContracts.status(sim, fam, c)
		elif s == "" and full:
			s = "too_many_contracts"
		v["status"] = s if s != "" else "ok"
		(out["open"] as Array).append(v)
	var now := _now(sim)
	for c: Dictionary in accepted_of(sim, fam):
		var v := c.duplicate(true)
		var s := why
		if s == "" and not out["at_board"]:
			s = "not_at_board"
		if s == "" and count_valid(sim.state.characters[actor]["inventory"], str(c["item"]),
				int(c.get("min_quality", 0))) < int(c["qty"]):
			s = "missing_items"
		v["status"] = s if s != "" else "ok"
		v["hours_left"] = ceili(maxf(0.0, float(int(c["due"]) - now)) / 60.0)
		(out["accepted"] as Array).append(v)
	return out


## The contracts accepted by `fam` now (references into the state; do not modify).
static func accepted_of(sim: Sim, fam: String) -> Array:
	var out: Array = []
	if fam == "":
		return out
	for c: Dictionary in sim.state.contracts.get("accepted", []):
		if str(c.get("family", "")) == fam:
			out.append(c)
	return out


## Whether `actor` stands at the board's service tile (on the map, not walking).
static func at_board(sim: Sim, actor: String) -> bool:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	var svc := board_service(sim)
	if ch.is_empty() or svc.size() != 2 or str(ch.get("location", "")) != "" \
			or not (ch.get("path", []) as Array).is_empty():
		return false
	var pos: Array = ch.get("position", [])
	return pos.size() == 2 and int(pos[0]) == int(svc[0]) and int(pos[1]) == int(svc[1])


## The board's service tile of the current map ([] if the map has no board).
static func board_service(sim: Sim) -> Array:
	return sim.catalog.maps().get(sim.state.map_id, {}).get("board", {}).get("service", [])


## Units of `item` in `inv` with quality >= `min_quality`.
static func count_valid(inv: Dictionary, item: String, min_quality: int) -> int:
	var n := 0
	for q: int in Inventory.QUALITIES:
		if q >= min_quality:
			n += Inventory.count(inv, item, q)
	return n


## The relation of `fam` with a client (0 if never touched).
static func relation(sim: Sim, fam: String, client: String) -> int:
	return int(sim.state.contracts.get("relations", {}).get("%s|%s" % [fam, client], 0))


## H12: the ids of the contract tables the board draws from (sorted): the tables whose profession is the profession
## of the head of a human family; every table if none matches.
static func board_tables(sim: Sim) -> Array:
	var all: Array = sim.catalog.contracts().keys()
	all.sort()
	var profs := {}
	var fams: Array = sim.state.families.keys()
	fams.sort()
	for f: String in fams:
		var fam: Dictionary = sim.state.families[f]
		if str(fam.get("controlled_by", "")) != "human":
			continue
		var head := str(fam.get("head", ""))
		var prof := str(sim.state.characters.get(head, {}).get("profession", ""))
		if prof != "":
			profs[prof] = true
	var out: Array = []
	for id: String in all:
		if profs.has(str(sim.catalog.contracts()[id].get("profession", ""))):
			out.append(id)
	return out if not out.is_empty() else all


## The data/contracts/ table that has `item` (the first by id), else the first table, else {}.
static func table_for_item(catalog: Catalog, item: String) -> Dictionary:
	var ids: Array = catalog.contracts().keys()
	ids.sort()
	for id: String in ids:
		for it: Dictionary in catalog.contracts()[id].get("items", []):
			if str(it.get("item", "")) == item:
				return catalog.contracts()[id]
	return catalog.contracts()[str(ids[0])] if not ids.is_empty() else {}


# --- Helpers ---------------------------------------------------------------------------------------------------------

## Failed (expired or abandoned): reputation + fail_reputation, relation + fail_relation, the client posts nothing
## for client_cooldown_days.
static func _fail(sim: Sim, i: int, reason: String) -> void:
	var accepted: Array = sim.state.contracts["accepted"]
	var c: Dictionary = accepted[i]
	accepted.remove_at(i)
	var fam := str(c.get("family", ""))
	var client := str(c["client"])
	var t := FestivalContracts.fail_table(c) if bool(c.get("race", false)) else table_for_item(sim.catalog, str(c["item"]))
	_reputation(sim, fam, int(t.get("fail_reputation", 0)), "contract_failed")
	_relation(sim, fam, client, int(t.get("fail_relation", 0)))
	var until := Clock.day(_now(sim)) + int(t.get("client_cooldown_days", 0))
	sim.state.contracts["cooldowns"][client] = maxi(until, int(sim.state.contracts["cooldowns"].get(client, -1)))
	sim.events.append({"type": "contract_failed", "family": fam, "contract": str(c["id"]), "reason": reason})
	if reason == "expired":
		Notices.add(sim, fam, Notices.WARNING, "notice.contract_expired", {"contract": str(c["id"]), "client": client,
			"item": str(c["item"]), "qty": int(c["qty"]), "reputation": int(t.get("fail_reputation", 0)),
			"days": int(t.get("client_cooldown_days", 0))}, str(c.get("actor", "")))
	if OS.is_debug_build():
		print("[Contracts] %s incumple %s (%s): cliente %s sin encargos hasta el día %d" % [fam, c["id"], reason,
			client, until])


## Deadline warnings: once per warn_hours entry, when the time left drops to it (only if the contract was accepted
## with more time than that left).
static func _warn(sim: Sim, c: Dictionary, now: int) -> void:
	var left := int(c["due"]) - now
	var span := int(c["due"]) - int(c["accepted"])
	var warned: Array = c.get("warned", [])
	for h: int in _board_cfg(sim).get("warn_hours", []):
		var m := int(h) * 60
		if left <= m and span > m and not int(h) in warned:
			warned.append(int(h))
			c["warned"] = warned
			var sev := Notices.URGENT if int(h) <= 2 else Notices.WARNING
			Notices.add(sim, str(c["family"]), sev, "notice.contract_due", {"contract": str(c["id"]),
				"client": str(c["client"]), "item": str(c["item"]), "qty": int(c["qty"]), "hours": int(h)},
				str(c.get("actor", "")))


static func _reputation(sim: Sim, fam: String, amount: int, reason: String) -> void:
	Reputation.change(sim, fam, amount, reason)  # H9: the only way (class of the reason, log, event)


static func _relation(sim: Sim, fam: String, client: String, amount: int) -> void:
	if amount == 0 or fam == "":
		return
	var key := "%s|%s" % [fam, client]
	var rel: Dictionary = sim.state.contracts["relations"]
	rel[key] = int(rel.get(key, 0)) + amount


static func _actor_reason(sim: Sim, actor: String) -> String:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	if ch.is_empty():
		return "unknown_actor"
	if not bool(ch.get("alive", true)):
		return "dead"
	if not sim.state.families.has(str(ch.get("family", ""))):
		return "no_family"
	return ""


## The index of contract `id` of family `fam` in `list` (festival contracts have one copy per family), else the first
## with that id, else -1.
static func _index_of(list: Array, id: String, fam: String) -> int:
	var first := -1
	for i: int in list.size():
		if str(list[i].get("id", "")) == id:
			if str(list[i].get("family", "")) == fam:
				return i
			if first < 0:
				first = i
	return first


## How many of `list` are plain contracts (not the festival ones of 4.25.4, which have their own limits).
static func _plain_count(list: Array) -> int:
	var n := 0
	for c: Dictionary in list:
		if not bool(c.get("race", false)):
			n += 1
	return n


static func _index(list: Array, id: String) -> int:
	for i: int in list.size():
		if str(list[i].get("id", "")) == id:
			return i
	return -1


static func _board_cfg(sim: Sim) -> Dictionary:
	return sim.catalog.market.get("board", {})


static func _now(sim: Sim) -> int:
	return int(sim.state.clock["minute"])
