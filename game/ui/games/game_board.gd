class_name GameBoard
extends Control
## The board of a game's screen (docs/ui/mecanicas/juegos.md; rules: sim/games/): the game's own picture in the middle
## of GameScreen, and the texts of its decision box. One subclass per kind of game (BoardDice, BoardPulso, ...).
## Reads the match's view; gives no orders. Drawn by code because it changes every step (dice, arms, positions); the
## fixed pieces (the table, the dice, the cards) come from VisualPaths.game_art when the art exists, else a greybox
## with a label that says what is missing.
##
## show_view(m, v, names): the state to draw now. play(entries): animates the new log entries one after the other and
## emits `shown` when it ends (instantly with fast). info(v) -> {title, text, read}: the texts of the decision box.

signal shown

const INK: Color = Color(0.93, 0.87, 0.74)
const DIM: Color = Color(0.62, 0.55, 0.45)
const GOLD: Color = Color(0.85, 0.68, 0.24)
const RED: Color = Color(0.7, 0.22, 0.18)
const GREEN: Color = Color(0.36, 0.58, 0.3)
const FELT: Color = Color(0.17, 0.25, 0.17)
const WOOD: Color = Color(0.29, 0.2, 0.13)

var m: GameMatch = null
var v: Dictionary = {}
var names: Array = []
var me: int = 0
var _queue: Array = []
var _t: float = 0.0
var _step_time: float = 0.35
var playing: bool = false
var missing: Array[String] = []   # the art pieces drawn as greybox (the screen and the smoke say it)


func show_view(match_: GameMatch, view: Dictionary, who: Array) -> void:
	m = match_
	v = view
	names = who
	queue_redraw()


## Animates `entries` (new log entries) one after the other; `shown` at the end.
func play(entries: Array, fast: bool = false) -> void:
	_queue = entries.duplicate()
	_t = 0.0
	playing = not _queue.is_empty() and not fast
	if not playing:
		_queue.clear()
		_on_entries_done()
		shown.emit()
		return
	_start_entry(_queue[0])


func _process(delta: float) -> void:
	if not playing:
		return
	_t += delta
	_animate(_t / _step_time)
	if _t >= _step_time:
		_t = 0.0
		_end_entry(_queue.pop_front())
		if _queue.is_empty():
			playing = false
			_on_entries_done()
			queue_redraw()
			shown.emit()
		else:
			_start_entry(_queue[0])
	queue_redraw()


## The texts of the decision box while an animation plays (the result is not told before it is seen).
func info_busy() -> Dictionary:
	return {"title": tr("games.ui.playing"), "text": "", "read": ""}


## The texts of the decision box: {title, text, read}.
func info(_view: Dictionary) -> Dictionary:
	return {"title": "", "text": "", "read": ""}


## The entries of the match not shown yet (and marks them as shown): what play() animates.
func new_entries(_m: GameMatch) -> Array:
	return []


## Forgets what was shown (a new game on the same board).
func reset() -> void:
	_queue.clear()
	playing = false


## A line of the log for an entry ("" = none).
func log_line(_entry: Dictionary) -> String:
	return ""


func _start_entry(_e: Dictionary) -> void:
	pass


func _end_entry(_e: Dictionary) -> void:
	pass


func _animate(_k: float) -> void:
	pass


func _on_entries_done() -> void:
	pass


func who(side: int) -> String:
	return str(names[side]) if side >= 0 and side < names.size() else "?"


# --- Drawing helpers -------------------------------------------------------------------------------------------------

## A fixed piece of art filling `r` (cropped to its proportions, never stretched), or its greybox with a label (and the
## id noted in `missing`).
func art_or_box(game: String, id: String, r: Rect2, color: Color, label: String = "") -> void:
	var tex := VisualPaths.game_art(game, id)
	if tex != null:
		# fill the rect at a whole scale when the art is big enough (the boards' backgrounds come at ×2: ½ = its native
		# pixels; else 1:1), cropped from the bottom centre; a smaller art fills it keeping its proportions
		var ts := tex.get_size()
		var src := Rect2(Vector2.ZERO, ts)
		var k := 2.0 if ts.x >= r.size.x * 2.0 and ts.y >= r.size.y * 2.0 else (1.0 if ts.x >= r.size.x and ts.y >= r.size.y else 0.0)
		if k > 0.0:
			src.size = r.size * k
			src.position = Vector2((ts.x - src.size.x) / 2.0, ts.y - src.size.y)
		elif ts.x / ts.y > r.size.x / r.size.y:
			src.size.x = ts.y * r.size.x / r.size.y
			src.position.x = (ts.x - src.size.x) / 2.0
		else:
			src.size.y = ts.x * r.size.y / r.size.x
			src.position.y = ts.y - src.size.y
		draw_texture_rect_region(tex, r, src)
		draw_rect(r, Color(0, 0, 0, 0.18))  # a veil: the board's texts read over the art
		return
	if not "%s/%s" % [game, id] in missing:
		missing.append("%s/%s" % [game, id])
	draw_rect(r, color)
	draw_rect(r, color.darkened(0.45), false, 1.0)
	if label != "":
		text(Vector2(r.position.x + 4, r.end.y - 4), label, DIM.darkened(0.2), 8)


## Text in the theme's pixel fonts at a crisp size: below 12 the small font at 8, else the body font at 16 (32 from
## 24 up). Right or centre alignment without a width aligns on `at`.
func text(at: Vector2, s: String, color: Color = INK, size_px: int = 16, width: float = -1.0,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var small := size_px < 12
	var f := get_theme_font("font", &"SmallLabel") if small else get_theme_default_font()
	if f == null:
		return
	var fs := 8 if small else (16 if size_px < 24 else 32)
	var pos := at
	if width < 0.0 and align != HORIZONTAL_ALIGNMENT_LEFT:
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		pos.x -= w if align == HORIZONTAL_ALIGNMENT_RIGHT else w / 2.0
		align = HORIZONTAL_ALIGNMENT_LEFT
	draw_string(f, pos, s, align, width, fs, color)


## A die showing `n` (1-6; 0 = under the cup) with its top-left at `at` and side `side`.
func die(at: Vector2, n: int, side: float = 18.0, hot: bool = false) -> void:
	var r := Rect2(at, Vector2(side, side))
	if n <= 0:
		var cup := VisualPaths.game_art("dice", "cup")
		if cup != null:
			draw_texture_rect(cup, r.grow(2), false)
		else:
			if not "dice/cup" in missing:
				missing.append("dice/cup")
			draw_rect(r.grow(1), WOOD.darkened(0.2))
			draw_rect(r.grow(1), Color.BLACK, false, 1.0)
			text(at + Vector2(side * 0.32, side * 0.72), "?", DIM, int(side * 0.6))
		return
	var tex := VisualPaths.game_art("dice", "die_%d" % n)
	if tex != null:
		var sh := VisualPaths.game_art("dice", "shadow")
		if sh != null:
			draw_texture_rect(sh, Rect2(at + Vector2(0, side * 0.8), Vector2(side, side / 3.0)), false)
		draw_texture_rect(tex, r, false)
	else:
		if not "dice/die" in missing:
			missing.append("dice/die")
		draw_rect(r, Color(0.93, 0.9, 0.82))
		draw_rect(r, Color(0.2, 0.15, 0.1), false, 1.0)
		var pip := maxf(1.5, side * 0.1)
		for p: Vector2 in _pips(n):
			draw_circle(at + p * side, pip, Color(0.15, 0.1, 0.08))
	if hot:
		draw_rect(r.grow(2), GOLD, false, 1.0)


static func _pips(n: int) -> Array:
	var c := Vector2(0.5, 0.5)
	var a := Vector2(0.25, 0.25)
	var b := Vector2(0.75, 0.75)
	var e := Vector2(0.75, 0.25)
	var f := Vector2(0.25, 0.75)
	match n:
		1:
			return [c]
		2:
			return [a, b]
		3:
			return [a, c, b]
		4:
			return [a, b, e, f]
		5:
			return [a, b, e, f, c]
	return [a, b, e, f, Vector2(0.25, 0.5), Vector2(0.75, 0.5)]


## A bar of `value` of `max_value` pips.
func pips(at: Vector2, value: int, max_value: int, color: Color, size: float = 7.0) -> void:
	for i: int in max_value:
		var r := Rect2(at + Vector2(i * (size + 2.0), 0), Vector2(size, size))
		draw_rect(r, color if i < value else Color(0.18, 0.14, 0.11))
		draw_rect(r, Color(0.07, 0.05, 0.04), false, 1.0)
