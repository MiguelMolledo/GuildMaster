class_name GameScreen
extends Control
## The screen of a game or competition (docs/ui/mecanicas/juegos.md; rules: docs/gdd/04f_vida_y_fiestas.md §4.26,
## sim/games/). One screen for every game, the same frame as the duel's (theme, PortraitFrame, PageCard for the result):
## the game's board in the middle (GameBoard: BoardDice, BoardPulso...), the portraits of who plays, the decision box
## (what one knows: the odds, the rival's gesture and how reliable it is), the actions of the open decision (keys 1-4),
## «Resolver sin jugar» (A) and the last lines of the log.
##
## The game is played here with its own GameMatch (the same keys as the sim's: world seed and match id); when it ends
## (or «Resolver sin jugar», or Esc: a game is not left half played) the screen gives ONE order, game_play, with the
## moves played, through `give` (Game.step_now): the sim replays the game and applies the gold and the reputation, and
## the result card shows what it applied. Nothing is saved. open(spec): {actor, game, opponents [refs], stake, opts,
## match (optional)}: what the fiestas, the tavern and --games-test pass.

signal closed
signal step_shown           # an animation ended (the smoke script takes its capture)
signal finished(result: Dictionary)

const KEYS: Array = [KEY_1, KEY_2, KEY_3, KEY_4]
const BOARDS: Dictionary = {"azar": "res://game/ui/games/board_dice.gd", "mayor": "res://game/ui/games/board_dice.gd",
	"pulso": "res://game/ui/games/board_pulso.gd", "envite": "res://game/ui/games/board_naipes.gd",
	"tourney": "res://game/ui/games/board_tourney.gd", "joust": "res://game/ui/games/board_joust.gd",
	"sortija": "res://game/ui/games/board_sortija.gd", "race": "res://game/ui/games/board_race.gd",
	"bulls": "res://game/ui/games/board_bulls.gd", "rescue": "res://game/ui/games/board_fight.gd",
	"brawl": "res://game/ui/games/board_fight.gd"}

var m: GameMatch = null
var spec: Dictionary = {}
var request: Dictionary = {}
var cfg: Dictionary = {}
var busy: bool = false
var applied: Dictionary = {}       # the game_played event of the order (or {} without a game)
var _state: WorldState = null
var _give: Callable = Callable()
var _board: GameBoard = null
var _names: Array = []
var _log_lines: Array[String] = []
var _pending_lines: Array[String] = []  # the log lines of what is being animated (shown when it ends)
var _bound: bool = false
var _sent: bool = false
var watch: bool = false            # the player watches a game of others (and may bet on it): req.watch
var betting: bool = false          # the bookmaker's step before the game (req.bets_open, always when watching)
var bets: Array = []               # [{on, stake}] placed
var bet_event: Dictionary = {}     # game_bet_settled of a bet on a game of others
var _market: Dictionary = {}
var _bet_stake: int = 10
var _bet_on: int = 0
var bet_only: bool = false           # a bet on a fight of the town (a brawl): placed now, paid when it is fought


func _ready() -> void:
	visible = false
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(get_node("%Auto") as Button).pressed.connect(_auto)
	MenuKit.add_hint(get_node("%Auto") as Button, "A")
	(get_node("%Result") as PageCard).button_pressed.connect(_on_result_button)


## Opens the game `req` {actor, game, opponents, stake, opts, match} of `state`; `give` applies an order now and returns
## its step's events (Game.step_now); without it the game is played on its own and nothing is applied.
func open(req: Dictionary, state: WorldState, games: Dictionary, give: Callable = Callable()) -> bool:
	_bind()
	request = req.duplicate(true)
	_state = state
	_give = give
	cfg = games
	_sent = false
	applied = {}
	var actor := str(req.get("actor", ""))
	var g := str(req.get("game", ""))
	watch = bool(req.get("watch", false))
	betting = bool(req.get("bets_open", watch))
	bets = []
	_bet_on = 0
	bet_event = {}
	bet_only = false
	var players: Array = []
	var mid := str(req.get("match", ""))
	if g in ["rescue", "brawl"]:
		# vida's fights (docs/contratos/juegos.md §5): their spec comes from the incident
		var sim: Sim = Game.sim
		var inc := Incidents.find(state, str(req.get("incident", "")))
		if sim == null or inc.is_empty():
			push_error("GameScreen: unknown incident %s" % req.get("incident", ""))
			return false
		if g == "rescue":
			var pv := Rescue.preview(sim, inc, actor, int(req.get("helpers", 2)))
			spec = {"game": "rescue", "match": str(pv["key"]), "seed": int(pv["seed"]), "players": pv["players"], "player": 0,
				"stake": 0, "opts": {"team_a": int(pv["team_a"])}}
			request["order"] = {"type": "resolve_incident", "actor": actor, "incident": str(inc["id"]), "choice": "rescue",
				"helpers": int(req.get("helpers", 2))}
		else:
			spec = Betting.brawl_spec(sim, inc)
			watch = true
			betting = true
			bet_only = true
		players = spec["players"]
		mid = str(spec["match"])
	else:
		players = [] if watch else [Games.player_of(state, actor)]
		for ref: Variant in req.get("players" if watch else "opponents", []):
			var p := Games.player_ref(state, games, str(ref))
			if p.is_empty():
				push_error("GameScreen: unknown player %s" % ref)
				return false
			players.append(p)
		if mid == "":
			mid = Games.match_id(state, g, actor) if not watch else "%s|watch|%s|%d" % [g, actor, int(state.clock.get("minute", 0))]
			request["match"] = mid
		spec = {"game": g, "match": mid, "seed": maxi(state.world_seed, 1), "players": players, "player": -1 if watch else 0,
			"stake": int(req.get("stake", 0)), "opts": (req.get("opts", {}) as Dictionary).duplicate(true)}
	if betting:
		var ms := spec.duplicate(true)
		ms["player"] = -1
		_market = Betting.market(games, ms)
	m = Games.create(games, spec)
	if m == null:
		push_error("GameScreen: unknown game %s" % g)
		return false
	_names.clear()
	for p: Dictionary in players:
		_names.append(_name_of(p))
	_setup_board(g)
	_setup_portraits(players)
	_log_lines.clear()
	_pending_lines.clear()
	(get_node("%Result") as PageCard).visible = false
	visible = true
	UiAnim.panel_in(get_node("%Frame") as Control)
	if OS.is_debug_build():
		print("[GameScreen] abre %s (%s): %s, apuesta %d, partida %s%s" % [g, ", ".join(_names), actor, int(spec["stake"]), mid,
			" (mira y apuesta)" if watch else (" (con apuestas)" if betting else "")])
	if betting:
		_board.show_view(m, m.view(0), _names)
		_refresh()
		return true
	_play_new()
	return true


## The bookmaker's step: the odds of each side and a bet (or none); then the game starts (or is watched). The row
## stays short whatever the number of players: «On: <name>» goes through them, «Bet: n» through the stakes.
func _refresh_betting() -> void:
	(get_node("%InfoTitle") as Label).text = tr("games.bets.title")
	var lines: Array[String] = []
	for side: Variant in _market:
		var mk: Dictionary = _market[side]
		var line := tr("games.bets.short") % [str(_names[int(side)]), roundi(float(mk["chance"]) * 100.0), float(mk["odds"])]
		lines.append(("▶ " if int(side) == _bet_on else "") + line)
	(get_node("%InfoText") as Label).text = "  ·  ".join(lines)
	(get_node("%InfoRead") as Label).text = tr("games.bets.margin") % roundi(float((cfg.get("bets", {}) as Dictionary).get("margin", 0.1)) * 100.0)
	var acts := get_node("%Actions") as HBoxContainer
	var fam := str(_state.characters.get(str(request.get("actor", "")), {}).get("family", ""))
	var reserve := Games.max_loss(str(spec["game"]), int(spec["stake"]), int(cfg.get("cap", 50))) if not watch and int(spec["stake"]) > 0 else 0
	var i := 0
	for id: String in ["on", "stake", "bet", "no_bet"]:
		var b := Button.new()
		match id:
			"on":
				b.text = tr("games.bets.on") % _short_name(str(_names[_bet_on]))
			"stake":
				b.text = tr("games.bets.stake") % _bet_stake
			"bet":
				var mk2: Dictionary = _market.get(_bet_on, {})
				b.text = tr("games.bets.place") % float(mk2.get("odds", 0.0))
				b.disabled = not Money.can_pay(_state, fam, _bet_stake + reserve)
				if b.disabled:
					b.tooltip_text = tr("ui.why.bet_gold") % [_bet_stake + reserve, Money.gold(_state, fam)]
			_:
				b.text = tr("games.bets.none")
		b.custom_minimum_size = Vector2(96, 28)
		b.theme_type_variation = &"PrimaryButton" if id == "bet" else &"BodyButton"
		b.set_meta("action", id)
		b.pressed.connect(_choose.bind(id))
		MenuKit.add_hint(b, str(i + 1))
		acts.add_child(b)
		acts.move_child(b, i)
		i += 1


## A bet on a brawl of the town: game_bet with its incident; the card says it is paid when they fight.
func _bet_brawl() -> void:
	var refused := ""
	var placed := {}
	if not bets.is_empty() and _give.is_valid():
		var b: Dictionary = bets[0]
		var o := {"type": "game_bet", "actor": str(request.get("actor", "")), "incident": str(request.get("incident", "")),
			"on": int(b["on"]), "stake": int(b["stake"])}
		for e: Dictionary in _give.call(o):
			if str(e.get("type", "")) == "order_refused" and str(e.get("order", "")) == "game_bet":
				refused = str(e.get("reason", ""))
			elif str(e.get("type", "")) == "game_bet_placed":
				placed = e
	_sent = true
	var effects: Array = []
	if not placed.is_empty():
		effects.append({"text": tr("games.brawl.placed") % [int(placed["stake"]), str(_names[int(placed["on"])]), float(placed["odds"])],
			"sign": ""})
	elif refused != "":
		effects.append({"text": tr("games.result.refused") % tr("reason.%s" % refused), "sign": "-"})
	else:
		effects.append({"text": tr("games.bets.none"), "sign": ""})
	(get_node("%Result") as PageCard).show_page({"template": "card", "title": tr("games.brawl.title"), "sticky": true,
		"blocks": [{"type": "paragraph", "text": tr("games.brawl.text")}, {"type": "effects", "items": effects}],
		"buttons": [{"id": "close", "text": tr("games.ui.close"), "primary": true}]})


func _short_name(n: String) -> String:
	return n if n.length() <= 18 else n.substr(0, 17) + "…"


func _bet_action(id: String) -> void:
	if id == "stake":
		var st: Array = cfg.get("stakes", [5, 10, 25, 50])
		_bet_stake = int(st[(st.find(_bet_stake) + 1) % st.size()])
		_refresh()
		return
	if id == "on":
		_bet_on = (_bet_on + 1) % maxi(1, _market.size())
		_refresh()
		return
	if id.begins_with("bet_"):  # «bet_<side>»: the bots and the smoke bet on a side directly
		_bet_on = id.substr(4).to_int()
		id = "bet"
	if id == "bet":
		bets.append({"on": _bet_on, "stake": _bet_stake})
	betting = false
	if OS.is_debug_build():
		print("[GameScreen] apuestas: %s" % [bets])
	if bet_only:
		_bet_brawl()
		return
	if watch and not bets.is_empty() and _give.is_valid():
		var b: Dictionary = bets[0]
		var o := {"type": "game_bet", "actor": str(request.get("actor", "")), "game": str(spec["game"]),
			"players": (request.get("players", []) as Array).duplicate(), "match": str(spec["match"]),
			"opts": (spec["opts"] as Dictionary).duplicate(true), "on": int(b["on"]), "stake": int(b["stake"]),
			"game_stake": int(spec["stake"])}
		for e: Dictionary in _give.call(o):
			if str(e.get("type", "")) == "game_bet_settled":
				bet_event = e
	_play_new()



func _name_of(p: Dictionary) -> String:
	if str(p.get("name_key", "")) != "":
		return tr(str(p["name_key"]))
	return str(p.get("name", "?"))


func _setup_board(g: String) -> void:
	var holder := get_node("%BoardHolder") as Control
	for c: Node in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	_board = (load(str(BOARDS.get(g, BOARDS["azar"]))) as GDScript).new() as GameBoard
	_board.name = "Board"
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_board)
	_board.reset()
	_board.shown.connect(_on_shown)


func _setup_portraits(players: Array) -> void:
	var left := get_node("%LeftPortrait") as PortraitFrame
	var right := get_node("%RightPortrait") as PortraitFrame
	_portrait(left, players[0], true)
	_portrait(right, players[1], false)
	right.set_meta("side", 1)
	(get_node("%LeftName") as Label).text = str(_names[0])
	(get_node("%RightName") as Label).text = str(_names[1])
	(get_node("%LeftInfo") as Label).text = _traits(players[0])
	(get_node("%RightInfo") as Label).text = _traits(players[1])
	var others := get_node("%Others") as VBoxContainer
	for c: Node in others.get_children():
		others.remove_child(c)
		c.queue_free()
	for i: int in range(2, players.size() if players.size() <= 4 else 2):  # a field of many: the board names them
		var row := HBoxContainer.new()
		var pf := (load("res://game/ui/portrait_frame.tscn") as PackedScene).instantiate() as PortraitFrame
		pf.custom_minimum_size = Vector2(38, 38)
		row.add_child(pf)
		_portrait(pf, players[i], false)
		var l := Label.new()
		l.text = str(_names[i])
		l.theme_type_variation = &"CaptionLabel"
		row.add_child(l)
		others.add_child(row)


func _portrait(pf: PortraitFrame, p: Dictionary, gold: bool) -> void:
	if _state.characters.has(str(p.get("id", ""))):
		pf.show_character(_state, str(p["id"]), {"gold": gold})
	else:
		var look := int(p.get("look", 0))
		pf.show_identity({"hair": Identity.hair_color(look % 5), "skin": Identity.skin_color(look % 3),
			"primary": Color("#6b4a2e"), "secondary": Color("#a08060"), "female": bool(p.get("female", false)),
			"portrait": {"id": "", "type": "commoner", "stage": "adult", "seed": look}}, {"gold": gold})
		pf.tooltip_text = _name_of(p)


## The stats that count in this game and the temper of a regular (what the screen tells of each player).
func _traits(p: Dictionary) -> String:
	var parts: Array[String] = []
	var stats: Array = []
	match str(spec["game"]):
		"pulso":
			stats = ["constitution", "empathy"]
		"envite":
			stats = ["empathy", "rhetoric"]
		"tourney", "rescue", "brawl":
			stats = ["martial", "empathy"]
		"joust":
			stats = ["dexterity", "empathy", "martial"]
		"sortija", "race", "bulls":
			stats = ["dexterity"]
	for s: String in stats:
		parts.append("%s %d" % [tr("stat.%s" % s), GameRules.stat(p, s)])
	if str(p.get("preset", "")) != "":
		parts.append(tr("games.temper.%s" % str(p.get("temper", "even"))))
	return " · ".join(parts)


## Animates what the match did since the last time, then refreshes.
func _play_new(fast: bool = false) -> void:
	_board.show_view(m, m.view(0), _names)
	var entries := _board.new_entries(m)
	for e: Dictionary in entries:
		var line := _board.log_line(e)
		if line != "":
			_pending_lines.append(line)
	busy = true
	_board.play(entries, fast)   # without entries (or fast) it ends at once: _on_shown refreshes
	if _board.playing:
		_refresh()


func _on_shown() -> void:
	busy = false
	_log_lines.append_array(_pending_lines)
	_pending_lines.clear()
	_refresh()
	step_shown.emit()
	if m.over() and not _sent:
		_finish()


func _refresh() -> void:
	if m == null:
		return
	var v := m.view(0)
	var g := str(spec["game"])
	(get_node("%Header") as Label).text = tr("games.%s.name" % g)
	var sub := tr("games.ui.sub_stake") % int(spec["stake"]) if int(spec["stake"]) > 0 else tr("games.ui.sub_free")
	if str((spec["opts"] as Dictionary).get("house", "")) != "":
		sub += " · " + tr("games.ui.in_house") % roundi(m.rake() * 100.0)
	(get_node("%Sub") as Label).text = sub
	_board.show_view(m, v, _names)
	_follow_rival(v)
	var acts := get_node("%Actions") as HBoxContainer
	for c: Node in acts.get_children():
		if c.has_meta("action"):
			acts.remove_child(c)  # at once: a button waiting to be freed would still widen the row (and the frame)
			c.queue_free()
	(get_node("%Auto") as Button).visible = not watch
	if betting:
		(get_node("%Auto") as Button).disabled = true
		_refresh_betting()
		return
	var inf := _board.info_busy() if busy and _board.playing else _board.info(v)
	if watch and not busy and not m.over():
		inf = {"title": tr("games.ui.watching"), "text": "", "read": ""}
	(get_node("%InfoTitle") as Label).text = str(inf.get("title", ""))
	(get_node("%InfoText") as Label).text = str(inf.get("text", ""))
	(get_node("%InfoRead") as Label).text = str(inf.get("read", ""))
	var i := 0
	for a: Dictionary in v.get("actions", []):
		var b := Button.new()
		var id := str(a["id"])
		var c := int(a.get("cost", 0))
		b.text = tr("games.%s.action.%s" % [g, id]) + (("  +%d" % -c) if c < 0 else (("  −%d" % c) if c > 0 else ""))
		b.custom_minimum_size = Vector2(110, 28)
		b.theme_type_variation = &"PrimaryButton"
		b.disabled = busy or not bool(a.get("enabled", true))
		b.tooltip_text = tr(str(a["why"])) if str(a.get("why", "")) != "" else tr("games.%s.action.%s.hint" % [g, id])
		b.set_meta("action", id)
		b.pressed.connect(_choose.bind(id))
		MenuKit.add_hint(b, str(i + 1))
		acts.add_child(b)
		acts.move_child(b, i)
		i += 1
	(get_node("%Auto") as Button).disabled = busy or m.over()
	(get_node("%Auto") as Button).tooltip_text = (tr("ui.why.over") if m.over() else tr("ui.why.busy_lance")) \
		if (get_node("%Auto") as Button).disabled else ""
	var lines := _log_lines.slice(maxi(0, _log_lines.size() - 3))
	(get_node("%Log") as Label).text = "\n".join(lines)
	var miss := _board.missing
	(get_node("%ArtNote") as Label).text = tr("games.ui.art_provisional") % ", ".join(miss) if not miss.is_empty() else ""


## In a field of many (the tournament), the right portrait is the rival of the bout being fought.
func _follow_rival(v: Dictionary) -> void:
	var cs: Array = v.get("bout_sides", [])
	if cs.size() != 2 or not 0 in cs:
		return
	var rival := int(cs[1]) if int(cs[0]) == 0 else int(cs[0])
	var right := get_node("%RightPortrait") as PortraitFrame
	if right.get_meta("side", -1) == rival:
		return
	right.set_meta("side", rival)
	_portrait(right, (spec["players"] as Array)[rival], false)
	(get_node("%RightName") as Label).text = str(_names[rival])
	(get_node("%RightInfo") as Label).text = _traits((spec["players"] as Array)[rival])


func _choose(action: String) -> void:
	if betting:
		_bet_action(action)
		return
	if busy or m == null or m.over():
		return
	var r := m.choose(0, action)
	if OS.is_debug_build():
		print("[GameScreen] elige %s -> %s" % [action, "ok" if bool(r["ok"]) else str(r["reason"])])
	if not bool(r["ok"]):
		return
	_play_new()


func _auto() -> void:
	if betting:
		_bet_action("no_bet")
		return
	if busy or m == null or m.over() or watch:
		return
	m.auto_finish()
	_play_new(true)


## The game is over: the order to the sim, then the result card.
func _finish() -> void:
	_sent = true
	if watch:
		_show_result("")
		return
	if request.get("order") is Dictionary:  # the rescue: vida's own order with the moves played
		_finish_order()
		return
	var o := {"type": "game_play", "actor": str(request.get("actor", "")), "game": str(spec["game"]),
		"opponents": (request.get("opponents", []) as Array).duplicate(), "stake": int(spec["stake"]),
		"opts": (spec["opts"] as Dictionary).duplicate(true), "moves": (m.moves() as Array).duplicate(), "auto": true,
		"match": str(spec["match"]), "bets": bets.duplicate(true)}
	var refused := ""
	if _give.is_valid():
		var events: Array = _give.call(o)
		for e: Dictionary in events:
			var t := str(e.get("type", ""))
			if t == "order_refused" and str(e.get("order", "")) == "game_play":
				refused = str(e.get("reason", ""))
			elif t == "game_played" and str(e.get("match", "")) == str(spec["match"]):
				applied = e
	if OS.is_debug_build():
		print("[GameScreen] fin %s: gana %d, oro %s, orden %s" % [spec["match"], int(m.result()["winner"]),
			applied.get("net", "-"), "rechazada: " + refused if refused != "" else "aplicada"])
	_show_result(refused)


func _finish_order() -> void:
	var o: Dictionary = (request["order"] as Dictionary).duplicate(true)
	o["moves"] = (m.moves() as Array).duplicate()
	o["auto"] = true
	var refused := ""
	if _give.is_valid():
		for e: Dictionary in _give.call(o):
			var t := str(e.get("type", ""))
			if t == "order_refused" and str(e.get("order", "")) == str(o["type"]):
				refused = str(e.get("reason", ""))
			elif t == "incident_rescue":
				applied = e
	if OS.is_debug_build():
		print("[GameScreen] rescate %s: %s" % [o.get("incident", ""), applied if refused == "" else "rechazado: " + refused])
	var won := bool(applied.get("won", m.won() if m is RescueMatch else false))
	var effects: Array = [{"text": tr("games.rescue.result.%s" % ("won" if won else "lost")), "sign": "+" if won else "-"}]
	if refused != "":
		effects = [{"text": tr("games.result.refused") % tr("reason.%s" % refused), "sign": "-"}]
	(get_node("%Result") as PageCard).show_page({"template": "card", "title": tr("games.rescue.title.%s" % ("won" if won else "lost")),
		"sticky": true, "blocks": [{"type": "paragraph", "text": tr("games.rescue.text.%s" % ("won" if won else "lost"))},
			{"type": "divider"}, {"type": "effects", "items": effects}],
		"buttons": [{"id": "close", "text": tr("games.ui.close"), "primary": true}]})
	finished.emit(m.result())


func _show_result(refused: String) -> void:
	var r := m.result()
	var w := int(r["winner"])
	var g := str(spec["game"])
	var how := str(applied.get("how", r["how"]))
	if how == "caught":
		w = -1
	var key := "draw" if w < 0 else ("win" if w == 0 else "lose")
	var net := int(applied.get("net", (r["net"] as Array)[0]))
	var effects: Array = []
	if watch:
		key = "watched"
		if bet_event.is_empty():
			effects.append({"text": tr("games.bets.none"), "sign": ""})
		else:
			var bn := int(bet_event["net"])
			effects.append({"text": tr("games.bets.result.%s" % ("won" if bool(bet_event["won"]) else "lost")) % SocialKit.signed(bn),
				"sign": "+" if bn > 0 else "-"})
			if int(bet_event.get("house_cut", 0)) > 0:
				effects.append({"text": tr("games.result.house") % int(bet_event["house_cut"]), "sign": ""})
	elif not applied.is_empty() or not _give.is_valid():
		if net != 0:
			effects.append({"text": tr("games.result.gold") % SocialKit.signed(net), "sign": "+" if net > 0 else "-"})
		if int(applied.get("house_cut", 0)) > 0:
			effects.append({"text": tr("games.result.house") % int(applied["house_cut"]), "sign": ""})
		var bn2 := int(applied.get("bets_net", 0))
		if not bets.is_empty():
			effects.append({"text": tr("games.bets.result.%s" % ("won" if bn2 > 0 else "lost")) % SocialKit.signed(bn2),
				"sign": "+" if bn2 > 0 else "-"})
		if int(applied.get("entry", 0)) > 0:
			effects.append({"text": tr("games.result.entry") % int(applied["entry"]), "sign": "-"})
		for f: Dictionary in applied.get("facts", []):
			if str(f.get("kind", "")) == "prize":
				var pt := tr("games.result.prize") % [int(f.get("gold", 0)), SocialKit.signed(int(f.get("reputation", 0)))] \
					if int(f.get("gold", 0)) > 0 else tr("games.result.prize_rep") % SocialKit.signed(int(f.get("reputation", 0)))
				effects.append({"text": pt, "sign": "+"})
			elif str(f.get("kind", "")) == "finalist":
				effects.append({"text": tr("games.result.finalist") % SocialKit.signed(int(f.get("reputation", 0))), "sign": "+"})
			elif str(f.get("kind", "")) == "bulls":
				effects.append({"text": tr("games.result.bulls") % [int(f.get("breaks", 0)), int(f.get("fails", 0))],
					"sign": "+" if int(f.get("fails", 0)) == 0 else "-"})
			elif str(f.get("kind", "")) == "favor":
				effects.append({"text": tr("games.result.favor") % _who_id(str(f.get("of", ""))), "sign": "+"})
			if str(f.get("kind", "")) == "caught":
				effects.append({"text": tr("games.result.caught") % _who_id(str(f.get("by", ""))), "sign": "-"})
			elif str(f.get("kind", "")) == "fraud":
				effects.append({"text": tr("games.result.fraud"), "sign": "-"})
	if refused != "":
		effects.append({"text": tr("games.result.refused") % tr("reason.%s" % refused), "sign": "-"})
	if effects.is_empty():
		effects.append({"text": tr("games.result.nothing"), "sign": ""})
	var winner_name := str(_names[w]) if w >= 0 else ""
	var first := tr("games.%s.result.%s" % [g, "win" if w >= 0 else "draw"]) % winner_name if w >= 0 \
		else tr("games.%s.result.draw" % g)
	var page := {"template": "card", "title": tr("games.result.%s" % key), "sticky": true,
		"blocks": [
			{"type": "paragraph", "text": first},
			{"type": "paragraph", "text": tr("games.how.caught") if how == "caught" else tr("games.%s.how.%s" % [g, how])},
			{"type": "divider"},
			{"type": "effects", "items": effects}],
		"buttons": [{"id": "again", "text": tr("games.ui.again"), "primary": true}, {"id": "close", "text": tr("games.ui.close")}]}
	var ill := VisualPaths.game_illustration("game_%s" % g)
	if ill != null:
		page["image"] = ill
	(get_node("%Result") as PageCard).show_page(page)
	finished.emit(r)


func _who_id(id: String) -> String:
	for i: int in (spec["players"] as Array).size():
		if str((spec["players"][i] as Dictionary)["id"]) == id:
			return str(_names[i])
	return str(_state.characters.get(id, {}).get("name", id))


func _on_result_button(id: String) -> void:
	if id == "again":
		var req := request.duplicate(true)
		req.erase("match")
		open(req, _state, cfg, _give)
	else:
		close()


func close() -> void:
	visible = false
	(get_node("%Result") as PageCard).visible = false
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	var k := (event as InputEventKey).physical_keycode
	if k == KEY_ESCAPE:
		if m != null and not m.over():
			_auto()
		elif not busy:
			close()
	elif (get_node("%Result") as PageCard).visible:
		pass
	elif k in KEYS:
		# the key presses the button that shows its number (MenuKit.add_hint), the bets' buttons too (verificación A7)
		var btns: Array = (get_node("%Actions") as Container).get_children().filter(func(c: Node) -> bool:
			return c is Button and (c as Button).visible)
		var i := KEYS.find(k)
		if i < btns.size() and not (btns[i] as Button).disabled:
			(btns[i] as Button).pressed.emit()
	elif k == KEY_A:
		_auto()
	get_viewport().set_input_as_handled()
