extends Node3D
## (no class_name: WorldView3D preloads it, FIELDS)
## The fields of a farm in the 3D town (docs/3d/repaso_oficios.md). The sim's field zones (Fields.zones: kind "field")
## have no place in the farmhouse's layout: here each one is a bed outside, on the tiles of the farm's lot that its
## house does not cover (else in a row behind the house), dressed by its state: bare soil (fallow, plowed), wheat sown,
## growing, ready, rotten. The house open in place puts each field's mark over its bed (InteriorBridge3D.station_screen
## asks point()). Reads only; rebuilt with the town (WorldView3D.build), dressed again when a field changes.

const BED: float = 1.5           # metres a side of a bed
const PIECE_SIZE: float = 2.0    # the kit's crop beds are one 2D tile (2 m)
const SOIL: Color = Color(0.36, 0.25, 0.16)
const SOIL_FALLOW: Color = Color(0.45, 0.36, 0.25)

var town: Town3D = null
var sim: Sim = null
var _beds: Dictionary = {}   # bld -> {zone: {"node": Node3D, "at": Vector3 (town local), "look": String}}
var _house: Dictionary = {}  # bld -> the house node the beds were laid out for
var _t: float = 0.0


func setup(t: Town3D, s: Sim) -> void:
	town = t
	sim = s
	rebuild()


func rebuild() -> void:
	for c: Node in get_children():
		c.queue_free()
	_beds.clear()
	_house.clear()
	if town == null or sim == null:
		return
	for b: String in sim.state.buildings:
		var zones := Fields.zones(sim, b)
		if zones.is_empty() or not town.bld_anchor.has(b):
			continue
		var h: Node3D = town.bld_anchor[b].get("house")
		if h == null or not is_instance_valid(h):
			continue
		_house[b] = h
		var spots := _spots(h, zones.size())
		_beds[b] = {}
		for k: int in zones.size():
			var root := Node3D.new()
			root.name = "Field_%s_%s" % [b, zones[k]]
			root.position = spots[k]
			root.rotation.y = _in_town(h).basis.get_euler().y
			add_child(root)
			_beds[b][zones[k]] = {"node": root, "at": spots[k], "look": ""}
		if OS.is_debug_build():
			print("[FarmFields3D] %s: %d fields at %s" % [b, zones.size(), spots])
	_dress()


## Where the bed of field `zone` of `bld` is (town local; Vector3.INF if it has none).
func point(bld: String, zone: String) -> Vector3:
	if not _beds.has(bld) or not (_beds[bld] as Dictionary).has(zone):
		return Vector3.INF
	return _beds[bld][zone]["at"]


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5 or sim == null:
		return
	_t = 0.0
	for b: String in _house:   # the town rebuilt that house (an upgrade, works): lay the beds out again
		if not town.bld_anchor.has(b) or town.bld_anchor[b].get("house") != _house[b]:
			rebuild()
			return
	_dress()


## The bed centres: along the lot's tiles the house leaves free, else in a row behind the house.
func _spots(h: Node3D, n: int) -> Array:
	var ht := _in_town(h)
	var wd: Vector2 = h.get_meta("wd", Vector2(6, 6))
	var box: Rect2i = h.get_meta("box", Rect2i())
	var free: Array = []
	for r: int in range(box.position.y, box.end.y):
		for c: int in range(box.position.x, box.end.x):
			var p := town._tp(c, r)
			var at := HouseBuilder.plan_to_godot(Vector3(p.x, p.y, 0.0))
			var local := ht.affine_inverse() * at
			if absf(local.x) > wd.x / 2.0 - 0.2 or absf(local.z) > wd.y / 2.0 - 0.2:
				free.append(at)
	var out: Array = []
	if free.size() >= 1:
		# the strip of free tiles: from the first to the last, a tile beyond each end, the beds spread along it
		var a: Vector3 = free[0]
		var z: Vector3 = free[free.size() - 1]
		var dir := (z - a).normalized() if a.distance_to(z) > 0.01 else ht.basis.x.normalized()
		var length := a.distance_to(z) + PIECE_SIZE
		var start := a - dir * PIECE_SIZE / 2.0
		for k: int in n:
			out.append(start + dir * length * (float(k) + 0.5) / float(n) + Vector3(0, 0.02, 0))
		return out
	for k: int in n:   # no free tile: behind the house (plan y back = godot -z)
		var local := Vector3(-wd.x / 2.0 + wd.x * (float(k) + 0.5) / float(n), 0.02, -(wd.y / 2.0 + BED / 2.0 + 0.3))
		out.append(ht * local)
	return out


## The house's transform in the town's space (it hangs from a container of the town).
func _in_town(h: Node3D) -> Transform3D:
	return town.global_transform.affine_inverse() * h.global_transform


## Each bed as its field is: the soil, and the wheat by its state.
func _dress() -> void:
	for b: String in _beds:
		for zone: String in _beds[b]:
			var bed: Dictionary = _beds[b][zone]
			var f := Fields.peek(sim.state, b, zone)
			var look := _look_of(f)
			if look == str(bed["look"]):
				continue
			bed["look"] = look
			var root: Node3D = bed["node"]
			for c: Node in root.get_children():
				c.queue_free()
			var soil := MeshInstance3D.new()
			var m := BoxMesh.new()
			m.size = Vector3(BED, 0.06, BED)
			soil.mesh = m
			var mat := StandardMaterial3D.new()
			mat.albedo_color = SOIL_FALLOW if look == "fallow" else SOIL
			mat.roughness = 1.0
			soil.material_override = mat
			root.add_child(soil)
			var piece := ""
			match look:
				"sown", "rotten":
					piece = "bancal_trigo_1"
				"growing":
					piece = "bancal_trigo_2"
				"ready":
					piece = "bancal_trigo_3"
			if piece != "":
				var n: Node3D = LandmarkBuilder.piece(piece) if LandmarkBuilder.catalog().get("pieces", {}).has(piece) \
					else LandmarkBuilder.build(piece)
				if n != null:
					n.scale = Vector3.ONE * (BED / PIECE_SIZE)
					root.add_child(n)
			if OS.is_debug_build():
				print("[FarmFields3D] %s %s: %s" % [b, zone, look])


static func _look_of(f: Dictionary) -> String:
	match str(f.get("state", "fallow")):
		"growing":
			return "sown" if float(f.get("growth", 0.0)) < 1.0 else "growing"
		"ready":
			return "ready"
		"rotten":
			return "rotten"
		"plowed":
			return "plowed"
	return "fallow"
