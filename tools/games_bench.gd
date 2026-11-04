extends SceneTree
## Measures the games of 04f §4.26 (docs/gdd/04f_vida_y_fiestas.md; data/games.json): for each game, the played side
## against the AI with «Resolver sin jugar», with a player who plays well with only what the screen shows, one who
## chooses at random and the fixed policies. Pure rules, no world.
##   godot --headless --path . -s tools/games_bench.gd [-- --n=4000 --only=azar,pulso --set=<path>=<json>]
## A staked game reports the expected gold per game in stakes (EV) and the share of games won; a competition, the
## share won. --set changes a figure of the table for this run only (e.g. --set=pulso.win.advantage=20).

var cfg: Dictionary = {}
var n: int = 4000
var only: Array = []


func _init() -> void:
	cfg = Catalog.load_from().games.duplicate(true)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = a.substr(4).to_int()
		elif a.begins_with("--only="):
			only = Array(a.substr(7).split(","))
		elif a.begins_with("--set="):
			var kv := a.substr(6).split("=", true, 1)
			var path := kv[0].split(".")
			var node: Dictionary = cfg
			for i in path.size() - 1:
				node = node[path[i]]
			node[path[path.size() - 1]] = JSON.parse_string(kv[1])
			print("[GamesBench] --set %s = %s" % [kv[0], kv[1]])
	GameMatch.verbose = false
	print("[GamesBench] %d partidas por fila" % n)
	for g: String in ["azar", "mayor", "pulso", "envite", "tourney", "joust", "sortija", "race", "bulls"]:
		if only.is_empty() or g in only:
			call("_bench_" + g)
	quit(0)


func _p(preset: String, over: Dictionary = {}) -> Dictionary:
	var p := Games.preset_player(cfg, "preset:" + preset)
	(p["stats"] as Dictionary).merge(over, true)
	return p


## Plays one game with `policy` on side 0: Callable(m, view) -> action.
func _play(game: String, i: int, players: Array, policy: Callable, stake: int, opts: Dictionary) -> GameMatch:
	var spec := {"game": game, "match": "bench|%s|%d" % [game, i], "seed": 7000 + i, "players": players,
		"player": 0 if policy.is_valid() else -1, "stake": stake, "opts": opts}
	var m := Games.create(cfg, spec)
	var guard := 0
	while policy.is_valid() and not m.over() and guard < 200:
		guard += 1
		var v := m.view(0)
		if int(v["turn"]) != 0:
			break
		var act := str(policy.call(m, v))
		if not bool(m.choose(0, act)["ok"]):
			m.choose(0, str(m.allowed(0)[0]))
	return m


func _row(label: String, game: String, players: Array, policy: Callable, stake: int = 10, opts: Dictionary = {}) -> Dictionary:
	var w := 0
	var net := 0.0
	for i: int in n:
		var m := _play(game, i, players, policy, stake, opts)
		var r := m.result()
		w += int(int(r["winner"]) == 0)
		net += float((r["net"] as Array)[0])
	var ev := net / n / maxf(1.0, float(stake))
	if stake > 0:
		print("| %s | %+.3f | %d %% |" % [label, ev, roundi(100.0 * w / n)])
	else:
		print("| %s | %d %% |" % [label, roundi(100.0 * w / n)])
	return {"ev": ev, "won": float(w) / n}


func _random(m: GameMatch, _v: Dictionary) -> String:
	return GameRules.pick(m.allowed(0), 99, m.id(), (m.moves() as Array).size(), "bench_random")


# --- Azar ------------------------------------------------------------------------------------------------------------

func _bench_azar() -> void:
	print("")
	print("Azar (iguales, en la calle, apuesta 10) | Oro por partida (apuestas) | Gana |")
	print("|---|---|---|")
	var ps := [_p("regular_even"), _p("regular_even")]
	_row("Resolver sin jugar", "azar", ps, Callable())
	_row("Juega bien (lo que dice la pantalla)", "azar", ps, func(_m: GameMatch, v: Dictionary) -> String:
		if str(v["phase"]) == "offer":
			return "double" if float(v["win"]) > float(v["double_at"]) and "double" in _m.allowed(0) else "pass"
		return "accept" if float(v["win"]) >= float(v["accept_at"]) else "refuse")
	_row("Al azar", "azar", ps, _random)
	_row("Siempre dobla y acepta", "azar", ps, func(_m: GameMatch, v: Dictionary) -> String:
		return ("double" if "double" in _m.allowed(0) else "pass") if str(v["phase"]) == "offer" else "accept")
	_row("Nunca dobla, siempre acepta", "azar", ps, func(_m: GameMatch, v: Dictionary) -> String:
		return "pass" if str(v["phase"]) == "offer" else "accept")
	_row("Nunca dobla, nunca acepta", "azar", ps, func(_m: GameMatch, v: Dictionary) -> String:
		return "pass" if str(v["phase"]) == "offer" else "refuse")
	_row("Resolver sin jugar en la tafurería (casa 10 %)", "azar", ps, Callable(), 10, {"rake": 0.1})
	_row("Contra el fanfarrón", "azar", [_p("regular_even"), _p("regular_boastful")], Callable())
	_row("Contra el prudente", "azar", [_p("regular_even"), _p("regular_prudent")], Callable())
	_row("Con dados cargados (tira él)", "azar", ps, Callable(), 10, {"loaded": 0, "thrower": 0})
	_row("Sin dados cargados (tira él)", "azar", ps, Callable(), 10, {"thrower": 0})


# --- Tres dados a la mayor ---------------------------------------------------------------------------------------------

func _bench_mayor() -> void:
	for k: int in [2, 3]:
		print("")
		print("A la mayor (%d jugadores, iguales, apuesta 10) | Oro por partida (apuestas) | Gana |" % (k + 1))
		print("|---|---|---|")
		var ps: Array = [_p("regular_even")]
		for i: int in k:
			ps.append(_p("regular_even"))
		_row("Resolver sin jugar", "mayor", ps, Callable())
		_row("Juega bien (lo que dice la pantalla)", "mayor", ps, func(_m: GameMatch, v: Dictionary) -> String:
			return "stay" if float(v["ev_stay"]) > float(v["ev_retire"]) else "retire")
		_row("Al azar", "mayor", ps, _random)
		_row("Siempre sigue", "mayor", ps, func(_m: GameMatch, _v: Dictionary) -> String: return "stay")
		_row("Siempre se retira", "mayor", ps, func(_m: GameMatch, _v: Dictionary) -> String: return "retire")
		if k == 2:
			_row("Contra un fanfarrón y un prudente", "mayor", [_p("regular_even"), _p("regular_boastful"),
				_p("regular_prudent")], Callable())
			_row("Con dados cargados", "mayor", ps, Callable(), 10, {"loaded": 0})


# --- Pulso -----------------------------------------------------------------------------------------------------------

func _bench_pulso() -> void:
	print("")
	print("| Pulso | Gana |")
	print("|---|---|")
	var plain := {"constitution": 3, "empathy": 3}
	_row("Iguales (Con 3, Emp 3)", "pulso", [_p("regular_even", plain), _p("regular_even", plain)], Callable(), 0)
	_row("Constitución 5 vs 3", "pulso", [_p("regular_even", {"constitution": 5, "empathy": 3}),
		_p("regular_even", plain)], Callable(), 0)
	_row("Constitución 7 vs 3", "pulso", [_p("regular_even", {"constitution": 7, "empathy": 3}),
		_p("regular_even", plain)], Callable(), 0)
	_row("Empatía 7 vs 3", "pulso", [_p("regular_even", {"constitution": 3, "empathy": 7}),
		_p("regular_even", plain)], Callable(), 0)
	print("")
	print("| El jugador (iguales) contra la IA | Gana |")
	print("|---|---|")
	var ps := [_p("regular_even", plain), _p("regular_even", plain)]
	_row("Resolver sin jugar", "pulso", ps, Callable(), 0)
	_row("Sigue la pista", "pulso", ps, func(m: GameMatch, v: Dictionary) -> String:
		var pm := m as PulsoMatch
		return pm.ai_choice(0, str(v["role"]), str((v["cue"] as Dictionary).get("id", ""))), 0)
	_row("Al azar", "pulso", ps, _random, 0)
	for act: String in ["push", "give", "hold"]:
		var a := act
		_row("Siempre %s" % act, "pulso", ps, func(m: GameMatch, _v: Dictionary) -> String:
			return a if a in m.allowed(0) else "hold", 0)


# --- Envite ------------------------------------------------------------------------------------------------------------

## «Plays well» with what the screen shows: the chance counting the gesture against the thresholds it shows.
func _envite_good(m: GameMatch, v: Dictionary, use_gesture: bool = true) -> String:
	var em := m as EnviteMatch
	var ai: Dictionary = cfg["envite"]["ai"]
	var p := float(v["win_gesture"]) if use_gesture else float(v["win"])
	var ok := m.allowed(0)
	if "raise" in ok or "pass" in ok:
		return "raise" if "raise" in ok and p >= float(ai["raise_at"]) else "pass"
	if "reraise" in ok and p >= float(ai["reraise_at"]):
		return "reraise"
	return "want" if p >= float(v["want_at"]) else "fold"


func _bench_envite() -> void:
	print("")
	print("Envite (iguales Emp 3 / Ret 3, apuesta 5) | Oro por partida (apuestas) | Gana |")
	print("|---|---|---|")
	var ps := [_p("regular_even"), _p("regular_even")]
	_row("Resolver sin jugar", "envite", ps, Callable(), 5)
	_row("Juega bien (oportunidad con el gesto)", "envite", ps, _envite_good, 5)
	_row("Sin mirar el gesto", "envite", ps, func(m: GameMatch, v: Dictionary) -> String:
		return _envite_good(m, v, false), 5)
	_row("Al azar", "envite", ps, _random, 5)
	_row("Siempre quiere, nunca envida", "envite", ps, func(m: GameMatch, _v: Dictionary) -> String:
		return "pass" if "pass" in m.allowed(0) else "want", 5)
	_row("Envida siempre y siempre quiere", "envite", ps, func(m: GameMatch, _v: Dictionary) -> String:
		var ok := m.allowed(0)
		if "raise" in ok:
			return "raise"
		if "reraise" in ok:
			return "reraise"
		return "want" if "want" in ok else "pass", 5)
	_row("Nunca quiere un envite", "envite", ps, func(m: GameMatch, _v: Dictionary) -> String:
		return "pass" if "pass" in m.allowed(0) else "fold", 5)
	_row("Contra el fanfarrón", "envite", [_p("regular_even"), _p("regular_boastful")], Callable(), 5)
	_row("Contra el prudente", "envite", [_p("regular_even"), _p("regular_prudent")], Callable(), 5)
	_row("Contra el tramposo", "envite", [_p("regular_even"), _p("regular_cheat")], Callable(), 5)
	_row("Empatía 7 contra Retórica 3", "envite", [_p("regular_even", {"empathy": 7}), _p("regular_even")], Callable(), 5)
	_row("Retórica 7 contra Empatía 3", "envite", [_p("regular_even", {"rhetoric": 7}), _p("regular_even")], Callable(), 5)


# --- Torneo de lucha ---------------------------------------------------------------------------------------------------

func _tourney_field(me_stats: Dictionary) -> Array:
	var ps: Array = [_p("regular_even", me_stats)]
	for o: Variant in cfg["tourney"]["outsiders"]:
		ps.append(Games.preset_player(cfg, "preset:" + str(o)))
	return ps


## Rounds won by side 0 on average (0-3) and the share of tournaments won.
func _trow(label: String, ps: Array, policy: Callable) -> void:
	var w := 0
	var rounds := 0
	var nn := maxi(1, n / 4)
	for i: int in nn:
		var m := _play("tourney", i, ps, policy, 0, {})
		w += int(int(m.result()["winner"]) == 0)
		rounds += int((m.d["rounds_won"] as Array)[0])
	print("| %s | %d %% | %.2f |" % [label, roundi(100.0 * w / nn), float(rounds) / nn])


func _bench_tourney() -> void:
	print("")
	print("| Torneo de lucha (espada; el campo: 7 forasteros, Arte Marcial 4-7) | Gana el torneo | Combates ganados |")
	print("|---|---|---|")
	for am: int in [3, 5, 7]:
		var ps := _tourney_field({"martial": am, "empathy": 3, "constitution": 5})
		_trow("Arte Marcial %d · Resolver sin jugar" % am, ps, Callable())
		if am == 5:
			_trow("Arte Marcial 5 · Sigue la pista", ps, func(m: GameMatch, _v: Dictionary) -> String: return m.ai_move(0))
			_trow("Arte Marcial 5 · Al azar", ps, _random)
			for act: String in CombatRules.ACTIONS:
				var a := act
				_trow("Arte Marcial 5 · Siempre %s" % act, ps, func(m: GameMatch, _v: Dictionary) -> String:
					return a if a in m.allowed(0) else "parry")


# --- Justa -------------------------------------------------------------------------------------------------------------

func _bench_joust() -> void:
	print("")
	print("| Justa (contra un caballero templado) | Gana | Tablas | Desmontado |")
	print("|---|---|---|---|")
	var plain := {"martial": 3, "empathy": 3, "dexterity": 3}
	var ps := [_p("regular_even", plain), _p("regular_even", plain)]
	_jrow("Iguales · Resolver sin jugar", ps, Callable())
	_jrow("Iguales · Sigue la pista (la política de la IA)", ps, func(m: GameMatch, _v: Dictionary) -> String: return m.ai_move(0))
	_jrow("Iguales · Al azar", ps, _random)
	for st: String in JoustMatch.STANCES:
		var a := st
		_jrow("Iguales · Siempre %s" % st, ps, func(_m: GameMatch, _v: Dictionary) -> String: return a)
	_jrow("Destreza 6 vs 3", [_p("regular_even", {"dexterity": 6}), _p("regular_even", plain)], Callable())
	_jrow("Empatía 7 vs Arte Marcial 3", [_p("regular_even", {"empathy": 7}), _p("regular_even", plain)], Callable())
	_jrow("Arte Marcial 7 (se le lee peor) vs 3", [_p("regular_even", {"martial": 7}), _p("regular_even", plain)], Callable())


func _jrow(label: String, ps: Array, policy: Callable) -> void:
	var w := 0
	var dr := 0
	var un := 0
	for i: int in n:
		var m := _play("joust", i, ps, policy, 0, {})
		var r := m.result()
		w += int(int(r["winner"]) == 0)
		dr += int(int(r["winner"]) < 0)
		un += int(str(r["how"]) == "unhorsed")
	print("| %s | %d %% | %d %% | %d %% |" % [label, roundi(100.0 * w / n), roundi(100.0 * dr / n), roundi(100.0 * un / n)])


# --- Sortija -----------------------------------------------------------------------------------------------------------

func _bench_sortija() -> void:
	print("")
	print("| Sortija (contra 3 jinetes de Destreza 3-5) | Gana | Puntos | Anillas |")
	print("|---|---|---|---|")
	var ps: Array = [_p("regular_even", {"dexterity": 4})]
	for r: Variant in cfg["sortija"]["riders"]:
		ps.append(Games.preset_player(cfg, "preset:" + str(r)))
	_srow("Destreza 4 · Resolver sin jugar", ps, Callable())
	_srow("Destreza 4 · Sigue la anilla y el mejor ritmo", ps, func(m: GameMatch, _v: Dictionary) -> String: return m.ai_move(0))
	_srow("Destreza 4 · Al azar", ps, _random)
	for p: String in SortijaMatch.PACES:
		var pc := p
		_srow("Destreza 4 · Siempre %s (sigue la anilla)" % p, ps, func(m: GameMatch, v: Dictionary) -> String:
			return pc if str(v["phase"]) == "pace" else m.ai_move(0))
	_srow("Destreza 4 · Mejor ritmo, baja la lanza al azar", ps, func(m: GameMatch, v: Dictionary) -> String:
		return m.ai_move(0) if str(v["phase"]) == "pace" else _random(m, v))
	var ps7 := ps.duplicate()
	ps7[0] = _p("regular_even", {"dexterity": 7})
	_srow("Destreza 7 · Resolver sin jugar", ps7, Callable())


func _srow(label: String, ps: Array, policy: Callable) -> void:
	var w := 0
	var pts := 0
	var hits := 0
	for i: int in n:
		var m := _play("sortija", i, ps, policy, 0, {})
		w += int(int(m.result()["winner"]) == 0)
		pts += int((m.d["points"] as Array)[0])
		hits += int((m.d["hits"] as Array)[0])
	print("| %s | %d %% | %.2f | %.2f |" % [label, roundi(100.0 * w / n), float(pts) / n, float(hits) / n])


# --- Carrera de caballos -----------------------------------------------------------------------------------------------

func _bench_race() -> void:
	print("")
	print("| Carrera (alquilado: 10, fuelle 6; contra un rocín, un alquilado y un corcel) | Gana | Distancia |")
	print("|---|---|---|")
	var ps: Array = [_p("regular_even", {"dexterity": 4})]
	for r: Variant in cfg["race"]["riders"]:
		ps.append(Games.preset_player(cfg, "preset:" + str(r)))
	_rrow("Resolver sin jugar", ps, Callable())
	_rrow("Sigue el plan (la política de la IA)", ps, func(m: GameMatch, _v: Dictionary) -> String: return m.ai_move(0))
	_rrow("Al azar", ps, _random)
	for p: String in RaceMatch.PACES:
		var pc := p
		_rrow("Siempre %s (si puede)" % p, ps, func(m: GameMatch, _v: Dictionary) -> String:
			return pc if pc in m.allowed(0) else ("keep" if "keep" in m.allowed(0) else "reserve"))
	_rrow("Aprieta al salir y reserva luego", ps, func(m: GameMatch, v: Dictionary) -> String:
		return "press" if int(v["stretch"]) == 0 else "reserve")
	var pj := ps.duplicate()
	pj[0] = _p("regular_even", {"dexterity": 4})
	pj[0]["horse"] = "jennet"
	_rrow("Con una jaca (velocidad 10,5, fuelle 5)", pj, Callable())
	var pd := ps.duplicate()
	pd[0] = _p("regular_even", {"dexterity": 4})
	pd[0]["horse"] = "destrier"
	_rrow("Con un corcel de fuelle (9,9, 8)", pd, Callable())


func _rrow(label: String, ps: Array, policy: Callable) -> void:
	var w := 0
	var dist := 0.0
	for i: int in n:
		var m := _play("race", i, ps, policy, 0, {})
		w += int(int(m.result()["winner"]) == 0)
		dist += float((m.d["dist"] as Array)[0])
	print("| %s | %d %% | %.1f |" % [label, roundi(100.0 * w / n), dist / n])


# --- Toros -------------------------------------------------------------------------------------------------------------

func _bench_bulls() -> void:
	print("")
	print("| Toros (un mozo solo, tres embestidas) | Aplausos | Quiebros | Sustos |")
	print("|---|---|---|---|")
	for bull: String in ["bravo", "manso", "resabiado"]:
		var ps: Array = [_p("regular_even", {"dexterity": 4})]
		_brow("%s · Resolver sin jugar" % bull, ps, Callable(), bull)
		if bull == "bravo":
			_brow("%s · Sigue la señal (la política de la IA)" % bull, ps, func(m: GameMatch, _v: Dictionary) -> String: return m.ai_move(0), bull)
			_brow("%s · Al azar" % bull, ps, _random, bull)
			for a: String in BullsMatch.ACTIONS:
				var ac := a
				_brow("%s · Siempre %s" % [bull, a], ps, func(_m: GameMatch, _v: Dictionary) -> String: return ac, bull)
			_brow("%s · Destreza 7" % bull, [_p("regular_even", {"dexterity": 7})], Callable(), bull)


func _brow(label: String, ps: Array, policy: Callable, bull: String) -> void:
	var pts := 0.0
	var br := 0
	var fl := 0
	for i: int in n:
		var m := _play("bulls", i, ps, policy, 0, {"bull": bull})
		pts += float((m.d["points"] as Array)[0])
		br += int((m.d["breaks"] as Array)[0])
		fl += int((m.d["fails"] as Array)[0])
	print("| %s | %.2f | %.2f | %.2f |" % [label, pts / n, float(br) / n, float(fl) / n])
