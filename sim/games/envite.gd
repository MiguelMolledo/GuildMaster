class_name EnviteMatch
extends GameMatch
## «Envite», a game of raises and bluffs of the truc family (docs/gdd/04f_vida_y_fiestas.md §4.26.8; figures:
## data/games.json "envite"). Two sides, a deck of 40 Spanish cards (oros, copas, espadas, bastos; 1-7, sota, caballo,
## rey), three cards each. The hand is played in three bazas that are uncovered one after the other: the first baza
## sets the highest card of each against the other's highest, the second the middle ones, the third the lowest; the
## higher card takes the baza (equal: parda). Who takes more bazas wins; tied, the first baza that was not parda; all
## parda, the mano (the side that is first, opts.mano or a keyed roll). The card order is the truc's: the four bravas
## (ace of swords, ace of clubs, seven of swords, seven of coins), then 3, 2, the other aces, king, knight, jack, the
## other sevens, 6, 5, 4 (data/games.json "envite.order").
##
## Before each baza there is a round of raises: the first to speak (the mano before the first baza, then whoever lost
## the last one) raises (envidar: the stake goes up by the starting stake) or passes; the other wants (quiero), raises
## again (subir, once per round) or does not want (no quiero: loses what he had put). If the first passes, the other
## may raise and the first answers. Nobody puts more than the cap (O-V8).
##
## The bluff is the heart of it: in each round each side shows a gesture about his hand (pleased = a strong hand,
## uneasy = a weak one; strong = it beats a random hand at least half of the times) that tells the truth with
## read_chance (empathy of the reader against the rhetoric of who shows it; the cheat reads better). The screen tells
## the played side its chance of winning with what it sees (its cards, the bazas uncovered) and counting the gesture
## (the exact posterior), and from what chance wanting pays. The AI (temper even, «Resolver sin jugar») plays those
## numbers: raises from raise_at, raises again from reraise_at, wants when the expected gold of wanting is above that
## of not wanting, and bluffs (raises with a weak hand) with its temper's chance.

static var _strength_cache: Dictionary = {}   # sorted level triple "a,b,c" -> chance of beating a random hand


static func create(games: Dictionary, id: String, seed: int, players: Array, player: int = -1, stake: int = 10,
		opts: Dictionary = {}) -> EnviteMatch:
	var m := EnviteMatch.new()
	m.cfg = games
	m._init_d("envite", id, seed, players, player, stake, opts)
	var mano := int(opts.get("mano", -1))
	if mano < 0:
		mano = 0 if GameRules.roll(seed, id, 0, "mano") < 0.5 else 1
	var deck := m._shuffled()
	var hands: Array = [deck.slice(0, 3), deck.slice(3, 6)]
	for s: int in 2:
		(hands[s] as Array).sort_custom(func(a: String, b: String) -> bool: return m.level(a) > m.level(b))
	m.d.merge({"mano": mano, "hands": hands, "level": stake, "round": 0, "bazas": [], "raised": false,
		"reraised": false, "first": mano, "phase": "bet", "turn": mano, "gestures": [["", "", ""], ["", "", ""]],
		"folded": -1, "speaks": [0, 0]}, true)
	if _log():
		print("[Games] envite %s: mano %d, manos %s, apuesta %d, jugador %d" % [id, mano, hands, stake, player])
	m._gestures()
	m._advance()
	return m


# --- Cards -------------------------------------------------------------------------------------------------------------

## The 40 cards "<suit>_<rank>".
func deck() -> Array:
	var out: Array = []
	for s: String in ["oros", "copas", "espadas", "bastos"]:
		for r: int in [1, 2, 3, 4, 5, 6, 7, 10, 11, 12]:
			out.append("%s_%d" % [s, r])
	return out


func _shuffled() -> Array:
	var dk := deck()
	for i: int in range(dk.size() - 1, 0, -1):
		var j := floori(GameRules.roll(match_seed(), id(), 0, "deal|%d" % i) * (i + 1))
		var t: Variant = dk[i]
		dk[i] = dk[j]
		dk[j] = t
	return dk


## The strength of a card: its place in envite.order counted from the bottom (the four of any suit is 0).
func level(card: String) -> int:
	var order: Array = sec().get("order", [])
	var n := order.size()
	for i: int in n:
		var e: String = order[i]
		if e == card or (e.begins_with("*_") and card.get_slice("_", 1) == e.get_slice("_", 1)):
			return n - 1 - i
	return 0


## How many cards of the deck have each level (index = level).
func level_counts() -> Array:
	var n := (sec().get("order", []) as Array).size()
	var out: Array = []
	out.resize(n)
	out.fill(0)
	for c: Variant in deck():
		out[level(str(c))] = int(out[level(str(c))]) + 1
	return out


func hand(side: int) -> Array:
	return (d["hands"] as Array)[side]


func levels(side: int) -> Array:
	var out: Array = []
	for c: Variant in hand(side):
		out.append(level(str(c)))
	return out


## The winner of a hand of sorted levels a against b (0 = a, 1 = b) with `mano` the side of a (0) or b (1).
static func hand_winner(a: Array, b: Array, mano: int) -> int:
	var wa := 0
	var wb := 0
	var first := -1
	for i: int in 3:
		if int(a[i]) > int(b[i]):
			wa += 1
			if first < 0:
				first = 0
		elif int(b[i]) > int(a[i]):
			wb += 1
			if first < 0:
				first = 1
	if wa != wb:
		return 0 if wa > wb else 1
	return first if first >= 0 else mano


## The chance a hand of sorted levels beats a random hand of the rest of the deck at the deal (cached): what the
## gesture tells (strong when >= 0.5). Half the deals it is mano.
func strength(lv: Array) -> float:
	var key := "%d,%d,%d" % [int(lv[0]), int(lv[1]), int(lv[2])]
	if _strength_cache.has(key):
		return float(_strength_cache[key])
	var counts := level_counts()
	for x: Variant in lv:
		counts[int(x)] = int(counts[int(x)]) - 1
	var w := 0.0
	var n := 0.0
	for e: Array in hands_of(counts, 3, counts.size() - 1):
		var h: Array = e[0]
		var wt := float(e[1])
		n += wt
		w += wt * (0.5 * float(int(hand_winner(lv, h, 0) == 0)) + 0.5 * float(int(hand_winner(lv, h, 1) == 0)))
	var p := w / maxf(1.0, n)
	_strength_cache[key] = p
	return p


static func _comb(n: int, k: int) -> float:
	if k > n or n <= 0:
		return 0.0 if k > 0 else 1.0
	match k:
		0:
			return 1.0
		1:
			return float(n)
		2:
			return n * (n - 1) / 2.0
	return n * (n - 1) * (n - 2) / 6.0


## Every hand of `k` cards (0-3) from `counts` (cards left of each level) with levels at most `top`, sorted high to low:
## [[levels], weight = the number of card combinations].
static func hands_of(counts: Array, k: int, top: int) -> Array:
	var out: Array = []
	if k == 0:
		return [[[], 1.0]]
	for a: int in range(top, -1, -1):
		if int(counts[a]) <= 0:
			continue
		if k == 1:
			out.append([[a], float(int(counts[a]))])
			continue
		for b: int in range(a, -1, -1):
			if int(counts[b]) - int(b == a) <= 0:
				continue
			if k == 2:
				out.append([[a, b], _comb(int(counts[a]), 2) if a == b else float(int(counts[a])) * int(counts[b])])
				continue
			for c: int in range(b, -1, -1):
				var w := 0.0
				if a == b and b == c:
					w = _comb(int(counts[a]), 3)
				elif a == b:
					w = _comb(int(counts[a]), 2) * int(counts[c])
				elif b == c:
					w = float(int(counts[a])) * _comb(int(counts[b]), 2)
				else:
					w = float(int(counts[a])) * int(counts[b]) * int(counts[c])
				if w > 0.0:
					out.append([[a, b, c], w])
	return out


# --- What a side knows -------------------------------------------------------------------------------------------------

## The bazas uncovered so far: [{cards [a, b], levels [a, b], winner (side or -1 parda)}].
func bazas() -> Array:
	return d["bazas"]


## {win, win_gesture}: the chance `side` wins the hand with what it sees (its cards and the bazas uncovered), and the
## same counting the gesture it sees of the other this round (exact posterior).
func odds(side: int) -> Dictionary:
	var mine := levels(side)
	var other := 1 - side
	var counts := level_counts()
	for x: Variant in mine:
		counts[int(x)] = int(counts[int(x)]) - 1
	var seen: Array = []
	for b: Dictionary in bazas():
		var lv := int((b["levels"] as Array)[other])
		seen.append(lv)
		counts[lv] = int(counts[lv]) - 1
	var g := str(((d["gestures"] as Array)[other] as Array)[int(d["round"])]) if int(d["round"]) < 3 else ""
	var r := read_chance(side, other)
	var acc := {"w": 0.0, "n": 0.0, "wg": 0.0, "ng": 0.0}
	var top := int(seen[seen.size() - 1]) if not seen.is_empty() else counts.size() - 1
	var mi := 0 if int(d["mano"]) == side else 1
	for e: Array in hands_of(counts, 3 - seen.size(), top):
		var full: Array = seen + (e[0] as Array)
		var w := float(e[1])
		var won := float(int(hand_winner(mine, full, mi) == 0))
		acc["n"] = float(acc["n"]) + w
		acc["w"] = float(acc["w"]) + w * won
		if g != "":
			var like := r if (g == "pleased") == (strength(full) >= 0.5) else 1.0 - r
			acc["ng"] = float(acc["ng"]) + w * like
			acc["wg"] = float(acc["wg"]) + w * like * won
	var p := float(acc["w"]) / maxf(1e-9, float(acc["n"]))
	var pg := float(acc["wg"]) / float(acc["ng"]) if g != "" and float(acc["ng"]) > 0.0 else p
	return {"win": p, "win_gesture": pg, "gesture": g, "read": r if g != "" else 0.0}


func read_chance(reader: int, shower: int) -> float:
	var bonus := float(GameRules.temper(cfg, player_of(reader)).get("read_bonus", 0.0))
	return GameRules.read_chance(sec().get("read", {}), GameRules.stat(player_of(reader), "empathy"),
		GameRules.stat(player_of(shower), "rhetoric"), bonus)


## The gestures of this round: each side shows one of its hand (pleased / uneasy), true with the other's read chance.
func _gestures() -> void:
	var rd := int(d["round"])
	if rd >= 3:
		return
	for s: int in 2:
		var truth := "pleased" if strength(levels(s)) >= 0.5 else "uneasy"
		var r := read_chance(1 - s, s)
		((d["gestures"] as Array)[s] as Array)[rd] = GameRules.cue(r, truth, ["pleased", "uneasy"], match_seed(), id(), rd,
			"gesture|%d" % s)


# --- Raises ------------------------------------------------------------------------------------------------------------

func step_up() -> int:
	return int(d["stake"])


func can_raise() -> bool:
	return int(d["level"]) + step_up() <= int(cfg.get("cap", 50))


## The thresholds the AI plays (and the screen shows): raise from raise_at, raise again from reraise_at, want from
## want_at = s / ((L + s)(2 − rake)), the chance where wanting a raise of s over L and not wanting are worth the same;
## bluff (raise) below bluff_below with the temper's chance.
func want_at() -> float:
	var lv := float(int(d["level"]))
	var s := float(step_up())
	return clampf(s / ((lv + s) * (2.0 - rake())), 0.0, 1.0)


## Whether the side that answers a raise may raise again (once per round, within the cap).
func can_reraise() -> bool:
	return not bool(d["reraised"]) and int(d["level"]) + 2 * step_up() <= int(cfg.get("cap", 50))


func ai_decision(side: int) -> String:
	var t := GameRules.temper(cfg, player_of(side))
	var o := odds(side)
	var p := float(o["win_gesture"])
	var ai: Dictionary = sec().get("ai", {})
	var ph := str(d["phase"])
	var rd := int(d["round"])
	if ph == "bet" or ph == "bet2":
		if can_raise() and p >= float(ai.get("raise_at", 0.62)):
			return "raise"
		if can_raise() and p < float(ai.get("bluff_below", 0.3)) \
				and GameRules.roll(match_seed(), id(), rd, "bluff|%d|%s" % [side, ph]) < float(t.get("bluff", 0.1)):
			return "raise"
		return "pass"
	# answering a raise
	if ph == "answer" and can_reraise() and p >= float(ai.get("reraise_at", 0.8)):
		return "reraise"
	return "want" if p >= want_at() + float(t.get("call_margin", 0.0)) else "fold"


func allowed(side: int) -> Array:
	var out: Array = []
	for a: Dictionary in _actions(side):
		if bool(a.get("enabled", true)):
			out.append(str(a["id"]))
	return out


func _actions(side: int) -> Array:
	var acts: Array = []
	var ph := str(d["phase"])
	if not over() and int(d["turn"]) == side:
		match ph:
			"bet", "bet2":
				acts = [{"id": "raise", "enabled": can_raise(), "why": "" if can_raise() else "games.why.cap"},
					{"id": "pass", "enabled": true}]
			"answer":
				var rr := can_reraise()
				acts = [{"id": "want", "enabled": true}, {"id": "reraise", "enabled": rr, "why": "" if rr else "games.why.cap"},
					{"id": "fold", "enabled": true}]
			"answer2":
				acts = [{"id": "want", "enabled": true}, {"id": "fold", "enabled": true}]
	return acts


func _view(side: int) -> Dictionary:
	var acts := _actions(side)
	var ph := str(d["phase"])
	var o := odds(side) if side >= 0 else {}
	var hands: Array = [hand(0).duplicate(), hand(1).duplicate()]
	if not over() or int(d["folded"]) >= 0:
		hands[1 - side] = []   # the other's cards stay hidden (except the bazas uncovered), and after a fold
	return {"actions": acts, "hand": hand(side).duplicate(), "hands": hands, "bazas": bazas().duplicate(true),
		"level": int(d["level"]), "round": int(d["round"]), "mano": int(d["mano"]), "win": float(o.get("win", 0.0)),
		"win_gesture": float(o.get("win_gesture", 0.0)), "gesture": str(o.get("gesture", "")),
		"read": float(o.get("read", 0.0)), "read_by": read_chance(1 - side, side), "want_at": want_at(),
		"my_gesture": str(((d["gestures"] as Array)[side] as Array)[mini(int(d["round"]), 2)]),
		"last": (d["log"] as Array).back() if not (d["log"] as Array).is_empty() else {},
		"prompt": "games.envite.prompt.%s" % ph if acts.size() > 0 else ""}


func _choose(side: int, action: String) -> Dictionary:
	_apply(side, action)
	return {"ok": true, "reason": ""}


func _apply(side: int, action: String) -> void:
	var ph := str(d["phase"])
	var rd := int(d["round"])
	(d["log"] as Array).append({"kind": "say", "side": side, "action": action, "round": rd, "level": int(d["level"])})
	var other := 1 - side
	match ph:
		"bet":
			if action == "raise":
				d["raised"] = true
				d["phase"] = "answer"
				d["turn"] = other
			else:
				d["phase"] = "bet2"
				d["turn"] = other
		"bet2":
			if action == "raise":
				d["raised"] = true
				d["phase"] = "answer2"
				d["turn"] = other
			else:
				_uncover()
		"answer":
			if action == "want":
				d["level"] = int(d["level"]) + step_up()
				_uncover()
			elif action == "reraise":
				d["level"] = int(d["level"]) + step_up()
				d["reraised"] = true
				d["phase"] = "answer2"
				d["turn"] = other
			else:
				_fold(side)
		"answer2":
			if action == "want":
				d["level"] = int(d["level"]) + step_up()
				_uncover()
			else:
				_fold(side)


func _fold(side: int) -> void:
	d["folded"] = side
	var lv := int(d["level"])
	(d["net"] as Array)[side] = -lv
	(d["net"] as Array)[1 - side] = lv
	d["ranking"] = [1 - side, side]
	_finish(1 - side, "fold")


## Uncovers the baza of this round; the hand ends when someone has it won, else the next round.
func _uncover() -> void:
	var rd := int(d["round"])
	var a := str(hand(0)[rd])
	var b := str(hand(1)[rd])
	var la := level(a)
	var lb := level(b)
	var w := -1
	if la > lb:
		w = 0
	elif lb > la:
		w = 1
	bazas().append({"cards": [a, b], "levels": [la, lb], "winner": w})
	(d["log"] as Array).append({"kind": "baza", "round": rd, "cards": [a, b], "winner": w})
	var won := [0, 0]
	for bz: Dictionary in bazas():
		if int(bz["winner"]) >= 0:
			won[int(bz["winner"])] += 1
	d["step"] = step() + 1
	var decided := int(won[0]) >= 2 or int(won[1]) >= 2 or rd >= 2
	if decided:
		var w2 := hand_winner(levels(0), levels(1), int(d["mano"]))
		var lv := int(d["level"])
		(d["net"] as Array)[w2] = lv
		(d["net"] as Array)[1 - w2] = -lv
		(d["scores"] as Array)[0] = int(won[0])
		(d["scores"] as Array)[1] = int(won[1])
		d["ranking"] = [w2, 1 - w2]
		_finish(w2, "bazas")
		return
	d["round"] = rd + 1
	d["raised"] = false
	d["reraised"] = false
	d["first"] = int(d["mano"]) if w < 0 else 1 - w
	d["phase"] = "bet"
	d["turn"] = int(d["first"])
	_gestures()


func _advance() -> void:
	var guard := 0
	while not over() and guard < 40:
		guard += 1
		var side := int(d["turn"])
		if plays(side):
			return
		_apply(side, ai_decision(side))


func _ai_move(side: int) -> String:
	return ai_decision(side)
