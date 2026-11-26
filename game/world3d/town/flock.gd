class_name Flock
extends MultiMeshInstance3D
## A flock of birds (pigeons over the roofs) circling over this node: one MultiMesh whose instances are moved and
## flapped by shaders/flock.gdshader, so the whole flock is one draw call and costs no script time.
##   var f := Flock.make(14, {"radius": 16.0, "height": 11.0})
##   f.position = centre_of_the_square
## opts: radius (m), height (m over the node), speed (m/s), spread (how much of the circle the flock takes, 0..1),
## size (wing span in metres), seed. The node's own transform places the circle.

const SHADER := "res://game/world3d/shaders/flock.gdshader"


static func make(n := 14, opts := {}) -> Flock:
	var f := Flock.new()
	f.name = "Bandada"
	var radius := float(opts.get("radius", 16.0))
	var height := float(opts.get("height", 11.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _bird(float(opts.get("size", 0.62)))
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 7))
	var spread := float(opts.get("spread", 0.16))
	for i in n:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		# x: place along the circle, y: radius factor, z: height offset, w: random (wing beat, tint)
		mm.set_instance_custom_data(i, Color(rng.randf() * spread, rng.randf_range(0.82, 1.18), rng.randf_range(-1.6, 1.6), rng.randf()))
	f.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("height", height)
	m.set_shader_parameter("speed", float(opts.get("speed", 6.5)))
	f.material_override = m
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the shader moves the birds: the box that is culled is the whole circle
	f.custom_aabb = AABB(Vector3(-radius * 1.3, height - 4.0, -radius * 1.3), Vector3(radius * 2.6, 8.0, radius * 2.6))
	f.add_to_group("tree")      # no outline pass, as the trees
	if OS.is_debug_build():
		print("[Flock] %d birds, radius %.1f m, height %.1f m, %d triangles each" % [n, radius, height, 7])
	return f


static func _bird(span: float) -> ArrayMesh:
	## a bird seen from afar: a body, two wings of two faces each and a tail. Looks to +z, wings along x.
	## COLOR.r = 1 on the wing vertices (the shader beats them), COLOR.g = shade of the face
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := span / 2.0
	var body := [Vector3(0, 0, 0.26 * span), Vector3(0.05 * span, 0, 0.0), Vector3(-0.05 * span, 0, 0.0), Vector3(0, 0, -0.2 * span), Vector3(0, 0.05 * span, 0.02 * span)]
	var tris := [
		[body[0], body[1], body[4], 0.0, 1.0], [body[0], body[4], body[2], 0.0, 0.9], [body[4], body[1], body[3], 0.0, 0.85], [body[4], body[3], body[2], 0.0, 0.8],
		[body[3] + Vector3(0, 0, 0.03 * span), Vector3(0.07 * span, 0, -0.34 * span), Vector3(-0.07 * span, 0, -0.34 * span), 0.0, 0.7]]
	for t in tris:
		for k in 3:
			st.set_color(Color(t[3], t[4], 0))
			st.add_vertex(t[k])
	for sx in [-1.0, 1.0]:
		var root_f := Vector3(sx * 0.04 * span, 0.01 * span, 0.12 * span)
		var root_b := Vector3(sx * 0.04 * span, 0.01 * span, -0.08 * span)
		var mid_f := Vector3(sx * 0.3 * span, 0.01 * span, 0.14 * span)
		var mid_b := Vector3(sx * 0.3 * span, 0.01 * span, -0.1 * span)
		var tip := Vector3(sx * h, 0.01 * span, -0.06 * span)
		for t in [[root_f, mid_f, root_b, 0.95], [mid_f, mid_b, root_b, 0.95], [mid_f, tip, mid_b, 0.78]]:
			for k in 3:
				st.set_color(Color(1.0, t[3], 0))
				st.add_vertex(t[k])
	return st.commit()
