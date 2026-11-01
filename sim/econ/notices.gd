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


## {"type": "read_notices", "actor", "ids": [ntc_id]}: marks them read (the actor's family's only).
static func order_read(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


## Retention (1 year) at dawn.
static func step(_sim: Sim) -> void:
	pass


## The notices of `fam`, newest first (`unread_only` to filter).
static func list(_sim: Sim, _fam: String, _unread_only: bool = false) -> Array:
	return []
