class_name CharacterView
extends Node2D
## Greybox walker (H1): a ~48 px figure in its family's colours, at its tile or between two tiles (D3: the sim moves
## by tiles, the view interpolates position -> path[0] with move_progress / minutes_per_tile). Shows its name and a
## ring when selected. Keeps only the character id; reads the rest from the state each frame.
## H4: the name (with the family for people of other families) also shows while the mouse is over the figure
## (hovered); an employee carries a small badge over the head in the colour of the family it works for, with a gold
## border when it works for the player's family (set_badge, data/view.json "character.badge").
## The figure is the scene of the character's visual id (game/visuals/characters/<id>.tscn, VisualPaths.character_id):
## AnimatedSprite2D + SpriteFrames, with the greybox figure inside until the frames arrive. Its Top marker gives the
## height (name label, badge, click area). This node only draws the marks: the selection ring and the badge.
## H7: a bubble over the head (set_bubble: the scene game/visuals/bubbles/<id>.tscn of the social activity or of the
## strongest emotion, which goes first, GDD 4.11.5) and a phrase when the selected person is near (set_phrase).
## Sprites (Guild Renew frames): the scene's AnimatedSprite2D "Sprite" has <motion>_<dir> animations (idle, walk, work,
## forge; dirs s se e ne n nw w sw) and the identity_swap shader, which gets the person's hair, skin and family colours
## here. follow() walks it towards path[0] (the sim's next tile) and idles when it stops, keeping its facing; the
## interior calls play_motion() for the work at a station.

var char_id: String = ""
var primary: Color = Color(0.5, 0.5, 0.5)
var secondary: Color = Color(0.8, 0.8, 0.8)
var female: bool = false
var selectable: bool = false  # the human family's people
var selected: bool = false:
	set(v):
		selected = v
		if _name_label != null:
			_name_label.visible = selected or hovered
		queue_redraw()
var hovered: bool = false:
	set(v):
		if v == hovered:
			return
		hovered = v
		if _name_label != null:
			_name_label.visible = selected or hovered
var badge: Color = Color(0, 0, 0, 0)   # alpha 0 = no job
var badge_own: bool = false            # works for the player's family
var badge_border: Color = Color(1.0, 0.85, 0.3)
var fig_height: float = 48.0
var fig_width: float = 14.0
var outline: Color = Color(0.12, 0.09, 0.07)
var visual_id: String = ""
var kin_sig: String = ""  # H8: family, control, tones and job when built (WorldView rebuilds the view if they change)
var _visual: Node2D = null
var _badge_mark: Node2D = null
var _name_label: Label
var bubble_id: String = ""      # H7: the bubble shown ("" = none)
var _bubble: Node2D = null
var _phrase_label: Label = null
const MARKS_Z: int = 20  # bubble, name, phrase and badge draw over every figure and building (no one cuts them)
var _sprite: AnimatedSprite2D = null
var motion: String = "idle"   # the sprite's motion now: idle, walk, work, forge
var facing: String = "s"      # its facing: s se e ne n nw w sw
const DIRS: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]


func setup(ch: Dictionary, family: Dictionary) -> void:
	char_id = str(ch["id"])
	female = bool(ch.get("female", false))
	selectable = str(ch.get("controlled_by", "")) == "human"
	var colors: Dictionary = family.get("colors", {})
	var dress: Variant = (ch.get("visual", {}) as Dictionary).get("dress") if ch.get("visual") is Dictionary else null
	if dress is Dictionary:  # vida (04f 4.24.3): a visitor wears the clothes of its town (the identity shader paints them)
		colors = dress
	primary = ViewConfig.color(str(colors.get("primary", "#808080")))
	secondary = ViewConfig.color(str(colors.get("secondary", "#c0c0c0")))
	var cfg: Dictionary = ViewConfig.value("character", {})
	fig_width = float(cfg.get("width", 14))
	outline = ViewConfig.color(str(cfg.get("outline", "#1e1812")))
	name = char_id
	visual_id = VisualPaths.character_id(ch, family)
	_visual = VisualPaths.instantiate("characters", visual_id)
	_visual.name = "Visual"
	# H8 (GDD 4.10.9): hair and skin of the person from the palette swap
	var vis: Dictionary = ch.get("visual", {}) if ch.get("visual") is Dictionary else {}
	var hair := Identity.hair_color(int(vis.get("hair", 0)))
	var skin := Identity.skin_color(int(vis.get("skin", 0)))
	var greybox := _visual.get_node_or_null("Greybox") as GreyboxFigure
	if greybox != null:
		greybox.female = female
		greybox.primary = primary
		greybox.secondary = secondary
		greybox.hair = hair
		greybox.skin = skin
	_sprite = _visual.get_node_or_null("Sprite") as AnimatedSprite2D
	if _sprite != null and (not _sprite.visible or _sprite.sprite_frames == null):
		_sprite = null  # the greybox is the look
	if _sprite != null:
		var mat := _sprite.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("hair", hair)
			mat.set_shader_parameter("skin", skin)
			mat.set_shader_parameter("primary", primary)
			mat.set_shader_parameter("secondary", secondary)
		motion = ""
		play_motion("idle", "s")
	kin_sig = kin_signature(ch)
	VisualPaths.place(_visual, Vector2.ZERO)
	fig_height = VisualPaths.top_height(_visual, 48.0)
	add_child(_visual)
	_badge_mark = Node2D.new()
	_badge_mark.name = "Badge"
	_badge_mark.draw.connect(_draw_badge)
	_badge_mark.z_index = MARKS_Z
	add_child(_badge_mark)
	badge_border = ViewConfig.color(str(cfg.get("badge_own_border", "#ffd84c")))
	_name_label = Label.new()
	_name_label.text = str(ch.get("name", char_id))
	var fam_name := str(family.get("name", ""))
	if fam_name == "" and str(family.get("name_key", "")) != "":  # vida: the town's watch, visitors and bandits
		fam_name = SimQuery.t_(str(family["name_key"]))
	if not selectable and fam_name != "":
		_name_label.text = "%s · %s" % [str(ch.get("name", char_id)), fam_name]
	WorldLabels.style(_name_label, "name")
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.size = Vector2(160, 14)
	_name_label.position = Vector2(-80, -fig_height - 20)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.visible = selected
	_name_label.name = "NameLabel"
	_name_label.z_index = MARKS_Z
	add_child(_name_label)
	queue_redraw()


## Fiestas (04f 4.25.3): the clothes in the festival's palette (rules.view_looks: {color, amount, mask}; {} = the
## everyday ones). Mixes the family's colours towards the look's colour in the identity shader (and the greybox);
## a mask of Carnival is a dark band over the face. Cheap when the look does not change.
var festive_look: String = ""


func set_festive(look: Dictionary) -> void:
	var id := str(look.get("id", ""))
	if id == festive_look:
		return
	festive_look = id
	var c := ViewConfig.color(str(look.get("color", "#ffffff")))
	var amount := clampf(float(look.get("amount", 0.0)), 0.0, 1.0) if id != "" else 0.0
	var p := primary.lerp(c, amount)
	var s := secondary.lerp(c.lightened(0.2), amount * 0.6)
	var greybox := _visual.get_node_or_null("Greybox") as GreyboxFigure if _visual != null else null
	if greybox != null:
		greybox.primary = p
		greybox.secondary = s
		greybox.queue_redraw()
	if _sprite != null and _sprite.material is ShaderMaterial:
		(_sprite.material as ShaderMaterial).set_shader_parameter("primary", p)
		(_sprite.material as ShaderMaterial).set_shader_parameter("secondary", s)
	var mask := get_node_or_null("FestiveMask") as ColorRect
	if bool(look.get("mask", false)):
		if mask == null:
			mask = ColorRect.new()
			mask.name = "FestiveMask"
			mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mask.size = Vector2(8, 3)
			mask.position = Vector2(-4, -fig_height + 6)
			mask.z_index = 1
			add_child(mask)
		mask.color = c.darkened(0.3)
		mask.visible = true
	elif mask != null:
		mask.visible = false


## H8: what the view was built from that can change during the game (a wedding moves a person to another family, a
## child comes of age and joins the group, a job): WorldView rebuilds the view when it differs.
static func kin_signature(ch: Dictionary) -> String:
	return "%s|%s|%s|%s" % [ch.get("family", ""), ch.get("controlled_by", ""), ch.get("visual", {}),
		ch.get("job") is Dictionary]


## H7: the bubble over the head (game/visuals/bubbles/<id>.tscn, its Feet over the head); "" = none.
func set_bubble(id: String) -> void:
	if id == bubble_id:
		return
	bubble_id = id
	if _bubble != null:
		_bubble.queue_free()
		_bubble = null
	if id == "":
		return
	_bubble = VisualPaths.instantiate("bubbles", id)
	_bubble.name = "Bubble"
	WorldLabels.style_tree(_bubble)   # a greybox bubble's glyph, in the project's small letter
	_bubble.z_index = MARKS_Z
	VisualPaths.place(_bubble, Vector2(bubble_shift, -fig_height - 12))
	add_child(_bubble)
	_apply_mark()


## docs/ui/mecanicas/ciudad_viva.md §6: an emotion bubble takes the colour of the family it is felt towards as its
## outline and a 2 px bar of its intensity on its right side (0..1); a = 0 (Color(0,0,0,0)) = no mark (activities).
var bubble_mark: Color = Color(0, 0, 0, 0)
var bubble_intensity: float = 0.0


func set_bubble_mark(c: Color, intensity: float) -> void:
	if c == bubble_mark and is_equal_approx(intensity, bubble_intensity):
		return
	bubble_mark = c
	bubble_intensity = clampf(intensity, 0.0, 1.0)
	_apply_mark()


func _apply_mark() -> void:
	if _bubble == null:
		return
	var outline := _bubble.get_node_or_null("Greybox/Outline") as Line2D
	var bar := _bubble.get_node_or_null("IntensityBar") as Line2D
	if bubble_mark.a <= 0.0:
		if bar != null:
			bar.queue_free()
		return
	if outline != null:
		outline.default_color = bubble_mark
	if bar == null:
		bar = Line2D.new()
		bar.name = "IntensityBar"
		bar.width = 2.0
		_bubble.add_child(bar)
	bar.default_color = bubble_mark
	var h := maxf(1.0, roundf(12.0 * bubble_intensity))
	bar.points = PackedVector2Array([Vector2(14, -6), Vector2(14, -6 - h)])


## Moves the bubble `dx` px sideways (WorldView.spread_bubbles, so close heads do not stack their bubbles).
var bubble_shift: float = 0.0


func set_bubble_shift(dx: float) -> void:
	bubble_shift = dx
	if _bubble != null:
		VisualPaths.place(_bubble, Vector2(dx, -fig_height - 12))


var _lantern: Node2D = null


## Vida (04f 4.24.4): the lantern in the hand of a guard on the night round (game/visuals/props/hand_lantern.tscn).
func set_lantern(on: bool) -> void:
	if on == (_lantern != null):
		return
	if not on:
		_lantern.queue_free()
		_lantern = null
		return
	_lantern = VisualPaths.instantiate("props", "hand_lantern")
	_lantern.name = "Lantern"
	VisualPaths.place(_lantern, Vector2(6, -fig_height * 0.45))
	add_child(_lantern)


func has_lantern() -> bool:
	return _lantern != null


## H7: a phrase over the bubble ("" = none): what a townsperson says when the selected person is near (GDD 4.11.3).
func set_phrase(text: String) -> void:
	if _phrase_label == null:
		if text == "":
			return
		_phrase_label = Label.new()
		_phrase_label.name = "PhraseLabel"
		_phrase_label.z_index = MARKS_Z + 1
		WorldLabels.style(_phrase_label, "phrase")
		_phrase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_phrase_label.size = Vector2(240, 14)
		_phrase_label.position = Vector2(-120, -fig_height - 46)
		_phrase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_phrase_label)
	_phrase_label.text = text
	_phrase_label.visible = text != ""


func phrase() -> String:
	return _phrase_label.text if _phrase_label != null and _phrase_label.visible else ""


## The name over the head (shown when selected or hovered).
func name_label() -> Label:
	return _name_label


## The character's scene (game/visuals/characters), or null before setup.
func visual() -> Node2D:
	return _visual


## The job badge: `c` = colour of the employer family (alpha 0 = none), `own` = it works for the player's family.
func set_badge(c: Color, own: bool) -> void:
	if c == badge and own == badge_own:
		return
	badge = c
	badge_own = own
	if _badge_mark != null:
		_badge_mark.queue_redraw()


## The badge from the state: the family whose building this character works at (none without a job).
func follow_badge(state: WorldState, player_family: String) -> void:
	var fam := SimQuery.employer_family(state, char_id)
	if fam == "":
		set_badge(Color(0, 0, 0, 0), false)
		return
	var colors: Dictionary = state.families.get(fam, {}).get("colors", {})
	set_badge(ViewConfig.color(str(colors.get("primary", "#808080"))), fam == player_family)


## Where the walker is, in tiles (floats between two tiles while walking).
static func tile_position(ch: Dictionary, minutes_per_tile: int, frac: float) -> Vector2:
	var pos: Array = ch.get("position", [0, 0])
	var from := Vector2(float(pos[0]), float(pos[1]))
	var path: Array = ch.get("path", [])
	if path.is_empty():
		return from
	var nxt: Array = path[0]
	var t := clampf((float(ch.get("move_progress", 0)) + frac) / float(maxi(1, minutes_per_tile)), 0.0, 1.0)
	return from.lerp(Vector2(float(nxt[0]), float(nxt[1])), t)


## Follows the state: whole world pixels (D2); walks towards the next tile of its path, idles when it has none.
func follow(ch: Dictionary, minutes_per_tile: int, frac: float) -> void:
	position = Iso.tilef_to_world(tile_position(ch, minutes_per_tile, frac)).round()
	var path: Array = ch.get("path", [])
	if path.is_empty():
		play_motion("idle", facing)
		return
	var pos: Array = ch.get("position", [0, 0])
	var nxt: Array = path[0]
	play_motion("walk", dir_of(Vector2(float(nxt[0]) - float(pos[0]), float(nxt[1]) - float(pos[1]))))


## The facing (s se e ne n nw w sw) of a move of `delta` tiles (col, row), as seen on screen.
static func dir_of(delta: Vector2) -> String:
	if delta.length_squared() < 0.0001:
		return "s"
	var ground := Vector2(delta.x - delta.y, delta.x + delta.y)  # the screen direction, unsquashed (2:1)
	var octant := int(roundf(rad_to_deg(ground.angle()) / 45.0))
	return DIRS[posmod(octant, 8)]


## Plays <motion>_<dir> on the sprite (falls back to idle_<dir>, then <motion>, then idle when the frames lack it).
## No-op without sprite or when it already plays it.
func play_motion(m: String, dir: String) -> void:
	if _sprite == null or (m == motion and dir == facing):
		return
	motion = m
	facing = dir
	var sf := _sprite.sprite_frames
	for a: String in ["%s_%s" % [m, dir], "idle_%s" % dir, m, "idle"]:
		if sf.has_animation(a) and sf.get_frame_count(a) > 0:
			if _sprite.animation != StringName(a) or not _sprite.is_playing():
				_sprite.play(a)
			return


## The animation the sprite plays now ("" without sprite).
func animation_name() -> String:
	return str(_sprite.animation) if _sprite != null else ""


## The clickable figure, in world pixels.
func pick_rect() -> Rect2:
	return Rect2(position + Vector2(-fig_width / 2.0 - 3.0, -fig_height - 2.0), Vector2(fig_width + 6.0, fig_height + 6.0))


## The selection ring (under the figure, which is the child scene).
func _draw() -> void:
	if selected:
		var ring := PackedVector2Array([Vector2(0, -9), Vector2(18, 0), Vector2(0, 9), Vector2(-18, 0), Vector2(0, -9)])
		draw_polyline(ring, Color(1.0, 0.85, 0.3), 2.0)


## The job badge over the head (its own node, over the figure): the employer's colour, gold border if it works for
## the player.
func _draw_badge() -> void:
	if badge.a <= 0.0:
		return
	var c := Vector2(0, -fig_height - 6)
	var d := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
	_badge_mark.draw_colored_polygon(d, badge)
	_badge_mark.draw_polyline(d + PackedVector2Array([d[0]]), badge_border if badge_own else outline,
		2.0 if badge_own else 1.0)
