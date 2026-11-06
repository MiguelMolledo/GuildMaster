class_name Misdeeds
extends RefCounted
## Equilibrio 6 (docs/decisiones.json; GDD 4.12.5.1): the AI families with a business commit small misdeeds (false
## weights at the market, a supplier left unpaid, contraband), more often the less honest they are, and some are seen:
## a seen misdeed is a public fact against the family (Tribunal.add_fact), the real case a player who does not
## fabricate proofs can take to court. Nothing else changes: no gold moves (what the misdeed earned is in the sales the
## family already made; the fine comes with the trial), honesty does not move, and the rolls are keyed (Kin.roll), so
## state.rng and every other system play as before.
## Figures [balance] in data/justice.json misdeeds: chance a day = base × (1 + (pivot − honesty) / scale), in
## [0, max]; seen = the chance it becomes public; kinds = {kind: {weight, max_honesty?}} (the fact's charge in facts).
## At dawn, from from_day. Events: misdeed {family, kind, seen, fact}; the human families get a notice when one is seen.


static func cfg(sim: Sim) -> Dictionary:
	return sim.catalog.justice.get("misdeeds", {})


static func step(sim: Sim) -> void:
	var c := cfg(sim)
	if not bool(c.get("enabled", false)) or not Ledger.is_dawn(sim):
		return
	var st := sim.state
	var day := Clock.day(int(st.clock["minute"]))
	if day < int(c.get("from_day", 1)):
		return
	var fams: Array = st.families.keys()
	fams.sort()
	for fam: String in fams:
		if not _commits(sim, fam):
			continue
		var p := chance(sim, fam)
		if p <= 0.0 or Kin.roll(st, "misd|%s|%d" % [fam, day]) >= p:
			continue
		var kind := _kind(sim, fam, day)
		if kind == "":
			continue
		var seen := Kin.roll(st, "misd_seen|%s|%d" % [fam, day]) < float(c.get("seen", 0.5))
		var head := Kin.head(st, fam)
		var fid := Tribunal.add_fact(sim, kind, fam, head) if seen else ""
		sim.events.append({"type": "misdeed", "family": fam, "kind": kind, "seen": seen, "fact": fid})
		if seen:
			for h: String in fams:
				if str(st.families[h].get("controlled_by", "")) == "human":
					Notices.add(sim, h, Notices.INFO, "notice.misdeed_seen", {"family": str(st.families[fam].get("name", fam)),
						"what": "misdeed." + kind})
		if OS.is_debug_build():
			print("[Misdeeds] día %d: %s comete %s (prob=%.3f, honestidad=%d, visto=%s, hecho=%s)" % [day, fam, kind, p,
				Tribunal.honesty(sim, fam), seen, fid])


## A day's chance for `fam`: base × (1 + (pivot − honesty) / scale), in [0, max].
static func chance(sim: Sim, fam: String) -> float:
	var c := cfg(sim)
	var h := float(Tribunal.honesty(sim, fam))
	var p := float(c.get("base", 0.0)) * (1.0 + (float(c.get("pivot", 0)) - h) / maxf(1.0, float(c.get("scale", 50))))
	return clampf(p, 0.0, float(c.get("max", 1.0)))


## An AI family (not the human's) with a living head in town and a business (a building that is not a house).
static func _commits(sim: Sim, fam: String) -> bool:
	var st := sim.state
	var f: Dictionary = st.families[fam]
	if str(f.get("controlled_by", "")) == "human":
		return false
	var head := Kin.head(st, fam)
	if head == "" or not Kin.alive(st, head) or Tribunal.is_banished(st, head):
		return false
	for b: Dictionary in st.buildings.values():
		if str(b.get("owner", "")) == fam and str(b.get("type", "")) != "house":
			return true
	return false


## The kind, by weight among the kinds the family's honesty allows (keyed roll).
static func _kind(sim: Sim, fam: String, day: int) -> String:
	var kinds: Dictionary = cfg(sim).get("kinds", {})
	var h := Tribunal.honesty(sim, fam)
	var ids: Array = kinds.keys()
	ids.sort()
	var total := 0.0
	var ok: Array = []
	for k: String in ids:
		var d: Dictionary = kinds[k]
		if d.has("max_honesty") and h > int(d["max_honesty"]):
			continue
		ok.append(k)
		total += float(d.get("weight", 1))
	if ok.is_empty() or total <= 0.0:
		return ""
	var r := Kin.roll(sim.state, "misd_kind|%s|%d" % [fam, day]) * total
	for k: String in ok:
		r -= float(kinds[k].get("weight", 1))
		if r < 0.0:
			return k
	return str(ok[-1])
