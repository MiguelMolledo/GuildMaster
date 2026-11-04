class_name BotGambler
extends RefCounted
## Bot that gambles (docs/gdd/04f_vida_y_fiestas.md §4.28.4, §4.26.6-8; docs/contratos/juegos.md): with the head of its
## family, every half hour from 09:00 to 22:00 it plays, in turn, «azar», «a la mayor» (with two regulars) and the
## envite against steady regulars (temper even: the same policy as «Resolver sin jugar», so neither side has an edge)
## in the gambling house of the scenario (state.meta.games_house: its rake), and bets on a pulso of two regulars at the
## bookmaker's odds. The same orders the UI gives (game_play with auto: true, game_bet). It keeps the stakes it put
## and the house's expected take of its bets, so the runner can check it loses what the house's margin says: neither
## more (the games are fair) nor less (the house is not cheated). Scenario: games_gambler.

const ID: String = "gambler"
const STAKE: int = 10
const MIN_GOLD: int = 200        # it stops when it has less (it never goes broke on purpose)

var _n: int = 0
var staked_games: int = 0
var staked_bets: int = 0
var expected_take: float = 0.0   # Σ stake × (1 − chance × odds) of its bets: the bookmaker's margin, ex ante
var skipped: int = 0


func orders(sim: Sim) -> Array:
	var st := sim.state
	var minute := int(st.clock["minute"])
	var hm := minute % Clock.MINUTES_PER_DAY
	if minute % 30 != 0 or hm < 9 * 60 or hm > 22 * 60:
		return []
	var fam := ""
	for f: String in st.families:
		if str(st.families[f].get("controlled_by", "")) == "human":
			fam = f
			break
	if fam == "":
		return []
	var me := Kin.head(st, fam)
	if me == "" or not Kin.alive(st, me):
		return []
	if Money.gold(st, fam) < MIN_GOLD:
		skipped += 1
		return []
	var house := str(st.meta.get("games_house", ""))
	var opts := {"house": house} if house != "" else {}
	var k := _n % 4
	_n += 1
	match k:
		0:
			staked_games += STAKE
			return [{"type": "game_play", "actor": me, "game": "azar", "opponents": ["preset:regular_even"],
				"stake": STAKE, "opts": opts, "auto": true}]
		1:
			staked_games += STAKE
			return [{"type": "game_play", "actor": me, "game": "mayor",
				"opponents": ["preset:regular_even", "preset:regular_even#2"], "stake": STAKE, "opts": opts, "auto": true}]
		2:
			staked_games += STAKE
			return [{"type": "game_play", "actor": me, "game": "envite", "opponents": ["preset:regular_even"],
				"stake": STAKE, "opts": opts, "auto": true}]
	var players := ["preset:regular_even", "preset:regular_even#2"]
	var mid := "gambler|pulso|%d" % _n
	var on := (_n / 4) % 2
	var spec := {"game": "pulso", "match": mid, "seed": maxi(st.world_seed, 1), "player": -1, "stake": 0, "opts": opts,
		"players": [Games.preset_player(sim.catalog.games, players[0]), Games.preset_player(sim.catalog.games, players[1])]}
	var mk := Betting.market(sim.catalog.games, spec)
	var chance := float((mk[on] as Dictionary)["chance"])
	var odds := float((mk[on] as Dictionary)["odds"])
	expected_take += STAKE * (1.0 - chance * odds)
	staked_bets += STAKE
	return [{"type": "game_bet", "actor": me, "game": "pulso", "players": players, "match": mid, "on": on,
		"stake": STAKE, "opts": opts}]


## What the runner checks (data/targets.json gambler): gambler_return = what it won or lost per gold staked;
## gambler_luck = the same plus what the house took (the rake it paid and the bookmaker's margin of its bets): about 0
## when the games and the odds are fair.
func measures(sim: Sim) -> Dictionary:
	var st := sim.state
	var fam := ""
	for f: String in st.families:
		if str(st.families[f].get("controlled_by", "")) == "human":
			fam = f
	var house_fam := Money.family_of(st, str(st.meta.get("games_house", "")))
	var net_games := 0
	var net_bets := 0
	var rake := 0
	for e: Dictionary in st.ledger.get("entries", []):
		if str(e.get("category", "")) != Money.GAMES:
			continue
		var ref := str(e.get("ref", ""))
		if str(e.get("family", "")) == fam:
			if ref.begins_with("bet_"):
				net_bets += int(e["amount"])
			else:
				net_games += int(e["amount"])
		elif str(e.get("family", "")) == house_fam and ref.begins_with("house_") and not ref.begins_with("house_bet_"):
			rake += int(e["amount"])
	var staked := maxi(1, staked_games + staked_bets)
	return {"gambler_games": staked_games / STAKE, "gambler_bets": staked_bets / STAKE, "gambler_skipped": skipped,
		"gambler_net_games": net_games, "gambler_net_bets": net_bets, "gambler_rake": rake,
		"gambler_return": snappedf(float(net_games + net_bets) / staked, 0.001),
		"gambler_bet_return": snappedf(float(net_bets) / maxi(1, staked_bets), 0.001),
		"gambler_luck": snappedf(float(net_games + net_bets + rake + expected_take) / staked, 0.001)}
