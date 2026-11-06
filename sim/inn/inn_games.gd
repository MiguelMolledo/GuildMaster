class_name InnGames
extends RefCounted
## The gaming table of the Taberna-Posada (docs/gdd/04f_vida_y_fiestas.md §4.27.4 and §4.27.5; contract of the games:
## docs/contratos/juegos.md §5). Rules only: the screen is the games' (App.open_game → GameScreen, one order game_play).
##
## · The table (upgrade inn_gaming_table) during the open turn: whoever of the family plays dice (azar, mayor) or cards
##   (envite) with the regulars: the neighbours sitting in the room (characters of the town) first, the regulars of
##   data/games.json (regular_*) for the rest. request() builds the game's request with opts.house = the tavern: the
##   games keep the house's rake of a net win and give it to the tavern's owner (game_played.house_cut; nothing when
##   the player plays in his own house).
## · The traveller's game (incident game_offer): a stranger of data/inn/inn.json games.offer.presets proposes a game
##   (keyed: who, which, how much). It stays open until the turn closes (night.offer); offer_request() plays it.
## · The licence: without it, a game in the tavern is a light offence if the constable's men see it (hear(): every
##   game_played whose house is a tavern; keyed chance games.illegal.seen, more with the constable's office held):
##   a fact illegal_gaming (charge minor_fraud, H11's court) against the family that played, and reputation.
## Nothing new in the save: night.offer and stats.games are fields of the night with their default ({} and []).

const GAMES: Array[String] = ["azar", "mayor", "envite"]


static func cfg(sim: Sim) -> Dictionary:
	return Inn.rules(sim).get("games", {})


## The table exists in `bld` (the upgrade).
static func has_table(sim: Sim, bld: String) -> bool:
	return Upgrades.flag(sim, bld, "inn_gaming_table")


## Whether a game can be sat now: "" or the reason (no_table, closed).
static func blocked(sim: Sim, bld: String) -> String:
	if not sim.state.buildings.has(bld) or str(sim.state.buildings[bld].get("type", "")) != "tavern_inn":
		return "not_inn"
	if not has_table(sim, bld):
		return "no_table"
	if not Inn.is_open(sim, bld):
		return "closed"
	return ""


## Who of `fam` sits at the table: the one the player moves inside the tavern, else any of the family inside, else the
## family's head ("" if none).
static func player_for(sim: Sim, bld: String, fam: String) -> String:
	var st := sim.state
	var ids: Array = st.characters.keys()
	ids.sort()
	var inside := ""
	for id: Variant in ids:
		var ch: Dictionary = st.characters[id]
		if str(ch.get("family", "")) != fam or not bool(ch.get("alive", true)) or str(ch.get("location", "")) != bld:
			continue
		if str(ch.get("controlled_by", "")) == "human":
			return str(id)
		if inside == "":
			inside = str(id)
	if inside != "":
		return inside
	return str(st.families.get(fam, {}).get("head", ""))


## The regulars for a game of `game` against `actor`: the neighbours in the room (not of the actor's family), then the
## regular presets in order; as many as the game wants (azar and envite one, mayor two).
static func regulars(sim: Sim, bld: String, actor: String, game: String) -> Array:
	var st := sim.state
	var want := 2 if game == "mayor" else 1
	var fam := str(st.characters.get(actor, {}).get("family", ""))
	var out: Array = []
	for g: Dictionary in Inn.guests(sim, bld):
		var chr := str(g.get("chr", ""))
		if chr == "" or chr == actor or not st.characters.has(chr) or out.has(chr):
			continue
		if str(st.characters[chr].get("family", "")) == fam or not str(g.get("state", "")) in ["seated", "waiting", "eating"]:
			continue
		out.append(chr)
		if out.size() >= want:
			return out
	var presets: Array = cfg(sim).get("regulars", ["regular_even", "regular_prudent", "regular_boastful"])
	var day := Clock.day(int(st.clock["minute"]))
	var start := Kin.randi_range(st, "inn|regulars|%s|%d" % [bld, day], 0, maxi(0, presets.size() - 1))
	for i: int in presets.size():
		if out.size() >= want:
			break
		out.append("preset:" + str(presets[(start + i) % presets.size()]))
	return out


## The request of a game at the table for GameScreen.open / the order game_play ({"reason": ...} if it cannot be).
static func request(sim: Sim, bld: String, actor: String, game: String, stake: int) -> Dictionary:
	var why := blocked(sim, bld)
	if why != "":
		return {"reason": why}
	if not game in GAMES:
		return {"reason": "unknown_game"}
	return {"actor": actor, "game": game, "opponents": regulars(sim, bld, actor, game), "stake": stake,
		"opts": {"house": bld}}


# --- The traveller's game -------------------------------------------------------------------------------------------

## The incident game_offer: a stranger (keyed) proposes a game; it stays in night.offer until the turn closes.
static func make_offer(sim: Sim, bld: String, inn: Dictionary) -> Dictionary:
	var st := sim.state
	var night: Dictionary = inn["night"]
	var day := int(night["day"])
	var oc: Dictionary = cfg(sim).get("offer", {})
	var presets: Array = oc.get("presets", ["regular_cheat"])
	var games: Array = oc.get("games", GAMES)
	var stakes: Array = oc.get("stakes", [10, 25])
	var key := "inn|offer_who|%s|%d" % [bld, day]
	var offer := {"preset": str(presets[Kin.randi_range(st, key, 0, presets.size() - 1)]),
		"game": str(games[Kin.randi_range(st, key + "|game", 0, games.size() - 1)]),
		"stake": int(stakes[Kin.randi_range(st, key + "|stake", 0, stakes.size() - 1)]),
		"minute": int(st.clock["minute"]), "status": "open"}
	if str(offer["game"]) == "mayor":
		offer["game"] = "azar"  # a stranger's proposal is a game of two
	night["offer"] = offer
	return offer


## The open offer of tonight in `bld` ({} if none, or played).
static func offer_of(sim: Sim, bld: String) -> Dictionary:
	var night: Dictionary = Inn.state_of(sim, bld).get("night", {})
	var o: Dictionary = night.get("offer", {})
	if o.is_empty() or str(o.get("status", "")) != "open" or not Inn.is_open(sim, bld):
		return {}
	return o


## The request to play tonight's offer ({"reason": ...} if there is none).
static func offer_request(sim: Sim, bld: String, actor: String) -> Dictionary:
	var o := offer_of(sim, bld)
	if o.is_empty():
		return {"reason": "no_offer"}
	return {"actor": actor, "game": str(o["game"]), "opponents": ["preset:" + str(o["preset"])], "stake": int(o["stake"]),
		"opts": {"house": bld}}


# --- Hearing the games played in a tavern ---------------------------------------------------------------------------

## Every game_played of the step whose house is a tavern: written in tonight's summary (stats.games), the offer taken
## when its stranger played, and the licence's check (without it: the light offence, if seen).
static func hear(sim: Sim) -> void:
	var st := sim.state
	for e: Dictionary in sim.events.duplicate():
		if str(e.get("type", "")) != "game_played":
			continue
		var bld := str(e.get("house", ""))
		if bld == "" or not st.buildings.has(bld) or str(st.buildings[bld].get("type", "")) != "tavern_inn":
			continue
		var seen := false
		if not Inn.licensed(sim, bld):
			seen = _offence(sim, bld, e)
		var inn := Inn.ensure(sim, bld)
		var night: Dictionary = inn.get("night", {})
		if night.is_empty():
			continue
		var stats: Dictionary = night["stats"]
		if not stats.get("games") is Array:
			stats["games"] = []
		(stats["games"] as Array).append({"game": str(e["game"]), "actor": str(e["actor"]), "won": bool(e["won"]),
			"net": int(e["net"]), "house_cut": int(e.get("house_cut", 0)), "seen": seen})
		var o: Dictionary = night.get("offer", {})
		if not o.is_empty() and str(o.get("status", "")) == "open" \
				and (e.get("opponents", []) as Array).has("preset:" + str(o["preset"])):
			o["status"] = "played"
			o["won"] = bool(e["won"])
		if OS.is_debug_build():
			print("[InnGames] %s: partida %s de %s en la mesa, %s, oro %+d, casa %d, sin licencia vista=%s" % [bld,
				e["game"], e["actor"], "gana" if bool(e["won"]) else "pierde", int(e["net"]), int(e.get("house_cut", 0)), seen])


## A game in an unlicensed tavern: seen by the constable's men (keyed by the match) → fact illegal_gaming against the
## family that played, reputation and a notice. Returns whether it was seen.
static func _offence(sim: Sim, bld: String, e: Dictionary) -> bool:
	var st := sim.state
	var ic: Dictionary = cfg(sim).get("illegal", {})
	var chance := float(ic.get("seen", 0.3))
	if Watch._constable(sim):
		chance = float(ic.get("seen_constable", 0.5))
	if Kin.roll(st, "inn|illegal|%s|%s" % [bld, str(e.get("match", ""))]) >= chance:
		return false
	var fam := str(e.get("family", ""))
	var actor := str(e.get("actor", ""))
	var fact := Tribunal.add_fact(sim, "illegal_gaming", fam, actor)
	Reputation.change(sim, fam, int(ic.get("reputation", -3)), "inn_illegal_gaming")
	Notices.add(sim, fam, Notices.WARNING, "notice.inn.illegal_gaming", {"building": bld}, bld)
	if not Inn.state_of(sim, bld).get("night", {}).is_empty():
		Inn._incident(sim, bld, "illegal_game", {"fact": fact})
	sim.events.append({"type": "inn_illegal_gaming", "building": bld, "family": fam, "actor": actor, "fact": fact})
	if OS.is_debug_build():
		print("[InnGames] %s: juego sin licencia visto (prob %.2f): hecho %s contra %s" % [bld, chance, fact, fam])
	return true
