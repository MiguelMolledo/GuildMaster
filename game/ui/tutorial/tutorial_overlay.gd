class_name TutorialOverlay
extends Control
## The focus of the tutorial (docs/ui/05_tutorial.md §5): darkens everything but the target's rect, frames it in a
## gold line that beats, points at it with an arrow and places the card where it does not cover it. Drawn every frame
## (the target moves: panels slide in with UiAnim, people walk). Guided mode: the veil takes the clicks outside the
## hole, the card and the pass-through rects (pause and speeds); keys are never taken. Without a target there is no
## veil and the card sits in the middle of the free view. A hint is the frame, the arrow and the card, without veil.

const MARGIN: float = 4.0

var avoid: Rect2 = Rect2()   # the panel that holds the target: the card keeps off it when it can
var look: Dictionary = {}
var hole: Rect2 = Rect2()       # the target on screen (no area = none)
var veil_on: bool = false
var guided: bool = false
var pass_rects: Array = []      # Rect2 that also take clicks in guided mode
var free_view: Rect2 = Rect2(244, 58, 352, 430)
var card_side: String = ""      # where the card went: below | above | right | left | free
var _t: float = 0.0

@onready var card: TutorialCard = %Card


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _bind() -> void:
	if card == null:
		card = get_node("%Card") as TutorialCard


## Shows the focus on `rect` (no area = no target), with the veil or not, the card `data` placed beside it.
func show_focus(rect: Rect2, veil: bool, guide: bool, passing: Array, data: Dictionary) -> void:
	_bind()
	visible = true
	hole = rect.grow(float(look.get("pad", 3))) if rect.has_area() else Rect2()
	veil_on = veil and hole.has_area()
	guided = guide and veil_on
	pass_rects = passing
	mouse_filter = Control.MOUSE_FILTER_STOP if guided else Control.MOUSE_FILTER_IGNORE
	card.show_card(data)
	place_card()
	queue_redraw()


func hide_all() -> void:
	_bind()
	if not visible and not card.visible:
		return
	visible = false
	hole = Rect2()
	veil_on = false
	guided = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.close()


func screen_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(960, 540)


## The card under the target; else above, right or left; never over the target nor off the screen. No target: the
## middle of the free view.
func place_card() -> void:
	var sz := card.get_combined_minimum_size()
	sz.x = maxf(sz.x, float(look.get("card_width", 236)))
	card.size = sz
	var scr := Rect2(Vector2.ZERO, screen_size()).grow(-MARGIN)
	if not hole.has_area():   # the middle of the free view, or its top or bottom when a docked card is there
		var stack: Array = PageCard.stack().map(func(pc: PageCard) -> Rect2: return pc.get_global_rect().grow(2.0))
		var fc := free_view.get_center()
		card.position = (fc - sz / 2.0).round()
		for p: Vector2 in [fc - sz / 2.0, Vector2(fc.x - sz.x / 2.0, free_view.end.y - sz.y),
				Vector2(fc.x - sz.x / 2.0, free_view.position.y), Vector2(free_view.position.x, fc.y - sz.y / 2.0)]:
			if not stack.any(func(o: Rect2) -> bool: return Rect2(p, sz).intersects(o)):
				card.position = _clamp(p, sz, scr).round()
				break
		card_side = "free"
		return
	var gap := float(look.get("card_gap", 10))
	var c := hole.get_center()
	var tries: Array = [
		["below", Vector2(c.x - sz.x / 2.0, hole.end.y + gap)],
		["above", Vector2(c.x - sz.x / 2.0, hole.position.y - gap - sz.y)],
		["right", Vector2(hole.end.x + gap, c.y - sz.y / 2.0)],
		["left", Vector2(hole.position.x - gap - sz.x, c.y - sz.y / 2.0)],
	]
	# The docked cards of the side stack (a feast, «Nuevo: …») are not covered either (jugador J3).
	var cards: Array = PageCard.stack().map(func(pc: PageCard) -> Rect2: return pc.get_global_rect().grow(2.0))
	var a := avoid.merge(hole) if avoid.has_area() else hole
	var ac := a.get_center()
	var around := [["below", Vector2(ac.x - sz.x / 2.0, a.end.y + gap)], ["above", Vector2(ac.x - sz.x / 2.0,
		a.position.y - gap - sz.y)], ["right", Vector2(a.end.x + gap, c.y - sz.y / 2.0)],
		["left", Vector2(a.position.x - gap - sz.x, c.y - sz.y / 2.0)]]
	# first beside the whole panel that holds the target (its other rows stay free) and off the stack; then off the
	# panel even over the stack (a notice covered is better than the panel to use); then beside the target alone
	for pass_: Array in [[around, a, cards], [around, a, []], [tries, hole, cards], [tries, hole, []]]:
		for t: Array in pass_[0]:
			var p := _clamp(t[1] as Vector2, sz, scr)
			var r := Rect2(p, sz)
			if r.intersects((pass_[1] as Rect2).grow(2.0)) or (pass_[2] as Array).any(func(o: Rect2) -> bool:
					return r.intersects(o)):
				continue
			card.position = p.round()
			card_side = str(t[0])
			return
	card.position = _clamp(Vector2(free_view.get_center().x - sz.x / 2.0, scr.end.y - sz.y), sz, scr).round()
	card_side = "free"


static func _clamp(p: Vector2, sz: Vector2, scr: Rect2) -> Vector2:
	return Vector2(clampf(p.x, scr.position.x, maxf(scr.position.x, scr.end.x - sz.x)),
		clampf(p.y, scr.position.y, maxf(scr.position.y, scr.end.y - sz.y)))


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if hole.has_area():
		place_card()
	queue_redraw()


## The pulse now: 0 → 1 → 0 over pulse_seconds, in whole steps of `pulse_grow` pixels.
func pulse() -> float:
	var period := maxf(0.1, float(look.get("pulse_seconds", 0.9)))
	return 0.5 - 0.5 * cos(TAU * fmod(_t, period) / period)


func _draw() -> void:
	var scr := Rect2(Vector2.ZERO, screen_size())
	if veil_on:
		var col := Color.html(str(look.get("veil", "#1a1209")))
		col.a = float(look.get("veil_alpha", 0.62))
		var h := hole.intersection(scr)
		draw_rect(Rect2(scr.position, Vector2(scr.size.x, h.position.y)), col)
		draw_rect(Rect2(0, h.end.y, scr.size.x, scr.end.y - h.end.y), col)
		draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), col)
		draw_rect(Rect2(h.end.x, h.position.y, scr.end.x - h.end.x, h.size.y), col)
	if not hole.has_area():
		return
	var gold := Color.html(str(look.get("frame", "#c8a84e")))
	var p := pulse()
	var grow := roundf(p * float(look.get("pulse_grow", 2)))
	var w := float(look.get("frame_width", 2))
	var fr := hole.grow(grow + w / 2.0)
	fr = Rect2(fr.position.round(), fr.size.round())
	var c := gold
	c.a = 0.55 + 0.45 * (1.0 - p)
	draw_rect(fr, c, false, w)
	_draw_arrow(gold, p)


## A gold triangle between the card and the target, pointing at the target, bobbing a couple of pixels.
func _draw_arrow(gold: Color, p: float) -> void:
	if card_side == "free" or card_side == "" or not card.visible:
		return
	var s := float(look.get("arrow", 7))
	var bob := roundf(p * float(look.get("arrow_bob", 2)))
	var cr := Rect2(card.position, card.size)
	var tip := Vector2.ZERO
	var dir := Vector2.ZERO
	match card_side:
		"below":
			tip = Vector2(clampf(hole.get_center().x, cr.position.x + s, cr.end.x - s), hole.end.y + 2.0 + bob)
			dir = Vector2.UP
		"above":
			tip = Vector2(clampf(hole.get_center().x, cr.position.x + s, cr.end.x - s), hole.position.y - 2.0 - bob)
			dir = Vector2.DOWN
		"right":
			tip = Vector2(hole.end.x + 2.0 + bob, clampf(hole.get_center().y, cr.position.y + s, cr.end.y - s))
			dir = Vector2.LEFT
		"left":
			tip = Vector2(hole.position.x - 2.0 - bob, clampf(hole.get_center().y, cr.position.y + s, cr.end.y - s))
			dir = Vector2.RIGHT
	tip = tip.round()
	var back := tip - dir * s
	var side := Vector2(-dir.y, dir.x) * s * 0.75
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), gold)


## Guided mode: the click goes through inside the hole and the pass-through rects (the card is a child: it is picked
## before this).
func _has_point(point: Vector2) -> bool:
	if not guided:
		return false
	if hole.has_point(point):
		return false
	for r: Variant in pass_rects:
		if (r as Rect2).has_point(point):
			return false
	return true
