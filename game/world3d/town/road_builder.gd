class_name RoadBuilder
extends RefCounted
## Builds organic road ribbons from plan-space polylines (x right, y back; see HouseBuilder).
## The polyline is smoothed (Catmull-Rom), resampled every STEP metres and its half width wobbles
## with noise; the road shader cuts a ragged edge, so nothing ends up straight.

const STEP := 0.5

static var _noise: FastNoiseLite
## Half widths travel in COLOR.r as hw / hw_unit (8-bit): raise it (and the shader's hw_unit) for wide ribbons.
static var hw_unit := 10.0


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _resample(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size() - 1:
		var p0: Vector2 = pts[max(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[min(i + 2, pts.size() - 1)]
		var n := maxi(1, int(p1.distance_to(p2) / STEP))
		for k in n:
			out.append(_catmull(p0, p1, p2, p3, float(k) / n))
	out.append(pts[pts.size() - 1])
	return out


## pts: plan-space Vector2 points. width: full width in metres. lift: small height to avoid z-fighting.
static func build(pts: Array, width: float, material: Material, lift := 0.012, seed := 1) -> MeshInstance3D:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.frequency = 0.08
	_noise.seed = seed
	var gpts := []
	for p in pts:
		gpts.append(Vector2(p.x, -p.y))  # plan -> godot xz
	var line := _resample(gpts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := [-1.0, -0.5, 0.0, 0.5, 1.0]
	var dist := 0.0
	var rows := []
	for i in line.size():
		var a := line[max(i - 1, 0)]
		var b := line[min(i + 1, line.size() - 1)]
		var tan := (b - a).normalized()
		var nrm := Vector2(-tan.y, tan.x)
		if i > 0:
			dist += line[i].distance_to(line[i - 1])
		var hw: float = width * 0.5 * (1.0 + 0.18 * _noise.get_noise_1d(dist))
		var ext := hw * 1.25
		var row := []
		for c in cols:
			var p: Vector2 = line[i] + nrm * c * ext
			row.append([Vector3(p.x, lift, p.y), Vector2(dist, c * ext), hw])
		rows.append(row)
	for i in rows.size() - 1:
		for j in cols.size() - 1:
			var quad := [rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j], rows[i + 1][j + 1], rows[i][j + 1]]
			for v in quad:
				st.set_color(Color(v[2] / hw_unit, 0, 0))
				st.set_uv(v[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A rounded patch (plaza, yard) for the road shader: UV.y = metres from the centre, so the shader's
## ragged edge and cobbled core work radially. r = half sizes; n = superellipse exponent (2 ellipse, 4+ rounded box).
static func disc(r: Vector2, n: float, material: Material, rings := 6, segs := 72) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := func(a: float) -> float:
		return pow(pow(absf(cos(a)) / r.x, n) + pow(absf(sin(a)) / r.y, n), -1.0 / n)
	for k in rings:
		var f0 := 1.3 * k / rings
		var f1 := 1.3 * (k + 1) / rings
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var quad := [[f0, a0], [f1, a1], [f1, a0], [f0, a0], [f0, a1], [f1, a1]]  # clockwise seen from above
			for q in quad:
				var edge: float = rim.call(q[1])
				var dist: float = edge * q[0]
				st.set_color(Color(edge / hw_unit, 0, 0))
				st.set_uv(Vector2(q[1] * edge, dist))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(cos(q[1]) * dist, 0, -sin(q[1]) * dist))
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
