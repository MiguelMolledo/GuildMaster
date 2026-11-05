class_name UpgradePreview
extends SubViewportContainer
## «What you will see» of an upgrade (docs/ui/mecanicas/mejoras.md §4, the owner's ask: the tree shows what changes in
## the building): a small render of the building with its finished upgrades, and the chosen one shown and lit in gold
## (a slow pulse) when it is not built yet. Interior upgrades (visual.interior_node, or a new_zone station) are drawn on
## the room of game/visuals/interiors/<type>.tscn; exterior ones (visual.exterior_overlay) on the building of
## game/visuals/buildings/<type>.tscn. An upgrade with nothing to draw shows the room as it is and says so (side()).
## Also gives the thumbnail of each upgrade for the tree's cells (thumbnail()): the sprite of its node, or null.
## Reads only the sim (SimQuery.upgrade_visual_nodes, the building's zones) and the catalog; gives no orders.

const GOLD := Color(1.0, 0.85, 0.35)
const PULSE_SECONDS: float = 0.6          # each half of the pulse
const MAX_PULSE_TIME_SCALE: float = 8.0   # above it the lit node stays gold without pulsing

var sim: Sim
var building: String = ""
var upgrade: String = ""
var _side: String = ""            # "interior" | "exterior" | "" (nothing to draw)
var _vp: SubViewport = null
var _cam: Camera2D = null
var _rooms: Dictionary = {}       # side -> Node2D instance
var _thumbs: Dictionary = {}      # upgrade -> Texture2D (or null)
var _lit: Node2D = null
var _tween: Tween = null


func _ensure() -> void:
	if _vp != null:
		return
	stretch = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_vp = SubViewport.new()
	_vp.name = "View"
	_vp.transparent_bg = true
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	_cam = Camera2D.new()
	_cam.name = "Camera"
	_vp.add_child(_cam)


func setup(s: Sim, bld: String) -> void:
	_ensure()
	if s != sim or bld != building:
		for k: String in _rooms:
			(_rooms[k] as Node).queue_free()
		_rooms.clear()
		_thumbs.clear()
	sim = s
	building = bld


func _type() -> String:
	return str(sim.state.buildings.get(building, {}).get("type", ""))


## Where `id` is drawn: "interior" (an interior node or a new station), "exterior" (an overlay) or "" (nothing).
func side_of(id: String) -> String:
	var u := sim.catalog.upgrade(id)
	var v: Dictionary = u.get("visual", {})
	if v.get("interior_node", null) != null or not _new_zone(id).is_empty():
		return "interior"
	if v.get("exterior_overlay", null) != null:
		return "exterior"
	return ""


func side() -> String:
	return _side


func _new_zone(id: String) -> String:
	for e: Dictionary in sim.catalog.upgrade(id).get("effects", []):
		if str(e.get("kind", "")) == "new_zone":
			return str(e.get("zone", ""))
	return ""


func _room(side_: String) -> Node2D:
	if _rooms.has(side_):
		return _rooms[side_]
	var n := InteriorBuilder.instantiate(_type()) if side_ == "interior" else VisualPaths.instantiate("buildings", _type())
	n.name = side_.capitalize()
	_vp.add_child(n)
	var kit := n.get_node_or_null("Kit")
	if kit != null and kit.has_method("ensure_built"):
		kit.call("ensure_built")
	_rooms[side_] = n
	return n


## Shows `id` (the room with the finished upgrades, `id` lit if it is not built yet).
func show_upgrade(id: String) -> void:
	_ensure()
	upgrade = id
	_side = side_of(id)
	var draw_side := _side if _side != "" else "interior"
	for k: String in ["interior", "exterior"]:
		if _rooms.has(k):
			(_rooms[k] as Node2D).visible = k == draw_side
	var room := _room(draw_side)
	room.visible = true
	_unlight()
	var on := {}
	for n: String in SimQuery.upgrade_visual_nodes(sim, building, draw_side):
		on[n] = true
	var owned := Upgrades.has(sim.state, building, id)
	var node_name := str(sim.catalog.upgrade(id).get("visual", {}).get(
		"interior_node" if draw_side == "interior" else "exterior_overlay", ""))
	var ups := room.get_node_or_null("Upgrades")
	if ups != null:
		for u: Node in ups.get_children():
			if u is Node2D:
				(u as Node2D).visible = on.has(str(u.name)) or str(u.name) == node_name
				(u as Node2D).modulate = Color.WHITE
	var zones: Dictionary = sim.state.buildings.get(building, {}).get("zones", {})
	var nz := _new_zone(id)
	var st := room.get_node_or_null("Stations")
	if st != null:
		for m: Node in st.get_children():
			if m is Node2D:
				(m as Node2D).visible = zones.has(str(m.name)) or str(m.name) == nz
				(m as Node2D).modulate = Color.WHITE
	if not owned and _side != "":
		var lit: Node2D = null
		if nz != "" and st != null:
			lit = st.get_node_or_null(nz) as Node2D
		if lit == null and ups != null and node_name != "":
			lit = ups.get_node_or_null(node_name) as Node2D
		_light(lit)
	_frame(room, draw_side)
	ViewConfig.info("UpgradePreview", "show %s (side=%s, owned=%s, lit=%s)" % [id, _side, owned, _lit != null])


## The node lit in gold now (null when the upgrade is built or has nothing to draw): tests.
func lit() -> Node2D:
	return _lit


func _light(n: Node2D) -> void:
	_lit = n
	if n == null:
		return
	n.modulate = GOLD
	if is_inside_tree() and pulse_allowed(n, Engine.time_scale):
		# bound to the node: it stops while the node is out of the tree and dies with it (a room freed by setup()
		# left an endless loop of zero length behind: «Infinite loop detected»)
		_tween = create_tween().bind_node(n).set_loops()
		_tween.tween_property(n, "modulate", Color(1.35, 1.2, 0.7), PULSE_SECONDS)
		_tween.tween_property(n, "modulate", GOLD, PULSE_SECONDS)


## Whether the gold pulse may run on `n`: it is in the tree and time is not sped up so much that a whole loop would fit
## in one frame (then it stays lit, still).
static func pulse_allowed(n: Node, time_scale: float) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree() and time_scale > 0.0 and time_scale <= MAX_PULSE_TIME_SCALE


func _unlight() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if _lit != null and is_instance_valid(_lit):
		_lit.modulate = Color.WHITE
	_lit = null


## Centres and zooms the camera on the room (interior: the kit's floor and walls) or the building's sprite.
func _frame(room: Node2D, side_: String) -> void:
	var r := Rect2()
	if side_ == "interior":
		var kit := room.get_node_or_null("Kit")
		var sz: Vector2i = kit.get("size") if kit != null else Vector2i(6, 6)
		var wall_h := float(kit.get("wall_height")) if kit != null else 36.0
		var left := Iso.tile_to_world(Vector2i(0, sz.y - 1)).x - Iso.TILE_W / 2.0
		var right := Iso.tile_to_world(Vector2i(sz.x - 1, 0)).x + Iso.TILE_W / 2.0
		var top := Iso.tile_to_world(Vector2i.ZERO).y - Iso.TILE_H / 2.0 - wall_h
		var bottom := Iso.tile_to_world(sz - Vector2i.ONE).y + Iso.TILE_H / 2.0
		r = Rect2(left, top, right - left, bottom - top)
	else:
		var sp := room.get_node_or_null("Sprite") as Sprite2D
		if sp != null and sp.texture != null:
			r = Rect2(sp.position + sp.offset, sp.texture.get_size())
		else:
			r = Rect2(-96, -160, 192, 200)
	var view := Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	if custom_minimum_size.x > 0.0:
		view = custom_minimum_size
	var z := minf(view.x / maxf(r.size.x, 1.0), view.y / maxf(r.size.y, 1.0)) * 0.95
	var at := r.get_center()
	if _lit != null and side_ == "interior":   # closer, between the room's centre and the new piece
		at = at.lerp(_lit.global_position + Vector2(0, -16), 0.6)
		z *= 1.7
	_cam.position = at.round()
	_cam.zoom = Vector2.ONE * z


## The thumbnail of `id` for the tree's cell: the first sprite of its interior node, its new station or its exterior
## overlay; null when it has none (the cell shows the branch's icon).
func thumbnail(id: String) -> Texture2D:
	_ensure()
	if _thumbs.has(id):
		return _thumbs[id]
	var tex: Texture2D = null
	var v: Dictionary = sim.catalog.upgrade(id).get("visual", {})
	var nz := _new_zone(id)
	if nz != "":
		tex = _first_texture(_room("interior").get_node_or_null("Stations/" + nz))
	if tex == null and v.get("interior_node", null) != null:
		tex = _first_texture(_room("interior").get_node_or_null("Upgrades/" + str(v["interior_node"])))
	if tex == null and v.get("exterior_overlay", null) != null:
		tex = _first_texture(_room("exterior").get_node_or_null("Upgrades/" + str(v["exterior_overlay"])))
	for k: String in _rooms:
		(_rooms[k] as Node2D).visible = k == (_side if _side != "" else "interior") and upgrade != ""
	_thumbs[id] = tex
	return tex


func _first_texture(n: Node) -> Texture2D:
	if n == null:
		return null
	if n is Sprite2D and (n as Sprite2D).texture != null:
		return (n as Sprite2D).texture
	for c: Node in n.get_children():
		var t := _first_texture(c)
		if t != null:
			return t
	return null
