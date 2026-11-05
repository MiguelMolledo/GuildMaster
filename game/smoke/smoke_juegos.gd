extends Node
## Games bot (--smoke-script=juegos; docs/gdd/04f_vida_y_fiestas.md §4.26, docs/ui/mecanicas/juegos.md; run it through
## `grimoire heavy` with the engine's --always-on-top). For each game of --smoke-games=<a,b,...> (default: all of
## Games.GAMES) it opens the game over the paused town (App.open_games_test: played for real, its order goes to the
## sim) and plays it with the AI's policy (what plays well): a capture before the first decision (juegos_<game>_1),
## one in the middle of the key moment's animation (juegos_<game>_2) and the result card (juegos_<game>_3). Checks
## that the board, both portraits, the decision box and the buttons are visible, that the result card came and that
## the order was applied (game_played). Quits with 1 if something is missing or on timeout.

var app: Node = null
var timeout: float = 240.0
var _games: Array = []
var _i: int = -1
var _screen: GameScreen = null
var _step: String = "next"
var _t: float = 0.0
var _total: float = 0.0
var _bad: int = 0
var _shot_key: bool = false
var _tries: int = 0


func _ready() -> void:
	_games = Array(Games.GAMES) + ["apuestas", "rescue", "brawl", "fair_bet", "festival_joust"]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
		elif a.begins_with("--smoke-games="):
			_games = Array(a.substr(14).split(","))
	print("[SmokeJuegos] start: %s (timeout=%.0f s)" % [_games, timeout])


func _go(step: String) -> void:
	print("[SmokeJuegos] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _game() -> String:
	return str(_games[_i])


func _visible_check() -> void:
	for n: String in ["%BoardHolder", "%LeftPortrait", "%RightPortrait", "%InfoTitle", "%Auto"]:
		var c := _screen.get_node(n) as Control
		if not c.is_visible_in_tree() or c.get_global_rect().size.x < 2.0:
			print("[SmokeJuegos] %s: %s no se ve" % [_game(), n])
			_bad += 1
	var buttons := 0
	for c: Node in _screen.get_node("%Actions").get_children():
		if c.has_meta("action"):
			buttons += 1
	if buttons == 0 and not _screen.m.over():
		print("[SmokeJuegos] %s: sin botones de decisión" % _game())
		_bad += 1


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeJuegos] TIMEOUT in step %s" % _step)
		app.save_shot("juegos_timeout")
		get_tree().quit(1)
		return
	match _step:
		"next":
			if _t > 0.6:
				_i += 1
				if _i >= _games.size():
					_go("done")
					print("[SmokeJuegos] fin: %d juegos, %d problemas" % [_games.size(), _bad])
					get_tree().quit(1 if _bad > 0 else 0)
					return
				_tries = 0
				_screen = app.open_games_test(_game(), {"match": "%s|smoke|0" % _game()})
				_shot_key = false
				_go("first")
		"first":
			if _t > 0.8 and not _screen.busy:
				if _screen.m.over() and not _screen.watch and _tries < 12:  # an azar on the first throw: nothing to decide, another game
					_tries += 1
					_screen = app.open_games_test(_game(), {"match": "%s|smoke|%d" % [_game(), _tries]})
					_t = 0.0
					return
				if not _screen.watch:
					_visible_check()
				app.save_shot("juegos_%s_1" % _game())
				_go("play")
		"play":
			if _screen.betting:
				_screen._choose("bet_1" if _screen.watch else "bet_0")  # on oneself in one's own game
				_t = 0.0
				return
			if _screen.busy:
				if not _shot_key and _t > 0.15:
					_shot_key = true
					app.save_shot("juegos_%s_2" % _game())
				return
			if _screen.m.over():
				_go("wait_result")
				return
			if _t > 0.3:
				var act := _screen.m.ai_move(0)
				if act == "":
					_go("wait_result")
					return
				_screen._choose(act)
				_t = 0.0
		"wait_result":
			var card := _screen.get_node("%Result") as PageCard
			if card.visible and _t > 0.6:
				if not _shot_key:
					app.save_shot("juegos_%s_2" % _game())
				app.save_shot("juegos_%s_3" % _game())
				if _screen.bet_only or _screen.request.get("order") is Dictionary:
					print("[SmokeJuegos] %s: %s" % [_game(), "apuesta puesta" if _screen.bet_only else "rescate %s" % _screen.applied])
					if _screen.request.get("order") is Dictionary and _screen.applied.is_empty():
						_bad += 1
				elif _screen.watch:
					if _screen.bet_event.is_empty():
						print("[SmokeJuegos] %s: la apuesta game_bet no se aplicó" % _game())
						_bad += 1
					else:
						print("[SmokeJuegos] %s: apuesta aplicada, oro %+d" % [_game(), int(_screen.bet_event["net"])])
				elif _screen.applied.is_empty():
					print("[SmokeJuegos] %s: la orden game_play no se aplicó" % _game())
					_bad += 1
				else:
					print("[SmokeJuegos] %s: aplicada, oro %+d (%s)" % [_game(), int(_screen.applied["net"]),
						_screen.applied["how"]])
				_screen.close()
				_go("next")
