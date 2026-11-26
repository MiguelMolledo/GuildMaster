class_name Marks3D
extends CanvasLayer
## The marks of the 3D town (docs/3d/plan.md M3D-2), drawn on a canvas layer under the HUD at the point of the 3D
## world they belong to (projected every frame), so they keep the 2D game's look and letters at any zoom:
## - the signs of the sim's buildings (BuildingMarks.Sign, the 2D board: SimQuery.building_label, the colour of
##   data/view.json buildings.<type>.sign; sign_mode "hover" only while the mouse is over the building or it is
##   picked) and of the map's services (the stalls, the board, the town hall: data/view.json services);
## - the building under the mouse: its sign lit and a frame on the ground around its footprint (3D, in the town);
## - the person under the mouse: a pale ring under the feet and the name (the selected one keeps both, in gold).
## Reads the state and the town; decides nothing.

const SIGN_LIFT: float = 1.4         # metres over a house's top
const SERVICE_LIFT: float = 2.9      # metres over the ground of a stall / the board
const FRAME_W: float = 0.14          # the hover frame's width (m)

var view: WorldView3D = null
var hovered_building: String = ""
var hovered_character: String = ""
var _signs: Dictionary = {}       # bld id | "svc:<id>" -> BuildingMarks.Sign
var _points: Dictionary = {}      # the same key -> Vector3 where it hangs
var _hover_only: Dictionary = {}  # bld id -> true (sign_mode "hover")
var _frame: MeshInstance3D = null
var _frame_of: String = ""
var _hover_ring: MeshInstance3D = null


func _init() -> void:
	layer = 1  # over the town, under the HUD (10) and the cards


## The signs of the town just built (`view.town`, `view.sim`).
func build() -> void:
	for n: Node in get_children():
		remove_child(n)
		n.queue_free()
	_signs.clear()
	_points.clear()
	_hover_only.clear()
	_frame = null
	_frame_of = ""
	_hover_ring = null
	hovered_building = ""
	hovered_character = ""
	var town := view.town
	if town == null:
		return
	var st := view.sim.state
	var cat := view.sim.catalog
	var looks: Dictionary = ViewConfig.value("buildings", {})
	for b: String in st.buildings:
		if not town.bld_anchor.has(b):
			continue
		var look: Dictionary = looks.get(str(st.buildings[b].get("type", "")), {})
		var sg := BuildingMarks.Sign.new()
		sg.name = "sign_" + b
		add_child(sg)
		sg.setup(SimQuery.building_label(st, cat, b), ViewConfig.color(str(look.get("sign", "#e0903a"))))
		_signs[b] = sg
		_points[b] = (town.bld_anchor[b].top as Vector3) + Vector3(0, SIGN_LIFT, 0)
		if str(look.get("sign_mode", "")) == "hover":
			_hover_only[b] = true
	var svc_looks: Dictionary = ViewConfig.value("services", {})
	for svc: Dictionary in SimQuery.map_services(st, cat):
		var kind := str(svc["kind"])
		var id := str(svc["id"])
		var key := "svc:" + id
		if _signs.has(key):
			continue
		var sg := BuildingMarks.Sign.new()
		sg.name = "service_" + id
		add_child(sg)
		var text := SimQuery.stall_name(cat, id) if kind == "stall" else SimQuery.t_("ui.%s.sign" % kind)
		sg.setup(text, ViewConfig.color(str(svc_looks.get(kind + "_sign", "#d8c8a0"))))
		_signs[key] = sg
		var t: Vector2i = svc["tile"]
		_points[key] = Vector3(t.x * 2.0 + 1.0, SERVICE_LIFT, t.y * 2.0 + 1.0)
	ViewConfig.info("Marks3D", "built (%d building signs, %d hover only, %d service signs)" % [
		_signs.size() - _count_services(), _hover_only.size(), _count_services()])


func _count_services() -> int:
	var n := 0
	for k: String in _signs:
		if k.begins_with("svc:"):
			n += 1
	return n


## Every frame: where each sign hangs on screen, what the mouse is over, the frame and the rings.
func update(mouse: Vector2, mouse_in_town: bool) -> void:
	var town := view.town
	if town == null or not view.visible:
		visible = false
		return
	visible = true
	var b := view.building_under(mouse) if mouse_in_town else ""
	var who := ""
	if mouse_in_town:
		who = view.pick_person(mouse, true)
		if who == "":
			who = view.pick_person(mouse, false)
	hovered_building = b if who == "" else ""
	hovered_character = who
	var rect := get_viewport().get_visible_rect().grow(40.0)
	for k: String in _signs:
		var sg: BuildingMarks.Sign = _signs[k]
		var p: Vector3 = _points[k]
		var shown := not _hover_only.has(k) or k == hovered_building or k == view.picked_building
		if shown and not town.cam.is_position_behind(p):
			var at := town.cam.unproject_position(p)
			sg.visible = rect.has_point(at)
			sg.position = at.round()
		else:
			sg.visible = false
		sg.highlighted = k == hovered_building or k == view.picked_building
	_update_frame()
	_update_hover_ring()
	town.name_shown = {}
	for id: String in [hovered_character, view.selected_id]:
		if id != "":
			town.name_shown[id] = true


func sign_of(key: String) -> BuildingMarks.Sign:
	return _signs.get(key, null)


func sign_shown(key: String) -> bool:
	var sg: BuildingMarks.Sign = _signs.get(key, null)
	return sg != null and sg.visible


## The frame on the ground around the footprint of the building under the mouse (or the picked one).
func _update_frame() -> void:
	var town := view.town
	var b := hovered_building if hovered_building != "" else view.picked_building
	if b == "" or not view.sim.state.buildings.has(b):
		if _frame != null and is_instance_valid(_frame):
			_frame.visible = false
		return
	if _frame == null or not is_instance_valid(_frame) or _frame.get_parent() != town:
		_frame = MeshInstance3D.new()
		_frame.name = "HoverFrame"
		_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.92, 0.6)
		_frame.material_override = mat
		town.add_child(_frame)
		_frame_of = ""
	if _frame_of != b:
		_frame_of = b
		var d: Dictionary = view.sim.state.buildings[b]
		var o: Array = d.get("origin", [0, 0])
		var f: Array = d.get("footprint", [1, 1])
		var x0 := float(o[0]) * 2.0
		var z0 := float(o[1]) * 2.0
		var x1 := x0 + float(f[0]) * 2.0
		var z1 := z0 + float(f[1]) * 2.0
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for seg: Array in [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x1, z0), Vector2(x1, z1)],
				[Vector2(x1, z1), Vector2(x0, z1)], [Vector2(x0, z1), Vector2(x0, z0)]]:
			_strip(st, seg[0], seg[1])
		_frame.mesh = st.commit()
	_frame.visible = true


func _strip(st: SurfaceTool, a: Vector2, b: Vector2) -> void:
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x) * FRAME_W
	var a2 := a - dir * FRAME_W
	var b2 := b + dir * FRAME_W
	var y := 0.07
	var q := [Vector3(a2.x - n.x, y, a2.y - n.y), Vector3(b2.x - n.x, y, b2.y - n.y),
		Vector3(b2.x + n.x, y, b2.y + n.y), Vector3(a2.x + n.x, y, a2.y + n.y)]
	for i: int in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:  # both faces
		st.add_vertex(q[i])


## A pale ring under the person under the mouse (not the selected one: that one has the gold ring).
func _update_hover_ring() -> void:
	var town := view.town
	if _hover_ring == null or not is_instance_valid(_hover_ring) or _hover_ring.get_parent() != town:
		_hover_ring = MeshInstance3D.new()
		_hover_ring.name = "HoverRing"
		var m := TorusMesh.new()
		m.inner_radius = 0.44
		m.outer_radius = 0.52
		_hover_ring.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.97, 0.88, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hover_ring.material_override = mat
		_hover_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		town.add_child(_hover_ring)
	var id := hovered_character
	var n: Node3D = town.people[id].node if id != "" and id != view.selected_id and town.people.has(id) else null
	_hover_ring.visible = n != null and n.visible
	if _hover_ring.visible:
		_hover_ring.position = n.position + Vector3(0, 0.05, 0)
