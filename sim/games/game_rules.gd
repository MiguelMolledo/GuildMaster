class_name GameRules
extends RefCounted
## Shared pieces of the games and competitions (docs/gdd/04f_vida_y_fiestas.md §4.26; figures: data/games.json).
## Pure and static. Every roll is keyed by (world seed, match id, step, what), like CombatRules.roll: a game never moves
## state.rng nor any other roll of the game, and the order in which the rolls are asked does not matter.
##
## A player is {id, name, stats {empathy, rhetoric, dexterity, constitution, martial, ...}, temper, preset, family}:
## Games.player_of builds it from a character of the state, Games.preset_player from data/games.json "presets".

const BLIND: int = -1
## How many ways each total of three dice comes out of 216 (3..18).
const WAYS_3D6: Dictionary = {3: 1, 4: 3, 5: 6, 6: 10, 7: 15, 8: 21, 9: 25, 10: 27, 11: 27, 12: 25, 13: 21, 14: 15,
	15: 10, 16: 6, 17: 3, 18: 1}


## A number in [0, 1) for one roll of one step of one match.
static func roll(seed: int, match_id: String, step: int, what: String) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = ("%d|games|%s|%d|%s" % [seed, match_id, step, what]).hash()
	return r.randf()


static func d6(seed: int, match_id: String, step: int, what: String) -> int:
	return mini(6, 1 + floori(roll(seed, match_id, step, what) * 6.0))


static func d100(seed: int, match_id: String, step: int, what: String) -> int:
	return mini(100, 1 + floori(roll(seed, match_id, step, what) * 100.0))


## `n` dice of one throw: [d6, ...] (each keyed "<what>|<i>").
static func throw_dice(seed: int, match_id: String, step: int, what: String, n: int) -> Array:
	var out: Array = []
	for i: int in n:
		out.append(d6(seed, match_id, step, "%s|%d" % [what, i]))
	return out


static func total(dice: Array) -> int:
	var t := 0
	for x: Variant in dice:
		t += int(x)
	return t


## A keyed d100 against a threshold with the SkillCheck criticals (data/games.json "critical").
static func check(cfg: Dictionary, threshold: int, seed: int, match_id: String, step: int, what: String) -> Dictionary:
	var crit: Dictionary = cfg.get("critical", {})
	var d := d100(seed, match_id, step, what)
	var ok := d <= threshold
	if d <= int(crit.get("success", 5)):
		ok = true
	elif d >= int(crit.get("fail", 96)):
		ok = false
	return {"success": ok, "roll": d, "threshold": threshold}


## The chance a pass with `threshold` succeeds (the criticals included): what the screens and the AI estimate.
static func pass_chance(cfg: Dictionary, threshold: int) -> float:
	var crit: Dictionary = cfg.get("critical", {})
	var lo := int(crit.get("success", 5))
	var hi := int(crit.get("fail", 96))
	var n := clampi(threshold, lo, hi - 1)
	return float(n) / 100.0


## A stat of a player (3, the townsfolk's usual, when it has none).
static func stat(p: Dictionary, s: String) -> int:
	return int((p.get("stats", {}) as Dictionary).get(s, 3))


## The chance a gesture tells the truth: base + (reader's stat − leader's stat) × step (+ bonus), clamped to [min, max].
static func read_chance(r: Dictionary, reader_value: int, leader_value: int, bonus: float = 0.0) -> float:
	var p := float(r.get("base", 0.5)) + (reader_value - leader_value) * float(r.get("step", 0.05)) + bonus
	return clampf(p, float(r.get("min", 0.34)), float(r.get("max", 0.9)))


## The gesture shown of an `actual` choice among `options`: the truth with chance `p`, otherwise one of the others (at
## even odds).
static func cue(p: float, actual: String, options: Array, seed: int, match_id: String, step: int,
		what: String = "cue") -> String:
	if roll(seed, match_id, step, what) < p or options.size() < 2:
		return actual
	var others: Array = []
	for o: Variant in options:
		if str(o) != actual:
			others.append(str(o))
	if others.is_empty():
		return actual
	return str(others[mini(others.size() - 1, floori(roll(seed, match_id, step, what + "_lie") * others.size()))])


## The probability that the truth is `x` when the gesture shows `seen` with reliability `p` and the prior of each option
## is `prior` (option -> weight): the reader's posterior (the lie is spread evenly over the other options).
static func posterior(prior: Dictionary, seen: String, p: float) -> Dictionary:
	var n := prior.size()
	var out: Dictionary = {}
	var total_w := 0.0
	for x: Variant in prior:
		var like := p if str(x) == seen else (1.0 - p) / maxf(1.0, float(n - 1))
		var w := float(prior[x]) * like
		out[str(x)] = w
		total_w += w
	for x: Variant in out:
		out[x] = float(out[x]) / total_w if total_w > 0.0 else 1.0 / float(n)
	return out


## The single most frequent entry of a history ("" when there is a tie at the top or nothing).
static func most_frequent(history: Array) -> String:
	var n: Dictionary = {}
	for a: Variant in history:
		n[str(a)] = int(n.get(str(a), 0)) + 1
	var best := ""
	var top := 0
	var tie := false
	var keys: Array = n.keys()
	keys.sort()
	for a: Variant in keys:
		var c := int(n[a])
		if c > top:
			best = str(a)
			top = c
			tie = false
		elif c == top:
			tie = true
	return "" if tie else best


## One of `options` at random by a keyed roll (uniform).
static func pick(options: Array, seed: int, match_id: String, step: int, what: String) -> String:
	if options.is_empty():
		return ""
	return str(options[mini(options.size() - 1, floori(roll(seed, match_id, step, what) * options.size()))])


## The temper of a player (data/games.json "tempers"): {stay_margin, bluff, call_margin, stay_always, read_bonus}.
static func temper(cfg: Dictionary, p: Dictionary) -> Dictionary:
	var ts: Dictionary = cfg.get("tempers", {})
	return ts.get(str(p.get("temper", "even")), ts.get("even", {}))
