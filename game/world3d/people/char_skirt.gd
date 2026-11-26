class_name CharSkirt
extends SkeletonModifier3D
## Long skirts on the shared animations (see docs/personajes.md, "Faldas largas: huesos de falda").
## The garment (tools/make_garment.py, skirt=...) carries a ring of columns around the hips, each a chain of four
## bones: skirt_<c>_0 (hip -> knee), skirt_<c>_1 (knee -> flap), skirt_<c>_2 (flap: the last span above the hem,
## with the hem ring) and skirt_<c>_3 (no weights: it marks where the hem rests). The animations do not know them; every frame, after the AnimationPlayer
## and CharAge, each column is laid out from the pelvis down, one segment after another, in its own vertical plane:
##   - the top segment rests on the thigh and the knee (the smallest angle that clears them);
##   - the lower segments hang by gravity from where the one above ends: at their rest flare, straighter down the
##     more the top segment was lifted (cloth over a knee falls plumb, in folds: every other column `fold` degrees
##     out, the next in), and only as far out as the legs need;
##   - against the floor a segment gathers (shortens along itself) instead of opening out, and a segment draped over
##     a leg that lies on the floor ends just past it (the rest of the cloth piles there);
##   - a column hangs at most `spread` degrees under a neighbour that a leg lifts (the cloth between them sags but
##     does not cut through the knee), every other column sags further (`pleat`): the folds between the supports;
##   - in game the angles follow those targets through a damped spring (`freq`, `damp`), never inside the legs,
##     and the body's speed drags the cloth back (`drag`): the skirt sways and trails behind the legs.
## Leg obstacles: tapered capsules around thigh, calf, foot and toes (sampled as spheres), plus the floor. The radii
## are calibrated in the rest pose (never more than the garment already clears standing), so standing it is still.
## The same solve() runs in tools/ropa_clip.gd (numeric clipping sweep) on the frames it poses (without the spring).

const SEGS := [["thigh", "calf"], ["calf", "foot"], ["foot", "ball"], ["ball", "ball_leaf"]]
## where each leg capsule is sampled (0 = at the bone, 1 = at its child; the joint between two capsules once, the
## hip joint never: it lies at the roots, which the thigh lifts): denser along the long bones
const SAMPLES := [[1.0 / 3.0, 2.0 / 3.0], [0.0, 1.0 / 3.0, 2.0 / 3.0], [0.0, 0.5], [0.0, 1.0]]
const NB := 4  # bones per column
const NK := 3  # posed segments per column (the 4th bone only marks the hem's rest)
const MIN_RHO := 0.1  # leg points nearer a segment's start than this are left to the segment above
const MIN_RHO_TOP := 0.14  # and nearer a root than this, to the hip band (it is skinned to the thighs)
const MAX_PHI := deg_to_rad(100.0)  # a little over level: cloth draped over a knee does not climb further
const ON_FLOOR := 0.02  # m: a segment that starts this near the floor lies on it (gathered, folded outwards)
const FOLD := deg_to_rad(75.0)
const HIGH := deg_to_rad(60.0)
const MIN_K := 0.15  # shortest a segment gathers to on the floor (scale along the bone)
const PUSH := 3.0  # rad/s: most a leg's push hands on to the cloth
const VMAX := 6.0  # rad/s: fastest the cloth swings
const DOWN := Vector3(0, -1, 0)

const STILL := 0.006  # m: legs that moved less than this (from the pelvis) since the last solve count as still

var rig := {}
var every := 1  # solve one frame in `every` (the skirt pose is kept in between); kit "skirt.every"
var _key := PackedVector3Array()
var _locals := []
var _frame := 0
var _solves := 0
var _phi := PackedFloat32Array()  # angles (NK per column) and their speeds, for the spring
var _vel := PackedFloat32Array()
var _g := []  # bone globals read this frame (only the bones the solve needs)
var _last_pos := Vector3.INF
var _speed := Vector3.ZERO  # the character's velocity in skeleton space (smoothed)

static var prof_us := 0  # total time spent in _process_modification_with_delta (all skirts), for benches
static var prof_calls := 0
static var prof_solve := 0  # of which in solve()


## Adds to the skeleton the skirt bones a part's skin binds and the skeleton lacks (their rest from the bind pose),
## all children of the pelvis (their poses are set as globals: a chain would carry the gather scale into the next
## bone as a shear). Returns how many were added. Call before the part's MeshInstance3D gets its skin.
static func add_bones(sk: Skeleton3D, skin: Skin) -> int:
	var missing := {}
	for i in skin.get_bind_count():
		var bn := String(skin.get_bind_name(i))
		if bn.begins_with("skirt_") and sk.find_bone(bn) < 0:
			missing[bn] = skin.get_bind_pose(i).affine_inverse()
	var names := missing.keys()
	names.sort_custom(func(a, b): return _order(a) < _order(b))
	var pi := sk.find_bone("pelvis")
	var pinv := sk.get_bone_global_rest(pi).affine_inverse()
	for bn in names:
		var b := sk.add_bone(bn)
		sk.set_bone_parent(b, pi)
		var local: Transform3D = pinv * (missing[bn] as Transform3D)
		sk.set_bone_rest(b, local)
		sk.set_bone_pose(b, local)
	return names.size()


static func _order(bn: String) -> int:
	return int(bn.get_slice("_", 1)) * 10 + int(bn.get_slice("_", 2))


static var _root_cache := {}  # part id -> per column [[bone name, weight], ...]


## Skin weights of the garment around each column's root: the hip band above the columns is skinned to the clothes'
## bones (pelvis, thighs), so the root moves the way that band does (no crease where the skirt bones take over).
static func root_weights(id: String, mesh: Mesh, skin: Skin, roots: Array) -> Array:
	if _root_cache.has(id):
		return _root_cache[id]
	var verts := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var per := 4
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		per = (arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() / v.size()
		verts.append_array(v)
		bones.append_array(arr[Mesh.ARRAY_BONES])
		weights.append_array(arr[Mesh.ARRAY_WEIGHTS])
	var skirt_bind := {}
	for i in skin.get_bind_count():
		if String(skin.get_bind_name(i)).begins_with("skirt_"):
			skirt_bind[i] = true
	var out := []
	for R in roots:
		# the nearest vertices that carry no skirt weight (pure clothes' weights)
		var near := []
		for v in verts.size():
			var d := (verts[v] - (R as Vector3)).length_squared()
			if near.size() < 6 or d < near[-1][0]:
				var pure := true
				for k in per:
					if weights[v * per + k] > 0.0 and skirt_bind.has(bones[v * per + k]):
						pure = false
						break
				if not pure:
					continue
				near.append([d, v])
				near.sort_custom(func(a, b): return a[0] < b[0])
				if near.size() > 6:
					near.pop_back()
		var acc := {}
		for n in near:
			for k in per:
				var w := weights[n[1] * per + k]
				if w > 0.0:
					var bn := String(skin.get_bind_name(bones[n[1] * per + k]))
					acc[bn] = acc.get(bn, 0.0) + w / near.size()
		var lst := []
		for bn in acc:
			lst.append([bn, acc[bn]])
		out.append(lst)
	_root_cache[id] = out
	return out


## The rig of the skirt bones on this skeleton (rest geometry per column, packed) with the part's "skirt" settings.
## mi: the garment's MeshInstance3D (for the root weights); without it the roots ride the pelvis.
static func make_rig(sk: Skeleton3D, cfg: Dictionary, mi: MeshInstance3D = null) -> Dictionary:
	var nc := 0
	while sk.find_bone("skirt_%d_0" % nc) >= 0:
		nc += 1
	var pel := sk.find_bone("pelvis")
	var p0 := sk.get_bone_global_rest(pel)
	var bones := PackedInt32Array()
	var att := []  # rest global bases of the bones (NB per column)
	var pts := PackedVector3Array()  # rest points (NB per column: root, knee, flap, hem)
	var o := PackedVector3Array()  # outwards, in the rest frame: 0 = front (+z), + towards the character's left (+x)
	var phi := PackedFloat32Array()  # rest angles from plumb, outwards (NK per column)
	var tau := PackedFloat32Array()  # rest share of a segment along the tangent (NK per column)
	var rin := PackedFloat32Array()  # and in its plane: sqrt(1 - tau^2)
	var lens := PackedFloat32Array()
	var dirs := PackedVector3Array()  # rest directions (NK per column)
	for j in nc:
		var th := TAU * j / nc
		var oj := Vector3(sin(th), 0, cos(th))
		var t := DOWN.cross(oj)
		o.append(oj)
		var gs := []
		for k in NB:
			var b := sk.find_bone("skirt_%d_%d" % [j, k])
			assert(b >= 0, "CharSkirt: skirt_%d_%d missing (regenerate the garment: 4 bones per column)" % [j, k])
			bones.append(b)
			gs.append(sk.get_bone_global_rest(b))
			att.append((gs[k] as Transform3D).basis)
			pts.append((gs[k] as Transform3D).origin)
		for k in NK:
			var v: Vector3 = (gs[k + 1] as Transform3D).origin - (gs[k] as Transform3D).origin
			var l := v.length()
			phi.append(atan2(v.dot(oj), v.dot(DOWN)))
			tau.append(v.dot(t) / l)
			rin.append(sqrt(maxf(0.0, 1.0 - pow(v.dot(t) / l, 2.0))))
			lens.append(l)
			dirs.append(v / l)
	# root weights: the hip band around each root, flattened (bone, weight, root in that bone's rest frame)
	var rw_b := PackedInt32Array()
	var rw_w := PackedFloat32Array()
	var rw_p := PackedVector3Array()
	var rw_n := PackedInt32Array()  # start index per column (+ end)
	if mi:
		var roots := []
		for j in nc:
			roots.append(pts[j * NB])
		var rw := root_weights(String(mi.name), mi.mesh, mi.skin, roots)
		for j in nc:
			rw_n.append(rw_b.size())
			var tot := 0.0
			var start := rw_b.size()
			for e in rw[j]:
				var bi := sk.find_bone(String(e[0]))
				if bi >= 0:
					rw_b.append(bi)
					rw_w.append(float(e[1]))
					rw_p.append(sk.get_bone_global_rest(bi).affine_inverse() * pts[j * NB])
					tot += float(e[1])
			for i in range(start, rw_b.size()):
				rw_w[i] /= maxf(1e-6, tot)
		rw_n.append(rw_b.size())
	# legs: per side, the chain thigh -> calf -> foot -> ball -> ball_leaf, capsules [radius at the bone, at its child]
	var legs := []
	var thighs := []
	for side in ["_l", "_r"]:
		var chain := PackedInt32Array()
		var r0 := PackedFloat32Array()
		var r1 := PackedFloat32Array()
		for s in SEGS:
			var r: Array = cfg.get("legs", {}).get(s[0], [0.09, 0.07])
			chain.append(sk.find_bone(s[0] + side))
			r0.append(float(r[0]))
			r1.append(float(r[1]))
		chain.append(sk.find_bone(SEGS[-1][1] + side))
		legs.append({chain = chain, r0 = r0, r1 = r1})
		thighs.append([chain[0], chain[1]])
	var posed := PackedInt32Array()
	for j in nc:
		for k in NK:
			posed.append(bones[j * NB + k])
	var rb := {}
	for b in rw_b:
		rb[b] = true
	var leg_bones := []
	for l in legs:
		for b in l.chain:
			leg_bones.append(b)
	return {nc = nc, bones = bones, posed = posed, att = att, pts = pts, o = o, phi = phi, tau = tau, rin = rin, lens = lens, dirs = dirs,
		rw_b = rw_b, rw_w = rw_w, rw_p = rw_p, rw_n = rw_n, pelvis = pel, p0 = p0, legs = legs,
		thighs = thighs, root_bones = rb.keys(), leg_bones = leg_bones,
		margin = float(cfg.get("margin", 0.015)), floor = float(cfg.get("floor", 0.02)),
		spread = deg_to_rad(float(cfg.get("spread", 40.0))), pleat = float(cfg.get("pleat", 0.6)),
		plumb = float(cfg.get("plumb", 0.8)), fold = deg_to_rad(float(cfg.get("fold", 9.0))), freq = float(cfg.get("freq", 2.2)), damp = float(cfg.get("damp", 0.35)),
		drag = deg_to_rad(float(cfg.get("drag", 6.0)))}


func setup(sk: Skeleton3D, cfg: Dictionary, mi: MeshInstance3D = null) -> void:
	name = "CharSkirt"
	rig = make_rig(sk, cfg, mi)
	every = maxi(1, int(cfg.get("every", 1)))
	var rest := []
	for b in sk.get_bone_count():
		rest.append(sk.get_bone_global_rest(b))
	calibrate(rig, rest)
	_g.resize(sk.get_bone_count())
	_phi = PackedFloat32Array()
	if OS.is_debug_build():
		print("[CharSkirt] setup: %d columns x %d segments, %d leg points, margin %.3f, floor %.3f, spread %.0f, pleat %.2f, spring %.1f Hz / %.2f" % [
			rig.nc, NK, (rig.cal_r as PackedFloat32Array).size() / (rig.nc * NK), rig.margin, rig.floor, rad_to_deg(rig.spread), rig.pleat, rig.freq, rig.damp])


## Leg sample points this frame (SAMPLES): positions and radii (+ margin, x the leg's age scale).
static func _leg_points(r: Dictionary, g: Array, pos: PackedVector3Array, rad: PackedFloat32Array) -> void:
	var margin: float = r.margin
	var n := 0
	for l in r.legs:
		var chain: PackedInt32Array = l.chain
		var r0: PackedFloat32Array = l.r0
		var r1: PackedFloat32Array = l.r1
		for s in r0.size():
			var ga: Transform3D = g[chain[s]]
			var a := ga.origin
			var b: Vector3 = (g[chain[s + 1]] as Transform3D).origin
			var k := ga.basis.x.length()  # age scale of the leg
			for u in SAMPLES[s]:
				pos[n] = a.lerp(b, u)
				rad[n] = (lerpf(r0[s], r1[s], u) + margin) * k
				n += 1


static func _npts(r: Dictionary) -> int:
	var n := 0
	for sm in SAMPLES:
		n += sm.size()
	return r.legs.size() * n


## Leg bounds of one segment level, point by point: for every leg point at the height of this level and every
## column whose sector (around the pelvis, widened by the point's radius) may hold it, the smallest angle (from
## plumb, outwards in the column's plane) for the segment from starts[j] of length lens[j] that keeps the point at
## its radius: the line's tangent when the point lies along the segment, the end's distance when it lies past the
## end. Radii are min(this frame, calibrated). Fills need (angle, -INF if none) and reach (how far along the
## segment the last point it has to pass nearly level ends: what a cloth draped over a knee or a leg on the floor
## covers before it falls).
static func _bounds(starts: PackedVector3Array, os: PackedVector3Array, ts: PackedVector3Array, lens: PackedFloat32Array,
		pos: PackedVector3Array, rads: PackedFloat32Array, c0s: PackedInt32Array, c1s: PackedInt32Array, hh: PackedFloat32Array,
		centre: Vector3, cal: PackedFloat32Array, k: int, np: int, nc: int, hs: float, need: PackedFloat32Array,
		reach: PackedFloat32Array) -> void:
	var y_hi := -INF
	var y_lo := INF
	var lmax := 0.0
	var ring := INF  # the nearest a start of this level comes to the pelvis axis
	for j in nc:
		need[j] = -INF
		reach[j] = 0.0
		var a := starts[j]
		y_hi = maxf(y_hi, a.y)
		y_lo = minf(y_lo, a.y)
		lmax = maxf(lmax, lens[j])
		ring = minf(ring, Vector2(a.x - centre.x, a.z - centre.z).length())
	y_hi += 0.14
	y_lo -= lmax + 0.14
	ring *= 0.9
	var stride := NK * np
	var base := k * np
	var mr2 := MIN_RHO_TOP * MIN_RHO_TOP if k == 0 else MIN_RHO * MIN_RHO
	for i in np:
		var p := pos[i]
		if p.y > y_hi or p.y < y_lo or hh[i] < ring:
			continue  # not at this level's height, or inside every column's start (the inner side of all of them)
		var rad0 := rads[i]
		for c in range(c0s[i], c1s[i] + 1):
			var j := c % nc
			if j < 0:
				j += nc
			var rad := cal[j * stride + base + i]
			if rad <= 0.0:
				continue
			if rad0 < rad:
				rad = rad0
			var v := p - starts[j]
			var x := v.dot(os[j])
			if x < -rad:
				continue  # on the inner side of this column
			var y := -v.y
			var rho2 := x * x + y * y
			var l := lens[j]
			var lr := l + rad
			if rho2 > lr * lr or rho2 < mr2:
				continue  # out of reach, or at the start (the segment above holds it)
			var rho := sqrt(rho2)
			if k == 1 and rho < rad + 0.05 and v.y < -0.05 and starts[j].y > 0.35:
				# the leg the segment above ended on (a knee under the cloth): it was wrapped from there, here it
				# only bends the cloth a little (a full tangent from its surface would throw the hem out level)
				rad *= 0.6
			var lat := v.dot(ts[j])
			if lat > rad + rho * hs or -lat > rad + rho * hs:
				continue  # out of this column's sector
			var d: float
			var tl := rho2 - rad * rad
			if tl <= l * l:
				d = asin(rad / rho)  # tangent: the point lies along the segment
			else:
				d = acos(clampf((rho2 + l * l - rad * rad) / (2.0 * rho * l), -1.0, 1.0))  # past the end: the end clears it
			var f := atan2(x, y) + d
			if f > need[j]:
				need[j] = f
			if f > HIGH:
				reach[j] = maxf(reach[j], sqrt(maxf(0.0, tl)) + rad)


## Broad phase: per leg point, the range of columns (c0..c1, may wrap) whose sector may hold it, and how far its
## sphere reaches from the pelvis axis (hh).
static func _ranges(pos: PackedVector3Array, rads: PackedFloat32Array, np: int, centre: Vector3, yaw: float, nc: int,
		c0s: PackedInt32Array, c1s: PackedInt32Array, hh: PackedFloat32Array) -> void:
	var step := TAU / nc
	for i in np:
		var dx := pos[i].x - centre.x
		var dz := pos[i].z - centre.z
		var h := sqrt(dx * dx + dz * dz)
		hh[i] = h + rads[i]
		var al := atan2(dx, dz) - yaw
		# generous: the exact sector test is in _bounds, seen from the segment's start, not the axis
		var half := step + (asin(minf(1.0, rads[i] / h)) if h > 1e-4 else PI)
		var c0 := int(floor((al - half) / step + 0.5))
		var c1 := int(floor((al + half) / step + 0.5))
		if c1 - c0 >= nc:
			c0 = 0
			c1 = nc - 1
		c0s[i] = c0
		c1s[i] = c1




## Calibration on the rest globals `g`: per column, segment and leg point, the largest radius that keeps the rest
## segment clear; per column and thigh capsule, the radius the root may sit at. The kit's capsules are generous;
## this makes them hug what the garment already clears.
static func calibrate(r: Dictionary, g: Array) -> void:
	var np := _npts(r)
	var pos := PackedVector3Array()
	var rad := PackedFloat32Array()
	pos.resize(np)
	rad.resize(np)
	_leg_points(r, g, pos, rad)
	var nc: int = r.nc
	var pts: PackedVector3Array = r.pts
	var cal := PackedFloat32Array()
	cal.resize(nc * NK * np)
	var cal_root := PackedFloat32Array()
	for j in nc:
		var o: Vector3 = r.o[j]
		for k in NK:
			var a := pts[j * NB + k]
			var b := pts[j * NB + k + 1]
			var phi_rest: float = r.phi[j * NK + k]
			for i in np:
				var v := pos[i] - a
				var al := atan2(v.dot(o), -v.y)
				var allowed: float
				if al >= phi_rest - deg_to_rad(1.0) and v.dot(o) > 0.0:
					allowed = 0.0  # the leg already sticks out of the cloth at rest here (toes under the hem): no constraint
				else:
					allowed = minf(rad[i], _seg_dist(pos[i], a, b) - 0.002)
				cal[(j * NK + k) * np + i] = maxf(0.0, allowed)
		for th in r.thighs:
			var d := _seg_dist(pts[j * NB], (g[th[0]] as Transform3D).origin, (g[th[1]] as Transform3D).origin)
			var leg: Dictionary = r.legs[0]
			cal_root.append(minf(float(leg.r0[0]) + r.margin, d - 0.003))
	r.cal_r = cal
	r.cal_root = cal_root
	r.np = np


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var u := clampf((p - a).dot(ab) / maxf(1e-8, ab.length_squared()), 0.0, 1.0)
	return (p - (a + ab * u)).length()


## Neighbours: a column hangs at most `spread` under a neighbour (every other one `spread` x (1 + pleat)).
static func _spread(v: PackedFloat32Array, k: int, nc: int, spread: float, pleat: float) -> void:
	var lo := INF
	var hi := -INF
	for j in nc:
		lo = minf(lo, v[j * NK + k])
		hi = maxf(hi, v[j * NK + k])
	if hi - lo <= spread:
		return
	for it in 2:
		for j in nc:
			var s := spread * (1.0 + pleat if j % 2 == 1 else 1.0)
			var m := maxf(v[((j + nc - 1) % nc) * NK + k], v[((j + 1) % nc) * NK + k]) - s
			if m > v[j * NK + k]:
				v[j * NK + k] = m


## Global transforms of the skirt bones for the bone globals `g` (indexed by bone; at least the pelvis, the root
## bones and the leg bones). Writes the posed ones into `g`. st: the spring state {phi, vel} (an empty Dictionary:
## none, the targets are used as they are; empty arrays: it starts on this pose), dt: seconds since the last solve,
## vel: the character's velocity in skeleton space.
static func solve(r: Dictionary, g: Array, st: Dictionary = {}, dt := 0.0, floor_y := 0.0, vel := Vector3.ZERO) -> void:
	var nc: int = r.nc
	var np: int = r.np
	var P: Transform3D = g[r.pelvis]
	var Q: Transform3D = P * (r.p0 as Transform3D).affine_inverse()
	var qb := Q.basis
	var qs := qb.x.length()
	var pos := PackedVector3Array()
	var rads := PackedFloat32Array()
	pos.resize(np)
	rads.resize(np)
	_leg_points(r, g, pos, rads)
	var fl: float = floor_y + r.floor
	var hs := sin(PI / nc)
	var fwd: Vector3 = qb * Vector3(0, 0, 1)
	var c0s := PackedInt32Array()
	var c1s := PackedInt32Array()
	var hh := PackedFloat32Array()
	c0s.resize(np)
	c1s.resize(np)
	hh.resize(np)
	_ranges(pos, rads, np, P.origin, atan2(fwd.x, fwd.z), nc, c0s, c1s, hh)
	var cal: PackedFloat32Array = r.cal_r
	var rest_phi: PackedFloat32Array = r.phi
	var taus: PackedFloat32Array = r.tau
	var rins: PackedFloat32Array = r.rin
	var lens: PackedFloat32Array = r.lens
	var pts: PackedVector3Array = r.pts
	var ro: PackedVector3Array = r.o
	var spread: float = r.spread
	var pleat: float = r.pleat
	var plumb: float = r.plumb
	var spring := not st.is_empty() and dt > 0.0
	var phi: PackedFloat32Array = st.get("phi", PackedFloat32Array())
	var pv: PackedFloat32Array = st.get("vel", PackedFloat32Array())
	if spring and phi.size() != nc * NK:
		spring = false
	var w := TAU * float(r.freq)
	var w2dt := w * w * dt
	var cdt := 2.0 * float(r.damp) * w * dt
	var drag: float = r.drag
	var hvel := Vector3(vel.x, 0, vel.z)
	# roots and column frames
	var at := PackedVector3Array()  # points of the columns this frame: NK + 1 per column (root, knee, flap, hem)
	at.resize(nc * (NK + 1))
	var os := PackedVector3Array()
	var ts := PackedVector3Array()
	os.resize(nc)
	ts.resize(nc)
	var rw_b: PackedInt32Array = r.rw_b
	var rw_w: PackedFloat32Array = r.rw_w
	var rw_p: PackedVector3Array = r.rw_p
	var rw_n: PackedInt32Array = r.rw_n
	var cal_root: PackedFloat32Array = r.cal_root
	var thighs: Array = r.thighs
	var nth := thighs.size()
	var th_a := PackedVector3Array()
	var th_ab := PackedVector3Array()
	var th_il := PackedFloat32Array()
	for th in thighs:
		var ta: Vector3 = (g[th[0]] as Transform3D).origin
		var ab: Vector3 = (g[th[1]] as Transform3D).origin - ta
		th_a.append(ta)
		th_ab.append(ab)
		th_il.append(1.0 / maxf(1e-8, ab.length_squared()))
	for j in nc:
		var R := Vector3.ZERO
		if rw_n.size() > 0:
			# skinned like the hip band around it
			for e in range(rw_n[j], rw_n[j + 1]):
				R += ((g[rw_b[e]] as Transform3D) * rw_p[e]) * rw_w[e]
		else:
			R = Q * pts[j * NB]
		# the root rises over a thigh that comes up under it (sitting, kneeling): never deeper than at rest
		for ti in nth:
			var rr: float = cal_root[j * nth + ti]
			for it in 3:
				var ab := th_ab[ti]
				var c := th_a[ti] + ab * clampf((R - th_a[ti]).dot(ab) * th_il[ti], 0.0, 1.0)
				var d := R.distance_to(c)
				if d >= rr:
					break
				R.y += rr - d
		var o: Vector3 = qb * ro[j]
		o.y = 0.0
		o = o.normalized() if o.length_squared() > 1e-6 else ro[j]
		at[j * (NK + 1)] = R
		os[j] = o
		ts[j] = DOWN.cross(o)
	# segment by segment, down the columns: hard bounds (legs, floor) and soft targets (gravity, drag)
	var hard := PackedFloat32Array()
	var soft := PackedFloat32Array()
	var ang := PackedFloat32Array()
	var kk := PackedFloat32Array()
	var dn := PackedVector3Array()
	hard.resize(nc * NK)
	soft.resize(nc * NK)
	ang.resize(nc * NK)
	kk.resize(nc * NK)
	dn.resize(nc * NK)
	var starts := PackedVector3Array()
	var lmax := PackedFloat32Array()
	var need := PackedFloat32Array()
	var reach := PackedFloat32Array()
	var lift := PackedFloat32Array()
	starts.resize(nc)
	lmax.resize(nc)
	need.resize(nc)
	reach.resize(nc)
	lift.resize(nc)
	var plumb_phi := deg_to_rad(4.0)
	var fold: float = r.fold
	var cover := deg_to_rad(25.0)
	var level := deg_to_rad(75.0)
	var lift_k := 1.0 / deg_to_rad(50.0)
	for k in NK:
		for j in nc:
			starts[j] = at[j * (NK + 1) + k]
			lmax[j] = lens[j * NK + k] * qs
		_bounds(starts, os, ts, lmax, pos, rads, c0s, c1s, hh, P.origin, cal, k, np, nc, hs, need, reach)
		var dk := drag * (1.0 + 0.5 * k)
		for j in nc:
			var q := j * NK + k
			var l := lmax[j]
			var ay := starts[j].y - fl
			var h := need[j]
			# the floor: the cloth gathers down to MIN_K before it is pushed outwards
			var lf := l * rins[q] * (1.0 if k == 0 else MIN_K)
			if ay < ON_FLOOR:
				h = maxf(h, FOLD)  # lying on the floor: folded outwards (and gathered, below)
			elif ay < lf:
				h = maxf(h, acos(clampf(ay / lf, -1.0, 1.0)))
			hard[q] = clampf(h, 0.0, MAX_PHI)
			# gravity: the rest flare, plumb under a lifted segment above; the speed drags it back
			var sf := rest_phi[q]
			if k > 0 and lift[j] > 0.0:
				# hanging from a lifted top the cloth falls in folds: every other column out, the next in
				sf = lerpf(sf, plumb_phi + (fold if j % 2 == 0 else -fold), plumb * lift[j])
			soft[q] = sf - dk * hvel.dot(os[j])
		_spread(hard, k, nc, spread, pleat)
		for j in nc:
			var q := j * NK + k
			var hq := hard[q]
			var f := maxf(hq, soft[q])
			if spring:
				# damped spring towards the target, never inside the legs
				var p0 := phi[q]
				var v := pv[q] + w2dt * (f - p0) - cdt * pv[q]
				f = p0 + v * dt
				if f < hq:
					# a leg pushes the cloth: it takes the leg's speed (up to PUSH), so it swings on a little
					v = maxf(v, minf((hq - p0) / dt, PUSH))
					f = hq
				pv[q] = clampf(v, -VMAX, VMAX)
				f = clampf(f, 0.0, MAX_PHI)
				phi[q] = f
			f = clampf(f, 0.0, MAX_PHI)
			ang[q] = f
			if k == 0:
				lift[j] = clampf((f - rest_phi[q]) * lift_k, 0.0, 1.0)
			var o := os[j]
			var d := (DOWN * cos(f) + o * sin(f)) * rins[q] + ts[j] * taus[q]
			dn[q] = d
			var l := lmax[j]
			var a := starts[j]
			# against the floor the segment gathers; draped over a leg near the floor, or over a knee nearly level, it
			# ends just past it (the cloth falls from there)
			var kf := 1.0
			if a.y - fl < ON_FLOOR:
				kf = MIN_K
			elif d.y < -1e-4:
				kf = clampf((a.y - fl) / (-d.y * l), MIN_K, 1.0)
			if reach[j] > 0.0 and hq > soft[q] + cover and ((k > 0 and a.y - fl < 0.3) or (k == 0 and hq > level)):
				kf = minf(kf, maxf(MIN_K, (reach[j] + 0.04) / l))
			kk[q] = kf
			at[j * (NK + 1) + k + 1] = a + d * (l * kf)
	if spring:
		st.phi = phi
		st.vel = pv
		var calm := true
		for q in nc * NK:
			if absf(pv[q]) > 0.15 or absf(maxf(hard[q], soft[q]) - phi[q]) > 0.02:
				calm = false
				break
		st.calm = calm
	elif st.has("dbg"):
		st.dbg = {hard = hard, soft = soft, ang = ang, kk = kk, at = at}
	elif not st.is_empty():
		st.calm = false
		# no spring yet (first frame): it starts at rest on this pose
		st.phi = ang
		var z := PackedFloat32Array()
		z.resize(nc * NK)
		st.vel = z
	# bone globals: the rest frame carried by the pelvis, turned onto the new directions (scaled along the bone
	# when gathered)
	var att: Array = r.att
	var bones: PackedInt32Array = r.bones
	var dirs: PackedVector3Array = r.dirs
	for j in nc:
		var b := Basis()
		for k in NK:
			var q := j * NK + k
			b = Basis(Quaternion((qb * dirs[q]).normalized(), dn[q].normalized())) * qb * (att[j * NB + k] as Basis)
			if kk[q] < 0.999:
				b = b * Basis.from_scale(Vector3(1.0, kk[q], 1.0))
			g[bones[j * NB + k]] = Transform3D(b, at[j * (NK + 1) + k])






var _st := {phi = PackedFloat32Array(), vel = PackedFloat32Array()}


func _process_modification_with_delta(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var sk := get_skeleton()
	if sk == null or rig.is_empty():
		return
	var P: Transform3D = sk.get_bone_global_pose(rig.pelvis)
	_g[rig.pelvis] = P
	for b in rig.root_bones:
		_g[b] = sk.get_bone_global_pose(b)
	# the character's speed (skeleton space), smoothed: the drag on the cloth
	var gp := sk.global_position
	if _last_pos != Vector3.INF and delta > 0.0:
		var v := sk.global_transform.basis.inverse() * ((gp - _last_pos) / delta)
		_speed = _speed.lerp(v, minf(1.0, delta * 8.0))
	_last_pos = gp
	# the legs seen from the pelvis: if they have not moved since the last solve (standing, sitting still), the body
	# does not move and the spring has settled, the skirt keeps its pose and nothing is solved
	var key := PackedVector3Array()
	var pinv := P.affine_inverse()
	for b in rig.leg_bones:
		_g[b] = sk.get_bone_global_pose(b)
	for l in rig.legs:
		key.append(pinv * (_g[(l.chain as PackedInt32Array)[1]] as Transform3D).origin)
		key.append(pinv * (_g[(l.chain as PackedInt32Array)[2]] as Transform3D).origin)
	key.append(P.basis.y.normalized() * 0.3)  # the pelvis tilt (about 1 degree counts)
	key.append(_speed * 0.1)
	_frame += 1
	var still := key.size() == _key.size()
	if still:
		for i in key.size():
			if key[i].distance_squared_to(_key[i]) > STILL * STILL:
				still = false
				break
	if _locals.is_empty() or ((not still or not _st.get("calm", false)) and _frame % every == 0):
		_key = key
		# floor under the feet: the skeleton's y = 0 is the character's floor (the armature offset moves the feet
		# onto it)
		var floor_y := -(sk.get_parent() as Node3D).position.y if sk.get_parent() is Node3D else 0.0
		var ts0 := Time.get_ticks_usec()
		solve(rig, _g, _st, delta * every, floor_y, _speed)
		prof_solve += Time.get_ticks_usec() - ts0
		_locals.clear()
		for b in rig.posed:
			_locals.append(pinv * (_g[b] as Transform3D))
		_solves += 1
	var i := 0
	for b in rig.posed:
		sk.set_bone_pose(b, _locals[i])
		i += 1
	prof_us += Time.get_ticks_usec() - t0
	prof_calls += 1
