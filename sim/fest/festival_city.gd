class_name FestivalCity
extends RefCounted
## Fiestas · the feast of another city (04f 4.25.6, owner 2026-11-06): a member of the family who is in a city of the
## region on the day of its patron feast or its fair may enter its games and bet on them, from the city's page. The
## games of each feast are data/world/region.json patron_feast.games (and rules.city_games.fair for the fairs), mapped
## to the spectacles of data/games.json by rules.city_games.games (the joust of Sant Jordi, the sortija, the race,
## the pulso of the miners, the bulls); the others of a feast (a procession of boats, a pilgrimage) are not games.
## Entering is playing it there and then (game_play with opts.city_feast = its key, against the spectacle's field);
## betting is watching it (game_bet with the same key: the field without the family, resolved by its match id). Each
## family plays a feast's game once and bets on it once: families[fam].city_feasts keeps the keys (read with a default;
## a key per game and day, pruned to the last city_games.keep).


static func cfg(sim: Sim) -> Dictionary:
	return (Festivals.rules(sim).get("city_games", {}) as Dictionary)


## The key of the game `sp` of feast `feast` of city `city` on `day`.
static func key(city: String, feast: String, day: int, sp: String) -> String:
	return "cityfeast|%s|%s|%d|%s" % [city, feast, day, sp]


## Whether order `o` is a game of a city's feast (game_play or game_bet with opts.city_feast): the traveller gives it
## away from home (Sim lets it through like the region's orders; its own checks say if he is there).
static func is_order(o: Dictionary) -> bool:
	return str(o.get("type", "")) in ["game_play", "game_bet"] and (o.get("opts", {}) as Dictionary).has("city_feast")


## The games of the feasts of the city `actor` is in today: [{city, feast, kind (patron | fair), spectacle, game,
## key}] ([] if he is not in a city of the region, or nothing of its feasts is a game).
static func here(sim: Sim, actor: String) -> Array:
	var out: Array = []
	if not Festivals.enabled(sim):
		return out
	var city := Travel.in_city(sim.state, actor)
	if city == "":
		return out
	var day := Clock.day(int(sim.state.clock["minute"]))
	var map: Dictionary = cfg(sim).get("games", {})
	for f: Dictionary in Festivals.city_feasts(sim, city, day):
		var names: Array = f.get("games", []) if str(f.get("kind", "")) == "patron" else cfg(sim).get("fair", [])
		for n: Variant in names:
			var sp := str(map.get(str(n), ""))
			if sp == "" or not FestivalGames.is_game(sim, sp):
				continue
			out.append({"city": city, "feast": str(f.get("id", "")), "kind": str(f.get("kind", "")), "spectacle": sp,
				"game": str(FestivalGames.spectacle_cfg(sim, sp).get("game", "")), "key": key(city, str(f.get("id", "")), day, sp)})
	return out


## The game of `here` with key `k` for `actor` ({} if it is not one of today's where he is).
static func game_of(sim: Sim, actor: String, k: String) -> Dictionary:
	for g: Dictionary in here(sim, actor):
		if str(g["key"]) == k:
			return g
	return {}


static func _done(st: WorldState, fam: String) -> Array:
	var f: Dictionary = st.families.get(fam, {})
	return f["city_feasts"] if f.get("city_feasts") is Array else []


## "" if `actor` may `what` (play | bet) the city feast game `k` now, else why: not_in_city (not there, or not today, or
## not a game of its feasts), already_played, already_bet.
static func reason(sim: Sim, actor: String, k: String, what: String) -> String:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	if ch.is_empty():
		return "unknown_actor"
	if game_of(sim, actor, k).is_empty():
		return "not_in_city"
	var mark := "%s|%s" % [what, k]
	if mark in _done(sim.state, str(ch.get("family", ""))):
		return "already_played" if what == "play" else "already_bet"
	return ""


## "" if `actor` may play the game `k` now (reason, then what the game asks: a title, the entry fee), else why.
static func play_reason(sim: Sim, actor: String, k: String) -> String:
	var why := reason(sim, actor, k, "play")
	if why != "":
		return why
	var fam := str(sim.state.characters[actor].get("family", ""))
	var c: Dictionary = sim.catalog.games.get(str(game_of(sim, actor, k).get("game", "")), {})
	var req: Dictionary = c.get("requires", {})
	if str(req.get("title", "")) != "" and Titles.rank(sim, Titles.current(sim, fam)) < Titles.rank(sim, str(req["title"])):
		return "no_title"
	if not Money.can_pay(sim.state, fam, int(c.get("entry_fee", 0))):
		return "not_enough_gold"
	return ""


## The game screen's requests for game `k`: to play it (`playing`) or to watch it and bet.
static func request(sim: Sim, actor: String, k: String, playing: bool) -> Dictionary:
	var g := game_of(sim, actor, k)
	if g.is_empty():
		return {}
	var f := field(sim, actor, k, playing)
	var req := {"game": str(g["game"]), "actor": actor, "match": k, "opts": {"city_feast": k}, "stake": 0}
	if playing:
		req["opponents"] = f.slice(1)
	else:
		req.merge({"watch": true, "players": f}, true)
	return req


## The field of the game `k` for the game screen: with the actor first to play it, without him to watch it.
static func field(sim: Sim, actor: String, k: String, playing: bool) -> Array:
	var g := game_of(sim, actor, k)
	if g.is_empty():
		return []
	return FestivalGames.field(sim, str(g["spectacle"]), actor if playing else "")


## Games._apply / Betting heard a city feast game played or bet on: the family's mark (once each), and an event.
static func done(sim: Sim, fam: String, actor: String, k: String, what: String) -> void:
	var f: Dictionary = sim.state.families[fam]
	if not f.get("city_feasts") is Array:
		f["city_feasts"] = []
	var marks: Array = f["city_feasts"]
	marks.append("%s|%s" % [what, k])
	while marks.size() > int(cfg(sim).get("keep", 24)):
		marks.pop_front()
	sim.events.append({"type": "city_feast_game", "actor": actor, "family": fam, "key": k, "what": what})
	if OS.is_debug_build():
		print("[FestivalCity] %s %s en %s" % [actor, "juega" if what == "play" else "apuesta", k])


# --- The feast's contracts on the city's board ((c), owner 2026-11-06) ----------------------------------------------

## At day_started of `day`: the feasts of city `c` today or tomorrow post their contracts on its board
## (rules.city_contracts: per patron feast id, and «fair» for every fair), once per feast and day (the offers carry
## `feast` and `until`, the end of the feast's day); the ones past `until` leave the board. They pay reward_mult
## (more than the city's own) and give reputation_bonus more there when delivered; the board's max_open does not count
## them. Nothing random: the rows are data.
static func post_contracts(sim: Sim, c: String, day: int) -> void:
	if not Festivals.enabled(sim) or c == Region.home(sim):
		return
	var cc: Dictionary = (Festivals.rules(sim).get("city_contracts", {}) as Dictionary)
	var board: Array = Region.city(sim, c)["board"]
	var now := int(sim.state.clock["minute"])
	for i: int in range(board.size() - 1, -1, -1):
		var off: Dictionary = board[i]
		if off.has("until") and int(off["until"]) <= now:
			board.remove_at(i)
	for d: int in [day, day + 1]:
		for f: Dictionary in Festivals.city_feasts(sim, c, d):
			var fid := str(f.get("id", ""))
			var rows: Array = (cc.get("patron", {}) as Dictionary).get(fid, []) if str(f.get("kind", "")) == "patron" \
				else cc.get("fair", [])
			var tag := "%s|%s|%d" % [c, fid, d]
			if rows.is_empty() or board.any(func(o: Dictionary) -> bool: return str(o.get("feast_key", "")) == tag):
				continue
			var until := (d + 1) * Clock.MINUTES_PER_DAY
			for row: Dictionary in rows:
				var item := str(row.get("item", ""))
				var qty := int(row.get("qty", 1))
				var reward := roundi(float(sim.catalog.item(item).get("base_price", 0)) * qty * float(cc.get("reward_mult", 2.0)))
				board.append({"id": Ids.next(sim.state, "rct"), "item": item, "qty": qty, "reward": reward,
					"days": d - day + 1, "feast": fid, "feast_kind": str(f.get("kind", "")), "feast_key": tag, "until": until,
					"reputation_bonus": int(cc.get("reputation_bonus", 3))})
				if OS.is_debug_build():
					print("[FestivalCity] %s publica por su fiesta %s: %s x%d por %d" % [c, fid, item, qty, reward])
