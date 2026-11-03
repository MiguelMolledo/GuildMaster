extends Node
## Fondos para las maquetas de la UI (docs/ui/): el juego real sin HUD, con la cámara en unos sitios y a unas horas.
## Es una herramienta, no parte del juego: monta game/app.tscn dentro de esta escena, la pausa, oculta el HUD (y los
## letreros si se pide) y guarda docs/ui/maquetas/fondos/<nombre>.png a 960×540. Siempre por la cola:
##   grimoire heavy --timeout 3m -- /opt/homebrew/bin/godot --audio-driver Dummy --always-on-top --path . \
##     res://tools/ui/captura_fondos.tscn -- --scenario=town_e_start
## La luz del día solo cambia bien si la partida empieza a esa hora: para las tomas de atardecer o noche, --at=HH:MM y
## --solo=<nombre> (p. ej. -- --scenario=town_e_start --at=20:30 --solo=titulo_atardecer). Hora "" = no tocar el reloj.

## [nombre, casilla del centro, hora "HH:MM", letreros visibles, interior (id de edificio o "")]
const SHOTS: Array = [
	["mapa_dia", Vector2i(22, 16), "11:00", true, ""],
	["plaza_dia", Vector2i(19, 17), "12:00", true, ""],
	["titulo_atardecer", Vector2i(20, 15), "", false, ""],
	["titulo_dia", Vector2i(20, 15), "09:30", false, ""],
	["rio_atardecer", Vector2i(33, 19), "", false, ""],
	["forja_interior", Vector2i(0, 0), "11:00", true, "bld_0001"],
]

var app: Node = null
var _t: float = 0.0
var _i: int = -1


var _only: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--solo="):
			_only = a.substr(7)
	app = (load("res://game/app.tscn") as PackedScene).instantiate()
	add_child(app)


func _process(delta: float) -> void:
	_t += delta
	if _i == -1:
		if _t > 1.0:
			Game.set_paused(true)
			_next()
		return
	(app.call("hud") as CanvasLayer).visible = false
	var ui := (app.call("interior") as Node).get_node_or_null("Ui") as CanvasLayer   # título y barra del interior
	if ui != null:
		ui.visible = false
	Game.set_paused(_t > 1.2)   # corre un momento para que el interior y la gente se pongan al día
	_signs_visible(bool(SHOTS[_i][3]))
	if _t > 2.0:
		var img := get_viewport().get_texture().get_image()
		var dir := ProjectSettings.globalize_path("res://docs/ui/maquetas/fondos")
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir.path_join(str(SHOTS[_i][0]) + ".png")
		img.save_png(path)
		print("[CapturaFondos] %s %s" % [path, img.get_size()])
		_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	while _only != "" and _i < SHOTS.size() and str(SHOTS[_i][0]) != _only:
		_i += 1
	if _i >= SHOTS.size():
		get_tree().quit()
		return
	var s: Array = SHOTS[_i]
	if str(s[2]) != "":
		var hm := str(s[2]).split(":")
		Game.set_time_of_day(Game.sim.state, hm[0].to_int() * 60 + hm[1].to_int())
	if str(s[4]) != "":
		app.call("open_interior", str(s[4]), true)
	else:
		var cam: Node = app.call("world").call("camera")
		cam.call("center_on", Iso.tile_to_world(s[1]))


func _signs_visible(on: bool) -> void:
	var signs: Dictionary = app.call("world").get("_signs")
	for k: String in signs:
		(signs[k] as CanvasItem).visible = on
	var service: Dictionary = app.call("world").get("_service_signs")
	for k: String in service:
		(service[k] as CanvasItem).visible = on
