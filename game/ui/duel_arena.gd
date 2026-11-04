class_name DuelArena
extends Control
## The stage of the duel screen (docs/ui/mecanicas/combate.md §3, §8): the two duellists face to face with their
## sprites (CharacterView, ×2), and the short animation of each lance: the strike lunges, the parry steps back with a
## spark, the feint half-lunges and pulls back; whoever is touched recoils and blinks, and a word rises over the middle
## («¡Toque!», «Choque», «Detenido», «Nada»). The duel poses and hit effects have no art yet: the sprites use their
## forge / work / idle animations and the effects are drawn by code (marked on screen as provisional, see MISSING_ART).
## View only: reads a lance record of Duel.lances_log(), gives no orders.

signal lance_shown

const SCALE: float = 2.0
const FEET_Y: float = 150.0
const GAP: float = 150.0          # distance between the two figures' feet
const FX_SECONDS: float = 0.45
## The motion of the sprite (game/visuals/characters/*_frames.tres) that stands for each action until the duel poses.
const POSE: Dictionary = {"strike": "forge", "parry": "idle", "feint": "work"}
const MISSING_ART: String = "duel_poses"

var fighters: Array[CharacterView] = []
var _fx: Array = []                 # [{kind, at, t}]
var _words: Label = null
var _missing: Label = null


func _ready() -> void:
	clip_contents = true
	_words = Label.new()
	_words.name = "Words"
	_words.theme_type_variation = &"GothicGoldTitle"
	_words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_words.visible = false
	add_child(_words)
	_missing = Label.new()
	_missing.name = "MissingArt"
	_missing.theme_type_variation = &"WarningLabel"
	_missing.text = tr("combat.ui.missing_art")
	_missing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_missing)
	resized.connect(_layout)


## The two duellists (characters of the state with their families): side 0 on the left facing east.
func setup(chars: Array, families: Array) -> void:
	for f: CharacterView in fighters:
		f.queue_free()
	fighters.clear()
	for i: int in 2:
		var v := CharacterView.new()
		v.setup(chars[i], families[i])
		v.scale = Vector2(SCALE, SCALE)
		add_child(v)
		fighters.append(v)
	_layout()
	idle()


func _layout() -> void:
	var cx := size.x / 2.0
	for i: int in fighters.size():
		fighters[i].position = Vector2(roundf(cx + (-GAP / 2.0 if i == 0 else GAP / 2.0)), FEET_Y)
	if _missing != null:
		_missing.position = Vector2(4, size.y - 18)
	if _words != null:
		_words.size = Vector2(size.x, 20)
		_words.position = Vector2(0, 8)


func idle() -> void:
	for i: int in fighters.size():
		fighters[i].play_motion("idle", "e" if i == 0 else "w")


## Plays the animation of one lance record (Duel.lances_log() entry); emits lance_shown when done (~0.6 s).
func play(rec: Dictionary, fast: bool = false) -> void:
	var acts: Array = rec.get("actions", ["", ""])
	var seconds := 0.3 if fast else 0.6
	for i: int in fighters.size():
		var a := str(acts[i])
		var dir := 1.0 if i == 0 else -1.0
		fighters[i].play_motion(str(POSE.get(a, "idle")), "e" if i == 0 else "w")
		match a:
			"strike":
				UiAnim.lunge(fighters[i], 18.0 * dir)
			"feint":
				UiAnim.lunge(fighters[i], 9.0 * dir, [0.5, 1.0, 0.0, -0.5, 0.0] as Array[float])
			"parry":
				UiAnim.lunge(fighters[i], -6.0 * dir, [1.0, 1.0, 0.5, 0.0] as Array[float])
	var w := int(rec.get("winner", -1))
	var mid := Vector2(size.x / 2.0, FEET_Y - 40.0)
	var kind := "spark" if "parry" in acts else ("slash" if "strike" in acts else "swirl")
	_fx.append({"kind": kind, "at": mid, "t": FX_SECONDS})
	var how := str(rec.get("how", "even"))
	var word := tr("combat.how.%s" % how)
	if w >= 0:
		word = tr("combat.ui.touch")
		var hit := fighters[1 - w]
		get_tree().create_timer(0.22).timeout.connect(func() -> void:
			UiAnim.recoil(hit, (-10.0 if w == 1 else 10.0))
			_fx.append({"kind": "hit", "at": hit.position + Vector2(0, -34), "t": FX_SECONDS}))
	_show_word(word)
	set_process(true)
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		idle()
		lance_shown.emit())


func _show_word(text: String) -> void:
	_words.text = text
	_words.visible = true
	_words.modulate.a = 1.0
	var t := _words.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_interval(0.5)
	t.tween_callback(func() -> void: _words.modulate.a = 0.5)
	t.tween_interval(0.1)
	t.tween_callback(func() -> void: _words.visible = false)


func _process(delta: float) -> void:
	for f: Dictionary in _fx:
		f["t"] = float(f["t"]) - delta
	_fx = _fx.filter(func(f: Dictionary) -> bool: return float(f["t"]) > 0.0)
	queue_redraw()
	if _fx.is_empty():
		set_process(false)


func _draw() -> void:
	draw_rect(Rect2(Vector2(0, FEET_Y - 2), Vector2(size.x, size.y - FEET_Y + 2)), Color(0.16, 0.12, 0.09, 0.6))
	draw_line(Vector2(0, FEET_Y - 2), Vector2(size.x, FEET_Y - 2), Color(0.35, 0.27, 0.18), 1.0)
	for f: Dictionary in _fx:
		var at: Vector2 = f["at"]
		var k := float(f["t"]) / FX_SECONDS
		var r := roundf(4.0 + (1.0 - k) * 10.0)
		match str(f["kind"]):
			"slash":
				draw_line(at + Vector2(-r, -r), at + Vector2(r, r), Color(1, 0.95, 0.85), 2.0)
				draw_line(at + Vector2(-r + 3, -r), at + Vector2(r + 3, r), Color(0.75, 0.2, 0.15), 1.0)
			"spark":
				for i: int in 4:
					var dv := Vector2.RIGHT.rotated(PI / 4.0 + i * PI / 2.0) * r
					draw_line(at, at + dv, Color(1.0, 0.85, 0.3), 2.0)
			"swirl":
				draw_arc(at, r, 0.0, PI * 1.5 * (1.0 - k) + 0.5, 12, Color(0.7, 0.85, 1.0), 2.0)
			"hit":
				draw_circle(at, r * 0.6, Color(0.85, 0.2, 0.15, k))
