extends Node
## Duel bot (--smoke-script=duel; docs/gdd/04e_combate.md §4e.8, docs/ui/mecanicas/combate.md; run it through
## `grimoire heavy` with the engine's --always-on-top). Opens the duel prototype over the paused game (the protagonist
## against the rival smith; --duel-kind / --duel-weapon as --duel-test) and plays a whole duel: when it reads, it
## answers the gesture (what beats it) unless the reliability is low, then it parries; when it leads, it strikes,
## feints and parries in turn as its breath allows. One capture before each choice (duel_lance_NN: the gesture and the
## buttons) and one in the middle of each lance's animation (duel_lance_NN_b), the result card (duel_result) and, with
## --duel-again, a second duel resolved with «Resolver sin jugar» (duel_auto_result). Checks on screen that the gesture,
## both portraits and the buttons are visible and prints the count. Quits with 1 if something is missing or on timeout.

var app: Node = null
var timeout: float = 120.0
var _screen: DuelScreen = null
var _step: String = "start"
var _t: float = 0.0
var _total: float = 0.0
var _bad: int = 0
var _lead_turn: int = 0
var _again: bool = false
var _shot_after: int = -1


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
		elif a == "--duel-again":
			_again = true
	print("[SmokeDuel] start (timeout=%.0f s)" % timeout)


func _go(step: String) -> void:
	print("[SmokeDuel] %s -> %s (t=%.1f s)" % [_step, step, _total])
	_step = step
	_t = 0.0


func _visible_check(what: String) -> void:
	var needed := ["%GestureTitle", "%GestureText", "%LeftPortrait", "%RightPortrait", "%Strike", "%Parry", "%Feint",
		"%Arena"]
	var bad := 0
	for n: String in needed:
		var c := _screen.get_node(n) as Control
		if not c.is_visible_in_tree() or c.get_global_rect().size.x < 2.0:
			print("[SmokeDuel] %s: %s no se ve" % [what, n])
			bad += 1
	_bad += bad


func _choice(v: Dictionary) -> String:
	var allowed: Array = v["allowed"]
	if str(v["role"]) == "read":
		if float(v["read"]) >= 0.45:
			var best := CombatRules.counter_of(_screen.cfg, str(v["cue"]))
			if best in allowed:
				return best
		return "parry"
	var order := ["strike", "feint", "parry"]
	for i: int in 3:
		var a: String = order[(_lead_turn + i) % 3]
		if a in allowed:
			_lead_turn += 1
			return a
	return "parry"


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout and _step != "done":
		print("[SmokeDuel] TIMEOUT in step %s" % _step)
		app.save_shot("duel_timeout")
		get_tree().quit(1)
		return
	match _step:
		"start":
			if _t > 0.5:
				_screen = app.open_duel_test()
				_go("choose")
		"choose":
			if _screen.busy and _shot_after >= 0 and _t > 0.25:
				app.save_shot("duel_lance_%02d_b" % (_shot_after + 1))  # mid-animation: the lunge and the effect
				_shot_after = -1
			if _t < 0.5 or _screen.busy:
				return
			if _screen.duel.over():
				_go("result")
				return
			var v := _screen.duel.view(_screen.player)
			_visible_check("lance %d" % (int(v["lance"]) + 1))
			app.save_shot("duel_lance_%02d" % (int(v["lance"]) + 1))
			var act := _choice(v)
			print("[SmokeDuel] lance %d: %s, pista %s (fiable %.2f, me lee %.2f), aliento %d -> %s" % [
				int(v["lance"]) + 1, v["role"], v["cue"], float(v["read"]), float(v["read_by"]),
				_screen.duel.breath(_screen.player), act])
			_shot_after = int(v["lance"])
			_screen._choose(act)
			_t = 0.0
		"result":
			if _t > 0.8:
				app.save_shot("duel_result")
				var r := _screen.duel.result()
				print("[SmokeDuel] resultado: ganador %d (%s), toques %s, lances %d" % [int(r["winner"]), r["end"],
					r["touches"], int(r["lances"])])
				if _again:
					_screen._on_result_button("again")
					_go("auto")
				else:
					_go("done")
		"auto":
			if _t > 0.8 and not _screen.busy and not _screen.duel.over():
				app.save_shot("duel_auto_start")
				_screen._auto_finish()
			elif _screen.duel.over() and not _screen.busy and _t > 1.0:
				app.save_shot("duel_auto_result")
				print("[SmokeDuel] resolver sin jugar: %s" % [_screen.duel.result()])
				_go("done")
		"done":
			if _t > 0.2:
				print("[SmokeDuel] done: %d problemas" % _bad)
				get_tree().quit(1 if _bad > 0 else 0)
