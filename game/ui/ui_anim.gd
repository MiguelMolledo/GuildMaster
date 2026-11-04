class_name UiAnim
extends RefCounted
## The UI's short animations (docs/ui/00_lenguaje_visual.md §8): whole-pixel steps, no easing of colours, never
## blocking the input, running while the game is paused (they are the view's). A panel comes in from its edge (8 → 4 → 0
## px in 3 steps, alpha in 2: 0.12 s); a pop-up notice slides in from the left in 4 steps (0.15 s); a gold figure
## counts up or down to its new value (0.4 s) and a «+42» / «−16» rises 8 px from it and fades (0.8 s).

const PANEL_STEPS: Array[float] = [8.0, 4.0, 0.0]
const PANEL_SECONDS: float = 0.12
const NOTICE_STEPS: Array[float] = [-24.0, -16.0, -8.0, 0.0]
const NOTICE_SECONDS: float = 0.15
const COUNT_SECONDS: float = 0.4
const FLOAT_SECONDS: float = 0.8
const FLOAT_RISE: float = 8.0


## `c` comes in from the right (dir 1) or the left (dir -1) by whole pixels, fading in. Its own position is put back.
static func panel_in(c: Control, dir: float = 1.0) -> void:
	if not c.is_inside_tree():
		return
	var base := c.position.x
	var t := c.create_tween()
	t.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var step := PANEL_SECONDS / float(PANEL_STEPS.size())
	c.modulate.a = 0.0
	for i: int in PANEL_STEPS.size():
		var dx: float = PANEL_STEPS[i] * dir
		var a := 0.5 if i == 0 else 1.0
		t.tween_callback(func() -> void:
			c.position.x = base + dx
			c.modulate.a = a)
		t.tween_interval(step)
	t.tween_callback(func() -> void:
		c.position.x = base
		c.modulate.a = 1.0)


## A pop-up notice slides in from the left in 4 steps.
static func notice_in(c: Control) -> void:
	if not c.is_inside_tree():
		return
	var t := c.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var step := NOTICE_SECONDS / float(NOTICE_STEPS.size())
	for dx: float in NOTICE_STEPS:
		t.tween_callback(func() -> void: c.position.x = dx)
		t.tween_interval(step)


## The figures a counter shows on its way from `from` to `to` (whole numbers, `steps` of them, ending on `to`).
static func count_steps(from: int, to: int, steps: int = 8) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(1, steps + 1):
		out.append(int(round(lerpf(float(from), float(to), float(i) / float(steps)))))
	return out


## `label` counts from `from` to `to` (0.4 s) and a «+N» / «−N» rises from it and fades (0.8 s).
static func gold_change(label: Label, from: int, to: int) -> void:
	if not label.is_inside_tree() or from == to:
		label.text = str(to)
		return
	var t := label.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var steps := count_steps(from, to)
	for v: int in steps:
		t.tween_callback(func() -> void: label.text = str(v))
		t.tween_interval(COUNT_SECONDS / float(steps.size()))
	var delta := Label.new()
	delta.text = ("+%d" if to > from else "−%d") % absi(to - from)
	delta.theme_type_variation = &"PositiveLabel" if to > from else &"ReasonLabel"
	delta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	delta.top_level = true
	label.add_child(delta)
	var at := label.global_position + Vector2(label.size.x + 2.0, 0.0)
	delta.global_position = at
	var f := delta.create_tween()
	f.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i: int in 4:
		var y := at.y - FLOAT_RISE * float(i + 1) / 4.0
		var a := 1.0 - float(i) / 4.0
		f.tween_callback(func() -> void:
			delta.global_position.y = roundf(y)
			delta.modulate.a = a)
		f.tween_interval(FLOAT_SECONDS / 4.0)
	f.tween_callback(delta.queue_free)


## Duel (docs/ui/mecanicas/combate.md §8): `n` lunges `dx` px towards the other and back, by whole pixels (0.24 s).
const LUNGE_STEPS: Array[float] = [0.5, 1.0, 1.0, 0.5, 0.0]
const LUNGE_SECONDS: float = 0.24
## A touch received: the figure is pushed back `dx` px and comes back in 3 steps while it blinks (0.18 s).
const RECOIL_STEPS: Array[float] = [1.0, 0.5, 0.0]
const RECOIL_SECONDS: float = 0.18


static func lunge(n: Node2D, dx: float, steps: Array[float] = LUNGE_STEPS, seconds: float = LUNGE_SECONDS) -> void:
	if not n.is_inside_tree():
		return
	var base := n.position.x
	var t := n.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for f: float in steps:
		t.tween_callback(func() -> void: n.position.x = base + roundf(dx * f))
		t.tween_interval(seconds / float(steps.size()))
	t.tween_callback(func() -> void: n.position.x = base)


static func recoil(n: Node2D, dx: float) -> void:
	if not n.is_inside_tree():
		return
	var base := n.position.x
	var t := n.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i: int in RECOIL_STEPS.size():
		var f: float = RECOIL_STEPS[i]
		var a := 0.4 if i % 2 == 0 else 1.0
		t.tween_callback(func() -> void:
			n.position.x = base + roundf(dx * f)
			n.modulate.a = a)
		t.tween_interval(RECOIL_SECONDS / float(RECOIL_STEPS.size()))
	t.tween_callback(func() -> void:
		n.position.x = base
		n.modulate.a = 1.0)
