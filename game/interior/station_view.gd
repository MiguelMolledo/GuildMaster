class_name StationView
extends Node2D
## One station of an interior (H2 greybox): its look (the station's scene, game/visuals/stations/<zone>.tscn or the
## child of its Marker2D in the interior scene, drawn behind) with its name, on its floor tile. Shows what the sim says
## (SimQuery.job_view): an occupied mark, the progress bar of the cycle, the master-touch window (the look blinks
## while it is open, GDD 4.4.5) and a short floating text (master touch done, item made). The look's Top marker gives
## the station's height (bar, marks, click area).

var zone: String = ""
var title: String = ""
var height: float = 20.0
var busy_color: Color = Color(0.94, 0.75, 0.25)
var progress_color: Color = Color(0.49, 0.78, 0.38)
var window_color: Color = Color(1.0, 0.94, 0.63)
var blink_hz: float = 3.0
var occupied: bool = false
var progress: float = -1.0      # -1 = no job
var window_open: bool = false
var touched: bool = false
var _t: float = 0.0
var _flash_text: String = ""
var _flash_left: float = 0.0
var _flash_seconds: float = 1.5
var _label: Label
var _flash: Label
var _look: Node2D = null


## `look` = the station's scene (null: game/visuals/stations/<zone>.tscn).
func setup(zone_id: String, text: String, cfg: Dictionary, look: Node2D = null) -> void:
	zone = zone_id
	title = text
	name = zone_id
	_look = look if look != null else VisualPaths.instantiate("stations", zone_id)
	_look.name = "Look"
	_look.show_behind_parent = true
	VisualPaths.place(_look, Vector2.ZERO)
	add_child(_look)
	height = VisualPaths.top_height(_look, 20.0)
	busy_color = ViewConfig.color(str(cfg.get("busy", "#f0c040")))
	progress_color = ViewConfig.color(str(cfg.get("progress", "#7cc860")))
	window_color = ViewConfig.color(str(cfg.get("window", "#fff0a0")))
	blink_hz = float(cfg.get("blink_hz", 3.0))
	_flash_seconds = float(cfg.get("touch_feedback_seconds", 1.5))
	_label = _make_label(text, Color(1.0, 0.95, 0.8), 9)
	_label.position = Vector2(-40, 6)
	_flash = _make_label("", Color(1.0, 0.9, 0.4), 10)
	_flash.visible = false
	add_child(_label)
	add_child(_flash)


## The station's scene (its look).
func look() -> Node2D:
	return _look


func _make_label(text: String, c: Color, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(80, 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Follows the sim's view of the job: {} or {actor, recipe, mode, progress, window_open, touched}.
func show_job(job: Dictionary, has_occupant: bool) -> void:
	var p := float(job.get("progress", -1.0)) if not job.is_empty() else -1.0
	var w := bool(job.get("window_open", false))
	var t := bool(job.get("touched", false))
	if p != progress or w != window_open or t != touched or has_occupant != occupied:
		progress = p
		window_open = w
		touched = t
		occupied = has_occupant
		queue_redraw()


## A short text over the station (the master touch landed, an item came out...).
func flash(text: String) -> void:
	_flash_text = text
	_flash_left = _flash_seconds
	_flash.text = text
	_flash.size = Vector2(160, 14)
	_flash.position = Vector2(-80, -height - 44)
	_flash.visible = true
	queue_redraw()


func flash_text() -> String:
	return _flash_text if _flash_left > 0.0 else ""


func _process(delta: float) -> void:
	_t += delta
	if _flash_left > 0.0:
		_flash_left -= delta
		_flash.position.y -= delta * 10.0
		if _flash_left <= 0.0:
			_flash.visible = false
	_blink()
	if window_open or _flash_left > 0.0:
		queue_redraw()


## The master-touch window: the greybox block blinks towards the window colour; a sprite look (its Greybox hidden or
## gone) is tinted instead.
func _blink() -> void:
	if _look == null:
		return
	var k := 0.35 + 0.35 * sin(_t * TAU * blink_hz) if window_open and not touched else 0.0
	var gb := _look.get_node_or_null("Greybox") as StationBlock
	if gb != null and gb.visible:
		gb.highlight_color = window_color
		gb.highlight = k
	else:
		_look.modulate = Color.WHITE.lerp(window_color, k)


## The block's drawn volume (local pixels): clicks inside it hit the station.
func pick_polygon() -> PackedVector2Array:
	var hw := Iso.TILE_W / 2.0 * 0.75
	var hh := Iso.TILE_H / 2.0 * 0.75
	return PackedVector2Array([Vector2(-hw, 0), Vector2(-hw, -height), Vector2(0, -hh - height), Vector2(hw, -height),
		Vector2(hw, 0), Vector2(0, hh)])


func _draw() -> void:
	var hw := Iso.TILE_W / 2.0 * 0.75
	var hh := Iso.TILE_H / 2.0 * 0.75
	if window_open and not touched:
		draw_polyline(pick_polygon() + PackedVector2Array([pick_polygon()[0]]), window_color, 2.0)
	if occupied:
		draw_circle(Vector2(hw - 4, -height - 4), 3.5, busy_color)
		draw_arc(Vector2(hw - 4, -height - 4), 4.5, 0.0, TAU, 12, Color(0.1, 0.07, 0.05), 1.0)
	if progress >= 0.0:
		var bar := Rect2(-22, -height - hh - 12, 44, 6)
		draw_rect(bar.grow(1.0), Color(0.1, 0.07, 0.05))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y)), progress_color)
		if touched:
			draw_rect(bar.grow(1.0), window_color, false, 1.0)
