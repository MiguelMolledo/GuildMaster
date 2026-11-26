class_name Convoy
extends Node3D
## A cart of the extras drawn along a polyline by the animals hitched to it: the animals walk at the pace of their walk
## animation, the cart follows the hitch as a trailer does (its axle keeps its distance to the hitch, so it cuts the
## corners a little) and its wheels turn by the distance covered over their radius.
##   var c := Convoy.make("carro_bueyes_marcha", "buey", [Vector2(0, 0), Vector2(20, 0), Vector2(20, 12)], {"loop": true})
##   add_child(c)
## The cart must be one of the pieces with wheel nodes (catalogue: nodes rueda_*, axles, hitch, team). Plan coordinates
## as in HouseBuilder (x right, y back); the convoy node stays at the origin and moves its children.
## opts: loop (the path closes on itself), speed (m/s; default the animal's walk_speed), coat (of the animals), start
## (metres along the path), ground (height). step(dt) can be driven by hand with set_process(false).

signal arrived

var cart: Node3D
var animals: Array[Node3D] = []
var path := PackedVector2Array()
var loop := false
var speed := 0.6
var ground := 0.0
var moving := true
var travelled := 0.0          # metres of path behind the hitch

var _lens := PackedFloat32Array()
var _total := 0.0
var _hitch_y := -3.0           # in the cart's own plan frame (its front looks to -y)
var _axle_y := 0.0
var _animal_back := 0.9        # the animal's origin behind the hitch point (the yoke sits on its neck)
var _offsets: Array = []       # sideways offset of each animal
var _axle := Vector2.ZERO      # plan position of the axle
var _wheels: Array = []        # [node, axis (godot), radius]
var _walk := 0.6


static func make(cart_id: String, animal_id: String, pts: Array, opts := {}) -> Convoy:
	var c := Convoy.new()
	c.name = "Convoy_" + cart_id
	var inf := LandmarkBuilder.info(cart_id)
	c.cart = LandmarkBuilder.piece(cart_id)
	if c.cart == null:
		return null
	c.add_child(c.cart)
	var seen := {}
	for a in LandmarkBuilder.animated(c.cart):
		if String(a.name).begins_with("rueda") and not seen.has(a.node):
			seen[a.node] = true
			c._wheels.append([a.node, a.axis, float(a.info.get("radius", 0.5))])
	var hitch: Array = inf.get("hitch", [[0, -3.0]])
	var axles: Array = inf.get("axles", [0.0])
	c._hitch_y = float(hitch[0][1])
	c._axle_y = float(axles[axles.size() - 1])       # the rear axle steers nothing: it is the one that trails
	var ainf := LandmarkBuilder.info(animal_id)
	c._walk = float(ainf.get("walk_speed", 0.6))
	c.speed = float(opts.get("speed", c._walk))
	# the yoke or the collar sits on the neck, ahead of the animal's middle by about a third of its length
	c._animal_back = float(ainf.get("size", [0, 2.0, 0])[1]) * (0.36 if hitch.size() > 1 else 0.05)
	for h in hitch:
		var an := LandmarkBuilder.animal(animal_id, "andar", String(opts.get("coat", "")), c.animals.size() + int(opts.get("seed", 0)))
		if an == null:
			continue
		c.add_child(an)
		c.animals.append(an)
		c._offsets.append(float(h[0]))
		var ap := an.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:      # a pair does not step together
			ap.seek(0.37 * c.animals.size() * ap.current_animation_length, true)
	c.loop = bool(opts.get("loop", false))
	c.ground = float(opts.get("ground", 0.0))
	# a team cannot turn on a point: every corner of the polyline is rounded with an arc of `corner` metres
	# (default: enough for the cart's length), so the animals lead the cart round it instead of snapping to the new way
	var rad := float(opts.get("corner", maxf(2.0, (c._axle_y - c._hitch_y) * 0.9)))
	for p in _rounded(pts, rad, c.loop):
		c.path.append(p)
	if c.loop and c.path.size() > 2:
		c.path.append(c.path[0])
	for i in range(c.path.size() - 1):
		c._lens.append(c.path[i].distance_to(c.path[i + 1]))
		c._total += c._lens[i]
	c.travelled = float(opts.get("start", 0.0))
	var p0 := c._at(c.travelled)
	var d0 := c._dir(c.travelled)
	c._axle = p0 - d0 * (c._axle_y - c._hitch_y)
	c._place(0.0)
	if OS.is_debug_build():
		print("[Convoy] %s with %d %s: path %.1f m, %.2f m/s, %d wheels, hitch-axle %.2f m" % [cart_id, c.animals.size(), animal_id, c._total, c.speed, c._wheels.size(),
			c._axle_y - c._hitch_y])
	return c


static func _rounded(pts: Array, rad: float, closed: bool) -> Array:
	## the polyline with its corners cut by arcs: each corner starts and ends `rad` (or half the shorter leg) from it
	var n := pts.size()
	if n < 3 or rad <= 0.0:
		return pts
	var out := []
	for i in n:
		var p: Vector2 = pts[i]
		if not closed and (i == 0 or i == n - 1):
			out.append(p)
			continue
		var a: Vector2 = pts[(i - 1 + n) % n]
		var b: Vector2 = pts[(i + 1) % n]
		var r := minf(rad, minf(p.distance_to(a), p.distance_to(b)) * 0.5)
		var p0 := p + (a - p).normalized() * r
		var p1 := p + (b - p).normalized() * r
		for k in 7:
			var t := k / 6.0
			out.append(p0.lerp(p, t).lerp(p.lerp(p1, t), t))      # a quadratic curve through the cut corner
	return out


func _process(dt: float) -> void:
	step(dt)


func _at(s: float) -> Vector2:
	if path.size() < 2:
		return path[0] if path.size() == 1 else Vector2.ZERO
	s = fposmod(s, _total) if loop else clampf(s, 0.0, _total)
	for i in _lens.size():
		if s <= _lens[i] or i == _lens.size() - 1:
			return path[i].lerp(path[i + 1], s / maxf(_lens[i], 1e-4))
		s -= _lens[i]
	return path[path.size() - 1]


func _dir(s: float) -> Vector2:
	var d := _at(s + 0.6) - _at(s - 0.6) if loop else _at(minf(s + 0.6, _total)) - _at(maxf(s - 0.6, 0.0))
	return d.normalized() if d.length() > 1e-4 else Vector2(0, -1)


func step(dt: float) -> void:
	if not moving or path.size() < 2:
		return
	var ds := speed * dt
	if not loop and travelled + ds >= _total:
		ds = _total - travelled
		moving = false
		for an in animals:
			LandmarkBuilder.play(an, "quieto")
		arrived.emit()
	travelled += ds
	_place(ds)


func _place(ds: float) -> void:
	var hitch := _at(travelled)
	# the axle trails the hitch at a fixed distance: it moves only along the line that joins them
	var back := _axle - hitch
	var ln := _axle_y - _hitch_y
	var before := _axle
	_axle = hitch + (back.normalized() if back.length() > 1e-4 else -_dir(travelled)) * ln
	var fwd := (hitch - _axle).normalized()          # the way the cart looks (its own -y)
	var yaw := atan2(-fwd.x, fwd.y) + PI             # the pieces look to plan -y (Godot +z)
	var side := Vector2(-fwd.y, fwd.x)               # the cart's own +x
	var origin := _axle + fwd * _axle_y              # the axle is at y = _axle_y of the cart, and its y runs backwards
	cart.position = Vector3(origin.x, ground, -origin.y)
	cart.rotation.y = yaw
	var rolled := (_axle - before).dot(fwd) if ds > 0.0 else 0.0
	for w in _wheels:
		(w[0] as Node3D).rotate_object_local(w[1], rolled / maxf(float(w[2]), 0.05))
	# the animals walk the path itself, ahead of the cart: they look the way the path goes where they are, not the way
	# the cart still points, so in a corner the team turns first and the cart follows
	var lead := _at(travelled + 0.01)
	var tdir := _dir(travelled)
	var tside := Vector2(-tdir.y, tdir.x)
	var ayaw := atan2(-tdir.x, tdir.y) + PI
	for i in animals.size():
		var p := lead - tdir * _animal_back + tside * float(_offsets[i])
		animals[i].position = Vector3(p.x, ground, -p.y)
		animals[i].rotation.y = ayaw
