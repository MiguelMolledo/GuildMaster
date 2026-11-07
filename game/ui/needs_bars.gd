class_name NeedsBars
extends Control
## Two small vertical bars next to a portrait of the group (sleep and food, GDD 4.2.6): rest (blue) and hunger (gold),
## red under their state (tired / hungry: needs.states). The tooltip says the figures and the state in words (never
## the colour alone). Drawn by code: it is dynamic. Colours: the theme type NeedsBars of greybox_theme.tres.

var rest: int = 100
var hunger: int = 100
var low_at: int = 30


func _init() -> void:
	custom_minimum_size = Vector2(5, 38)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_PASS


## Shows the view of Needs.view (needs, states, tracked); hidden when its needs do not move.
func show_view(v: Dictionary) -> void:
	visible = bool(v.get("tracked", false))
	var n: Dictionary = v.get("needs", {})
	var r := int(n.get("rest", 100))
	var h := int(n.get("hunger", 100))
	var parts: Array = [tr("ui.needs.bars_tip") % [r, h]]
	for s: Variant in v.get("states", []):
		parts.append(tr("ui.needs.state." + str(s)))
	tooltip_text = " · ".join(parts)
	if r != rest or h != hunger:
		rest = r
		hunger = h
		queue_redraw()


func _c(n: StringName) -> Color:
	return get_theme_color(n, &"NeedsBars")


func _draw() -> void:
	var hgt := size.y - 6.0
	for i: int in 2:
		var v := rest if i == 0 else hunger
		var x := float(i) * 3.0
		var r := Rect2(x, 3.0, 2.0, hgt)
		draw_rect(r, _c(&"track"))
		var fill := roundf(hgt * clampf(float(v) / 100.0, 0.0, 1.0))
		var col := _c(&"low") if v < low_at else _c(&"rest" if i == 0 else &"hunger")
		draw_rect(Rect2(x, 3.0 + hgt - fill, 2.0, fill), col)
