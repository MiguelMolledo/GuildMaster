@tool
class_name GreyboxFigure
extends Node2D
## Greybox walker (H1): a ~48 px figure, its shadow, a dress or a tunic, and (H8) the hair. The CharacterView that wraps it gives it the
## family's colours (primary, secondary). Delete it (or hide it) when the character's SpriteFrames get their frames.

@export var female: bool = false:
	set(v):
		female = v
		queue_redraw()
@export var height: float = 48.0:
	set(v):
		height = v
		queue_redraw()
@export var width: float = 14.0:
	set(v):
		width = v
		queue_redraw()
@export var skin: Color = Color(0.878431, 0.705882, 0.54902):
	set(v):
		skin = v
		queue_redraw()
## H8 identity (GDD 4.10.9): the hair tone of the palette swap (the game sets the person's, Identity).
@export var hair: Color = Color(0.352941, 0.227451, 0.133333):
	set(v):
		hair = v
		queue_redraw()
@export var outline: Color = Color(0.117647, 0.094118, 0.070588):
	set(v):
		outline = v
		queue_redraw()
## Family colours: the preview ones here; the game sets the family's.
@export var primary: Color = Color(0.5, 0.5, 0.5):
	set(v):
		primary = v
		queue_redraw()
@export var secondary: Color = Color(0.8, 0.8, 0.8):
	set(v):
		secondary = v
		queue_redraw()


func _draw() -> void:
	var w := width
	var h := height
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
	# hair: a cap over the head, longer at the sides for a woman
	var top := Vector2(0, -h + head_r)
	var cap := PackedVector2Array([top + Vector2(-head_r, 1), top + Vector2(-head_r + 1, -3), top + Vector2(-3, -head_r),
		top + Vector2(3, -head_r), top + Vector2(head_r - 1, -3), top + Vector2(head_r, 1), top + Vector2(3, -2),
		top + Vector2(-3, -2)])
	draw_colored_polygon(cap, hair)
	if female:
		draw_rect(Rect2(top.x - head_r - 1, top.y - 1, 3, head_r + 4), hair)
		draw_rect(Rect2(top.x + head_r - 2, top.y - 1, 3, head_r + 4), hair)
