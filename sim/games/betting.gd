class_name Betting
extends RefCounted
## Bets on any game or competition (docs/gdd/04f_vida_y_fiestas.md §4.26.6; figures: data/games.json "bets"). The
## bookmaker (a NPC in the plaza or the tavern keeper) gives odds from the sim's chances (Games.win_odds: automatic
## games with their own keys) with the house's margin: odds = (1 − margin) / chance, rounded down to `step`, between
## min_odds and max_odds. A bet of s on an outcome that comes pays floor(s × odds) (the stake included); one that does
## not loses s. Stakes of data/games.json "stakes", at most the cap (O-V8). The gold comes from and goes to outside
## (P4) but for the house's part: with opts.house, the owner of that building takes floor(s × margin) of every bet.
##
## Two ways in:
##   - the order game_bet {actor, game, opponents → players [refs], opts, match, on (a side), stake}: a bet on a game
##     of others resolved now with Games.auto (the same match id gives the same result to whoever resolves it: the
##     fiestas resolve their competitions with their own id and a bet on it, placed before, settles the same);
##   - `bets` [{on, stake}] in the order game_play: betting on one's own game (on = 0) or against oneself (fraud if one
##     then loses having played: «trampa», seen with chance bets.fraud_seen).
## For bets kept until a competition is run later (the fiestas' calendar), quote() and settle() are the pieces.


## {side: odds} from {side: chance}.
static func quote(games: Dictionary, chances: Dictionary) -> Dictionary:
	var b: Dictionary = games.get("bets", {})
	var m := float(b.get("margin", 0.1))
	var step := float(b.get("step", 0.05))
	var out: Dictionary = {}
	for k: Variant in chances:
		var p := maxf(0.001, float(chances[k]))
		var o := floorf((1.0 - m) / p / step) * step
		out[k] = clampf(o, float(b.get("min_odds", 1.05)), float(b.get("max_odds", 20.0)))
	return out


## The market of a game: {side: {chance, odds}} (n automatic games from Games.win_odds).
static func market(games: Dictionary, spec: Dictionary, n: int = -1) -> Dictionary:
	if n < 0:
		n = int((games.get("bets", {}) as Dictionary).get("samples", 60))
	var ch := Games.win_odds(games, spec, n)
	var q := quote(games, ch)
	var out: Dictionary = {}
	for k: Variant in ch:
		out[k] = {"chance": float(ch[k]), "odds": float(q[k])}
	return out


static func payout(stake: int, odds: float) -> int:
	return floori(stake * odds + 0.0001)


## What a bet of `stake` on `on` at `odds` leaves when `winner` won: payout − stake, or −stake.
static func settle(stake: int, odds: float, on: int, winner: int) -> int:
	return payout(stake, odds) - stake if on == winner else -stake


## Whether a stake is valid: one of `stakes`, at most the cap.
static func valid_stake(games: Dictionary, stake: int) -> bool:
	return stake in (games.get("stakes", []) as Array) and stake <= int(games.get("cap", 50))


## The order game_bet: a bet on a game of others, resolved now.
static func order_bet(sim: Sim, o: Dictionary) -> Dictionary:
	if str(o.get("incident", "")) != "":
		return _order_bet_incident(sim, o)
	if str(o.get("festival", "")) != "":
		return FestivalGames.order_bet(sim, o)  # a festival's competition, before it is fought
	var st := sim.state
	var games: Dictionary = sim.catalog.games
	var g := str(o.get("game", ""))
	if not g in Games.GAMES:
		return Orders.fail("unknown_game")
	var actor := str(o.get("actor", ""))
	var ch: Dictionary = st.characters.get(actor, {})
	if ch.is_empty() or not bool(ch.get("alive", true)) or str(ch.get("family", "")) == "":
		return Orders.fail("unknown_actor")
	var players: Array = []
	for ref: Variant in o.get("players", []):
		var p := Games.player_ref(st, games, str(ref))
		if p.is_empty() or str(p["id"]) == actor:
			return Orders.fail("bad_players")
		players.append(p)
	var lim: Array = Games.PLAYERS.get(g, [2, 2])
	if players.size() < int(lim[0]) or players.size() > int(lim[1]):
		return Orders.fail("bad_players")
	var stake := int(o.get("stake", 0))
	if not valid_stake(games, stake):
		return Orders.fail("bad_stake")
	var fam := str(ch["family"])
	if not Money.can_pay(st, fam, stake):
		return Orders.fail("not_enough_gold")
	var on := int(o.get("on", -1))
	if on < 0 or on >= players.size():
		return Orders.fail("bad_bet")
	var mid := str(o.get("match", ""))
	if mid == "":
		return Orders.fail("bad_bet")
	var opts: Dictionary = (o.get("opts", {}) as Dictionary).duplicate(true)
	opts.erase("rake")
	var house := str(opts.get("house", ""))
	if house != "" and not st.buildings.has(house):
		return Orders.fail("unknown_house")
	var cfk := str(opts.get("city_feast", ""))
	if cfk != "":  # fiestas: watching another city's feast game there, once (FestivalCity)
		var fw := FestivalCity.reason(sim, actor, cfk, "bet")
		if fw == "" and (mid != cfk or str(FestivalCity.game_of(sim, actor, cfk).get("game", "")) != g):
			fw = "bad_bet"
		if fw != "":
			return Orders.fail(fw)
	var spec := {"game": g, "match": mid, "seed": maxi(st.world_seed, 1), "players": players, "player": -1,
		"stake": int(o.get("game_stake", 0)), "opts": opts}
	var mk := market(games, spec)
	var odds := float((mk[on] as Dictionary)["odds"])
	var r := Games.auto(games, spec)
	var w := int(r.get("winner", -1))
	var net := settle(stake, odds, on, w)
	Money.change(sim, fam, net, Money.GAMES, "bet_" + g, house, actor, false)
	var cut := _house_cut(sim, games, house, fam, stake, g)
	if cfk != "":
		FestivalCity.done(sim, fam, actor, cfk, "bet")
	sim.events.append({"type": "game_bet_settled", "actor": actor, "family": fam, "game": g, "match": mid, "on": on,
		"stake": stake, "odds": odds, "winner": w, "won": w == on, "net": net, "house": house, "house_cut": cut})
	Games._warn_losses(sim, fam)
	if OS.is_debug_build():
		print("[Betting] %s apuesta %d a %d en %s (cuota %.2f): gana %d, oro %+d" % [actor, stake, on, mid, odds, w, net])
	return Orders.ok()


## The house's part of a bet placed in `house` (its owner's, when it is another family).
static func _house_cut(sim: Sim, games: Dictionary, house: String, fam: String, stake: int, g: String) -> int:
	if house == "":
		return 0
	var owner := Money.family_of(sim.state, house)
	var cut := floori(stake * float((games.get("bets", {}) as Dictionary).get("margin", 0.1)))
	if owner != "" and owner != fam and cut > 0:
		Money.change(sim, owner, cut, Money.GAMES, "house_bet_" + g, house, "")
		return cut
	return 0


## The bets of a game_play on one's own game: {ok, reason, bets [{on, stake, odds}]} priced before the game is played.
static func own_bets(sim: Sim, spec: Dictionary, bets: Array, fam: String, reserve: int) -> Dictionary:
	var games: Dictionary = sim.catalog.games
	if bets.is_empty():
		return {"ok": true, "bets": []}
	var total := 0
	var mk := market(games, spec)
	var out: Array = []
	for b: Variant in bets:
		var bd := b as Dictionary
		var stake := int(bd.get("stake", 0))
		var on := int(bd.get("on", -1))
		if not valid_stake(games, stake):
			return {"ok": false, "reason": "bad_stake"}
		if not mk.has(on):
			return {"ok": false, "reason": "bad_bet"}
		total += stake
		out.append({"on": on, "stake": stake, "odds": float((mk[on] as Dictionary)["odds"])})
	if not Money.can_pay(sim.state, fam, reserve + total):
		return {"ok": false, "reason": "not_enough_gold"}
	return {"ok": true, "bets": out}


# --- Bets on a brawl of the town (vida's altercation, 04f §4.24.5 and §4.26.6) -------------------------------------------
## game_bet {actor, incident, on (0: the first of the two, 1: the other), stake}: while the two are still on their way
## (phase gathering) the bookmaker prices the brawl (the incident's own duel, BrawlMatch) and takes the stake; the bet
## rides on the incident (state.town.incidents, saved since v17: no save of its own) and is paid when it is fought
## (incident_fight: settle_incident) or given back if it never is (they cool down, the watch comes first: refund_incident).

## The spec of the brawl of altercation `inc` (the duel Incidents._fight will fight).
static func brawl_spec(sim: Sim, inc: Dictionary) -> Dictionary:
	var d := Incidents.def(sim, "altercation")
	var w := str(d.get("weapon", "fists"))
	var players: Array = []
	for c: Variant in inc.get("people", []):
		var ch: Dictionary = sim.state.characters.get(str(c), {})
		players.append({"id": str(c), "name": str(ch.get("name", "?")), "family": str(ch.get("family", "")),
			"stats": (ch.get("stats", {}) as Dictionary).duplicate(), "fighter": Duels.fighter_of(sim, str(c), w)})
	return {"game": "brawl", "match": str(inc["id"]), "seed": sim.state.world_seed, "players": players, "player": -1,
		"stake": 0, "opts": {"kind": str(d.get("duel_kind", "first_blood")), "weapon": w}}


static func _order_bet_incident(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var games: Dictionary = sim.catalog.games
	var actor := str(o.get("actor", ""))
	var ch: Dictionary = st.characters.get(actor, {})
	if ch.is_empty() or str(ch.get("family", "")) == "":
		return Orders.fail("unknown_actor")
	var inc := Incidents.find(st, str(o["incident"]))
	if inc.is_empty() or str(inc.get("def", "")) != "altercation":
		return Orders.fail("unknown_incident")
	if str(inc.get("phase", "")) != "gathering":
		return Orders.fail("too_late")
	if actor in (inc.get("people", []) as Array):
		return Orders.fail("bad_bet")  # one does not bet on one's own brawl
	var stake := int(o.get("stake", 0))
	if not valid_stake(games, stake):
		return Orders.fail("bad_stake")
	var fam := str(ch["family"])
	if not Money.can_pay(st, fam, stake):
		return Orders.fail("not_enough_gold")
	var on := int(o.get("on", -1))
	if on < 0 or on > 1:
		return Orders.fail("bad_bet")
	var mk := market(games, brawl_spec(sim, inc))
	var odds := float((mk[on] as Dictionary)["odds"])
	Money.change(sim, fam, -stake, Money.GAMES, "bet_brawl", "", actor)
	if not inc.get("bets") is Array:
		inc["bets"] = []
	(inc["bets"] as Array).append({"actor": actor, "family": fam, "on": on, "stake": stake, "odds": odds, "settled": false})
	sim.events.append({"type": "game_bet_placed", "actor": actor, "family": fam, "game": "brawl", "incident": str(inc["id"]),
		"on": on, "stake": stake, "odds": odds})
	Games._warn_losses(sim, fam)
	if OS.is_debug_build():
		print("[Betting] %s apuesta %d a %s en la pelea %s (cuota %.2f)" % [actor, stake, (inc["people"] as Array)[on], inc["id"], odds])
	return Orders.ok()


## The brawl of `inc` was fought and `winner` (a character id, "" a draw) won: its bets are paid (a draw gives the
## stakes back).
static func settle_incident(sim: Sim, inc: Dictionary, winner: String) -> void:
	var people: Array = inc.get("people", [])
	for b: Variant in inc.get("bets", []):
		var bet := b as Dictionary
		if bool(bet.get("settled", false)):
			continue
		bet["settled"] = true
		var stake := int(bet["stake"])
		var back := stake if winner == "" else (payout(stake, float(bet["odds"])) if str(people[int(bet["on"])]) == winner else 0)
		if back > 0:
			Money.change(sim, str(bet["family"]), back, Money.GAMES, "bet_brawl", "", str(bet["actor"]))
		sim.events.append({"type": "game_bet_settled", "actor": str(bet["actor"]), "family": str(bet["family"]), "game": "brawl",
			"match": str(inc["id"]), "incident": str(inc["id"]), "on": int(bet["on"]), "stake": stake, "odds": float(bet["odds"]),
			"winner": people.find(winner), "won": back > stake, "net": back - stake, "house": "", "house_cut": 0})


## The incident closes: a bet still open (the brawl never came) gives its stake back.
static func refund_incident(sim: Sim, inc: Dictionary) -> void:
	for b: Variant in inc.get("bets", []):
		var bet := b as Dictionary
		if bool(bet.get("settled", false)):
			continue
		bet["settled"] = true
		Money.change(sim, str(bet["family"]), int(bet["stake"]), Money.GAMES, "bet_brawl", "", str(bet["actor"]))
		sim.events.append({"type": "game_bet_settled", "actor": str(bet["actor"]), "family": str(bet["family"]), "game": "brawl",
			"match": str(inc["id"]), "incident": str(inc["id"]), "on": int(bet["on"]), "stake": int(bet["stake"]),
			"odds": float(bet["odds"]), "winner": -1, "won": false, "net": 0, "refunded": true, "house": "", "house_cut": 0})
