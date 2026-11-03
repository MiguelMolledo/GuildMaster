class_name ElectionCalendar
extends Control
## The calendar line of an election (docs/ui/mecanicas/cargos_y_elecciones.md §3): three stretches of one year —
## registration (green), campaign (amber) and the vote (blue) — and a 1 px mark for today. Drawn by code: dynamic.

## Its colours: the theme type ElectionCalendar (registration, campaign, vote, today, edge).

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


func _c(n: StringName) -> Color:
	return SocialKit.theme_color(&"ElectionCalendar", n)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _c(&"edge"))
	var h := size.y - 2.0
	draw_rect(Rect2(_x(start_day), 1, _x(campaign_day) - _x(start_day) - 1, h), _c(&"registration"))
	draw_rect(Rect2(_x(campaign_day), 1, _x(vote_day) - _x(campaign_day) - 1, h), _c(&"campaign"))
	draw_rect(Rect2(_x(vote_day), 1, size.x - _x(vote_day), h), _c(&"vote"))
	var t := _x(float(today) + 0.5)
	draw_rect(Rect2(t, -2, 1, size.y + 4), _c(&"today"))
