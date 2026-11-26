extends "res://game/world3d/town/pueblo.gd"
## Plays a GuildMaster sim trace (tools/sim_trace.gd) over the 3D town built from the same map (pueblo.gd).
## One marker per character: a capsule in its family colour, its name and an icon of what it does. People inside a
## building are hidden (as in the 2D view) and counted over the roof. The light follows the hour.
## Run:   godot --path . res://sim3d.tscn [-- --trace=<path>] [--at=HH:MM] [--speed=10]
## Check: godot --headless --path . res://sim3d.tscn -- --simcheck   (paths vs 3D houses/trees/props/doors; no window)
## Shots: godot --path . res://sim3d.tscn -- --simshots               (out/sim3d_*.png)
## Keys: Space pause · [ ] or - + speed (x1 x10 x60 x300) · Tab follow next person · F stop following ·
##       (x0.25 x0.5 x1 x10 x60 x300; at x0.25 a straight step is 1.2 m/s, a walk) ·
##       WASD/arrows pan · Q/E rotate · PgUp/PgDn tilt · wheel zoom · C cutaway · R restart · N names on/off

const DEFAULT_TRACE := "res://out/trace_town_e.json"
const GAME_MIN_PER_SEC := 1440.0 / 300.0  # GuildMaster at x1: one day = 5 real minutes (data/time.json)
const SPEEDS := [0.25, 0.5, 1.0, 10.0, 60.0, 300.0]  # x1 = GuildMaster's x1 (one tile = 2 m in 0.42 s: a sprint)
const ICON := {"work": "⚒", "work_out": "⚒", "work_night": "⚒", "sleep": "💤", "home": "🏠", "shopping": "🛒",
	"market": "🛒", "chat": "💬", "greet": "👋", "social": "💬", "court": "❤", "guard_patrol": "🛡", "guard_post": "🛡",
	"guard_greet": "🛡", "guard_respond": "🛡", "mass": "⛪", "water": "💧", "wash": "💧", "brawl": "👊",
	"watch_fight": "👀", "watch_show": "👀", "dice": "🎲", "eat_home": "🍲", "bench": "🪑", "errand": "📦",
	"leisure": "🍺", "inside": "🚪"}
const PHASE_ES := {"dawn": "amanecer", "day": "día", "dusk": "atardecer", "night": "noche"}
const SEASON_ES := {"spring": "primavera", "summer": "verano", "autumn": "otoño", "winter": "invierno"}

var trace: Dictionary
var mpt := 2.0
var t_min := 0.0
var t0 := 0.0
var t1 := 0.0
var speed_i := 3
var paused := false
var names_on := true
var follow_id := ""
var people := {}      # chr id -> {node, body, icon, label, pos: PackedInt32Array, st: Array, first, jitter}
var bld_anchor := {}  # sim building id -> {house, door: Vector2 plan, top: Vector3, label: Label3D}
var _sun: DirectionalLight3D
var _env: Environment
var _hud: Label
var _days := []       # [{day, bounds: {dawn, day, dusk, night}}]
var use_cart := true  # GuildMaster: the scripted cart along the main road (off in the game: the sim has no such cart)


func _ready() -> void:
	var path := DEFAULT_TRACE
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trace="):
			path = a.trim_prefix("--trace=")
	if trace.is_empty():  # GuildMaster: Town3D sets trace (the live feed of the sim) before _ready
		var txt := FileAccess.get_file_as_string(path)
		if txt != "":
			trace = JSON.parse_string(txt)
	if not trace.is_empty():
		walk_mask = trace.get("map", {}).get("walkable", [])  # props keep off the sim's walkable tiles (pueblo.gd)
		_sim_buildings()
	super()
	var at := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trace="):
			path = a.trim_prefix("--trace=")
		elif a.begins_with("--at="):
			at = a.trim_prefix("--at=")
		elif a.begins_with("--speed="):
			speed_i = maxi(0, SPEEDS.find(float(a.trim_prefix("--speed="))))
	if trace.is_empty():
		push_error("[Sim3D] no trace at %s (run tools/sim_trace.gd)" % path)
		return
	mpt = float(trace.meta.minutes_per_tile)
	if use_cart and vivo != null and (vivo.cfg as Dictionary).has("convoy") and not "--simcheck" in OS.get_cmdline_user_args():
		cart_trip = preload("res://game/world3d/town/cart_trip.gd").new(self, vivo.cfg.convoy)
		cart_trip.setup()
	t0 = float(trace.meta.start_minute)
	t1 = float(trace.meta.end_minute)
	t_min = t0
	if at != "":
		t_min = _day_start(t0) + _dia_offset() + int(at.get_slice(":", 0)) * 60 + int(at.get_slice(":", 1))
	for n in get_children():
		if n is DirectionalLight3D:
			_sun = n
		elif n is WorldEnvironment:
			_env = n.environment
	_parse_days()
	_anchor_buildings()
	_live_setup()
	_night_setup()
	_clima_setup()
	_spawn_people()
	_make_hud()
	if OS.is_debug_build():
		print("[Sim3D] trace %s: %d people, %d buildings, minutes %d..%d (mpt=%d)" % [path, people.size(),
			bld_anchor.size(), int(t0), int(t1), int(mpt)])
	var args := OS.get_cmdline_user_args()
	if "--simcheck" in args:
		_check()
		get_tree().quit()
	elif "--simshots" in args:
		_sim_shots()
	else:
		_apply(t_min)


func _sim_buildings() -> void:
	## what the trace knows of each building at its first minute, for pueblo.gd (level of look, building works, farms)
	## and the season of that day (crops)
	var start := float(trace.meta.start_minute)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):  # the town is built as the trace has it at the minute the playback starts
			start = _day_start(start) + _dia_offset() + int(a.trim_prefix("--at=").get_slice(":", 0)) * 60 + int(a.trim_prefix("--at=").get_slice(":", 1))
	for b in trace.buildings:
		var bd: Dictionary = trace.buildings[b]
		if (bd.get("origin", []) as Array).size() != 2:
			continue
		sim_buildings[Vector2i(int(bd.origin[0]), int(bd.origin[1]))] = _bld_at(b, start)
	var days: Array = trace.meta.get("days", [])
	if not days.is_empty():
		season_id = String(days[0].get("season", "spring"))
	if OS.is_debug_build():
		print("[Sim3D] %d buildings of the trace with their state at minute %d (season %s)" % [sim_buildings.size(), int(start), season_id])


var _farm_of := {}  # sim building -> somebody who lives there works the fields


func _bld_at(b: String, t: float) -> Dictionary:
	## what the trace knows of a building at minute t, as pueblo.gd reads it (sim_buildings): the row of its timeline in
	## force (finished upgrades, upgrade works, building works) and whether the sim has it at all yet
	var bd: Dictionary = trace.buildings[b]
	var row: Array = []
	for r in bd.get("tl", []):
		if float(r[0]) <= t or row.is_empty():
			row = r
	if not _farm_of.has(b):
		var farm := false
		for id in trace.characters:
			var c: Dictionary = trace.characters[id]
			if String(c.get("home", "")) == b and String(c.get("occupation", "")).begins_with("field"):
				farm = true
		_farm_of[b] = farm
	return {"id": b, "now": t, "farm": _farm_of[b], "type": String(bd.get("type", "")), "door": bd.get("door", []),
		"footprint": bd.get("footprint", []), "plot": String(bd.get("plot", "")), "exists": t >= float(bd.get("first", 0)) or float(bd.get("first", 0)) <= float(trace.meta.start_minute),
		"upgrades": row[2] if row.size() > 2 else [], "work": row[3] if row.size() > 3 else [],
		"construction": row[4] if row.size() > 4 else []}


# ---------------------------------------------------------------- levels and building works as the trace plays
## A building whose timeline changes during the trace (an upgrade finished, upgrade works, building works) is looked at
## once per game minute: when its look changes (pueblo.gd look_key: level, stage of the works), its house is built
## again where it stands (pueblo.gd rebuild_house) and everything that pointed at the old one follows (_rehoused).
var _live_blds := []     # the sim buildings whose look may change during the trace
var _live_t := -1.0e9
var rebuilds := []       # [{minute, house, from, to, ms}]


func _live_setup() -> void:
	for b in trace.buildings:
		var bd: Dictionary = trace.buildings[b]
		var tl: Array = bd.get("tl", [])
		if (bd.get("origin", []) as Array).size() != 2 or not bld_anchor.has(b):
			continue
		var moves := tl.size() > 1 or float(bd.get("first", 0)) > float(trace.meta.start_minute)
		for r in tl:
			if (r as Array).size() > 4 and (not (r[3] as Array).is_empty() or not (r[4] as Array).is_empty()):
				moves = true
		if moves:
			_live_blds.append(b)
	if OS.is_debug_build():
		print("[Sim3D] %d buildings whose level or works change during the trace: %s" % [_live_blds.size(), _live_blds])


func _live_buildings(t: float) -> void:
	if absf(t - _live_t) < 1.0 or "--vivo-obra=no" in OS.get_cmdline_user_args():
		return
	_live_t = t
	for b: String in _live_blds:
		var bd: Dictionary = trace.buildings[b]
		var o := Vector2i(int(bd.origin[0]), int(bd.origin[1]))
		var h: Node3D = bld_anchor[b].house
		if not is_instance_valid(h) or not h.has_meta("lot") or (h.get_meta("lot").box as Rect2i).position != o:
			continue  # anchored to the house of another lot
		sim_buildings[o] = _bld_at(b, t)
		var key := look_key(_look_of(h.get_meta("lot")))
		var was := String(h.get_meta("look_key", ""))
		if key == was:
			continue
		_before_rehouse(h)
		var nh := rebuild_house(h)
		if nh == null:
			continue
		_rehoused(h, nh)
		rebuilds.append({"minute": int(t), "house": String(nh.name), "from": was, "to": key, "ms": (rebuild_ms[String(nh.name)] as Array).back()})
		_live_t = -1.0e9  # one house per frame: the next one, if any, on the next
		break


func _house_merged(h: Node3D) -> void:
	var lit := bool(_glass_on.get(h, false))
	_glass_on.erase(h)
	_glass[h] = _glass_of(h)
	_set_windows(h, lit)


func _before_rehouse(_h: Node3D) -> void:
	pass  # sim3d_chars.gd: an open house closes first


func _rehoused(old: Node3D, nh: Node3D) -> void:
	## what pointed at the old house: the anchors of the sim buildings (count over the roof, door lamp), the window
	## glass that lights at night, the wall lantern by the door, the walkers' obstacles
	for b in bld_anchor:
		if bld_anchor[b].house == old:
			bld_anchor[b].house = nh
			var top := nh.position + Vector3(0, float(nh.get_meta("top", 7.0)), 0)
			bld_anchor[b].top = top
			(bld_anchor[b].label as Label3D).position = top
	_glass.erase(old)
	_glass_on.erase(old)
	_glass[nh] = _glass_of(nh)
	if old.has_meta("lantern") and is_instance_valid(old.get_meta("lantern")):
		(old.get_meta("lantern") as Node).queue_free()
	_door_lantern(nh)
	_ob_count = -1


var pitch := 52.0  # steeper than pueblo's 30: the streets between the houses must show

# ---------------------------------------------------------------- camera: continuous WASD / Q-E / zoom, like a game
## Held keys move the camera every frame; speed eases in and out (no jumps). W/A/S/D or arrows pan, Shift faster,
## Q/E turn, RePág/AvPág tilt, the wheel or a trackpad pinch zoom towards a goal the size eases to.
const CAM_PAN_SPEED := 0.9      # ortho sizes per second: the same feel at any zoom
const CAM_FAST := 2.5           # with Shift
const CAM_TURN_SPEED := 110.0   # degrees per second
const CAM_TILT_SPEED := 40.0    # degrees per second
const CAM_EASE := 9.0           # 1/s: how fast the speed follows the keys (start and stop in ~0.3 s)
const CAM_ZOOM_EASE := 12.0     # 1/s: how fast the size follows the wheel
const CAM_ZOOM_MIN := 3.0     # close enough to see a face or a hinge (the old floor was 8)
const CAM_ZOOM_MAX := 90.0    # the whole town and its outskirts
var _cam_vel := Vector3.ZERO
var _yaw_vel := 0.0
var _tilt_vel := 0.0
var _zoom_goal := -1.0


func _cam_free() -> bool:
	## sim3d_chars locks the camera while it animates it (opening a house) or shows the separate interior
	return true


func _held(keys: Array) -> bool:
	for k in keys:
		if Input.is_key_pressed(k):
			return true
	return false


func _cam_keys(delta: float) -> void:
	if not _cam_free() or get_viewport().gui_get_focus_owner() != null:
		_cam_vel = Vector3.ZERO
		_yaw_vel = 0.0
		_tilt_vel = 0.0
		_zoom_goal = -1.0
		return
	var k := 1.0 - exp(-CAM_EASE * delta)
	var mv := Vector3.ZERO
	if _held([KEY_W, KEY_UP]): mv.z -= 1.0
	if _held([KEY_S, KEY_DOWN]): mv.z += 1.0
	if _held([KEY_A, KEY_LEFT]): mv.x -= 1.0
	if _held([KEY_D, KEY_RIGHT]): mv.x += 1.0
	if mv != Vector3.ZERO:
		follow_id = ""
		mv = mv.normalized() * cam.size * CAM_PAN_SPEED * (CAM_FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_cam_vel = _cam_vel.lerp(mv, k)
	var turn := (1.0 if Input.is_key_pressed(KEY_E) else 0.0) - (1.0 if Input.is_key_pressed(KEY_Q) else 0.0)
	_yaw_vel = lerpf(_yaw_vel, turn * CAM_TURN_SPEED, k)
	var tilt := (1.0 if Input.is_key_pressed(KEY_PAGEUP) else 0.0) - (1.0 if Input.is_key_pressed(KEY_PAGEDOWN) else 0.0)
	_tilt_vel = lerpf(_tilt_vel, tilt * CAM_TILT_SPEED, k)
	var moved := false
	if _cam_vel.length_squared() > 1e-6:
		target += _cam_vel.rotated(Vector3.UP, deg_to_rad(yaw)) * delta
		moved = true
	if absf(_yaw_vel) > 0.01:
		yaw = fposmod(yaw + _yaw_vel * delta, 360.0)
		moved = true
	if absf(_tilt_vel) > 0.01:
		pitch = clampf(pitch + _tilt_vel * delta, 26.0, 80.0)
		moved = true
	if _zoom_goal > 0.0:
		cam.size = lerpf(cam.size, _zoom_goal, 1.0 - exp(-CAM_ZOOM_EASE * delta))
		if absf(cam.size - _zoom_goal) < 0.02:
			cam.size = _zoom_goal
			_zoom_goal = -1.0
	if moved:
		_update_camera()


func _zoom_by(f: float) -> void:
	var from := _zoom_goal if _zoom_goal > 0.0 else cam.size
	_zoom_goal = clampf(from * f, CAM_ZOOM_MIN, CAM_ZOOM_MAX)


func _update_camera() -> void:
	cam.rotation_degrees = Vector3(-pitch, yaw, 0)
	cam.position = target + cam.basis.z * 80.0
	if cutaway:
		set_cutaway(true)


func _dia_offset() -> float:
	## --dia=N (1 = the first day of the trace) moves --at to that day; --fiesta= forces its festival on day 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dia="):
			return maxf(0.0, float(int(a.trim_prefix("--dia=")) - 1)) * 1440.0
	return 0.0


func _day_start(m: float) -> float:
	return floorf(m / 1440.0) * 1440.0


# ---------------------------------------------------------------- setup
func _parse_days() -> void:
	for d in trace.meta.days:
		var b := {}
		var prev: String = d.phase_by_half_hour["0"]
		for k in range(30, 1440, 30):
			var ph: String = d.phase_by_half_hour[str(k)]
			if ph != prev:
				b[ph] = k  # the minute each phase starts (night starts in the evening, not at 00:00)
			prev = ph
		_days.append({"day": int(d.day), "season": String(d.season), "bounds": b})


func _anchor_buildings() -> void:
	## each sim building -> the 3D house whose door is nearest the sim door tile (pueblo.gd places the houses)
	for b in trace.buildings:
		var bd: Dictionary = trace.buildings[b]
		if (bd.door as Array).size() != 2:
			continue
		var door_p := _tp(float(bd.door[0]), float(bd.door[1]))
		var best: Node3D = null
		var best_d := 1e9
		for h in houses:
			var dd := _door(h)
			var dist: float = (dd[0] as Vector2).distance_to(door_p)
			if dist < best_d:
				best_d = dist
				best = h
		if best == null:
			continue
		var top := best.position + Vector3(0, float(best.get_meta("top", 9.0 if best.get_meta("type", "") in ["tavern_inn", "town_hall"] else 7.0)), 0)
		var lab := _label3d("", 120, Color(1, 0.97, 0.85))
		lab.position = top
		add_child(lab)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.7, 0.38)
		lamp.omni_range = 7.0
		lamp.light_energy = 0.0
		var dd0 := _door(best)
		var lp: Vector2 = (dd0[0] as Vector2) + (dd0[1] as Vector2) * 0.8
		lamp.position = HouseBuilder.plan_to_godot(Vector3(lp.x, lp.y, 2.2))
		add_child(lamp)
		bld_anchor[b] = {"house": best, "door": door_p, "dist": best_d, "top": top, "label": lab, "type": bd.type,
			"lamp": lamp}


# ---------------------------------------------------------------- light, weather and life (docs/clima.md)
const Luz := preload("res://game/world3d/light/luz.gd")
const Clima := preload("res://game/world3d/light/clima.gd")
var luz: RefCounted     # scripts/clima/luz.gd: the light by the hour and what gives depth
var clima: Node         # scripts/clima/clima.gd: the weather (group "clima"), its effects and the life by season
var lluvia_gente: RefCounted  # scripts/clima/lluvia_gente.gd: who stands in the street shelters, sacks over the heads


func _clima_setup() -> void:
	if DisplayServer.get_name() == "headless" and "--simcheck" in OS.get_cmdline_user_args():
		return
	luz = Luz.new(self, Luz.parse(OS.get_cmdline_user_args()))
	clima = Clima.new()
	clima.name = "Clima"
	add_child(clima)
	clima.setup(self)
	lluvia_gente = preload("res://game/world3d/light/lluvia_gente.gd").new(self)


func _variant(m: Material, s: String) -> Material:
	## "relieve": the kit's own shading (its normal maps and roughness, no toon bands) with the outline pass
	if s != "relieve" or not (m is StandardMaterial3D):
		return super(m, s)
	var key := "%s|%d" % [s, m.get_instance_id()]
	if not _variants.has(key):
		var v: StandardMaterial3D = m.duplicate()
		v.next_pass = _outline_mat
		_variants[key] = v
	return _variants[key]


# ---------------------------------------------------------------- night: windows and lanterns
## Windows: the glass surfaces (MI_WindowGlass) of a sim building's 3D house get a warm emissive material while somebody
## inside is awake after dusk (the trace's doing != sleep), and go back to their own material when they sleep or leave.
## Lanterns: a wall lantern beside every house door (emissive glass, lit from dusk to dawn) and the door lamp of each
## sim building (OmniLight, brighter while someone is awake inside). Light and sky follow data/time.json phases (_light).
var _glass := {}        # house -> [[MeshInstance3D, surface, own override]]
var _glass_on := {}     # house -> bool
var _win_mat: StandardMaterial3D
var _lantern_mat: StandardMaterial3D
var night_stats := {"glass_surfaces": 0, "lanterns": 0, "lamps": 0}
var _lantern_glows: Array = []  # the lit pane of every door lantern: hidden by day (unlit it is a pale box inside the cage)
var _glows_on := false


func _night_setup() -> void:
	_win_mat = StandardMaterial3D.new()
	_win_mat.albedo_color = Color(0.35, 0.2, 0.08)
	_win_mat.emission_enabled = true
	_win_mat.emission = Color(1.0, 0.68, 0.32)
	_win_mat.emission_energy_multiplier = 2.2
	_lantern_mat = StandardMaterial3D.new()
	_lantern_mat.albedo_color = Color(0.9, 0.7, 0.4)
	_lantern_mat.emission_enabled = true
	_lantern_mat.emission = Color(1.0, 0.72, 0.36)
	_lantern_mat.emission_energy_multiplier = 0.0
	_lantern_scene = load(QPROPS % "Lantern_Wall")
	_glow_mesh = BoxMesh.new()
	_glow_mesh.size = Vector3(0.2, 0.28, 0.2)
	for h in houses:
		_glass[h] = _glass_of(h)
		night_stats.glass_surfaces += (_glass[h] as Array).size()
		_door_lantern(h)
	night_stats.lamps = bld_anchor.size()
	if OS.is_debug_build():
		print("[Sim3D] night: %d window glass surfaces in %d houses, %d lanterns, %d door lamps" % [
			night_stats.glass_surfaces, houses.size(), night_stats.lanterns, night_stats.lamps])


var _lantern_scene: PackedScene
var _glow_mesh: BoxMesh


func _glass_of(h: Node3D) -> Array:
	## [[MeshInstance3D, surface, own override]] of the window glass of a house
	var list := []
	for mi in h.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var sm := m.mesh.surface_get_material(i)
			if sm and sm.resource_name.contains("Glass"):
				list.append([m, i, m.get_surface_override_material(i)])
	return list


func _door_lantern(h: Node3D) -> void:
	## a lantern on the wall beside the door, its arm out of the facade: on the side the house's modules leave free
	## (pueblo.gd _module_spots: the hanging sign and the shop windows), none if both are taken or it is a building site
	var lside := float(h.get_meta("lantern_side", 1.0))
	if lside == 0.0:
		return
	var dd := _door(h)
	var lp: Vector2 = (dd[0] as Vector2) + (dd[2] as Vector2) * 1.25 * lside + (dd[1] as Vector2) * 0.02
	var n: Node3D = _lantern_scene.instantiate()
	n.position = HouseBuilder.plan_to_godot(Vector3(lp.x, lp.y, 1.9))
	var og := Vector3((dd[1] as Vector2).x, 0, -(dd[1] as Vector2).y)
	n.rotation.y = atan2(og.x, og.z)
	var g := MeshInstance3D.new()
	g.mesh = _glow_mesh
	g.material_override = _lantern_mat
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.position = Vector3(0, 0.62, 1.08)
	g.visible = _glows_on
	_lantern_glows.append(g)
	n.add_child(g)
	add_child(n)
	h.set_meta("lantern", n)  # SituCut hides it while its wall is down
	night_stats.lanterns += 1


func _set_windows(h: Node3D, on: bool) -> void:
	if bool(_glass_on.get(h, false)) == on:
		return
	_glass_on[h] = on
	for g in _glass.get(h, []):
		(g[0] as MeshInstance3D).set_surface_override_material(int(g[1]), _win_mat if on else g[2])


func _night_update(t: float) -> void:
	var dark := 1.0 - daylight(t)
	_lantern_mat.emission_energy_multiplier = 5.0 * clampf(dark * 1.6 - 0.3, 0.0, 1.0)
	var lit := _lantern_mat.emission_energy_multiplier > 0.01
	if lit != _glows_on:
		_glows_on = lit
		var alive := []
		for g in _lantern_glows:  # the lantern of a house built again is gone (untyped: a freed one cannot be assigned)
			if is_instance_valid(g):
				(g as Node3D).visible = lit
				alive.append(g)
		_lantern_glows = alive
	_win_mat.emission_energy_multiplier = 0.8 + 3.6 * dark


func _label3d(text: String, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.outline_size = 12
	l.modulate = col
	l.outline_modulate = Color(0.12, 0.08, 0.05)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	return l


func _spawn_people() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.93, 0.76, 0.6)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.2
	head_mesh.height = 0.4
	_skin_mat = skin
	_head_mesh = head_mesh
	for id in trace.characters:
		_spawn_person(String(id), skin, head_mesh)


var _skin_mat: StandardMaterial3D
var _head_mesh: SphereMesh


## One marker (GuildMaster: also called for people who appear while the game runs).
func _spawn_person(id: String, skin: StandardMaterial3D = null, head_mesh: SphereMesh = null) -> void:
	if skin == null:
		skin = _skin_mat
		head_mesh = _head_mesh
	if true:
		var c: Dictionary = trace.characters[id]
		var fam: Dictionary = trace.families.get(c.family, {})
		var col := Color.from_string(String(fam.get("color", "#808080")), Color.GRAY)
		var root := Node3D.new()
		root.name = id
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.26
		cm.height = 1.25
		body.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = col.lightened(0.15)
		body.material_override = m
		body.position.y = 0.62
		root.add_child(body)
		var head := MeshInstance3D.new()
		head.mesh = head_mesh
		head.material_override = skin
		head.position.y = 1.42
		root.add_child(head)
		var name_l := _label3d(String(c.name), 40, Color(1, 1, 1))
		name_l.no_depth_test = false
		name_l.position.y = 2.0
		root.add_child(name_l)
		var icon_l := _label3d("", 110, Color(1, 1, 1))
		icon_l.position.y = 2.75
		root.add_child(icon_l)
		add_child(root)
		var h := hash(String(id))
		var jit := Vector2(float(h % 97) / 97.0 - 0.5, float((h / 97) % 89) / 89.0 - 0.5) * 0.8
		people[id] = {"node": root, "name": name_l, "icon": icon_l, "pos": PackedInt32Array(c.pos), "st": c.st,
			"first": float(c.first), "jitter": jit, "doing": "", "loc": ""}


func _make_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.72)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(12, 12)
	cl.add_child(panel)
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 20)
	panel.add_child(_hud)


# ---------------------------------------------------------------- playback
func _process(delta: float) -> void:
	_cam_keys(delta)
	if trace.is_empty() or "--simshots" in OS.get_cmdline_user_args():
		return
	if not paused:
		t_min += delta * GAME_MIN_PER_SEC * SPEEDS[speed_i]
		if t_min >= t1:
			t_min = t0
	_apply(t_min)
	if follow_id != "" and people.has(follow_id):
		var n: Node3D = people[follow_id].node
		if n.visible:
			target = target.lerp(n.position + Vector3(0, 1, 0), minf(1.0, delta * 4.0))
			_update_camera()


## A plan point pushed out of the seat obstacles (pueblo.gd seat_obstacles: capsules [a, b, radius]) by a body radius:
## the view steers walkers round the benches and stools the sim does not know about. Continuous in p.
const BODY_R := 0.3


var _ob_grid := {}   # Vector2i (4 m cell) -> [obstacle]: the obstacles near a point without walking the whole list
var _ob_count := -1


func _obstacles_near(p: Vector2) -> Array:
	if _ob_count != seat_obstacles.size():
		_ob_count = seat_obstacles.size()
		_ob_grid.clear()
		for ob in seat_obstacles:
			var a: Vector2 = ob[0]
			var b: Vector2 = ob[1]
			var r := float(ob[2]) + BODY_R + 0.2
			for cx in range(floori((minf(a.x, b.x) - r) / 4.0), floori((maxf(a.x, b.x) + r) / 4.0) + 1):
				for cy in range(floori((minf(a.y, b.y) - r) / 4.0), floori((maxf(a.y, b.y) + r) / 4.0) + 1):
					var k := Vector2i(cx, cy)
					if not _ob_grid.has(k):
						_ob_grid[k] = []
					_ob_grid[k].append(ob)
	return _ob_grid.get(Vector2i(floori(p.x / 4.0), floori(p.y / 4.0)), [])


var cart_trip: RefCounted = null  # the cart that crosses the town along the main road (scripts/cart_trip.gd)


func avoid(p: Vector2) -> Vector2:
	var moving: Array = cart_trip.capsule if cart_trip != null else []
	for it in 3:
		var obs: Array = _obstacles_near(p)
		if not moving.is_empty():
			obs = obs + [moving]  # the cart going by: walkers step aside
		for ob in obs:
			var a: Vector2 = ob[0]
			var b: Vector2 = ob[1]
			var ab := b - a
			var k := 0.0 if ab.length_squared() < 1e-6 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var q := a + ab * k
			var R: float = float(ob[2]) + BODY_R
			var d := p.distance_to(q)
			if d < R:
				var n := (p - q) / d if d > 1e-4 else (Vector2(-ab.y, ab.x).normalized() if ab.length_squared() > 1e-6 else Vector2(1, 0))
				p = q + n * R
	return p


func clearance(p: Vector2) -> float:
	## distance from a body of BODY_R at p to the nearest seat obstacle (negative = overlapping)
	var best := 99.0
	for ob in _obstacles_near(p):
		var a: Vector2 = ob[0]
		var b: Vector2 = ob[1]
		var ab := b - a
		var k := 0.0 if ab.length_squared() < 1e-6 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * k) - float(ob[2]) - BODY_R)
	return best


func _tile_traffic() -> Dictionary:
	var out := {}
	if trace.is_empty():
		return out
	for id in trace.characters:
		var pos: Array = trace.characters[id].pos
		for k in pos.size() / 3:
			var t := Vector2i(int(pos[k * 3 + 1]), int(pos[k * 3 + 2]))
			out[t] = int(out.get(t, 0)) + 1
	return out


func _corner_traffic() -> Dictionary:
	var out := {}
	if trace.is_empty():
		return out
	for id in trace.characters:
		var pos: Array = trace.characters[id].pos
		for k in range(1, pos.size() / 3):
			var a := Vector2i(int(pos[k * 3 - 2]), int(pos[k * 3 - 1]))
			var b := Vector2i(int(pos[k * 3 + 1]), int(pos[k * 3 + 2]))
			if absi(a.x - b.x) == 1 and absi(a.y - b.y) == 1:
				var c := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
				out[c] = int(out.get(c, 0)) + 1
	return out


## The index of the last entry with minute <= t in a flat [m, c, r, ...] array (-1 if none).
func _pos_index(pos: PackedInt32Array, t: float) -> int:
	var lo := 0
	var hi := pos.size() / 3 - 1
	var ans := -1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if float(pos[mid * 3]) <= t:
			ans = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return ans


func _state_at(st: Array, t: float) -> Array:
	var lo := 0
	var hi := st.size() - 1
	var ans := 0
	while lo <= hi:
		var mid := (lo + hi) / 2
		if float(st[mid][0]) <= t:
			ans = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return st[ans]


## In the rain the walkers hurry (docs/clima.md, «La lluvia en la gente»): along each run of steps of the trace (the
## same tiles, in the same order) the clock of the walk runs `hurry()` times faster, so they get there sooner and wait at
## the end of the run (most often a door, under its eave) until the trace has them go in. Only the view: the trace,
## --simcheck and who is where at each minute do not change.
func hurry() -> float:
	if clima == null or "--prisa=no" in OS.get_cmdline_user_args():
		return 1.0
	var r := maxf(float(clima.now.get("lluvia", 0.0)), float(clima.now.get("nieve", 0.0)) * 0.4)
	return lerpf(1.0, 1.7, clampf((r - 0.1) * 1.6, 0.0, 1.0))


func _adjacent(pos: PackedInt32Array, a: int, b: int) -> bool:
	return maxi(absi(pos[a * 3 + 1] - pos[b * 3 + 1]), absi(pos[a * 3 + 2] - pos[b * 3 + 2])) <= 1


func _walk_run(p: Dictionary, t: float) -> Vector2:
	## [start, end] minutes of the run of consecutive steps the trace has p on at minute t (x > y: not walking)
	var run: Vector2 = p.get("run", Vector2(1, 0))
	if t >= run.x and t <= run.y:
		return run
	var pos: PackedInt32Array = p.pos
	var n := pos.size() / 3
	var k := _pos_index(pos, t)
	run = Vector2(1, 0)
	if k >= 0 and k + 1 < n and _adjacent(pos, k, k + 1) and float(pos[(k + 1) * 3]) - t < mpt:
		var e := k + 1
		while e + 1 < n and float(pos[(e + 1) * 3] - pos[e * 3]) <= mpt + 0.01 and _adjacent(pos, e, e + 1):
			e += 1
		var s := k + 1
		# back while the step into s-1 is a step (adjacent tiles) and the one into s follows it without a pause
		while s - 1 >= 1 and float(pos[s * 3] - pos[(s - 1) * 3]) <= mpt + 0.01 and _adjacent(pos, s - 2, s - 1):
			s -= 1
		run = Vector2(float(pos[s * 3]) - mpt, float(pos[e * 3]))
	p.run = run
	return run


func _walk_t(p: Dictionary, t: float, h: float) -> float:
	if h <= 1.001:
		return t
	var run := _walk_run(p, t)
	if run.x > run.y:
		return t
	return minf(run.y, run.x + (t - run.x) * h)


## Tile position (fractional while walking) at minute t: a tile entered at minute m was left behind mpt minutes before.
func tile_at(p: Dictionary, t: float) -> Vector2:
	t = _walk_t(p, t, hurry())
	var pos: PackedInt32Array = p.pos
	var k := maxi(0, _pos_index(pos, t))
	var a := Vector2(pos[k * 3 + 1], pos[k * 3 + 2])
	if (k + 1) * 3 < pos.size():
		var b := Vector2(pos[k * 3 + 4], pos[k * 3 + 5])
		var left := float(pos[k * 3 + 3]) - t
		if left < mpt and maxf(absf(b.x - a.x), absf(b.y - a.y)) <= 1.0:
			return a.lerp(b, clampf(1.0 - left / mpt, 0.0, 1.0))
	return a


## Velocity on the ground at minute t, in plan metres per game minute (zero when not between two tiles).
func motion_at(p: Dictionary, t: float) -> Vector2:
	var h := hurry()
	var tw := _walk_t(p, t, h)
	if tw != t:
		var run := _walk_run(p, t)
		return Vector2.ZERO if tw >= run.y else _motion_raw(p, tw) * h
	return _motion_raw(p, t)


func _motion_raw(p: Dictionary, t: float) -> Vector2:
	var pos: PackedInt32Array = p.pos
	var k := maxi(0, _pos_index(pos, t))
	if (k + 1) * 3 >= pos.size():
		return Vector2.ZERO
	var a := Vector2(pos[k * 3 + 1], pos[k * 3 + 2])
	var b := Vector2(pos[k * 3 + 4], pos[k * 3 + 5])
	var left := float(pos[k * 3 + 3]) - t
	if left >= mpt or maxf(absf(b.x - a.x), absf(b.y - a.y)) > 1.0:
		return Vector2.ZERO
	return Vector2(b.x - a.x, -(b.y - a.y)) * 2.0 / mpt


## Real seconds per game minute at the current speed.
func real_per_game_minute() -> float:
	return 1.0 / (GAME_MIN_PER_SEC * float(SPEEDS[speed_i]))


func _apply(t: float) -> void:
	_live_buildings(t)
	if cart_trip != null:
		cart_trip.update(t)
	var inside := {}  # building -> {doing: n}
	var counts := {"calle": 0, "trabajando": 0, "durmiendo": 0, "en casa": 0, "andando": 0}
	for id in people:
		var p: Dictionary = people[id]
		var root: Node3D = p.node
		if t < float(p.first):
			root.visible = false
			continue
		var s: Array = _state_at(p.st, t)
		var loc := String(s[1])
		var doing := String(s[2])
		p.doing = doing
		p.loc = loc
		if doing in ["work", "work_out", "work_night"]:
			counts["trabajando"] += 1
		elif doing == "sleep":
			counts["durmiendo"] += 1
		elif doing == "home":
			counts["en casa"] += 1
		if loc != "":
			root.visible = false
			if loc != "~":
				if not inside.has(loc):
					inside[loc] = {}
				inside[loc][doing] = int(inside[loc].get(doing, 0)) + 1
			continue
		root.visible = true
		counts["calle"] += 1
		if doing == "walk":
			counts["andando"] += 1
		var tp := tile_at(p, t)
		var plan := _tp(tp.x, tp.y)
		var jit: Vector2 = p.jitter
		var pp := avoid(Vector2(plan.x + jit.x, plan.y - jit.y))  # round the benches, the shop counters and the cross (seat_obstacles)
		if lluvia_gente != null:
			pp = lluvia_gente.shelter(id, p, pp, t)  # standing in the rain: against the nearest wall or under a porch
		var y := ground_y(pp)  # up the ramp and over the deck of a bridge (pueblo.gd bridges)
		var newp := Vector3(pp.x, y, -pp.y)
		var mv := newp - root.position
		if Vector2(mv.x, mv.z).length() > 0.01:
			root.rotation.y = atan2(mv.x, mv.z)
		root.position = newp
		(p.icon as Label3D).text = String(ICON.get(doing, ""))
		(p.name as Label3D).visible = names_on
	for b in bld_anchor:
		var txt := ""
		if inside.has(b):
			for d in inside[b]:
				txt += "%s%d " % [String(ICON.get(d, "·")), int(inside[b][d])]
		(bld_anchor[b].label as Label3D).text = txt.strip_edges()
		var awake := 0  # a lamp at the door while someone inside is awake (or working) after dark
		if inside.has(b):
			for d in inside[b]:
				if d != "sleep":
					awake += int(inside[b][d])
		(bld_anchor[b].lamp as OmniLight3D).light_energy = (1.0 - daylight(t)) * (2.2 if awake > 0 else 0.5)
		_set_windows(bld_anchor[b].house, awake > 0 and daylight(t) < 0.65)
	_night_update(t)
	_light(t)
	_hud_text(t, counts)


func _day_info(t: float) -> Dictionary:
	var day := int(floor(t / 1440.0))
	for d in _days:
		if int(d.day) == day:
			return d
	return _days.back() if not _days.is_empty() else {"day": day, "season": "spring", "bounds": {}}


## 0 at night, 1 in full day; ramps through dawn and dusk (phase starts from the trace = data/time.json).
func daylight(t: float) -> float:
	var b: Dictionary = _day_info(t).bounds
	var md := fmod(t, 1440.0)
	var dawn := float(b.get("dawn", 300))
	var day := float(b.get("day", 420))
	var dusk := float(b.get("dusk", 1140))
	var night := float(b.get("night", 1260))
	if md < dawn or md >= night:
		return 0.0
	if md < day:
		return (md - dawn) / maxf(1.0, day - dawn)
	if md < dusk:
		return 1.0
	return 1.0 - (md - dusk) / maxf(1.0, night - dusk)


func _light(t: float) -> void:
	if luz != null:
		luz.light(t)  # scripts/clima/luz.gd (-- --luz=antes: the light below, as it was)
		if clima != null:
			clima.update(t)
		return
	if _sun == null:
		return
	var d := daylight(t)
	var md := fmod(t, 1440.0)
	var warm := clampf((1.0 - d) * 2.2, 0.0, 1.0) if d > 0.0 else 0.0  # orange through dawn and dusk
	_sun.light_energy = lerpf(0.3, 1.45, pow(d, 1.4))  # moonlight floor 0.2: the town stays readable at night
	_sun.light_color = Color(1.0, 0.94, 0.82).lerp(Color(1.0, 0.62, 0.35), warm).lerp(Color(0.55, 0.62, 0.95), 1.0 - minf(1.0, d * 3.0))
	_sun.rotation_degrees = Vector3(-lerpf(18.0, 50.0, d), -35.0 + (md / 60.0 - 13.0) * 9.0 + home_yaw - 45.0, 0)
	if _env:
		_env.ambient_light_energy = lerpf(0.55, 0.75, d)
		_env.ambient_light_color = Color(0.62, 0.7, 0.92).lerp(Color(0.36, 0.42, 0.78), 1.0 - d)
		# glow only after dusk: the lit windows and lanterns bloom (it costs, measured in sim3d_chars --bench)
		var want_glow := d < 0.5
		if _env.glow_enabled != want_glow:
			_env.glow_enabled = want_glow
			_env.glow_intensity = 0.8
			_env.glow_bloom = 0.0
			_env.glow_hdr_threshold = 1.0
			_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		_env.background_color = Color(0.55, 0.65, 0.8).lerp(Color(0.95, 0.6, 0.4), warm * 0.6).lerp(Color(0.06, 0.08, 0.16), 1.0 - d)


func _hud_text(t: float, counts: Dictionary) -> void:
	if _hud == null:
		return
	var di := _day_info(t)
	var md := int(fmod(t, 1440.0))
	var b: Dictionary = di.bounds
	var ph := "night"
	for k in ["dawn", "day", "dusk", "night"]:
		if b.has(k) and md >= int(b[k]):
			ph = k
	var follow := ""
	if follow_id != "":
		var p: Dictionary = people[follow_id]
		follow = "\nSiguiendo: %s · %s%s" % [trace.characters[follow_id].name, p.doing,
			"" if p.loc == "" else " (dentro de %s)" % trace.buildings.get(p.loc, {}).get("type", p.loc)]
	_hud.text = "Día %d · %s · %02d:%02d · %s    x%s%s\nEn la calle %d (andando %d) · trabajando %d · en casa %d · durmiendo %d%s\nEspacio pausa · [ ] velocidad · Tab seguir · F soltar · WASD mover · Q/E girar · RePág/AvPág inclinar · C corte · N nombres" % [
		int(di.day) + 1, SEASON_ES.get(di.season, di.season), md / 60, md % 60, PHASE_ES.get(ph, ph), str(SPEEDS[speed_i]).trim_suffix(".0"),
		"  (pausa)" if paused else "", counts["calle"], counts["andando"], counts["trabajando"], counts["en casa"],
		counts["durmiendo"], follow]


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# smooth zoom: the wheel (or a trackpad scroll, with its factor) moves a goal the size eases to
		var steps: float = e.factor if e.factor > 0.0 else 1.0
		_zoom_by(pow(0.88 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88, steps))
		return
	if e is InputEventMagnifyGesture:
		_zoom_by(1.0 / maxf(0.2, e.factor))  # trackpad pinch
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE: paused = not paused
			KEY_BRACKETRIGHT, KEY_EQUAL, KEY_PLUS: speed_i = mini(speed_i + 1, SPEEDS.size() - 1)
			KEY_BRACKETLEFT, KEY_MINUS: speed_i = maxi(speed_i - 1, 0)
			KEY_R: t_min = t0
			KEY_N: names_on = not names_on
			KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_Q, KEY_E, KEY_PAGEUP, KEY_PAGEDOWN:
				pass  # held keys: the camera moves in _cam_keys every frame (no jump per press)
			KEY_F: follow_id = ""
			KEY_TAB:
				var ids := people.keys()
				ids.sort()
				var i := ids.find(follow_id)
				for k in ids.size():
					var cand: String = ids[(i + 1 + k) % ids.size()]
					if (people[cand].node as Node3D).visible:
						follow_id = cand
						cam.size = minf(cam.size, 22.0)
						break
			_: super(e)
	else:
		super(e)


# ---------------------------------------------------------------- checks (headless)
## Every tile the sim walks vs the 3D town: inside a house footprint, on a tree or a prop, on water; and how far each
## sim door is from the door of the 3D house it was matched to. Prints and writes out/sim3d_check.json.
func _check() -> void:
	var foot := []  # [house, half w, half d]
	for h in houses:
		var wd: Vector2 = h.get_meta("wd")
		foot.append([h, wd.x / 2.0, wd.y / 2.0])
	var trees := []
	for n in get_tree().get_nodes_in_group("tree"):
		if n is Node3D and not n is MultiMeshInstance3D:
			trees.append(Vector2((n as Node3D).position.x, (n as Node3D).position.z))
	var props := []
	var seat_nodes := []
	for n in _q.get_children():
		if n is Node3D:
			if n.has_meta("flat"):
				continue  # crop rows: walked over
			if n.has_meta("seat"):
				seat_nodes.append(Vector2((n as Node3D).position.x, (n as Node3D).position.z))
				continue
			props.append([Vector2((n as Node3D).position.x, (n as Node3D).position.z), String(n.name)])
	var tiles := {}  # "c,r" -> visits (tile entries + half-way points between consecutive tiles)
	var samples := 0
	for id in people:
		var pos: PackedInt32Array = people[id].pos
		for k in pos.size() / 3:
			var key := "%d,%d" % [pos[k * 3 + 1], pos[k * 3 + 2]]
			tiles[key] = int(tiles.get(key, 0)) + 1
			samples += 1
	var in_house := {}
	var on_tree := {}
	var on_prop := {}
	var on_water := {}
	var mid_house := 0
	for key in tiles:
		var c := int(key.get_slice(",", 0))
		var r := int(key.get_slice(",", 1))
		var g := Vector2(c * 2.0 + 1.0, r * 2.0 + 1.0)  # godot x, z
		var hit := _house_at(foot, g, 0.0)
		if hit != "":
			in_house[key] = [tiles[key], hit, _t(c, r)]
		for tr in trees:
			if (tr as Vector2).distance_to(g) < 0.9:
				on_tree[key] = [tiles[key], _t(c, r)]
		for pr in props:
			if (pr[0] as Vector2).distance_to(g) < 0.7:
				on_prop[key] = [tiles[key], pr[1], _t(c, r)]
		if _t(c, r) == "w":
			on_water[key] = tiles[key]
	# half-way points of every step (diagonals cut corners)
	for id in people:
		var pos: PackedInt32Array = people[id].pos
		for k in range(1, pos.size() / 3):
			var a := Vector2(pos[k * 3 - 2], pos[k * 3 - 1])
			var b := Vector2(pos[k * 3 + 1], pos[k * 3 + 2])
			if maxf(absf(b.x - a.x), absf(b.y - a.y)) > 1.0:
				continue
			var m := (a + b) / 2.0
			if _house_at(foot, Vector2(m.x * 2.0 + 1.0, m.y * 2.0 + 1.0), 0.0) != "":
				mid_house += 1
	var doors := {}
	var door_max := 0.0
	var doors_far := 0
	for b in bld_anchor:
		var dm := float(bld_anchor[b].dist)
		door_max = maxf(door_max, dm)
		if dm > 2.3:
			doors_far += 1
		doors[b] = {"type": bld_anchor[b].type, "dist_m": snappedf(dm, 0.01),
			"house": String((bld_anchor[b].house as Node3D).name)}
	# the props nearest any walked tile (closest approach), and seats someone walks through without sitting there
	var prop_min := 99.0
	var prop_min_at := ""
	for key in tiles:
		var g := Vector2(int(key.get_slice(",", 0)) * 2.0 + 1.0, int(key.get_slice(",", 1)) * 2.0 + 1.0)
		for pr in props:
			var dd := (pr[0] as Vector2).distance_to(g)
			if dd < prop_min:
				prop_min = dd
				prop_min_at = "%s near tile %s" % [pr[1], key]
	# walkers past the seats: sample every step of whoever is not sitting, raw (sim tile line) and steered (avoid)
	var seat_raw := 0
	var seat_left := 0
	var steer_min := 99.0
	for id in people:
		var p: Dictionary = people[id]
		var pos: PackedInt32Array = p.pos
		for k in range(1, pos.size() / 3):
			var srow: Array = _state_at(p.st, float(pos[k * 3]) - 0.5)
			if String(srow[2]) in ["bench", "dice"] or String(srow[1]) != "":
				continue
			var a := _tp(pos[k * 3 - 2], pos[k * 3 - 1])
			var b := _tp(pos[k * 3 + 1], pos[k * 3 + 2])
			if a.distance_to(b) > 3.0:
				continue
			var jit: Vector2 = p.jitter
			var hit_raw := false
			var hit := false
			for j in 9:
				var q := a.lerp(b, j / 8.0) + Vector2(jit.x, -jit.y)
				if clearance(q) < -0.05:
					hit_raw = true
				var c := clearance(avoid(q))
				steer_min = minf(steer_min, c)
				if c < -0.05:
					hit = true
			seat_raw += int(hit_raw)
			seat_left += int(hit)
	# the pieces of PuebloVivo (lamps, benches, trees, sheds, pier...) against every step, steered as the view plays it
	var pts := []
	for id in people:
		var p: Dictionary = people[id]
		var pos: PackedInt32Array = p.pos
		var jit: Vector2 = p.jitter
		for k in range(1, pos.size() / 3):
			var a := _tp(pos[k * 3 - 2], pos[k * 3 - 1])
			var b := _tp(pos[k * 3 + 1], pos[k * 3 + 2])
			if a.distance_to(b) > 3.0:
				continue
			for j in 9:
				pts.append(avoid(a.lerp(b, j / 8.0) + Vector2(jit.x, -jit.y)))
	var vivo_rep: Dictionary = vivo.check(pts) if vivo != null and vivo.on() else {}
	var rep := {"vivo": vivo_rep, "people": people.size(), "tile_entries": samples, "distinct_tiles": tiles.size(),
		"tiles_inside_house": in_house, "tiles_on_tree": on_tree, "tiles_on_prop": on_prop, "tiles_on_water": on_water,
		"half_steps_inside_house": mid_house, "doors": doors, "door_max_m": snappedf(door_max, 0.01),
		"doors_over_2_3m": doors_far, "houses_3d": houses.size(), "props": props.size(), "prop_nearest_walked_m":
		snappedf(prop_min, 0.01), "prop_nearest": prop_min_at, "prop_stats": prop_stats, "seats": seats.size(), "steps_through_a_seat_raw": seat_raw, "steps_through_a_seat_steered": seat_left,
		"steered_min_clearance_m": snappedf(steer_min, 0.01),
		"yard_tiles": yard_tiles.size()}
	var f := FileAccess.open("res://out/sim3d_check.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	print("[Sim3D] check: %d tile entries on %d tiles; inside a 3D house %d tiles; on a tree %d; on a prop %d; on water %d; half-steps inside a house %d" % [
		samples, tiles.size(), in_house.size(), on_tree.size(), on_prop.size(), on_water.size(), mid_house])
	for b in doors:
		print("[Sim3D]   door %s (%s): %.2f m from the 3D door of %s" % [b, doors[b].type, doors[b].dist_m, doors[b].house])
	print("[Sim3D] check: doors max %.2f m (%d over 2.3 m); %d props, nearest to a walked tile %.2f m; props %s; %d seats; steps through a seat: %d raw, %d steered (min clearance %.2f m)" % [
		door_max, doors_far, props.size(), prop_min, prop_stats, seats.size(), seat_raw, seat_left, steer_min])
	if not vivo_rep.is_empty():
		print("[Sim3D] check: %d pieces of PuebloVivo against %d points of the steps: inside a piece %s; nearest %.2f m (%s); %s" % [
			vivo_rep.pieces, vivo_rep.points, vivo_rep.inside_a_piece, vivo_rep.nearest_m, vivo_rep.nearest, vivo_rep.stats])
	var us := Time.get_ticks_usec()
	var n := 0
	var t := t0
	while t < t1:
		_apply(t)
		t += 7.3
		n += 1
	print("[Sim3D] _apply: %.1f us per frame (%d frames over the whole trace, %d people)" % [
		float(Time.get_ticks_usec() - us) / n, n, people.size()])


func _house_at(foot: Array, g: Vector2, margin: float) -> String:
	for fh in foot:
		var h: Node3D = fh[0]
		var local := h.transform.affine_inverse() * Vector3(g.x, 0.5, g.y)
		if absf(local.x) < float(fh[1]) - margin and absf(local.z) < float(fh[2]) - margin:
			return String(h.name)
	return ""


# ---------------------------------------------------------------- screenshots
func _sim_shots() -> void:
	var day0 := _day_start(t0)
	# [file, minute of day 1, camera target, ortho size, yaw]
	var plaza := HouseBuilder.plan_to_godot(Vector3(_tp(19.5, 18.5).x, _tp(19.5, 18.5).y, 2))
	var shots := [
		["sim3d_0830_plaza.png", 8 * 60 + 30, plaza, 26.0, home_yaw],
		["sim3d_1230_pueblo.png", 12 * 60 + 30, Vector3(W, 2, H), 66.0, home_yaw],
		["sim3d_1230_forja_campos.png", 12 * 60 + 30, HouseBuilder.plan_to_godot(Vector3(_tp(14, 24).x, _tp(14, 24).y, 1)), 30.0, home_yaw],
		["sim3d_2015_atardecer.png", 20 * 60 + 15, plaza, 30.0, home_yaw],
		["sim3d_2300_noche.png", 23 * 60, plaza, 40.0, home_yaw]]
	for s in shots:
		var t: float = day0 + float(s[1])
		if t < t0:
			t += 1440.0
		target = s[2]
		cam.size = s[3]
		yaw = s[4]
		_update_camera()
		_apply(t)
		await _snap(s[0])
	get_tree().quit()
