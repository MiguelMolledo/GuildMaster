extends Node
## Scripted check of walking with the keys (--smoke-script=teclas; run it through `grimoire heavy` with the engine's
## --always-on-top): the capital, its head selected and the camera somewhere else; real key events (the same road as
## the OS) hold W, then D, then S+A, then a tap of W+D; then with nobody selected D pans the camera. Each leg checks
## what the walker and the camera did, logs it and takes a shot (reports/shots/teclas_<leg>.png). Exit code 1 if a
## check fails or after `timeout` seconds.

# [name, keys held, seconds held, seconds waited after letting go]
const LEGS: Array = [
	["w", [KEY_W], 2.4, 0.9],
	["d", [KEY_D], 2.4, 0.9],
	["sa", [KEY_S, KEY_A], 2.0, 0.9],
	["toque_wd", [KEY_W, KEY_D], 0.08, 1.2],
	["sin_nadie_d", [KEY_D], 1.0, 0.3],
]

var app: Node = null
var timeout: float = 60.0
var _total: float = 0.0
var _t: float = 0.0
var _i: int = -1
var _held: bool = false
var _who: String = ""
var _from: Vector2i = Vector2i.ZERO
var _cam_from: Vector2 = Vector2.ZERO
var _orders: int = 0
var _refused: int = 0
var _failed: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-timeout="):
			timeout = a.substr(16).to_float()
	Game.order_given.connect(func(_o: Dictionary) -> void: _orders += 1)
	Events.sim_event.connect(func(e: Dictionary) -> void:
		if str(e.get("type", "")) == "order_refused":
			_refused += 1
			print("[SmokeTeclas] order refused: %s" % str(e)))
	print("[SmokeTeclas] start (%d legs)" % LEGS.size())


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeTeclas] TIMEOUT at leg %d" % _i)
		get_tree().quit(1)
		return
	if _i == -1:
		if _t > 0.5:
			_start()
		return
	var leg: Array = LEGS[_i]
	if _held and _t >= float(leg[2]):
		_keys(leg[1], false)
		_held = false
		_t = 0.0
	elif not _held and _t >= float(leg[3]):
		_end_leg()
		_next()


func _start() -> void:
	var r := NewGame.from_scenario("region_capital_start")
	if not bool(r.get("ok", false)):
		print("[SmokeTeclas] scenario failed: %s" % r.get("error", ""))
		get_tree().quit(1)
		return
	Game.start(r["state"])
	Game.set_paused(false)
	var w: WorldView = app.world()
	_who = w.first_selectable()
	w.select(_who)
	w.camera().zoom_index = 0
	w.camera().center_on(Iso.tile_to_world(Vector2i(60, 20)))  # far from the walker: the keys bring the camera back
	_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	if _i >= LEGS.size():
		print("[SmokeTeclas] done: %s (refused=%d)" % ["FAILED %d" % _failed if _failed > 0 else "ok", _refused])
		get_tree().quit(1 if _failed > 0 or _refused > 0 else 0)
		return
	var w: WorldView = app.world()
	if str(LEGS[_i][0]).begins_with("sin_nadie"):
		w.select("")
	_from = _tile()
	_cam_from = w.camera().position
	_orders = 0
	_keys(LEGS[_i][1], true)
	_held = true


func _end_leg() -> void:
	var leg: Array = LEGS[_i]
	var w: WorldView = app.world()
	var at := _tile()
	var cam := w.camera().position
	var feet := w.view_of(_who).position
	var walking := not (Game.sim.state.characters[_who].get("path", []) as Array).is_empty()
	print("[SmokeTeclas] %s: tile %s -> %s (%d tiles), orders=%d, camera moved %d px, camera to walker %d px, walking=%s"
		% [leg[0], _from, at, maxi(absi(at.x - _from.x), absi(at.y - _from.y)), _orders,
		int(cam.distance_to(_cam_from)), int(cam.distance_to(feet)), walking])
	match str(leg[0]):
		"toque_wd":
			_check(maxi(absi(at.x - _from.x), absi(at.y - _from.y)) <= 1, "a tap walks one tile at most")
			_check(not walking, "and stops")
		"sin_nadie_d":
			_check(at == _from, "nobody selected: nobody walks")
			_check(cam.x > _cam_from.x + 100.0, "the keys pan the camera")
		_:
			_check(at != _from, "the walker moved")
			_check(not walking, "and stopped after the keys were let go")
			_check(cam.distance_to(feet) < 60.0, "the camera is on the walker")
	app.save_shot("teclas_%s" % leg[0])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print("[SmokeTeclas]   %s %s" % ["ok  " if ok else "FAIL", what])


func _tile() -> Vector2i:
	var p: Array = Game.sim.state.characters[_who]["position"]
	return Vector2i(int(p[0]), int(p[1]))


func _keys(keys: Array, pressed: bool) -> void:
	for k: int in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k as Key
		e.keycode = k as Key
		e.pressed = pressed
		Input.parse_input_event(e)
