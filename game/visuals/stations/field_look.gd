class_name FieldLook
extends Node2D
## H12 Patrón (docs/gdd/04d_otras_clases.md 4.22.4.8): the look of a field station of the farm. Draws the bed of
## earth by the field's state with the ground tiles of the map (assets/art/tiles): fallow = bare earth, plowed =
## furrows, growing = sprouts then green rows (by its growth), ready = golden wheat, rotten = the golden wheat gone
## brown; under it, a growth bar while it grows and the days left to harvest while it is ready (red on its last day).
## InteriorStage feeds it Fields.view's row every half second (show_field). Greybox until the field tiles of the
## PixelLab cycle (4.22.9 #2).

const TEX := {"fallow": "res://assets/art/tiles/dirt.png", "plowed": "res://assets/art/tiles/field_winter.png",
	"sprouts": "res://assets/art/tiles/field_spring.png", "green": "res://assets/art/tiles/field_summer.png",
	"ready": "res://assets/art/tiles/field_autumn.png", "rotten": "res://assets/art/tiles/field_autumn.png"}
const SCALE: float = 1.6

var state: String = "plowed"
var growth: float = 0.0       # 0-1 of the way to ready
var days_left: int = -1       # ready: dawns before it rots
var days_to_ready: int = -1   # growing: dawns until ready
var _tex: Dictionary = {}


func show_field(row: Dictionary) -> void:
	var s := str(row.get("state", "fallow"))
	var g := clampf(float(row.get("growth", 0.0)) / maxf(float(row.get("grow", 1.0)), 0.001), 0.0, 1.0)
	var dl := int(row.get("days_left", -1))
	var dr := int(row.get("days_to_ready", -1))
	if s == state and is_equal_approx(g, growth) and dl == days_left and dr == days_to_ready:
		return
	state = s
	growth = g
	days_left = dl
	days_to_ready = dr
	queue_redraw()


func _stage() -> String:
	if state == "growing":
		return "sprouts" if growth < 0.5 else "green"
	return state if TEX.has(state) else "fallow"


func _texture(key: String) -> Texture2D:
	if not _tex.has(key):
		_tex[key] = load(str(TEX[key])) as Texture2D
	return _tex[key]


func _draw() -> void:
	var t := _texture(_stage())
	var w := Iso.TILE_W * SCALE
	var h := Iso.TILE_H * SCALE
	var mod := Color(0.62, 0.5, 0.38) if state == "rotten" else Color.WHITE
	if t != null:
		draw_texture_rect(t, Rect2(-w / 2.0, -h / 2.0, w, h), false, mod)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(-w / 2, 0), Vector2(0, -h / 2), Vector2(w / 2, 0),
			Vector2(0, h / 2)]), Color(0.45, 0.33, 0.2))
	var font := ThemeDB.fallback_font
	if state == "growing":
		var bar := Rect2(-20, h / 2.0 + 2.0, 40, 4)
		draw_rect(bar.grow(1.0), Color(0.1, 0.07, 0.05))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * growth, bar.size.y)), Color(0.49, 0.78, 0.38))
		if days_to_ready >= 0:
			_text(font, Vector2(24, h / 2.0 + 7.0), "%d d" % days_to_ready, Color(0.85, 0.95, 0.7))
	elif state == "ready" and days_left >= 0:
		var c := Color(0.95, 0.35, 0.25) if days_left <= 1 else Color(1.0, 0.85, 0.35)
		_text(font, Vector2(-8, h / 2.0 + 10.0), "%d d" % days_left, c)


func _text(font: Font, at: Vector2, s: String, c: Color) -> void:
	draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0.08, 0.05, 0.03))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c)
