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
var window_from: float = -1.0   # the master-touch window as fractions of the cycle (-1: none), drawn in gold on the bar
var window_to: float = -1.0
var blocked: bool = false
var night: bool = false         # set by the interior: an empty station shows the moon instead of the idle mark
var productive: bool = true    # a station with recipes (furnace, anvil): only these show the status mark
var marks: Array = []          # numbers of the selected person's waiting orders that come here (active pause)
var _icons: Dictionary = {}     # status -> 16 px icon (docs/ui/mecanicas/forja_interior.md §3)
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
	_label.position = Vector2(-60, 6)
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
	WorldLabels.style(l, "flash" if font_size > 9 else "station", c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(120, 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Follows the sim's view of the job: {} or {actor, recipe, mode, progress, window_open, touched}.
func show_job(job: Dictionary, has_occupant: bool) -> void:
	var p := float(job.get("progress", -1.0)) if not job.is_empty() else -1.0
	var w := bool(job.get("window_open", false))
	var t := bool(job.get("touched", false))
	var wf := float(job.get("window_from", -1.0))
	var wt := float(job.get("window_to", -1.0))
	var bl := bool(job.get("blocked", false))
	if p != progress or w != window_open or t != touched or has_occupant != occupied or wf != window_from \
			or wt != window_to or bl != blocked:
		progress = p
		window_open = w
		touched = t
		occupied = has_occupant
		window_from = wf
		window_to = wt
		blocked = bl
		queue_redraw()


## What the station's mark says: "window" (the master touch is open), "blocked" (stopped: storage full, no
## inputs), "working", "night" (nobody, at night) or "idle".
func status() -> String:
	if progress >= 0.0 and window_open and not touched:
		return "window"
	if blocked:
		return "blocked"
	if progress >= 0.0:
		return "working"
	return "night" if night else "idle"


func _icon(st: String) -> Texture2D:
	if not _icons.has(st):
		var name_ := {"window": "icon_working", "blocked": "icon_warning", "working": "icon_working", "night": "icon_moon",
			"idle": "icon_idle"}[st] as String
		_icons[st] = UiIcons.ui(name_)
	return _icons[st]


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
	var top := -height - hh - 12
	if progress >= 0.0:
		var bar := Rect2(-22, top, 44, 6)
		draw_rect(bar.grow(1.0), Color(0.1, 0.07, 0.05))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y)), progress_color)
		if window_from >= 0.0 and window_to > window_from:
			# the master-touch window, seen from the first minute of the cycle: dim gold before, bright while open,
			# grey once it closed without a touch, with a check once given (forja_interior.md §4.2)
			var wr := Rect2(bar.position.x + roundf(bar.size.x * window_from), bar.position.y + bar.size.y - 2.0,
				maxf(2.0, roundf(bar.size.x * (window_to - window_from))), 2.0)
			var c := window_color.darkened(0.45)
			if window_open and not touched:
				c = window_color
			elif progress > window_to and not touched:
				c = Color(0.45, 0.42, 0.38)
			draw_rect(wr, c)
			if touched:
				draw_line(wr.position + Vector2(0, -3), wr.position + Vector2(2, -1), window_color, 1.0)
				draw_line(wr.position + Vector2(2, -1), wr.position + Vector2(6, -5), window_color, 1.0)
		if touched:
			draw_rect(bar.grow(1.0), window_color, false, 1.0)
	for i: int in marks.size():
		# right over the station's top (beside its bar when it has one), one after the other
		var at := Vector2(-5.0 * float(marks.size() - 1) + 11.0 * i, -height - 6.0) if progress < 0.0 \
			else Vector2(28.0 + 11.0 * i, top + 3.0)
		draw_circle(at, 5.0, window_color.darkened(0.1))
		draw_arc(at, 5.5, 0.0, TAU, 14, Color(0.1, 0.07, 0.05), 1.0)
		_draw_digit(at, int(marks[i]))
	var tex := _icon(status()) if productive else null
	if tex != null and (status() != "window" or int(_t * blink_hz * 2.0) % 2 == 0):
		var y := top - 18.0 if progress >= 0.0 else -height - 20.0
		draw_texture(tex, Vector2(-8, y).round(), Color(1, 0.9, 0.5) if status() == "window" else Color.WHITE)


## A small dark digit (1-9) centred on `at`, drawn by pixels (the marks of the active pause).
func _draw_digit(at: Vector2, n: int) -> void:
	const DIGITS := {1: ["010", "110", "010", "010", "111"], 2: ["111", "001", "111", "100", "111"],
		3: ["111", "001", "011", "001", "111"], 4: ["101", "101", "111", "001", "001"], 5: ["111", "100", "111", "001", "111"],
		6: ["111", "100", "111", "101", "111"], 7: ["111", "001", "010", "010", "010"], 8: ["111", "101", "111", "101", "111"],
		9: ["111", "101", "111", "001", "111"]}
	var rows: Array = DIGITS.get(clampi(n, 1, 9), DIGITS[9])
	var o := (at - Vector2(1.5, 2.5)).round()
	for y: int in rows.size():
		for x: int in 3:
			if str(rows[y])[x] == "1":
				draw_rect(Rect2(o + Vector2(x, y), Vector2.ONE), Color(0.1, 0.07, 0.05))
