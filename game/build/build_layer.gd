class_name BuildLayer
extends Node2D
## H6 · the building mode on the town map (docs/gdd/04_diseno_de_juego.md §4.9: «el mapa resalta las parcelas —
## verde rústica, naranja producción, azul vivienda, gris ocupada»). While it is on, every plot of the map (Plots.all)
## is drawn over the ground as its tiles in its zone's colour (grey when something stands on it, but the family's
## own in its zone's colour with a border), the one under the mouse brighter, with a small label (a free lot, a ruin,
## a building of whom). The town view picks the plot under a click (plot_at) and the HUD opens its card (PlotCard).
## Colours in data/view.json "build_mode" (with these defaults).

const DEFAULTS: Dictionary = {"rustic": "#6fae4a", "production": "#e0903a", "housing": "#5a8ccf", "taken": "#8a8a8a",
	"alpha": 0.42, "hover_alpha": 0.7}

var world: Node = null
var sim: Sim = null
var plots: Array = []          # Plots.all at the last refresh
var hovered: String = ""       # plot id under the mouse
var family: String = ""        # the player's family: its own buildings keep their zone's colour
var _labels: Dictionary = {}   # plot id -> Label


func setup(w: Node, s: Sim, fam: String) -> void:
	world = w
	sim = s
	family = fam
	name = "BuildLayer"
	z_index = 5
	visible = false
	refresh()


## Reads the plots again (after a build, a demolition...) and redraws.
func refresh() -> void:
	plots = Plots.all(sim) if sim != null else []
	for l: Node in _labels.values():
		if is_instance_valid(l):
			l.queue_free()
	_labels.clear()
	for p: Dictionary in plots:
		var l := Label.new()
		l.text = label_of(p)
		WorldLabels.style(l, "flash")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.name = "plot_label_" + str(p["id"])
		l.reset_size()
		var mid := _centre(p)
		l.position = (mid - Vector2(l.size.x / 2.0, l.size.y + 6.0)).round()
		add_child(l)
		_labels[str(p["id"])] = l
	queue_redraw()


## What a plot's label says: «Solar 3×3», «Ruina 3×3», the building's name (and «en obra»).
func label_of(p: Dictionary) -> String:
	var s: Array = p.get("size", [0, 0])
	var dims := "%d×%d" % [int(s[0]), int(s[1])]
	match str(p.get("kind", "")):
		"lot":
			return SimQuery.t_("ui.plots.label.lot") % dims
		"ruin":
			return SimQuery.t_("ui.plots.label.ruin") % dims
	var bld := str(p.get("building", ""))
	var name_ := SimQuery.building_label(sim.state, sim.catalog, bld) if sim != null and bld != "" else ""
	if sim != null and str(sim.state.buildings.get(bld, {}).get("state", "")) == "construction":
		return SimQuery.t_("ui.plots.label.works") % name_
	return name_


func set_on(on: bool) -> void:
	if on:
		refresh()
	visible = on
	ViewConfig.info("BuildLayer", "modo construcción %s (%d parcelas)" % ["on" if on else "off", plots.size()])


## The plot whose tiles hold `tile` ("" if none).
func plot_at(tile: Vector2i) -> String:
	for p: Dictionary in plots:
		var o: Array = p.get("origin", [0, 0])
		var s: Array = p.get("size", [1, 1])
		if tile.x >= int(o[0]) and tile.y >= int(o[1]) and tile.x < int(o[0]) + int(s[0]) and tile.y < int(o[1]) + int(s[1]):
			return str(p["id"])
	return ""


func set_hovered(id: String) -> void:
	if id != hovered:
		hovered = id
		queue_redraw()


func colour_of(p: Dictionary) -> Color:
	var cfg: Dictionary = DEFAULTS.duplicate()
	cfg.merge(ViewConfig.value("build_mode", {}), true)
	var key := str(p.get("zone", "production"))
	if str(p.get("kind", "")) == "building" and str(p.get("owner", "")) != family:
		key = "taken"
	var c := Color(str(cfg.get(key, "#888888")))
	c.a = float(cfg["hover_alpha"] if str(p["id"]) == hovered else cfg["alpha"])
	return c


func _draw() -> void:
	for p: Dictionary in plots:
		var col := colour_of(p)
		for t: Vector2i in PlotLayer.tiles_of(p):
			var c := Iso.tile_to_world(t)
			var hw := Iso.TILE_W / 2.0
			var hh := Iso.TILE_H / 2.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -hh), c + Vector2(hw, 0), c + Vector2(0, hh),
				c + Vector2(-hw, 0)]), col)
		var o: Array = p.get("origin", [0, 0])
		var s: Array = p.get("size", [1, 1])
		var a := Iso.tile_to_world(Vector2i(int(o[0]), int(o[1]))) + Vector2(0, -Iso.TILE_H / 2.0)
		var b := Iso.tile_to_world(Vector2i(int(o[0]) + int(s[0]) - 1, int(o[1]))) + Vector2(Iso.TILE_W / 2.0, 0)
		var c2 := Iso.tile_to_world(Vector2i(int(o[0]) + int(s[0]) - 1, int(o[1]) + int(s[1]) - 1)) + Vector2(0, Iso.TILE_H / 2.0)
		var d := Iso.tile_to_world(Vector2i(int(o[0]), int(o[1]) + int(s[1]) - 1)) + Vector2(-Iso.TILE_W / 2.0, 0)
		var edge := Color(col.r, col.g, col.b, 1.0)
		draw_polyline(PackedVector2Array([a, b, c2, d, a]), edge, 3.0 if str(p["id"]) == hovered else 1.5, true)


func _centre(p: Dictionary) -> Vector2:
	var mid := Vector2.ZERO
	var tiles := PlotLayer.tiles_of(p)
	for t: Vector2i in tiles:
		mid += Iso.tile_to_world(t)
	return mid / maxf(1.0, float(tiles.size()))
