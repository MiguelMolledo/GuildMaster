extends Node
## The tutorial's data test with a window (--smoke-script=tutorial_datos, docs/ui/05_tutorial.md §8; through
## `grimoire heavy`): for every chapter, in the game of its "test" (a new game of a start, or a scenario), every step
## is shown in turn (the tutorial on hold: nothing moves on by itself) and must find its own target. When the focus
## falls on what opens it, that is opened as the player would (a button pressed, the own workshop managed with a
## double click, another building entered and a stall visited walking there with the game running, the station's
## menu) and it looks again, up to MAX_TRIES (a walk waits longer). A step whose "if" fails is skipped. Shots of the
## first and the last step of chapters 3 on (reports/shots/tut_<chapter>_primero.png / _ultimo.png). Prints one line
## per step and a summary; quits with 1 if any step does not find its target.

const MAX_TRIES: int = 6
const SETTLE: float = 0.5      # after showing a step
const AFTER_OPEN: float = 0.9  # after opening something (the fade into a building takes 0.4 s)
const AFTER_WALK: float = 4.0  # after sending the head somewhere (the game runs ×4 meanwhile)

var app: Node = null
var _tut: Tutorial = null
var _queue: Array = []
var _chapter: String = ""
var _i: int = -1
var _tries: int = 0
var _wait: float = 0.0
var _stage: String = "start"
var _last: int = -1
var _ok: int = 0
var _skipped: int = 0
var _failed: PackedStringArray = []
var _total: float = 0.0


func _process(delta: float) -> void:
	_total += delta
	if _total > 600.0:
		print("[SmokeTutorialDatos] TIMEOUT (chapter=%s, step=%d)" % [_chapter, _i])
		get_tree().quit(1)
		return
	_wait -= delta
	if _wait > 0.0:
		return
	match _stage:
		"start":
			_tut = app.tutorial()
			_tut.memory["game/tutorial_hints"] = false
			_queue = _tut.chapter_ids()
			_stage = "chapter"
		"chapter":
			if _queue.is_empty():
				_summary()
				return
			_chapter = str(_queue.pop_front())
			_load_game(_chapter)
			_wait = 1.0
			_stage = "begin"
		"begin":
			_tut.hold = true
			_tut.start(_chapter)
			_last = _last_step()
			_i = -1
			_next_step()
		"step":
			_check()


func _load_game(id: String) -> void:
	var test: Dictionary = _tut.chapters[id].get("test", {})
	var r: Dictionary
	if test.has("start"):
		r = NewGame.from_start(Game.sim.catalog, str(test["start"]), "normal", {}, 7)
	else:
		r = NewGame.from_scenario(str(test.get("scenario", "")))
	if not bool(r.get("ok", false)):
		_failed.append("%s: no game (%s)" % [id, r.get("error", "")])
		return
	Game.start(r["state"], Game.sim.catalog)
	app._enter_game()
	Game.set_paused(true)
	print("[SmokeTutorialDatos] chapter %s in %s" % [id, test])


## The index of the last step that will be shown (its "if" holds).
func _last_step() -> int:
	var out := -1
	for i: int in _tut.steps.size():
		if not _tut.steps[i].has("if") or _tut.ctx.condition(_tut.steps[i]["if"] as Dictionary):
			out = i
	return out


func _next_step() -> void:
	_i += 1
	while _i < _tut.steps.size() and _tut.steps[_i].has("if") and not _tut.ctx.condition(_tut.steps[_i]["if"] as Dictionary):
		print("[SmokeTutorialDatos]   %s.%s skipped (if)" % [_chapter, _tut.steps[_i]["id"]])
		_skipped += 1
		_i += 1
	if _i >= _tut.steps.size():
		_tut.hold = false
		_tut.stop()
		app.close_interior()
		_stage = "chapter"
		_wait = 0.6
		return
	_tries = 0
	_tut.show_step(_i)
	_stage = "step"
	_wait = SETTLE


func _check() -> void:
	var st := _tut.step()
	var f: Dictionary = _tut.focus
	var id := "%s.%s" % [_chapter, st.get("id", "")]
	if not st.has("target"):
		print("[SmokeTutorialDatos]   %s: no target (card in the free view)" % id)
		_found(st)
		return
	if bool(f.get("found", false)) and not bool(f.get("opener", false)):
		Game.set_paused(true)
		print("[SmokeTutorialDatos]   %s: found %s (tries=%d)" % [id, f.get("rect", Rect2()), _tries])
		_found(st)
		return
	if not bool(f.get("found", false)) or _tries >= MAX_TRIES:
		print("[SmokeTutorialDatos]   %s: NOT FOUND (target=%s, focus=%s, tries=%d)" % [id, st.get("target", {}),
			f.get("target", {}), _tries])
		_failed.append(id)
		app.save_shot("tut_falla_" + id.replace(".", "_"))
		_next_step()
		return
	_tries += 1
	print("[SmokeTutorialDatos]   %s: opens %s" % [id, f.get("target", {})])
	_wait = AFTER_WALK if _open(f.get("target", {}) as Dictionary, f.get("node") as Node) else AFTER_OPEN


func _found(st: Dictionary) -> void:
	_ok += 1
	var ids := _tut.chapter_ids()
	if ids.find(_chapter) >= 2 and (_i == _first_step() or _i == _last):
		app.save_shot("tut_%s_%s" % [_chapter, "primero" if _i == _first_step() else "ultimo"])
	_next_step()


func _first_step() -> int:
	for i: int in _tut.steps.size():
		if not _tut.steps[i].has("if") or _tut.ctx.condition(_tut.steps[i]["if"] as Dictionary):
			return i
	return -1


## Opens what the focus fell on, as the player would. True if the head was sent walking (the game runs meanwhile).
func _open(t: Dictionary, node: Node) -> bool:
	var st := Game.sim.state
	var head := Kin.head(st, SimQuery.player_family(st))
	var interior: InteriorView = app.interior()
	if t.has("ui"):
		var b := node as BaseButton
		if b == null:
			return false
		if b.toggle_mode and not b.button_pressed:
			b.button_pressed = true   # toggled (the building's bar)
		b.pressed.emit()              # pressed (tabs, the HUD's buttons)
		if str(b.name) == "ExitButton":
			_run()   # the head walks out: the order waits for the game to run
			return true
		return false
	var kind := str(t.get("world", ""))
	var id := str(_tut.ctx.symbol(t.get("id", "")))
	match kind:
		"building", "door":
			if not t.has("id"):
				for bid: String in st.buildings:
					if str(st.buildings[bid].get("type", "")) == str(t.get("type", "")):
						id = bid
						break
			app.world().select(head)
			if id == str(_tut.ctx.symbol("$workshop")):
				app.open_interior(id, true)   # double click: manage it
				return false
			app.world().command_enter(id)       # another building: walk in
			_run()
			return true
		"station":
			if interior.shop_stall != "":
				interior.open_shop()
			else:   # in management mode nobody of the family is inside: the menu as the head's
				interior.station_menu().open_for(Game.sim, head, interior.building, id, interior.station_screen(id))
		"service":
			app.world().select(head)
			for svc: Dictionary in app.world().get("_services"):
				if str(svc["id"]) == id:
					app.world().command_service(svc)   # walks there; the HUD opens its panel on arrival
			_run()
			return true
	return false


## The game runs ×4 while the head walks.
func _run() -> void:
	Game.set_speed(4)
	Game.set_paused(false)


func _summary() -> void:
	print("[SmokeTutorialDatos] %d steps found, %d skipped (if), %d fail%s" % [_ok, _skipped, _failed.size(),
		"" if _failed.is_empty() else ": " + ", ".join(_failed)])
	get_tree().quit(0 if _failed.is_empty() else 1)
