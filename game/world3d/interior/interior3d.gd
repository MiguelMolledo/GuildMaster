extends Node3D
## The forge interior in 3D, built from GuildMaster's data/interiors/forge.json (copied to res://data/view3d/interiors)
## by Interior3DBuilder, with people working inside (CharBuilder), zones you can hover and select, a day/night
## switch and a cutaway camera that turns in 90 degree steps.
## Run: godot --path . res://interior.tscn -- [--shots] [--bench] [--upgrades]
## Keys: Q/E turn 90, wheel zoom, right/middle drag pan, Tab upper floor, C cutaway mode, N night, click a zone.
## Embedded (interior_villa.gd): `embedded = true`, then setup(); activate(true/false) switches camera and light,
## Esc / F asks to leave (signal exit_requested).

signal exit_requested

const DATA := "res://data/view3d/interiors/forge.json"
const BUILDING := "res://data/view3d/interiors/forge_building.json"
const SHOTS_DIR := "/Users/miguelmolledo/.grimoire/workspace/channels/ch_01m6abhw3phgxh2509d0/files/prueba3d/"
const ZONE_NAMES := {"furnace": "Fragua", "anvil": "Yunque", "counter": "Mostrador", "storage": "Almacén"}
const KIND_NAMES := {"craft": "producción", "sales": "venta", "storage": "almacén", "home": "vivienda", "service": "servicio", "rest": "descanso"}
const WALK_SPEED := 1.25
const WALK_CLIP := 1.02  # m/s the Walk clip covers at scale 1 (tools/anim_speed.gd: 2 x stride / cycle)
static var SMITH_ANIMS := ["Interact", "PickUp_Table"]  # furnace, anvil

var embedded := false
## In place (docs/interior3d.md, «Interior en sitio»): this node is a child of the house of the town it is the inside
## of (same local frame), built from `data_path` (a compact interior with "shell"). No camera, sun, sky or ground of
## its own: `town` (sim3d_chars.gd) has them and drives the cut of the house (SituCut); here are the pieces, the
## partitions, the lights, the people and the zones.
var situ := false
var town: Node
var data_path := DATA
var data_opts := {}  # Interior3DBuilder's: mirror, upgrades
var stats := {"frames": 0, "min_gap": 99.0, "close_frames": 0, "min_clear": 99.0, "inside_frames": 0, "waits": 0, "repaths": 0, "pushes": 0, "wait_s": 0.0, "walk_s": 0.0, "trips": 0}
var keep_visible := false  # in place: the pieces and lights stay drawn when the house is closed (the forge fire through the shop window)
var live := false  # the people come from the sim (live_sync) instead of the scripted smith/apprentice/keeper/customer
var active := true
var B: Interior3DBuilder
var interior: Node3D
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var yaw := 45.0
var yaw_goal := 45.0
var pitch := 38.0
var target := Vector3(10, 0.8, 8)
var top := 0
var mode := "down"
var night := false
var people: Array = []  # actor dictionaries
var hover_zone := ""
var sel_zone := ""
var mouse_room := ""
var zone_kind := {}
var forge_lights: Array[OmniLight3D] = []
var extra_lights: Array = []  # [light, day energy, night energy]
var _hl := {}  # zone -> {node, mat, label}
var _ui: CanvasLayer
var _panel: PanelContainer
var _panel_label: Label
var _help: Label
var _t := 0.0
var _customer_looks: Array = []
var _customer_i := 0
var _smith_items := {}
var _anvil_ingot: MeshInstance3D


func dbg(msg: String) -> void:
	if OS.is_debug_build():
		print("[Interior3D] " + msg)


func _ready() -> void:
	if not embedded:
		setup()
		var args := OS.get_cmdline_user_args()
		if "--shots" in args:
			_shots()
		elif "--bench" in args:
			_bench()
		elif "--animtest" in args:
			_animtest()


func setup() -> void:
	var t0 := Time.get_ticks_usec()
	B = Interior3DBuilder.new(data_path, "res://data/view3d/interiors/props_catalog.json", "res://data/view3d/interiors/lights.json", data_opts)
	for z in JSON.parse_string(FileAccess.get_file_as_string(BUILDING)).zones:
		zone_kind[z.id] = z.kind
	for z in B.d.get("stations", {}):  # an interior that names its own zones (every building but the forge)
		if (B.d.stations[z] as Dictionary).has("kind"):
			zone_kind[z] = B.d.stations[z].kind
	if situ:
		B.wall_shader = SituCut.shader("style" in town and String(town.style) != "pbr")
	else:
		_environment()
	interior = B.build()
	add_child(interior)
	if situ:
		cam = town.cam
		_town_style(interior)
	else:
		_ground()
	_forge_fire()
	_highlights()
	if not live:
		if B.d.has("cast"):
			_cast_people()
		else:
			_people()
	_build_ui()
	set_night(false)
	_update_camera()
	dbg("ready in %.0f ms (%d people)" % [(Time.get_ticks_usec() - t0) / 1000.0, people.size()])
	if embedded:
		activate(false)


# ------------------------------------------------------------------ world
func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_hdr_threshold = 1.1
	if not embedded:
		var we := WorldEnvironment.new()
		we.environment = env
		add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 24
	cam.far = 200
	cam.environment = env
	add_child(cam)


func _town_style(n: Node) -> void:
	## in place: the pieces take the shading of the town (toon, outline) so the inside does not look like another game
	if n is MeshInstance3D and n.mesh and town.has_method("_variant"):
		for i in n.mesh.get_surface_count():
			var m: Material = n.get_active_material(i)
			if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled == false and (m as StandardMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				# toon as the town, without its outline pass: a 7 cm hull swallows a chest or a stool seen from this close
				n.set_surface_override_material(i, town._variant(_matte(m), "pbr" if String(town.style) == "pbr" else "toon"))
	for c in n.get_children():
		_town_style(c)


var _mattes := {}


func _matte(m: StandardMaterial3D) -> StandardMaterial3D:
	## The Fantasy Props materials are fully metallic where their ORM map says iron (the cauldron, the hoops and straps
	## of a chest): with the town's toon shading and no sky to reflect they come out black. In place they are drawn as
	## dull painted iron instead: no metal, the same colour map.
	if String(town.style) == "pbr" or (m.metallic_texture == null and m.metallic < 0.5):
		return m
	var key := m.get_instance_id()
	if not _mattes.has(key):
		var v: StandardMaterial3D = m.duplicate()
		v.metallic = 0.0
		v.metallic_texture = null
		v.metallic_specular = 0.2
		_mattes[key] = v
	return _mattes[key]


func _ground() -> void:
	# grass around the building, not under it (the forge pit goes below ground level)
	var gm := ShaderMaterial.new()
	gm.shader = load("res://game/world3d/shaders/ground.gdshader")
	gm.set_shader_parameter("grass", load("res://kit/foliage/grass.png"))
	var w := B.W * B.TILE
	var h := B.H * B.TILE
	var m := 45.0
	for r in [Rect2(-m, -m, w + 2 * m, m), Rect2(-m, h, w + 2 * m, m), Rect2(-m, 0, m, h), Rect2(w, 0, m, h)]:
		var g := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = r.size
		g.mesh = pm
		g.material_override = gm
		g.position = Vector3(r.position.x + r.size.x / 2.0, -0.03, r.position.y + r.size.y / 2.0)
		add_child(g)
	# a path from the entrance outward
	var e: Dictionary = B.d.entrance
	var p := B.tile_pos(int(e.floor), Vector2i(e.tile[0], e.tile[1]))
	var path := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6, 0.02, 1.6)
	path.mesh = bm
	path.material_override = B._tri_mat("res://kit/streets/tierra_albedo.png", 0.35)
	path.position = Vector3(-3, -0.015, p.z)
	add_child(path)


func _forge_fire() -> void:
	for n in get_tree().get_nodes_in_group("station_piece"):
		if not is_ancestor_of(n):
			continue
		var z: String = n.get_meta("zone")
		if z.begins_with("furnace"):
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.5, 0.18)
			l.omni_range = 7.5
			l.omni_attenuation = 1.2
			l.shadow_enabled = true
			l.position = Vector3(0, 0.9, 0.6)
			if situ:
				# in the town its shadow pass draws every house piece in reach six times over: a shorter reach (the house
				# is 6 m) and two paraboloids instead of a cube
				l.omni_range = 6.0
				l.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
			n.add_child(l)
			forge_lights.append(l)
		elif z == "anvil":
			_anvil_ingot = B._box(n, Vector3(0.24, 0.05, 0.09), Vector3(0.12, 1.06, 0.0), B.smat("hot", Color(1.0, 0.42, 0.1), 0.0, 0.6, 4.0))
			_anvil_ingot.visible = false
	for fr: Dictionary in B.fires:  # hearths and ovens of the furniture at real scale: a warm light at their fire
		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.6, 0.28)
		fl.omni_range = 4.0
		fl.position = fr.at
		B.level_node(int(fr.floor)).add_child(fl)
		extra_lights.append([fl, 0.45, 1.8])
	for p in B.placed:
		if p.id == "candle_stand" or p.id == "kitchen_hearth" or p.id == "hearth_small":
			var l := OmniLight3D.new()
			var hearth: bool = p.id != "candle_stand"
			l.light_color = Color(1.0, 0.62, 0.3) if hearth else Color(1.0, 0.78, 0.45)
			l.omni_range = 4.5 if hearth else 3.5
			var at := B.pos_at(int(p.floor), Vector2(p.pos[0], p.pos[1])) if p.has("pos") else B.tile_pos(int(p.floor), Vector2i(p.tile[0], p.tile[1]))
			l.position = at + Vector3(0, 1.0 if hearth else 1.45, 0)
			B.level_node(int(p.floor)).add_child(l)
			extra_lights.append([l, 0.3 if hearth else 0.0, 1.6 if hearth else 1.1])


func set_night(on: bool) -> void:
	night = on
	if situ:
		pass  # the town has the sky and the sun
	elif on:
		env.background_color = Color(0.03, 0.04, 0.08)
		env.ambient_light_color = Color(0.3, 0.36, 0.6)
		env.ambient_light_energy = 0.22
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun.light_energy = 0.16
	else:
		env.background_color = Color(0.55, 0.65, 0.8)
		env.ambient_light_color = Color(0.62, 0.7, 0.92)
		env.ambient_light_energy = 0.65
		sun.light_color = Color(1.0, 0.94, 0.82)
		sun.light_energy = 1.35
	for rl in B.room_lights:
		var l: OmniLight3D = rl.light
		var a := float(rl.def.alpha)
		if l.light_negative:
			l.light_energy = a * (1.2 if on else 2.4)
		else:
			l.light_energy = a * (14.0 if on else 4.0)
	for e in extra_lights:
		(e[0] as OmniLight3D).light_energy = e[2] if on else e[1]
		(e[0] as OmniLight3D).visible = (e[2] if on else e[1]) > 0.0
	dbg("night %s" % on)


# ------------------------------------------------------------------ camera and cutaway
func _update_camera() -> void:
	if not situ:
		cam.rotation_degrees = Vector3(-pitch, yaw, 0)
		cam.position = target + cam.basis.z * 60.0  # cam is a child: local space
	_apply_cut()


func cam_plan_dir() -> Vector2:
	if situ:
		# the town's camera, in the frame of the house: local (x, z) from the house towards the camera
		var y := deg_to_rad(float(town.yaw))
		var loc := global_transform.basis.inverse() * Vector3(sin(y), 0, cos(y))
		return Vector2(loc.x, loc.z)
	return Vector2(sin(deg_to_rad(yaw_goal)), cos(deg_to_rad(yaw_goal)))


func _apply_cut() -> void:
	var focus := sel_zone if sel_zone != "" else hover_zone
	var room := mouse_room
	if focus != "":
		room = B.room_at(B.zones[focus].floor, B.zones[focus].tile)
	B.set_cutaway(cam_plan_dir(), mode, top, room)
	for p in people:
		p.node.visible = p.floor <= top and p.get("shown", true)
		var tag: Node3D = (p.node as Node).get_node_or_null("NameTag")
		if tag:
			tag.visible = p.floor == top  # a name drawn over everything must not show through the floor above


func set_top(f: int) -> void:
	top = clampi(f, B.floors[0], B.floors[-1])
	_apply_cut()
	dbg("showing up to floor %d" % top)


func set_mode(m: String) -> void:
	mode = m
	_apply_cut()
	dbg("cutaway mode %s" % m)


func turn(deg: float) -> void:
	yaw_goal = fposmod(yaw_goal + deg, 360.0)
	dbg("turn to yaw %.0f" % yaw_goal)
	_apply_cut()


func activate(on: bool) -> void:
	active = on
	if not situ:
		cam.current = on
		sun.visible = on
	_ui.visible = on
	interior.visible = on or (situ and keep_visible)
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		_update_camera()


# ------------------------------------------------------------------ people
func _people() -> void:
	var vill: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/view3d/chars/villagers.json")).villagers
	var by := {}
	for v in vill:
		by[v.name] = v
	var smith: Dictionary = by["Herrero"].duplicate(true)
	var appr := {"name": "Aprendiz", "sex": "m", "height": 0.93,
		"parts": {"torso": "peasant", "arms": "peasant", "legs": "peasant", "feet": "peasant", "hair": "hair_parted"},
		"paint": {"skin": "fair", "hair": "chestnut", "torso": ["marron", "negro"], "arms": "marron"}}
	var keeper: Dictionary = by["Mercader"].duplicate(true)
	keeper.name = "Tendera"
	for n in ["Noble", "Campesina", "Vieja", "Cazadora", "Guardia"]:
		if by.has(n):
			_customer_looks.append(by[n].duplicate(true))
	var sp: Dictionary = B.d.get("spots", {})
	var s := _actor(smith, "smith", "furnace", Vector2i(B.stand("furnace")))
	_smith_items = _smith_tools(s)
	_actor(appr, "apprentice", "storage", Vector2i(sp.apprentice[0], sp.apprentice[1]) if sp.has("apprentice") else Vector2i(4, 2))
	var k := _actor(keeper, "keeper", "counter", B.stand("counter"))
	_approach(k, "counter")
	var c := _actor(_customer_looks[0], "customer", "counter", Vector2i(-1, 6))
	if B.compact:
		c.state = "idle"
		c.timer = 1.0
		c.shown = false
		c.node.visible = false


func _actor(def: Dictionary, role: String, zone: String, tile: Vector2i) -> Dictionary:
	var d := def.duplicate(true)
	d.seed = people.size() * 13 + 5
	d.anim = "Idle"
	var n := CharBuilder.build(d)
	interior.add_child(n)
	var a := {"node": n, "ap": n.get_node("AnimationPlayer"), "name": String(def.name), "role": role, "zone": zone,
		"floor": 0, "tile": tile, "path": [], "task": 0, "timer": 0.0, "state": "idle", "doing": "", "shown": true}
	n.position = _tile_xyz(0, tile)
	people.append(a)
	dbg("actor %s (%s) at %s, parts %s" % [a.name, role, tile, n.get_meta("parts")])
	return a


func _tile_xyz(f: int, t: Vector2i) -> Vector3:
	return B.tile_pos(f, t)  # outside the rooms too (the street in front of the door)


func _skel(a: Dictionary) -> Skeleton3D:
	return a.node.get_node("Armature").get_child(0)


## Something held: a BoneAttachment3D on `bone`, the item placed in skeleton space at rest (so it follows the bone).
func _hold(a: Dictionary, bone: String, item: Node3D, at: Transform3D) -> BoneAttachment3D:
	var sk := _skel(a)
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	sk.add_child(ba)
	var rest := sk.get_bone_global_rest(sk.find_bone(bone))
	ba.add_child(item)
	item.transform = rest.affine_inverse() * at
	return ba


## A fist grip in skeleton space at rest: the handle runs along the knuckles (pinky -> index, local +z),
## local +y points along the fingers (where a hammer head or the tongs' jaws face).
func _grip(a: Dictionary, side: String) -> Transform3D:
	var sk := _skel(a)
	var at := func(b: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(b + "_" + side)).origin
	var hand: Vector3 = at.call("hand")
	var idx: Vector3 = at.call("index_01")
	var pinky: Vector3 = at.call("pinky_01")
	var mid: Vector3 = at.call("middle_01")
	var z := (idx - pinky).normalized()
	var y := (mid - hand)
	y = (y - z * y.dot(z)).normalized()
	var x := y.cross(z)
	var centre := (idx + pinky) * 0.5 * 0.55 + hand * 0.45
	return Transform3D(Basis(x, y, z), centre)


func _smith_tools(a: Dictionary) -> Dictionary:
	# hammer: handle through the fist (pointing forward at rest), head on top
	var hammer := Node3D.new()
	hammer.name = "Hammer"
	B._box(hammer, Vector3(0.035, 0.035, 0.42), Vector3(0, 0, 0.13), B.smat("wood", Color(0.36, 0.24, 0.15)))
	B._box(hammer, Vector3(0.075, 0.17, 0.08), Vector3(0, 0.02, 0.34), B.smat("iron", Color(0.25, 0.25, 0.28), 0.6, 0.45))
	var h := _hold(a, "hand_r", hammer, _grip(a, "r"))
	# tongs with a hot ingot in the left hand
	var tongs := Node3D.new()
	tongs.name = "Tongs"
	for s in [-1, 1]:
		var b := B._box(tongs, Vector3(0.02, 0.02, 0.5), Vector3(s * 0.018, 0, 0.2), B.smat("iron", Color(0.25, 0.25, 0.28), 0.6, 0.45))
		b.rotation.y = deg_to_rad(s * 2)
	var ingot := B._box(tongs, Vector3(0.09, 0.05, 0.2), Vector3(0, 0, 0.5), B.smat("hot", Color(1.0, 0.42, 0.1), 0.0, 0.6, 4.0))
	ingot.name = "Ingot"
	var t := _hold(a, "hand_l", tongs, _grip(a, "l"))
	return {"hammer": h, "tongs": t}


func _carry(a: Dictionary, on: bool) -> void:
	if on and not a.has("load"):
		var sk := _skel(a)
		var sh := sk.get_bone_global_rest(sk.find_bone("clavicle_r")).origin
		var crate: Node3D = load(Interior3DBuilder.QP % "Crate_Wooden").instantiate()
		crate.scale = Vector3.ONE * 0.55
		a.load = _hold(a, "spine_03", crate, Transform3D(Basis(Vector3.UP, 0.2), sh + Vector3(0.0, 0.02, -0.05)))
	elif not on and a.has("load"):
		a.load.queue_free()
		a.erase("load")


func _play(a: Dictionary, anim: String) -> void:
	## loops by hand (the shared animation library is not ours to change): _tick replays a.cur when it ends
	var ap: AnimationPlayer = a.ap
	if anim != "Walk":
		ap.speed_scale = float((a.node as Node3D).get_meta("base_speed", 1.0))
	if a.get("cur", "") != anim or not ap.is_playing():
		if (a.role == "live" or a.role == "cast") and _own_check():
			(CharBuilder as Script).call("play", a.node, anim, "", 0.25)  # also takes away the items of an own animation
		else:
			ap.play(anim, 0.25)
		a.cur = anim


func _face(a: Dictionary, dir: Vector2) -> void:
	a.face = atan2(dir.x, dir.y)


func _go(a: Dictionary, to: Vector2i, extra := {}) -> void:
	var from: Vector2i = a.tile
	var p := []
	if B.room_of[a.floor].has(from):
		p = B.path(a.floor, from, to, extra)
	else:
		# outside: walk to the entrance tile first (in place: by the street tile in front of the door and its threshold)
		var e: Dictionary = B.d.entrance
		var et := Vector2i(e.tile[0], e.tile[1])
		var inside: Array = B.path(a.floor, et, to, extra)
		if inside.is_empty():
			p = []
		elif B.compact:
			p = [from] + ([] if from == B.entrance_out(2) else [B.entrance_out(2)]) + [B.entrance_out(1)] + inside
		else:
			p = [from] + inside
	if p.is_empty():
		push_warning("[Interior3D] %s: no path %s -> %s" % [a.name, from, to])
		return
	p.pop_front()
	a.path = p
	a.state = "walk"
	dbg("%s walks %s -> %s (%d tiles)" % [a.name, from, to, p.size()])


func _process(delta: float) -> void:
	if B == null or _panel == null:
		return
	_t += delta
	if not situ and absf(yaw - yaw_goal) > 0.01:
		var dy := fposmod(yaw_goal - yaw + 180.0, 360.0) - 180.0
		yaw += clampf(dy, -240.0 * delta, 240.0 * delta)
		if absf(fposmod(yaw_goal - yaw + 180.0, 360.0) - 180.0) < 0.5:
			yaw = yaw_goal
		_update_camera()
	for l in forge_lights:
		var fl := 0.82 + 0.1 * sin(_t * 11.0) + 0.08 * sin(_t * 23.7 + 1.3)
		l.light_energy = (3.4 if night else 2.2) * fl
	for a in people:
		_tick(a, delta)
	if B.compact:
		_measure()
	if _panel.visible:
		_panel_label.text = _zone_text(sel_zone)


func _move(a: Dictionary, delta: float) -> bool:
	## true when the path is done
	if a.path.is_empty():
		return true
	var n: Node3D = a.node
	var ws: float = a.get("walk_speed", WALK_SPEED)
	var stepd := ws * delta
	if a.path[0] is Vector3:
		# a free point (the street, the flight of stairs): straight to it, the height with the way
		var g3: Vector3 = a.path[0]
		var f3 := Vector3(g3.x - n.position.x, 0, g3.z - n.position.z)
		_play(a, "Walk")
		(a.ap as AnimationPlayer).speed_scale = ws / (WALK_CLIP * (a.node as Node3D).scale.x)
		if f3.length() > 0.01:
			a.face = atan2(f3.x, f3.z)
		if f3.length() <= stepd:
			n.position = g3
			a.path.pop_front()
			return a.path.is_empty()
		n.position = n.position.lerp(g3, stepd / f3.length())
		return false
	var nxt: Vector2i = a.path[0]
	if B.compact and a.get("claim") != nxt and a.get("push_to") != nxt and _taken(a, nxt):
		# somebody stands on the next tile: wait, then go round, and only if there is no way round walk through
		a.wait = float(a.get("wait", 0.0)) + delta
		stats.wait_s += delta
		if float(a.wait) - delta <= 0.0:
			stats.waits += 1
		_play(a, "Idle")
		# not everybody at the same moment: two who meet head on would step aside to the same side, again and again
		if a.wait > 0.6 + 0.3 * (people.find(a) % 4) and not a.get("repathed", false):
			a.repathed = true
			var last = a.path[-1]
			if last is Vector2i and B.room_of[a.floor].has(a.tile):
				var alt: Array = B.path(a.floor, a.tile, last, _others(a))
				if alt.size() > 1:
					alt.pop_front()
					a.path = alt  # the wait goes on counting: if the way round is taken too, through after 2.5 s
					stats.repaths += 1
					dbg("%s goes round (%d tiles)" % [a.name, alt.size()])
		if a.wait < 2.5:
			return false
		stats.pushes += 1
		a.push_to = nxt
		dbg("%s has no way round at %s: walks through" % [a.name, nxt])
	a.wait = 0.0
	a.repathed = false
	a.claim = nxt
	stats.walk_s += delta
	var goal := _tile_xyz(a.floor, nxt)
	var flat := Vector3(goal.x - n.position.x, 0, goal.z - n.position.z)
	var dist := flat.length()
	_play(a, "Walk")
	# the Walk clip covers WALK_CLIP m/s at scale 1: play it at the pace the node moves (no sliding feet)
	(a.ap as AnimationPlayer).speed_scale = ws / (WALK_CLIP * (a.node as Node3D).scale.x)
	if dist > 0.01:
		a.face = atan2(flat.x, flat.z)
	if dist <= stepd:
		n.position = goal
		a.tile = nxt
		a.erase("push_to")
		a.erase("claim")
		a.path.pop_front()
		return a.path.is_empty()
	n.position += flat / dist * stepd
	n.position.y = lerpf(n.position.y, goal.y, clampf(delta * 6.0, 0, 1))
	return false


func _taken(a: Dictionary, t: Vector2i) -> bool:
	## another person (in view, same floor) stands on that tile or is stepping onto it
	for b: Dictionary in people:
		if b == a or b.floor != a.floor or not b.get("shown", true):
			continue
		if b.get("claim") == t:
			return true  # on the way to it: a step, once begun, is not stopped half way
		if b.tile == t:
			if b.get("claim") != null:
				var c := _tile_xyz(b.floor, b.tile)
				if Vector2(b.node.position.x - c.x, b.node.position.z - c.z).length() > B.TILE * 0.55:
					continue  # more than half way out of it
			return true
	return false


func _others(a: Dictionary) -> Dictionary:
	var out := {}
	for b in people:
		if b != a and b.floor == a.floor and b.get("shown", true):
			out[b.tile] = true
	return out


## Capacity test (sim3d_chars --situshots --sitio=aforo): n people who keep walking to a random free tile of a floor.
## How often they have to wait, go round or (no way round) walk through each other says how many really fit.
func aforo(n: int, f: int) -> void:
	for a in people:
		a.node.queue_free()
	people.clear()
	live_actors.clear()
	stats = {"frames": 0, "min_gap": 99.0, "close_frames": 0, "min_clear": 99.0, "inside_frames": 0, "waits": 0, "repaths": 0, "pushes": 0, "wait_s": 0.0, "walk_s": 0.0, "trips": 0}
	var vill: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/view3d/chars/villagers.json")).villagers
	var free := _free_tiles(f)
	free.shuffle()
	for i in mini(n, free.size()):
		var a := _actor(vill[i % vill.size()], "wander", "", free[i])
		a.floor = f
		a.node.position = _tile_xyz(f, free[i])
		a.timer = randf_range(0.2, 1.5)
	set_top(f)
	dbg("capacity test: %d people on floor %d (%d free tiles)" % [people.size(), f, free.size()])


func _free_tiles(f: int) -> Array:
	var out := []
	for t: Vector2i in B.room_of[f]:
		if not B.blocked[f].has(t) and not B.rooms[B.room_of[f][t]].get("annex", false):
			out.append(t)
	return out


func _wander(a: Dictionary) -> void:
	if a.state == "arrive":
		a.state = "idle"
		a.timer = randf_range(0.6, 2.0)
		stats.trips += 1
		_play(a, "Idle")
	elif a.state == "idle" and a.timer <= 0.0:
		var free := _free_tiles(a.floor)
		var to: Vector2i = free[randi() % free.size()]
		var wanted := false  # nobody else is going there
		for b in people:
			if b != a and not (b.path as Array).is_empty() and b.path[-1] is Vector2i and b.path[-1] == to:
				wanted = true
		if to != a.tile and not wanted and not _taken(a, to):
			_go(a, to)
		if a.state != "walk":
			a.timer = 0.4


func _measure() -> void:
	## compact interiors: how close people get to each other and to the pieces (body radius 0.22 m), every frame
	stats.frames += 1
	var close := false
	var inside := false
	for i in people.size():
		var a: Dictionary = people[i]
		if not a.get("shown", true) or a.has("off_tile"):
			continue  # out of sight, or on a bench or a bed
		var pa: Vector3 = a.node.position
		for j in range(i + 1, people.size()):
			var b: Dictionary = people[j]
			if not b.get("shown", true) or b.has("off_tile") or b.floor != a.floor or absf(b.node.position.y - pa.y) > 1.0:
				continue
			var gap := Vector2(pa.x - b.node.position.x, pa.z - b.node.position.z).length()
			stats.min_gap = minf(stats.min_gap, gap)
			if gap < 0.44:
				close = true
		if absf(pa.y - a.floor * B.FLOOR_H) > 0.3 or a.get("seated", false):
			continue  # on the stairs, or sitting at a table
		for rc: Rect2 in B.obstacles.get(a.floor, []):
			var q := Vector2(clampf(pa.x, rc.position.x, rc.end.x), clampf(pa.z, rc.position.y, rc.end.y))
			var cl := q.distance_to(Vector2(pa.x, pa.z)) - 0.22
			stats.min_clear = minf(stats.min_clear, cl)
			if cl < -0.05:
				inside = true
	if close:
		stats.close_frames += 1
	if inside:
		stats.inside_frames += 1


## Standing at a station: closer than the stand tile centre (tiles are 2 m), `reach` m from the station.
const REACH := {"furnace": 1.25, "anvil": 0.8, "storage": 1.0, "counter": 0.8}


func _approach(a: Dictionary, zone: String) -> void:
	var st: Vector2i = B.zones[zone].tile
	var c := _tile_xyz(a.floor, a.tile)
	var sp := B.tile_pos(B.zones[zone].floor, st)
	var dir := Vector3(sp.x - c.x, 0, sp.z - c.z).normalized()
	var reach := B.reach_of(zone, float(REACH.get(zone, 1.0)))
	if a.role == "customer" and B.d.customers.has("reach"):
		reach = float(B.d.customers.reach)
	a.work_pos = Vector3(sp.x, c.y, sp.z) - dir * reach
	a.face = atan2(dir.x, dir.z)


func _tick(a: Dictionary, delta: float) -> void:
	var n: Node3D = a.node
	if a.has("cur") and not (a.ap as AnimationPlayer).is_playing():
		(a.ap as AnimationPlayer).play(a.cur, 0.0)
	if a.has("face") and not a.get("lying", false):
		n.rotation.y = lerp_angle(n.rotation.y, a.face, clampf(delta * 8.0, 0, 1))
	if a.has("work_pos"):
		if a.state == "walk":
			a.erase("work_pos")
		else:
			n.position = n.position.lerp(a.work_pos, clampf(delta * 4.0, 0, 1))
	if a.state == "walk":
		if _move(a, delta):
			a.state = "arrive"
		return
	a.timer -= delta
	match a.role:
		"live": _live(a)
		"smith": _smith(a)
		"apprentice": _apprentice(a)
		"keeper": _keeper(a)
		"customer": _customer(a)
		"wander": _wander(a)
		"cast": _cast(a)


func _smith(a: Dictionary) -> void:
	# furnace (heat the piece: tongs) -> anvil (hammer it) -> furnace ...
	match a.state:
		"idle", "arrive":
			if a.state == "arrive" or a.timer <= 0.0:
				if a.task == 0 and a.tile == B.stand("furnace"):
					a.state = "work"
					a.timer = 6.0
					a.zone = "furnace"
					a.doing = "calentando el hierro"
					_approach(a, "furnace")
					_play(a, SMITH_ANIMS[0])
					_smith_items.hammer.visible = false
					_smith_items.tongs.visible = true
					_smith_items.tongs.get_node("Tongs/Ingot").visible = true
				elif a.task == 1 and a.tile == B.stand("anvil"):
					a.state = "work"
					a.timer = 8.5
					a.zone = "anvil"
					a.doing = "forjando en el yunque"
					_approach(a, "anvil")
					_play(a, SMITH_ANIMS[1])
					_smith_items.hammer.visible = true
					_smith_items.tongs.visible = true
				else:
					a.doing = "va a la " + ("fragua" if a.task == 0 else "yunque")
					_go(a, B.stand("furnace") if a.task == 0 else B.stand("anvil"))
					if a.state != "walk":
						a.timer = 1.0
		"work":
			if a.task == 1 and a.timer < 6.0 and a.get("cur", "") == SMITH_ANIMS[1]:
				# the piece is on the anvil: tongs down, strike with the hammer
				_play(a, "Punch_Cross")
				_smith_items.tongs.visible = false
				_anvil_ingot.visible = true
				a.doing = "golpea el hierro en el yunque"
				dbg("%s strikes at the anvil" % a.name)
			if a.timer <= 0.0:
				_anvil_ingot.visible = false
				a.task = 1 - a.task
				a.state = "idle"
				a.doing = "va al " + ("yunque" if a.task == 1 else "fragua")
				_go(a, B.stand("anvil") if a.task == 1 else B.stand("furnace"))


func _apprentice(a: Dictionary) -> void:
	# picks finished pieces by the anvil, carries them to the storeroom, comes back
	var pick := Vector2i(4, 3)
	var sp: Dictionary = B.d.get("spots", {})
	if sp.has("pick"):
		pick = Vector2i(sp.pick[0], sp.pick[1])
	var drop := B.stand("storage")
	match a.state:
		"idle", "arrive":
			if a.state == "idle" and a.timer > 0.0:
				return
			if a.task == 0:
				if a.tile != pick:
					a.doing = "va a por piezas"
					a.zone = "anvil"
					_go(a, pick)
					return
				a.state = "work"
				a.timer = 2.2
				a.doing = "recoge piezas"
				_face(a, Vector2(0, 1))
				if B.compact:
					var to_anvil := B.tile_pos(0, B.zones["anvil"].tile) - B.tile_pos(0, pick)
					_face(a, Vector2(to_anvil.x, to_anvil.z))
				_play(a, "PickUp_Table")
			else:
				if a.tile != drop:
					_go(a, drop)
					return
				a.state = "work"
				a.timer = 2.2
				a.zone = "storage"
				a.doing = "guarda piezas en el almacén"
				_approach(a, "storage")
				_play(a, "PickUp_Table")
		"work":
			if a.timer <= 0.0:
				if a.task == 0:
					_carry(a, true)
					a.task = 1
					a.zone = "storage"
					a.doing = "lleva piezas al almacén"
					_go(a, drop)
				else:
					_carry(a, false)
					a.task = 0
					a.state = "idle"
					a.timer = 1.0
					a.zone = "anvil"
					a.doing = "vuelve al taller"
					_play(a, "Idle")


func _customer_at_counter() -> bool:
	for p in people:
		if p.role == "customer" and p.state == "buy":
			return true
	return false


func _keeper(a: Dictionary) -> void:
	a.zone = "counter"
	if _customer_at_counter():
		a.doing = "atiende a un cliente"
		_play(a, "Idle_Talking")
	else:
		a.doing = "espera clientes"
		_play(a, "Idle")


func _street(back: bool) -> Array:
	## compact: the customer's way along the street (customers.street, tile units), as free points
	var pts := []
	var way: Array = B.d.get("customers", {}).get("street", [])
	if way.is_empty():  # no street in the data: along the front of the house, 0.6 m beyond the tile before the door
		var o := B.entrance_out(2)
		way = [[o.x + 7.0, o.y + 0.6], [o.x + 0.0, o.y + 0.6]]
	for q in way:
		pts.append(B.pos_at(0, Vector2(q[0], q[1])))
	if back:
		pts.reverse()
	return pts


func _customer_street(a: Dictionary) -> void:
	## in place: comes along the street from the plaza, buys at the fold-down counter from outside, goes back
	var spot := Vector2i(B.d.customers.counter[0].tile[0], B.d.customers.counter[0].tile[1])
	match a.state:
		"idle":
			if a.timer > 0.0:
				return
			var way := _street(false)
			a.node.position = way[0]
			a.shown = true
			a.node.visible = true
			a.task = 0
			a.doing = "viene de la plaza"
			a.path = way.slice(1) + [spot]
			a.state = "walk"
		"arrive":
			if a.task == 0:
				a.state = "buy"
				a.timer = 6.0
				a.doing = "compra en el mostrador"
				_approach(a, "counter")
				_play(a, "Idle_Talking")
			else:
				_respawn_customer(a)
		"buy":
			if a.timer <= 0.0:
				_coin_pop(a.node.position + Vector3(0, 2.1, 0))
				a.task = 1
				a.doing = "se va contento"
				a.tile = Vector2i(-99, -99)
				a.path = _street(true)
				a.state = "walk"


func _customer(a: Dictionary) -> void:
	if B.compact:
		_customer_street(a)
		return
	var spot := Vector2i(B.d.customers.counter[0].tile[0], B.d.customers.counter[0].tile[1])
	var keep_out := {B.stand("counter"): true}
	match a.state:
		"idle":
			if a.timer > 0.0:
				return
			a.shown = true
			a.node.visible = a.floor <= top
			a.task = 0
			a.doing = "entra en la tienda"
			_go(a, spot, keep_out)
		"arrive":
			if a.task == 0:
				a.state = "buy"
				a.timer = 5.0
				a.doing = "compra una espada"
				_approach(a, "counter")
				_play(a, "Idle_Talking")
			elif a.task == 1:
				# out of the door, two steps outside
				a.task = 2
				a.path = [Vector2i(-1, a.tile.y), Vector2i(-2, a.tile.y)]
				a.state = "walk"
			else:
				_respawn_customer(a)
		"buy":
			if a.timer <= 0.0:
				_coin_pop(a.node.position + Vector3(0, 2.1, 0))
				a.task = 1
				a.doing = "se va contento"
				var e: Dictionary = B.d.entrance
				_go(a, Vector2i(e.tile[0], e.tile[1]), keep_out)


func _respawn_customer(a: Dictionary) -> void:
	_customer_i = (_customer_i + 1) % _customer_looks.size()
	var old: Node3D = a.node
	var d: Dictionary = _customer_looks[_customer_i].duplicate(true)
	d.anim = "Idle"
	d.seed = _customer_i
	var n := CharBuilder.build(d)
	interior.add_child(n)
	old.queue_free()
	a.node = n
	a.ap = n.get_node("AnimationPlayer")
	a.name = String(d.name)
	a.tile = Vector2i(-2, a.tile.y)
	n.position = _tile_xyz(0, a.tile)
	if B.compact:
		a.tile = Vector2i(-99, -99)
	n.visible = false
	a.shown = false
	a.state = "idle"
	a.timer = 2.5
	a.doing = "fuera"
	dbg("next customer: %s" % a.name)


func _coin_pop(at: Vector3) -> void:
	var l := Label3D.new()
	l.text = "+ 24 monedas"
	l.font_size = 40
	l.pixel_size = 0.006
	l.modulate = Color(1.0, 0.85, 0.3)
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = at
	interior.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", at.y + 1.0, 1.4)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.4)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------ zones: hover, select, panel
func _highlights() -> void:
	for z in B.zones:
		if zone_name(z) == "":
			continue
		var zd: Dictionary = B.zones[z]
		var node := Node3D.new()
		node.name = "Zone_" + z
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.85, 0.3, 0.3)
		m.no_depth_test = false
		var centre := Vector3.ZERO
		for t in zd.tiles:
			var mi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(B.TILE * 0.92, B.TILE * 0.92)
			mi.mesh = pm
			mi.material_override = m
			mi.position = B.tile_pos(zd.floor, t) + Vector3(0, 0.03, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
			centre += mi.position
		centre /= zd.tiles.size()
		var l := Label3D.new()
		l.text = zone_name(z)
		l.font_size = 56
		l.pixel_size = 0.012 if not B.compact else 0.007
		l.outline_size = 16
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = centre + Vector3(0, 2.6 if not B.compact else 2.3, 0)
		node.add_child(l)
		node.visible = false
		interior.add_child(node)
		_hl[z] = {"node": node, "mat": m, "label": l}


func zone_name(z: String) -> String:
	return String((B.d.get("stations", {}).get(z, {}) as Dictionary).get("name", ZONE_NAMES.get(z, "")))


func _refresh_highlights() -> void:
	for z in _hl:
		var h: Dictionary = _hl[z]
		var on: bool = z == hover_zone or z == sel_zone
		h.node.visible = on and B.zones[z].floor <= top
		(h.mat as StandardMaterial3D).albedo_color = Color(1.0, 0.55, 0.15, 0.45) if z == sel_zone else Color(1.0, 0.88, 0.35, 0.3)


func _pick(screen: Vector2) -> Array:
	## [floor, tile] under the mouse: the highest shown floor whose room is under the cursor
	var o := cam.project_ray_origin(screen)
	var dv := cam.project_ray_normal(screen)
	for f in range(top, B.floors[0] - 1, -1):
		var y := global_position.y + f * B.FLOOR_H
		if absf(dv.y) < 1e-4:
			continue
		var k := (y - o.y) / dv.y
		var hit := to_local(o + dv * k)
		var t := B.world_to_tile(hit)
		if B.room_of[f].has(t) or (B.compact and _zone_at(f, t) != ""):
			return [f, t]
	return [-99, Vector2i(-99, -99)]


func _zone_at(f: int, t: Vector2i) -> String:
	for z in _hl:
		if B.zones[z].floor == f and (B.zones[z].tiles as Array).has(t):
			return z
	return ""


func _zone_text(z: String) -> String:
	if z == "":
		return ""
	var kind: String = zone_kind.get(z, "")
	var lines := ["%s  ·  %s" % [zone_name(z), KIND_NAMES.get(kind, kind)], ""]
	var who := []
	var clients := []
	for p in people:
		if p.zone == z and p.get("shown", true):
			(clients if p.role == "customer" else who).append("  %s: %s" % [p.name, p.doing])
	lines.append("Trabajan aquí:" if not who.is_empty() else "Nadie trabaja aquí ahora")
	lines.append_array(who)
	if not clients.is_empty():
		lines.append("Clientes:")
		lines.append_array(clients)
	return "\n".join(lines)


func set_hover(z: String) -> void:
	if z != hover_zone:
		hover_zone = z
		_refresh_highlights()
		_apply_cut()


func select(z: String) -> void:
	sel_zone = z
	_panel.visible = z != ""
	_panel_label.text = _zone_text(z)
	_refresh_highlights()
	_apply_cut()
	dbg("selected zone '%s'" % z)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.07, 0.88)
	sb.border_color = Color(0.85, 0.62, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(1180, 24)
	_panel.custom_minimum_size = Vector2(390, 0)
	_panel_label = Label.new()
	_panel_label.add_theme_font_size_override("font_size", 20)
	_panel_label.add_theme_color_override("font_color", Color(0.97, 0.9, 0.78))
	_panel.add_child(_panel_label)
	_panel.visible = false
	_ui.add_child(_panel)
	_help = Label.new()
	_help.position = Vector2(18, 862)
	_help.add_theme_font_size_override("font_size", 16)
	_help.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_help.add_theme_constant_override("outline_size", 5)
	_ui.add_child(_help)
	_update_help()


func _update_help() -> void:
	var t := "Q/E girar · rueda zoom · Tab planta alta · C corte (%s) · N noche · clic en una zona" % {"down": "paredes bajas", "cut": "GDD", "off": "sin corte"}[mode]
	if embedded:
		t += " · Esc salir al pueblo"
	if situ:
		t = "Tab planta alta · Q/E girar · rueda zoom · clic en una zona · Esc o F cerrar la casa"
	_help.text = t


func _unhandled_input(e: InputEvent) -> void:
	if not active:
		return
	if situ:
		# the camera is the town's: here only the floor in view and the zones (a click outside every zone goes on to the town)
		if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_TAB:
			set_top((top + 1) % B.floors.size())
			get_viewport().set_input_as_handled()
		elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE and sel_zone != "":
			select("")
			get_viewport().set_input_as_handled()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var hit := _pick(e.position)
			var z := _zone_at(hit[0], hit[1])
			if z != "" or sel_zone != "":
				select(z)
				get_viewport().set_input_as_handled()
		elif e is InputEventMouseMotion and not (e.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)):
			var hit := _pick(e.position)
			set_hover(_zone_at(hit[0], hit[1]))
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_Q: turn(-90)
			KEY_E: turn(90)
			KEY_TAB: set_top((top + 1) % B.floors.size())
			KEY_C:
				set_mode({"down": "cut", "cut": "off", "off": "down"}[mode])
				_update_help()
			KEY_N: set_night(not night)
			KEY_ESCAPE, KEY_F:
				if sel_zone != "" and e.keycode == KEY_ESCAPE:
					select("")
				elif embedded:
					exit_requested.emit()
			_: return
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.size = clampf(cam.size * (0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 5.0, 40.0)
			_update_camera()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			var hit := _pick(e.position)
			select(_zone_at(hit[0], hit[1]))
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		if e.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			var k: float = cam.size / get_viewport().get_visible_rect().size.y
			target -= cam.basis.x * e.relative.x * k
			target += Vector3(cam.basis.y.x, 0, cam.basis.y.z).normalized() * e.relative.y * k / sin(deg_to_rad(pitch))
			_update_camera()
		else:
			var hit := _pick(e.position)
			var room := B.room_at(hit[0], hit[1]) if hit[0] > -99 else ""
			if room != mouse_room:
				mouse_room = room
				_apply_cut()
			set_hover(_zone_at(hit[0], hit[1]))
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ screenshots and bench
func _snap(fname: String, dir := SHOTS_DIR) -> void:
	for i in 5:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir + fname)
	print("[Interior3D] saved ", dir + fname)


func _wait(sec: float) -> void:
	var t1 := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < t1:
		await get_tree().process_frame


func _view(at: Vector3, size: float, y: float, p := 38.0) -> void:
	target = at
	cam.size = size
	yaw = y
	yaw_goal = y
	pitch = p
	_update_camera()


func _wait_for(a: Dictionary, zone: String, state: String, limit := 40.0) -> void:
	var t1 := Time.get_ticks_msec() + int(limit * 1000)
	while Time.get_ticks_msec() < t1 and not (a.zone == zone and a.state == state):
		await get_tree().process_frame
	await _wait(1.2)


func _shots() -> void:
	get_window().always_on_top = true  # a window in the background is throttled by macOS
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	await _wait(1.5)
	var smith: Dictionary = people[0]
	var c := Vector3(B.W * B.TILE / 2.0, 0.6, B.H * B.TILE / 2.0)
	if only == "" or only == "dia":
		await _wait_for(smith, "anvil", "work")
		_view(c, 23, 45)
		await _snap("interior_corte_dia.png")
	if only == "" or only == "alta":
		set_top(1)
		await _snap("interior_planta_alta.png")
		set_top(0)
	if only == "" or only == "girado":
		_view(c, 23, 225)
		await _snap("interior_girado.png")
		_view(c, 23, 135)
		await _snap("interior_girado_135.png")
	if only == "" or only == "gdd":
		_view(c, 23, 45)
		set_mode("cut")
		set_hover("anvil")
		await _snap("interior_corte_gdd.png")
		set_hover("")
		set_mode("down")
	if only == "" or only == "noche":
		_view(c, 23, 45)
		set_night(true)
		await _snap("interior_noche.png")
		set_night(false)
	if only == "" or only == "zona":
		_view(c, 23, 45)
		set_hover("furnace")
		select("counter")
		await _wait(0.3)
		await _snap("interior_zona.png")
		select("")
		set_hover("")
	if only == "" or only == "herrero":
		await _wait_for(smith, "anvil", "work")
		await _wait(2.4)  # past the PickUp_Table part: hammer strikes
		var p: Vector3 = smith.node.position
		_view(p + Vector3(0.4, 1.0, 0), 4.2, 45, 24)
		await _snap("interior_herrero.png")
		await _wait_for(smith, "furnace", "work")
		p = smith.node.position
		_view(p + Vector3(0, 1.1, -0.3), 4.6, 20, 22)
		await _snap("interior_herrero_fragua.png")
	if only == "" or only == "gente":
		_view(c + Vector3(3, 0, 2), 13, 45, 34)
		await _snap("interior_gente.png")
	get_tree().quit()


func _bench() -> void:
	get_window().always_on_top = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _wait(2.0)
	var c := Vector3(B.W * B.TILE / 2.0, 0.6, B.H * B.TILE / 2.0)
	var res := {}
	for cfg in [["dia_planta_baja", 0, false, 45.0], ["dia_planta_alta", 1, false, 45.0], ["noche_planta_baja", 0, true, 45.0], ["noche_girado", 0, true, 225.0]]:
		set_top(cfg[1])
		set_night(cfg[2])
		_view(c, 23, cfg[3])
		await _wait(1.0)
		var f0 := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_usec()
		var worst := 0.0
		var last := t0
		var dc := 0
		var prims := 0
		var cpu := 0.0
		var gpu := 0.0
		while Time.get_ticks_usec() - t0 < 5_000_000:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
			dc = maxi(dc, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			prims = maxi(prims, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		var frames := Engine.get_frames_drawn() - f0
		var secs := (Time.get_ticks_usec() - t0) / 1e6
		res[cfg[0]] = {"fps": snappedf(frames / secs, 0.1), "render_cpu_ms": snappedf(cpu / frames, 0.01), "render_gpu_ms": snappedf(gpu / frames, 0.01), "ms_avg": snappedf(secs * 1000.0 / frames, 0.01), "ms_worst": snappedf(worst, 0.01),
			"draw_calls": dc, "primitives": prims, "objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))}
		print("[Interior3D] bench %s: %s" % [cfg[0], res[cfg[0]]])
	res.window = str(get_viewport().get_visible_rect().size)
	res.video_mem_mb = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	res.people = people.size()
	var fa := FileAccess.open("res://out/interior_bench.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(res, "  "))
	print("[Interior3D] BENCH ", JSON.stringify(res))
	get_tree().quit()


## Which animation reads as work at the anvil and the furnace: the smith at each station, several moments.
func _animtest() -> void:
	get_window().always_on_top = true
	var smith: Dictionary = people[0]
	for p in people:
		if p != smith:
			p.node.visible = false
			p.shown = false
	await _wait_for(smith, "anvil", "work")
	smith.role = "frozen"
	var pos: Vector3 = smith.node.position
	for anim in ["PickUp_Table", "Interact", "Punch_Cross", "Punch_Jab"]:
		smith.ap.play(anim, 0.0)
		for k in 3:
			smith.ap.speed_scale = 1.0
			smith.ap.seek(smith.ap.get_animation(anim).length * (0.15 + 0.3 * k), true)
			smith.ap.speed_scale = 0.0
			_view(pos + Vector3(0.4, 1.0, 0), 3.6, 45, 20)
			await _snap("anim_%s_%d.png" % [anim, k], ProjectSettings.globalize_path("res://out/interior/"))
	get_tree().quit()


# ------------------------------------------------------------------ live: the people the sim has inside
## live_sync(roster) once per frame from the town view (sim3d_chars.gd): roster = sim character id ->
## {def (CharBuilder), name, station (furnace/anvil/counter/storage or ""), doing (the trace's: work, home, sleep...)}.
## Who is new comes in by the door and walks to the zone of its station; who is gone walks out of the door and is freed;
## home goes up to the kitchen, sleep to the bedroom (floor 1, Tab shows it). Work at a station plays its animation.
const LIVE_UP := [Vector2i(8, 4), Vector2i(8, 3)]  # stairs: floor 0 foot tile, floor 1 landing (forge.json stairs)
const LIVE_SPOT := {"kitchen": [1, Vector2i(1, 3)], "bed": [1, Vector2i(7, 1)], "shop": [0, Vector2i(4, 6)],
	"kitchen2": [1, Vector2i(2, 2)], "kitchen3": [1, Vector2i(2, 1)], "cradle": [1, Vector2i(6, 1)]}
## more than one at home: the first on the stool, the next standing by the table and by the hearth; a baby (age < 3,
## no baby body in the kit) is in the cradle and, like a sleeper, not drawn
const KITCHEN_EXTRA := ["kitchen2", "kitchen3"]
const KITCHEN_HEARTH := Vector2i(0, 1)
const BABY_AGE := 3
const KITCHEN_TABLE := Vector2i(3, 3)  # the stool at (1, 3) faces it (forge.json props)
var live_actors := {}  # sim id -> actor


func _spot(name: String) -> Array:
	## [floor, tile] of a place for who is not at a station: the data's "spots" (compact interiors) or LIVE_SPOT
	var sp: Dictionary = B.d.get("spots", {})
	if sp.has(name) and sp[name] is Array and sp[name][1] is Array:
		return [int(sp[name][0]), Vector2i(sp[name][1][0], sp[name][1][1])]
	return LIVE_SPOT.get(name, [])


func _spot_tile(name: String, fallback: Vector2i) -> Vector2i:
	var sp: Dictionary = B.d.get("spots", {})
	return Vector2i(sp[name][0], sp[name][1]) if sp.has(name) else fallback
var live_snap := false  # new actors appear at their place (entering a building where people already are)
var _live_label: Label
var _own_anims := -1   # 1 when CharBuilder has the own-animation API (tools/make_anims.gd, data/chars/anims.json)


func live_sync(roster: Dictionary) -> void:
	for id in roster:
		var r: Dictionary = roster[id]
		if not live_actors.has(id):
			var e: Dictionary = B.d.entrance
			var a := _actor(r.def, "live", "", B.entrance_out(2) if B.compact else Vector2i(-2, int(e.tile[1])))
			a.name = String(r.name)
			a.sim_id = id
			a.goal = ""
			a.legs = []
			a.items = _smith_tools(a)
			a.items.hammer.visible = false
			a.items.tongs.visible = false
			a.node.visible = a.floor <= top
			live_actors[id] = a
			if live_snap:
				var want := _live_goal(r)
				a.floor = int(_spot(want)[0]) if not _spot(want).is_empty() else 0
				a.tile = _spot(want)[1] if not _spot(want).is_empty() else B.stand(want)
				a.node.position = _tile_xyz(a.floor, a.tile)
				a.node.visible = a.floor <= top
				a.goal = want
				a.want = want
				a.zone = want if B.zones.has(want) else ""  # the zone panel lists who works there
				a.state = "arrive"
			dbg("live: %s %s (%s at %s)" % [a.name, "is in" if live_snap else "comes in", r.doing, r.station])
		var la: Dictionary = live_actors[id]
		la.want = _live_goal(r)
		la.sim_doing = String(r.doing)
		if int((r.def as Dictionary).get("age", 30)) < BABY_AGE and la.want in ["kitchen", "bed"]:
			la.want = "cradle"
	# one place each at the kitchen (by sim id, so nobody swaps places from one frame to the next)
	var at_home := []
	for id in live_actors:
		if live_actors[id].want == "kitchen":
			at_home.append(id)
	at_home.sort()
	for i in at_home.size():
		if i > 0:
			live_actors[at_home[i]].want = KITCHEN_EXTRA[(i - 1) % KITCHEN_EXTRA.size()]
	for id in live_actors.keys():
		if not roster.has(id) and live_actors[id].want != "out":
			live_actors[id].want = "out"
			dbg("live: %s leaves" % live_actors[id].name)
	if _live_label:
		var lines := []
		for id in live_actors:
			var a: Dictionary = live_actors[id]
			if a.want != "out":
				lines.append("%s: %s" % [a.name, a.doing])
		_live_label.text = ("Dentro (según la sim):\n" + "\n".join(lines)) if not lines.is_empty() else "Nadie dentro ahora"


func _live_goal(r: Dictionary) -> String:
	var st := String(r.station)
	var doing := String(r.doing)
	if doing in ["work", "work_night"] and st != "":
		var z := st if B.zones.has(st) and ZONE_NAMES.has(st) else st.get_slice("_", 0)
		return z if B.zones.has(z) else "storage"
	if doing == "sleep":
		return "bed"
	if doing == "home":
		return "kitchen"
	return "shop"


func _live_stop(a: Dictionary) -> void:
	if not a.get("shown", true):
		a.shown = true
		a.node.visible = a.floor <= top
	a.items.hammer.visible = false
	a.items.tongs.visible = false
	if a.get("zone", "") == "anvil" and _anvil_ingot:
		_anvil_ingot.visible = false
	_carry(a, false)
	a.erase("work_pos")
	a.node.rotation.x = 0.0
	a.sub = 0


func _live_route(a: Dictionary) -> void:
	a.goal = a.want
	_live_stop(a)
	var legs := []
	var tf := 0
	var tt := Vector2i.ZERO
	if a.want == "out":
		tf = 0
	elif not _spot(a.want).is_empty():
		tf = _spot(a.want)[0]
		tt = _spot(a.want)[1]
	else:
		tt = B.stand(a.want)
		# somebody else of the sim already works at that station: beside it, on the nearest free tile
		for id in live_actors:
			var o: Dictionary = live_actors[id]
			if o != a and o.get("goal", "") == a.want and B.compact:
				for nb in [tt + Vector2i(0, 1), tt + Vector2i(0, -1), tt + Vector2i(-1, 0), tt + Vector2i(1, 0)]:
					if B.room_of[0].has(nb) and not B.blocked[0].has(nb) and not _taken(a, nb):
						tt = nb
						break
				break
	if a.floor != tf and not B.stair_runs.is_empty():
		# compact: up or down the flight on foot (the floor of the person changes at the top)
		var run: Dictionary = B.stair_runs[0]
		if a.floor == 0:
			legs += [{"go": run.from}, {"path": [run.foot, run.top]}, {"set": [1, run.to]}, {"path": [run.to]}]
		else:
			legs += [{"go": run.to}, {"path": [run.top]}, {"set": [0, run.from]}, {"path": [run.foot, run.from]}]
	elif a.floor != tf:
		if a.floor == 0:
			legs += [{"go": LIVE_UP[0]}, {"hop": [1, LIVE_UP[1]]}]
		else:
			legs += [{"go": LIVE_UP[1]}, {"hop": [0, LIVE_UP[0]]}]
	if a.want == "out":
		var e: Dictionary = B.d.entrance
		var et := Vector2i(e.tile[0], e.tile[1])
		if B.compact:
			legs += [{"go": et}, {"path": [B.entrance_out(1), B.entrance_out(2)]}, {"free": true}]
		else:
			legs += [{"go": et}, {"path": [Vector2i(-1, et.y), Vector2i(-2, et.y)]}, {"free": true}]
		a.doing = "sale"
	else:
		legs.append({"go": tt})
		a.doing = {"furnace": "va a la fragua", "anvil": "va al yunque", "counter": "va al mostrador",
			"storage": "va al almacén", "kitchen": "sube a casa", "kitchen2": "sube a casa", "kitchen3": "sube a casa",
			"bed": "sube a dormir", "cradle": "a la cuna"}.get(a.want, "entra")
	a.legs = legs
	a.state = "arrive"
	a.zone = a.want if B.zones.has(a.want) else ""


func _live(a: Dictionary) -> void:
	if a.get("goal", "") != a.get("want", ""):
		_live_route(a)
		return
	match a.state:
		"arrive":
			if not (a.legs as Array).is_empty():
				_live_leg(a)
			else:
				_live_start(a)
		"work":
			_live_work(a)


func _live_leg(a: Dictionary) -> void:
	var leg: Dictionary = (a.legs as Array).pop_front()
	if leg.has("go"):
		if a.tile == leg.go and B.room_of[a.floor].has(a.tile):
			return  # already there: next leg on the next tick
		_go(a, leg.go)
		if a.state != "walk":  # no path: jump there rather than stand stuck
			a.tile = leg.go
			a.node.position = _tile_xyz(a.floor, a.tile)
	elif leg.has("set"):
		a.floor = int(leg.set[0])
		a.tile = leg.set[1]
		a.node.visible = a.floor <= top
	elif leg.has("hop"):
		a.floor = int(leg.hop[0])
		a.tile = leg.hop[1]
		a.node.position = _tile_xyz(a.floor, a.tile)
		a.node.visible = a.floor <= top
	elif leg.has("path"):
		a.path = (leg.path as Array).duplicate()
		a.state = "walk"
	elif leg.has("free"):
		dbg("live: %s is out" % a.name)
		a.node.queue_free()
		people.erase(a)
		live_actors.erase(a.sim_id)


func _live_start(a: Dictionary) -> void:
	a.state = "work"
	a.sub = 0
	a.timer = 0.0
	match a.want:
		"furnace":
			_approach(a, "furnace")
			a.doing = "calienta el hierro en la fragua"
			if not _own(a, "heat"):
				_play(a, "Interact")
				a.items.tongs.visible = true
				a.items.tongs.get_node("Tongs/Ingot").visible = true
		"anvil":
			_approach(a, "anvil")
			a.doing = "forja en el yunque"
			if _anvil_ingot:
				_anvil_ingot.visible = true
			if not _own(a, "hammer"):
				_play(a, "PickUp_Table")
				a.items.tongs.visible = true
				a.items.hammer.visible = true
				a.timer = 2.4
		"counter":
			_approach(a, "counter")
			a.doing = "atiende el mostrador"
			if not _own(a, "count_coins"):
				_play(a, "Idle")
		"storage":
			_approach(a, "storage")
			a.doing = "barre el almacén"
			if not _own(a, "sweep"):
				_play(a, "PickUp_Table")
		"kitchen":
			# on the kitchen stool, facing the table: the sitting pose has the pelvis 0.33 m behind the root, at 0.54 m
			a.doing = "en casa (cocina, arriba)"
			var st := B.tile_pos(1, _spot("kitchen")[1])
			var tb := B.tile_pos(1, _spot_tile("kitchen_table", KITCHEN_TABLE))
			for h in B._holders:  # compact: the stool stands where the data put it, not on a tile centre
				if h[0].id == "stool" and int(h[0].floor) == 1 and h[0].has("pos"):
					st = B.pos_at(1, Vector2(h[0].pos[0], h[0].pos[1]))
			var dir := Vector3(tb.x - st.x, 0, tb.z - st.z).normalized()
			var k: float = (a.node as Node3D).scale.x
			a.face = atan2(dir.x, dir.z)
			# the own taburete (0.45 m, data/props/ropa_muebles.json) is sat with sit_bench; the kit stool (0.59 m) with sit_stool
			var seat := Interior3DBuilder.top_of("stool", 0.58)
			a.work_pos = st + dir * 0.33 * k + Vector3(0, seat - 0.44 * k, 0)
			if _own(a, "sit_bench" if seat < 0.5 else "sit_stool"):  # the own poses sit with the root on the floor
				a.work_pos = st + dir * 0.33 * k
			else:
				_play(a, "Sitting_Idle")
		"kitchen2", "kitchen3":
			# standing by the table (kitchen2) or the hearth (kitchen3), talking
			a.doing = "en casa (cocina, arriba)"
			var here := B.tile_pos(1, _spot(a.want)[1])
			var look := B.tile_pos(1, _spot_tile("kitchen_table", KITCHEN_TABLE) if a.want == "kitchen2" else _spot_tile("kitchen_hearth", KITCHEN_HEARTH))
			a.face = atan2(look.x - here.x, look.z - here.z)
			_play(a, "Idle_Talking")
		"cradle":
			a.doing = "en la cuna (bebé)"  # no baby body in the kit: not drawn
			a.shown = false
			a.node.visible = false
		"bed":
			a.doing = "duerme (arriba)"  # no lying pose in the library: asleep is not drawn
			a.shown = false
			a.node.visible = false
		_:
			a.doing = "dentro"
			_play(a, "Idle")


func _live_work(a: Dictionary) -> void:
	a.timer -= 0.0  # _tick already counts the timer down
	if a.want == "anvil" and a.sub == 0 and a.timer <= 0.0 and a.get("cur", "") == "PickUp_Table":
		a.sub = 1
		_play(a, "Punch_Cross")  # the hammer strikes (until the own "hammer" animation is there)
		a.items.tongs.visible = false


## The own animations of the «animaciones de oficio» work (CharBuilder.anim_name / CharBuilder.play, data/chars/anims.json)
## when they exist in this checkout; false = use the stand-ins above. They bring their own items.
func _own_check() -> bool:
	if _own_anims < 0:
		_own_anims = 0
		for m in (CharBuilder as Script).get_script_method_list():
			if String(m.name) == "anim_name":
				_own_anims = 1
		dbg("own animations API: %s" % ("yes" if _own_anims == 1 else "no (stand-ins)"))
	return _own_anims == 1


func _own(a: Dictionary, anim: String, carry := "") -> bool:
	if not _own_check():
		return false
	var full := String((CharBuilder as Script).call("anim_name", a.ap, anim))
	if full == "" or not full.contains("/"):
		return false
	(CharBuilder as Script).call("play", a.node, anim, carry, 0.25)
	a.cur = full
	return true


func live_clear() -> void:
	for id in live_actors:
		var a: Dictionary = live_actors[id]
		a.node.queue_free()
		people.erase(a)
	live_actors.clear()
	if _anvil_ingot:
		_anvil_ingot.visible = false


func live_label(on: bool) -> void:
	if _live_label == null:
		_live_label = Label.new()
		_live_label.position = Vector2(18, 18) if not situ else Vector2(18, 132)
		_live_label.add_theme_font_size_override("font_size", 18)
		_live_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_live_label.add_theme_constant_override("outline_size", 6)
		_ui.add_child(_live_label)
	_live_label.visible = on


# ------------------------------------------------------------------ cast: scripted people by data (any building)
## Data "cast": [{look (a villager of data/chars/villagers.json), name, start: [floor, [c, r]] or outside: true,
## looks: [other villagers to come back as], steps: [...]}]. The steps repeat in a loop; each one is a place and what is
## done there for `secs` seconds (`say` = the text of the zone panel):
##   {zone}                    the stand of a station; faces its piece (`reach` in the station: at that distance of it)
##   {tile: [floor, [c, r]], look: [c, r]}
##   {sit: "<name of a prop>", off: [dx, dz], look: [c, r]}   on a seat (anim sit_bench, sit_talk, drink...)
##   {lie: "<name of a prop>"}                                on a bed (the own sleep_back: on the back under a blanket)
##   {enter: true}  comes along the street to the door;  {window: true}  buys at the shop window from the street;
##   {leave: true}  goes out by the door and away (comes back, as the next of `looks`, with the next enter)
## anim: an own animation (data/chars/anims.json: hammer, saw, stir, sweep, count_coins, drink...) or one of the library;
## carry: true = a crate on the shoulder on the way to that step.
func _cast_people() -> void:
	var vill: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/view3d/chars/villagers.json")).villagers
	var by := {}
	for v in vill:
		by[v.name] = v
	var i := 0
	for c: Dictionary in B.d.cast:
		var def: Dictionary = (by.get(String(c.get("look", "Campesina")), vill[0]) as Dictionary).duplicate(true)
		for k in ["age", "height", "sex"]:
			if c.has(k):
				def[k] = c[k]
		def.name = String(c.get("name", def.name))
		var f := 0
		var t := B.entrance_out(2)
		if c.has("start"):
			f = int(c.start[0])
			t = Vector2i(c.start[1][0], c.start[1][1])
		var a := _actor(def, "cast", "", t)
		a.floor = f
		a.node.position = _tile_xyz(f, t)
		a.steps = c.get("steps", [])
		a.step_i = 0
		a.legs = []
		a.looks = []
		for nm in c.get("looks", []):
			if by.has(nm):
				a.looks.append(by[nm])
		a.timer = float(c.get("wait", 0.4 + 0.9 * i))
		if c.get("outside", false):
			a.shown = false
			a.node.visible = false
			a.tile = Vector2i(-99, -99)
		_name_tag(a)
		i += 1


func _name_tag(a: Dictionary) -> void:
	var l := Label3D.new()
	l.name = "NameTag"
	l.text = String(a.name)
	l.font_size = 30
	l.pixel_size = 0.006
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true  # never cut by a wall or an awning
	l.render_priority = 3
	l.position.y = 2.05
	(a.node as Node3D).add_child(l)


func _run_between(f0: int, f1: int) -> Dictionary:
	for r: Dictionary in B.stair_runs:
		if int(r.floor) == mini(f0, f1) and int(r.to_floor) == maxi(f0, f1):
			return r
	return {}


func _legs_to(a: Dictionary, tf: int, tt: Vector2i) -> Array:
	## the legs of the way from where the person is to tile tt of floor tf, flight by flight
	var legs := []
	var f: int = a.floor
	while f != tf:
		var up := tf > f
		var run := _run_between(f, f + (1 if up else -1))
		if run.is_empty():
			legs.append({"hop": [tf, tt]})
			return legs
		if up:
			legs += [{"go": run.from}, {"path": [run.foot, run.top]}, {"set": [f + 1, run.to]}, {"path": [run.to]}]
		else:
			legs += [{"go": run.to}, {"path": [run.top]}, {"set": [f - 1, run.from]}, {"path": [run.foot, run.from]}]
		f += 1 if up else -1
	legs.append({"go": tt})
	return legs


func _piece_point(st: Dictionary, key: String) -> Array:
	## [floor, local point, yaw] of the named seat or bed of a step, with its `off` (metres, in the piece's own frame)
	var pc: Dictionary = B.named.get(String(st[key]), {})
	if pc.is_empty():
		push_warning("[Interior3D] cast: no prop named %s" % st[key])
		return [0, Vector3.ZERO, 0.0]
	var yaw := deg_to_rad(float(pc.rot))
	var off: Array = st.get("off", [0, 0])
	return [int(pc.floor), (pc.pos as Vector3) + Vector3(float(off[0]), 0, float(off[1])).rotated(Vector3.UP, yaw), yaw]


func _cast_target(a: Dictionary, st: Dictionary) -> Array:
	if st.has("zone"):
		return [int(B.zones[st.zone].floor), B.stand(st.zone)]
	if st.has("tile"):
		return [int(st.tile[0]), Vector2i(st.tile[1][0], st.tile[1][1])]
	for key in ["sit", "lie"]:
		if st.has(key):
			var pp := _piece_point(st, key)
			var t := B.world_to_tile(pp[1])
			if key == "lie" or B.blocked[pp[0]].has(t) or not B.room_of[pp[0]].has(t):
				t = _near_untaken(a, pp[0], pp[1])
			if t == Vector2i(-99, -99):
				break
			return [pp[0], t]
	return [int(a.floor), a.tile]


func _near_untaken(a: Dictionary, f: int, at: Vector3) -> Vector2i:
	## the free tile of floor f nearest to a point where nobody else stands or is going
	var best := Vector2i(-99, -99)
	var bd := 3.2
	for t: Vector2i in _free_tiles(f):
		var c := _tile_xyz(f, t)
		var dd := Vector2(c.x - at.x, c.z - at.z).length()
		if dd >= bd:
			continue
		var busy := false
		for b: Dictionary in people:
			if b != a and b.floor == f and b.get("shown", true) and (b.tile == t or b.get("claim") == t or ((b.path as Array).size() > 0 and b.path[-1] is Vector2i and b.path[-1] == t)):
				busy = true
		if not busy:
			bd = dd
			best = t
	return best if best != Vector2i(-99, -99) else B.near_free(f, at)


func _cast_stop(a: Dictionary) -> void:
	var n: Node3D = a.node
	_carry(a, false)
	a.erase("seated")
	if a.has("off_tile"):
		# back on its feet beside the bench or the bed: on the tile it left, or the nearest nobody stands on
		a.tile = a.off_tile
		a.erase("off_tile")
		if _taken(a, a.tile):
			var t := _near_untaken(a, a.floor, _tile_xyz(a.floor, a.tile))
			if t != Vector2i(-99, -99):
				a.tile = t
	if a.get("lying", false) or a.has("work_pos"):
		var yaw := n.rotation.y if not a.get("lying", false) else float(a.get("lie_yaw", 0.0))
		a.lying = false
		a.erase("work_pos")
		n.basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * n.scale.x)
		if B.room_of[a.floor].has(a.tile):
			n.position = _tile_xyz(a.floor, a.tile)
	a.zone = ""


func _cast(a: Dictionary) -> void:
	match a.state:
		"arrive":
			if not (a.legs as Array).is_empty():
				_live_leg(a)
			elif a.has("step"):
				_cast_begin(a)
			else:
				a.state = "idle"
		"idle", "work":
			if a.timer <= 0.0:
				_cast_next(a)


func _cast_next(a: Dictionary) -> void:
	var steps: Array = a.steps
	if steps.is_empty():
		a.timer = 5.0
		return
	var st: Dictionary = steps[int(a.step_i) % steps.size()]
	a.step_i = int(a.step_i) + 1
	_cast_stop(a)
	a.step = st
	var legs := []
	var inside_now: bool = B.room_of[a.floor].has(a.tile)
	if st.get("enter", false):
		var way := _street(false)
		a.node.position = way[0]
		a.floor = 0
		a.tile = B.entrance_out(2)
		a.shown = true
		a.node.visible = true
		a.doing = "llega por la calle"
		legs.append({"path": way.slice(1) + [B.entrance_out(2)]})
	elif st.get("leave", false):
		a.doing = "se va"
		if inside_now or a.floor != 0:
			var e: Dictionary = B.d.entrance
			legs += _legs_to(a, 0, Vector2i(e.tile[0], e.tile[1]))
			legs.append({"path": [B.entrance_out(1), B.entrance_out(2)]})
		legs.append({"path": _street(true)})
	elif st.get("window", false):
		var spot: Array = B.d.customers.counter[0].tile
		a.doing = "va al mostrador"
		legs.append({"path": [Vector2i(spot[0], spot[1])]})
	else:
		var tgt := _cast_target(a, st)
		a.doing = String(st.get("going", "va a su sitio"))
		legs += _legs_to(a, tgt[0], tgt[1])
		if st.get("carry", false):
			_carry(a, true)
	a.legs = legs
	a.state = "arrive"


func _cast_begin(a: Dictionary) -> void:
	var st: Dictionary = a.step
	var n: Node3D = a.node
	a.erase("step")
	a.state = "work"
	a.timer = float(st.get("secs", 5.0))
	a.doing = String(st.get("say", ""))
	_carry(a, false)
	if st.get("enter", false):
		a.timer = 0.0
		return
	if st.get("leave", false):
		a.shown = false
		n.visible = false
		a.tile = Vector2i(-99, -99)
		a.doing = "fuera"
		if not (a.looks as Array).is_empty():
			_cast_relook(a)
		return
	var anim := String(st.get("anim", "Idle"))
	var k := n.scale.x
	if st.has("zone"):
		a.zone = String(st.zone)
		if (B.d.stations[st.zone] as Dictionary).has("reach"):
			_approach(a, st.zone)
		else:
			var zp: Vector3 = B.zone_pos.get(st.zone, B.tile_pos(a.floor, B.zones[st.zone].tile))
			a.face = atan2(zp.x - n.position.x, zp.z - n.position.z)
	if st.get("window", false):
		a.zone = String(st.get("at", "counter"))
		if B.zones.has(a.zone):
			_approach(a, a.zone)
	if st.has("look"):
		var lk := B.pos_at(a.floor, Vector2(st.look[0], st.look[1]))
		a.face = atan2(lk.x - n.position.x, lk.z - n.position.z)
	if st.has("sit"):
		var pp := _piece_point(st, "sit")
		var sp: Vector3 = pp[1]
		var yaw: float = pp[2] + deg_to_rad(float(st.get("face", 0.0)))
		if st.has("look"):
			var lk2 := B.pos_at(a.floor, Vector2(st.look[0], st.look[1]))
			yaw = atan2(lk2.x - sp.x, lk2.z - sp.z)
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		a.face = yaw
		a.seated = true
		a.work_pos = sp + dir * 0.33 * k  # the own sitting poses have the root on the floor, the pelvis 0.33 m behind it
		if B.world_to_tile(sp) != a.tile:  # on a bench that takes its own tile: the tile beside it is free for the others
			a.off_tile = a.tile
			a.tile = Vector2i(-50, -50 - people.find(a))
		if not _own(a, anim if anim != "Idle" else "sit_bench"):
			_play(a, "Sitting_Idle")
			a.work_pos.y += float(Interior3DBuilder.muebles().get(String(B.named[String(st.sit)].id), {}).get("seat_h", 0.45)) - 0.44 * k
	elif st.has("lie"):
		var pp2 := _piece_point(st, "lie")
		var mb: Dictionary = Interior3DBuilder.muebles().get(String(B.named[String(st.lie)].id), {})
		var lie: Array = mb.get("lie", [0, 0.48, 0])
		var rot := Basis(Vector3.UP, float(pp2[2]))
		# on the back, the head towards the head of the bed (its -z): the standing pose of the library, laid down
		a.erase("face")
		a.lying = true
		a.off_tile = a.tile
		a.tile = Vector2i(-50, -50 - people.find(a))
		a.lie_yaw = float(pp2[2]) + PI
		if _own(a, anim if anim.begins_with("sleep") else "sleep_back"):
			# the own pose lies on its back with its root on the mattress top, the head to its -z (the bed's head), under
			# the blanket it carries
			n.basis = rot.scaled(Vector3.ONE * k)
			a.work_pos = (pp2[1] as Vector3) + rot * Vector3(float(lie[0]), float(lie[1]) - 0.03 + float(st.get("up", 0.0)), float(lie[2]))
		else:
			_play(a, "Idle")
			(a.ap as AnimationPlayer).speed_scale = 0.15
			n.basis = (rot * Basis(Vector3.RIGHT, -PI / 2.0)).scaled(Vector3.ONE * k)
			a.work_pos = (pp2[1] as Vector3) + rot * Vector3(float(lie[0]), float(lie[1]) + 0.1 * k + float(st.get("up", 0.0)), float(lie[2]) + 0.93 * k)
		n.position = a.work_pos
	elif not _own(a, anim):
		_play(a, anim if (a.ap as AnimationPlayer).has_animation(anim) else "Idle")
	dbg("%s: %s (%s, %.0f s)" % [a.name, a.doing, anim, a.timer])


func _cast_relook(a: Dictionary) -> void:
	## the next of its looks: another guest or customer comes next time
	a.look_i = (int(a.get("look_i", -1)) + 1) % (a.looks as Array).size()
	var d: Dictionary = (a.looks[a.look_i] as Dictionary).duplicate(true)
	d.anim = "Idle"
	d.seed = int(a.look_i) * 7 + 3
	var old: Node3D = a.node
	var n := CharBuilder.build(d)
	interior.add_child(n)
	n.position = old.position
	n.visible = false
	old.queue_free()
	a.node = n
	a.ap = n.get_node("AnimationPlayer")
	a.name = String(d.name)
	a.erase("cur")
	a.erase("load")
	_name_tag(a)
	dbg("cast: next comes %s" % a.name)
