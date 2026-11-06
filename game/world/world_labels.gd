class_name WorldLabels
extends RefCounted
## The letters of the town and the rooms (verificación B9): the signs over the buildings, the names over the people,
## what they say, the stations' names, the works bars, the badges and the greybox bubbles. One style for all of them,
## with the project's fonts at their own size (docs/ui/00_lenguaje_visual.md §6: another size deforms the letter) and
## a dark contour so they read over the art at zoom 1. Pure styling: a view calls style() on the Label it makes.
##   role  "sign" (a building's board: bold ink, no contour) · "name" · "phrase" · "station" · "flash" (light, contour)
##         · "small" (bars, badges, bubbles: Pixel Operator 8)

const BODY: Font = preload("res://assets/art/ui/fonts/pixel_operator.ttf")
const BOLD: Font = preload("res://assets/art/ui/fonts/pixel_operator_bold.ttf")
const SMALL: Font = preload("res://assets/art/ui/fonts/pixel_operator_8.ttf")
const INK: Color = Color("#1f140d")
const LIGHT: Color = Color("#fff2cc")
const CONTOUR: Color = Color("#1a1209")


## Sets the font, size, colour and contour of `l` for `role`; `color` replaces the role's colour when given.
static func style(l: Label, role: String, color: Color = Color(0, 0, 0, 0)) -> void:
	var font: Font = BODY
	var size := 16
	var fg := LIGHT
	var outline := 2
	match role:
		"sign":
			font = BOLD
			fg = INK
			outline = 0
		"flash", "name":
			font = BOLD
		"small":
			font = SMALL
			size = 8
	if color.a > 0.0:
		fg = color
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", fg)
	l.add_theme_color_override("font_outline_color", CONTOUR)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_constant_override("line_spacing", -3)


## Every Label under `n` (a bubble's greybox) in `role`.
static func style_tree(n: Node, role: String = "small") -> void:
	if n is Label:
		style(n as Label, role, (n as Label).get_theme_color("font_color") if (n as Label).has_theme_color_override("font_color") else Color(0, 0, 0, 0))
	for c: Node in n.get_children():
		style_tree(c, role)
