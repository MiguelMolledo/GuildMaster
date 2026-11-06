class_name Games
extends RefCounted
## The API of the games and competitions (docs/gdd/04f_vida_y_fiestas.md §4.26; contract: docs/contratos/juegos.md) for
## the screens, the fiestas (rama fiestas), the tavern (rama posada), the bots and the benches.
##
##   Games.create(games, spec)      a GameMatch to play step by step (the screen; spec below)
##   Games.auto(games, spec)        the whole game played by the AI on every side: its result()
##   Games.win_odds(games, spec, n) the chance of each side (or outcome) winning, from n automatic games with their own
##                                  keys (they never move the real game's rolls): what the bookmaker's odds start from
##   Games.player_of(state, chr)    a player from a character (its stats; temper even)
##   Games.preset_player(games, id) a player from data/games.json "presets" ("preset:<id>[#n]")
##   Games.replay(sim, order)       the order game_play: the game replayed with its moves, then money and reputation
##
## spec = {game, match (the id: its rolls' key), seed (the world's), players [player], player (the side the human
## plays, -1 = none), stake, opts {...the game's own}}. Nothing here is saved: a game exists while it is played.

const GAMES: Array[String] = ["azar", "mayor", "pulso", "envite", "tourney", "joust", "sortija", "race", "bulls"]
## How many players a game takes [min, max] (the actor included).
const PLAYERS: Dictionary = {"azar": [2, 2], "pulso": [2, 2], "mayor": [2, 4], "envite": [2, 2], "tourney": [8, 8], "joust": [2, 2], "sortija": [2, 6], "race": [2, 6], "bulls": [1, 4]}
## Games played for a stake (the others are competitions with a prize; pulso may go for a stake or for nothing).
const STAKED: Array[String] = ["azar", "mayor", "envite"]


static func create(games: Dictionary, spec: Dictionary) -> GameMatch:
	var g := str(spec.get("game", ""))
	var id := str(spec.get("match", g))
	var seed := int(spec.get("seed", 1))
	var players: Array = spec.get("players", [])
	var player := int(spec.get("player", -1))
	var stake := int(spec.get("stake", 0))
	var opts: Dictionary = spec.get("opts", {})
	match g:
		"azar":
			return AzarMatch.create(games, id, seed, players, player, stake, opts)
		"mayor":
			return MayorMatch.create(games, id, seed, players, player, stake, opts)
		"pulso":
			return PulsoMatch.create(games, id, seed, players, player, stake, opts)
		"envite":
			return EnviteMatch.create(games, id, seed, players, player, stake, opts)
		"tourney":
			return TourneyMatch.create(games, games.get("_combat", {}), id, seed, players, player, stake, opts)
		"joust":
			return JoustMatch.create(games, id, seed, players, player, stake, opts)
		"sortija":
			return SortijaMatch.create(games, id, seed, players, player, stake, opts)
		"race":
			return RaceMatch.create(games, id, seed, players, player, stake, opts)
		"bulls":
			return BullsMatch.create(games, id, seed, players, player, stake, opts)
		# not games of their own (no game_play): the town's fights of vida, played or priced through their incident
		"rescue":
			return RescueMatch.create(games, games.get("_combat", {}), id, seed, players, player, opts)
		"brawl":
			return BrawlMatch.create(games, games.get("_combat", {}), id, seed, players, opts)
	return null


static func auto(games: Dictionary, spec: Dictionary) -> Dictionary:
	var s := spec.duplicate()
	s["player"] = -1
	var m := create(games, s)
	return m.result() if m != null else {"ok": false, "over": true, "winner": -1}


## The chance of each side winning (index -> float, plus -1 for no winner), from `n` automatic games keyed
## "<match>|odds|<i>": the same players and options, other dice. Laplace-smoothed so no outcome is ever 0.
static func win_odds(games: Dictionary, spec: Dictionary, n: int = 60) -> Dictionary:
	var counts: Dictionary = {}
	var players: Array = spec.get("players", [])
	var was := GameMatch.verbose
	GameMatch.verbose = false
	for i: int in n:
		var s := spec.duplicate()
		s["player"] = -1
		s["match"] = "%s|odds|%d" % [str(spec.get("match", "")), i]
		var r := auto(games, s)
		var w := int(r.get("winner", -1))
		counts[w] = int(counts.get(w, 0)) + 1
	GameMatch.verbose = was
	var out: Dictionary = {}
	var k := players.size()
	for side: int in k:
		out[side] = (float(counts.get(side, 0)) + 0.5) / (float(n) + 0.5 * k)
	return out


## A player from a character of the state.
static func player_of(state: WorldState, chr: String) -> Dictionary:
	var ch: Dictionary = state.characters.get(chr, {})
	return {"id": chr, "name": str(ch.get("name", chr)), "family": str(ch.get("family", "")),
		"stats": (ch.get("stats", {}) as Dictionary).duplicate(), "temper": "even", "preset": ""}


## A player from a preset of data/games.json ("preset:<id>" or "preset:<id>#<n>" for several of the same).
static func preset_player(games: Dictionary, ref: String) -> Dictionary:
	var pid := ref.trim_prefix("preset:").get_slice("#", 0)
	var pr: Dictionary = (games.get("presets", {}) as Dictionary).get(pid, {})
	if pr.is_empty():
		return {}
	return {"id": ref if ref.begins_with("preset:") else "preset:" + ref, "name": "", "name_key": str(pr.get("name_key", "")),
		"family": "", "stats": (pr.get("stats", {}) as Dictionary).duplicate(), "temper": str(pr.get("temper", "even")),
		"preset": pid, "look": int(pr.get("look", 0)), "female": bool(pr.get("female", false)), "horse": str(pr.get("horse", ""))}


## A player by reference: a character id or "preset:<id>[#n]" ({} if unknown).
static func player_ref(state: WorldState, games: Dictionary, ref: String) -> Dictionary:
	if ref.begins_with("preset:"):
		return preset_player(games, ref)
	if state.characters.has(ref):
		return player_of(state, ref)
	return {}


## The default id of a game played now by `actor` (the clock minute: a game cannot be thrown again in the same minute,
## and every played game moves the clock one minute through its order).
static func match_id(state: WorldState, game: String, actor: String) -> String:
	return "%s|%s|%d" % [game, actor, int(state.clock.get("minute", 0))]


## What a game may cost the actor at most (the gold he must have to sit down).
static func max_loss(game: String, stake: int, cap: int) -> int:
	match game:
		"azar", "mayor":
			return mini(2 * stake, maxi(cap, stake))
		"envite":
			return mini(maxi(cap, stake), stake * 7)  # three rounds of a raise and a raise again
	return stake


## The spec of the order `o` (players read from the state), or {"reason": ...} when it is not valid.
static func spec_of(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var games: Dictionary = sim.catalog.games
	var g := str(o.get("game", ""))
	if not g in GAMES:
		return {"reason": "unknown_game"}
	var actor := str(o.get("actor", ""))
	var ch: Dictionary = st.characters.get(actor, {})
	if ch.is_empty() or not bool(ch.get("alive", true)) or str(ch.get("family", "")) == "":
		return {"reason": "unknown_actor"}
	var players: Array = [player_of(st, actor)]
	for ref: Variant in o.get("opponents", []):
		var p := player_ref(st, games, str(ref))
		if p.is_empty() or str(p["id"]) == actor:
			return {"reason": "bad_players"}
		players.append(p)
	var lim: Array = PLAYERS.get(g, [2, 2])
	if players.size() < int(lim[0]) or players.size() > int(lim[1]):
		return {"reason": "bad_players"}
	var stake := int(o.get("stake", 0))
	if g in STAKED or stake > 0:
		if not stake in (games.get("stakes", []) as Array):
			return {"reason": "bad_stake"}
		if stake > int(games.get("cap", 50)):
			return {"reason": "over_cap"}
		if not Money.can_pay(st, str(ch["family"]), max_loss(g, stake, int(games.get("cap", 50)))):
			return {"reason": "not_enough_gold"}
	# who may enter (the joust: a title of Ciudadano or more) and the entry fee (horse and lance rented: D8)
	var gsec: Dictionary = games.get(g, {})
	var req: Dictionary = gsec.get("requires", {})
	if str(req.get("title", "")) != "" and Titles.rank(sim, Titles.current(sim, str(ch["family"]))) \
			< Titles.rank(sim, str(req["title"])):
		return {"reason": "no_title"}
	if int(gsec.get("entry_fee", 0)) > 0 and not Money.can_pay(st, str(ch["family"]), int(gsec["entry_fee"])):
		return {"reason": "not_enough_gold"}
	var opts: Dictionary = (o.get("opts", {}) as Dictionary).duplicate(true)
	opts.erase("rake")  # the margin of an order is the house's (opts.house), never the order's
	var house := str(opts.get("house", ""))
	if house != "" and not st.buildings.has(house):
		return {"reason": "unknown_house"}
	if opts.has("loaded"):
		if not g in ["azar", "mayor"] or int(opts["loaded"]) != 0:
			return {"reason": "bad_option"}
		var item := str((games.get("loaded", {}) as Dictionary).get("item", "loaded_dice"))
		if Inventory.count(ch.get("inventory", {}), item) <= 0:
			return {"reason": "no_loaded_dice"}
	var fest := FestivalGames.play_block(sim, o)  # a festival's competition: only the entry called, once
	if fest != "":
		return {"reason": fest}
	var mid := str(o.get("match", ""))
	if mid == "":
		mid = match_id(st, g, actor)
	return {"game": g, "match": mid, "seed": maxi(st.world_seed, 1), "players": players, "player": 0, "stake": stake,
		"opts": opts}


## The order game_play {actor, game, opponents [refs], stake, opts, moves [the played side's choices, in order], auto
## (true: what is left is resolved without playing; default true), match (optional: the caller's id)}. Replays the game
## with the same keys, then applies what it left: the actor's family wins or loses its net (the house keeps its rake
## of a net win in a licensed house and gives it to the house's owner). Gold of the others comes from and goes to
## outside (P4). Emits game_played.
static func replay(sim: Sim, o: Dictionary) -> Dictionary:
	var spec := spec_of(sim, o)
	if spec.has("reason"):
		return Orders.fail(str(spec["reason"]))
	var games: Dictionary = sim.catalog.games
	var fam := str(sim.state.characters[str(o["actor"])]["family"])
	var cap := int(games.get("cap", 50))
	var reserve := max_loss(str(spec["game"]), int(spec["stake"]), cap) if int(spec["stake"]) > 0 else 0
	var bets := Betting.own_bets(sim, spec, o.get("bets", []), fam, reserve)
	if not bool(bets["ok"]):
		return Orders.fail(str(bets["reason"]))
	spec["bets"] = bets["bets"]
	var m := create(games, spec)
	for mv: Variant in o.get("moves", []):
		if m.over():
			return Orders.fail("bad_move")
		var r := m.choose(0, str(mv))
		if not bool(r["ok"]):
			return Orders.fail("bad_move")
	if not m.over():
		if not bool(o.get("auto", true)):
			return Orders.fail("unfinished")
		m.auto_finish()
	var res := m.result()
	return _apply(sim, o, spec, m, res)


static func _apply(sim: Sim, o: Dictionary, spec: Dictionary, m: GameMatch, res: Dictionary) -> Dictionary:
	var st := sim.state
	var games: Dictionary = sim.catalog.games
	var actor := str(o["actor"])
	var fam := str(st.characters[actor]["family"])
	var net := int((res["net"] as Array)[0])
	var house := str((spec["opts"] as Dictionary).get("house", ""))
	var facts: Array = (res.get("facts", []) as Array).duplicate(true)
	var w := int(res["winner"])
	var caught := _caught(sim, spec, m) if (spec["opts"] as Dictionary).has("loaded") else ""
	if caught != "":
		net = -int(spec["stake"])  # the game does not count: the cheat loses his stake and the dice
		w = -1
		facts.append({"kind": "caught", "by": caught})
	var cut := 0
	if net > 0 and m.rake() > 0.0 and (house == "" or Money.family_of(st, house) != fam):
		cut = floori(net * m.rake())  # (one's own house takes nothing: posada, its gaming table)
	if net - cut != 0:
		Money.change(sim, fam, net - cut, Money.GAMES, str(spec["game"]), house, actor, false)
	if cut > 0 and house != "":
		var owner := Money.family_of(st, house)
		if owner != "" and owner != fam:
			Money.change(sim, owner, cut, Money.GAMES, "house_" + str(spec["game"]), house, "")
	# bets on one's own game (priced before it was played)
	var bet_net := 0
	var against := false
	for b: Dictionary in spec.get("bets", []):
		var bn := Betting.settle(int(b["stake"]), float(b["odds"]), int(b["on"]), w)
		bet_net += bn
		# against oneself: betting on the other of a head-to-head (in a field of many, a bet on another is just a bet)
		against = against or (int(b["on"]) != 0 and (spec["players"] as Array).size() == 2)
		Betting._house_cut(sim, games, house, fam, int(b["stake"]), str(spec["game"]))
	if bet_net != 0:
		Money.change(sim, fam, bet_net, Money.GAMES, "bet_" + str(spec["game"]), house, actor, false)
	# betting against oneself and losing having played is fraud, if someone notices (O-V10, «trampa»)
	if against and w != 0 and (m.moves() as Array).size() > 0 and caught == "" \
			and GameRules.roll(int(spec["seed"]), str(spec["match"]), 99, "fraud") \
			< float((games.get("bets", {}) as Dictionary).get("fraud_seen", 0.5)):
		_cheat(sim, fam, actor, str(spec["match"]), "fraud", "")
		facts.append({"kind": "fraud"})
	# a competition's entry fee and prize (data/games.json "<game>"; the fiestas' sponsors add theirs by the event)
	var sec: Dictionary = games.get(str(spec["game"]), {})
	var rank: Array = res.get("ranking", [])
	var entry := int(sec.get("entry_fee", 0))
	if entry > 0:
		Money.change(sim, fam, -entry, Money.GAMES, "entry_" + str(spec["game"]), house, actor, true)
	if sec.has("prize") and caught == "" and w == 0:
		var pz: Dictionary = sec["prize"]
		if int(pz.get("gold", 0)) != 0:
			Money.change(sim, fam, int(pz["gold"]), Money.GAMES, "prize_" + str(spec["game"]), house, actor, true)
		if int(pz.get("reputation", 0)) != 0:
			Reputation.change(sim, fam, int(pz["reputation"]), "games_prize")
		facts.append({"kind": "prize", "gold": int(pz.get("gold", 0)), "reputation": int(pz.get("reputation", 0))})
		var favor := int(sec.get("favor", 0))
		if favor > 0:  # the favour of a lady or a knight: the one the winner courts most (cortejo, 4.10.1)
			var best := ""
			var top := 0
			for c: Variant in Courtship.candidates(sim, actor):
				var a := Courtship.affinity(st, actor, str(c))
				if a > top:
					top = a
					best = str(c)
			if best != "":
				Courtship.add_affinity(sim, actor, best, favor, "games_favor")
				facts.append({"kind": "favor", "of": best})
	elif sec.has("finalist") and caught == "" and rank.size() > 1 and int(rank[1]) == 0:
		var fz: Dictionary = sec["finalist"]
		if int(fz.get("reputation", 0)) != 0:
			Reputation.change(sim, fam, int(fz["reputation"]), "games_finalist")
		facts.append({"kind": "finalist", "reputation": int(fz.get("reputation", 0))})
	if str((spec["opts"] as Dictionary).get("event", "")) != "":
		FestivalGames.played(sim, spec, res)  # a festival's competition the player fought: its result, its bets
	# the bulls: applause and jeers (O-V5 a: a failure is a fright, never a wound until 4.22's health)
	for f: Dictionary in res.get("facts", []):
		if str(f.get("kind", "")) == "bulls":
			var rep := int(f.get("breaks", 0)) * int(sec.get("rep_per_break", 2)) + int(f.get("fails", 0)) * int(sec.get("rep_per_fail", -1))
			if rep != 0:
				Reputation.change(sim, fam, rep, "games_bulls")
			if int(f.get("fails", 0)) > 0:
				Emotions.add(sim, actor, "scared", "bull")
	var opp: Array = []
	for p: Variant in (spec["players"] as Array).slice(1):
		opp.append(str((p as Dictionary)["id"]))
	sim.events.append({"type": "game_played", "actor": actor, "family": fam, "game": str(spec["game"]),
		"match": str(spec["match"]), "opponents": opp, "stake": int(spec["stake"]), "winner": w, "won": w == 0,
		"net": net - cut, "house_cut": cut, "house": house, "how": "caught" if caught != "" else str(res["how"]),
		"moves": (m.moves() as Array).size(), "facts": facts, "bets_net": bet_net, "entry": entry,
		"event": str((spec["opts"] as Dictionary).get("event", ""))})
	_warn_losses(sim, fam)
	if OS.is_debug_build():
		print("[Games] partida %s (%s) de %s: gana %d, oro %+d (casa %d, apuestas %+d), %d jugadas suyas, %s%s" % [
			spec["match"], spec["game"], actor, w, net - cut, cut, bet_net, (m.moves() as Array).size(), res["how"],
			(", PILLADO por " + caught) if caught != "" else ""])
	return Orders.ok()


## Loaded dice: each rival may notice them (keyed): empathy of the rival against the dexterity of the cheat. The id of
## who caught him, or "".
static func _caught(sim: Sim, spec: Dictionary, m: GameMatch) -> String:
	var games: Dictionary = sim.catalog.games
	var ld: Dictionary = games.get("loaded", {})
	var c: Dictionary = ld.get("catch", {})
	var me: Dictionary = (spec["players"] as Array)[0]
	for j: int in range(1, (spec["players"] as Array).size()):
		var p: Dictionary = (spec["players"] as Array)[j]
		var th := int(c.get("base", 25)) + (GameRules.stat(p, "empathy") - GameRules.stat(me, "dexterity")) * int(c.get("step", 5))
		if bool(GameRules.check(games, th, int(spec["seed"]), str(spec["match"]), 98, "caught|%d" % j)["success"]):
			var actor := str(me["id"])
			var fam := str(sim.state.characters[actor]["family"])
			var item := str(ld.get("item", "loaded_dice"))
			var inv: Dictionary = sim.state.characters[actor]["inventory"]
			for stk: Dictionary in (inv.get("stacks", []) as Array).duplicate():
				if str(stk["item"]) == item:
					Inventory.remove(inv, item, int(stk["quality"]), 1)
					break
			_cheat(sim, fam, actor, str(spec["match"]), "loaded_dice", str(p["id"]))
			return str(p["id"])
	return ""


## A cheat seen: a public fact with the charge «trampa» (cheat, light: H11's court), reputation and an event the city
## life (altercations, 4.24.5) can listen to.
static func _cheat(sim: Sim, fam: String, actor: String, match_id: String, how: String, by: String) -> void:
	var ld: Dictionary = sim.catalog.games.get("loaded", {})
	var fact := Tribunal.add_fact(sim, "cheat", fam, actor, "cheat")
	Reputation.change(sim, fam, int(ld.get("reputation", -5)), "games_cheat")
	sim.events.append({"type": "game_cheat_caught", "actor": actor, "family": fam, "match": match_id, "how": how,
		"by": by, "fact": fact})
	if OS.is_debug_build():
		print("[Games] trampa vista: %s (%s) en %s, la ve %s, hecho %s" % [actor, how, match_id, by if by != "" else "alguien", fact])


## O-V8: a warning when the family has lost more than warn_loss at games and bets today (once a day).
static func _warn_losses(sim: Sim, fam: String) -> void:
	var st := sim.state
	var day := Clock.day(int(st.clock["minute"]))
	var lost := 0
	for e: Dictionary in st.ledger.get("entries", []):
		if int(e.get("day", -1)) == day and str(e.get("family", "")) == fam and str(e.get("category", "")) == Money.GAMES:
			lost += int(e.get("amount", 0))
	var limit := int(sim.catalog.games.get("warn_loss", 100))
	if lost >= -limit:
		return
	for n: Dictionary in st.notices:
		if str(n.get("key", "")) == "notice.games_losses" and str(n.get("family", "")) == fam and int(n.get("day", -1)) == day:
			return
	Notices.add(sim, fam, Notices.WARNING, "notice.games_losses", {"gold": -lost})
