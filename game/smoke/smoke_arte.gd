extends Node
## Scripted capture of the town's art (--smoke-script=arte; run it through `grimoire heavy` with the engine's
## --always-on-top): scenario town_e_start at noon, paused, the camera on a few places and a shot of each
## (reports/shots/arte_<place>.png): the trees of the north, the river with the bridge, a block of houses and yards,
## and the plaza. Quits when done, or after `timeout` seconds.

const PLACES: Array = [["norte", Vector2i(18, 3)], ["rio", Vector2i(35, 19)], ["manzana", Vector2i(20, 10)],
	["plaza", Vector2i(19, 17)], ["sur", Vector2i(12, 30)]]

var app: Node = null
var timeout: float = 60.0
var _t: float = 0.0
var _total: float = 0.0
var _i: int = -1


func _ready() -> void:
	print("[SmokeArte] start (%d places)" % PLACES.size())


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeArte] TIMEOUT at place %d" % _i)
		get_tree().quit(1)
		return
	if _i == -1:
		if _t > 0.5:
			var r := NewGame.from_scenario("town_e_start")
			Game.start(r["state"])
			Game.set_paused(true)
			_next()
		return
	if _t > 0.5:
		app.save_shot("arte_%s" % PLACES[_i][0])
		_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	if _i >= PLACES.size():
		print("[SmokeArte] done")
		get_tree().quit(0)
		return
	print("[SmokeArte] camera on %s %s" % [PLACES[_i][0], PLACES[_i][1]])
	app.world().camera().center_on(Iso.tile_to_world(PLACES[_i][1]))
