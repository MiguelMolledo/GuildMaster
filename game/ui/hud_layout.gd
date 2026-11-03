class_name HudLayout
extends RefCounted
## Layout rules of the HUD that keep its panels from covering each other (pure: the tests check them without a HUD).
## The fixed zones of docs/ui/01_hud.md §4 at 960×540 (margin 4, gap 4): hud.tscn places one Control per zone with
## these rects; on a wider or taller window (stretch aspect "expand") the right zones follow the right edge and the
## bottom ones the bottom edge (`zones`).

const BASE: Vector2 = Vector2(960, 540)
const ZONES: Dictionary = {
	"card": Rect2(4, 4, 236, 50),          # 1 · portraits of the group + name, gold, title of the active one
	"status": Rect2(244, 4, 472, 28),      # 2 · debt, panel buttons with their key, menu
	"clock": Rect2(720, 4, 236, 50),       # 3 · time, date, phase, pause and speeds
	"column": Rect2(4, 58, 236, 186),      # 4 · objective (folds) and the queued orders
	"manage": Rect2(600, 58, 356, 430),    # 5 · one management panel at a time
	"selection": Rect2(244, 492, 472, 44), # 6 · what is selected; inside, the building's bar
	"notices": Rect2(4, 404, 236, 132),    # 7 · pop-up notices, bottom up, 3 at most
}
const FIXED: Array[String] = ["card", "status", "clock", "column", "manage", "selection", "notices"]
const VIEW: Rect2 = Rect2(244, 58, 352, 430)   # the free view between the column and the management panel
const BIG_MODAL: Vector2 = Vector2(912, 440)   # family tree, chart, chronicle (§4.7)


## The zones for a viewport of `size` (the 960×540 rects moved with the right / bottom edges).
static func zones(size: Vector2 = BASE) -> Dictionary:
	var dx := size.x - BASE.x
	var dy := size.y - BASE.y
	var out := {}
	for k: String in ZONES:
		var r: Rect2 = ZONES[k]
		match k:
			"clock", "manage":
				r.position.x += dx
			"status":
				r.position.x += dx / 2.0
			"selection":
				r.position += Vector2(dx / 2.0, dy)
			"notices":
				r.position.y += dy
		out[k] = r
	return out


## Pairs of fixed zones that overlap (none: §4, "ninguna zona fija se solapa con otra").
static func overlaps(z: Dictionary) -> Array:
	var out: Array = []
	for i: int in FIXED.size():
		for j: int in range(i + 1, FIXED.size()):
			var a: Rect2 = z[FIXED[i]]
			var b: Rect2 = z[FIXED[j]]
			if a.intersects(b):
				out.append([FIXED[i], FIXED[j]])
	return out


## The rect of a big modal (912×440) on a viewport of `size`: centred across, under the top bar (the HUD above stays
## in sight).
static func big_modal(size: Vector2 = BASE) -> Rect2:
	return Rect2(Vector2(roundf((size.x - BIG_MODAL.x) / 2.0), 58.0), BIG_MODAL)


## The free view between the column and the management panel, under the top bar and over the selection bar
## ([244, 58, 352, 430] at 960×540).
static func view_rect(size: Vector2 = BASE) -> Rect2:
	var z := zones(size)
	var left: float = (z["column"] as Rect2).end.x + 4.0
	var top: float = (z["column"] as Rect2).position.y
	return Rect2(left, top, (z["manage"] as Rect2).position.x - 4.0 - left, (z["selection"] as Rect2).position.y - 4.0 - top)


## The centre of the free view (the interior is drawn there, not in the middle of the screen).
static func view_center(size: Vector2 = BASE) -> Vector2:
	return view_rect(size).get_center().round()


## Whether the objective folds to its title and progress: the column (objective + queue) must fit `column_h`
## (§4.3, "la columna se pliega antes que solaparse").
static func fold_objective(unfolded_h: float, queue_h: float, column_h: float = 186.0, gap: float = 4.0) -> bool:
	return queue_h > 0.0 and unfolded_h + gap + queue_h > column_h


## How much the camera must move (in screen pixels, for WorldCamera.pan) so that `point` (a screen position) under
## one of the `blocked` rects (the management panel, the selection bar) lands in the `free` view (§4.6: "lo justo");
## ZERO if nothing covers it.
static func reveal_delta(point: Vector2, blocked: Array, free: Rect2, margin: float = 24.0) -> Vector2:
	var hidden := false
	for r: Rect2 in blocked:
		if r.has_point(point):
			hidden = true
	if not hidden:
		return Vector2.ZERO
	var inner := free.grow(-margin)
	var target := point.clamp(inner.position, inner.end)
	return point - target


## The gravity of a pop-up notice (§5): "urgent", "warning", "done" or "" (info: only in the book).
## `done_keys`: the notice keys that are a goal met (data/view.json notices.done_keys).
static func notice_gravity(severity: String, key: String, done_keys: Array) -> String:
	if key in done_keys:
		return "done"
	if severity == "urgent" or severity == "warning":
		return severity
	return ""


## Notices on screen after one more arrives: at most `max_n`, the oldest goes (it stays in the book).
static func push_notice(shown: Array, n: Variant, max_n: int = 3) -> Array:
	var out := shown.duplicate()
	out.append(n)
	while out.size() > max_n:
		out.pop_front()
	return out


## Whether the objective's how-to is unfolded: inside a building always; on the map only while it is new
## (`seconds_left` > 0) or while the mouse is over the panel, so the folded panel covers less of the town.
static func hint_shown(has_text: bool, interior_open: bool, seconds_left: float, mouse_over: bool) -> bool:
	return has_text and (interior_open or seconds_left > 0.0 or mouse_over)
