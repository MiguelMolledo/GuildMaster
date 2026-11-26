class_name SituCut
extends Node
## The cutaway of one house of the town, in place (as in The Sims): the roof and the floors above the one in view melt
## away, the walls that face the camera drop to a stub, the door opens. It works on the baked pieces of the house
## (HouseBuilder.bake: a mesh per wall side and level, the rest of each level, the roof): while the cut is on, the
## merged mesh of opt3d ("merged", "glass") is hidden and the pieces are drawn with shaders/situ_cut.gdshader; when it
## is off again and every piece is back in place, the merged mesh returns.
##   var cut := SituCut.new(); house.add_child(cut); cut.setup(town, house)
##   cut.set_on(true)                 # animated; cut.set_on(true, true) = at once
##   cut.update(cam_dir_local, top)   # every frame: plan direction (x, z) from the house towards the camera in the
##                                    # house's own frame, and the highest floor in view

const SHADER := "res://game/world3d/shaders/situ_cut.gdshader"
const LOW_H := 0.95      # a lowered wall (the fold-down shop counter stays whole)
const FLOOR_H := 3.0
const DROP := 7.5        # m/s the cut line travels
const MELT := 2.6        # 1 / s of a fade

var town: Node
var house: Node3D
var parts: Array = []    # {mi, kind: wall|floor|roof|leaf|prop, level, out: Vector2, cut, fade, cut_goal, fade_goal, full, orig: []}
var on := false
var top := 0
var cam_local := Vector2(1, 1)
var settled := true
var speed := 1.0  # GuildMaster: the walls drop and the roof melts this many times faster (Town3D: 1 / transition_k)
var leaves: Array = []   # [node, closed yaw, level, outward]
var _merged: Array = []
var _leaf_open := 0.0
static var _mats := {}
static var _shaders := {}


static func dbg(msg: String) -> void:
	if OS.is_debug_build():
		print("[SituCut] " + msg)


static func shader(toon: bool) -> Shader:
	if not _shaders.has(toon):
		var s: Shader = load(SHADER)
		if not toon:
			var p := Shader.new()
			p.code = s.code.replace("render_mode cull_disabled, diffuse_toon, specular_toon;", "render_mode cull_disabled;")
			s = p
		_shaders[toon] = s
	return _shaders[toon]


static func cut_mat(src: Material, toon: bool) -> Material:
	var key := "%d|%s" % [src.get_instance_id() if src else 0, toon]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = shader(toon)
	m.set_shader_parameter("albedo_tex", Interior3DBuilder._white())
	var sm := src as StandardMaterial3D
	if sm:
		if sm.albedo_texture:
			m.set_shader_parameter("albedo_tex", sm.albedo_texture)
		m.set_shader_parameter("albedo_color", sm.albedo_color)
		m.set_shader_parameter("use_normal", sm.normal_enabled and sm.normal_texture != null)
		m.set_shader_parameter("normal_tex", sm.normal_texture)
		m.set_shader_parameter("uv_scale", sm.uv1_scale)
		m.set_shader_parameter("uv_offset", sm.uv1_offset)
		m.set_shader_parameter("rough", 1.0 if toon else sm.roughness)
		if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.resource_name.contains("Glass"):
			m.set_shader_parameter("base_fade", 0.6)
	_mats[key] = m
	return m


func setup(town_: Node, house_: Node3D) -> void:
	town = town_
	house = house_
	name = "SituCut"
	for child in house.get_children():
		if child.has_meta("situ_view") or child == self:
			continue
		if child.has_meta("level"):
			var lv := int(child.get_meta("level"))
			for sub in child.get_children():
				if sub is MeshInstance3D:
					if sub.is_in_group("wall"):
						_part(sub, "wall", lv, sub.get_meta("outward"))
					else:
						_part(sub, "floor", lv)
		elif child.is_in_group("roof"):
			for mi in child.find_children("*", "MeshInstance3D", true, false):
				_part(mi, "roof", 99)
		elif child.has_meta("door_leaf"):
			var out: Vector2 = child.get_meta("outward")
			if child.has_meta("leaf_hide"):  # the leaves of a portal: they do not swing, they go
				for mi in child.find_children("*", "MeshInstance3D", true, false):
					_part(mi, "decor", 0)
				continue
			leaves.append([child, (child as Node3D).rotation.y, int(child.get_meta("leaf_level", 0)), out])
			for mi in child.find_children("*", "MeshInstance3D", true, false):
				_part(mi, "wall", int(child.get_meta("leaf_level", 0)), out)
		elif child.has_meta("opt_house") or child.has_meta("opt_glass"):
			_merged.append(child)
		elif String(child.name) == "Interior":
			# the furniture HouseBuilder puts behind the windows: with the house open the real inside takes its place
			for mi in child.find_children("*", "MeshInstance3D", true, false):
				_part(mi, "decor", 0)
		elif child is MeshInstance3D:
			_part(child, "prop", 0)
	set_process(false)
	dbg("%s: %d pieces (%d door leaves), merged mesh %s" % [house.name, parts.size(), leaves.size(), "yes" if not _merged.is_empty() else "no (pieces always drawn)"])


func _part(mi: MeshInstance3D, kind: String, level: int, out := Vector2.ZERO) -> void:
	var full := (level if level < 99 else 0) * FLOOR_H + 4.0
	parts.append({"mi": mi, "kind": kind, "level": level, "out": out, "cut": full, "fade": 0.0, "cut_goal": full, "fade_goal": 0.0,
		"full": full, "orig": [], "was": mi.visible})


func _faces(out: Vector2) -> bool:
	## a wall faces the camera; a corner post (diagonal outward) goes down only when both its walls do
	if absf(out.x) > 0.1 and absf(out.y) > 0.1:
		return out.x * cam_local.x > 0.07 and out.y * cam_local.y > 0.07
	return out.dot(cam_local) > 0.1


func _goals() -> void:
	var low: Array = house.get_meta("situ_low", [])  # walls that go down whatever the camera (the shop window)
	for p in parts:
		var lv: int = p.level
		p.cut_goal = p.full
		p.fade_goal = 0.0
		if not on:
			continue
		if p.kind == "roof" or p.kind == "decor" or (lv > top and lv < 99):
			p.fade_goal = 1.0
		elif p.kind == "wall" and lv == top and (_faces(p.out) or (lv == 0 and low.has(p.out))):
			p.cut_goal = lv * FLOOR_H + LOW_H
	settled = false
	set_process(true)


func set_on(v: bool, instant := false) -> void:
	if v == on:
		return
	on = v
	if on:
		var toon: bool = "style" in town and String(town.style) != "pbr"
		for p in parts:
			var mi: MeshInstance3D = p.mi
			p.orig = []
			p.was = mi.visible
			for i in mi.mesh.get_surface_count():
				p.orig.append(mi.get_surface_override_material(i))
				if p.kind != "prop":
					mi.set_surface_override_material(i, cut_mat(mi.mesh.surface_get_material(i), toon))
			mi.visible = true
			p.cut = p.full
			p.fade = 0.0
		for m in _merged:
			(m as Node3D).visible = false
	_goals()
	if instant:
		_step(1000.0)
	dbg("%s: cut %s" % [house.name, "on" if on else "off"])


func update(dir_local: Vector2, top_floor: int) -> void:
	if not on:
		return
	if dir_local.distance_to(cam_local) > 0.01 or top_floor != top:
		cam_local = dir_local
		top = top_floor
		_goals()


func _process(delta: float) -> void:
	_step(delta)


func _step(delta: float) -> void:
	var done := true
	var base := house.global_position.y
	for p in parts:
		p.cut = move_toward(float(p.cut), float(p.cut_goal), DROP * delta * speed)
		p.fade = move_toward(float(p.fade), float(p.fade_goal), MELT * delta * speed)
		if p.cut != p.cut_goal or p.fade != p.fade_goal:
			done = false
		var mi: MeshInstance3D = p.mi
		if on or not settled:
			mi.visible = float(p.fade) < 0.999
		if p.kind != "prop":
			mi.set_instance_shader_parameter("cut_y", base + (float(p.cut) if float(p.cut) < float(p.full) else 1000.0))
			mi.set_instance_shader_parameter("fade", float(p.fade))
	# the doors swing open while the cut is on
	var want := 1.0 if on else 0.0
	_leaf_open = move_toward(_leaf_open, want, delta * 2.5 * speed)
	if _leaf_open != want:
		done = false
	for l in leaves:
		(l[0] as Node3D).rotation.y = float(l[1]) - deg_to_rad(100.0) * smoothstep(0.0, 1.0, _leaf_open)
	# the wall lantern by the door (sim3d.gd) goes with the front wall
	if house.has_meta("lantern") and is_instance_valid(house.get_meta("lantern")):
		var front_low := false
		for p in parts:
			if p.kind == "wall" and p.level == 0 and (p.out as Vector2) == Vector2(0, -1) and float(p.cut) < float(p.full) - 1.6:
				front_low = true
		(house.get_meta("lantern") as Node3D).visible = not front_low
	if done:
		settled = true
		set_process(false)
		if not on:
			_restore()


func _restore() -> void:
	for p in parts:
		var mi: MeshInstance3D = p.mi
		for i in mi.mesh.get_surface_count():
			if i < (p.orig as Array).size():
				mi.set_surface_override_material(i, p.orig[i])
		mi.visible = p.was
	for m in _merged:
		(m as Node3D).visible = true
