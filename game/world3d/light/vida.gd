extends RefCounted
## The life of the season and the hour in the sim town (docs/clima.md, «Estaciones y vida»). Built by clima.gd; every
## piece is one draw call (a MultiMesh, a Flock or a GPUParticles3D) and is hidden when it is not its season or hour.
##   copas      tree crowns in the season's colour: set_season of main.gd for the kit/trees (foliage shader) and a tint
##              per kind for the Quaternius trees (spring tender green, summer dark, autumn ochre, orange and red; in
##              winter the kit/trees lose their leaves and the Quaternius ones keep fewer)
##   hojas      autumn: leaves falling from the crowns (GPUParticles from points on every broad-leaved crown)
##   hojarasca  autumn and winter: leaf litter round the trunks and against the walls (MultiMesh)
##   vencejos   spring and summer, the evening hours: swallows wheeling fast over the plaza and the river (Flock)
##   cuervos    over the fields by day (Flock, black)
##   patos      on the river, drifting (MultiMesh moved by its shader; not when it is frozen)
##   palomas    perched on the ridges round the plaza; they fly up when the cart goes by and land again
##   mariposas  spring and summer days without rain, round the camera (GPUParticles)
##   luciernagas summer nights (and late spring) without rain (GPUParticles)
##   humo       chimneys of the houses with the hearth lit by the sim (someone awake at home at meal times, in the
##              evening, all day in winter; the decor houses by chance) (one GPUParticles from the lit chimneys)
##   forja      sparks and dark smoke from the forge while the sim has someone working inside
## -- --vida=-hojas,-humo ... switches pieces off (cl_lab --cllab=coste measures each).

const SEASON_MAIN := {"spring": 3, "summer": 0, "autumn": 1, "winter": 2}  # main.gd SEASONS index
const AUTUMN := [Color(2.3, 1.35, 0.25), Color(2.6, 0.9, 0.18), Color(2.2, 0.55, 0.15), Color(1.9, 1.15, 0.35), Color(1.5, 1.05, 0.45)]
const TINT := {"spring": Color(1.12, 1.22, 0.78), "summer": Color(0.78, 0.88, 0.72), "winter": Color(0.95, 0.85, 0.6)}
const LEAF_COLS := [Color(0.92, 0.62, 0.12), Color(0.85, 0.36, 0.08), Color(0.62, 0.2, 0.06), Color(0.55, 0.38, 0.16), Color(0.95, 0.78, 0.2)]
const ALL := ["copas", "hojas", "hojarasca", "vencejos", "cuervos", "patos", "palomas", "mariposas", "luciernagas", "humo", "forja"]

var clima: Node
var town: Node3D
var season := "spring"
var on := {}
var stats := {}
var leaves: GPUParticles3D
var litter: MultiMeshInstance3D
var swallows: Array = []
var crows: Flock
var ducks: MultiMeshInstance3D
var perch: Array = []       # [{mm: MultiMeshInstance3D, flock: Flock, at: Vector3, up_until: float}]
var butterflies: GPUParticles3D
var fireflies: GPUParticles3D
var smoke: GPUParticles3D
var forges: Array = []      # [{b: building id, sparks, smoke}]
var chimneys := {}          # house -> [Vector3 tops]
var _scanned := {}          # houses built again whose chimneys were looked for
var _lit_key := ""
var _next_check := 0.0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()


func _init(c: Node) -> void:
	clima = c
	town = c.town
	season = String(town.season_id)
	for k in ALL:
		on[k] = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vida="):
			for p in a.trim_prefix("--vida=").split(",", false):
				if p == "no":
					for k in ALL:
						on[k] = false
				elif p.begins_with("-"):
					on[p.substr(1)] = false
	_rng.seed = 11
	if DisplayServer.get_name() == "headless":
		return
	var t0 := Time.get_ticks_msec()
	if on.copas:
		_crowns()
	var crowns := _crown_points()
	if on.hojas and season == "autumn":
		leaves = _leaves(crowns)
	if on.hojarasca and season in ["autumn", "winter"]:
		litter = _litter(crowns)
	if on.vencejos and season in ["spring", "summer"]:
		for spot in [[19.5, 19.0, 24.0, 10.0], [35.5, 18.0, 20.0, 8.0], [12.0, 26.0, 18.0, 12.0]]:
			var f := Flock.make(16, {"radius": spot[2], "height": spot[3], "speed": 14.0, "spread": 0.55, "size": 0.34, "seed": int(spot[0])})
			f.name = "Vencejos"
			f.position = _at(spot[0], spot[1])
			_tint_flock(f, Color(0.08, 0.09, 0.14), Color(0.85, 0.82, 0.78))
			f.visible = false
			town.add_child(f)
			swallows.append(f)
	if on.cuervos:
		var fc := _centroid("f")
		if fc != Vector3.INF:
			crows = Flock.make(9, {"radius": 11.0, "height": 4.5, "speed": 5.0, "spread": 0.3, "size": 0.62, "seed": 5})
			crows.name = "Cuervos"
			crows.position = fc
			_tint_flock(crows, Color(0.05, 0.05, 0.06), Color(0.12, 0.12, 0.14))
			town.add_child(crows)
	if on.patos and season != "winter":
		ducks = _ducks()
	if on.palomas:
		_perches()
	if on.mariposas and season in ["spring", "summer"]:
		butterflies = _bugs(6)
	if on.luciernagas and season in ["summer", "spring"]:
		fireflies = _bugs(7)
	if on.humo:
		_find_chimneys()
		# grey and thin: light, opaque puffs of 4 m piled up over a chimney read as a white blot on the roof
		# (GuildMaster-3d, docs/3d/repaso_oficios.md)
		smoke = _smoke_particles(3, Color(0.66, 0.66, 0.68), 0.34)
	if on.forja:
		_forges()
	if OS.is_debug_build():
		print("[ClimaVida] %s: %s in %d ms (%s)" % [season, stats, Time.get_ticks_msec() - t0, on])


func _at(c: float, r: float, y := 0.0) -> Vector3:
	var p: Vector2 = town._tp(c, r)
	return Vector3(p.x, y, -p.y)


func _centroid(tile: String) -> Vector3:
	var s := Vector2.ZERO
	var n := 0
	for r in town.H:
		for c in town.W:
			if town._t(c, r) == tile:
				s += Vector2(c, r)
				n += 1
	return Vector3.INF if n == 0 else _at(s.x / n, s.y / n)


func _tint_flock(f: Flock, a: Color, b: Color) -> void:
	var m: ShaderMaterial = f.material_override
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)


# ---------------------------------------------------------------- crowns by season
func _tree_mmis() -> Array:
	var out := []
	for n in town.get_children():
		if n is MultiMeshInstance3D and n.is_in_group("tree") and n.has_meta("tree_src"):
			out.append(n)
	return out


func _crowns() -> void:
	town.set_season(int(SEASON_MAIN.get(season, 0)))
	var done := {}
	var n := 0
	for mmi: MultiMeshInstance3D in _tree_mmis():
		var src := String(mmi.get_meta("tree_src"))
		if not src.contains("q_nature") or src.contains("Pine"):
			continue
		var mm: MultiMesh = mmi.multimesh if mmi.multimesh else (mmi.get_meta("whole") if mmi.has_meta("whole") else null)
		if mm == null or mm.mesh == null or done.has(mm.mesh):
			continue
		done[mm.mesh] = true
		var kind := absi(hash(src.get_file())) % AUTUMN.size()
		for i in mm.mesh.get_surface_count():
			var m := mm.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null or not m.resource_name.begins_with("Leaves"):
				continue
			var base: StandardMaterial3D = m.get_meta("season_base") if m.has_meta("season_base") else m  # GuildMaster
			var v: StandardMaterial3D = base.duplicate()
			v.set_meta("season_base", base)
			if season == "autumn":
				v.albedo_color = AUTUMN[kind]
			elif TINT.has(season):
				v.albedo_color = TINT[season]
			if season == "winter":
				v.alpha_scissor_threshold = 0.8  # fewer leaves
			mm.mesh.surface_set_material(i, v)
			n += 1
	stats.copas = n
	# the painted grass of the ground: main.gd GROUND barely turns; here it dries more in autumn
	var gtint := {"autumn": Vector3(1.34, 0.96, 0.52), "winter": Vector3(1.08, 1.0, 0.82), "summer": Vector3(0.98, 0.97, 0.8)}
	if gtint.has(season) and town.gm:
		town.gm.set_shader_parameter("tint", gtint[season])
		town.gm.set_shader_parameter("seco", {"autumn": 0.6, "winter": 0.5, "summer": 0.15}[season])
	# the grass tufts of the ground cover follow: drier in autumn, straw in winter, tender in spring
	var gt := {"autumn": Color(1.4, 0.92, 0.38), "winter": Color(1.1, 0.95, 0.62), "spring": Color(1.05, 1.12, 0.85)}
	if gt.has(season):
		var seen := {}
		for mmi in town.find_children("*", "MultiMeshInstance3D", false, false):
			var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh if (mmi as MultiMeshInstance3D).multimesh else (mmi.get_meta("whole") if mmi.has_meta("whole") else null)
			if mm == null or mm.mesh == null or seen.has(mm.mesh) or not mm.mesh.resource_path.contains("Grass"):
				continue
			seen[mm.mesh] = true
			for i in mm.mesh.get_surface_count():
				var m := mm.mesh.surface_get_material(i) as StandardMaterial3D
				if m:
					# GuildMaster: the season changes while the game runs (and the meshes are shared between towns):
					# the tint goes over the kit's own material, not over the last season's
					var base: StandardMaterial3D = m.get_meta("season_base") if m.has_meta("season_base") else m
					var v: StandardMaterial3D = base.duplicate()
					v.albedo_color = base.albedo_color * gt[season]
					v.set_meta("season_base", base)
					mm.mesh.surface_set_material(i, v)
		stats.hierba = seen.size()


func _crown_points() -> PackedVector3Array:
	## a point in the crown of every broad-leaved tree (the falling leaves and the litter start there)
	var pts := PackedVector3Array()
	for mmi: MultiMeshInstance3D in _tree_mmis():
		if mmi.has_meta("tree_far"):
			continue
		var src := String(mmi.get_meta("tree_src"))
		if src.contains("Pine") or src.contains("pino"):
			continue
		var mm: MultiMesh = mmi.multimesh if mmi.multimesh else (mmi.get_meta("whole") if mmi.has_meta("whole") else null)
		if mm == null or mm.mesh == null:
			continue
		var top := mm.mesh.get_aabb().end.y
		for i in mm.instance_count:
			var xf := mmi.global_transform * mm.get_instance_transform(i)
			pts.append(xf.origin + Vector3(0, top * xf.basis.get_scale().y * 0.7, 0))
	stats.crowns = pts.size()
	return pts


func _points_tex(pts: PackedVector3Array) -> ImageTexture:
	var img := Image.create(maxi(1, pts.size()), 1, false, Image.FORMAT_RGBF)
	for i in pts.size():
		img.set_pixel(i, 0, Color(pts[i].x, pts[i].y, pts[i].z))
	return ImageTexture.create_from_image(img)


func _vida_mat(kind: int, tint: Color, opacity: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://game/world3d/shaders/clima_vida.gdshader")
	sm.set_shader_parameter("kind", kind)
	sm.set_shader_parameter("tint", tint)
	sm.set_shader_parameter("opacity", opacity)
	return sm


func _gp(name: String, amount: int, life: float, quad: Vector2, mat: ShaderMaterial, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-400, -20, -400), Vector3(800, 80, 800))
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = quad
	q.material = mat
	p.draw_pass_1 = q
	p.add_to_group("tree")
	town.add_child(p)
	return p


func _ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for i in cols.size():
		g.add_point(float(i) / maxf(1.0, cols.size() - 1.0), cols[i])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


# ---------------------------------------------------------------- autumn
func _leaves(pts: PackedVector3Array) -> GPUParticles3D:
	if pts.is_empty():
		return null
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = _points_tex(pts)
	pm.emission_point_count = pts.size()
	pm.direction = Vector3(0.6, -1, 0.3)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.35, -0.55, 0.2)
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.06
	pm.turbulence_influence_max = 0.14
	pm.color_initial_ramp = _ramp(LEAF_COLS)
	var p := _gp("Hojas", clampi(pts.size() * 4, 60, 1200), 9.0, Vector2(0.3, 0.22), _vida_mat(5, Color.WHITE, 1.0), pm)
	stats.hojas = p.amount
	return p


func _litter(crowns: PackedVector3Array) -> MultiMeshInstance3D:
	## litter: cards under the crowns and against the walls of the houses (the corners where the wind piles them)
	var xs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for c in crowns:
		for k in 3:
			var off := Vector2(_rng.randf_range(-2.6, 2.6), _rng.randf_range(-2.6, 2.6))
			xs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.9, 1.6)), Vector3(c.x + off.x, 0.04, c.z + off.y)))
			cols.append(LEAF_COLS[_rng.randi() % LEAF_COLS.size()])
	for h: Node3D in town.houses:
		var wd: Vector2 = h.get_meta("wd", Vector2(6, 6))
		for k in 4:
			# along the foot of a wall, in the yard side or the street side
			var side := _rng.randi() % 4
			var along := _rng.randf_range(-0.45, 0.45)
			var lp := Vector2(along * wd.x, (wd.y / 2.0 + 0.35) * (1 if side % 2 == 0 else -1))
			if side >= 2:
				lp = Vector2((wd.x / 2.0 + 0.35) * (1 if side == 2 else -1), along * wd.y)
			var g := h.global_transform * Vector3(lp.x, 0.05, lp.y)
			xs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1.4, 1, 0.7) * _rng.randf_range(0.7, 1.1)), Vector3(g.x, 0.05, g.z)))
			cols.append(LEAF_COLS[_rng.randi() % LEAF_COLS.size()])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := PlaneMesh.new()
	q.size = Vector2(1.3, 1.3)
	mm.mesh = q
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		var cc := cols[i]
		cc.a = _rng.randf()
		mm.set_instance_color(i, cc)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Hojarasca"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ShaderMaterial.new()
	sm.shader = load("res://game/world3d/shaders/clima_hojarasca.gdshader")
	sm.set_shader_parameter("amount", 1.0 if season == "autumn" else 0.45)
	mmi.material_override = sm
	mmi.add_to_group("tree")
	town.add_child(mmi)
	stats.hojarasca = xs.size()
	return mmi


# ---------------------------------------------------------------- ducks and pigeons
func _duck_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := SphereMesh.new()
	body.radial_segments = 8
	body.rings = 4
	var parts := [[body, Transform3D(Basis().scaled(Vector3(0.2, 0.11, 0.32)), Vector3(0, 0.06, 0)), Color(0.45, 0.36, 0.26)],
		[body, Transform3D(Basis().scaled(Vector3(0.08, 0.08, 0.09)), Vector3(0, 0.2, 0.2)), Color(0.12, 0.38, 0.2)],
		[body, Transform3D(Basis().scaled(Vector3(0.035, 0.02, 0.06)), Vector3(0, 0.18, 0.3)), Color(0.9, 0.65, 0.15)]]
	for p in parts:
		var arr: Array = (p[0] as SphereMesh).get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var xf: Transform3D = p[1]
		for k in idx:
			st.set_color(p[2])
			st.set_normal((xf.basis * norms[k]).normalized())
			st.add_vertex(xf * verts[k])
	return st.commit()


func _ducks() -> MultiMeshInstance3D:
	var water := []
	for r in town.H:
		for c in town.W:
			if town._t(c, r) == "w":
				water.append(Vector2i(c, r))
	if water.is_empty():
		return null
	var n := mini(10, water.size() / 6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _duck_mesh()
	mm.instance_count = n
	for i in n:
		var t: Vector2i = water[(i * 7919 + 13) % water.size()]
		var p := _at(t.x, t.y, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf_range(0.5, 1.1), _rng.randf(), 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Patos"
	mmi.multimesh = mm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://game/world3d/shaders/clima_pato.gdshader")
	mmi.material_override = sm
	mmi.add_to_group("tree")
	town.add_child(mmi)
	stats.patos = n
	return mmi


func _perches() -> void:
	## pigeons on the ridges of the houses nearest the plaza
	var plaza := _at(19.5, 19.0)
	var hs: Array = town.houses.duplicate()
	hs.sort_custom(func(a, b): return (a as Node3D).global_position.distance_to(plaza) < (b as Node3D).global_position.distance_to(plaza))
	var bird: ArrayMesh = Flock._bird(0.42)
	for h: Node3D in hs.slice(0, 4):
		var mg := h.get_node_or_null("merged") as MeshInstance3D
		if mg == null:
			continue
		var bb := mg.global_transform * mg.get_aabb()
		var wd: Vector2 = h.get_meta("wd", Vector2(6, 6))
		var along := h.global_transform.basis.x.normalized() if wd.x >= wd.y else h.global_transform.basis.z.normalized()
		var c := Vector3(bb.get_center().x, bb.end.y - 0.12, bb.get_center().z)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bird
		mm.instance_count = 5
		for i in 5:
			var p := c + along * (float(i) - 2.0) * 0.55 * _rng.randf_range(0.8, 1.2)
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(0.45, 1.0, 1.0))  # wings folded
			mm.set_instance_transform(i, Transform3D(b, p))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "PalomasPosadas"
		mmi.multimesh = mm
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.5, 0.52, 0.58)
		pm.vertex_color_use_as_albedo = false
		mmi.material_override = pm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.add_to_group("tree")
		town.add_child(mmi)
		var f := Flock.make(5, {"radius": 7.0, "height": 6.0, "speed": 7.0, "spread": 0.4, "size": 0.5, "seed": perch.size() + 3})
		f.name = "PalomasVuelo"
		f.position = Vector3(c.x, c.y - 4.0, c.z)
		f.visible = false
		town.add_child(f)
		perch.append({"mm": mmi, "flock": f, "at": c, "up_until": -1.0})
	stats.palomas = perch.size() * 5


# ---------------------------------------------------------------- insects
func _bugs(kind: int) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 0.5, 14)
	pm.direction = Vector3(0, 0.2, 1)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.5 if kind == 6 else 1.0
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.15
	pm.turbulence_influence_max = 0.3
	var mat: ShaderMaterial
	var p: GPUParticles3D
	if kind == 6:
		pm.color_initial_ramp = _ramp([Color(0.98, 0.96, 0.9), Color(1.0, 0.85, 0.2), Color(0.95, 0.5, 0.1), Color(0.55, 0.7, 1.0)])
		mat = _vida_mat(6, Color.WHITE, 1.0)
		p = _gp("Mariposas", 36, 7.0, Vector2(0.16, 0.1), mat, pm)
	else:
		mat = _vida_mat(7, Color.WHITE, 1.0)
		p = _gp("Luciernagas", 140, 6.0, Vector2(0.09, 0.09), mat, pm)
	p.visible = false
	p.emitting = false
	stats[p.name.to_lower()] = p.amount
	return p


# ---------------------------------------------------------------- smoke and sparks
func _find_chimneys() -> void:
	## the houses are baked (HouseBuilder: roof, chimneys and walls in a few meshes): a chimney is a flat top of a
	## column that stands well above everything round it (scripts: chimney_tops; tools/cl_dump.gd lists them)
	var n := 0
	for h: Node3D in town.houses:
		var tops := chimney_tops(h)
		if not tops.is_empty():
			chimneys[h] = tops
			n += tops.size()
	stats.chimeneas = n


static func chimney_tops(h: Node3D) -> Array:
	## in the baked roof, the chimneys are the pieces of brick or rock (Prop_Chimney: MI_RockTrim + MI_Brick,
	## Prop_Chimney2: MI_UnevenBrick): the connected parts of those surfaces that are compact in plan (under 1.8 m) and
	## taller than 0.7 m; the gable walls of brick are wide and are left out
	var out := []
	for mi: MeshInstance3D in h.find_children("baked", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := mi.global_transform
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			var nm := ""
			if m:
				nm = m.resource_name
				if m is StandardMaterial3D and (m as StandardMaterial3D).albedo_texture:
					nm += (m as StandardMaterial3D).albedo_texture.resource_path
			if not (nm.contains("Brick") or nm.contains("RockTrim") or nm.contains("brick") or nm.contains("stone")):
				continue
			var arr := mi.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			# union-find over vertices that share a position
			var parent := PackedInt32Array()
			parent.resize(verts.size())
			for k in verts.size():
				parent[k] = k
			var by_pos := {}
			for k in verts.size():
				var key := Vector3i(roundi(verts[k].x * 50), roundi(verts[k].y * 50), roundi(verts[k].z * 50))
				if by_pos.has(key):
					_union(parent, k, by_pos[key])
				else:
					by_pos[key] = k
			for t in range(0, idx.size(), 3):
				_union(parent, idx[t], idx[t + 1])
				_union(parent, idx[t], idx[t + 2])
			var boxes := {}
			for k in verts.size():
				var r := _find(parent, k)
				var g := xf * verts[k]
				if boxes.has(r):
					boxes[r] = (boxes[r] as AABB).expand(g)
				else:
					boxes[r] = AABB(g, Vector3.ZERO)
			for r in boxes:
				var bb: AABB = boxes[r]
				if Vector2(bb.size.x, bb.size.z).length() < 1.8 and bb.size.y > 0.7 and bb.end.y > 3.0:
					var top := Vector3(bb.get_center().x, bb.end.y + 0.1, bb.get_center().z)
					var dup := false
					for o: Vector3 in out:
						if o.distance_to(top) < 0.8:
							dup = true
					if not dup:
						out.append(top)
	return out


static func _find(p: PackedInt32Array, k: int) -> int:
	while p[k] != k:
		p[k] = p[p[k]]
		k = p[k]
	return k


static func _union(p: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(p, a)
	var rb := _find(p, b)
	if ra != rb:
		p[ra] = rb


func _smoke_particles(kind: int, col: Color, opac: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 0.7
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0.35, 0.12, 0.2)
	pm.damping_min = 0.15
	pm.damping_max = 0.3
	pm.scale_min = 0.5
	pm.scale_max = 0.8
	var curve := Curve.new()
	curve.max_value = 3.0
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.08
	var p := _gp("Humo", 1, 6.0, Vector2(1.1, 1.1), _vida_mat(kind, col, opac), pm)
	p.visible = false
	p.emitting = false
	return p


func _forges() -> void:
	for b in town.bld_anchor:
		if String(town.bld_anchor[b].type) != "forge":
			continue
		var h: Node3D = town.bld_anchor[b].house
		var tops: Array = chimneys.get(h, [])
		var at: Vector3 = tops[0] if not tops.is_empty() else h.global_position + Vector3(0, 6, 0)
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.15
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 35.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 4.0
		pm.gravity = Vector3(0, -2.5, 0)
		var sp := _gp("ChispasForja", 40, 1.1, Vector2(0.12, 0.12), _vida_mat(4, Color.WHITE, 1.0), pm)
		sp.position = at
		sp.local_coords = true
		sp.visible = false
		sp.emitting = false
		var sm := _smoke_particles(3, Color(0.36, 0.34, 0.33), 0.8)
		var pm2: ParticleProcessMaterial = sm.process_material
		sm.name = "HumoForja"
		pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm2.emission_sphere_radius = 0.2
		sm.amount = 22
		sm.position = at
		sm.local_coords = false
		forges.append({"b": b, "sparks": sp, "smoke": sm})
	stats.forjas = forges.size()


# ---------------------------------------------------------------- per frame
var suspended := false


func suspend(on_: bool) -> void:
	## every piece hidden (cl_lab --cllab=coste: what the life costs)
	suspended = on_
	for n in town.get_children():
		if n is Flock or n is GPUParticles3D or (n is MultiMeshInstance3D and String(n.name) in ["Hojarasca", "Patos", "PalomasPosadas"]):
			if on_:
				n.set_meta("vida_vis", n.visible)
				n.visible = false
			elif n.has_meta("vida_vis"):
				n.visible = n.get_meta("vida_vis")
	if not on_:
		_lit_key = ""


func update(t: float) -> void:
	if suspended:
		return
	var dt := town.get_process_delta_time()
	if Engine.get_write_movie_path() != "":
		dt = 1.0 / 30.0
	_clock += dt
	var day: float = town.daylight(t)
	var h := fmod(t, 1440.0) / 60.0
	var rain: float = maxf(float(clima.now.lluvia), float(clima.now.nieve))
	var far: bool = town.cam.size > 40.0
	var gold: float = town.luz.golden(t) if town.luz else 0.0
	var dusk_hours := (h > 17.5 and h < 21.5) or gold > 0.25
	for f: Flock in swallows:
		f.visible = dusk_hours and day > 0.08 and rain < 0.2
	if crows:
		crows.visible = day > 0.3 and rain < 0.5
	if ducks:
		ducks.visible = rain < 0.8
	# pigeons: up when the cart is near, down again after a while
	var cart: Array = town.cart_trip.capsule if town.cart_trip != null else []
	for p: Dictionary in perch:
		var near := false
		if not cart.is_empty():
			var cp: Vector2 = cart[0]
			near = Vector2(cp.x, -cp.y).distance_to(Vector2(p.at.x, p.at.z)) < 14.0
		if near and day > 0.2:
			p.up_until = _clock + 18.0
		var up := _clock < float(p.up_until)
		(p.flock as Flock).visible = up
		(p.mm as MultiMeshInstance3D).visible = not up and day > 0.1
	# insects round the camera
	var tg: Vector3 = town.target
	var half: float = clampf(town.cam.size * 0.7, 8.0, 30.0)
	if butterflies:
		var want := day > 0.6 and rain < 0.05 and not far and float(clima.now.velo) < 0.5
		_follow(butterflies, want, tg + Vector3(0, 1.0, 0), half, int(36 * pow(half / 18.0, 2.0)))
	if fireflies:
		var want2 := day < 0.15 and rain < 0.05 and not far and (season == "summer" or h > 20.0)
		_follow(fireflies, want2, tg + Vector3(0, 0.8, 0), half, int(140 * pow(half / 18.0, 2.0)))
	for g in [leaves, smoke, butterflies]:
		if g:
			((g.draw_pass_1 as QuadMesh).material as ShaderMaterial).set_shader_parameter("light", maxf(day, 0.12))
	if smoke:   # under clouds and rain the smoke is as grey as the day (unshaded, it kept the full sun)
		var dull := 1.0 - 0.35 * float(clima.now.nubes) - 0.3 * rain
		((smoke.draw_pass_1 as QuadMesh).material as ShaderMaterial).set_shader_parameter("light", maxf(day * dull, 0.12))
	if _clock >= _next_check:
		_next_check = _clock + 1.0
		_hearths(t, h)


func _follow(p: GPUParticles3D, want: bool, at: Vector3, half: float, amount: int) -> void:
	if not want:
		if p.visible:
			p.emitting = false
			p.visible = false
		return
	(p.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(half, 0.6, half)
	p.global_position = at
	amount = clampi(amount, 10, 600)
	if absi(p.amount - amount) > amount / 3:
		p.amount = amount
	if not p.visible:
		p.visible = true
		p.emitting = true


func _hearths(t: float, h: float) -> void:
	## which chimneys smoke: a sim house with someone awake inside at meal times or in the evening (all day in winter),
	## a decor house by chance at the same hours; the forge while somebody works in it
	var meal := (h > 6.0 and h < 9.0) or (h > 12.0 and h < 14.5) or (h > 18.5 and h < 22.5)
	var cold := season == "winter" or (season == "autumn" and (h < 9.0 or h > 18.0))
	var inside := {}
	var working := {}
	for id in town.people:
		var p: Dictionary = town.people[id]
		var loc := String(p.get("loc", ""))
		if loc == "" or loc == "~":
			continue
		var d := String(p.get("doing", ""))
		if d != "sleep":
			inside[loc] = true
		if d in ["work", "work_night", "work_out"]:
			working[loc] = true
	var lit := PackedVector3Array()
	var anchored := {}
	if "--humo=todas" in OS.get_cmdline_user_args():
		meal = true
		cold = true
	for b in town.bld_anchor:
		var house: Node3D = town.bld_anchor[b].house
		if not is_instance_valid(house):
			continue
		anchored[house] = true
		if not chimneys.has(house) and not _scanned.has(house):   # a house built again (an upgrade, works): its chimneys
			_scanned[house] = true
			var tops := chimney_tops(house)
			if not tops.is_empty():
				chimneys[house] = tops
		if not chimneys.has(house):
			continue
		var on_ := (inside.has(b) or "--humo=todas" in OS.get_cmdline_user_args()) and (meal or cold)
		if String(town.bld_anchor[b].type) == "forge":
			on_ = false  # its own dark smoke
		if on_:
			for c in chimneys[house]:
				lit.append(c)
	for house in chimneys.keys():
		if not is_instance_valid(house):   # the house was built again (GuildMaster-3d: freed, its new one is scanned above)
			chimneys.erase(house)
			continue
		if anchored.has(house):
			continue
		var luck := float(absi(hash(String((house as Node).name) + str(int(t / 1440.0)))) % 100) / 100.0
		if (meal and luck < 0.45) or (cold and luck < 0.7):
			for c in chimneys[house]:
				lit.append(c)
	if smoke:
		var key := str(lit)
		if key != _lit_key:
			_lit_key = key
			var pm: ParticleProcessMaterial = smoke.process_material
			if lit.is_empty():
				smoke.emitting = false
				smoke.visible = false
			else:
				pm.emission_point_texture = _points_tex(lit)
				pm.emission_point_count = lit.size()
				smoke.amount = clampi(lit.size() * 16, 16, 800)
				smoke.visible = true
				smoke.emitting = true
			stats.humo_chimeneas = lit.size()
			if OS.is_debug_build():
				print("[ClimaVida] %02d:%02d smoke from %d chimneys" % [int(h), int(fmod(h, 1.0) * 60.0), lit.size()])
	for f: Dictionary in forges:
		var w := working.has(f.b)
		if OS.is_debug_build() and w != (f.sparks as GPUParticles3D).visible:
			print("[ClimaVida] forge %s %s" % [f.b, "working: sparks and smoke" if w else "idle"])
		(f.sparks as GPUParticles3D).visible = w
		(f.sparks as GPUParticles3D).emitting = w
		(f.smoke as GPUParticles3D).visible = w
		(f.smoke as GPUParticles3D).emitting = w
