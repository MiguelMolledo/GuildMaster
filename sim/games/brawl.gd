class_name BrawlMatch
extends GameMatch
## A brawl of the town (an altercation of vida, docs/gdd/04f_vida_y_fiestas.md §4.24.5), as a game to bet on (§4.26.6):
## the very duel Incidents._fight fights (Duel.auto with the incident's id as the duel's, the world seed, the
## fighters of Duels.fighter_of with the altercation's weapon, its duel kind). Nobody plays it: it exists so the
## bookmaker can price it (Games.win_odds: other ids, other dice) and the screen can show it; the incident's own fight
## is the one that pays the bets (Betting.settle_incident). Players: [a, b] with their `fighter`.

var combat: Dictionary = {}


static func create(games: Dictionary, combat_cfg: Dictionary, id: String, seed: int, players: Array, opts: Dictionary = {}) -> BrawlMatch:
	var m := BrawlMatch.new()
	m.cfg = games
	m.combat = combat_cfg
	m._init_d("brawl", id, seed, players, -1, 0, opts)
	var was := Duel.verbose
	Duel.verbose = false
	var du := Duel.create(combat_cfg, id, seed, m.fighter(0), m.fighter(1), str(opts.get("kind", "first_blood")), -1)
	Duel.verbose = was
	for rec: Variant in du.lances_log():
		var r: Dictionary = (rec as Dictionary).duplicate(true)
		r["kind"] = "lance"
		r["sides"] = [0, 1]
		(m.d["log"] as Array).append(r)
	var w := int(du.result()["winner"])
	m.d["touches"] = (du.d["touches"] as Array).duplicate()
	m.d["scores"] = (du.d["touches"] as Array).duplicate()
	m.d["ranking"] = [w, 1 - w] if w >= 0 else [0, 1]
	m._finish(w, "brawl")
	return m


func fighter(k: int) -> Dictionary:
	var p := player_of(k)
	if p.get("fighter") is Dictionary:
		return p["fighter"]
	return CombatRules.fighter(str(p.get("id", "s%d" % k)), p.get("stats", {}), str(opt("weapon", "fists")))
