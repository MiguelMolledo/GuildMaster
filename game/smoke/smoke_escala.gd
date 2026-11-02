extends Node
## Scripted capture of the building scale (--smoke-script=escala; run it through `grimoire heavy` with the engine's
## --always-on-top): scenario town_e_start, paused, Hugo standing at the door of his forge (behind it, on the hidden
## side) and Ana at the town hall's service tile (behind it: selected there, the town hall goes see-through), the camera
## on the plaza, the forge street and the town hall at zoom 1 and zoom 2: reports/shots/escala_<place>_z<zoom>[_<tag>].png (--shot-tag=<tag>, e.g. antes / despues).
## forja_detras: Tomás behind the forge, selected (see-through); forja_mejoras: the forge with every upgrade at zoom 2. Quits when done, or after `timeout` seconds.

const PLACES: Array = [["plaza", Vector2i(19, 16), "chr_0001"], ["forja", Vector2i(26, 20), "chr_0001"],
	["ayuntamiento", Vector2i(20, 27), "chr_0002"], ["forja_detras", Vector2i(26, 20), "chr_0003"]]
const POSES: Dictionary = {"chr_0001": [26, 19], "chr_0002": [20, 25], "chr_0003": [25, 19]}

var app: Node = null
var timeout: float = 60.0
var tag: String = ""
var _t: float = 0.0
var _total: float = 0.0
var _i: int = -1


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot-tag="):
			tag = a.substr(11)
	print("[SmokeEscala] start (%d places x 2 zooms, tag=%s)" % [PLACES.size(), tag])


func _process(delta: float) -> void:
	_t += delta
	_total += delta
	if _total > timeout:
		print("[SmokeEscala] TIMEOUT at shot %d" % _i)
		get_tree().quit(1)
		return
	if _i == -1:
		if _t > 0.5:
			var r := NewGame.from_scenario("town_e_start")
			for id: String in POSES:
				if r["state"].characters.has(id):
					r["state"].characters[id]["position"] = POSES[id]
					r["state"].characters[id]["path"] = []
			Game.start(r["state"])
			Game.set_paused(true)
			app.world().select("chr_0001")
			_next()
		return
	if _t > 0.8:
		var sfx := ("_" + tag) if tag != "" else ""
		if _i == PLACES.size() * 2:
			app.save_shot("escala_forja_mejoras_z2" + sfx)
		else:
			var place: Array = PLACES[_i / 2]
			app.save_shot("escala_%s_z%d%s" % [place[0], 1 + _i % 2, sfx])
		_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	if _i == PLACES.size() * 2:
		# the forge with every upgrade done (capture only: the state is edited), its wall overlays on the taller sprite
		var r := NewGame.from_scenario("forge_upgrades")
		r["state"].buildings["bld_0001"]["upgrades"] = Game.sim.catalog.upgrade_tree("forge").map(
			func(u: Variant) -> String: return str((u as Dictionary).get("id", u)) if u is Dictionary else str(u))
		Game.start(r["state"])
		Game.set_paused(true)
		var cam2: WorldCamera = app.world().camera()
		cam2.zoom_index = 1
		cam2.center_on(app.world().building_visual("bld_0001").position + Vector2(0, -60))
		print("[SmokeEscala] forge with every upgrade")
		return
	if _i > PLACES.size() * 2:
		print("[SmokeEscala] done")
		get_tree().quit(0)
		return
	var place: Array = PLACES[_i / 2]
	var cam: WorldCamera = app.world().camera()
	cam.zoom_index = _i % 2
	cam.center_on(Iso.tile_to_world(place[1]))
	app.world().select(str(place[2]))
	print("[SmokeEscala] camera on %s %s zoom x%d" % [place[0], place[1], cam.current_zoom()])
