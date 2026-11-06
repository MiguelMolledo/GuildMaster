class_name FestivalGames
extends RefCounted
## The games of the festivals (docs/gdd/04f_vida_y_fiestas.md §4.25.3 `spectacle`, §4.26; fiestas: Festivals). A
## festival's spectacle that is a competition of 4.26 (data/games.json "spectacles": the bulls of the Corpus, the horse
## race of the fairs, the joust and the fighting tournament of the tournament the mayor opens by organizing the joust)
## is fought when Festivals fires it (festival_spectacle):
##   - nobody of the player's family entered: Games.auto with the match id "<festival>|<spectacle>" among its field
##     (presets), festival_game_result, the bets on it paid;
##   - the player's family entered (order game_enter, before it starts): festival_game_call, and the screen plays it
##     (game_play with that match and opts.event = the festival); the game's result pays the bets. If nobody plays
##     it (a bot, the window closed), the festival's end resolves it without playing.
## Bets (game_bet {festival, spectacle, on, stake}) are placed before the spectacle at the bookmaker's odds of its field.
## Entries, calls and bets live in the festival's instance (state.festivals, saved since v18): no save of their own.


static func spectacle_cfg(sim: Sim, sp: String) -> Dictionary:
	return (sim.catalog.games.get("spectacles", {}) as Dictionary).get(sp, {})


static func is_game(sim: Sim, sp: String) -> bool:
	return not spectacle_cfg(sim, sp).is_empty()


static func match_id(inst: Dictionary, sp: String) -> String:
	return "%s|%s" % [str(inst["id"]), sp]


## The refs of the field of a spectacle: its presets; with `actor`, he takes the first place.
static func field(sim: Sim, sp: String, actor: String = "") -> Array:
	var c := spectacle_cfg(sim, sp)
	var refs: Array = []
	for r: Variant in c.get("field", []):
		refs.append("preset:" + str(r))
	var size := int(c.get("size", refs.size()))
	if actor != "":
		return [actor] + refs.slice(0, size - 1)
	return refs.slice(0, size)


## The spec of a spectacle's game (the field, or the actor with his opponents).
static func spec_for(sim: Sim, inst: Dictionary, sp: String, actor: String = "") -> Dictionary:
	var c := spectacle_cfg(sim, sp)
	var players: Array = []
	for r: Variant in field(sim, sp, actor):
		players.append(Games.player_ref(sim.state, sim.catalog.games, str(r)))
	return {"game": str(c.get("game", "")), "match": match_id(inst, sp), "seed": maxi(sim.state.world_seed, 1),
		"players": players, "player": -1, "stake": 0, "opts": {"event": str(inst["id"])}}


static func _games(inst: Dictionary) -> Dictionary:
	if not inst.get("games") is Dictionary:
		inst["games"] = {"entries": {}, "bets": [], "results": {}}
	return inst["games"]


## Whether spectacle `sp` of `inst` is still to come (not fired yet).
static func _to_come(inst: Dictionary, sp: String) -> bool:
	for k: Variant in inst.get("done", []):
		if str(k).begins_with(sp + "@"):
			return false
	return true


static func _of_festival(sim: Sim, inst: Dictionary, sp: String) -> bool:
	for s: Dictionary in Festivals.spectacles(sim):
		if str(s["festival"]) == str(inst["id"]) and str(s["spectacle"]) == sp:
			return true
	return false


## game_enter {actor, festival, spectacle}: the actor will fight the spectacle's competition (the entry fee and the
## requirements are the game's, checked now and paid when it is played).
## "" if `actor` may enter spectacle `sp` of `inst` now, else why (unknown_actor, unknown_spectacle, too_late,
## already_entered, bet_placed, no_title, not_enough_gold): game_enter's checks, also for the card's button (fiestas).
static func enter_reason(sim: Sim, actor: String, inst: Dictionary, sp: String) -> String:
	var st := sim.state
	var ch: Dictionary = st.characters.get(actor, {})
	if ch.is_empty() or str(ch.get("family", "")) == "":
		return "unknown_actor"
	if inst.is_empty() or not is_game(sim, sp) or not _of_festival(sim, inst, sp):
		return "unknown_spectacle"
	if not _to_come(inst, sp):
		return "too_late"
	var g: Dictionary = inst["games"] if inst.get("games") is Dictionary else {}  # read only: the card asks it too
	if (g.get("entries", {}) as Dictionary).has(sp):
		return "already_entered"
	var fam := str(ch["family"])
	for b: Dictionary in g.get("bets", []):
		if str(b["spectacle"]) == sp and str(b["family"]) == fam:
			return "bet_placed"  # who bet on the field does not then enter it
	var c: Dictionary = sim.catalog.games.get(str(spectacle_cfg(sim, sp).get("game", "")), {})
	var req: Dictionary = c.get("requires", {})
	if str(req.get("title", "")) != "" and Titles.rank(sim, Titles.current(sim, fam)) < Titles.rank(sim, str(req["title"])):
		return "no_title"
	if not Money.can_pay(st, fam, int(c.get("entry_fee", 0))):
		return "not_enough_gold"
	return ""


static func order_enter(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var inst := Festivals.find(sim, str(o.get("festival", "")))
	var sp := str(o.get("spectacle", ""))
	var why := enter_reason(sim, actor, inst, sp)
	if why != "":
		return Orders.fail(why)
	var ch: Dictionary = st.characters[actor]
	var fam := str(ch["family"])
	var g := _games(inst)
	(g["entries"] as Dictionary)[sp] = {"actor": actor, "family": fam, "status": "entered"}
	sim.events.append({"type": "game_entered", "actor": actor, "family": fam, "festival": str(inst["id"]),
		"spectacle": sp, "game": str(spectacle_cfg(sim, sp).get("game", ""))})
	if OS.is_debug_build():
		print("[FestivalGames] %s se inscribe en %s de %s" % [actor, sp, inst["id"]])
	return Orders.ok()


## game_bet {actor, festival, spectacle, on, stake} (Betting.order_bet sends it here).
static func order_bet(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var games: Dictionary = sim.catalog.games
	var actor := str(o.get("actor", ""))
	var ch: Dictionary = st.characters.get(actor, {})
	if ch.is_empty() or str(ch.get("family", "")) == "":
		return Orders.fail("unknown_actor")
	var inst := Festivals.find(sim, str(o.get("festival", "")))
	var sp := str(o.get("spectacle", ""))
	if inst.is_empty() or not is_game(sim, sp) or not _of_festival(sim, inst, sp):
		return Orders.fail("unknown_spectacle")
	if not _to_come(inst, sp):
		return Orders.fail("too_late")
	var g := _games(inst)
	var fam := str(ch["family"])
	if (g["entries"] as Dictionary).has(sp):
		return Orders.fail("bad_bet")  # a field with the player's family in it: bets go with its game_play
	var stake := int(o.get("stake", 0))
	if not Betting.valid_stake(games, stake):
		return Orders.fail("bad_stake")
	if not Money.can_pay(st, fam, stake):
		return Orders.fail("not_enough_gold")
	var spec := spec_for(sim, inst, sp)
	var on := int(o.get("on", -1))
	if on < 0 or on >= (spec["players"] as Array).size():
		return Orders.fail("bad_bet")
	var mk := Betting.market(games, spec)
	var odds := float((mk[on] as Dictionary)["odds"])
	Money.change(sim, fam, -stake, Money.GAMES, "bet_" + str(spec["game"]), "", actor)
	(g["bets"] as Array).append({"actor": actor, "family": fam, "spectacle": sp, "on": on, "stake": stake, "odds": odds,
		"settled": false})
	sim.events.append({"type": "game_bet_placed", "actor": actor, "family": fam, "game": str(spec["game"]),
		"festival": str(inst["id"]), "spectacle": sp, "on": on, "stake": stake, "odds": odds})
	Games._warn_losses(sim, fam)
	return Orders.ok()


## Whether game_play `o` may play the festival match it names ("" if it may, or it names none): only the entry called
## now, by its actor, once (a festival's game is not thrown again).
static func play_block(sim: Sim, o: Dictionary) -> String:
	var ev := str((o.get("opts", {}) as Dictionary).get("event", ""))
	if ev == "":
		return ""
	var inst := Festivals.find(sim, ev)
	if inst.is_empty():
		return "unknown_spectacle"
	var mid := str(o.get("match", ""))
	var sp := mid.get_slice("|", mid.get_slice_count("|") - 1)
	var entry: Dictionary = (_games(inst)["entries"] as Dictionary).get(sp, {})
	if entry.is_empty() or match_id(inst, sp) != mid or str(entry.get("actor", "")) != str(o.get("actor", "")):
		return "not_called"
	if str(entry.get("status", "")) != "called":
		return "not_called"
	return ""


## Festivals fired spectacle `sp` of `inst` (its hour came).
static func on_spectacle(sim: Sim, inst: Dictionary, sp: String) -> void:
	if not is_game(sim, sp):
		return
	var g := _games(inst)
	var entry: Dictionary = (g["entries"] as Dictionary).get(sp, {})
	if not entry.is_empty():
		var refs := field(sim, sp, str(entry["actor"]))
		entry["status"] = "called"
		sim.events.append({"type": "festival_game_call", "festival": str(inst["id"]), "spectacle": sp,
			"game": str(spectacle_cfg(sim, sp).get("game", "")), "actor": str(entry["actor"]), "family": str(entry["family"]),
			"opponents": refs.slice(1), "match": match_id(inst, sp)})
		if OS.is_debug_build():
			print("[FestivalGames] %s: le toca a %s (%s)" % [match_id(inst, sp), entry["actor"], spectacle_cfg(sim, sp).get("game", "")])
		return
	var spec := spec_for(sim, inst, sp)
	var was := GameMatch.verbose
	GameMatch.verbose = false
	var res := Games.auto(sim.catalog.games, spec)
	GameMatch.verbose = was
	_close(sim, inst, sp, spec, res)


## The game of the player's entry was played (Games._apply, game_play with opts.event = the festival and its match).
static func played(sim: Sim, spec: Dictionary, res: Dictionary) -> void:
	var inst := Festivals.find(sim, str((spec.get("opts", {}) as Dictionary).get("event", "")))
	if inst.is_empty():
		return
	var mid := str(spec["match"])
	var sp := mid.get_slice("|", mid.get_slice_count("|") - 1)
	var entry: Dictionary = (_games(inst)["entries"] as Dictionary).get(sp, {})
	if entry.is_empty() or match_id(inst, sp) != mid:
		return
	entry["status"] = "played"
	_close(sim, inst, sp, spec, res)


## The festival ends: an entry called and never played is resolved without playing; a bet on a spectacle that never
## came (a part not organized, the festival cut short) gives its stake back.
static func on_end(sim: Sim, inst: Dictionary) -> void:
	if not inst.get("games") is Dictionary:
		return
	var g := _games(inst)
	for sp: Variant in (g["entries"] as Dictionary).keys():
		var e: Dictionary = g["entries"][sp]
		if str(e.get("status", "")) == "called":
			var refs := field(sim, str(sp), str(e["actor"]))
			Games.replay(sim, {"type": "game_play", "actor": str(e["actor"]), "game": str(spectacle_cfg(sim, str(sp)).get("game", "")),
				"opponents": refs.slice(1), "match": match_id(inst, str(sp)), "opts": {"event": str(inst["id"])}, "auto": true})
	for b: Dictionary in g["bets"]:
		if not bool(b.get("settled", false)):
			b["settled"] = true
			Money.change(sim, str(b["family"]), int(b["stake"]), Money.GAMES, "bet_refund", "", str(b["actor"]))
			sim.events.append({"type": "game_bet_settled", "actor": str(b["actor"]), "family": str(b["family"]),
				"festival": str(inst["id"]), "spectacle": str(b["spectacle"]), "on": int(b["on"]), "stake": int(b["stake"]),
				"odds": float(b["odds"]), "winner": -1, "won": false, "net": 0, "refunded": true, "house": "", "house_cut": 0})


static func _close(sim: Sim, inst: Dictionary, sp: String, spec: Dictionary, res: Dictionary) -> void:
	var g := _games(inst)
	var w := int(res.get("winner", -1))
	var players: Array = spec["players"]
	var wid := str((players[w] as Dictionary).get("id", "")) if w >= 0 else ""
	(g["results"] as Dictionary)[sp] = {"winner": wid, "ranking": res.get("ranking", []), "how": str(res.get("how", ""))}
	for b: Dictionary in g["bets"]:
		if bool(b.get("settled", false)) or str(b["spectacle"]) != sp:
			continue
		b["settled"] = true
		var stake := int(b["stake"])
		var back := Betting.payout(stake, float(b["odds"])) if int(b["on"]) == w else (stake if w < 0 else 0)
		if back > 0:
			Money.change(sim, str(b["family"]), back, Money.GAMES, "bet_" + str(spec["game"]), "", str(b["actor"]))
		sim.events.append({"type": "game_bet_settled", "actor": str(b["actor"]), "family": str(b["family"]),
			"festival": str(inst["id"]), "spectacle": sp, "match": str(spec["match"]), "on": int(b["on"]), "stake": stake,
			"odds": float(b["odds"]), "winner": w, "won": int(b["on"]) == w, "net": back - stake, "house": "", "house_cut": 0})
	var name := str((players[w] as Dictionary).get("name", "")) if w >= 0 else ""
	if w >= 0 and str((players[w] as Dictionary).get("name_key", "")) != "":
		name = str(players[w]["name_key"])
	sim.events.append({"type": "festival_game_result", "festival": str(inst["id"]), "def": str(inst["def"]), "spectacle": sp,
		"game": str(spec["game"]), "winner": wid, "winner_name": name, "how": str(res.get("how", ""))})
	if OS.is_debug_build():
		print("[FestivalGames] %s: gana %s (%s)" % [str(spec["match"]), wid if wid != "" else "nadie", res.get("how", "")])
