class_name BotDuelist
extends RefCounted
## Bot that duels by the rules (docs/gdd/04e_combate.md §4e.6, docs/contratos/duelo.md): with the head of its family
## it challenges the rival of the trade (or whoever it has a cause against) whenever it can, walking to them first like
## the UI does; it lets the sim send it to the plaza at dawn and, in the duel, follows the gesture (the AI policy of
## «Resolver sin jugar», lance by lance with duel_move). It never brawls and never gives an order the rules refuse.
## The same orders the UI gives. Scenario: duel_ready (sim_runner --scenario=duel_ready --bots=duelist).

const ID: String = "duelist"

var _walking: int = -1   # minute it last sent the head towards its target


func orders(sim: Sim) -> Array:
	var st := sim.state
	var fam := _player_family(st)
	if fam == "":
		return []
	var me := Kin.head(st, fam)
	if me == "" or not Kin.alive(st, me):
		return []
	var mine := Duels.of_character(st, me)
	if not mine.is_empty():
		if str(mine["status"]) == Duels.FIGHTING and int(mine["player_side"]) >= 0:
			return [_lance(sim, mine, me)]
		return []  # pending or accepted: the sim calls it to the plaza
	var now := int(st.clock["minute"])
	if now % 15 != 0:
		return []
	var target := _target(sim, me)
	if target == "":
		return []
	if Duels.challenge_status(sim, me, target, "", "first_blood", true) == "":
		var c: Array = Duels.causes(sim, me, target)
		return [{"type": "duel_challenge", "actor": me, "target": target, "cause": str(c[0]["cause"]), "kind": "first_blood"}]
	if Duels.challenge_status(sim, me, target, "", "first_blood", false) == "" and now - _walking >= 30 \
			and str(st.characters[me].get("path", []) as Array) == "[]":
		_walking = now
		var spot := Courtship.spot(st, target)
		if str(st.characters[me].get("location", "")) != "":
			return [{"type": "exit_building", "actor": me}, {"type": "move_to", "actor": me, "tile": spot, "queued": true}]
		return [{"type": "move_to", "actor": me, "tile": spot}]
	return []


## The one it would challenge: the first other family's adult it has a cause against (the trade's rival first).
func _target(sim: Sim, me: String) -> String:
	var st := sim.state
	var mine := str(st.characters[me].get("family", ""))
	var ids: Array = []
	var fams: Array = st.families.keys()
	fams.sort()
	for f: String in fams:  # the trade's rivals and the families that offended it: their adults
		if f != mine and (Duels.trade_rivals(sim, mine, f) or Duels._offended(sim, mine, f)):
			for m: String in st.families[f].get("members", []):
				ids.append(m)
	var best := ""
	for id: String in ids:
		if Duels.challenge_status(sim, me, id, "", "first_blood", false) != "":
			continue
		var c: Array = Duels.causes(sim, me, id)
		if c.any(func(x: Dictionary) -> bool: return str(x["cause"]) == "rivalry"):
			return id
		if best == "":
			best = id
	return best


## The lance: what the AI policy would choose for its side (it reads the gesture it is shown).
func _lance(sim: Sim, rec: Dictionary, me: String) -> Dictionary:
	var du := Duel.wrap(sim.catalog.combat, rec["duel"])
	var side := int(rec["player_side"])
	var v := du.view(side)
	var act := CombatRules.ai_choice(sim.catalog.combat, du.fighter(side), du.breath(side), str(v["role"]),
		str(v["cue"]), du.d["history"][1 - side], int(du.d["seed"]), str(du.d["id"]), int(v["lance"]), side)
	return {"type": "duel_move", "actor": me, "duel": rec["id"], "action": act}


func _player_family(st: WorldState) -> String:
	var ids: Array = st.families.keys()
	ids.sort()
	for f: String in ids:
		if str(st.families[f].get("controlled_by", "")) == "human":
			return f
	return ""
