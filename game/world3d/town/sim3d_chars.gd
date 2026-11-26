extends "res://game/world3d/town/sim3d.gd"
## The vertical slice: the GuildMaster sim trace (tools/sim_trace.gd v2) over the 3D town with CharBuilder townsfolk.
## - Look from the data: outfit by occupation / profession / family role, the family colour on the main fabric, the
##   sim's skin and hair tones, the age (CharBuilder `age`).
## - Feet planted: the sim moves everyone one tile per minutes_per_tile, so the view picks the gait (Walk / Jog / Sprint)
##   from the real ground speed and plays it at the rate that covers that speed with this body's stride.
## - Seats: who the trace has on a bench or dice slot sits on the bench / stool pueblo.gd put there (Sitting_*), facing
##   the group; chats stand facing the partner. Walkers are steered round the seats (sim3d.gd avoid()).
## - Every house with an interior in place lives (docs/interior3d.md, «Interior en sitio»; pueblo.gd gives the houses
##   their meta "interior"): F, a click on a house or zooming in on it opens it where it stands: the roof melts, the
##   walls that face the camera drop (SituCut) and the inside (interior3d.gd in place, data/interiors/<type>_sitio_n<level>.json)
##   shows who the trace has in that building, each at its place (SituLive); the street goes on around it. One house
##   open at a time. Tab: upper floor; Esc / F or zooming out: the roof comes back. `--abrir[=<names>]`: every house
##   opened in turn, pictures and cost (out/p3b_abrir.json).
##   `--interior=grande`: the old separate interior of 20 x 16 m (fade to black and back). `--sitio=demo`: the four
##   scripted people (smith, hand, shopkeeper, customers who come along the street) instead of the sim's.
## Run:  godot --path . res://sim3d_chars.tscn [-- --at=HH:MM] [--speed=0.25] [--simshots] [--bench] [--situshots]
## Keys: as sim3d (x0.25 default here) · F / click the forge: open it · Esc: close

const InteriorScene := preload("res://game/world3d/interior/interior3d.gd")
const SituLive := preload("res://game/world3d/interior/situ_live.gd")
const FAR := Vector3(3000, 0, 3000)
const SHOTS_DIR := "/Users/miguelmolledo/.grimoire/workspace/channels/ch_01m6abhw3phgxh2509d0/files/prueba3d/"
const CLIP := {"Walk": 1.02, "Jog_Fwd": 2.68, "Sprint": 3.52}  # m/s at scale 1 (tools/anim_speed.gd)
const MAX_RATE := 2.6  # fastest playback of a locomotion clip; above it (x10 and up) the feet slide
const SKIN_BY_SIM := ["fair", "olive", "tan", "brown", "pale", "tan"]  # GuildMaster data/view.json palette.skin
const HAIR_BY_SIM := ["black", "dark", "brown", "blond", "auburn", "white", "dark", "chestnut", "chestnut", "blond"]
const RANGER := {torso = "ranger", arms = "ranger", legs = "ranger", feet = "ranger"}
const PEASANT := {torso = "peasant", arms = "peasant", legs = "peasant", feet = "peasant"}

## doing -> animation when standing still
const STILL_ANIM := {"work": "Fixing_Kneeling", "work_out": "Fixing_Kneeling", "work_night": "Fixing_Kneeling",
	"chat": "Idle_Talking", "greet": "Idle_Talking", "court": "Idle_Talking", "guard_greet": "Idle_Talking",
	"social": "Idle_Talking", "shopping": "Interact", "market": "Interact", "visit_merchant": "Interact",
	"errand": "PickUp_Table", "water": "PickUp_Table", "wash": "Fixing_Kneeling", "guard_post": "Sword_Idle",
	"guard_patrol": "Sword_Idle", "guard_respond": "Sword_Idle", "brawl": "Punch_Jab", "dice": "Idle_Talking",
	"bench": "Idle", "watch_fight": "Idle", "watch_show": "Idle", "leisure": "Idle_Talking", "mass": "Idle"}
const TALK := ["chat", "greet", "court", "guard_greet", "social", "leisure", "dice", "bench"]
## occupation prefix -> [look, still animation at work]
const JOBS := {"gate": ["guard", "Sword_Idle"], "armory": ["guard", "Sword_Idle"], "field": ["farmer", "hoe|Fixing_Kneeling"],
	"stall": ["merchant", "Interact"], "well": ["water", "PickUp_Table"], "river": ["water", "Fixing_Kneeling"],
	"church": ["clergy", "Idle"], "townhall": ["clerk", "Idle_Talking"]}

var _chr := {}  # id -> {node, ap, def, yaw, v, anim, rate}
var _own_api := -1  # 1: CharBuilder.play / anim_name exist (own animations of tools/make_anims.gd)
var _last_us := 0
var gait_stats := {"frames": 0, "moving": 0, "slide": 0, "rate_max": 0.0, "by_gait": {}, "by_age": {}}

var inside_view: Node3D
var inside := false
var live_bld := ""
var _busy := false
var _fade: ColorRect
var _hint: Label
var _back := {}
var _inside_night := -1
var situ_mode := false   # the houses have their interior in place (they carry meta "interior": pueblo.gd)
var situ_cut: SituCut
var situ_house: Node3D   # the house whose interior is mounted (one at a time; the player's forge from the start)
var transition_k := 1.0  # GuildMaster: length of a house's opening and closing (1 = Prueba3D's; flows may shorten it)
var use_sound := true  # GuildMaster: the town's own sound system (off in the game until it goes through AudioDirector)
var mount_stats := {}    # house name -> ms of mounting its interior (SituShell.open)
var _at_place := false       # opening a house: who is already inside appears at its place
var _focus_auto := false  # opened by zooming in (no camera move, closes by zooming out)
var _cut_yaw := -999.0
var _forge_label: Label3D
const FOCUS_ZOOM := 10.5    # zooming in to this size over the house opens it
const UNFOCUS_ZOOM := 17.0  # ... and zooming out past this closes it again
const FOCUS_SIZE := 13.0    # the camera size F / a click goes to


func _init() -> void:
	speed_i = 0  # x0.25: a straight step is 1.2 m/s, people walk


# ---------------------------------------------------------------- townsfolk
func _spawn_people() -> void:
	super()
	if OS.is_debug_build():
		print("[Sim3DChars] %d townsfolk built" % _chr.size())


## GuildMaster: the CharBuilder body of one person (also for people who appear while the game runs).
func _spawn_person(id: String, skin: StandardMaterial3D = null, head_mesh: SphereMesh = null) -> void:
	super(id, skin, head_mesh)
	if true:
		var p: Dictionary = people[id]
		var root: Node3D = p.node
		for c in root.get_children():
			if c is MeshInstance3D:
				c.free()
		var c: Dictionary = trace.characters[id]
		var d := _def_for(String(id), c)
		var ch := CharBuilder.build(d)
		root.add_child(ch)
		_chr[id] = {node = ch, ap = ch.get_node("AnimationPlayer"), def = d, yaw = 0.0, v = 0.0, anim = "Idle",
			rate = 1.0, last = Vector3.INF}
		(p.name as Label3D).position.y = 2.15
		(p.icon as Label3D).position.y = 2.85


func on_far_zoom(far: bool) -> void:
	## opt3d "far" (whole-town view): the townsfolk stop casting shadows (2.8 ms at 1600x900, out/fpsprof_v2.json)
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if far else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for id in _chr:
		for gi in (_chr[id].node as Node).find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).cast_shadow = mode
	if OS.is_debug_build():
		print("[Sim3DChars] far zoom %s: townsfolk shadows %s" % [far, "off" if far else "on"])


func _def_for(id: String, c: Dictionary) -> Dictionary:
	var h := absi(hash(id))
	var female: bool = String(c.get("sex", "f" if c.get("female", false) else "m")) == "f"
	var fam: Dictionary = trace.families.get(c.family, {})
	var dye := _nearest_dye(Color.from_string(String(fam.get("color", "#808080")), Color.GRAY))
	var occ := String(c.get("occupation", ""))
	var prof := String(c.get("profession", ""))
	var vis: Dictionary = c.get("visual", {}) if c.get("visual") is Dictionary else {}
	var job := ""
	var job_anim := ""
	for k in JOBS:
		if occ.begins_with(k):
			job = JOBS[k][0]
			job_anim = JOBS[k][1]
	if String(c.family) == "fam_watch":
		job = "guard"
		job_anim = "Sword_Idle"
	elif String(c.family) == "fam_visitors":
		job = "traveller"
	elif job == "" and occ == "" and String(c.get("family_role", "")) == "head":
		job = {"blacksmith": "smith", "carpenter": "carpenter", "mason": "mason", "tailor": "tailor"}.get(prof, "")
	var skin: String = SKIN_BY_SIM[int(vis.skin) % SKIN_BY_SIM.size()] if vis.has("skin") else ["fair", "olive", "tan"][h % 3]
	# the palette's aged tone (the white) is drawn with the natural one, as in 2D (Identity.natural_hair): a girl of 8
	# never has white hair; the grey of the old comes from the age (CharAge)
	var hair: String = HAIR_BY_SIM[Identity.natural_hair(int(vis.hair)) % HAIR_BY_SIM.size()] if vis.has("hair") \
		else ["dark", "brown"][h % 2]
	var parts: Dictionary = PEASANT.duplicate()
	parts.hair = (["hair_long", "hair_buns", "hair_buzzed_f"] if female else ["hair_parted", "hair_buzzed", "hair_parted"])[(h / 3) % 3]
	if not female and (h / 11) % 3 == 0:
		parts.beard = "beard"
	var paint := {"skin": skin, "hair": hair, "*": {"tex": "peasant" if (h / 5) % 2 == 0 else "peasant2"}, "torso": dye, "arms": dye}
	match job:
		"guard":
			parts = RANGER.duplicate()
			parts.hair = "hair_buzzed" if not female else "hair_buns"
			parts.acc = ["pauldron", "bracers"]
			paint.merge({"*": {}, "torso": dye, "arms": dye, "legs": "pardo"}, true)
		"merchant", "clerk", "tailor":
			parts.merge({torso = "ranger", arms = "ranger"}, true)
			paint.merge({torso = {tex = "ranger3", a = "crudo", b = dye}, arms = {tex = "ranger3", a = "crudo", b = dye}}, true)
		"traveller":
			# visitors: the dress colours the sim gives them
			var dr: Dictionary = vis.get("dress", {})
			var a := _nearest_dye(Color.from_string(String(dr.get("primary", "#6a5a4a")), Color.GRAY))
			var b := _nearest_dye(Color.from_string(String(dr.get("secondary", "#c8b890")), Color.GRAY))
			parts = RANGER.duplicate()
			parts.hair = "hair_long" if female else "hair_parted"
			paint.merge({"*": {}, "torso": [a, b], "arms": [a, b], "legs": ["", b]}, true)
		"clergy":
			parts = RANGER.duplicate()
			parts.feet = "peasant"
			parts.acc = ["hood"]
			paint.merge({"*": {"tex": "ranger3"}, "torso": ["gris", "negro"], "arms": ["gris", "negro"], "legs": ["", "negro"],
				("hood_ranger_f" if female else "hood_ranger_m"): ["", "negro"], "feet": {"tex": "peasant"}}, true)
		"smith", "carpenter", "mason":
			parts.acc = ["apron"]
			var work_dye: String = {"smith": "gris", "carpenter": "pardo", "mason": "crudo"}[job]
			paint.merge({torso = [work_dye, "negro"], arms = work_dye}, true)
		"farmer":
			paint.merge({legs = "pardo"}, true)
	var d := {name = String(c.name), sex = "f" if female else "m", parts = parts, paint = paint, seed = h % 1000,
		height = 0.96 + float((h / 13) % 9) / 100.0, anim = "Idle"}
	if c.has("age"):
		d.age = int(c.age)
	d.job_anim = job_anim
	if OS.is_debug_build():
		print("[Sim3DChars] %s %s (%s, %d): job=%s skin=%s hair=%s dye=%s" % [id, c.name, d.sex, int(c.get("age", -1)),
			job if job != "" else "-", skin, hair, dye])
	return d


static func _nearest_dye(col: Color) -> String:
	## the family colour (sim palette) -> the closest muted dye of CharBuilder
	if col.s < 0.15:
		return "gris" if col.v > 0.3 else "negro"
	var best := "pardo"
	var bd := 9.0
	CharBuilder.load_data()
	for n in CharBuilder.pal.dyes:
		var dy: Array = CharBuilder.pal.dyes[n]
		if dy[0] < 0:
			continue
		var dh := absf(fposmod(col.h * 360.0 - dy[0] + 180.0, 360.0) - 180.0) / 180.0
		var dv := absf(col.v * 0.6 - dy[2])
		var d := dh * 2.0 + dv
		if d < bd:
			bd = d
			best = n
	return best


# ---------------------------------------------------------------- per frame
func _apply(t: float) -> void:
	super(t)
	var now := Time.get_ticks_usec()
	var dt := clampf(float(now - _last_us) / 1e6, 0.0, 0.1) if _last_us > 0 else 0.0
	_last_us = now
	var rpm := real_per_game_minute()
	var sitters := {}  # social point id -> sitters, for Sitting_Talking
	for id in _chr:
		var p: Dictionary = people[id]
		if (p.node as Node3D).visible and String(p.doing) in ["bench", "dice"]:
			var row: Array = _state_at(p.st, t)
			var pid := String(row[5]).get_slice("|", 0) if row.size() > 5 else ""
			sitters[pid] = int(sitters.get(pid, 0)) + 1
	for id in _chr:
		var p: Dictionary = people[id]
		var root: Node3D = p.node
		if inside and situ_mode and (inside_view.live_actors.has(id) or (live_bld != "" and String(p.loc) == live_bld)):
			root.visible = false  # in the open house (or still walking out of it): one body, the one of the inside
		if not root.visible:
			continue
		# by an open house the name of who stands in the street is not cut by its lowered walls
		var by_open: bool = inside and situ_mode and Vector2(root.position.x - situ_house.position.x, root.position.z - situ_house.position.z).length() < 9.0
		if (p.name as Label3D).no_depth_test != by_open:
			(p.name as Label3D).no_depth_test = by_open
		var e: Dictionary = _chr[id]
		var ch: Node3D = e.node
		var k := ch.scale.x
		var stride := float(ch.get_meta("stride", k))
		var doing := String(p.doing)
		var row: Array = _state_at(p.st, t)
		var spot := String(row[5]) if row.size() > 5 else ""
		var vel := motion_at(p, t)  # plan m per game minute
		var v := 0.0 if paused else vel.length() / rpm  # m per real second
		var jumped: bool = e.last == Vector3.INF or (root.position - e.last).length() > 4.0 or dt == 0.0
		e.last = root.position
		var anim := "Idle"
		var rate := float(ch.get_meta("base_speed", 1.0))
		var yaw: float = e.yaw
		var seat: Dictionary = seats.get(spot, {}) if doing in ["bench", "dice"] and vel == Vector2.ZERO else {}
		if not seat.is_empty():
			# on the seat: pelvis over the seat (0.33 m behind the root). The own sit_stool pose sits on 0.59 m with
			# the root on the floor; the library Sitting_* sit at 0.44 m, so the root goes up to the seat.
			var dir: Vector2 = seat.dir
			var sp: Vector2 = seat.pos + dir * 0.33 * k
			yaw = atan2(dir.x, -dir.y)
			if _has_anim(e, "sit_stool"):
				anim = "sit_stool"
				root.position = Vector3(sp.x, 0.0, -sp.y)
			else:
				anim = "Sitting_Talking" if int(sitters.get(spot.get_slice("|", 0), 0)) > 1 else "Sitting_Idle"
				root.position = Vector3(sp.x, float(seat.top) - 0.44 * k, -sp.y)
			jumped = true
		elif vel != Vector2.ZERO:
			e.v = v if jumped else lerpf(e.v, v, 1.0 - exp(-dt * 4.0))
			var g := "Walk"
			if e.v > 3.3 * stride:
				g = "Sprint"
			elif e.v > 1.9 * stride:
				g = "Jog_Fwd"
			anim = g
			rate = v / (CLIP[g] * stride)
			gait_stats.moving += 1
			gait_stats.by_gait[g] = int(gait_stats.by_gait.get(g, 0)) + 1
			if rate > MAX_RATE:
				gait_stats.slide += 1
				rate = MAX_RATE
			gait_stats.rate_max = maxf(gait_stats.rate_max, rate)
			# per life stage (kit.ages.stages): a child's or an elder's stride is not an adult's
			var band := String(CharBuilder.age_stage(e.def).get("name", "adult")) if e.def.has("age") else "adult"
			var ba: Dictionary = gait_stats.by_age.get(band, {"moving": 0, "slide": 0, "rate_max": 0.0, "stride": stride})
			ba.moving += 1
			if v / (CLIP[g] * stride) > MAX_RATE:
				ba.slide += 1
			ba.rate_max = maxf(float(ba.rate_max), rate)
			gait_stats.by_age[band] = ba
			yaw = atan2(vel.x, -vel.y)
		else:
			e.v = 0.0
			anim = String(STILL_ANIM.get(doing, "Idle"))
			if doing in ["work", "work_out"] and String(e.def.job_anim) != "":
				anim = String(e.def.job_anim)
				if anim.contains("|"):  # "own|fallback": the own animation when this checkout has it
					anim = anim.get_slice("|", 0) if _has_anim(e, anim.get_slice("|", 0)) else anim.get_slice("|", 1)
			if doing in TALK:
				var mate := _talk_mate(id, root.position)
				if mate != Vector3.INF:
					yaw = atan2(mate.x - root.position.x, mate.z - root.position.z)
		gait_stats.frames += 1
		e.yaw = yaw if jumped else lerp_angle(float(e.yaw), yaw, 1.0 - exp(-dt * 10.0))
		root.rotation.y = e.yaw
		var ap: AnimationPlayer = e.ap
		# on an errand (📦) the sim has them carrying: CharBuilder's carry_box layer over the walk or the idle
		var carry := "box" if doing == "errand" and anim in ["Walk", "Jog_Fwd", "Sprint", "Idle", "PickUp_Table"] and _has_anim(e, "carry_box") else ""
		if carry != "" and anim == "PickUp_Table":
			anim = "Idle"  # standing on the errand with the crate in the arms
		if anim != e.anim or carry != String(e.get("carry", "")):
			e.anim = anim
			e.carry = carry
			_play_anim(e, anim, 0.0 if jumped else 0.25, carry)
		elif carry == "" and not ap.is_playing():
			_play_anim(e, anim, 0.0)  # the library clips do not loop
		if carry != "":
			var tree: AnimationTree = (e.node as Node).get_node_or_null("AnimationTree")
			if tree:
				tree.set("parameters/speed/scale", rate)
		else:
			ap.speed_scale = rate
	if inside_view:
		_sync_inside(t)
		if inside and situ_mode:
			# the cut follows the camera: which walls face it, which floor is in view
			situ_cut.update(_cut_dir(), inside_view.top)
			if yaw != _cut_yaw:
				_cut_yaw = yaw
				inside_view._apply_cut()


func _own() -> bool:
	if _own_api < 0:
		_own_api = 0
		for m in (CharBuilder as Script).get_script_method_list():
			if String(m.name) == "play":
				_own_api = 1
	return _own_api == 1


func _has_anim(e: Dictionary, anim: String) -> bool:
	if not _own():
		return (e.ap as AnimationPlayer).has_animation(anim)
	return String((CharBuilder as Script).call("anim_name", e.ap, anim)) != ""


func _play_anim(e: Dictionary, anim: String, fade: float, carry := "") -> void:
	## CharBuilder.play when it exists (own animations bring and take away their items: hoe, hammer...), else the player
	if _own():
		(CharBuilder as Script).call("play", e.node, anim, carry, fade)
		if carry != "":
			# in the AnimationTree the library clips (no loop of their own) must loop, like the player replays them
			var tree: AnimationTree = (e.node as Node).get_node_or_null("AnimationTree")
			if tree:
				var bt := tree.tree_root as AnimationNodeBlendTree
				for nn in ["lower", "upper"]:
					var an := bt.get_node(nn) as AnimationNodeAnimation
					an.use_custom_timeline = true
					an.stretch_time_scale = false
					an.timeline_length = (e.ap as AnimationPlayer).get_animation(an.animation).length
					an.loop_mode = Animation.LOOP_LINEAR
	else:
		(e.ap as AnimationPlayer).play(anim, fade)


func _talk_mate(id: String, at: Vector3) -> Vector3:
	## the nearest visible person talking within 3 m (to face), INF if none
	var best := Vector3.INF
	var bd := 3.0
	for o in people:
		if o == id:
			continue
		var q: Dictionary = people[o]
		if not (q.node as Node3D).visible or String(q.doing) not in TALK:
			continue
		var d := ((q.node as Node3D).position - at).length()
		if d < bd and d > 0.2:
			bd = d
			best = (q.node as Node3D).position
	return best


# ---------------------------------------------------------------- the forge from inside
func _make_hud() -> void:
	super()
	if "--simcheck" in OS.get_cmdline_user_args():
		return
	live_bld = _player_forge()
	var first: Node3D = bld_anchor[live_bld].house if live_bld != "" else null
	if (first == null or not first.has_meta("interior")) and not "--interior=grande" in OS.get_cmdline_user_args():
		for h in houses:  # no forge of the player with an interior in place: any house that has one
			if h.has_meta("interior") and (first == null or not first.has_meta("interior")):
				first = h
	if first == null:
		return
	situ_mode = first.has_meta("interior")
	if situ_mode:
		# in place: the inside is a child of its house; the cut works on the house's own pieces. The player's forge is
		# mounted from the start; any other house is mounted when it is opened (_mount)
		_mount(first)
	else:
		situ_house = first
		inside_view = InteriorScene.new()
		inside_view.embedded = true
		inside_view.live = not ("--sitio=demo" in OS.get_cmdline_user_args() or "--sitio=aforo" in OS.get_cmdline_user_args())
		inside_view.position = FAR
		add_child(inside_view)
		inside_view.setup()
		inside_view.exit_requested.connect(leave)
		if inside_view.live:
			inside_view.live_label(true)
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_fade)
	_hint = Label.new()
	_hint.position = Vector2(18, 16)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(18, get_viewport().get_visible_rect().size.y - 34)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.text = "F, clic o acercar el zoom sobre una casa: abrirla" if situ_mode else "F o clic en la herrería: entrar"
	ui.add_child(_hint)
	var lab := _label3d("Herrería", 90, Color(1, 0.9, 0.6))
	_forge_label = lab
	lab.visible = live_bld != "" and String(trace.buildings[live_bld].type) == "forge"
	lab.position = first.position + Vector3(0, float(first.get_meta("top", 7.0)) + 1.4, 0)
	add_child(lab)
	if OS.is_debug_build():
		var n := 0
		for h in houses:
			n += int(h.has_meta("interior"))
		print("[Sim3DChars] %d houses with an interior in place; mounted: %s (sim building %s)" % [n, first.name, live_bld if live_bld != "" else "-"])


func _before_rehouse(h: Node3D) -> void:
	## the sim builds this house again (a level more, the next stage of its works): if it is the one mounted, it closes
	## at once and its interior goes with the old house
	if situ_house != h or inside_view == null or not situ_mode:
		return
	if inside:
		inside_view.activate(false)
		inside = false
		_hint.visible = true
		_forge_label.visible = bool(_forge_label.get_meta("was", true))
		for b in bld_anchor:
			if bld_anchor[b].house == h:
				(bld_anchor[b].label as Label3D).visible = true
	_unmount()
	situ_house = null
	live_bld = ""


func _bld_of(house: Node3D) -> String:
	## the sim building that lives in a house of the town ("" for a house the sim has nobody in)
	for b in bld_anchor:
		if bld_anchor[b].house == house and trace.buildings.has(b) and (trace.buildings[b] as Dictionary).has("tl"):
			return b
	for b in bld_anchor:
		if bld_anchor[b].house == house:
			return b
	return ""


func _upgrades_at(b: String, t: float) -> Array:
	## the finished upgrades the trace has for a building at minute t
	var ups := []
	for r in (trace.buildings.get(b, {}) as Dictionary).get("tl", []):
		if float(r[0]) <= t or ups.is_empty():
			ups = r[2] if (r as Array).size() > 2 else []
	return ups


func _mount(house: Node3D) -> void:
	## the interior in place of a house and the cut that opens it (SituShell.open), closed. One at a time: the one
	## mounted before goes. People: the sim's (SituLive), or with --sitio=demo the data's own cast.
	if inside_view != null and situ_house == house:
		return
	situ_mode = true
	_unmount()
	situ_house = house
	live_bld = _bld_of(house)
	var args := OS.get_cmdline_user_args()
	var o := SituShell.open(house, self, {"live": not ("--sitio=demo" in args or "--sitio=aforo" in args),
		"keep_visible": "--sitio=visto" in args, "upgrades": _upgrades_at(live_bld, t_min)})
	inside_view = o.view
	situ_cut = o.cut
	mount_stats[String(house.name)] = float(o.ms)
	_inside_night = -1
	if inside_view.live:
		inside_view.live_label(true)
	if OS.is_debug_build():
		print("[Sim3DChars] interior in place of %s (%s, sim building %s) mounted in %.0f ms" % [house.name,
			String(house.get_meta("interior")).get_file(), live_bld if live_bld != "" else "-", float(o.ms)])


func _unmount() -> void:
	if inside_view == null or not situ_mode:
		return
	if situ_cut != null:
		situ_cut.set_on(false, true)  # the house whole again before its cut goes
		situ_cut.queue_free()
	if inside_view.live:
		inside_view.live_clear()
	inside_view.queue_free()
	inside_view = null
	situ_cut = null


func _house_near(at: Vector3, reach: float) -> Node3D:
	## the house with an interior in place whose footprint is nearest to a ground point, within `reach` m of its walls
	var best: Node3D = null
	var bd := reach
	for h in houses:
		if not h.has_meta("interior"):
			continue
		var wd: Vector2 = h.get_meta("wd")
		var loc := h.global_transform.affine_inverse() * Vector3(at.x, h.global_position.y, at.z)
		var d := Vector2(maxf(absf(loc.x) - wd.x / 2.0, 0.0), maxf(absf(loc.z) - wd.y / 2.0, 0.0)).length()
		if d < bd:
			bd = d
			best = h
	return best


func _player_forge() -> String:
	## the forge of the player's family (families.controlled_by == "player"), else the first forge
	var first := ""
	for b in trace.buildings:
		var bd: Dictionary = trace.buildings[b]
		if bd.type != "forge" or not bld_anchor.has(b):
			continue
		if first == "":
			first = b
		if String(trace.families.get(bd.owner, {}).get("controlled_by", "")) == "player":
			return b
	return first


func _sync_inside(t: float) -> void:
	if not inside:
		return
	var roster := {}
	for id in people:
		var p: Dictionary = people[id]
		if live_bld == "" or t < float(p.first) or String(p.loc) != live_bld:
			continue
		var row: Array = _state_at(p.st, t)
		roster[id] = {def = _chr[id].def, name = String(trace.characters[id].name), station = String(row[4]) if row.size() > 4 else "",
			doing = String(row[2])}
	_roster_extra(roster)
	if inside_view.live:
		if situ_mode:
			SituLive.sync(inside_view, roster, _at_place)  # any building: its stations, seats and beds (scripts/situ_live.gd)
		else:
			inside_view.live_snap = _at_place
			inside_view.live_sync(roster)
			inside_view.live_snap = false
	var n := 1 if daylight(t) < 0.35 else 0
	if n != _inside_night:
		_inside_night = n
		inside_view.set_night(n == 1)


## The game's people inside that are not townsfolk of the trace (the guests of a tavern): added by Town3D.
func _roster_extra(_roster: Dictionary) -> void:
	pass


func _process(delta: float) -> void:
	super(delta)
	if not situ_mode or _busy or _scripted():
		return
	# zooming in over a house opens it, zooming out (or panning away) closes it
	if not inside:
		if cam.size <= FOCUS_ZOOM:
			var h := _house_near(target, 1.0)
			if h != null:
				enter(true, h)
		return
	var fp := situ_house.global_position
	var off := Vector2(target.x - fp.x, target.z - fp.z).length()
	if cam.size > (UNFOCUS_ZOOM if _focus_auto else 30.0) or off > (8.0 if _focus_auto else 16.0):
		leave()


func _scripted() -> bool:
	## a run that drives the camera itself (pictures, measures): no opening by zoom
	for a in OS.get_cmdline_user_args():
		if a in ["--simshots", "--situshots", "--bench", "--dcprof"] or a.begins_with("--vistas=") or a.begins_with("--abrir") or a.begins_with("--obrashots"):
			return true
	return false


func _cut_dir() -> Vector2:
	## plan direction from the house towards the camera, in the house's own frame (as main.gd set_cutaway)
	return Vector2(sin(deg_to_rad(yaw)), -cos(deg_to_rad(yaw))).rotated(-situ_house.rotation.y)


func front_yaw(h: Node3D, from: float) -> float:
	## the camera yaw nearest `from`, among the four diagonals, that looks at the front of house h (its door wall is
	## one of the two walls the cut lowers)
	var best := from
	var bd := 999.0
	for k in 4:
		var y := 45.0 + 90.0 * k
		var dir := Vector2(sin(deg_to_rad(y)), -cos(deg_to_rad(y))).rotated(-h.rotation.y)
		if dir.dot(Vector2(0, -1)) < 0.1:
			continue
		var dy := absf(fposmod(y - from + 180.0, 360.0) - 180.0)
		if dy < bd:
			bd = dy
			best = from + fposmod(y - from + 180.0, 360.0) - 180.0
	return best


func clear_front_yaw(h: Node3D, from: float) -> float:
	## front_yaw, but of the four diagonals the one whose line of sight from house h up to the camera crosses the least
	## of other houses (a tall neighbour in front hides the open house). Those that look at its front count as they are;
	## the other two (the cut lowers its back walls) count 2 m more. Ties: the nearest to `from`.
	var best := front_yaw(h, from)
	var score := 1e9
	var log := []
	for k in 4:
		var y := 45.0 + 90.0 * k
		var dir := Vector2(sin(deg_to_rad(y)), -cos(deg_to_rad(y))).rotated(-h.rotation.y)
		var yy := from + fposmod(y - from + 180.0, 360.0) - 180.0
		var hid := _hidden_by(h, yy) + (0.0 if dir.dot(Vector2(0, -1)) >= 0.1 else 2.0)
		log.append("%.0f: %.1f m" % [y, hid])
		var sc := hid + absf(yy - from) / 1000.0
		if sc < score:
			score = sc
			best = yy
	if OS.is_debug_build():
		print("[Sim3DChars] %s: sight line inside other houses by yaw (back walls +2) %s -> %.0f" % [h.name, ", ".join(log), fposmod(best, 360.0)])
	return best


func _hidden_by(h: Node3D, y: float) -> float:
	## metres of the sight line, from the middle of house h to a camera at yaw y, that run inside other houses
	var dirv := Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(y), 0)).z
	var start := h.global_position + Vector3(0, 1.2, 0)
	var total := 0.0
	for o in houses:
		if o == h or not is_instance_valid(o) or not o.has_meta("wd"):
			continue
		if o.global_position.distance_to(h.global_position) > 30.0:
			continue
		var wd: Vector2 = o.get_meta("wd")
		var top := float(o.get_meta("top", 7.0)) + 2.5
		var inv := o.global_transform.affine_inverse()
		for i in 60:
			var p: Vector3 = inv * (start + dirv * (0.5 * i))
			if absf(p.x) < wd.x / 2.0 + 0.3 and absf(p.z) < wd.y / 2.0 + 0.3 and p.y > 0.0 and p.y < top:
				total += 0.5
	return total


func _set_windows(h: Node3D, on: bool) -> void:
	if inside and situ_mode and h == situ_house:
		return  # open: its pieces are drawn by the cut, and the inside shows who is awake
	super(h, on)


func _turn(deg: float) -> void:
	## Q / E with the house open: a quarter turn, eased (the cut follows the camera)
	_busy = true
	var y0 := yaw
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(k: float):
		yaw = y0 + deg * k
		_update_camera(), 0.0, 1.0, 0.45)
	await tw.finished
	_busy = false


func _cam_free() -> bool:
	## held-key camera (sim3d.gd): off while a house opens or closes (a tween drives the camera) and in the old
	## separate interior (it has its own camera); on with a house open in place
	return not _busy and not (inside and not situ_mode)


func _unhandled_input(e: InputEvent) -> void:
	if situ_mode and inside and not _busy:
		# the house is open in place: the town keeps all its keys (held WASD / Q-E move the camera smoothly); Esc / F close it
		if e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_ESCAPE, KEY_F]:
			leave()
			get_viewport().set_input_as_handled()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _house_under(e.position) not in [null, situ_house]:
			_switch(_house_under(e.position))  # a click on another house: this one closes, that one opens
			get_viewport().set_input_as_handled()
		else:
			super(e)
		return
	if inside or _busy:
		# inside: only the clock keys reach the town (the interior handles its own keys and Esc / F)
		if e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_SPACE, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_MINUS, KEY_EQUAL, KEY_PLUS]:
			super(e)
		return
	if (inside_view or situ_mode) and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F:
		enter()
		get_viewport().set_input_as_handled()
		return
	if (inside_view or situ_mode) and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var h := _house_under(e.position)
		if h != null:
			enter(false, h)
			get_viewport().set_input_as_handled()
			return
	super(e)


func _house_under(screen: Vector2) -> Node3D:
	## the house a click falls on: the roof is what you click, so the ray is tested at mid-height of a house and on the
	## ground. With the interiors in place: any house that has one; else the forge of the old separate interior.
	var o := cam.project_ray_origin(screen)
	var dv := cam.project_ray_normal(screen)
	if absf(dv.y) < 1e-4:
		return null
	for y: float in [4.0, 0.0]:
		var hit := o + dv * ((y - o.y) / dv.y)
		if situ_mode:
			var h := _house_near(hit, 0.4)
			if h != null:
				return h
		elif situ_house != null and Vector2(hit.x - situ_house.global_position.x, hit.z - situ_house.global_position.z).length() < 5.0:
			return situ_house
	return null


func _switch(h: Node3D) -> void:
	leave()
	while _busy:
		await get_tree().process_frame
	enter(false, h)


func enter(auto := false, house: Node3D = null) -> void:
	## opens a house: the one given, else the one with an interior in place nearest to what the camera looks at
	if _busy or inside or (inside_view == null and not situ_mode):
		return
	if situ_mode:
		if house == null:
			house = _house_near(target, 6.0)
		if house == null:
			if OS.is_debug_build():
				print("[Sim3DChars] no house with an interior in place within 6 m of the camera target")
			return
		_mount(house)
		_open(auto)
		return
	_busy = true
	if OS.is_debug_build():
		print("[Sim3DChars] entering %s at minute %.0f" % [live_bld, t_min])
	_back = {target = target, size = cam.size, yaw = yaw}
	var fp := situ_house.global_position
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_method(func(k: float):
		target = (_back.target as Vector3).lerp(Vector3(fp.x, 2, fp.z), k)
		cam.size = lerpf(_back.size, 12.0, k)
		_update_camera(), 0.0, 1.0, 0.6)
	tw.parallel().tween_property(_fade, "color:a", 1.0, 0.3).set_delay(0.35)
	await tw.finished
	inside = true
	_inside_night = -1
	_at_place = true  # who is already inside appears at its place, not at the door
	_sync_inside(t_min)
	_at_place = false
	if _sun:
		_sun.visible = false
	_hud.get_parent().get_parent().visible = false
	_hint.visible = false
	inside_view.activate(true)
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.3)
	await tw2.finished
	_busy = false


func _open(auto: bool) -> void:
	## in place: no jump. The house opens where it stands; by F / click the camera also comes close and turns to its front
	_busy = true
	_focus_auto = auto
	_back = {target = target, size = cam.size, yaw = yaw}
	if OS.is_debug_build():
		print("[Sim3DChars] opening %s (%s) in place at minute %.0f (%s)" % [situ_house.name, live_bld if live_bld != "" else "nobody of the sim", t_min, "zoom" if auto else "F / click"])
	inside = true
	_inside_night = -1
	_at_place = true  # who is already inside appears at its place, not at the door
	_sync_inside(t_min)
	_at_place = false
	inside_view.activate(true)
	_cut_yaw = -999.0
	situ_cut.cam_local = _cut_dir()
	situ_cut.top = inside_view.top
	situ_cut.set_on(true)
	for b in bld_anchor:
		if bld_anchor[b].house == situ_house:
			(bld_anchor[b].label as Label3D).visible = false
	_forge_label.set_meta("was", _forge_label.visible)
	_forge_label.visible = false
	_hint.visible = false
	if not auto:
		var fp := situ_house.global_position
		var y1 := clear_front_yaw(situ_house, yaw)
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_method(func(k: float):
			target = (_back.target as Vector3).lerp(Vector3(fp.x, 1.2, fp.z), k)
			cam.size = lerpf(_back.size, minf(float(_back.size), FOCUS_SIZE), k)
			yaw = lerpf(_back.yaw, y1, k)
			_update_camera(), 0.0, 1.0, maxf(0.01, 0.7 * transition_k))
		await tw.finished
	_busy = false


func _close() -> void:
	_busy = true
	var closing := inside_view  # GuildMaster: another house may open meanwhile (Town3D._close_now): then stop here
	if OS.is_debug_build():
		print("[Sim3DChars] closing %s at minute %.0f" % [situ_house.name, t_min])
	situ_cut.set_on(false)
	if not _focus_auto:
		var from := {target = target, size = cam.size, yaw = yaw}
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_method(func(k: float):
			target = (from.target as Vector3).lerp(_back.target, k)
			cam.size = lerpf(from.size, _back.size, k)
			yaw = lerpf(from.yaw, _back.yaw, k)
			_update_camera(), 0.0, 1.0, maxf(0.01, 0.6 * transition_k))
		await tw.finished
	while situ_cut != null and inside_view == closing and not situ_cut.settled:  # the roof is back before the inside goes
		await get_tree().process_frame
	if inside_view != closing or not inside:
		return
	inside_view.activate(false)
	if inside_view.live:
		inside_view.live_clear()
	inside = false
	for b in bld_anchor:
		if bld_anchor[b].house == situ_house:
			(bld_anchor[b].label as Label3D).visible = true
	_forge_label.visible = bool(_forge_label.get_meta("was", true))
	_hint.visible = true
	_busy = false


func leave() -> void:
	if _busy or not inside:
		return
	if situ_mode:
		_close()
		return
	_busy = true
	if OS.is_debug_build():
		print("[Sim3DChars] leaving %s at minute %.0f" % [live_bld, t_min])
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	await tw.finished
	inside_view.activate(false)
	inside_view.live_clear()
	inside = false
	if _sun:
		_sun.visible = true
	_hud.get_parent().get_parent().visible = true
	_hint.visible = true
	cam.current = true
	var fp := situ_house.global_position
	var tw2 := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw2.tween_property(_fade, "color:a", 0.0, 0.25)
	tw2.parallel().tween_method(func(k: float):
		target = Vector3(fp.x, 2, fp.z).lerp(_back.target, k)
		cam.size = lerpf(12.0, _back.size, k)
		_update_camera(), 0.0, 1.0, 0.6)
	await tw2.finished
	_busy = false


# ---------------------------------------------------------------- screenshots and bench
func _snap_to(fname: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	img.save_png(SHOTS_DIR + fname)
	print("[Sim3DChars] saved ", SHOTS_DIR + fname)


func _goto(t: float, at: Vector3, size: float, y := -1.0) -> void:
	t_min = t
	target = at
	cam.size = size
	yaw = y if y >= 0.0 else home_yaw
	_update_camera()
	_apply(t - 0.5)
	for i in 3:
		await RenderingServer.frame_post_draw
	_apply(t)


func _hold(sec: float) -> void:
	## `sec` real seconds with the clock stopped at t_min (shots): animations play, the interior people walk
	var end := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		_apply(t_min)


func _plan3(c: float, r: float, y := 1.0) -> Vector3:
	return HouseBuilder.plan_to_godot(Vector3(_tp(c, r).x, _tp(c, r).y, y))


func _sim_shots() -> void:
	## rodaja_*.png: morning plaza, noon fields and forge, inside the forge, dusk benches, night windows
	get_window().always_on_top = true
	paused = false
	var day0 := _day_start(t0)
	var args := OS.get_cmdline_user_args()
	var only := ""
	var pre := "rodaja_"
	for a in args:
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--shots_prefix="):
			pre = a.trim_prefix("--shots_prefix=")
	var plaza := _plan3(19.5, 19.0)
	for k in seats:
		var sp: Vector2 = seats[k].pos
		if String(k).begins_with("dice_plaza") and DICE_AT == Vector3.ZERO:
			DICE_AT = Vector3(sp.x, 0.8, -sp.y)
		if String(k) == "bench_w|1":
			BENCH_AT = Vector3(sp.x, 0.8, -sp.y)
	var fp := (bld_anchor[live_bld].house as Node3D).global_position if live_bld != "" else plaza
	var shots := [
		["rodaja_0830_plaza.png", 8 * 60 + 30, plaza, 24.0, home_yaw],
		["rodaja_1230_campos.png", 12 * 60 + 30, _plan3(6.5, 31.5), 26.0, home_yaw],
		["rodaja_1230_forja_fuera.png", 12 * 60 + 30, Vector3(fp.x, 1.5, fp.z) + Vector3(0, 0, -3), 20.0, 225.0],
		["rodaja_2015_corrillos.png", SHOT_DUSK, _plan3(18.5, 22.5), 16.0, 225.0],
		["rodaja_2015_dados_cerca.png", SHOT_DUSK, DICE_AT, 6.5, 200.0],
		["rodaja_2015_banco_cerca.png", SHOT_DUSK, BENCH_AT, 6.0, 120.0],
		["rodaja_2115_noche.png", SHOT_NIGHT, _plan3(18.0, 20.5), 34.0, home_yaw]]
	for s in shots:
		if only != "" and not String(s[0]).contains(only):
			continue
		await _goto(day0 + float(s[1]), s[2], s[3], s[4])
		await _hold(1.2)
		await _snap_to(String(s[0]).replace("rodaja_", pre))
	if live_bld != "" and situ_mode and (only == "" or only.contains("forja")):
		# the forge opened in place: smith and hand at work (day 2 11:00 in the default trace)
		var fp2 := situ_house.global_position
		await _goto(day0 + float(SHOT_FORGE), Vector3(fp2.x, 2, fp2.z), 30.0, home_yaw)
		await _hold(0.5)
		await _snap_to(pre + "forja_1_pueblo.png")
		enter()
		while _busy:
			await _hold(0.05)
		await _hold(5.0)
		await _snap_to(pre + "forja_2_dentro.png")
		cam.size = 8.5
		_update_camera()
		await _hold(1.5)
		await _snap_to(pre + "forja_3_cerca.png")
		leave()
		while _busy:
			await _hold(0.05)
		await _hold(0.5)
		await _snap_to(pre + "forja_4_fuera.png")
	elif live_bld != "" and (only == "" or only.contains("forja")):
		# inside the forge: smith and hand at work (day 2 11:00 in the default trace)
		await _goto(day0 + float(SHOT_FORGE), Vector3(fp.x, 2, fp.z), 30.0, 45.0)
		await _hold(0.5)
		await _snap_to(pre + "forja_1_pueblo.png")
		enter()
		while _busy:
			await get_tree().process_frame
		await _hold(4.0)
		var c := Vector3(inside_view.B.W * inside_view.B.TILE / 2.0, 0.6, inside_view.B.H * inside_view.B.TILE / 2.0)
		inside_view._view(c, 21.0, 45.0)
		await _hold(1.0)
		await _snap_to(pre + "forja_2_dentro.png")
		inside_view._view(c + Vector3(-3.5, 0.4, -3.0), 9.0, 45.0, 30.0)
		await _hold(1.5)
		await _snap_to(pre + "forja_3_cerca.png")
		leave()
		while _busy:
			await get_tree().process_frame
		await _hold(0.5)
		await _snap_to(pre + "forja_4_fuera.png")
	get_tree().quit()


## minutes after day0 of the default trace (fixed cast, --skip=4): the plaza dice/bench at dusk, night, smith + hand
const SHOT_DUSK := 20 * 60 + 15         # day 1 of the trace: two at the dice table, one on the west bench
const SHOT_NIGHT := 1440 + 21 * 60 + 15  # day 2: lit windows where somebody is awake (both forges, a house)
const SHOT_FORGE := 1440 + 11 * 60
var DICE_AT := Vector3.ZERO   # set from the seats (pueblo.gd) before the shots
var BENCH_AT := Vector3.ZERO


func _ready() -> void:
	super()
	if use_sound and not trace.is_empty() and not "--sonido=no" in OS.get_cmdline_user_args():
		add_child(preload("res://game/world3d/audio/sonido.gd").new(self))  # the sound of the town (docs/sonido.md)
	if bool((trace.get("meta", {}) as Dictionary).get("live", false)):
		return  # GuildMaster: the game's town runs none of the prueba's own runners (--abrir, --bench, --vistas...)
	if "--bench" in OS.get_cmdline_user_args():
		_bench()
	elif "--edadshots" in OS.get_cmdline_user_args():
		_edad_shots()
	elif "--muebleshots" in OS.get_cmdline_user_args():
		_muebles_shots()
	elif "--dcprof" in OS.get_cmdline_user_args():
		_dcprof()
	elif "--situshots" in OS.get_cmdline_user_args():
		_situ_shots()
	else:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--vistas="):
				_vistas(a.trim_prefix("--vistas="))
			elif a.begins_with("--abrir"):
				_abrir(a.trim_prefix("--abrir").trim_prefix("="))
			elif a.begins_with("--obrashots"):
				_obra_shots()


func _vistas(spec: String) -> void:
	## Pictures of any place: --vistas=<name>:<col>,<row>,<zoom>[,<yaw>[,<hour>[,<seconds running before>]]];... (tile
	## coordinates of the map; yaw -1 = the town's; hour of day 2 of the trace, 12 by default) -> <shots_prefix><name>.png
	get_window().always_on_top = true
	get_window().size = Vector2i(1600, 900)
	var day0 := _day_start(t0)
	var pre := "p3_"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots_prefix="):
			pre = a.trim_prefix("--shots_prefix=")
	await _hold(1.0)
	for part in spec.split(";", false):
		var v := part.get_slice(":", 1).split(",")
		if v.size() < 3:
			continue
		var y := float(v[3]) if v.size() > 3 else -1.0
		var hour := float(v[4]) if v.size() > 4 else 12.0
		paused = false
		await _goto(day0 + 1440.0 + hour * 60.0, _plan3(float(v[0]), float(v[1])), float(v[2]), y)
		await _hold(float(v[5]) if v.size() > 5 else 1.2)
		paused = true
		await _snap_to(pre + part.get_slice(":", 0) + ".png")
	get_tree().quit()


func _dc_now(frames := 6) -> int:
	var dc := 0
	for i in frames:
		await RenderingServer.frame_post_draw
		dc = maxi(dc, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	return dc


func _busiest(b: String, from_h: float, to_h: float) -> float:
	## the minute of day 2 of the trace, between two hours, with most people of the sim inside a building (work first)
	var day1 := _day_start(t0) + 1440.0
	var best := day1 + 12.0 * 60.0
	var bn := -1.0
	var m := day1 + from_h * 60.0
	while m <= day1 + to_h * 60.0:
		var n := 0.0
		for id in people:
			var p: Dictionary = people[id]
			if m < float(p.first):
				continue
			var row: Array = _state_at(p.st, m)
			if String(row[1]) == b:
				n += 1.0 + (0.5 if String(row[2]) in ["work", "work_night"] else 0.0) - (0.4 if String(row[2]) == "sleep" else 0.0)
		if n > bn:
			bn = n
			best = m
		m += 15.0
	return best


func _abrir(spec: String) -> void:
	## Every house with an interior in place opened in turn where it stands (or the ones named: --abrir=forge_25_20,house_9_8),
	## from its front at zoom 12, at the hour of day 2 with most people of the sim inside (--hora= fixes it): draw calls
	## closed, open and looking at the top floor, ms of mounting the interior, the worst frame while it opens and fps
	## open -> out/<shots_prefix>abrir.json and pictures <shots_prefix>abrir_<house>[_alta].png. `--noche[=<houses>]`: also at 21:15.
	get_window().always_on_top = true
	get_window().size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var pre := "p3b_"
	var hora := -1.0
	var night := ""  # --noche (every house) or --noche=<house>,<house>
	var zoom := 12.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots_prefix="):
			pre = a.trim_prefix("--shots_prefix=")
		elif a.begins_with("--hora="):
			hora = float(a.trim_prefix("--hora="))
		elif a.begins_with("--noche"):
			night = a.trim_prefix("--noche").trim_prefix("=") if a.contains("=") else "*"
		elif a.begins_with("--zoom="):
			zoom = float(a.trim_prefix("--zoom="))
	await _hold(1.5)
	var day1 := _day_start(t0) + 1440.0
	var res := {}
	var none := {}
	for h in houses:
		if not h.has_meta("interior"):
			none[String(h.name)] = String(h.get_meta("no_interior", "no interior"))
			continue
		if spec != "" and not String(h.name) in spec.split(","):
			continue
		var b := _bld_of(h)
		var times := [_busiest(b, 7.0, 21.0) if hora < 0.0 else day1 + hora * 60.0]
		if night == "*" or String(h.name) in night.split(","):
			times.append(day1 + 21.25 * 60.0)
		for ti in times.size():
			var tag := String(h.name) + ("" if ti == 0 else "_noche")
			var fp := h.global_position
			paused = false
			await _goto(float(times[ti]), Vector3(fp.x, 1.2, fp.z), zoom, fposmod(clear_front_yaw(h, home_yaw), 360.0))
			await _hold(1.0)
			var e := {"interior": String(h.get_meta("interior")).get_file(), "sim_building": b, "type": String(h.get_meta("look", "")),
				"level": int(h.get_meta("level", 0)), "minute_of_day": int(fmod(float(times[ti]), 1440.0)), "dc_closed": await _dc_now()}
			var t_open := Time.get_ticks_usec()
			var worst := 0.0
			var last := t_open
			enter(false, h)
			e["enter_call_ms"] = snappedf((Time.get_ticks_usec() - t_open) / 1000.0, 0.1)  # mounting + who is inside, before the first frame
			while _busy or (situ_cut and not situ_cut.settled):
				await RenderingServer.frame_post_draw
				_apply(t_min)
				var now := Time.get_ticks_usec()
				worst = maxf(worst, (now - last) / 1000.0)
				last = now
			e["mount_ms"] = snappedf(float(mount_stats.get(String(h.name), 0.0)), 0.1)
			e["open_worst_frame_ms"] = snappedf(worst, 0.1)
			await _hold(4.0)
			e["people"] = inside_view.live_actors.size()
			e["dc_open"] = await _dc_now()
			var f0 := Engine.get_frames_drawn()
			var s0 := Time.get_ticks_usec()
			while Time.get_ticks_usec() - s0 < 2_000_000:
				await RenderingServer.frame_post_draw
				_apply(t_min)
			e["fps_open"] = snappedf((Engine.get_frames_drawn() - f0) / ((Time.get_ticks_usec() - s0) / 1e6), 0.1)
			paused = true
			await _snap_to("%sabrir_%s.png" % [pre, tag])
			paused = false
			if (inside_view.B.floors as Array).size() > 1 and ti == 0:
				inside_view.set_top(int(inside_view.B.floors[-1]))
				await _hold(2.0)
				e["dc_open_top"] = await _dc_now()
				paused = true
				await _snap_to("%sabrir_%s_alta.png" % [pre, tag])
				paused = false
				inside_view.set_top(int(inside_view.B.floors[0]))
			leave()
			while _busy:
				await _hold(0.05)
			await _hold(0.3)
			res[tag] = e
			print("[Sim3DChars] abrir %s: %s" % [tag, JSON.stringify(e)])
	var fa := FileAccess.open("res://out/%sabrir.json" % pre, FileAccess.WRITE)
	fa.store_string(JSON.stringify({"houses": res, "without_interior": none}, "  "))
	print("[Sim3DChars] ABRIR without interior: ", JSON.stringify(none))
	get_tree().quit()


func _obra_shots() -> void:
	## The buildings whose level or works change during the trace (tools/sim_trace.gd --guion=obra), each seen at zoom
	## 14 from its front while the clock runs through every change of its look: a picture at the middle of each stage
	## (<shots_prefix>obra_<house>_<n>_<stage>.png) and the ms each rebuild took -> out/<shots_prefix>obra.json.
	## Then the whole trace played at x300 from the far view: rebuilds while the town is in sight.
	get_window().always_on_top = true
	get_window().size = Vector2i(1600, 900)
	var pre := "p3b_"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots_prefix="):
			pre = a.trim_prefix("--shots_prefix=")
	await _hold(1.5)
	var res := {"stages": {}, "rebuilds": []}
	for b: String in _live_blds:
		var bd: Dictionary = trace.buildings[b]
		var o := Vector2i(int(bd.origin[0]), int(bd.origin[1]))
		# the minutes its look changes, by sampling the trace
		var marks := []  # [from, to, key]
		var last := ""
		var m := t0
		var lot: Dictionary = (bld_anchor[b].house as Node3D).get_meta("lot")
		while m <= t1:
			sim_buildings[o] = _bld_at(b, m)
			var key := look_key(_look_of(lot))
			if key != last:
				if not marks.is_empty():
					marks[-1][1] = m
				marks.append([m, t1, key])
				last = key
			m += 5.0
		var i := 0
		for mk in marks:
			# the brightest minute of the stage (a stage that falls at night is taken at its middle)
			var mid := (float(mk[0]) + float(mk[1])) / 2.0
			var best := mid
			var bl := -1.0
			var q := float(mk[0]) + 2.0
			while q < float(mk[1]):
				if daylight(q) > bl + 0.05:
					bl = daylight(q)
					best = q
				q += 20.0
			var h: Node3D = bld_anchor[b].house
			var fp := h.global_position
			paused = false
			await _goto(best, Vector3(fp.x, 1.5, fp.z), 14.0, fposmod(front_yaw(h, home_yaw), 360.0))
			await _hold(1.0)
			h = bld_anchor[b].house
			var st := String(h.get_meta("stage", "done"))
			var nm := "%sobra_%s_%d_%s_n%d.png" % [pre, h.name, i, st, int(h.get_meta("level", 0))]
			paused = true
			await _snap_to(nm)
			res.stages["%s_%d" % [h.name, i]] = {"minute": int(best), "from": int(mk[0]), "to": int(mk[1]), "look": mk[2], "shot": nm}
			i += 1
	# the trace from end to end at x300, the whole town in sight
	paused = false
	await _goto(t0, Vector3(W, 2, H), 66.0)
	rebuilds.clear()
	speed_i = SPEEDS.size() - 1
	var worst := 0.0
	var prev := Time.get_ticks_usec()
	var n := 0
	var sum := 0.0
	while t_min < t1 - 30.0 and n < 6000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - prev) / 1000.0)
		sum += (now - prev) / 1000.0
		prev = now
		n += 1
	res.rebuilds = rebuilds
	res["merge_ms"] = merge_ms
	res["play_x300"] = {"frames": n, "ms_avg": snappedf(sum / maxi(1, n), 0.01), "ms_worst_frame": snappedf(worst, 0.1)}
	var fa := FileAccess.open("res://out/%sobra.json" % pre, FileAccess.WRITE)
	fa.store_string(JSON.stringify(res, "  "))
	print("[Sim3DChars] OBRA ", JSON.stringify(res))
	get_tree().quit()


func _muebles_shots() -> void:
	## someone on an errand with a crate in the arms (carry_box) and the own furniture inside the forge -> p60_caja_*, p60_muebles_*
	get_window().always_on_top = true
	paused = true
	var day0 := _day_start(t0)
	var shots := 0
	for id in people:
		if shots >= 2:
			break
		var p: Dictionary = people[id]
		var rows: Array = p.st
		for k in rows.size() - 1:
			var row: Array = rows[k]
			# an errand (the trace has them standing at a spot in the street with the goods) in daylight
			var m := (float(row[0]) + float(rows[k + 1][0])) / 2.0
			if String(row[2]) != "errand" or String(row[1]) != "" or fmod(m, 1440.0) < 7 * 60 or fmod(m, 1440.0) > 18 * 60:
				continue
			await _goto(m, Vector3.ZERO, 3.5)
			set_cutaway(true)
			for q in people:
				(people[q].icon as Label3D).visible = false  # the 📦 icon hides the crate
			for yw in [45.0, 225.0]:
				yaw = yw
				target = (p.node as Node3D).global_position + Vector3(0, 0.9, 0)
				_update_camera()
				await _hold(1.0)
				await _snap_to("p60_caja_%s_%d.png" % [String(trace.characters[id].name).to_lower().replace("í", "i"), int(yw)])
			for q in people:
				(people[q].icon as Label3D).visible = true
			set_cutaway(false)
			yaw = 45.0
			shots += 1
			break
	if live_bld != "":
		var fp := (bld_anchor[live_bld].house as Node3D).global_position
		await _goto(day0 + float(SHOT_FORGE), Vector3(fp.x, 2, fp.z), 26.0)
		await _hold(0.5)
		enter()
		while _busy:
			await get_tree().process_frame
		await _hold(5.0)
		var B = inside_view.B
		inside_view._view(B.tile_pos(0, Vector2i(4, 4)), 20.0, 45.0)
		await _hold(1.0)
		await _snap_to("p60_muebles_taller.png")
		inside_view._view(B.tile_pos(0, B.zones["counter"].tile), 7.0, 45.0, 32.0)
		await _hold(1.0)
		await _snap_to("p60_muebles_mostrador.png")
		inside_view._view(B.tile_pos(0, B.zones["anvil"].tile), 7.0, 225.0, 32.0)
		await _hold(1.0)
		await _snap_to("p60_muebles_yunque.png")
		inside_view.set_top(1)
		inside_view._view(B.tile_pos(1, Vector2i(2, 2)), 8.0, 45.0, 34.0)
		await _hold(1.0)
		await _snap_to("p60_muebles_cocina.png")
	get_tree().quit()


func _edad_shots() -> void:
	## trace of GuildMaster's family_ages scenario (tools/sim_trace.gd --scenario=family_ages): the eldest and the
	## youngest who walk the streets, close; inside the forge the children at home upstairs; then 40 s of playback at
	## x0.25 with the gait per life stage (gait_stats.by_age) -> p60_edad_*.png, out/edad_gait.json
	get_window().always_on_top = true
	paused = true
	var day0 := _day_start(t0)
	var walkers := []
	for id in trace.characters:
		var c: Dictionary = trace.characters[id]
		if (c.pos as Array).size() > 30 and c.has("age"):
			walkers.append(id)
	walkers.sort_custom(func(a, b): return int(trace.characters[a].age) > int(trace.characters[b].age))
	var picks := [walkers.front(), walkers.back()] if walkers.size() > 1 else walkers
	for id in picks:
		var pos: PackedInt32Array = people[id].pos
		var found := -1.0
		# the middle of a run of at least 7 steps in daylight, out in the street (not at a door)
		for k in range(4, pos.size() / 3 - 4):
			var m := float(pos[k * 3])
			var md := fmod(m, 1440.0)
			if md < 8 * 60 or md > 17 * 60:
				continue
			if float(pos[(k + 3) * 3]) - float(pos[(k - 3) * 3]) > mpt * 6 + 0.5:
				continue
			var row := _state_at(people[id].st, m)
			if String(row[1]) != "":
				continue
			found = m - mpt * 0.5
			break
		if found < 0:
			continue
		var c: Dictionary = trace.characters[id]
		await _goto(found, Vector3.ZERO, 6.0)
		target = (people[id].node as Node3D).global_position + Vector3(0, 1, 0)
		_update_camera()
		await _hold(0.6)
		if not (people[id].node as Node3D).visible:
			print("[Sim3DChars] edad: %s not in sight at %d" % [c.name, int(found)])
		await _snap_to("p60_edad_%s_%d_calle.png" % [String(c.name).to_lower().replace("è", "e"), int(c.age)])
	# inside the forge with the children at home (day 0, 10:00)
	if live_bld != "":
		var fp := (bld_anchor[live_bld].house as Node3D).global_position
		await _goto(day0 + 10 * 60, Vector3(fp.x, 2, fp.z), 26.0)
		await _hold(0.5)
		enter()
		while _busy:
			await get_tree().process_frame
		await _hold(9.0)
		var B = inside_view.B
		var c0: Vector3 = B.tile_pos(0, Vector2i(5, 4))
		inside_view._view(c0, 21.0, 45.0)
		await _hold(1.0)
		await _snap_to("p60_edad_forja_planta_baja.png")
		inside_view.set_top(1)
		var kc: Vector3 = B.tile_pos(1, Vector2i(2, 2))
		inside_view._view(kc, 9.0, 45.0, 34.0)
		await _hold(1.5)
		await _snap_to("p60_edad_forja_cocina.png")
		inside_view.set_top(0)
		leave()
		while _busy:
			await get_tree().process_frame
	# gait per life stage while the clock runs at x0.25 (people walk) through the morning
	gait_stats = {"frames": 0, "moving": 0, "slide": 0, "rate_max": 0.0, "by_gait": {}, "by_age": {}}
	await _goto(day0 + 7 * 60, Vector3(W, 2, H), 40.0)
	speed_i = 0
	paused = false
	var end := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
	var fa := FileAccess.open("res://out/edad_gait.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(gait_stats, "  "))
	print("[Sim3DChars] edad gait: ", JSON.stringify(gait_stats))
	get_tree().quit()


func _dcprof() -> void:
	## draw calls by category (scripts/dc_prof.gd) in the bench views -> out/dcprof.json
	get_window().always_on_top = true
	get_window().size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _hold(2.0)
	var day0 := _day_start(t0)
	var res := {}
	var prefix := ""
	var out := "res://out/dcprof.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots_prefix="):
			prefix = a.trim_prefix("--shots_prefix=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var cfgs := [["pueblo_dia", 1440 + 12 * 60, Vector3(W, 2, H), 66.0], ["plaza_dia", 1440 + 12 * 60, _plan3(19.5, 19.0), 26.0],
		["pueblo_noche", SHOT_NIGHT, Vector3(W, 2, H), 66.0], ["plaza_noche", SHOT_NIGHT, _plan3(19.5, 19.0), 26.0],
		["calle_dia", 1440 + 12 * 60, _plan3(17.0, 21.0), 12.0],
		["taberna_terraza", 1440 + 17 * 60, _plan3(27.5, 37.0), 12.0], ["patio_sur", 1440 + 17 * 60, _plan3(16.5, 35.5), 16.0],
		["patio_este", 1440 + 17 * 60, _plan3(28.5, 18.5), 16.0],
		["traseras_se", 1440 + 17 * 60, _plan3(27.5, 28.0), 18.0, 225.0], ["traseras_oeste", 1440 + 17 * 60, _plan3(11.0, 16.0), 18.0, 225.0],
		["traseras_ne", 1440 + 17 * 60, _plan3(27.5, 10.0), 18.0, 225.0],
		["patio_se", 1440 + 12 * 60, _plan3(27.5, 28.0), 16.0], ["patio_ne", 1440 + 12 * 60, _plan3(27.5, 10.0), 16.0],
		["pozo", 1440 + 12 * 60, _plan3(19.0, 18.0, 0.8), 7.0],
		# the town with its modules and landmarks: market, workshop street (fronts look north: yaw 225), river and bridge, church
		["mercado_z12", 1440 + 12 * 60, _plan3(19.5, 16.5) if home_yaw > 90.0 and home_yaw < 270.0 else _plan3(19.0, 14.5), 12.0], ["plaza_otra", 1440 + 12 * 60, _plan3(19.5, 19.0), 26.0, home_yaw + 180.0],
		["talleres_dia", 1440 + 12 * 60, _plan3(21.0, 33.0), 26.0, 225.0], ["talleres_noche", SHOT_NIGHT, _plan3(21.0, 33.0), 26.0, 225.0],
		["talleres_z12", 1440 + 12 * 60, _plan3(17.5, 33.5), 12.0, 225.0], ["forjas_z12", 1440 + 12 * 60, _plan3(27.0, 20.5), 12.0],
		["rio_dia", 1440 + 12 * 60, _plan3(35.5, 18.0), 26.0], ["rio_noche", SHOT_NIGHT, _plan3(35.5, 18.0), 26.0],
		["rio_z12", 1440 + 12 * 60, _plan3(36.5, 17.5), 12.0], ["iglesia_dia", 1440 + 12 * 60, _plan3(19.5, 11.5, 3.0), 20.0, 45.0],
		["armeria_z12", 1440 + 12 * 60, _plan3(26.5, 16.0), 12.0, 135.0],
		["campos_dia", 1440 + 12 * 60, _plan3(6.5, 31.5), 26.0], ["campos_z12", 1440 + 12 * 60, _plan3(5.0, 30.0), 12.0]]
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	for cfg in cfgs:
		if only != "" and not String(cfg[0]) in only.split(","):
			continue
		await _goto(day0 + float(cfg[1]), cfg[2], cfg[3], float(cfg[4]) if cfg.size() > 4 else -1.0)
		await _hold(1.0)
		paused = true
		if prefix != "":
			await _snap_to("%s%s.png" % [prefix, cfg[0]])
		if "--fpsprof" in OS.get_cmdline_user_args():
			res[cfg[0]] = await preload("res://game/world3d/town/dc_prof.gd").fps_profile(self, _sun, _env, [inside_view])
			print("[Sim3DChars] fpsprof %s: %s" % [cfg[0], JSON.stringify(res[cfg[0]])])
		elif not "--noprof" in OS.get_cmdline_user_args():
			res[cfg[0]] = await preload("res://game/world3d/town/dc_prof.gd").profile(self, _sun, [inside_view])
			print("[Sim3DChars] dcprof %s: %s" % [cfg[0], JSON.stringify(res[cfg[0]])])
		paused = false
	var fa := FileAccess.open(out, FileAccess.WRITE)
	fa.store_string(JSON.stringify(res, "  "))
	get_tree().quit()


func _bench() -> void:
	## fps of the whole scene at 1600x900 (--res=WxH): town by day, town at night, inside the forge (out/rodaja_bench.json)
	get_window().always_on_top = true
	var res_size := Vector2i(1600, 900)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--res="):
			res_size = Vector2i(int(a.trim_prefix("--res=").get_slice("x", 0)), int(a.trim_prefix("--res=").get_slice("x", 1)))
	get_window().size = res_size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _hold(2.0)
	var day0 := _day_start(t0)
	var fp := (bld_anchor[live_bld].house as Node3D).global_position
	var res := {}
	var cfgs := [["pueblo_dia", 1440 + 12 * 60, Vector3(W, 2, H), 66.0, false], ["plaza_dia", 1440 + 12 * 60, _plan3(19.5, 19.0), 26.0, false],
		["pueblo_noche", SHOT_NIGHT, Vector3(W, 2, H), 66.0, false], ["plaza_noche", SHOT_NIGHT, _plan3(19.5, 19.0), 26.0, false],
		["forja_fuera", SHOT_FORGE, Vector3(fp.x, 1.2, fp.z), 13.0, false, 135.0], ["forja_dentro", SHOT_FORGE, Vector3(fp.x, 1.2, fp.z), 13.0, true, 135.0]]
	for cfg in cfgs:
		await _goto(day0 + float(cfg[1]), cfg[2], cfg[3], float(cfg[5]) if cfg.size() > 5 else -1.0)
		if cfg[4]:
			enter()
			while _busy:
				await get_tree().process_frame
			await _hold(2.0)
		await _hold(1.0)
		var f0 := Engine.get_frames_drawn()
		var t_start := Time.get_ticks_usec()
		var worst := 0.0
		var last := t_start
		var cpu := 0.0
		var gpu := 0.0
		var dc := 0
		var apply_us := 0.0
		while Time.get_ticks_usec() - t_start < 5_000_000:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
			dc = maxi(dc, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		var frames := Engine.get_frames_drawn() - f0
		var secs := (Time.get_ticks_usec() - t_start) / 1e6
		var a0 := Time.get_ticks_usec()
		for i in 20:
			_apply(t_min)
		apply_us = (Time.get_ticks_usec() - a0) / 20.0
		res[cfg[0]] = {"fps": snappedf(frames / secs, 0.1), "ms_avg": snappedf(secs * 1000.0 / frames, 0.01),
			"ms_worst": snappedf(worst, 0.01), "render_cpu_ms": snappedf(cpu / frames, 0.01), "render_gpu_ms": snappedf(gpu / frames, 0.01),
			"draw_calls": dc, "apply_us": snappedf(apply_us, 1)}
		print("[Sim3DChars] bench %s: %s" % [cfg[0], res[cfg[0]]])
		if cfg[4]:
			leave()
			while _busy:
				await get_tree().process_frame
	res.window = str(get_viewport().get_visible_rect().size)
	res.video_mem_mb = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	res.people = people.size()
	res.night = night_stats
	res.gait = gait_stats
	var bout := "res://out/rodaja_bench.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			bout = a.trim_prefix("--out=")
	var fa := FileAccess.open(bout, FileAccess.WRITE)
	fa.store_string(JSON.stringify(res, "  "))
	print("[Sim3DChars] BENCH ", JSON.stringify(res))
	get_tree().quit()


# ---------------------------------------------------------------- interior in place: screenshots and numbers
func _wait_open() -> void:
	while _busy or (situ_cut and not situ_cut.settled):
		await _hold(0.05)


func _situ_shots() -> void:
	## sims_*.png: the sequence of going in (town, zoom, roof off, upper floor), game zooms, the other yaws, night from
	## the street and inside; with --sitio=demo the four scripted people and, after --secs (default 90), how close they
	## got to each other and to the pieces (out/sims_gente.json). --shots_prefix= changes "sims_".
	get_window().always_on_top = true
	paused = false
	var day0 := _day_start(t0)
	var pre := "sims_"
	var secs := 90.0
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots_prefix="):
			pre = a.trim_prefix("--shots_prefix=")
		elif a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var fp := situ_house.global_position
	var at := Vector3(fp.x, 1.2, fp.z)
	var demo: bool = not inside_view.live
	if "--sitio=aforo" in OS.get_cmdline_user_args():
		# how many fit: n people walking about a floor, 40 s each (x3), ground floor and upper floor
		await _goto(day0 + float(SHOT_FORGE), at, 13.0, home_yaw)
		enter()
		await _wait_open()
		var res := {}
		seed(7)
		for cfg in [[0, 2], [0, 4], [0, 6], [0, 8], [0, 10], [1, 2], [1, 3], [1, 4], [1, 6]]:
			inside_view.aforo(int(cfg[1]), int(cfg[0]))
			await _wait_open()
			Engine.time_scale = 3.0
			await _hold(secs / 3.0)
			Engine.time_scale = 1.0
			var st2: Dictionary = inside_view.stats.duplicate()
			st2.free_tiles = inside_view._free_tiles(int(cfg[0])).size()
			st2.wait_share = snappedf(float(st2.wait_s) / maxf(0.001, float(st2.wait_s) + float(st2.walk_s)), 0.001)
			res["planta%d_%d" % [cfg[0], cfg[1]]] = st2
			print("[Sim3DChars] aforo floor %d, %d people: %s" % [cfg[0], cfg[1], JSON.stringify(st2)])
			if int(cfg[1]) in [6, 8] or int(cfg[0]) == 1 and int(cfg[1]) == 4:
				await _snap_to("%saforo_p%d_%d.png" % [pre, cfg[0], cfg[1]])
		var fo := FileAccess.open("res://out/%saforo.json" % pre, FileAccess.WRITE)
		fo.store_string(JSON.stringify(res, "  "))
		get_tree().quit()
		return
	if demo:
		# the worst case: smith, hand, shopkeeper and customers, for `secs` seconds
		await _goto(day0 + float(SHOT_FORGE), at, 16.0, home_yaw)
		enter()
		await _wait_open()
		await _hold(14.0)
		await _snap_to(pre + "demo_1_frente.png")
		cam.size = 9.0
		_update_camera()
		await _hold(6.0)
		await _snap_to(pre + "demo_2_cerca.png")
		cam.size = 13.0
		yaw = 45.0
		_update_camera()
		await _hold(7.0)
		await _snap_to(pre + "demo_3_yaw45.png")
		yaw = 225.0
		_update_camera()
		await _hold(5.0)
		await _snap_to(pre + "demo_4_yaw225.png")
		yaw = 135.0
		cam.size = 26.0
		_update_camera()
		await _hold(5.0)
		await _snap_to(pre + "demo_5_zoom26.png")
		cam.size = 13.0
		_update_camera()
		await _hold(maxf(0.0, secs - 40.0))
		await _snap_to(pre + "demo_6_final.png")
		var st: Dictionary = inside_view.stats.duplicate()
		st.seconds = secs
		st.people = inside_view.people.size()
		var fa := FileAccess.open("res://out/%sgente.json" % pre, FileAccess.WRITE)
		fa.store_string(JSON.stringify(st, "  "))
		print("[Sim3DChars] people in place: ", JSON.stringify(st))
		get_tree().quit()
		return
	if only == "" or only == "entrar":
		await _goto(day0 + float(SHOT_FORGE), at, 30.0, home_yaw)
		await _hold(1.0)
		await _snap_to(pre + "1_pueblo.png")
		cam.size = 15.0
		_update_camera()
		await _hold(0.8)
		await _snap_to(pre + "2_zoom.png")
		enter(true)  # as by zooming in: the house opens under the camera as it is
		while _busy:
			await get_tree().process_frame
		situ_cut.set_process(false)  # hold the cut half way for the picture
		situ_cut.set_on(false, true)
		situ_cut.set_on(true)
		situ_cut.set_process(false)
		situ_cut._step(0.17)
		await _snap_to(pre + "3_abriendo.png")
		situ_cut.set_process(true)
		await _wait_open()
		await _hold(3.0)
		await _snap_to(pre + "3b_abierta_yaw45.png")
		leave()
		await _wait_open()
		enter()
		await _wait_open()
		await _hold(5.0)
		await _snap_to(pre + "4_tejado_fuera.png")
		inside_view.set_top(1)
		await _wait_open()
		await _hold(1.0)
		await _snap_to(pre + "5_planta_alta.png")
		inside_view.set_top(0)
		await _wait_open()
	if only == "" or only == "zoom":
		if not inside:
			await _goto(day0 + float(SHOT_FORGE), at, 16.0, home_yaw)
			enter()
			await _wait_open()
			await _hold(5.0)
		for z in [9.0, 12.0, 18.0, 26.0]:
			cam.size = z
			target = at
			_update_camera()
			await _hold(1.0)
			await _snap_to(pre + "zoom%d.png" % int(z))
		cam.size = 13.0
		for y in [45.0, 225.0, 315.0]:
			yaw = y
			_update_camera()
			await _wait_open()
			await _hold(0.8)
			await _snap_to(pre + "yaw%d.png" % int(y))
		yaw = 135.0
		_update_camera()
		inside_view.select("anvil")
		await _hold(0.6)
		await _snap_to(pre + "zona.png")
		inside_view.select("")
	if inside:
		leave()
		await _wait_open()
	if only == "" or only == "casa":
		# the smith comes home (the trace: day 2, 17:05, for five minutes): the clock is held there while he walks in
		# and up the stairs on foot; then the upper floor
		var th := day0 + 1440.0 + 17 * 60 + 3
		await _goto(th, at, 13.0, 45.0)
		enter()
		await _wait_open()
		await _hold(1.0)
		paused = true
		t_min = th + 4.0
		for k in 80:
			await _hold(0.2)
			var up := false
			for a in inside_view.people:
				if a.node.position.y > 1.3 and a.node.position.y < 2.3:
					up = true
			if up:
				break
		await _snap_to(pre + "6_sube_a_casa.png")
		await _hold(8.0)
		inside_view.set_top(1)
		await _wait_open()
		await _hold(1.5)
		await _snap_to(pre + "7_en_casa.png")
		inside_view.set_top(0)
		paused = false
		leave()
		await _wait_open()
	if only == "" or only == "noche":
		# night, the smith at the furnace: from the street with the house closed, then open
		var tn := day0 + 1440.0 + 21 * 60 + 10
		inside_view.keep_visible = true
		inside_view.interior.visible = true
		inside_view.set_night(true)
		inside_view.process_mode = Node.PROCESS_MODE_INHERIT
		var front := situ_house.global_transform.basis.z  # out of the door
		await _goto(tn, at + front * 2.5, 10.0, front_yaw(situ_house, 45.0))
		inside = true  # the people of the sim at their places while the house is still closed
		inside_view.live_snap = true
		_sync_inside(tn)
		inside_view.live_snap = false
		await _hold(4.0)
		await _snap_to(pre + "noche_calle.png")
		inside = false
		inside_view.live_clear()
		enter()
		await _wait_open()
		await _hold(5.0)
		await _snap_to(pre + "noche_dentro.png")
		leave()
		await _wait_open()
	get_tree().quit()
