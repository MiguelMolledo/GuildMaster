class_name BuildLayer3D
extends BuildLayer
## H6's building mode (04 §4.9) over the 3D town (docs/3d/plan.md): the same plots, colours, labels and hover as the
## 2D BuildLayer, each plot drawn as its ground rectangle projected with the town's camera every frame (over the
## houses, as the 2D one is drawn over the map) and its label over its middle. WorldView3D picks the plot under a
## click with plot_at(tile_under(...)). It sits on its own canvas layer under the town's marks; it reads only.

const GROUND_LIFT: float = 0.05   # metres over the ground
const SIG_EVERY: float = 0.5      # seconds between looks at what stands in the town (a build, a demolition...)

var view: WorldView3D = null
var _sig: String = ""
var _sig_t: float = 0.0


func refresh() -> void:
	super()
	_sig = _signature()
	for l: Label in _labels.values():
		l.visible = false   # placed over the plot's 3D middle while the mode is on (_process)


func _process(delta: float) -> void:
	if not visible or view == null or view.town == null:
		return
	_sig_t += delta
	if _sig_t >= SIG_EVERY:
		_sig_t = 0.0
		if _signature() != _sig:
			ViewConfig.info("BuildLayer3D", "the town changed: plots again")
			refresh()
	set_hovered(plot_at(view.tile_under(get_viewport().get_mouse_position())))
	for p: Dictionary in plots:
		var l: Label = _labels.get(str(p["id"]))
		if l == null:
			continue
		var at := _screen(_middle(p))
		l.visible = at != Vector2.INF
		if l.visible:
			l.position = (at - Vector2(l.size.x / 2.0, l.size.y + 6.0)).round()
	queue_redraw()


## What makes the plots change: the buildings, their kind, owner and state.
func _signature() -> String:
	if sim == null:
		return ""
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for b: String in ids:
		var d: Dictionary = sim.state.buildings[b]
		parts.append("%s:%s:%s:%s" % [b, d.get("type", ""), d.get("owner", ""), d.get("state", "")])
	return ",".join(parts)


func _screen(p: Vector3) -> Vector2:
	if view.town.cam.is_position_behind(p):
		return Vector2.INF
	return view.town.cam.unproject_position(p)


func _middle(p: Dictionary) -> Vector3:
	var o: Array = p.get("origin", [0, 0])
	var s: Array = p.get("size", [1, 1])
	return Vector3((float(o[0]) + float(s[0]) / 2.0) * 2.0, GROUND_LIFT, (float(o[1]) + float(s[1]) / 2.0) * 2.0)


func _draw() -> void:
	if view == null or view.town == null:
		return
	for p: Dictionary in plots:
		var col := colour_of(p)
		var o: Array = p.get("origin", [0, 0])
		var s: Array = p.get("size", [1, 1])
		var x0 := float(o[0]) * 2.0
		var z0 := float(o[1]) * 2.0
		var x1 := (float(o[0]) + float(s[0])) * 2.0
		var z1 := (float(o[1]) + float(s[1])) * 2.0
		var pts := PackedVector2Array()
		for c: Vector3 in [Vector3(x0, GROUND_LIFT, z0), Vector3(x1, GROUND_LIFT, z0), Vector3(x1, GROUND_LIFT, z1),
				Vector3(x0, GROUND_LIFT, z1)]:
			var sp := _screen(c)
			if sp == Vector2.INF:
				break
			pts.append(sp)
		if pts.size() < 4:
			continue
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, Color(col.r, col.g, col.b, 1.0), 3.0 if str(p["id"]) == hovered else 1.5, true)
