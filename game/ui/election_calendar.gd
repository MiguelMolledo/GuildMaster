class_name ElectionCalendar
extends Control
## The calendar line of an election (docs/ui/mecanicas/cargos_y_elecciones.md §3): three stretches of one year —
## registration (green), campaign (amber) and the vote (blue) — and a 1 px mark for today. Drawn by code: dynamic.

const REG: Color = Color(0.494118, 0.784314, 0.494118)
const CAMP: Color = Color(0.878431, 0.627451, 0.25098)
const VOTE: Color = Color(0.541176, 0.705882, 0.815686)
const TODAY: Color = Color(0.94902, 0.847059, 0.501961)
const EDGE: Color = Color(0.101961, 0.0705882, 0.0352941)

var start_day: int = 0      # the first day of the stretch shown (registration opens)
var campaign_day: int = 0
var vote_day: int = 1
var today: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(200, 6)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_days(start: int, campaign: int, vote: int, now: int) -> void:
	start_day = start
	campaign_day = campaign
	vote_day = vote
	today = now
	queue_redraw()


func _x(day: float) -> float:
	var span := maxf(1.0, float(vote_day + 1 - start_day))
	return roundf(clampf((day - start_day) / span, 0.0, 1.0) * size.x)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), EDGE)
	var h := size.y - 2.0
	draw_rect(Rect2(_x(start_day), 1, _x(campaign_day) - _x(start_day) - 1, h), REG)
	draw_rect(Rect2(_x(campaign_day), 1, _x(vote_day) - _x(campaign_day) - 1, h), CAMP)
	draw_rect(Rect2(_x(vote_day), 1, size.x - _x(vote_day), h), VOTE)
	var t := _x(float(today) + 0.5)
	draw_rect(Rect2(t, -2, 1, size.y + 4), TODAY)
