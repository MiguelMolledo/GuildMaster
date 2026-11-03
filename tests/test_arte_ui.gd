extends "res://tests/test_case.gd"
## UI look and overlaps (arte): the pixel art theme on every panel and on the HUD's root, the group portraits in the
## card, the objective's hint folding on the map, and bubbles of close heads spread apart.

var cat := Catalog.load_from()


func test_theme_is_pixel_art_and_on_the_hud_root() -> void:
	var th := load("res://game/ui/greybox_theme.tres") as Theme
	check(th.get_stylebox("panel", "PanelContainer") is StyleBoxTexture, "panels: the wooden 9-patch")
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		check(th.get_stylebox(st, "Button") is StyleBoxTexture, "buttons: %s" % st)
	check(th.get_font("font", "Button") != null, "buttons: the pixel font")
	var hud := FileAccess.get_file_as_string("res://game/ui/hud.tscn")
	var root := hud.substr(hud.find('[node name="Root" type="Control" parent="."]'), 220)
	check(root.contains('theme = ExtResource("3_theme")'), "the HUD's root carries the theme (new panels inherit it)")


func test_group_portraits_live_in_the_card() -> void:
	var hud := FileAccess.get_file_as_string("res://game/ui/hud.tscn")
	check(hud.contains('[node name="GroupBar" type="HBoxContainer" parent="Root/Card/HBox"]'),
		"the group's portraits are inside the card (zone 1), never over another panel")


func test_objective_hint_folds_on_the_map() -> void:
	check(HudLayout.hint_shown(true, false, 5.0, false), "unfolded while it is new")
	check(not HudLayout.hint_shown(true, false, 0.0, false), "folded on the map after a while")
	check(HudLayout.hint_shown(true, false, 0.0, true), "the mouse over the panel unfolds it")
	check(HudLayout.hint_shown(true, true, 0.0, false), "always unfolded inside a building")
	check(not HudLayout.hint_shown(false, true, 5.0, true), "nothing to show without a text")


func test_close_bubbles_spread_apart() -> void:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(NewGame.from_scenario("town_e_start")["state"], cat)
	var ids: Array = v.state.characters.keys()
	ids.sort()
	var a: CharacterView = v.view_of(str(ids[0]))
	var b: CharacterView = v.view_of(str(ids[1]))
	for w: String in ids:
		v.view_of(str(w)).set_bubble("")
	a.position = Vector2(100, 100)
	b.position = Vector2(100 + 8, 100 - 16)  # one tile behind, a little to the side
	a.set_bubble("dice")
	b.set_bubble("dice")
	v.spread_bubbles()
	var ra := Rect2(a.position + Vector2(a.bubble_shift - 13, -a.fig_height - 34), Vector2(26, 22))
	var rb := Rect2(b.position + Vector2(b.bubble_shift - 13, -b.fig_height - 34), Vector2(26, 22))
	check(not ra.intersects(rb), "the two bubbles do not overlap (%s, %s)" % [a.bubble_shift, b.bubble_shift])
	check(not ra.grow(-2.0).intersects(b.pick_rect()), "the front bubble does not land on the figure behind")
	v.free()
