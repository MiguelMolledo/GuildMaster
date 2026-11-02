class_name Emotions
extends RefCounted
## Temporary emotional states (GDD 4.11.5), the 4 of the MVP: grateful, offended, angry, scared. Separate from the
## permanent relation. state.emotions[chr] = [{state, source, start, duration, intensity0}]: `source` is the family
## that caused it (prices and treatment are the family's) [provisional]; start and duration in game minutes; the
## intensity is derived (intensity0 × (1 − elapsed / duration)), never stored minute by minute.
## Contract: docs/contratos/h7_ciudad.md. Figures: data/town.json "emotions", "incompatible", "max_per_source".

const FULL: float = 100.0


## A new state of `chr` towards family `source` (its duration drawn from the town stream). The incompatible one
## (grateful <-> angry) and the same state towards that source are replaced; with max_per_source already active
## towards it, the oldest goes. Returns the emotion.
static func add(sim: Sim, chr: String, state: String, source: String) -> Dictionary:
	var st := sim.state
	var def: Dictionary = sim.catalog.town.get("emotions", {}).get(state, {})
	if def.is_empty() or not st.characters.has(chr):
		return {}
	var now := int(st.clock["minute"])
	var span: Array = def.get("duration_days", [1, 1])
	var r := Kin.roll(st, "emo|%s|%s|%s|%d" % [chr, state, source, now])
	var days := float(span[0]) + (float(span[1]) - float(span[0])) * r
	var e := {"state": state, "source": source, "start": now, "duration": maxi(1, roundi(days * Clock.MINUTES_PER_DAY)),
		"intensity0": int(FULL)}
	var bad := [state]
	for pair: Array in sim.catalog.town.get("incompatible", []):
		if state in pair:
			bad.append(str(pair[0]) if str(pair[1]) == state else str(pair[1]))
	var keep: Array = []
	for old: Dictionary in st.emotions.get(chr, []):
		if str(old.get("source", "")) == source and str(old.get("state", "")) in bad:
			_ended(sim, chr, old, "replaced")
			continue
		keep.append(old)
	var same: Array = keep.filter(func(x: Dictionary) -> bool: return str(x.get("source", "")) == source)
	var cap := int(sim.catalog.town.get("max_per_source", 2))
	while same.size() >= cap:
		var oldest: Dictionary = same.pop_front()
		keep.erase(oldest)
		_ended(sim, chr, oldest, "replaced")
	keep.append(e)
	st.emotions[chr] = keep
	sim.events.append({"type": "emotion_added", "character": chr, "state": state, "source": source})
	if OS.is_debug_build():
		print("[Emotions] %s se siente %s hacia %s (%.1f días)" % [chr, state, source, days])
	return e


## Every hour on the hour: the states that reached 0 end (relation_on_expire with the family's head as the other
## party: the permanent relation is between people).
static func step(sim: Sim) -> void:
	var st := sim.state
	if st.emotions.is_empty():
		return
	var now := int(st.clock["minute"])
	if now % 60 != 0:
		return
	var ids: Array = st.emotions.keys()
	ids.sort()
	for chr: String in ids:
		var keep: Array = []
		for e: Dictionary in st.emotions[chr]:
			if now >= int(e.get("start", 0)) + int(e.get("duration", 0)):
				_ended(sim, chr, e, "expired")
				continue
			keep.append(e)
		if keep.is_empty():
			st.emotions.erase(chr)
		else:
			st.emotions[chr] = keep


static func _ended(sim: Sim, chr: String, e: Dictionary, why: String) -> void:
	var def: Dictionary = sim.catalog.town.get("emotions", {}).get(str(e.get("state", "")), {})
	var res := int(def.get("relation_on_expire", 0))
	var src := str(e.get("source", ""))
	if why == "expired" and res != 0:
		var head := Kin.head(sim.state, src)
		if head != "" and head != chr:
			change_relation(sim, head, chr, res, "emotion_expired")
	sim.events.append({"type": "emotion_ended", "character": chr, "state": str(e.get("state", "")), "source": src,
		"reason": why})
	if OS.is_debug_build():
		print("[Emotions] a %s se le pasa %s hacia %s (%s)" % [chr, e.get("state", ""), src, why])


## The permanent relation (-100..100) between two characters changes by `amount`.
static func change_relation(sim: Sim, a: String, b: String, amount: int, why: String) -> int:
	var rel := Courtship.relation(sim.state, a, b)
	var before := int(rel.get("relation", 0))
	rel["relation"] = clampi(before + amount, -100, 100)
	sim.events.append({"type": "relation_changed", "actor": a, "target": b, "amount": int(rel["relation"]) - before,
		"relation": int(rel["relation"]), "reason": why})
	return int(rel["relation"])


## The relation between two characters (0 if they never dealt).
static func relation(st: WorldState, a: String, b: String) -> int:
	var r: Variant = st.relationships.get(Ids.pair_key(a, b))
	return int((r as Dictionary).get("relation", 0)) if r is Dictionary else 0


## The intensity (0..100) of an emotion now.
static func intensity(sim: Sim, e: Dictionary) -> float:
	var dur := maxf(1.0, float(e.get("duration", 1)))
	var left := 1.0 - (float(sim.state.clock["minute"]) - float(e.get("start", 0))) / dur
	return clampf(float(e.get("intensity0", FULL)) * left, 0.0, FULL)


## The active states of `chr` towards family `source` ("" = towards anybody).
static func active(sim: Sim, chr: String, source: String = "") -> Array:
	var out: Array = []
	for e: Dictionary in sim.state.emotions.get(chr, []):
		if (source == "" or str(e.get("source", "")) == source) and intensity(sim, e) > 0.0:
			out.append(e)
	return out


## Whether `chr` holds `state` towards `source`.
static func has(sim: Sim, chr: String, state: String, source: String) -> bool:
	for e: Dictionary in active(sim, chr, source):
		if str(e["state"]) == state:
			return true
	return false


## What family `fam` pays buying from (`side` "buy") or gets selling to (`side` "sell") `chr`: the product of the
## buy_mult / sell_mult of its states towards the family (1.0 without any).
static func price_mult(sim: Sim, chr: String, fam: String, side: String) -> float:
	var m := 1.0
	var defs: Dictionary = sim.catalog.town.get("emotions", {})
	for e: Dictionary in active(sim, chr, fam):
		m *= float(defs.get(str(e["state"]), {}).get("buy_mult" if side == "buy" else "sell_mult", 1.0))
	return m


## Whether `chr` refuses to trade with family `fam` (angry above refuses_trade_over).
static func refuses_trade(sim: Sim, chr: String, fam: String) -> bool:
	var defs: Dictionary = sim.catalog.town.get("emotions", {})
	for e: Dictionary in active(sim, chr, fam):
		var over: Variant = defs.get(str(e["state"]), {}).get("refuses_trade_over")
		if over != null and intensity(sim, e) > float(over):
			return true
	return false


## Whether `chr` refuses a conversation with family `fam` (offended, angry).
static func refuses_talk(sim: Sim, chr: String, fam: String) -> bool:
	var defs: Dictionary = sim.catalog.town.get("emotions", {})
	for e: Dictionary in active(sim, chr, fam):
		if bool(defs.get(str(e["state"]), {}).get("refuses_talk", false)):
			return true
	return false


## The efficiency multiplier of an employee's states towards its employer family (grateful +10 %, angry −20 %).
static func employee_mult(sim: Sim, chr: String, fam: String) -> float:
	var m := 1.0
	var defs: Dictionary = sim.catalog.town.get("emotions", {})
	for e: Dictionary in active(sim, chr, fam):
		m *= float(defs.get(str(e["state"]), {}).get("employee_mult", 1.0))
	return m


## For the UI: [{state, source, intensity, icon, name_key}] of `chr`, the strongest first.
static func list(sim: Sim, chr: String) -> Array:
	var defs: Dictionary = sim.catalog.town.get("emotions", {})
	var out: Array = []
	for e: Dictionary in active(sim, chr):
		var d: Dictionary = defs.get(str(e["state"]), {})
		out.append({"state": str(e["state"]), "source": str(e["source"]), "intensity": roundi(intensity(sim, e)),
			"icon": str(d.get("icon", "")), "name_key": str(d.get("name_key", ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["intensity"]) > int(b["intensity"]))
	return out


## The icon of the strongest state of `chr` ("" if none): it goes over the social bubble (4.11.5).
static func top_icon(sim: Sim, chr: String) -> String:
	var l := list(sim, chr)
	return str(l[0]["icon"]) if not l.is_empty() else ""
