extends Node3D
## Street test: three houses from rules, orthographic isometric camera, three shading styles.
## Keys: 1 kit PBR · 2 toon · 3 toon + outline · Q/E rotate camera 90° · C cutaway · wheel zoom.
## Run with `-- --shots` to save comparison screenshots to res://out/ and quit.

const STYLES := ["pbr", "toon", "outline"]

var houses: Array[Node3D] = []
var cam: Camera3D
var yaw := 45.0
var target := Vector3(0, 2, 8)
var style := "pbr"
var cutaway := false
var _orig := {}  # MeshInstance3D -> Array of original surface materials
var _variants := {}  # "style|material id" -> Material
var _outline_mat: StandardMaterial3D


func _ready() -> void:
	_build_world()
	var defs := _street()
	for def in defs:
		var h := HouseBuilder.build(def)
		h.position = HouseBuilder.plan_to_godot(def.at)
		h.rotation.y = deg_to_rad(def.get("rot", 0.0))
		h.set_meta("wd", Vector2(def.w, def.d))
		add_child(h)
		houses.append(h)
	_quarter()
	_roads()
	_nature()
	_gallery()
	_plant_trees()
	_collect_materials(self)
	_update_camera()
	if "--shots" in OS.get_cmdline_user_args():
		_shots()


## Families give the plaster colour; wealth gives size, floors, roof, wood and props.
const FAMILIES := {
	"Ferrer": "plaster_ocre", "Vidal": "plaster_rosa", "Soler": "plaster_azul",
	"Costa": "", "Pujol": "plaster_verde",
}


func _template(wealth: String, family: String, rng: RandomNumberGenerator) -> Dictionary:
	var pal := {plaster = FAMILIES[family], stone = ["", "stone_calida", "stone_oscura"][rng.randi() % 3]}
	var d := {seed = rng.randi(), shutters = true, palette = pal}
	match wealth:
		"pobre":
			d.merge({w = 4, d = [4, 6][rng.randi() % 2], floors = 1, walls = ["UnevenBrick"],
				floors_mat = ["Floor_UnevenBrick"], corner = "Corner_Exterior_Wood", window = "Window_Wide_Flat",
				side_windows = 0.3, round_door = false})
			pal.roof = ["", "roof_marron", "roof_oscura"][rng.randi() % 3]
			pal.wood = ""
			d.props = [["Prop_Crate", Vector3(2.7, -d.d / 2.0 - 0.9, 0), rng.randf() * 90]]
		"ciudadano":
			d.merge({w = 6, d = [6, 8][rng.randi() % 2], floors = 2, walls = ["UnevenBrick", "Plaster"],
				floors_mat = ["Floor_Brick", "Floor_WoodDark"], corner = "Corner_Exterior_Wood",
				window = "Window_Wide_Round", grid = true, chimneys = [0.5]})
			pal.roof = ["", "roof_oscura"][rng.randi() % 2]
			pal.wood = ["", "wood_roja"][rng.randi() % 2]
			d.interior = [["Stair_Interior_Solid", Vector3(-2.0, -d.d / 2.0 + 1.6, 0), 0.0],
				["Stair_Interior_Rails", Vector3(-2.0, -d.d / 2.0 + 1.6, 0), 0.0],
				["Prop_Crate", Vector3(1.8, d.d / 2.0 - 1.2, 0), 10.0]]
		_:
			d.merge({w = 8, d = [8, 10][rng.randi() % 2], floors = 3, walls = ["UnevenBrick", "Plaster", "Plaster"],
				floors_mat = ["Floor_RedBrick", "Floor_WoodLight", "Floor_WoodDark"], corner = "Corner_ExteriorWide_Wood",
				window = "Window_Wide_Round", grid = true, side_windows = 0.9, chimneys = [0.6, -0.6]})
			pal.roof = ["roof_oscura", "roof_pizarra", ""][rng.randi() % 3]
			pal.wood = "wood_nogal"
			d.interior = [["Stair_Interior_Solid", Vector3(-3.0, -d.d / 2.0 + 2.0, 0), 0.0],
				["Prop_Crate", Vector3(2.8, d.d / 2.0 - 1.2, 0), 0.0], ["Prop_Crate", Vector3(2.8, d.d / 2.0 - 2.3, 0), 25.0]]
			d.props = [["Prop_Vine2", Vector3(-3.0, -d.d / 2.0 - 0.1, 3), 0.0]]
	return d


## Two rows of houses facing a street along x (street centre at plan y = -8).
func _street() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var rows := [
		[["pobre", "Costa"], ["ciudadano", "Ferrer"], ["rico", "Soler"], ["ciudadano", "Vidal"], ["pobre", "Pujol"]],
		[["ciudadano", "Pujol"], ["pobre", "Ferrer"], ["ciudadano", "Costa"], ["rico", "Vidal"]],
	]
	var out := []
	for r in rows.size():
		var x := -24.0
		for entry in rows[r]:
			var d := _template(entry[0], entry[1], rng)
			d.name = "%s_%s_%d" % [entry[1], entry[0], out.size()]
			x += d.w / 2.0
			if r == 0:
				d.at = Vector3(x, d.d / 2.0, 0)
			else:
				d.at = Vector3(x, -16 - d.d / 2.0, 0)
				d.rot = 180.0
			x += d.w / 2.0 + 1.5 + rng.randf() * 1.5
			out.append(d)
	return out


const SEASONS := ["verano", "otono", "invierno", "primavera"]
const TREE_KINDS := {"roble": 3, "chopo": 3, "frutal": 3, "pino": 3}
var season := 0
var _foliage := {}  # family -> ShaderMaterial
var _bark: StandardMaterial3D
var gm: ShaderMaterial
const GROUND := {"verano": Vector3(1, 1, 1), "otono": Vector3(1.18, 0.98, 0.72), "invierno": Vector3(1, 1, 1), "primavera": Vector3(0.95, 1.12, 0.9)}


func _tree_materials(fam: String) -> void:
	if _bark == null:
		_bark = StandardMaterial3D.new()
		_bark.albedo_texture = load("res://kit/foliage/bark.png")
		_bark.uv1_triplanar = true
		_bark.uv1_scale = Vector3(1.1, 0.45, 1.1)
		_bark.vertex_color_use_as_albedo = true
		_bark.vertex_color_is_srgb = true
		_bark.roughness = 0.95
	if not _foliage.has(fam):
		var m := ShaderMaterial.new()
		m.shader = load("res://game/world3d/shaders/foliage.gdshader")
		m.set_shader_parameter("blossom", 0.45 if fam == "frutal" else 0.0)
		m.set_shader_parameter("wind", 0.4 if fam == "pino" else 1.0)
		_foliage[fam] = m


func _skin_tree(n: Node, fam: String) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var src: Material = n.mesh.surface_get_material(i)
			var nm: String = src.resource_name if src else ""
			n.set_surface_override_material(i, _bark if nm.contains("bark") else _foliage[fam])
	for c in n.get_children():
		_skin_tree(c, fam)


## Groves behind both rows of houses and at the ends of the street; nothing on the street itself.
func _plant_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var zones := [Rect2(-34, 13, 70, 22), Rect2(-34, -48, 70, 20), Rect2(-48, -30, 12, 40)]
	var count := 0
	for z in zones:
		var n := int(z.get_area() / 30.0)
		for k in n:
			var fam: String = ["roble", "roble", "chopo", "frutal", "pino", "pino"][rng.randi() % 6]
			if z.position.y < -40 or z.position.y > 10:
				fam = ["roble", "pino", "pino", "chopo"][rng.randi() % 4] if rng.randf() < 0.6 else fam
			_tree_materials(fam)
			var scene: PackedScene = load("res://kit/trees/%s_%d.glb" % [fam, rng.randi() % TREE_KINDS[fam]])
			var t: Node3D = scene.instantiate()
			var px: float = z.position.x + rng.randf() * z.size.x
			var py: float = z.position.y + rng.randf() * z.size.y
			t.position = HouseBuilder.plan_to_godot(Vector3(px, py, 0))
			t.rotation.y = rng.randf() * TAU
			t.scale = Vector3.ONE * rng.randf_range(0.8, 1.15)
			_skin_tree(t, fam)
			t.add_to_group("tree")
			add_child(t)
			count += 1
	if OS.is_debug_build():
		print("[Prueba3D] planted %d trees" % count)


func set_season(i: int) -> void:
	season = i % SEASONS.size()
	var s: String = SEASONS[season]
	for fam in _foliage:
		var m: ShaderMaterial = _foliage[fam]
		var evergreen: bool = fam == "pino"
		m.set_shader_parameter("autumn", 1.0 if s == "otono" and not evergreen else 0.0)
		m.set_shader_parameter("spring", 1.0 if s == "primavera" else 0.0)
		m.set_shader_parameter("bare", s == "invierno" and not evergreen)
	gm.set_shader_parameter("tint", GROUND[s])
	gm.set_shader_parameter("snow", 1.0 if s == "invierno" else 0.0)
	for rm in _road_mats:
		rm.set_shader_parameter("snow", 1.0 if s == "invierno" else 0.0)
	if OS.is_debug_build():
		print("[Prueba3D] season=%s" % s)


# ---------------------------------------------------------------- artisan quarter
var _q: Node3D


func _place(def: Dictionary, at: Vector3, rot := 0.0) -> Node3D:
	var h := HouseBuilder.build(def)
	h.position = HouseBuilder.plan_to_godot(at)
	h.rotation.y = deg_to_rad(rot)
	h.set_meta("wd", Vector2(def.w, def.d))
	add_child(h)
	houses.append(h)
	return h


func _p(name: String, at: Vector3, rot := 0.0) -> void:
	HouseBuilder._piece(name, _q, at, rot)


func _fence(from: Vector2, to: Vector2, piece := "Prop_WoodenFence_Single", gap := -1) -> void:
	var d := to - from
	var n := int(round(d.length() / 2.0))
	for i in n:
		if i == gap:
			continue
		var c := from + d.normalized() * (2.0 * i + 1.0)
		_p(piece, Vector3(c.x, c.y, 0), rad_to_deg(d.angle()))


## Workshops, a farm and a mansion: compound footprints, yards and trade props.
func _quarter() -> void:
	_q = Node3D.new()
	_q.name = "Quarter"
	add_child(_q)
	var shop := {floors_mat = ["Floor_Brick", "Floor_WoodDark"], corner = "Corner_Exterior_Wood",
		window = "Window_Wide_Round", grid = true, shutters = true}
	# Smithy: house + open forge pavilion, anvil, trough, coal, logs, barrels.
	var smith := shop.duplicate(true)
	smith.merge({name = "Herreria", seed = 501, w = 6, d = 6, floors = 2, walls = ["UnevenBrick", "Plaster"],
		chimneys = [0.5], palette = {plaster = "plaster_ocre", wood = "wood_nogal", stone = "stone_oscura", roof = "roof_oscura"}})
	_place(smith, Vector3(55, 3.6, 0))
	_place({name = "Forja", seed = 502, w = 4, d = 6, floors = 1, walls = ["UnevenBrick"], floors_mat = ["Floor_Brick"],
		corner = "Corner_Exterior_Wood", open = ["front", "right"], palette = {roof = "roof_oscura", wood = "wood_nogal"}},
		Vector3(61.6, 3.6, 0))
	_p("@fragua", Vector3(61.6, 5.2, 0))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.55, 0.2)
	glow.light_energy = 2.5
	glow.omni_range = 4.5
	glow.position = HouseBuilder.plan_to_godot(Vector3(61.6, 4.9, 1.2))
	_q.add_child(glow)
	_qp("Anvil_Log", Vector3(61.4, 2.4, 0), 15)
	_qp("WeaponStand", Vector3(63.2, 6.2, 0), 180)
	_qp("Whetstone", Vector3(59.6, 1.6, 0), 40)
	_qp("Bucket_Metal", Vector3(64.0, 1.2, 0))
	_p("@carbon", Vector3(64.6, 5.6, 0))
	_p("@abrevadero", Vector3(65.0, 2.0, 0), 90)
	_qp("Barrel", Vector3(52.6, 0.6, 0))
	_qp("Barrel", Vector3(53.4, 1.0, 0), 40)
	_p("@lena", Vector3(56, 7.6, 0), 90)
	_p("@cartel", Vector3(58.6, -0.6, 0))
	# Tailor: town house with a cloth stall in front and a drying line in the side yard.
	var tailor := shop.duplicate(true)
	tailor.merge({name = "Sastreria", seed = 511, w = 6, d = 8, floors = 2, walls = ["Plaster", "Plaster"],
		palette = {plaster = "plaster_azul", wood = "wood_roja", roof = ""}})
	_place(tailor, Vector3(75, 4.6, 0))
	_qp("Stall_Empty", Vector3(73.0, -1.2, 0), 0)
	_p("@telas", Vector3(73.0, -1.0, 0))
	_qp("Dummy", Vector3(77.2, -0.4, 0), 200)
	_p("@tendedero", Vector3(80.4, 5, 0), 90)
	_p("@sacos", Vector3(80.2, 1.2, 0), 30)
	_p("@cartel", Vector3(77.6, -0.6, 0))
	# Herbalist: small cottage with a fenced herb garden and a drying rack.
	_place({name = "Herbolista", seed = 521, w = 4, d = 6, floors = 1, walls = ["UnevenBrick"], floors_mat = ["Floor_UnevenBrick"],
		corner = "Corner_Exterior_Wood", window = "Window_Wide_Flat", round_door = false, shutters = true,
		palette = {roof = "roof_marron", wood = "", stone = "stone_calida"}}, Vector3(89, 3.6, 0))
	for bx in [93.4, 96.2]:
		for by in [1.6, 3.8]:
			_p("@bancal", Vector3(bx, by, 0), 90 if by > 2 else 0)
	_p("@secadero", Vector3(94.8, 6.2, 0))
	_qp("Cauldron", Vector3(92.4, 6.4, 0))
	_qp("Bucket_Wooden_1", Vector3(93.2, 7.0, 0))
	_qp("Vase_2", Vector3(87.2, 0.4, 0))
	_fence(Vector2(91.6, 0.3), Vector2(99.6, 0.3), "Prop_WoodenFence_Single", 1)
	_fence(Vector2(99.6, 0.3), Vector2(99.6, 8.3))
	_fence(Vector2(91.6, 8.3), Vector2(99.6, 8.3))
	_p("@cartel", Vector3(87.4, -0.6, 0))
	# Farm: farmhouse, barn, fenced field with crop rows, haystacks, bales, trough, wagon.
	_place({name = "Granja", seed = 531, w = 6, d = 6, floors = 2, walls = ["UnevenBrick", "Plaster"],
		floors_mat = ["Floor_UnevenBrick", "Floor_WoodDark"], corner = "Corner_Exterior_Wood", window = "Window_Wide_Flat",
		round_door = false, shutters = true, chimneys = [0.5],
		palette = {plaster = "plaster_ocre", wood = "", roof = "roof_marron"}}, Vector3(106, 3.6, 0))
	_place({name = "Granero", seed = 532, w = 8, d = 12, floors = 1, walls = ["UnevenBrick"], floors_mat = ["Floor_UnevenBrick"],
		corner = "Corner_ExteriorWide_Wood", window = "Window_Wide_Flat", side_windows = 0.1, round_door = true,
		palette = {roof = "roof_oscura", wood = "", stone = "stone_calida"}}, Vector3(120, 5.6, 0), 90)
	for k in 7:
		_p("@surco", Vector3(104 + k * 1.3, 13.5, 0))
		_p("@surco", Vector3(104 + k * 1.3, 17.6, 0))
	_fence(Vector2(102.6, 10.6), Vector2(112.6, 10.6))
	_fence(Vector2(102.6, 20.6), Vector2(112.6, 20.6))
	_fence(Vector2(102.6, 10.6), Vector2(102.6, 20.6))
	_fence(Vector2(112.6, 10.6), Vector2(112.6, 20.6), "Prop_WoodenFence_Single", 2)
	_p("@almiar", Vector3(116, 13, 0))
	_p("@almiar", Vector3(119, 14.5, 0))
	_p("@paca", Vector3(126.2, 1.2, 0), 10)
	_p("@paca", Vector3(126.4, 2.0, 0.55), 80)
	_p("@paca", Vector3(127.4, 1.4, 0), 35)
	_p("@abrevadero", Vector3(111.6, 1.4, 0))
	_p("@sacos", Vector3(109.6, 0.8, 0))
	_qp("FarmCrate_Apple", Vector3(108.2, 0.4, 0), 10)
	_qp("FarmCrate_Carrot", Vector3(107.2, 0.6, 0), -15)
	_qp("Barrel_Apples", Vector3(103.6, 0.8, 0))
	_qp("Stall_Cart_Empty", Vector3(117.0, -1.0, 0), 90)
	_p("Prop_Wagon", Vector3(114.0, 1.6, 0), 250)
	# Mansion (south side, facing the street): main block, wing, tower, walled front garden.
	var rich := {floors_mat = ["Floor_RedBrick", "Floor_WoodLight", "Floor_WoodDark", "Floor_WoodDark"],
		corner = "Corner_ExteriorWide_Wood", window = "Window_Wide_Round", grid = true, shutters = true, side_windows = 0.9,
		palette = {plaster = "plaster_rosa", wood = "wood_nogal", roof = "roof_pizarra", stone = "stone_calida"}}
	var main := rich.duplicate(true)
	main.merge({name = "Mansion", seed = 541, w = 8, d = 10, floors = 3, walls = ["UnevenBrick", "Plaster", "Plaster"],
		chimneys = [0.6, -0.6]})
	_place(main, Vector3(72, -26, 0), 180)
	var wing := rich.duplicate(true)
	wing.merge({name = "Mansion_ala", seed = 542, w = 6, d = 6, floors = 2, walls = ["UnevenBrick", "Plaster"], chimneys = [0.5]})
	_place(wing, Vector3(79.2, -24, 0), 180)
	var tower := rich.duplicate(true)
	tower.merge({name = "Mansion_torre", seed = 543, w = 4, d = 4, floors = 4, walls = ["UnevenBrick", "UnevenBrick", "Plaster", "Plaster"],
		roof = "tower", side_windows = 0.6})
	_place(tower, Vector3(65.8, -23, 0), 180)
	_fence(Vector2(62, -16.9), Vector2(84, -16.9), "Prop_ExteriorBorder_Straight1", 5)
	_p("Prop_MetalFence_Ornament", Vector3(71.4, -17.2, 0), 0)
	_p("Prop_MetalFence_Ornament", Vector3(74.6, -17.2, 0), 0)
	for gx in [66.0, 69.0, 75.0, 78.0]:
		_p("@bancal", Vector3(gx, -18.6, 0))
	_p("@cartel", Vector3(72.6, -16.0, 0))


# ---------------------------------------------------------------- organic roads
var _road_mats: Array[ShaderMaterial] = []


func _road_mat(cobble_core: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://game/world3d/shaders/road.gdshader")
	m.set_shader_parameter("dirt", load("res://kit/streets/tierra_albedo.png"))
	m.set_shader_parameter("cobble", load("res://kit/streets/adoquin_albedo.png"))
	m.set_shader_parameter("cobble_n", load("res://kit/streets/adoquin_normal.png"))
	m.set_shader_parameter("cobble_core", cobble_core)
	_road_mats.append(m)
	return m


func _road_y(x: float) -> float:
	return -8.0 + 2.2 * sin(x * 0.05) + 0.8 * sin(x * 0.13 + 1.0)


## Main street (cobbled core, dirt margins), a dirt path to every door, alleys through the gaps
## between houses towards the back yards, and a farm track.
func _roads() -> void:
	var main_mat := _road_mat(0.36)
	var dirt := _road_mat(0.0)
	var pts := []
	var x := -56.0
	while x <= 140.0:
		pts.append(Vector2(x, _road_y(x)))
		x += 10.0
	add_child(RoadBuilder.build(pts, 11.0, main_mat, 0.02, 1))
	var north := []
	var south := []
	for h in houses:
		var wd: Vector2 = h.get_meta("wd")
		var tr: Transform3D = h.global_transform
		var door_g := tr * Vector3(0, 0, wd.y / 2.0)
		var out_g := (tr.basis * Vector3(0, 0, 1)).normalized()
		var door := Vector2(door_g.x, -door_g.z)
		var out := Vector2(out_g.x, -out_g.z)
		var side := Vector2(-out.y, out.x) * randf_range(-0.6, 0.6)
		var a := door + out * 1.6 + side
		var b := door + out * 3.0 - side * 0.5
		var path := [door, a, b, Vector2(b.x, _road_y(b.x))]
		if absf(out.y) > 0.7:
			path = [door, a, Vector2(a.x + 0.4, _road_y(a.x) + 0.5 * signf(door.y - _road_y(a.x)))]
		add_child(RoadBuilder.build(path, randf_range(1.8, 2.6), dirt, 0.016, h.get_instance_id() % 997))
		var half := wd.x / 2.0 if absf(out.y) > 0.7 else wd.y / 2.0
		var c := Vector2(h.global_position.x, -h.global_position.z)
		(north if c.y > _road_y(c.x) else south).append(Vector2(c.x - half, c.x + half))
	for side in [[north, 13.0], [south, -29.0]]:
		var spans: Array = side[0]
		spans.sort_custom(func(p, q): return p.x < q.x)
		for i in spans.size() - 1:
			var g0: float = spans[i].y
			var g1: float = spans[i + 1].x
			if g1 - g0 < 1.4:
				continue
			var gx := (g0 + g1) / 2.0
			var ry := _road_y(gx)
			var end_y: float = side[1]
			var alley := [Vector2(gx, ry), Vector2(gx + 0.3, lerpf(ry, end_y, 0.35)),
				Vector2(gx - 0.4, lerpf(ry, end_y, 0.7)), Vector2(gx + 0.6, end_y)]
			add_child(RoadBuilder.build(alley, minf(2.8, g1 - g0 - 0.2), dirt, 0.014, int(gx * 13) % 997))
	add_child(RoadBuilder.build([Vector2(113, _road_y(113)), Vector2(113.6, 4), Vector2(113.2, 9), Vector2(114.5, 15.6), Vector2(119, 16)],
		3.0, dirt, 0.015, 77))


# ---------------------------------------------------------------- Quaternius kits
const QPROPS := "res://kit/q_props/Exports/glTF/%s.gltf"
const QNATURE := "res://kit/q_nature/glTF/%s.gltf"


func _qp(name: String, at: Vector3, rot := 0.0) -> void:
	var n: Node3D = load(QPROPS % name).instantiate()
	n.position = HouseBuilder.plan_to_godot(at)
	n.rotation.y = deg_to_rad(rot)
	_q.add_child(n)


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _first_mesh(c)
		if m:
			return m
	return null


func _blocked(p: Vector2, margin: float) -> bool:
	if absf(p.y - _road_y(p.x)) < 6.2 + margin:
		return true
	for h in houses:
		var wd: Vector2 = h.get_meta("wd")
		var c := Vector2(h.global_position.x, -h.global_position.z)
		var r := maxf(wd.x, wd.y) / 2.0 + margin
		if absf(p.x - c.x) < r and absf(p.y - c.y) < r:
			return true
	return false


## Ground cover from the Stylized Nature MegaKit, one MultiMesh per model.
func _nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var kinds := {"Grass_Common_Short": 520, "Grass_Common_Tall": 220, "Grass_Wispy_Short": 260, "Grass_Wispy_Tall": 120,
		"Flower_3_Group": 90, "Flower_4_Group": 90, "Clover_1": 120, "Bush_Common": 40, "Bush_Common_Flowers": 30,
		"Fern_1": 60, "Rock_Medium_1": 10, "Rock_Medium_2": 10, "Pebble_Round_2": 60, "Pebble_Square_3": 40,
		"Mushroom_Common": 30, "Plant_1": 40}
	for kind in kinds:
		var src := _first_mesh(load(QNATURE % kind).instantiate())
		if src == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src.mesh
		var xs: Array[Transform3D] = []
		var tries := 0
		while xs.size() < kinds[kind] and tries < kinds[kind] * 20:
			tries += 1
			var p := Vector2(rng.randf_range(-60, 140), rng.randf_range(-42, 28))
			var margin := 1.2 if kind.begins_with("Bush") or kind.begins_with("Rock") else 0.4
			if _blocked(p, margin):
				continue
			var small: bool = kind.begins_with("Grass") or kind.begins_with("Flower") or kind.begins_with("Clover") or kind.begins_with("Fern") or kind.begins_with("Plant")
			var sc := rng.randf_range(0.4, 0.7) if small else rng.randf_range(0.7, 1.2)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc)
			xs.append(Transform3D(b, HouseBuilder.plan_to_godot(Vector3(p.x, p.y, 0))))
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.add_to_group("tree")
		add_child(mmi)
	if OS.is_debug_build():
		print("[Prueba3D] nature scattered")


## Side-by-side tree comparison west of the village: mine / Nature MegaKit / Textured Stylized Trees.
func _gallery() -> void:
	var rows := [
		[["mine", "roble_0"], ["mine", "chopo_0"], ["mine", "frutal_0"], ["mine", "pino_0"], ["mine", "roble_2"]],
		[["nat", "CommonTree_1"], ["nat", "CommonTree_3"], ["nat", "Pine_1"], ["nat", "TwistedTree_1"], ["nat", "DeadTree_1"]],
		[["tex", "Tree_1"], ["tex", "Tree_5"], ["tex", "Birch_1"], ["tex", "Pine_1"], ["tex", "Tree_9"]],
	]
	for r in rows.size():
		for k in rows[r].size():
			var e: Array = rows[r][k]
			var path: String
			match e[0]:
				"mine": path = "res://kit/trees/%s.glb" % e[1]
				"nat": path = QNATURE % e[1]
				_: path = "res://kit/q_trees/FBX/%s.fbx" % e[1]
			var t: Node3D = load(path).instantiate()
			if e[0] == "mine":
				var fam: String = e[1].split("_")[0]
				_tree_materials(fam)
				_skin_tree(t, fam)
			elif e[0] == "tex":
				_skin_textured(t, e[1].split("_")[0])
			t.position = HouseBuilder.plan_to_godot(Vector3(-108 + k * 9.0, 12 - r * 11.0, 0))
			t.add_to_group("tree")
			add_child(t)


## The Textured Stylized Trees FBX files do not carry their texture links: map them by material name.
func _skin_textured(n: Node, kind: String) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var src: Material = n.mesh.surface_get_material(i)
			var nm: String = (src.resource_name if src else "").to_lower()
			var m := StandardMaterial3D.new()
			m.roughness = 0.9
			if nm.contains("leaf") or nm.contains("leav"):
				var tex: String = {"Birch": "Birch_Leaves_Green.png", "Pine": "Pine_Leaves.png"}.get(kind, "Tree_Leaves.png")
				m.albedo_texture = load("res://kit/q_trees/Textures/" + tex)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.alpha_scissor_threshold = 0.4
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			else:
				m.albedo_texture = load("res://kit/q_trees/Textures/" + ("Birch_Bark.png" if kind == "Birch" else "Tree_Bark.jpg"))
			n.set_surface_override_material(i, m)
			if OS.is_debug_build():
				print("[Prueba3D] textured tree %s surface %d material '%s'" % [kind, i, nm])
	for c in n.get_children():
		_skin_textured(c, kind)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.7, 0.92)
	env.ambient_light_energy = 0.75
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	ground.mesh = pm
	gm = ShaderMaterial.new()
	gm.shader = load("res://game/world3d/shaders/ground.gdshader")
	gm.set_shader_parameter("grass", load("res://kit/foliage/grass.png"))
	ground.material_override = gm
	ground.position = Vector3(1, -0.02, 10)
	add_child(ground)
	# Street surfaces: seamless textures baked from 3dShapes (tools/street_textures.mjs), world-space
	# triplanar UVs so any street layout tiles without seams. Sidewalks are slightly raised (curb edge).

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 40
	cam.far = 400
	add_child(cam)
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.albedo_color = Color(0.16, 0.1, 0.07)
	_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_mat.grow = true
	_outline_mat.grow_amount = 0.07


func _street_mat(tex: String, triplanar: bool, uv_scale: Vector3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://kit/streets/%s_albedo.png" % tex)
	m.normal_enabled = true
	m.normal_texture = load("res://kit/streets/%s_normal.png" % tex)
	m.normal_scale = 1.4
	m.roughness = 0.92
	m.uv1_scale = uv_scale
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
	else:
		# parallax relief from the 3dShapes height map (not supported with triplanar)
		m.heightmap_enabled = true
		m.heightmap_texture = load("res://kit/streets/%s_height.png" % tex)
		m.heightmap_scale = 4.0
		m.heightmap_deep_parallax = true
		m.heightmap_min_layers = 8
		m.heightmap_max_layers = 24
	return m


## A street strip: solid body (triplanar sides) + a top plane with parallax relief.
func _surface(_kind, size: Vector3, plan_pos: Vector3, tex: String, uv_scale: float) -> void:
	var base := HouseBuilder.plan_to_godot(plan_pos)
	if size.y > 0.05:
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		body.mesh = bm
		body.material_override = _street_mat(tex, true, Vector3.ONE * uv_scale)
		body.position = base
		body.add_to_group("tree")
		add_child(body)
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x, size.z)
	top.mesh = pm
	top.material_override = _street_mat(tex, false, Vector3(size.x * uv_scale, size.z * uv_scale, 1))
	top.position = base + Vector3(0, size.y / 2 + 0.003, 0)
	top.add_to_group("tree")
	add_child(top)


func _collect_materials(n: Node) -> void:
	if n.is_in_group("tree"):
		return
	if n is MeshInstance3D and n.mesh:
		var mats := []
		for i in n.mesh.get_surface_count():
			mats.append(n.get_active_material(i))
		_orig[n] = mats
	for c in n.get_children():
		_collect_materials(c)


func _variant(m: Material, s: String) -> Material:
	if s == "pbr" or not (m is StandardMaterial3D):
		return m
	var key := "%s|%d" % [s, m.get_instance_id()]
	if not _variants.has(key):
		var v: StandardMaterial3D = m.duplicate()
		v.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		v.specular_mode = BaseMaterial3D.SPECULAR_TOON
		v.roughness = 1.0
		if s == "outline":
			v.next_pass = _outline_mat
		_variants[key] = v
	return _variants[key]


func set_style(s: String) -> void:
	style = s
	for mi in _orig:
		var mats: Array = _orig[mi]
		for i in mats.size():
			mi.set_surface_override_material(i, _variant(mats[i], s))
	if OS.is_debug_build():
		print("[Prueba3D] style=%s (%d meshes)" % [s, _orig.size()])


func set_cutaway(on: bool) -> void:
	cutaway = on
	var fwd := Vector2(sin(deg_to_rad(yaw)), -cos(deg_to_rad(yaw)))
	for h in houses:
		# camera direction in the house's own plan space
		var local := fwd.rotated(-h.rotation.y)
		HouseBuilder.set_cutaway(h, on, local, 0)


func _update_camera() -> void:
	cam.rotation_degrees = Vector3(-30, yaw, 0)
	cam.position = target + cam.basis.z * 80.0
	if cutaway:
		set_cutaway(true)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_1: set_style("pbr")
			KEY_2: set_style("toon")
			KEY_3: set_style("outline")
			KEY_Q: yaw -= 90; _update_camera()
			KEY_E: yaw += 90; _update_camera()
			KEY_C: set_cutaway(not cutaway)
			KEY_4: set_season(season + 1)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.size = max(8.0, cam.size * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.size = min(80.0, cam.size * 1.1)


func _snap(fname: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	img.save_png("res://out/" + fname)
	print("[Prueba3D] saved ", fname)


func _shots() -> void:
	set_style("outline")
	cam.size = 62
	_update_camera()
	for i in 4:
		set_season(i)
		await _snap("godot_arboles_%s.png" % SEASONS[i])
	set_season(0)
	cam.size = 20
	target = Vector3(-4, 1, 8)
	_update_camera()
	await _snap("godot_calles_cerca.png")
	for shot in [["godot_galeria.png", Vector3(-90, 3, -1), 40.0], ["godot_barrio.png", Vector3(90, 2, 8), 52.0], ["godot_herreria.png", Vector3(62, 2, -2), 18.0],
			["godot_granja.png", Vector3(114, 2, -10), 26.0], ["godot_mansion.png", Vector3(72, 4, 20), 28.0, 225.0]]:
		target = shot[1]
		cam.size = shot[2]
		yaw = shot[3] if shot.size() > 3 else 45.0
		_update_camera()
		await _snap(shot[0])
	target = Vector3(0, 2, 8)
	cam.size = 40
	_update_camera()
	set_style("pbr")
	await _snap("godot_calle_pbr.png")
	set_style("outline")
	await _snap("godot_calle_contorno.png")
	yaw = 225
	_update_camera()
	await _snap("godot_calle_otro_lado.png")
	yaw = 45
	cam.size = 30
	_update_camera()
	set_cutaway(true)
	await _snap("godot_calle_corte.png")
	get_tree().quit()
