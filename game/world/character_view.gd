class_name CharacterView
extends Node2D
## Greybox walker (H1): a ~48 px figure in its family's colours, at its tile or between two tiles (D3: the sim moves
## by tiles, the view interpolates position -> path[0] with move_progress / minutes_per_tile). Shows its name and a
## ring when selected. Keeps only the character id; reads the rest from the state each frame.
## H4: the name (with the family for people of other families) also shows while the mouse is over the figure
## (hovered); an employee carries a small badge over the head in the colour of the family it works for, with a gold
## border when it works for the player's family (set_badge, data/view.json "character.badge").

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
var skin: Color = Color(0.88, 0.70, 0.55)
var outline: Color = Color(0.12, 0.09, 0.07)
var _name_label: Label


func setup(ch: Dictionary, family: Dictionary) -> void:
	char_id = str(ch["id"])
	female = bool(ch.get("female", false))
	selectable = str(ch.get("controlled_by", "")) == "human"
	var colors: Dictionary = family.get("colors", {})
	primary = ViewConfig.color(str(colors.get("primary", "#808080")))
	secondary = ViewConfig.color(str(colors.get("secondary", "#c0c0c0")))
	var cfg: Dictionary = ViewConfig.value("character", {})
	fig_height = float(cfg.get("height", 48))
	fig_width = float(cfg.get("width", 14))
	skin = ViewConfig.color(str(cfg.get("skin", "#e0b48c")))
	outline = ViewConfig.color(str(cfg.get("outline", "#1e1812")))
	name = char_id
	badge_border = ViewConfig.color(str(cfg.get("badge_own_border", "#ffd84c")))
	_name_label = Label.new()
	_name_label.text = str(ch.get("name", char_id))
	if not selectable and str(family.get("name", "")) != "":
		_name_label.text = "%s · %s" % [str(ch.get("name", char_id)), str(family["name"])]
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_name_label.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.size = Vector2(120, 14)
	_name_label.position = Vector2(-60, -fig_height - 20)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.visible = selected
	add_child(_name_label)
	queue_redraw()


## The job badge: `c` = colour of the employer family (alpha 0 = none), `own` = it works for the player's family.
func set_badge(c: Color, own: bool) -> void:
	if c == badge and own == badge_own:
		return
	badge = c
	badge_own = own
	queue_redraw()


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


## Follows the state: whole world pixels (D2).
func follow(ch: Dictionary, minutes_per_tile: int, frac: float) -> void:
	position = Iso.tilef_to_world(tile_position(ch, minutes_per_tile, frac)).round()


## The clickable figure, in world pixels.
func pick_rect() -> Rect2:
	return Rect2(position + Vector2(-fig_width / 2.0 - 3.0, -fig_height - 2.0), Vector2(fig_width + 6.0, fig_height + 6.0))


func _draw() -> void:
	var w := fig_width
	var h := fig_height
	if selected:
		var ring := PackedVector2Array([Vector2(0, -9), Vector2(18, 0), Vector2(0, 9), Vector2(-18, 0), Vector2(0, -9)])
		draw_polyline(ring, Color(1.0, 0.85, 0.3), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-9, 0), Vector2(0, -4), Vector2(9, 0), Vector2(0, 4)]),
		Color(0, 0, 0, 0.3))
	var head_r := 6.0
	var body_top := -h + head_r * 2.0
	# legs
	draw_rect(Rect2(-w / 2.0 + 2, -12, w / 2.0 - 3, 12), outline)
	draw_rect(Rect2(1, -12, w / 2.0 - 3, 12), outline)
	# body: a dress (wider at the hem) or a tunic
	var body: PackedVector2Array
	if female:
		body = PackedVector2Array([Vector2(-w / 2.0 + 1, body_top), Vector2(w / 2.0 - 1, body_top),
			Vector2(w / 2.0 + 3, -4), Vector2(-w / 2.0 - 3, -4)])
	else:
		body = PackedVector2Array([Vector2(-w / 2.0, body_top), Vector2(w / 2.0, body_top), Vector2(w / 2.0, -11),
			Vector2(-w / 2.0, -11)])
	draw_colored_polygon(body, primary)
	draw_polyline(body + PackedVector2Array([body[0]]), outline, 1.0)
	draw_rect(Rect2(-w / 2.0, body_top + 12, w, 3), secondary)
	# head
	draw_circle(Vector2(0, -h + head_r), head_r + 1.0, outline)
	draw_circle(Vector2(0, -h + head_r), head_r, skin)
	if badge.a > 0.0:
		# a small diamond over the head: the employer's colour, gold border if it works for the player
		var c := Vector2(0, -h - 6)
		var d := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
		draw_colored_polygon(d, badge)
		draw_polyline(d + PackedVector2Array([d[0]]), badge_border if badge_own else outline, 2.0 if badge_own else 1.0)
