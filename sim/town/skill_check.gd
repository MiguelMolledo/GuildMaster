class_name SkillCheck
extends RefCounted
## Resolution of actions (GDD 4.2.4): threshold = base + (actor stat − target stat) × step + modifiers; a d100 roll;
## <= critical_success is a critical success, >= critical_fail a critical failure, else success if roll <= threshold.
## Deterministic with the seed: the roll comes from the town stream (Kin.roll with a key), never from state.rng, so a
## check does not move the economy's dice. Figures: data/town.json "skill_check".


## {success, critical, roll, threshold}. `key` names the check (who, against whom, when): same key, same roll.
static func roll(sim: Sim, key: String, actor_stat: int, target_stat: int, modifiers: int = 0) -> Dictionary:
	var cfg: Dictionary = sim.catalog.town.get("skill_check", {})
	var threshold := int(cfg.get("base", 50)) + (actor_stat - target_stat) * int(cfg.get("step", 5)) + modifiers
	var d100 := 1 + floori(Kin.roll(sim.state, "skill|" + key) * 100.0)
	var success := d100 <= threshold
	var critical := false
	if d100 <= int(cfg.get("critical_success", 5)):
		success = true
		critical = true
	elif d100 >= int(cfg.get("critical_fail", 96)):
		success = false
		critical = true
	sim.events.append({"type": "skill_check", "key": key, "success": success, "critical": critical, "roll": d100,
		"threshold": threshold})
	if OS.is_debug_build():
		print("[SkillCheck] %s: tirada %d contra %d (%d vs %d, mod %d) -> %s%s" % [key, d100, threshold, actor_stat,
			target_stat, modifiers, "éxito" if success else "fallo", " crítico" if critical else ""])
	return {"success": success, "critical": critical, "roll": d100, "threshold": threshold}


## The chance (0-1) that roll() succeeds for these stats: the threshold, with the criticals at both ends (for the
## tooltips that show a probability: the Rogue's arrest card).
static func chance(sim: Sim, actor_stat: int, target_stat: int, modifiers: int = 0) -> float:
	var cfg: Dictionary = sim.catalog.town.get("skill_check", {})
	var threshold := int(cfg.get("base", 50)) + (actor_stat - target_stat) * int(cfg.get("step", 5)) + modifiers
	var lo := int(cfg.get("critical_success", 5))
	var hi := int(cfg.get("critical_fail", 96)) - 1
	return clampi(threshold, lo, hi) / 100.0


## A stat of a character (5 if it has none).
static func stat(sim: Sim, chr: String, name: String) -> int:
	return int(sim.state.characters.get(chr, {}).get("stats", {}).get(name, 5))
