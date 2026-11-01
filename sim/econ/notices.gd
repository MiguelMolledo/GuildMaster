class_name Notices
extends RefCounted
## The warnings log (GDD 4.18): {id, day, minute, family, severity, target, key, params, read}. Any system adds with
## add(); keeping them 1 year, reading and marking read belong to subgrim «cuentas».
## Contract: docs/contratos/h3_mercado.md.

const INFO: String = "info"
const WARNING: String = "warning"
const URGENT: String = "urgent"
const SEVERITIES: Array[String] = [INFO, WARNING, URGENT]


## Adds a notice for `fam`. `key` is an i18n key whose text takes `params` (the UI formats it); `target` is the
## building or character a click centres on ("" for none). Emits notice_added. Returns the notice id.
static func add(sim: Sim, fam: String, severity: String, key: String, params: Dictionary = {}, target: String = "") -> String:
	if not severity in SEVERITIES:
		push_error("Notices.add: unknown severity %s" % severity)
		return ""
	var st := sim.state
	var id := Ids.next(st, "ntc")
	var minute := int(st.clock["minute"])
	st.notices.append({"id": id, "day": Clock.day(minute), "minute": minute, "family": fam, "severity": severity,
		"target": target, "key": key, "params": params.duplicate(true), "read": false})
	sim.events.append({"type": "notice_added", "id": id, "family": fam, "severity": severity, "key": key,
		"params": params.duplicate(true), "target": target})
	if OS.is_debug_build():
		print("[Notices] %s %s: %s %s (objetivo=%s)" % [fam, severity, key, str(params), target])
	return id


## {"type": "read_notices", "actor", "ids": [ntc_id]}: marks them read. Every id must be a notice of the actor's
## family (unknown_notice, and nothing changes); already read ones stay read. Emits notices_read {family, ids}.
static func order_read(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not st.characters.has(actor):
		return Orders.fail("unknown_actor")
	var fam := str(st.characters[actor].get("family", ""))
	if fam == "":
		return Orders.fail("no_family")
	var raw: Variant = o.get("ids", [])
	if not raw is Array:
		return Orders.fail("unknown_notice")
	var want := {}
	for id: Variant in raw:
		want[str(id)] = true
	var found: Array = []
	for n: Dictionary in st.notices:
		if want.has(str(n["id"])) and str(n["family"]) == fam:
			found.append(n)
	if found.size() != want.size():
		return Orders.fail("unknown_notice")
	var ids: Array = []
	for n: Dictionary in found:
		n["read"] = true
		ids.append(str(n["id"]))
	sim.events.append({"type": "notices_read", "family": fam, "ids": ids})
	if OS.is_debug_build():
		print("[Notices] %s marca leídos %s (%s)" % [actor, str(ids), fam])
	return Orders.ok()


## Retention at dawn: notices older than notices_keep_years (data/accounts.json, 1 year = 8 days) go away.
static func step(sim: Sim) -> void:
	var st := sim.state
	if st.notices.is_empty() or not Ledger.is_dawn(sim):
		return
	var keep := int(sim.catalog.accounts.get("notices_keep_years", 1)) * Clock.days_per_year(sim.catalog.time)
	var first_kept := Clock.day(int(st.clock["minute"])) - keep + 1
	if int(st.notices[0]["day"]) >= first_kept:
		return
	var before := st.notices.size()
	st.notices = st.notices.filter(func(n: Dictionary) -> bool: return int(n["day"]) >= first_kept)
	if OS.is_debug_build():
		print("[Notices] retención: %d avisos anteriores al día %d se borran" % [before - st.notices.size(), first_kept])


## The notices of `fam`, newest first (`unread_only` to filter). Copies.
static func list(sim: Sim, fam: String, unread_only: bool = false) -> Array:
	var out: Array = []
	for i: int in range(sim.state.notices.size() - 1, -1, -1):
		var n: Dictionary = sim.state.notices[i]
		if str(n["family"]) == fam and not (unread_only and bool(n["read"])):
			out.append(n.duplicate(true))
	return out


## How many unread notices `fam` has (the HUD badge).
static func unread_count(sim: Sim, fam: String) -> int:
	var n := 0
	for x: Dictionary in sim.state.notices:
		if str(x["family"]) == fam and not bool(x["read"]):
			n += 1
	return n
