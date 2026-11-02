class_name HudLayout
extends RefCounted
## Layout rules of the HUD that keep its panels from covering each other (pure: the tests check them without a HUD).


## Where the H8 group portraits go: under the selected person's panel (which grows with the queued orders).
static func group_bar_y(selected_visible: bool, selected: Rect2, base_y: float = 66.0) -> float:
	return maxf(base_y, selected.end.y + 6.0) if selected_visible else base_y


## Whether the objective's how-to is unfolded: inside a building always; on the map only while it is new
## (`seconds_left` > 0) or while the mouse is over the panel, so the folded panel covers less of the town.
static func hint_shown(has_text: bool, interior_open: bool, seconds_left: float, mouse_over: bool) -> bool:
	return has_text and (interior_open or seconds_left > 0.0 or mouse_over)
