extends Node3D
## The festivals and the town events of GuildMaster in the town of the sim (docs/fiestas.md, «En el pueblo»).
## A child of the town (pueblo.gd / sim3d.gd / sim3d_chars.gd), made by PuebloVivo.live(). It reads what is on from the
## trace (tools/sim_trace.gd: `festivals` and `events`, with their start, end and programme) or, with an old trace
## without them, from GuildMaster's calendar (the fixed festival of each day). Each festival or event has its town
## layout in data/fiestas.json `pueblo`: pieces of kit/fiestas, kit/extras and kit/landmarks by site (plaza centre,
## ring, edges, the main street, overhead, balconies, doors of the hosts, the church, the town hall, the meadow north of
## the town, the outskirts by the gates) and rigid groups (the tilt yard). A solver puts each one on the real plan:
## never on a house, water, a stall, a bench, a prop, a tree or before a door, and where the trace walks least while it
## stands there; what blocks gets an obstacle the view steers walkers round (sim3d.gd avoid). The pieces go up at the
## start of the festival (the overhead dressing and the maypole from the eve) and come down at its end.
## The people: who the trace has standing in the plaza (chat, stroll, social...) during a festival goes to a use point
## of a piece (catalogue `use`: seats of the stands and the banquet tables, a ring round the bonfire) and does its action
## there (sits, watches, dances after the dance hour); the procession (holy week, rogation, corpus, the marquis's
## reception) walks a route from the church round the plaza with its pieces carried by hooded bearers; the giants and
## big-heads of the carnival walk round the plaza.
## Arguments: --fiesta=<id>[,<id>] force those (festival or event ids of GuildMaster) on the second day of the trace
## (the one the views and the measures of sim3d_chars look at), instead of what the trace has;
## --fiesta=no nothing; --fiesta_gente=no no people at the pieces, no procession.

const DATA := "res://data/view3d/fiestas.json"
const FIRE_SHADER := "res://game/world3d/shaders/fuego.gdshader"
const LAT := 0.25
const FAR_ZOOM := 40.0
const BODY := 0.3
const WALK_M_PER_MIN := 1.0  # the sim: one tile (2 m) per minutes_per_tile (2)
var GM_FESTIVALS: String = "res://data/festivals.json"  # GuildMaster: its own calendar
const IDLE_DOING := ["chat", "greet", "court", "social", "stroll", "stand", "leisure", "watch_show", "watch_fight",
	"mass", "visit_noble", "visit_pilgrim", "visit_merchant", "visit_minstrel", "visit_soldier", "visit_peddler",
	"visit_beggar", "play"]
## catalogue action -> [animation, animation after the dance hour]
const ACTION_ANIM := {"mirar": ["Idle", "Dance"], "sentarse": ["Sitting_Idle", "Sitting_Talking"], "estar": ["Idle_Talking", "Dance"],
	"escuchar": ["Idle", "Idle"], "comprar": ["Interact", "Interact"], "leer": ["Idle", "Idle"],
	"esperar_cuenco": ["Idle", "Idle"], "alistarse": ["Idle_Talking", "Idle_Talking"], "bailar": ["Dance", "Dance"],
	"actuar": ["Idle_Talking", "Dance"], "predicar": ["Idle_Talking", "Idle_Talking"], "hablar": ["Idle_Talking", "Idle_Talking"],
	"coger_bordon": ["Interact", "Interact"]}

var town                 # the town node (untyped: its members are read as they are)
var fe := {}             # data/fiestas.json
var layouts := {}        # def -> its town layout (data/fiestas.json pueblo)
var insts: Array = []    # [{def, kind, start, end, eve, schedule: [{what, at}], hosts, couple, placed: [], mounted}]
var block := {}          # Vector2i lattice cell (godot x/z / LAT) -> bits: 1 solid, 2 before a door, 4 a festival piece
var visits := {}         # Vector2i tile -> [[minute in, minute out], ...] of the trace
var plaza := Rect2()     # godot x/z of the plaza tiles
var plaza_mid := Vector2.ZERO
var main_rows: Array = []  # rows of the main street
var stats := {"pieces": 0, "no_room": 0, "missing": 0, "walked_centres": 0, "groups": 0}
var _sites := {}
var _boxes: Array = []   # [{g, rot, half, a, b}] the festival pieces placed: two only clash if they stand at the same time
var _fire_mat: ShaderMaterial
var _glow_mat: StandardMaterial3D
var _spark_mesh: QuadMesh
var _spark_pm: ParticleProcessMaterial
var _night := -1
var _far := -1
var _t := 0.0
var _args: PackedStringArray
var _gente := true
var _last_t := -1.0e9
var _drive := {}         # chr id -> {use: {inst, piece, i}, anim, from: Vector3, t0, path: [Vector3]}
var _taken := {}
var _reach := 14.0
var _uses_cache: Array = []
var _uses_dirty := true
var _seek_t := 0.0
var _by_key := {}
var _by_key_src = null       # the free people look for a use point every 0.25 s, not every frame
var _cost := {"us": 0, "frames": 0}         # "inst|piece|use" -> chr id
var _walkers: Array = [] # procession and carnival: [{inst, node, role, offset, lateral, piece, anim}]
var _lights: Array = []  # [OmniLight3D, base energy, phase, inst]
var _flames: Array = []  # [MeshInstance3D flames, inst, lit_from minute]
var _sparks: Array = []  # [GPUParticles3D, inst, lit_from minute]
var _smokes: Array = []  # [GPUParticles3D, inst, lit_from minute]: the smoke of the bonfires (scripts/clima/vida.gd's)
## The festival or event standing now (its def id, "" if none; the first by priority): the sound reads it in the group
## "suceso" (scripts/audio/sonido.gd: the music and the sounds of the festival, docs/sonido.md).
var suceso: String:
	get:
		var timed: bool = town != null and "t_min" in town
		for i in insts:
			if i.mounted and (not timed or float(town.t_min) >= float(i.start)):
				return String(i.def)
		return ""


func setup(t) -> void:
	town = t
	name = "FiestasPueblo"
	add_to_group("suceso")
	process_priority = 100  # after the town's own _process (sim3d_chars moves and animates the people first)
	_args = OS.get_cmdline_user_args()
	var force := ""
	for a in _args:
		if a.begins_with("--fiesta="):
			force = a.trim_prefix("--fiesta=")
		elif a == "--fiesta_gente=no":
			_gente = false
	if force == "no":
		_log("off (--fiesta=no)")
		return
	fe = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	layouts = fe.get("pueblo", {})
	if layouts.is_empty() or LandmarkBuilder.catalog().is_empty():
		_log("no town layouts in %s or no kit/fiestas: nothing to put up" % DATA)
		return
	_instances(force)
	if insts.is_empty():
		_log("no festival nor event in force in the trace")
		return
	var us := Time.get_ticks_usec()
	_map_sites()
	_visits()
	_lattice()
	for a in _args:
		if a.begins_with("--fp_mapa="):
			_dump_map(a.trim_prefix("--fp_mapa="))
	for inst in insts:
		_plan(inst)
	_log("%d festivals/events, %d pieces planned (%d without room, %d unknown), %d groups; %d tile centres the trace walks under a piece while it stands; %.0f ms" % [
		insts.size(), stats.pieces, stats.no_room, stats.missing, stats.groups, stats.walked_centres, float(Time.get_ticks_usec() - us) / 1000.0])
	if "--simcheck" in _args and "trace" in town and town.trace is Dictionary and town.trace.has("characters"):
		_check()
	# a town without the sim (pueblo.tscn): the forced festivals stand at once
	if not ("t_min" in town):
		for inst in insts:
			_mount(inst)


func _log(msg: String) -> void:
	if OS.is_debug_build():
		print("[FiestasPueblo] " + msg)


# ---------------------------------------------------------------- what is on
func _instances(force: String) -> void:
	var trace: Dictionary = town.trace if "trace" in town and town.trace is Dictionary else {}
	var gm: Dictionary = {}
	var gtxt := FileAccess.get_file_as_string(GM_FESTIVALS)
	if gtxt != "":
		gm = JSON.parse_string(gtxt)
	var defs: Dictionary = gm.get("festivals", {})
	var t0 := float(trace.get("meta", {}).get("start_minute", 0))
	var t1 := float(trace.get("meta", {}).get("end_minute", 1440))
	var day0 := int(floor(t0 / 1440.0))
	if force != "":
		# the second day of the trace (the one sim3d_chars --vistas, --bench and --dcprof look at), or its only day
		var day := day0 + 1 if t1 - (day0 + 1) * 1440.0 >= 20 * 60 else day0
		for id in force.split(","):
			var d: Dictionary = defs.get(id, {})
			var s := day * 1440 + int(d.get("start_hour", 0)) * 60
			var e := s + int(d.get("hours", 24)) * 60
			if d.is_empty():  # an event: the whole day
				s = day * 1440
				e = s + 1440
			if trace.is_empty():
				s = -1000000
				e = 1000000
			insts.append(_inst(id, "festival" if not d.is_empty() else "event", s, e, s - 17 * 60, d, day, [], []))
		_log("forced %s on day %d" % [force, day])
		return
	if trace.has("festivals"):
		for f: Dictionary in trace.festivals:
			if float(f.end) <= t0 or float(f.start) >= t1:
				continue
			var i := _inst(String(f.def), "festival", int(f.start), int(f.end), int(f.get("announce", int(f.start) - 720)),
				defs.get(String(f.def), {}), int(f.day), f.get("hosts", []), f.get("couple", []))
			if f.has("schedule"):
				i.schedule = f.schedule
			i.id = String(f.id)
			insts.append(i)
		for e: Dictionary in trace.get("events", []):
			if float(e.end) <= t0 or float(e.start) >= t1:
				continue
			insts.append(_inst(String(e.def), "event", int(e.start), int(e.end), int(e.start), {}, int(e.start) / 1440, [], []))
	elif not defs.is_empty():
		# an old trace: the fixed festival of each day of it (GuildMaster's calendar: day_of_year = day % days per year)
		var dpy := 8
		for day in range(day0 - 1, int(ceil(t1 / 1440.0)) + 1):
			for id in defs:
				var d: Dictionary = defs[id]
				if String(d.get("kind", "")) == "fixed" and int(d.get("day_of_year", -1)) == posmod(day, dpy) and day >= 1:
					var s := day * 1440 + int(d.get("start_hour", 0)) * 60
					var e := s + int(d.get("hours", 24)) * 60
					if e > t0 and s < t1:
						insts.append(_inst(id, "festival", s, e, (day - 1) * 1440 + 720, d, day, [], []))
	# the ones without a town layout are only logged; events go after the festivals (they yield the room)
	var keep := []
	for i in insts:
		if layouts.has(i.def):
			keep.append(i)
		else:
			_log("%s (%s, %d..%d): no town layout in data/fiestas.json pueblo" % [i.def, i.kind, i.start, i.end])
	keep.sort_custom(func(a, b): return _prio(a) > _prio(b))
	insts = keep
	for i in insts:
		_log("%s %s from %s to %s (eve %s), schedule %s" % [i.kind, i.def, _hhmm(i.start), _hhmm(i.end), _hhmm(i.eve),
			(i.schedule as Array).map(func(s): return "%s %s" % [s.what, _hhmm(s.at)])])


func _prio(i: Dictionary) -> int:
	var lay: Dictionary = layouts.get(i.def, {})
	return int(lay.get("priority", 50)) + (0 if i.kind == "event" else 100)


func _inst(id: String, kind: String, s: int, e: int, eve: int, d: Dictionary, day: int, hosts: Array, couple: Array) -> Dictionary:
	var sched := []
	for x: Dictionary in d.get("schedule", []):
		sched.append({"what": String(x.get("what", "")), "at": day * 1440 + int(x.get("hour", 0)) * 60})
	return {"id": id, "def": id, "kind": kind, "start": s, "end": e, "eve": mini(eve, s), "schedule": sched,
		"hosts": hosts, "couple": couple, "placed": [], "mounted": false, "eve_up": false, "day": day}


static func _hhmm(m: float) -> String:
	var md := posmod(int(m), 1440)
	return "d%d %02d:%02d" % [int(floor(m / 1440.0)), md / 60, md % 60]


func sched_at(inst: Dictionary, what: String) -> float:
	for s in inst.schedule:
		if String(s.what) == what:
			return float(s.at)
	return INF


# ---------------------------------------------------------------- the plan of the town
func _g(c: float, r: float) -> Vector2:
	return Vector2(c * 2.0 + 1.0, r * 2.0 + 1.0)  # tile centre -> godot x/z


func _map_sites() -> void:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-1, -1)
	for r in town.H:
		for c in town.W:
			if town._t(c, r) in ["P", "S", "N"]:
				lo = Vector2i(mini(lo.x, c), mini(lo.y, r))
				hi = Vector2i(maxi(hi.x, c), maxi(hi.y, r))
	if hi.x >= 0:
		plaza = Rect2(lo.x * 2.0, lo.y * 2.0, (hi.x - lo.x + 1) * 2.0, (hi.y - lo.y + 1) * 2.0)
		plaza_mid = plaza.get_center()
	# the main street: the rows with most street tiles (GuildMaster FestivalLayer: the longest street row)
	var best := 0
	var by_row := {}
	for r in town.H:
		var n := 0
		for c in town.W:
			if town._t(c, r) == "=":
				n += 1
		by_row[r] = n
		best = maxi(best, n)
	for r in by_row:
		if int(by_row[r]) >= best - 2 and best > 8:
			main_rows.append(r)
	_log("plaza %s (centre %s), main street rows %s, church %s" % [plaza, plaza_mid, main_rows,
		town.church.name if town.church else "none"])


func _visits() -> void:
	if not ("trace" in town) or not (town.trace is Dictionary) or not town.trace.has("characters"):
		return
	var end := float(town.trace.meta.end_minute)
	for id in town.trace.characters:
		var pos: Array = town.trace.characters[id].pos
		var n := pos.size() / 3
		for k in n:
			var tl := Vector2i(int(pos[k * 3 + 1]), int(pos[k * 3 + 2]))
			var m_in := float(pos[k * 3])
			var m_out := float(pos[(k + 1) * 3]) if k + 1 < n else end
			if not visits.has(tl):
				visits[tl] = []
			visits[tl].append([m_in, m_out])


func walked(tl: Vector2i, a: float, b: float) -> float:
	## how much the trace uses tile `tl` between minutes a and b: one per pass, plus a fifth per minute standing there
	var cost := 0.0
	for v in visits.get(tl, []):
		if float(v[1]) > a and float(v[0]) < b:
			cost += 1.0 + maxf(0.0, minf(float(v[1]), b) - maxf(float(v[0]), a) - 2.0) * 0.2
	return cost


func _cell(g: Vector2) -> Vector2i:
	return Vector2i(floori(g.x / LAT), floori(g.y / LAT))


func _mark_circle(g: Vector2, r: float, bit: int) -> void:
	var a := _cell(g - Vector2(r, r))
	var b := _cell(g + Vector2(r, r))
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			if (Vector2(x + 0.5, y + 0.5) * LAT).distance_to(g) <= r:
				block[Vector2i(x, y)] = int(block.get(Vector2i(x, y), 0)) | bit


func _mark_capsule(a: Vector2, b: Vector2, r: float, bit: int) -> void:
	var c0 := _cell(Vector2(minf(a.x, b.x) - r, minf(a.y, b.y) - r))
	var c1 := _cell(Vector2(maxf(a.x, b.x) + r, maxf(a.y, b.y) + r))
	var ab := b - a
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			var p := Vector2(x + 0.5, y + 0.5) * LAT
			var k := 0.0 if ab.length_squared() < 1e-6 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			if p.distance_to(a + ab * k) <= r:
				block[Vector2i(x, y)] = int(block.get(Vector2i(x, y), 0)) | bit


func _mark_obb(g: Vector2, rot: float, half: Vector2, bit: int) -> void:
	var rr := half.length()
	var c0 := _cell(g - Vector2(rr, rr))
	var c1 := _cell(g + Vector2(rr, rr))
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			var l := _local(Vector2(x + 0.5, y + 0.5) * LAT, g, rot)
			if absf(l.x) <= half.x and absf(l.y) <= half.y:
				block[Vector2i(x, y)] = int(block.get(Vector2i(x, y), 0)) | bit


static func _local(p: Vector2, g: Vector2, rot: float) -> Vector2:
	## godot x/z point -> the piece's plan frame (x right, y back) for a piece at g turned `rot` degrees
	var q := (p - g).rotated(deg_to_rad(rot))   # godot rotation.y turns +z (plan -y) towards +x
	return Vector2(q.x, -q.y)


static func _world(l: Vector2, g: Vector2, rot: float) -> Vector2:
	## the piece's plan point -> godot x/z
	return g + Vector2(l.x, -l.y).rotated(-deg_to_rad(rot))


func _lattice() -> void:
	## what a festival piece must keep off, rasterised once at LAT
	var us := Time.get_ticks_usec()
	for h in town.houses:
		var wd: Vector2 = h.get_meta("wd")
		var xf: Transform3D = h.transform
		var half := Vector2(wd.x / 2.0 + 0.25, wd.y / 2.0 + 0.25)
		var gc := Vector2(xf.origin.x, xf.origin.z)
		var rr := half.length()
		var c0 := _cell(gc - Vector2(rr, rr))
		var c1 := _cell(gc + Vector2(rr, rr))
		var inv := xf.affine_inverse()
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				var p := Vector2(x + 0.5, y + 0.5) * LAT
				var l := inv * Vector3(p.x, 0.5, p.y)
				if absf(l.x) <= half.x and absf(l.z) <= half.y:
					block[Vector2i(x, y)] = int(block.get(Vector2i(x, y), 0)) | 1
		# before its door: 1.6 m out, 1.4 m wide each side
		var dd: Array = town._door(h)
		var dp: Vector2 = dd[0]
		var out: Vector2 = dd[1]
		_mark_capsule(Vector2(dp.x, -dp.y), Vector2(dp.x + out.x * 2.2, -(dp.y + out.y * 2.2)), 1.2, 2)
	for r in town.H:
		for c in town.W:
			var ch: String = town._t(c, r)
			var solid := ch == "w" or ch == "b" or ((ch == "S" or ch == "N" or ch == "#") and plaza.grow(0.1).has_point(_g(c, r)))
			if solid:
				var a := _cell(Vector2(c * 2.0, r * 2.0))
				for x in range(a.x - 2, a.x + 10):
					for y in range(a.y - 2, a.y + 10):
						block[Vector2i(x, y)] = int(block.get(Vector2i(x, y), 0)) | 1
			elif ch == "T":
				_mark_circle(_g(c, r), 1.1, 1)
	if "trace" in town and town.trace is Dictionary:
		for b in town.trace.get("buildings", {}):
			var bd: Dictionary = town.trace.buildings[b]
			if (bd.get("door", []) as Array).size() == 2:
				_mark_circle(_g(float(bd.door[0]), float(bd.door[1])), 1.1, 2)
	for ob in town.seat_obstacles:  # plan coordinates
		_mark_capsule(Vector2(ob[0].x, -ob[0].y), Vector2(ob[1].x, -ob[1].y), float(ob[2]) + 0.15, 1)
	for p: Vector2 in town._prop_spots:
		_mark_circle(Vector2(p.x, -p.y), 0.75, 1)
	for p: Vector2 in town._post_spots:
		_mark_circle(Vector2(p.x, -p.y), 0.35, 1)
	for k in town._lat_used:
		var cg := (Vector2(k) + Vector2(0.5, 0.5)) * float(town.LAT)
		block[_cell(cg)] = int(block.get(_cell(cg), 0)) | 1
	if town.vivo != null:
		for it in town.vivo.items:
			if it.get("flat", false):
				continue
			var rc: Rect2 = it.rect
			_mark_circle(it.at, maxf(maxf(absf(rc.position.x), absf(rc.end.x)), maxf(absf(rc.position.y), absf(rc.end.y))) * 0.8, 1)
	for n in get_tree().get_nodes_in_group("tree"):
		if n is MultiMeshInstance3D:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			if mm == null or n.has_meta("far_twin_of"):
				continue
			var gx: Transform3D = (n as Node3D).global_transform
			for i in mm.instance_count:
				var o := gx * mm.get_instance_transform(i).origin
				_mark_circle(Vector2(o.x, o.z), 0.9, 1)
		elif n is Node3D and (n as Node3D).get_parent() == town:
			var o := (n as Node3D).global_position
			_mark_circle(Vector2(o.x, o.z), 0.9, 1)
	_log("lattice: %d cells kept off in %.0f ms" % [block.size(), float(Time.get_ticks_usec() - us) / 1000.0])


func _dump_map(spec: String) -> void:
	## debug: what is kept off in tiles c0,r0..c1,r1, two characters per tile (0.5 m cells sampled at their centre):
	## # solid, d before a door, . free; the map character at the left
	var v := spec.split(",")
	for r in range(int(v[1]), int(v[3]) + 1):
		for sub in 2:
			var line := "%2d%s " % [r, town._t(0, r) if sub == 0 else " "]
			for c in range(int(v[0]), int(v[2]) + 1):
				for sx in 4:
					var g := Vector2(c * 2.0 + sx * 0.5 + 0.25, r * 2.0 + sub * 1.0 + 0.5)
					var bt := int(block.get(_cell(g), 0))
					line += "#" if bt & 1 else ("d" if bt & 2 else ".")
			print("[FiestasPueblo] mapa " + line)


# ---------------------------------------------------------------- sites
## [godot x/z point, rot (deg) the piece faces, extra] candidates of a site, best first
func site(s: String, inst: Dictionary) -> Array:
	var key := s + "|" + ",".join(inst.hosts)
	if _sites.has(key):
		return _sites[key]
	var out := []
	var base := s.get_slice(":", 0)
	match base:
		"plaza_centro":
			for p in _grid(plaza.grow(-1.0), 0.5):
				out.append([p, _face_to(p, plaza_mid, true), p.distance_to(plaza_mid)])
			out.sort_custom(func(a, b): return a[2] < b[2])
		"plaza_anillo", "plaza_n", "plaza_s", "plaza_e", "plaza_o":
			var band := plaza.grow(-1.0)
			for p in _grid(band, 0.5):
				var d := minf(minf(p.x - band.position.x, band.end.x - p.x), minf(p.y - band.position.y, band.end.y - p.y))
				if d > 3.0:
					continue
				var side := _side_of(p)
				if base != "plaza_anillo" and side != base.substr(6):
					continue
				out.append([p, _face_to(p, plaza_mid, false), atan2(p.y - plaza_mid.y, p.x - plaza_mid.x)])
			out.sort_custom(func(a, b): return a[2] < b[2])
		"calle":
			# beside the main street, off it, out of the plaza: from the plaza outwards
			for r in main_rows:
				for c in town.W:
					for dr in [-1, 1]:
						var rr: int = r + dr
						if rr in main_rows or town._t(c, rr) in ["#", "w", "b", "T"] or town._t(c, r) != "=":
							continue
						var p := _g(c, rr) + Vector2(0, -dr * 0.4)
						if plaza.grow(1.5).has_point(p):
							continue
						out.append([p, 0.0 if dr > 0 else 180.0, absf(p.x - plaza_mid.x)])
			out.sort_custom(func(a, b): return a[2] < b[2])
		"calle_alto":
			var zc := 0.0
			for r in main_rows:
				zc += float(r) * 2.0 + 1.0
			zc /= maxf(1.0, main_rows.size())
			var x := plaza_mid.x
			for k in range(1, 12):
				for sgn in [-1.0, 1.0]:
					var px: float = plaza_mid.x + sgn * (plaza.size.x / 2.0 + 3.5 + (k - 1) * 6.5)
					if px > 2.0 and px < town.W * 2.0 - 2.0 and town._t(floori(px / 2.0), floori(zc / 2.0)) != "b":
						out.append([Vector2(px, zc), 90.0, k * 10.0 + (0.0 if sgn < 0 else 0.5)])
			# the two streets across, north and south of the main one
			for c in town.W:
				var n := 0
				for r in town.H:
					if town._t(c, r) == "=":
						n += 1
				if n < 12:
					continue
				for k in range(1, 6):
					for sgn in [-1.0, 1.0]:
						var pz: float = zc + sgn * (3.5 + (k - 1) * 6.5)
						var pc := Vector2(c * 2.0 + 1.0, pz)
						if town._t(c, floori(pz / 2.0)) == "=":
							out.append([pc, 0.0, 40.0 + k * 10.0 + absf(pc.x - plaza_mid.x) * 0.1])
			out.sort_custom(func(a, b): return a[2] < b[2])
		"plaza_alto":
			var band := plaza.grow(-1.2)
			for e in [[band.position, Vector2(band.end.x, band.position.y)], [Vector2(band.end.x, band.position.y), band.end],
					[band.end, Vector2(band.position.x, band.end.y)], [Vector2(band.position.x, band.end.y), band.position]]:
				var a: Vector2 = e[0]
				var b: Vector2 = e[1]
				var nseg := maxi(1, int((a.distance_to(b) - 1.0) / 6.2))
				for i in nseg:
					var p := a.lerp(b, (i + 0.5) / nseg)
					var dir := (b - a).normalized()
					out.append([p, -rad_to_deg(atan2(dir.y, dir.x)), i])
		"balcon", "balcon_rico":
			for h in town.houses:
				if String(h.get_meta("type", "")) in ["church", "mill"]:
					continue
				if base == "balcon_rico" and not String(h.get_meta("wealth", "")) in ["noble", "well"]:
					continue
				var dd: Array = town._door(h)
				var dp := Vector2(dd[0].x, -dd[0].y)
				var outd := Vector2(dd[1].x, -dd[1].y)
				var side := Vector2(dd[2].x, -dd[2].y)
				var dist := _dist_plaza(dp)
				if dist > 14.0:
					continue
				for sg in [-1.0, 1.0]:
					out.append([dp + side * sg * 1.6 + outd * 0.06, _rot_of(outd), dist + sg * 0.01, h])
			out.sort_custom(func(a, b): return a[2] < b[2])
		"puerta_anfitrion", "puerta_rica", "puertas", "puerta_iglesia", "puerta_ayto", "puertas_plaza":
			var hs := []
			match base:
				"puerta_anfitrion":
					hs = _host_houses(inst)
				"puerta_iglesia":
					if town.church:
						hs = [town.church]
				"puerta_ayto":
					for h in town.houses:
						if String(h.get_meta("type", "")) == "town_hall":
							hs.append(h)
				_:
					for h in town.houses:
						if String(h.get_meta("type", "")) in ["church", "mill"]:
							continue
						if base == "puerta_rica" and not String(h.get_meta("wealth", "")) in ["noble", "well"]:
							continue
						hs.append(h)
			for h in hs:
				var dd: Array = town._door(h)
				var dp := Vector2(dd[0].x, -dd[0].y)
				var outd := Vector2(dd[1].x, -dd[1].y)
				if base == "puertas_plaza" and _dist_plaza(dp) > 10.0:
					continue
				out.append([dp, _rot_of(outd), _dist_plaza(dp), h])
			if base != "puerta_anfitrion" and base != "puerta_iglesia" and base != "puerta_ayto":
				out.sort_custom(func(a, b): return a[2] < b[2])
		"prado_norte":
			var top := 0
			for r in town.H:
				if town._t(int(plaza_mid.x / 2.0), r) in [",", "="]:
					top = r
					break
			var area := Rect2(2.0, 0.6, town.W * 2.0 - 10.0, maxf(2.0, top * 2.0 - 1.4))
			var mid := Vector2(plaza_mid.x, area.get_center().y)
			for p in _grid(area, 0.5):
				out.append([p, 0.0, p.distance_to(mid)])
			out.sort_custom(func(a, b): return a[2] < b[2])
		"prado":
			# prado:<c0>,<r0>,<c1>,<r1>: a meadow by tiles, from its middle out
			var v := s.get_slice(":", 1).split(",")
			var area := Rect2(float(v[0]) * 2.0 + 0.6, float(v[1]) * 2.0 + 0.6, (float(v[2]) - float(v[0]) + 1) * 2.0 - 1.2, (float(v[3]) - float(v[1]) + 1) * 2.0 - 1.2)
			for p in _grid(area, 0.5):
				out.append([p, 0.0, p.distance_to(area.get_center())])
			out.sort_custom(func(a, b): return a[2] < b[2])
		"afueras":
			var gates := []
			for g in town.mapd.get("spawns", {}):
				if String(g).ends_with("_gate"):
					var sp: Array = town.mapd.spawns[g]
					gates.append(Vector2i(int(sp[0]), int(sp[1])))
			for r in town.H:
				for c in town.W:
					if town._t(c, r) != ".":
						continue
					var bestd := 1 << 20
					for gt: Vector2i in gates:
						bestd = mini(bestd, maxi(absi(c - gt.x), absi(r - gt.y)))
					if bestd <= 1 or bestd > 10:
						continue
					out.append([_g(c, r), 0.0, float(bestd) + float(r) * 0.001])
			out.sort_custom(func(a, b): return a[2] < b[2])
		"iglesia_frente":
			if town.church:
				var dd: Array = town._door(town.church)
				var dp := Vector2(dd[0].x, -dd[0].y)
				var outd := Vector2(dd[1].x, -dd[1].y)
				for p in _grid(Rect2(dp - Vector2(10, 10), Vector2(20, 20)), 0.5):
					if (p - dp).dot(outd) < 1.5:
						continue
					out.append([p, _rot_of(outd), p.distance_to(dp + outd * 4.0)])
				out.sort_custom(func(a, b): return a[2] < b[2])
	_sites[key] = out
	return out


func _grid(r: Rect2, step: float) -> Array:
	var out := []
	var x := r.position.x + step / 2.0
	while x < r.end.x:
		var y := r.position.y + step / 2.0
		while y < r.end.y:
			out.append(Vector2(x, y))
			y += step
		x += step
	return out


func _side_of(p: Vector2) -> String:
	var d := {"n": p.y - plaza.position.y, "s": plaza.end.y - p.y, "o": p.x - plaza.position.x, "e": plaza.end.x - p.x}
	var best := "n"
	for k in d:
		if d[k] < d[best]:
			best = k
	return best


func _dist_plaza(p: Vector2) -> float:
	var q := Vector2(clampf(p.x, plaza.position.x, plaza.end.x), clampf(p.y, plaza.position.y, plaza.end.y))
	return q.distance_to(p)


static func _rot_of(dir: Vector2) -> float:
	## rotation (deg) that turns a piece's front (plan -y, godot +z) towards godot direction dir
	return rad_to_deg(atan2(dir.x, dir.y))


func _face_to(p: Vector2, to: Vector2, away: bool) -> float:
	var d := (p - to) if away else (to - p)
	if d.length() < 0.01:
		return 0.0
	return snappedf(_rot_of(d), 90.0)


func _host_houses(inst: Dictionary) -> Array:
	## the homes of the hosts (their families) and of the couple; else the richest house near the plaza
	var out := []
	if "trace" in town and town.trace is Dictionary:
		var want := {}
		for c in inst.couple:
			var ch: Dictionary = town.trace.characters.get(c, {})
			if String(ch.get("home", "")) != "":
				want[String(ch.home)] = true
		for id in town.trace.characters:
			var ch: Dictionary = town.trace.characters[id]
			if String(ch.get("family", "")) in inst.hosts and String(ch.get("family_role", "")) == "head" and String(ch.get("home", "")) != "":
				want[String(ch.home)] = true
		for b in want:
			var bd: Dictionary = town.trace.buildings.get(b, {})
			if (bd.get("door", []) as Array).size() != 2:
				continue
			var dg := _g(float(bd.door[0]), float(bd.door[1]))
			var best: Node3D = null
			var bdist := 1e9
			for h in town.houses:
				var dd: Array = town._door(h)
				var dist := Vector2(dd[0].x, -dd[0].y).distance_to(dg)
				if dist < bdist:
					bdist = dist
					best = h
			if best and bdist < 4.0 and not best in out:
				out.append(best)
	if out.is_empty():
		var bd := 1e9
		var best: Node3D = null
		for h in town.houses:
			if not String(h.get_meta("wealth", "")) in ["noble", "well"]:
				continue
			var dd: Array = town._door(h)
			var d := _dist_plaza(Vector2(dd[0].x, -dd[0].y))
			if d < bd:
				bd = d
				best = h
		if best:
			out.append(best)
	return out


# ---------------------------------------------------------------- the solver
## Footprint half extents (plan x, y) of a catalogue piece, of a kit prop (q:) or of a group
func _half(id: String) -> Vector2:
	if id.begins_with("q:") or id.begins_with("n:"):
		return Vector2(0.4, 0.4)
	var inf := LandmarkBuilder.info(id)
	var fp: Array = inf.get("footprint", inf.get("size", [1, 1]))
	return Vector2(float(fp[0]) / 2.0, float(fp[1]) / 2.0)


func _fits(g: Vector2, rot: float, half: Vector2, flags: Dictionary) -> bool:
	## every 0.4 m of the footprint (and its edge) off what is kept clear
	var ignore_door: bool = flags.get("door_ok", false)
	var mask := 1 | (0 if ignore_door or flags.get("flat", false) else 2)
	var a: float = flags.get("_a", -INF)
	var b: float = flags.get("_b", INF)
	var near := []
	for bx in ([] if flags.get("flat", false) else _boxes):
		if float(bx.a) < b and float(bx.b) > a and (bx.g as Vector2).distance_to(g) < (bx.half as Vector2).length() + half.length() + 0.3:
			near.append(bx)
	var nx := maxi(1, ceili(half.x * 2.0 / 0.4))
	var ny := maxi(1, ceili(half.y * 2.0 / 0.4))
	for i in nx + 1:
		for j in ny + 1:
			var l := Vector2(-half.x + half.x * 2.0 * i / nx, -half.y + half.y * 2.0 * j / ny)
			var p := _world(l, g, rot)
			if p.x < 0.5 or p.y < 0.5 or p.x > town.W * 2.0 - 0.5 or p.y > town.H * 2.0 - 0.5:
				return false
			if int(block.get(_cell(p), 0)) & mask:
				return false
			for bx in near:
				var l2 := _local(p, bx.g, bx.rot)
				if absf(l2.x) <= float(bx.half.x) + 0.15 and absf(l2.y) <= float(bx.half.y) + 0.15:
					return false
	return true


func _walk_cost(g: Vector2, rot: float, half: Vector2, a: float, b: float) -> float:
	## the trace's use of the tile centres under the footprint (grown by a body) while it stands
	var cost := 0.0
	var rr := half.length() + BODY
	for c in range(floori((g.x - rr) / 2.0), floori((g.x + rr) / 2.0) + 1):
		for r in range(floori((g.y - rr) / 2.0), floori((g.y + rr) / 2.0) + 1):
			var l := _local(_g(c, r), g, rot)
			if absf(l.x) <= half.x + BODY and absf(l.y) <= half.y + BODY:
				cost += walked(Vector2i(c, r), a, b)
	return cost


func _plan(inst: Dictionary) -> void:
	var lay: Dictionary = layouts[inst.def]
	for e: Dictionary in lay.get("pieces", []):
		if e.has("needs") and not _part_on(inst, String(e.needs)):
			_log("%s: %s left out (%s is not paid for)" % [inst.def, e.get("p", "?"), e.needs])
			continue
		var n := int(e.get("n", 1))
		var picks: Array = []
		for k in n:
			var pl := _place(inst, e, picks)
			if pl.is_empty():
				stats.no_room += 1
				_log("%s: no room for %s at %s (%d of %d)" % [inst.def, e.get("p", e.get("group", "?")), e.get("site", ""), k + 1, n])
				break
			picks.append(pl.g)
			inst.placed.append(pl)
	if lay.has("route"):
		inst.route = _route(String(lay.route))


func _part_on(inst: Dictionary, part: String) -> bool:
	## a part of the programme somebody must pay for (the bulls): on if the trace says so; forced festivals have it
	for x in inst.schedule:
		if String(x.what) == part:
			return bool(x.get("on", true))
	return true


func _place(inst: Dictionary, e: Dictionary, picks: Array) -> Dictionary:
	var is_group := e.has("group")
	var id := String(e.get("p", ""))
	if not is_group and not id.begins_with("q:") and LandmarkBuilder.info(id).is_empty():
		stats.missing += 1
		_log("%s: unknown piece %s" % [inst.def, id])
		return {}
	var parts: Array = e.get("parts", []) if is_group else []
	var half := _group_half(parts, e.get("chains", [])) if is_group else _half(id)
	if e.has("half"):
		half = Vector2(e.half[0], e.half[1])
	var overhead: bool = e.has("z") and float(e.z) > 2.0 or String(e.get("site", "")).ends_with("_alto") or String(e.get("site", "")).begins_with("balcon")
	var a := float(inst.eve if e.get("eve", false) else inst.start)
	var b := float(inst.end)
	var cands: Array = site(String(e.get("site", "plaza_centro")), inst)
	e = e.duplicate()
	e["_a"] = a
	e["_b"] = b
	var best := {}
	var best_score := INF
	var tried := 0
	var spread := float(e.get("spread", 4.0))
	for cd in cands:
		var g: Vector2 = cd[0]
		var base_rot: float = float(e.rot) if e.has("rot") else float(cd[1])
		if e.has("rot_rel"):
			base_rot = float(cd[1]) + float(e.rot_rel)
		var outs := [0.0]
		if e.has("off") and cd.size() > 3:
			var h: Node3D = cd[3]
			var dd: Array = town._door(h)
			var outd := Vector2(dd[1].x, -dd[1].y)
			var side := Vector2(dd[2].x, -dd[2].y)
			g = g + outd * float(e.off[1]) + side * float(e.off[0])
			for k in int(e.get("off_try", 0)):
				outs.append(0.8 * (k + 1))
		var close := false
		for q: Vector2 in picks:
			if q.distance_to(g) < spread:
				close = true
		if close:
			continue
		var rots: Array = [base_rot] if (e.has("rot") or e.has("rot_rel") or overhead or e.get("fixed_rot", false)) else [base_rot, base_rot + 90.0, base_rot + 180.0, base_rot + 270.0]
		var g0 := g
		var found := false
		for o in outs:
			if found:
				break
			if float(o) > 0.0:
				var dd2: Array = town._door(cd[3])
				g = g0 + Vector2(dd2[1].x, -dd2[1].y) * float(o)
			for rot in rots:
				if not overhead and not _fits(g, rot, half, e):
					continue
				found = true
				tried += 1
				var cost := 0.0 if overhead or e.get("flat", false) else _walk_cost(g, rot, half, a, b)
				var score := cost * 4.0 + float(cd[2]) * float(e.get("near", 1.0))
				if score < best_score:
					best_score = score
					best = {"e": e, "id": id, "g": g, "rot": fposmod(rot, 360.0), "half": half, "cost": cost, "overhead": overhead,
						"group": is_group, "house": cd[3] if cd.size() > 3 else null}
				break
		if tried >= int(e.get("tries", 40)) and not best.is_empty():
			break
	if best.is_empty():
		if String(e.get("site", "")).begins_with("puerta"):
			_log("%s: %s tried %s" % [inst.def, id, cands.map(func(c): return [(c[0] as Vector2).snapped(Vector2(0.1, 0.1)), int(c[1]), String((c[3] as Node).name) if c.size() > 3 else ""])])
		return {}
	if not overhead:
		_boxes.append({"g": best.g, "rot": best.rot, "half": best.half, "a": a, "b": b})
	stats.pieces += 1
	stats.walked_centres += int(best.cost > 0.0)
	if is_group:
		stats.groups += 1
	_log("%s: %s at %s rot %d (site %s, trace use under it %.1f)" % [inst.def, id if not is_group else "group " + String(e.group),
		best.g.snapped(Vector2(0.1, 0.1)), int(best.rot), e.get("site", ""), best.cost])
	return best


func _group_half(parts: Array, chains: Array) -> Vector2:
	var m := Vector2.ZERO
	for p in parts:
		var h := _half(String(p[0]))
		var r := deg_to_rad(float(p[3]) if p.size() > 3 else 0.0)
		var ex := absf(h.x * cos(r)) + absf(h.y * sin(r))
		var ey := absf(h.x * sin(r)) + absf(h.y * cos(r))
		m.x = maxf(m.x, absf(float(p[1])) + ex)
		m.y = maxf(m.y, absf(float(p[2])) + ey)
	for c in chains:
		var hh := _half(String(c.piece))
		for pt in [c.from, c.to]:
			m.x = maxf(m.x, absf(float(pt[0])) + hh.y)
			m.y = maxf(m.y, absf(float(pt[1])) + hh.y)
	return m


# ---------------------------------------------------------------- up and down
func _mount(inst: Dictionary, eve_only := false) -> void:
	if inst.mounted:
		return
	var us := Time.get_ticks_usec()
	var made := 0
	for pl in inst.placed:
		if pl.has("nodes"):
			continue
		if eve_only and not pl.e.get("eve", false):
			continue
		pl.nodes = []
		if pl.group:
			for p in pl.e.get("parts", []):
				var opts: Dictionary = p[4] if p.size() > 4 else {}
				var n := _build(String(p[0]), _world(Vector2(float(p[1]), float(p[2])), pl.g, pl.rot), pl.rot + (float(p[3]) if p.size() > 3 else 0.0), opts, inst)
				if n:
					pl.nodes.append(n)
			for c in pl.e.get("chains", []):
				var a := Vector2(c.from[0], c.from[1])
				var b := Vector2(c.to[0], c.to[1])
				var step: float = float(LandmarkBuilder.info(String(c.piece)).get("module", 2.0))
				var k := int(round(a.distance_to(b) / step))
				var dir := (b - a).normalized()
				var lrot := -rad_to_deg(atan2(dir.y, dir.x))
				for i in k:
					if (c.get("skip", []) as Array).has(float(i)):
						continue
					var lp := a + dir * step * (i + 0.5)
					var n := _build(String(c.piece), _world(lp, pl.g, pl.rot), pl.rot + lrot, {}, inst)
					if n:
						pl.nodes.append(n)
		else:
			var n := _build(pl.id, pl.g, pl.rot, pl.e.get("opts", {}), inst)
			if n:
				if pl.e.has("z"):
					n.position.y = float(pl.e.z)
				pl.nodes.append(n)
		made += pl.nodes.size()
		if not pl.overhead and pl.e.get("blocks", true) and not pl.e.get("flat", false):
			pl.obstacle = _obstacle(pl)
			town.seat_obstacles.append(pl.obstacle)
	if "_ob_count" in town:
		town._ob_count = -1  # sim3d.gd rebuilds its grid of obstacles
	_uses_dirty = true
	if not eve_only:
		inst.mounted = true
	else:
		inst.eve_up = true
	_night = -1
	_far = -1
	_log("%s up%s: %d pieces in %.0f ms" % [inst.def, " (eve)" if eve_only else "", made, float(Time.get_ticks_usec() - us) / 1000.0])


func _unmount(inst: Dictionary) -> void:
	for pl in inst.placed:
		for n in pl.get("nodes", []):
			if is_instance_valid(n):
				_forget(n)
				n.queue_free()
		pl.erase("nodes")
		if pl.has("obstacle"):
			town.seat_obstacles.erase(pl.obstacle)
			pl.erase("obstacle")
	_lights = _lights.filter(func(l): return l[3] != inst)
	_flames = _flames.filter(func(f): return f[1] != inst)
	_sparks = _sparks.filter(func(s): return s[1] != inst)
	_smokes = _smokes.filter(func(s): return s[1] != inst)
	for w in _walkers:
		if w.inst == inst and is_instance_valid(w.node):
			w.node.queue_free()
	_walkers = _walkers.filter(func(w): return w.inst != inst)
	for id in _drive.keys():
		if _drive[id].use.inst == inst:
			_release(id)
	if "_ob_count" in town:
		town._ob_count = -1
	inst.mounted = false
	inst.eve_up = false
	_uses_dirty = true
	_log("%s down" % inst.def)


func _forget(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		town._orig.erase(mi)


func _obstacle(pl: Dictionary) -> Array:
	var h: Vector2 = pl.half
	var sh := minf(h.x, h.y)
	var r := sh * 1.414 + 0.05  # the corners of the footprint inside it
	var along := Vector2(maxf(0.0, h.x - sh), 0.0) if h.x >= h.y else Vector2(0.0, maxf(0.0, h.y - sh))
	var a := _world(-along, pl.g, pl.rot)
	var b := _world(along, pl.g, pl.rot)
	return [Vector2(a.x, -a.y), Vector2(b.x, -b.y), r]  # plan coordinates, as pueblo.gd seat_obstacles


func _build(id: String, g: Vector2, rot: float, opts: Dictionary, inst: Dictionary) -> Node3D:
	var n: Node3D
	if id.begins_with("q:"):
		var qp: String = town.QPROPS % id.substr(2)
		n = load(qp).instantiate() if ResourceLoader.exists(qp) else null
	else:
		var bopts := {}
		if opts.has("goods"):
			bopts["goods"] = opts.goods
		if opts.has("awning"):
			bopts["awning"] = Color(opts.awning[0], opts.awning[1], opts.awning[2])
		if opts.has("tint"):
			var t := {}
			for m in opts.tint:
				t[m] = Color(opts.tint[m][0], opts.tint[m][1], opts.tint[m][2])
			bopts["tint"] = t
		n = LandmarkBuilder.build(id, bopts)
	if n == null:
		_log("could not build %s" % id)
		return null
	n.position = Vector3(g.x, float(opts.get("z", 0.0)), g.y)
	n.rotation.y = deg_to_rad(rot)
	if opts.has("scale"):
		n.scale = Vector3.ONE * float(opts.scale)
	add_child(n)
	_dress(n, inst, id)
	# the far view (zoom > FAR_ZOOM): the small pieces go (torches, wall shields, petals, chalk crosses, kit props)
	if id.begins_with("q:") or int(LandmarkBuilder.info(id).get("tris", 1000)) < 400 or float(opts.get("z", 0.0)) > 2.5:
		n.set_meta("fp_small", true)
	return n


func _dress(root: Node3D, inst: Dictionary, id: String) -> void:
	## the town's look (canonical material + toon with outline), the flames, the sparks, the lanterns and the lights
	var cat := LandmarkBuilder.catalog()
	var lit_from := INF
	var lay: Dictionary = layouts.get(inst.def, {})
	if lay.get("lit", {}).has(id):
		lit_from = sched_at(inst, String(lay.lit[id]))
	var stack: Array[Node] = [root]
	var no_outline := false
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		var inf: Dictionary = cat.pieces.get(String(n.name), {}) if cat.has("pieces") else {}
		if inf.get("outline", true) == false:
			no_outline = true
		if n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh:
			_split_flames(n, inst, lit_from)
			_glow_panes(n)
		if inf.is_empty() or not (n is Node3D):
			continue
		var fire: Dictionary = inf.get("fire", {})
		if not fire.is_empty() and fire.get("lit", true) and int(fire.get("sparks", 18)) > 0 and not n.has_node("Chispas"):
			var sp := _spark(fire)
			n.add_child(sp)
			_sparks.append([sp, inst, lit_from])
			if float(fire.get("r", 0.0)) >= 0.45:
				var sm := _smoke(fire)
				if sm:
					n.add_child(sm)
					_smokes.append([sm, inst, lit_from])
	for li in LandmarkBuilder.lights(root):
		var inf: Dictionary = cat.pieces.get(String(li.get_parent().name), {})
		var lc: Dictionary = inf.get("light", {})
		li.light_energy = 0.0
		li.visible = false
		_lights.append([li, float(lc.get("energy", 1.0)), randf() * 10.0, inst, lc.get("flicker", false), lit_from])
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.name == "Llamas" or m3.mesh == null:
			continue
		if no_outline:
			continue
		var mats := []
		for i in m3.mesh.get_surface_count():
			var m := m3.get_active_material(i)
			if m and m.resource_name == "MI_Luz":
				mats.append(m)
				continue
			var cm: Material = preload("res://game/world3d/town/opt3d.gd").canon(m)
			mats.append(cm)
			m3.set_surface_override_material(i, town._variant(cm, "outline"))
		town._orig[m3] = mats


func _split_flames(mi: MeshInstance3D, inst: Dictionary, lit_from: float) -> void:
	## the surfaces of MI_Fuego go to a mesh of their own with the fire shader, no shadow, no outline (as fiestas.gd)
	var am: ArrayMesh = mi.mesh
	if mi.name == "Llamas":
		return
	var idx := []
	for i in am.get_surface_count():
		var m := am.surface_get_material(i)
		if m is StandardMaterial3D and m.resource_name == "MI_Fuego":
			idx.append(i)
	if idx.is_empty():
		return
	if _fire_mat == null:
		_fire_mat = ShaderMaterial.new()
		_fire_mat.shader = load(FIRE_SHADER)
		_fire_mat.resource_name = "MI_Fuego"
	var flame := ArrayMesh.new()
	var rest := ArrayMesh.new()
	for i in am.get_surface_count():
		var arrays := am.surface_get_arrays(i)
		var fmt := am.surface_get_format(i)
		if idx.has(i):
			flame.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
			flame.surface_set_material(flame.get_surface_count() - 1, _fire_mat)
		else:
			rest.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
			rest.surface_set_material(rest.get_surface_count() - 1, am.surface_get_material(i))
	mi.mesh = rest
	var fm := MeshInstance3D.new()
	fm.name = "Llamas"
	fm.mesh = flame
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fm.add_to_group("tree")
	mi.add_child(fm)
	_flames.append([fm, inst, lit_from])


func _glow_panes(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m and m.resource_name == "MI_Luz":
			if _glow_mat == null:
				_glow_mat = StandardMaterial3D.new()
				_glow_mat.resource_name = "MI_Luz"
				_glow_mat.albedo_color = Color(1.0, 0.9, 0.7)
				_glow_mat.vertex_color_use_as_albedo = true
				_glow_mat.emission_enabled = true
				_glow_mat.emission = Color(1.0, 0.8, 0.5)
				_glow_mat.emission_energy_multiplier = 0.0
				_glow_mat.roughness = 0.9
			mi.mesh.surface_set_material(i, _glow_mat)


func _smoke(fire: Dictionary) -> GPUParticles3D:
	## the chimney smoke of «luz, clima y vida» (scripts/clima/vida.gd _smoke_particles), wider, from the top of the fire
	var cl := get_tree().get_nodes_in_group("clima")
	if cl.is_empty() or not ("vida" in cl[0]) or cl[0].vida == null or not cl[0].vida.has_method("_smoke_particles"):
		return null
	var p: GPUParticles3D = cl[0].vida._smoke_particles(3, Color(0.55, 0.52, 0.5), 0.7)
	p.name = "HumoHoguera"
	p.amount = 16 if float(fire.get("r", 0.5)) > 0.6 else 9
	var pm: ParticleProcessMaterial = p.process_material
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = float(fire.get("r", 0.5)) * 0.45
	var at: Array = fire.get("at", [0, 0, 0.5])
	p.position = HouseBuilder.plan_to_godot(Vector3(at[0], at[1], float(at[2]) + float(fire.get("r", 0.5)) * 1.6))
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 14, 12))
	return p


func _spark(fire: Dictionary) -> GPUParticles3D:
	if _spark_mesh == null:
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2(0.05, 0.05)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.albedo_color = Color(1.0, 0.55, 0.15)
		sm.emission_enabled = true
		sm.emission = Color(1.0, 0.5, 0.12)
		sm.emission_energy_multiplier = 3.0
		sm.vertex_color_use_as_albedo = true
		_spark_mesh.material = sm
		_spark_pm = ParticleProcessMaterial.new()
		_spark_pm.direction = Vector3(0, 1, 0)
		_spark_pm.spread = 22.0
		_spark_pm.initial_velocity_min = 0.9
		_spark_pm.initial_velocity_max = 1.9
		_spark_pm.gravity = Vector3(0, 0.35, 0)
		_spark_pm.scale_min = 0.5
		_spark_pm.scale_max = 1.0
		_spark_pm.turbulence_enabled = true
		_spark_pm.turbulence_noise_strength = 1.2
		_spark_pm.turbulence_noise_scale = 3.0
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.8, 0.3, 1.0))
		grad.set_color(1, Color(0.8, 0.15, 0.02, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		_spark_pm.color_ramp = gt
	var p := GPUParticles3D.new()
	p.name = "Chispas"
	p.amount = int(fire.get("sparks", 18))
	p.lifetime = 1.6
	p.randomness = 0.6
	var pm: ParticleProcessMaterial = _spark_pm.duplicate()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = float(fire.get("r", 0.4)) * 0.6
	p.process_material = pm
	p.draw_pass_1 = _spark_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var at: Array = fire.get("at", [0, 0, 0.5])
	p.position = HouseBuilder.plan_to_godot(Vector3(at[0], at[1], at[2]))
	p.add_to_group("tree")
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	return p


# ---------------------------------------------------------------- per frame
func _process(dt: float) -> void:
	if insts.is_empty():
		return
	_t += dt
	var t: float = float(town.t_min) if "t_min" in town else 0.0
	for inst in insts:
		var up: bool = t >= float(inst.start) and t < float(inst.end) if "t_min" in town else true
		var eve: bool = "t_min" in town and t >= float(inst.eve) and t < float(inst.start)
		if up and not inst.mounted:
			_mount(inst)
		elif not up and inst.mounted:
			_unmount(inst)
		if eve and not inst.eve_up and not inst.mounted:
			_mount(inst, true)
		elif not eve and not up and inst.eve_up:
			_unmount(inst)
	var dark := 0
	if town.has_method("daylight"):
		dark = int(town.daylight(t) < 0.35)
	var far := int(town.cam.size > FAR_ZOOM) if town.cam else 0
	if dark != _night or far != _far or absf(t - _last_t) > 5.0:
		_night = dark
		_far = far
		_last_t = t
		for f in _flames:
			if is_instance_valid(f[0]):
				(f[0] as Node3D).visible = t >= float(f[2]) or f[2] == INF
		for s in _smokes:
			if is_instance_valid(s[0]):
				var lit: bool = t >= float(s[2]) or s[2] == INF
				(s[0] as GPUParticles3D).emitting = lit
				(s[0] as Node3D).visible = lit
		for s in _sparks:
			if is_instance_valid(s[0]):
				var lit: bool = t >= float(s[2]) or s[2] == INF
				(s[0] as GPUParticles3D).emitting = far == 0 and lit
				(s[0] as Node3D).visible = far == 0 and lit
		if _glow_mat:
			_glow_mat.emission_energy_multiplier = 2.2 if dark else 0.0
		if _fire_mat:
			_fire_mat.set_shader_parameter("strength", 1.6 if dark else 1.3)
		for n in get_children():
			if n is Node3D and n.has_meta("fp_small"):
				(n as Node3D).visible = far == 0
	for l in _lights:
		var li := l[0] as OmniLight3D
		if not is_instance_valid(li):
			continue
		var on: bool = _night == 1 and (t >= float(l[5]) or l[5] == INF)
		if li.visible != on:
			li.visible = on
		if on and l[4]:
			li.light_energy = float(l[1]) * (0.86 + 0.14 * sin(_t * 11.0 + float(l[2])) * sin(_t * 6.3 + float(l[2]) * 1.7))
		elif on:
			li.light_energy = float(l[1])
	if _gente and "people" in town and "_chr" in town:
		var us := Time.get_ticks_usec()
		_people(t, dt)
		_cost.us += Time.get_ticks_usec() - us
		_cost.frames += 1
		if _cost.frames == 600:
			_log("people and procession: %.0f us per frame (%d driven, %d walkers)" % [float(_cost.us) / 600.0, _drive.size(), _walkers.size()])
			_cost = {"us": 0, "frames": 0}


# ---------------------------------------------------------------- people at the pieces
func _uses() -> Array:
	## every use point of the pieces up: [key, inst, godot x/z, yaw (godot rotation.y), action, seat height] (cached:
	## the pieces that stand do not move; the ones the procession takes have no use point of these actions)
	if not _uses_dirty:
		return _uses_cache
	_uses_dirty = false
	var out := []
	for inst in insts:
		if not inst.mounted:
			continue
		for pi in inst.placed.size():
			var pl: Dictionary = inst.placed[pi]
			for n in pl.get("nodes", []):
				if not is_instance_valid(n):
					continue
				var inf := LandmarkBuilder.info(String(n.get_meta("landmark", n.name)))
				var g := Vector2((n as Node3D).position.x, (n as Node3D).position.z)
				var rot := rad_to_deg((n as Node3D).rotation.y)
				var ui := 0
				for u: Dictionary in inf.get("use", []):
					ui += 1
					var act := String(u.get("action", ""))
					if not act in ACTION_ANIM:
						continue
					var at: Array = u.at
					var p := _world(Vector2(float(at[0]), float(at[1])), g, rot)
					var f := deg_to_rad(float(u.get("facing", 0)))
					var dl := Vector2(-sin(f), cos(f))        # facing in the piece's plan frame
					var dg := _world(dl, Vector2.ZERO, rot)   # ... in godot x/z
					var z := float(u.get("z", inf.get("seat_z", 0.45))) if act == "sentarse" else float(u.get("z", 0.0))
					if inf.get("seat_z") is Array and act == "sentarse" and not u.has("z"):
						z = float(inf.seat_z[0])
					out.append(["%s|%d|%d|%d" % [inst.def, pi, n.get_instance_id(), ui], inst, p, atan2(dg.x, dg.y), act, z, dg])
	_uses_cache = out
	return out


func _people(t: float, dt: float) -> void:
	var uses := _uses()
	_reach = 14.0
	for inst in insts:
		if inst.mounted:
			_reach = maxf(_reach, float(layouts[inst.def].get("reach", 14.0)))
	_walk_procession(t)
	if uses.is_empty() and _drive.is_empty():
		return
	if not is_same(_by_key_src, uses):
		_by_key = {}
		for u in uses:
			_by_key[u[0]] = u
		_by_key_src = uses
	var by_key := _by_key
	_seek_t -= dt
	var seek := _seek_t <= 0.0
	if seek:
		_seek_t = 0.25
	var rpm: float = town.real_per_game_minute() if town.has_method("real_per_game_minute") else 1.0
	for id in town._chr:
		if not seek and not _drive.has(id):
			continue
		var p: Dictionary = town.people[id]
		var root: Node3D = p.node
		var doing := String(p.doing)
		var moving: bool = town.motion_at(p, t) != Vector2.ZERO
		var here := Vector2(root.position.x, root.position.z)
		var d: Dictionary = _drive.get(id, {})
		var free: bool = root.visible and not moving and doing in IDLE_DOING and (plaza.grow(6.0).has_point(here) or not d.is_empty() or _reach > 20.0)
		if not d.is_empty() and (not free or not by_key.has(d.key)):
			_release(id)
			d = {}
		if d.is_empty() and free and root.visible:
			# the nearest free use point within reach
			var best = null
			var bd := _reach
			for u in uses:
				if _taken.has(u[0]):
					continue
				var dist := (u[2] as Vector2).distance_to(here)
				if dist < bd:
					bd = dist
					best = u
			if best != null:
				d = {"key": best[0], "t0": t, "from": here, "anim": "", "path": _path(here, best[2])}
				_drive[id] = d
				_taken[best[0]] = id
		if d.is_empty():
			continue
		var u: Array = by_key[d.key]
		_drive_one(id, d, u, t, rpm)


func _drive_one(id: String, d: Dictionary, u: Array, t: float, rpm: float) -> void:
	var e: Dictionary = town._chr[id]
	var root: Node3D = town.people[id].node
	var ch: Node3D = e.node
	var k := ch.scale.x
	var target: Vector2 = u[2]
	var act := String(u[4])
	var dir: Vector2 = u[6]
	var path: Array = d.path
	var dist := _route_len(path)
	var walked := (t - float(d.t0)) * WALK_M_PER_MIN
	var anim := ""
	var rate := float(ch.get_meta("base_speed", 1.0))
	if walked < dist:
		var r := _route_at(path, walked)
		var p: Vector2 = r[0]
		root.position = Vector3(p.x, 0.0, p.y)
		var mv: Vector2 = r[1]
		root.rotation.y = atan2(mv.x, mv.y)
		anim = "Walk"
		rate = (WALK_M_PER_MIN / maxf(rpm, 1e-4)) / (1.02 * float(ch.get_meta("stride", k)))
	else:
		var inst: Dictionary = u[1]
		var late := t >= sched_at(inst, "dance") or t >= sched_at(inst, "wedding_banquet") and act == "sentarse"
		anim = String(ACTION_ANIM[act][1 if late else 0])
		if act == "sentarse":
			var sp := target + dir * 0.33 * k
			root.position = Vector3(sp.x, float(u[5]) - 0.44 * k, sp.y)
			if anim == "Sitting_Talking" and inst.def in ["noble_wedding", "neighbours_wedding", "st_michael", "all_saints_matanza"] and town._has_anim(e, "eat"):
				anim = "eat"
				root.position = Vector3(sp.x, float(u[5]) - 0.45, sp.y) if false else root.position
		else:
			root.position = Vector3(target.x, float(u[5]), target.y)  # on a stage or a pulpit: its deck height
		root.rotation.y = atan2(dir.x, dir.y)
		if anim == "Dance":
			rate = 1.0
	var ap: AnimationPlayer = e.ap
	var want := String((CharBuilder as Script).call("anim_name", ap, anim)) if town._own() else anim
	if want == "":
		want = anim
	if anim != String(d.anim) or ap.current_animation != want:
		d.anim = anim
		town._play_anim(e, anim, 0.25)
	ap.speed_scale = rate


func _path(a: Vector2, b: Vector2) -> Array:
	## straight when near, else by the walkable tiles (the sim's) and the last step to the point
	if a.distance_to(b) < 6.0:
		return [a, b]
	var mid := _bfs(_tile_of(a), _tile_of(b))
	if mid.is_empty():
		return [a, b]
	return _smooth([a] + mid + [b])


func _release(id: String) -> void:
	var d: Dictionary = _drive.get(id, {})
	if not d.is_empty():
		_taken.erase(d.key)
	_drive.erase(id)


# ---------------------------------------------------------------- routes, the procession and the carnival
func _route(kind: String) -> Array:
	## godot x/z polyline from the church door round the plaza and back (by the walkable tiles), or round the plaza
	var pts := []
	var ring := plaza.grow(-4.2)  # round the well, inside the ring of stalls
	var loop := [Vector2(ring.position.x, ring.position.y), Vector2(ring.end.x, ring.position.y), ring.end,
		Vector2(ring.position.x, ring.end.y), Vector2(ring.position.x, ring.position.y)]
	if kind == "plaza" or town.church == null:
		return loop
	var dd: Array = town._door(town.church)
	var door := Vector2(dd[0].x, -dd[0].y) + Vector2(dd[1].x, -dd[1].y) * 1.5
	var first: Vector2 = loop[0]
	var bi := 0
	for i in loop.size() - 1:
		if (loop[i] as Vector2).distance_to(door) < first.distance_to(door):
			first = loop[i]
			bi = i
	var walk := _bfs(_tile_of(door), _tile_of(first))
	pts.append(door)
	pts.append_array(walk)
	for j in loop.size():
		pts.append(loop[(bi + j) % (loop.size() - 1)])
	var back := walk.duplicate()
	back.reverse()
	pts.append_array(back)
	pts.append(door)
	return _smooth(pts)


func _tile_of(g: Vector2) -> Vector2i:
	return Vector2i(floori(g.x / 2.0), floori(g.y / 2.0))


func _bfs(a: Vector2i, b: Vector2i) -> Array:
	var prev := {a: a}
	var q := [a]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == b:
			break
		for dlt in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dlt
			if prev.has(n) or not town.walkable(n.x, n.y):
				continue
			prev[n] = c
			q.append(n)
	if not prev.has(b):
		return []
	var out := []
	var c := b
	while c != a:
		out.push_front(_g(c.x, c.y))
		c = prev[c]
	return out


func _smooth(pts: Array) -> Array:
	var out := []
	for p in pts:
		if out.is_empty() or (out.back() as Vector2).distance_to(p) > 0.5:
			out.append(p)
	return out


func _route_at(route: Array, s: float) -> Array:
	## [point, tangent] at arc length s along the route (clamped)
	if route.size() < 2:
		return [route[0] if not route.is_empty() else Vector2.ZERO, Vector2(0, 1)]
	var acc := 0.0
	for i in route.size() - 1:
		var a: Vector2 = route[i]
		var b: Vector2 = route[i + 1]
		var l := a.distance_to(b)
		if acc + l >= s or i == route.size() - 2:
			var k := clampf((s - acc) / maxf(l, 1e-4), 0.0, 1.0)
			return [a.lerp(b, k), (b - a).normalized()]
		acc += l
	return [route.back(), Vector2(0, 1)]


func _route_len(route: Array) -> float:
	var l := 0.0
	for i in route.size() - 1:
		l += (route[i] as Vector2).distance_to(route[i + 1])
	return l


func _walk_procession(t: float) -> void:
	for inst in insts:
		if not inst.mounted or not inst.has("route"):
			continue
		var lay: Dictionary = layouts[inst.def]
		var pr: Dictionary = lay.get("procession", {})
		var at0 := sched_at(inst, String(pr.get("at", "procession")))
		if at0 == INF:
			at0 = float(inst.start) + 60.0
		var mins := float(pr.get("minutes", 100))
		var route: Array = inst.route
		var L := _route_len(route)
		if not inst.has("walkers_made"):
			_make_walkers(inst, pr)
		var loop: bool = pr.get("loop", false)
		var total := L + float(pr.get("length", 20.0))
		var speed := float(pr.get("speed", 0.55)) if loop else total / mins  # m per game minute
		var head := (t - at0) * speed if loop else clampf((t - at0) / mins, 0.0, 1.0) * total
		var moving := t >= at0 and t <= at0 + mins
		var rpm: float = town.real_per_game_minute() if town.has_method("real_per_game_minute") else 1.0
		for w in _walkers:
			if w.inst != inst or not is_instance_valid(w.node):
				continue
			var s := head - float(w.offset)
			if loop and moving:
				s = fposmod(s, L)
			var r := _route_at(route, clampf(s, 0.0, L))
			var tan: Vector2 = r[1]
			var nrm := Vector2(-tan.y, tan.x)
			var p: Vector2 = (r[0] as Vector2) + nrm * float(w.lateral)
			var yaw := atan2(tan.x, tan.y) + float(w.get("turn", 0.0))
			var out := s < 0.0 or s > L or not (moving or loop and t >= at0)
			if loop and not moving:
				out = true
			var park = w.get("park")
			(w.node as Node3D).visible = not out or park != null
			if park != null:
				# waiting where it was put (before the church); it walks to the route in its first and last 3 m
				var pg: Vector2 = park
				var py := deg_to_rad(float(w.park_rot)) + float(w.get("park_turn", 0.0))
				if out:
					p = pg
					yaw = py
				elif s < 3.0 and not loop:
					p = pg.lerp(p, s / 3.0)
				elif s > L - 3.0 and not loop:
					p = p.lerp(pg, (s - (L - 3.0)) / 3.0)
			var n: Node3D = w.node
			n.position = Vector3(p.x, n.position.y, p.y)
			n.rotation.y = yaw
			var walking := not out
			if w.has("ap"):
				var anim := String(w.walk) if walking else String(w.stand)
				if String(w.get("playing", "")) != anim:
					w.playing = anim
					(CharBuilder as Script).call("play", n, anim, String(w.get("carry", "")), 0.25)
				(w.ap as AnimationPlayer).speed_scale = clampf((speed / maxf(rpm, 1e-4)) / 1.02, 0.3, 2.2) if walking else 1.0
			elif w.get("bob", false) and walking:
				n.position.y = absf(sin(_t * 4.2 + float(w.offset))) * 0.06
				n.rotation.z = sin(_t * 2.1 + float(w.offset)) * 0.04


func _make_walkers(inst: Dictionary, pr: Dictionary) -> void:
	## the pieces of the procession leave their place and follow the route; the bearers are hooded figures (CharBuilder)
	inst.walkers_made = true
	var offs := 0.0
	for el: Dictionary in pr.get("order", []):
		var id := String(el.p) if el.has("p") else ""
		var node: Node3D = null
		var park = null
		var park_rot := 0.0
		for pl in inst.placed:
			if pl.id == id and not pl.get("walker", false) and not pl.get("nodes", []).is_empty():
				node = pl.nodes[0]
				pl.walker = true
				park = pl.g
				park_rot = pl.rot
				if pl.has("obstacle"):
					town.seat_obstacles.erase(pl.obstacle)
					pl.erase("obstacle")
				break
		if id != "" and node == null:
			node = _build(id, Vector2.ZERO, 0.0, el.get("opts", {}), inst)
		var off := float(el.get("gap", 2.5))
		offs += off
		if node:
			_walkers.append({"inst": inst, "node": node, "offset": offs, "lateral": float(el.get("x", 0.0)), "bob": true,
				"turn": PI if el.get("turn", false) else 0.0, "park": park, "park_rot": park_rot})
		for b: Array in el.get("bearers", []):
			var fig := _figure(String(el.get("look", "penitent")), _walkers.size())
			if fig == null:
				continue
			var w := {"inst": inst, "node": fig, "offset": offs - float(b[1]) if el.get("turn", false) else offs + float(b[1]),
				"lateral": float(b[0]), "ap": fig.get_node("AnimationPlayer"),
				"walk": String(el.get("walk", "Walk_Formal")), "stand": String(el.get("stand", "Idle")), "carry": String(b[2]) if b.size() > 2 else ""}
			if park != null:  # beside its piece where it waits, facing as the piece
				w.park = _world(Vector2(float(b[0]) * 1.35, float(b[1])), park, park_rot)
				w.park_rot = park_rot
				w.park_turn = PI if el.get("turn", false) else 0.0
			_walkers.append(w)
		if el.has("rows"):
			for i in int(el.rows):
				offs += 1.4
				for x in [-1.2, 1.2]:
					var fig := _figure(String(el.get("look", "penitent")), _walkers.size())
					if fig:
						_walkers.append({"inst": inst, "node": fig, "offset": offs, "lateral": x, "ap": fig.get_node("AnimationPlayer"),
							"walk": "Walk_Formal", "stand": "Idle", "carry": String(el.get("carry", ""))})
	if "_ob_count" in town:
		town._ob_count = -1
	_log("%s: procession of %d along %.0f m" % [inst.def, _walkers.filter(func(w): return w.inst == inst).size(), _route_len(inst.route)])


func _walks(inst: Dictionary, pl: Dictionary) -> bool:
	## a piece the procession takes along (it is not an obstacle where it waits)
	for el in layouts[inst.def].get("procession", {}).get("order", []):
		if String(el.get("p", "")) == String(pl.id):
			return true
	return false


func _figure(look: String, seed: int) -> Node3D:
	## an anonymous hooded figure (nazareno, bearer of the giants): the clergy look of sim3d_chars in the festival colour
	var dye: String = {"penitent": "lila", "corpus": "crudo", "carnival": "rojo", "noble": "granate"}.get(look, "lila")
	var d := {name = "Figura_%s_%d" % [look, seed], sex = "m", seed = 500 + seed, height = 0.98 + float(seed % 5) / 100.0, anim = "Idle",
		parts = {torso = "ranger", arms = "ranger", legs = "ranger", feet = "peasant", hair = "hair_buzzed", acc = ["hood"]},
		paint = {"*": {"tex": "ranger3"}, "torso": [dye, "negro"], "arms": [dye, "negro"], "legs": ["", "negro"],
			"hood_ranger_m": ["", dye], "feet": {"tex": "peasant"}, "skin": "fair", "hair": "dark"}}
	var ch := CharBuilder.build(d)
	if ch == null:
		return null
	add_child(ch)
	ch.set_meta("fp_small", false)
	return ch


# ---------------------------------------------------------------- check (sim3d --simcheck)
func _check() -> void:
	## for every piece while it stands: the trace's tile centres under it (grown by a body), and the steps of the trace
	## (as sim3d.gd plays them, steered round the obstacles) that still fall inside it
	var rep := {"festivals": [], "pieces": 0, "walked_centres_under": 0, "steered_inside": 0, "people_standing_under": 0}
	for inst in insts:
		var obs := []
		for pl in inst.placed:
			if not pl.overhead and pl.e.get("blocks", true) and not pl.e.get("flat", false):
				var ob := _obstacle(pl)
				obs.append(ob)
				town.seat_obstacles.append(ob)
		if "_ob_count" in town:
			town._ob_count = -1
		var a := float(inst.start)
		var b := float(inst.end)
		var under := 0
		var inside := 0
		var standing := 0
		var bad := []
		for pl in inst.placed:
			if pl.overhead or pl.e.get("flat", false) or not pl.e.get("blocks", true) or pl.get("walker", false):
				continue
			rep.pieces += 1
			var c := _walk_cost(pl.g, pl.rot, pl.half - Vector2(BODY, BODY) * 0.0, a, b)
			if c > 0.0:
				under += 1
				bad.append([pl.id if not pl.group else String(pl.e.group), pl.g.snapped(Vector2(0.1, 0.1)), snappedf(c, 0.1)])
		for id in town.trace.characters:
			var pos: Array = town.trace.characters[id].pos
			var n := pos.size() / 3
			for k in range(1, n):
				var m := float(pos[k * 3])
				if m < a or m > b:
					continue
				var p0 := _g(float(pos[k * 3 - 2]), float(pos[k * 3 - 1]))
				var p1 := _g(float(pos[k * 3 + 1]), float(pos[k * 3 + 2]))
				if p0.distance_to(p1) > 3.0:
					continue
				for j in 9:
					var q := p0.lerp(p1, j / 8.0)
					var pl_q := Vector2(q.x, -q.y)
					var st: Vector2 = town.avoid(pl_q) if town.has_method("avoid") else pl_q
					var sq := Vector2(st.x, -st.y)
					for pl in inst.placed:
						if pl.overhead or pl.e.get("flat", false) or not pl.e.get("blocks", true) or _walks(inst, pl):
							continue
						var l := _local(sq, pl.g, pl.rot)
						if absf(l.x) < pl.half.x - 0.05 and absf(l.y) < pl.half.y - 0.05:
							inside += 1
		for ob in obs:
			town.seat_obstacles.erase(ob)
		if "_ob_count" in town:
			town._ob_count = -1
		rep.walked_centres_under += under
		rep.steered_inside += inside
		rep.festivals.append({"def": inst.def, "kind": inst.kind, "from": _hhmm(inst.start), "to": _hhmm(inst.end),
			"pieces": inst.placed.size(), "pieces_on_walked_tiles": under, "which": bad, "steered_points_inside": inside})
	var f := FileAccess.open("res://out/fp_check.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	print("[FiestasPueblo] check: %d pieces; on a tile the trace walks while they stand: %d; steered points of the trace still inside a piece: %d (out/fp_check.json)" % [
		rep.pieces, rep.walked_centres_under, rep.steered_inside])
	for fz in rep.festivals:
		print("[FiestasPueblo]   %s %s..%s: %d pieces, %d on walked tiles %s, %d steered points inside" % [fz.def, fz.from, fz.to,
			fz.pieces, fz.pieces_on_walked_tiles, fz.which, fz.steered_points_inside])
