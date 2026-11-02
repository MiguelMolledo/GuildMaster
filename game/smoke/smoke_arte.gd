extends Node
## Scripted capture of the town's art (--smoke-script=arte; run it through `grimoire heavy` with the engine's
## --always-on-top): scenario town_e_start at noon, paused, the camera on a few places and a shot of each
## (reports/shots/arte_<place>.png): the trees of the north, the river with the bridge, a block of houses and yards,
## the plaza, the south, the map's corner and west gate (its border), the fields in each season (the clock moved on by
## whole days, capture only); then scenario forge_upgrades with every upgrade of the
## forge marked as done (capture only: the state is edited directly) and its interior (arte_forja_mejoras).
## Quits when done, or after `timeout` seconds.

const PLACES: Array = [["norte", Vector2i(18, 3)], ["rio", Vector2i(35, 19)], ["manzana", Vector2i(20, 10)],
	["plaza", Vector2i(19, 17)], ["sur", Vector2i(12, 30)], ["esquina", Vector2i(39, 39)], ["oeste", Vector2i(0, 19)],
	["campos_primavera", Vector2i(6, 32), "spring"], ["campos_verano", Vector2i(6, 32), "summer"],
	["campos_otono", Vector2i(6, 32), "autumn"], ["campos_invierno", Vector2i(6, 32), "winter"]]

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
	if _t > 0.8:
		app.save_shot("arte_%s" % (PLACES[_i][0] if _i < PLACES.size() else "forja_mejoras"))
		_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	if _i == PLACES.size():
		var r := NewGame.from_scenario("forge_upgrades")
		r["state"].buildings["bld_0001"]["upgrades"] = Game.sim.catalog.upgrade_tree("forge").map(
			func(u: Variant) -> String: return str((u as Dictionary).get("id", u)) if u is Dictionary else str(u))
		Game.start(r["state"])
		Game.set_paused(true)
		app.open_interior("bld_0001", true)
		print("[SmokeArte] forge interior with every upgrade")
		return
	if _i > PLACES.size():
		print("[SmokeArte] done")
		get_tree().quit(0)
		return
	if _i < PLACES.size():
		print("[SmokeArte] camera on %s %s" % [PLACES[_i][0], PLACES[_i][1]])
		app.world().camera().center_on(Iso.tile_to_world(PLACES[_i][1]))
		if (PLACES[_i] as Array).size() > 2:
			_set_season(str(PLACES[_i][2]))


## Moves the clock on by whole days until it is `season` (the same time of day). Capture only.
func _set_season(season: String) -> void:
	var clock: Dictionary = Game.sim.state.clock
	for _k: int in 64:
		if Clock.season(int(clock["minute"]), Game.sim.catalog.time) == season:
			return
		clock["minute"] = int(clock["minute"]) + Clock.MINUTES_PER_DAY
