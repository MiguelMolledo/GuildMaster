class_name CombatRules
extends RefCounted
## The rules of one lance of the duel «a tres tiempos» (docs/gdd/04e_combate.md §2; figures: data/combat.json).
## Pure and deterministic: every function takes the combat table (`cfg`, Catalog.combat) and plain dictionaries;
## nothing here holds state or reads the world. Every roll is keyed by (seed, duel, lance, what), like Kin.roll: it
## never moves state.rng nor any other roll of the game, and the order in which the rolls are asked does not matter.
##
## A fighter is {id, martial, empathy, constitution, dexterity, weapon (a weapons id), armor (bool), wounded (bool)}.
## Sides are 0 (the challenger) and 1 (the challenged). Actions: strike, parry, feint (data/combat.json "actions").

const ACTIONS: Array[String] = ["strike", "parry", "feint"]
const BLIND: int = -1


## A fighter from a character's stats (5 for a missing one) and its kit.
static func fighter(id: String, stats: Dictionary, weapon: String = "fists", armor: bool = false,
		wounded: bool = false) -> Dictionary:
	return {"id": id, "martial": int(stats.get("martial", 5)), "empathy": int(stats.get("empathy", 5)),
		"constitution": int(stats.get("constitution", 5)), "dexterity": int(stats.get("dexterity", 5)),
		"weapon": weapon, "armor": armor, "wounded": wounded}


## The weapon a character fights with: its equipped tool or weapon by data/combat.json "items" (fists otherwise).
static func weapon_for(cfg: Dictionary, equipment: Dictionary) -> String:
	var items: Dictionary = cfg.get("items", {})
	for slot: String in ["weapon", "tool"]:
		var it := str((equipment.get(slot, {}) as Dictionary).get("item", "")) if equipment.get(slot) is Dictionary else ""
		if items.has(it):
			return str(items[it])
	return "fists"


## Whether a character's equipped clothes count as armour (data/combat.json "armor_items").
static func armored(cfg: Dictionary, equipment: Dictionary) -> bool:
	var c: Variant = equipment.get("clothes")
	return c is Dictionary and str((c as Dictionary).get("item", "")) in (cfg.get("armor_items", []) as Array)


static func weapon(cfg: Dictionary, f: Dictionary) -> Dictionary:
	var ws: Dictionary = cfg.get("weapons", {})
	return ws.get(str(f.get("weapon", "fists")), ws.get("fists", {}))


static func breath_max(cfg: Dictionary, f: Dictionary) -> int:
	var b: Dictionary = cfg.get("breath", {})
	return int(b.get("base", 3)) + floori(int(f.get("constitution", 5)) * float(b.get("per_constitution", 0.5))) \
		+ int(weapon(cfg, f).get("breath", 0))


## The breath an action costs (negative: it recovers breath).
static func cost(cfg: Dictionary, action: String) -> int:
	return int((cfg.get("actions", {}) as Dictionary).get(action, {}).get("breath", 0))


static func can_afford(cfg: Dictionary, breath: int, action: String) -> bool:
	return action in ACTIONS and breath >= maxi(0, cost(cfg, action))


## The actions one may take with `breath` left (parry is always there).
static func allowed(cfg: Dictionary, breath: int) -> Array[String]:
	var out: Array[String] = []
	for a: String in ACTIONS:
		if can_afford(cfg, breath, a):
			out.append(a)
	return out


static func breath_after(cfg: Dictionary, f: Dictionary, breath: int, action: String) -> int:
	return clampi(breath - cost(cfg, action), 0, breath_max(cfg, f))


## Whether action `a` beats action `b` in the triangle.
static func beats(cfg: Dictionary, a: String, b: String) -> bool:
	return str((cfg.get("actions", {}) as Dictionary).get(a, {}).get("beats", "")) == b


## The action that beats `a`.
static func counter_of(cfg: Dictionary, a: String) -> String:
	for x: String in ACTIONS:
		if beats(cfg, x, a):
			return x
	return "parry"


## The chance the reader's cue tells the truth: base + (reader's empathy − leader's martial) × step, clamped.
static func read_chance(cfg: Dictionary, reader: Dictionary, leader: Dictionary) -> float:
	var r: Dictionary = cfg.get("read", {})
	var p := float(r.get("base", 0.5)) + (int(reader.get(str(r.get("stat", "empathy")), 5))
		- int(leader.get(str(r.get("against", "martial")), 5))) * float(r.get("step", 0.05))
	if bool(reader.get("wounded", false)):
		p += float((cfg.get("wounded", {}) as Dictionary).get("read", 0.0))
	return clampf(p, float(r.get("min", 0.34)), float(r.get("max", 0.9)))


## Who leads lance `lance` (0-based): BLIND for the first lances, then the sides alternate (the challenger first unless
## initiative.first says "challenged").
static func leader_of(cfg: Dictionary, lance: int) -> int:
	var ini: Dictionary = cfg.get("initiative", {})
	var blind := int(ini.get("blind", 1))
	if lance < blind:
		return BLIND
	var first := 1 if str(ini.get("first", "challenger")) == "challenged" else 0
	return (lance - blind + first) % 2


## A number in [0, 1) for one roll of one lance of one duel.
static func roll(seed: int, duel: String, lance: int, what: String) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = ("%d|combat|%s|%d|%s" % [seed, duel, lance, what]).hash()
	return r.randf()


static func d100(seed: int, duel: String, lance: int, what: String) -> int:
	return 1 + floori(roll(seed, duel, lance, what) * 100.0)


## The gesture the reader sees of the leader's `actual` action: the truth with chance `p`, otherwise one of the other two.
static func cue(p: float, actual: String, seed: int, duel: String, lance: int) -> String:
	if roll(seed, duel, lance, "cue") < p:
		return actual
	var others: Array[String] = []
	for a: String in ACTIONS:
		if a != actual:
			others.append(a)
	return others[0] if roll(seed, duel, lance, "cue_lie") < 0.5 else others[1]


## The AI's choice (the rival, the NPCs and «Resolver sin jugar»). role: "read" (answers the cue: what beats it if it
## has the breath, else the cue itself, else parry) or "lead"/"blind" (counters the opponent's most frequent action with
## chance ai.habit once there is ai.min_history of it, else a weighted mix with the weapon's edge favoured).
static func ai_choice(cfg: Dictionary, f: Dictionary, breath: int, role: String, seen: String, opp_history: Array,
		seed: int, duel: String, lance: int, side: int) -> String:
	if role == "read" and seen != "":
		var best := counter_of(cfg, seen)
		if can_afford(cfg, breath, best):
			return best
		if can_afford(cfg, breath, seen):
			return seen
		return "parry"
	var ai: Dictionary = cfg.get("ai", {})
	if opp_history.size() >= int(ai.get("min_history", 2)):
		var mf := most_frequent(opp_history)
		if mf != "" and roll(seed, duel, lance, "habit|%d" % side) < float(ai.get("habit", 0.5)):
			var c := counter_of(cfg, mf)
			if can_afford(cfg, breath, c):
				return c
	var opts := allowed(cfg, breath)
	var edge := str(weapon(cfg, f).get("edge", ""))
	var weights: Array[float] = []
	var total := 0.0
	for a: String in opts:
		var w := 1.0 + (float(ai.get("edge_weight", 0.3)) if a == edge else 0.0)
		weights.append(w)
		total += w
	var x := roll(seed, duel, lance, "style|%d" % side) * total
	for i in opts.size():
		x -= weights[i]
		if x < 0.0:
			return opts[i]
	return opts[opts.size() - 1]


## The single most frequent action of a history ("" if there is a tie at the top).
static func most_frequent(history: Array) -> String:
	var n: Dictionary = {}
	for a: Variant in history:
		n[str(a)] = int(n.get(str(a), 0)) + 1
	var best := ""
	var top := 0
	var tie := false
	for a: String in ACTIONS:
		var c := int(n.get(a, 0))
		if c > top:
			best = a
			top = c
			tie = false
		elif c == top and c > 0:
			tie = true
	return "" if tie else best


## A keyed d100 against a threshold, with the SkillCheck criticals.
static func check(cfg: Dictionary, threshold: int, seed: int, duel: String, lance: int, what: String) -> Dictionary:
	var crit: Dictionary = cfg.get("critical", {})
	var d := d100(seed, duel, lance, what)
	var ok := d <= threshold
	if d <= int(crit.get("success", 5)):
		ok = true
	elif d >= int(crit.get("fail", 96)):
		ok = false
	return {"success": ok, "roll": d, "threshold": threshold}


static func _mods(cfg: Dictionary, att: Dictionary, def: Dictionary) -> int:
	var m := 0
	if bool(def.get("armor", false)):
		m += int((cfg.get("armor", {}) as Dictionary).get("against", 0))
	if bool(att.get("wounded", false)):
		m += int((cfg.get("wounded", {}) as Dictionary).get("rolls", 0))
	return m


## The threshold of the touch of the winner of an exchange with `action`.
static func touch_threshold(cfg: Dictionary, att: Dictionary, def: Dictionary, action: String) -> int:
	var t: Dictionary = cfg.get("touch", {})
	var s := str(t.get("stat", "martial"))
	var w := weapon(cfg, att)
	return int(t.get("base", 50)) + (int(att.get(s, 5)) - int(def.get(s, 5))) * int(t.get("step", 5)) \
		+ int(t.get("advantage", 30)) + (int(w.get("touch", 0)) if str(w.get("edge", "")) == action else 0) \
		+ _mods(cfg, att, def)


## The threshold of side 0 in a clash (a tie on strike): side 0 touches if it passes, side 1 otherwise.
static func clash_threshold(cfg: Dictionary, a: Dictionary, b: Dictionary) -> int:
	var c: Dictionary = cfg.get("clash", {})
	var s := str(c.get("stat", "martial"))
	var th := int(c.get("base", 50)) + (int(a.get(s, 5)) - int(b.get(s, 5))) * int(c.get("step", 5))
	var wa := weapon(cfg, a)
	var wb := weapon(cfg, b)
	if str(wa.get("edge", "")) == "strike":
		th += int(wa.get("tie", 0))
	if str(wb.get("edge", "")) == "strike":
		th -= int(wb.get("tie", 0))
	return th + _mods(cfg, a, b) - _mods(cfg, b, a)


## The threshold of the holder of a weapon whose edge is the tied action and has a tie bonus (a one-sided roll: it
## touches or nothing).
static func edge_threshold(cfg: Dictionary, holder: Dictionary, other: Dictionary) -> int:
	var c: Dictionary = cfg.get("clash", {})
	var s := str(c.get("stat", "martial"))
	return int(c.get("base", 50)) + (int(holder.get(s, 5)) - int(other.get(s, 5))) * int(c.get("step", 5)) \
		+ int(weapon(cfg, holder).get("tie", 0)) + _mods(cfg, holder, other)


## Resolves one lance from both actions: {winner (-1 nobody, 0, 1), how, roll, threshold}. how: "beats" (the triangle
## and the touch landed), "held" (won the exchange, the touch missed), "clash" (strike against strike), "edge" (a tie
## on the action of a weapon's edge, landed), "even" (a tie with nothing).
static func resolve_lance(cfg: Dictionary, fa: Dictionary, fb: Dictionary, act_a: String, act_b: String,
		seed: int, duel: String, lance: int) -> Dictionary:
	var f: Array = [fa, fb]
	if act_a != act_b:
		var w := 0 if beats(cfg, act_a, act_b) else 1
		var act := act_a if w == 0 else act_b
		var r := check(cfg, touch_threshold(cfg, f[w], f[1 - w], act), seed, duel, lance, "touch")
		return {"winner": w if bool(r["success"]) else -1, "how": "beats" if bool(r["success"]) else "held",
			"exchange": w, "roll": r["roll"], "threshold": r["threshold"]}
	if act_a == "strike":
		var r := check(cfg, clash_threshold(cfg, fa, fb), seed, duel, lance, "clash")
		return {"winner": 0 if bool(r["success"]) else 1, "how": "clash", "exchange": -1, "roll": r["roll"],
			"threshold": r["threshold"]}
	var ea := str(weapon(cfg, fa).get("edge", "")) == act_a and int(weapon(cfg, fa).get("tie", 0)) > 0
	var eb := str(weapon(cfg, fb).get("edge", "")) == act_a and int(weapon(cfg, fb).get("tie", 0)) > 0
	if ea != eb:
		var h := 0 if ea else 1
		var r := check(cfg, edge_threshold(cfg, f[h], f[1 - h]), seed, duel, lance, "edge")
		return {"winner": h if bool(r["success"]) else -1, "how": "edge" if bool(r["success"]) else "even",
			"exchange": -1, "roll": r["roll"], "threshold": r["threshold"]}
	return {"winner": -1, "how": "even", "exchange": -1, "roll": 0, "threshold": 0}
