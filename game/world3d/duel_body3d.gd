extends Node2D
## A duellist of the duel screen in 3D (M3D-5): the person's own CharBuilder body from the 3D town (Sim3DChars._def_for:
## its clothes, family colours, age), drawn in a SubViewport of its own world (side view, lit, transparent) and shown as
## a sprite whose feet are this node's origin, so the duel arena moves it as it moved the 2D sprite (lunge, recoil).
## play_motion(motion, dir) is the CharacterView call the arena makes: the motions of a lance as the kit's clips.
## Runs while the game is paused (the duel screen pauses it).

const VP_SIZE := Vector2i(120, 180)
const CAM_SIZE := 2.6                  # metres of the view's height: a grown-up and its sword arm
## arena motion -> kit clip (Universal Animation Library: kit/chars/derived/animations.res)
const CLIP := {"idle": "Sword_Idle", "forge": "Sword_Attack", "work": "Punch_Jab", "hit": "Hit_Chest"}
## a fist fight: the guard and the blows of a boxer (the sword's slash spreads both arms)
const CLIP_FISTS := {"idle": "Idle", "forge": "Punch_Cross", "work": "Punch_Jab", "hit": "Hit_Chest"}

var fists: bool = false

var vp: SubViewport = null
var body: Node3D = null
var ap: AnimationPlayer = null
var _facing := "e"


## A body for `id` from the 3D town `town` (null if the town does not have that person).
static func make(town: Node, id: String) -> Node2D:
	if town == null or not ("trace" in town) or not (town.trace.characters as Dictionary).has(id):
		return null
	var d: Dictionary = town.call("_def_for", id, town.trace.characters[id])
	var n: Node2D = load("res://game/world3d/duel_body3d.gd").new()
	n.call("_build", d)
	return n


func _build(d: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	vp = SubViewport.new()
	vp.size = VP_SIZE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.72, 0.68)
	e.ambient_light_energy = 0.7
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SIZE
	cam.position = Vector3(0, CAM_SIZE / 2.0 - 0.05, 6.0)
	vp.add_child(cam)
	cam.current = true
	body = CharBuilder.build(d)
	vp.add_child(body)
	ap = body.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null:
		ap.process_mode = Node.PROCESS_MODE_ALWAYS
	var spr := Sprite2D.new()
	spr.texture = vp.get_texture()
	spr.centered = false
	spr.offset = Vector2(-VP_SIZE.x / 2.0, -VP_SIZE.y)   # the feet on this node's origin
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(spr)


## The arena's motion: "idle" | "forge" (the strike) | "work" (the feint) facing "e" or "w".
func play_motion(motion: String, dir: String) -> void:
	if body == null:
		return
	_facing = dir
	body.rotation.y = deg_to_rad(90.0 if dir == "e" else -90.0)
	_clip = str((CLIP_FISTS if fists else CLIP).get(motion, "Idle" if fists else "Sword_Idle"))
	_play()


var _clip := "Sword_Idle"


func _play() -> void:
	if (CharBuilder as Script).has_method("play"):   # own animations bring and take away their items, like the town
		(CharBuilder as Script).call("play", body, _clip, "", 0.1)
	elif ap != null and _clip_name(_clip) != "":
		ap.play(_clip_name(_clip), 0.1)


func _process(_delta: float) -> void:
	if ap != null and not ap.is_playing():
		_play()   # the library clips do not loop: the stance goes on


## The clip's name as the body's AnimationPlayer has it (with or without its library prefix).
func _clip_name(clip: String) -> String:
	for n: StringName in ap.get_animation_list():
		var s := String(n)
		if s == clip or s.ends_with("/" + clip):
			return s
	return ""
