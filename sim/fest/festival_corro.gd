class_name FestivalCorro
extends RefCounted
## Fiestas · the corro in the plaza (04f 4.26, owner 2026-11-06): on a feast's day, while it is on, the family can play
## the tavern's games (pulso, the dice: azar and a la mayor, the envite) in the plaza against the regulars, with the same
## game screen and the same order (game_play with opts.corro = the feast's instance). No house and no licence: nobody
## takes a cut. With the preacher in town it is frowned upon: each game costs the family reputation (rules.corro.frowned).
## Figures in data/festivals.json rules.corro. Nothing of its own is saved: the game is one order, as in the tavern.


static func cfg(sim: Sim) -> Dictionary:
	return (Festivals.rules(sim).get("corro", {}) as Dictionary)


## The feast in force whose corro may be played now ({} if none): the first active instance.
static func feast(sim: Sim) -> Dictionary:
	var act := Festivals.active(sim)
	return act[0] if not act.is_empty() else {}


## The games of the corro (data: pulso, azar, mayor, envite).
static func games(sim: Sim) -> Array:
	return cfg(sim).get("games", ["pulso", "azar", "mayor", "envite"])


## "" if `actor` may play `game` in the corro of feast instance `inst_id` now, else why: no_feast (it is not on),
## unknown_game, unknown_actor, away (travelling or banished: not in the plaza).
static func reason(sim: Sim, actor: String, game: String, inst_id: String) -> String:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	if ch.is_empty() or str(ch.get("family", "")) == "" or not bool(ch.get("alive", true)):
		return "unknown_actor"
	var inst := Festivals.find(sim, inst_id)
	if inst.is_empty() or not Festivals.active(sim).has(inst):
		return "no_feast"
	if not game in games(sim):
		return "unknown_game"
	if Region.is_away(sim.state, actor) or Tribunal.is_banished(sim.state, actor):
		return "away"
	return ""


## The regulars of the plaza for `game` against `actor` (preset refs): as many as the game wants (a la mayor two, the
## rest one), in a keyed order per feast and game (the same ones all the feast).
static func opponents(sim: Sim, inst: Dictionary, actor: String, game: String) -> Array:
	var presets: Array = cfg(sim).get("regulars", ["regular_even", "regular_prudent", "regular_boastful"])
	var n := 2 if game == "mayor" else 1
	if presets.is_empty():
		return []
	var start := Kin.randi_range(sim.state, "fst|corro|%s|%s|%s" % [inst.get("id", ""), game, actor], 0, presets.size() - 1)
	var out: Array = []
	for i: int in mini(n, presets.size()):
		out.append("preset:" + str(presets[(start + i) % presets.size()]))
	return out


## The stake of the corro (the plaza's small one).
static func stake(sim: Sim) -> int:
	return int(cfg(sim).get("stake", 5))


## Whether a feast that frowns on gambling is on (the preacher: rules.corro.frowned.by).
static func frowned(sim: Sim) -> bool:
	var by: Array = (cfg(sim).get("frowned", {}) as Dictionary).get("by", ["preacher"])
	for inst: Dictionary in Festivals.active(sim):
		if str(inst["def"]) in by:
			return true
	return false


## The reputation a game of the corro costs today (0 unless frowned upon).
static func frowned_reputation(sim: Sim) -> int:
	return int((cfg(sim).get("frowned", {}) as Dictionary).get("reputation", -2)) if frowned(sim) else 0


## Games._apply heard a game of the corro: frowned upon, the family loses reputation; game_corro for the measures.
static func played(sim: Sim, spec: Dictionary, fam: String, actor: String, facts: Array) -> void:
	var rep := frowned_reputation(sim)
	if rep != 0:
		Reputation.change(sim, fam, rep, "games_frowned")
		facts.append({"kind": "frowned", "reputation": rep})
	sim.events.append({"type": "game_corro", "actor": actor, "family": fam, "game": str(spec["game"]),
		"festival": str((spec["opts"] as Dictionary).get("corro", "")), "frowned": rep})
	if OS.is_debug_build():
		print("[FestivalCorro] %s juega %s en el corro de %s%s" % [actor, spec["game"], (spec["opts"] as Dictionary).get("corro", ""),
			" (mal visto: reputación %d)" % rep if rep != 0 else ""])
