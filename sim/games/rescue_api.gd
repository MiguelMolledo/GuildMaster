class_name Rescue
extends RefCounted
## The played rescue's pieces (docs/contratos/juegos.md §5; vida: Incidents «kidnapping|rescue»).
##   Rescue.preview(sim, inc, actor, helpers) -> {players, team_a, key, seed}: the fighters the rescue will meet, for the
##     screen (reads only; the bandits are built from data the way Life.add_person builds them).
##   Rescue.fight(sim, side_a, side_b, key, fam_b, moves) -> won: what Incidents calls with the real people: the chain
##     of duels of RescueMatch, the actor's bouts with `moves` (none: the AI fights them all, the old
##     Incidents._fights to the last roll), and «scared» for the rescuers who lose.

## The stats a temporary person gets before its own (as Life.add_person).
const PERSON_STATS: Dictionary = {"charisma": 4, "empathy": 4, "negotiation": 4, "arcane": 1, "dexterity": 4, "craft": 3,
	"martial": 4, "constitution": 4, "rhetoric": 4, "stealth": 3}


static func preview(sim: Sim, inc: Dictionary, actor: String, helpers: int) -> Dictionary:
	var st := sim.state
	var rc: Dictionary = Incidents.def(sim, "kidnapping").get("rescue", {})
	var n := clampi(helpers, 0, int(rc.get("max_helpers", 3)))
	var side: Array = [actor]
	var watch := Watch.guards(st)
	for i: int in n:
		side.append(watch[i % watch.size()] if not watch.is_empty() else actor)
	var players: Array = []
	for c: Variant in side:
		var ch: Dictionary = st.characters.get(str(c), {})
		players.append({"id": str(c), "name": str(ch.get("name", "?")), "family": str(ch.get("family", "")),
			"stats": (ch.get("stats", {}) as Dictionary).duplicate(), "fighter": Duels.fighter_of(sim, str(c))})
	var span: Array = rc.get("fights", [2, 3])
	var nb := Kin.randi_range(st, "events_city|rescue_n|%s" % inc["id"], int(span[0]), int(span[1]))
	for i: int in nb:
		var stats := PERSON_STATS.duplicate()
		stats.merge(rc.get("bandit_stats", {}), true)
		players.append({"id": "bandit_%d" % i, "name": "", "name_key": "games.rescue.bandit", "family": Life.FAMILY_BANDITS,
			"stats": stats, "fighter": CombatRules.fighter("bandit_%d" % i, stats, "fists"), "look": 50 + i})
	return {"players": players, "team_a": side.size(), "key": "%s|rescue" % inc["id"], "seed": st.world_seed}


static func fight(sim: Sim, side_a: Array, side_b: Array, key: String, fam_b: String, moves: Array = []) -> bool:
	var st := sim.state
	var players: Array = []
	for c: Variant in side_a + side_b:
		players.append({"id": str(c), "name": str(st.characters.get(str(c), {}).get("name", "")), "fighter": Duels.fighter_of(sim, str(c))})
	var was := GameMatch.verbose
	var m := RescueMatch.create(sim.catalog.games, sim.catalog.combat, key, st.world_seed, players, 0 if not moves.is_empty() else -1,
		{"team_a": side_a.size()})
	for mv: Variant in moves:
		if m.over() or int(m.d["turn"]) != 0:
			break
		if not bool(m.choose(0, str(mv))["ok"]):
			break
	if not m.over():
		m.auto_finish()
	GameMatch.verbose = was
	for c: Variant in m.d["lost_a"]:
		if fam_b != "" and st.characters.has(str(c)):
			Emotions.add(sim, str(c), "scared", fam_b)
	if OS.is_debug_build():
		print("[Rescue] %s: %d combates, %s%s" % [key, int(m.d["n"]), "rescatado" if m.won() else "vencidos",
			(" (jugado: %d lances)" % moves.size()) if not moves.is_empty() else ""])
	return m.won()
