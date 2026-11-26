extends RefCounted
## The townsfolk in the rain (docs/clima.md, «La lluvia en la gente»). sim3d.gd calls shelter() for everyone it places
## in the street; the walkers' hurry is sim3d.gd hurry() (the same tiles of the trace, sooner).
##   - who stands still in the street (chatting, waiting, shopping, done with a walk before the door) steps to the
##     nearest porch or lean-to within 5 m, else against the nearest house wall within 4.5 m (under the eave), and
##     back to the trace's spot when it walks on; the seated, the workers at their stall and the guards stay
##   - two of every three carry a sack over the head (a cloth on the Head bone) while it rains
## Only the view: the trace, --simcheck (it reads the trace, not this) and who is where at each minute do not change.
##   -- --abrigo=no   no shelter and no sacks

const STAY := ["bench", "dice", "work", "work_out", "work_night", "guard_post", "guard_patrol", "guard_respond", "brawl"]
const PORCH_R := 5.0
const WALL_R := 4.5

var town: Node3D
var on := true
var _last_us := 0
var _dt := 0.0
var _sack_mesh: BoxMesh
var _sack_mat: StandardMaterial3D
var stats := {"sheltering": 0, "sacks": 0}


func _init(t: Node3D) -> void:
	town = t
	on = not ("--abrigo=no" in OS.get_cmdline_user_args())


func wet() -> float:
	if town.clima == null:
		return 0.0
	return float(town.clima.now.get("lluvia", 0.0))


func shelter(id: String, p: Dictionary, pp: Vector2, t: float) -> Vector2:
	if not on:
		return pp
	var now := Time.get_ticks_usec()
	if now != _last_us:
		_dt = clampf(float(now - _last_us) / 1e6, 0.0, 0.1) if _last_us > 0 else 0.0
		if Engine.get_write_movie_path() != "":
			_dt = 1.0 / 30.0
		_last_us = now
	var raining := wet() > 0.15
	_sack(p, raining)
	var still: bool = town.motion_at(p, t) == Vector2.ZERO and not String(p.doing) in STAY
	var k := float(p.get("shelter_k", 0.0))
	if raining and still:
		var from: Vector2 = p.get("shelter_from", Vector2.INF)
		if from == Vector2.INF or from.distance_to(pp) > 0.6:
			p.shelter_from = pp
			p.shelter_to = _spot(id, pp)
			if (p.shelter_to as Vector2) != Vector2.INF and OS.is_debug_build():
				print("[LluviaGente] %s (%s) shelters: %s -> %s" % [id, p.doing, pp, p.shelter_to])
		if (p.shelter_to as Vector2) == Vector2.INF:
			k = maxf(0.0, k - _dt * 2.0)
		else:
			k = minf(1.0, k + _dt * 0.7)
	else:
		k = maxf(0.0, k - _dt * 2.5)
	p.shelter_k = k
	if k <= 0.0 or not p.has("shelter_to") or (p.shelter_to as Vector2) == Vector2.INF:
		return pp
	return pp.lerp(p.shelter_to, smoothstep(0.0, 1.0, k))


func _spot(id: String, pp: Vector2) -> Vector2:
	## a porch cell near, else a point 0.6 m out of the nearest wall; Vector2.INF if none is near
	var jit := Vector2(float(absi(hash(id)) % 100) / 100.0 - 0.5, float(absi(hash(id + "y")) % 100) / 100.0 - 0.5)
	var best := Vector2.INF
	var bd := PORCH_R
	for pc in town._porch_cells:
		var c: Vector2 = pc[0]
		var d := c.distance_to(pp)
		if d < bd:
			bd = d
			best = c + jit * 1.2
	if best == Vector2.INF:
		bd = WALL_R
		for h: Node3D in town.houses:
			var wd: Vector2 = h.get_meta("wd", Vector2.ZERO)
			if wd == Vector2.ZERO:
				continue
			var inv := h.transform.affine_inverse()
			var l := inv * Vector3(pp.x, 0.0, -pp.y)
			var q := Vector3(clampf(l.x, -wd.x / 2.0, wd.x / 2.0), 0.0, clampf(l.z, -wd.y / 2.0, wd.y / 2.0))
			var d := Vector2(l.x - q.x, l.z - q.z).length()
			if d < 0.01 or d >= bd:
				continue
			var n := Vector3(l.x - q.x, 0.0, l.z - q.z).normalized()
			var along := Vector3(-n.z, 0.0, n.x) * jit.x * 1.4  # not all on the same spot of the wall
			var g := h.transform * (q + n * 0.6 + along)
			bd = d
			best = Vector2(g.x, -g.z)
	if best == Vector2.INF:
		return best
	# on ground the sim walks (not into a fenced yard nor over the water): from the wall back towards where it stood
	for i in 9:
		var q := best.lerp(pp, i / 8.0)
		var c := floori(q.x / 2.0)
		var r := floori(-q.y / 2.0)
		if town.walkable(c, r) and town._t(c, r) != "w" and town._house_at_plan(q, 0.2) == null:
			if q.distance_to(pp) < 0.5:
				return Vector2.INF  # nowhere nearer the wall than where it already stands
			return town.avoid(q)  # off the benches, the counters and the cross
	return Vector2.INF


func _sack(p: Dictionary, raining: bool) -> void:
	var root: Node3D = p.node
	var sack: Node3D = p.get("sack", null)
	if sack == null:
		if not raining or absi(hash(String(root.name))) % 3 == 0:
			return
		var sk: Skeleton3D = null
		for n in root.find_children("*", "Skeleton3D", true, false):
			sk = n
			break
		if sk == null or sk.find_bone("Head") < 0:
			p.sack = Node3D.new()  # nothing to hang it on
			return
		if _sack_mesh == null:
			_sack_mesh = BoxMesh.new()
			_sack_mesh.size = Vector3(0.44, 0.07, 0.42)
			_sack_mat = StandardMaterial3D.new()
			_sack_mat.albedo_color = Color(0.58, 0.47, 0.32)
			_sack_mat.roughness = 1.0
		var ba := BoneAttachment3D.new()
		ba.name = "saco_lluvia"
		ba.bone_name = "Head"
		sk.add_child(ba)
		var mi := MeshInstance3D.new()
		mi.mesh = _sack_mesh
		mi.material_override = _sack_mat
		# the Head bone's axes are not the world's (the mannequin's run along the bone): up in its own frame, from the rest
		var hb := sk.find_bone("Head")
		var rest := sk.get_bone_global_rest(hb).basis.orthonormalized()
		var up := (rest.inverse() * Vector3.UP).normalized()
		var fwd := (rest.inverse() * Vector3.FORWARD).normalized()
		var b := Basis.looking_at(fwd, up)  # -z to the front, y up, in the bone's frame
		mi.transform = Transform3D(b * Basis.from_euler(Vector3(deg_to_rad(-10), 0, 0)), up * 0.24 - fwd * 0.02)
		ba.add_child(mi)
		p.sack = ba
		stats.sacks += 1
		sack = ba
	if sack.visible != raining:
		sack.visible = raining
