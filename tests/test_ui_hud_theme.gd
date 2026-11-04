extends "res://tests/test_case.gd"
## The UI theme (docs/ui/00_lenguaje_visual.md): pixel fonts at their crisp sizes, the kit's 9-patch pieces for every
## state, the token colours, the cursors, and no panel forcing its own font size (the theme rules).

const THEME: String = "res://game/ui/greybox_theme.tres"
const MENU_FILES: Array[String] = ["new_game_screen.tscn", "ending_screen.tscn"]  # the menus' worker owns them


func _theme() -> Theme:
	return load(THEME) as Theme


func _path(r: Resource) -> String:
	return r.resource_path if r != null else ""


func test_fonts_are_pixel_operator_and_jacquard_at_their_sizes() -> void:
	var th := _theme()
	check(_path(th.default_font).ends_with("pixel_operator.ttf"), "default font: Pixel Operator")
	eq(th.default_font_size, 16, "default size 16")
	check(_path(th.get_font("font", "Button")).ends_with("pixel_operator_bold.ttf"), "buttons: Pixel Operator Bold")
	eq(th.get_font_size("font_size", "Button"), 16, "buttons at 16")
	eq(th.get_constant("line_spacing", "Label"), -3, "labels: line_spacing -3 (13 px lines)")
	check(_path(th.get_font("font", "TitleLabel")).ends_with("jacquard_24.ttf"), "titles: Jacquard 24")
	eq(th.get_font_size("font_size", "TitleLabel"), 24, "titles at 24")
	check(_path(th.get_font("font", "SectionTitle")).ends_with("pixel_operator_bold.ttf"), "small titles: PO Bold")
	eq(th.get_font_size("font_size", "SectionTitle"), 16, "small titles at 16")
	# the small gothic (Jacquarda Bastarda 9 at 13) smudged at its size: no variation uses it any more (2026-11-04)
	for type: StringName in th.get_font_type_list():
		for fname: StringName in th.get_font_list(type):
			check(not _path(th.get_font(fname, type)).ends_with("jacquarda_bastarda_9.ttf"), "%s: not the small gothic" % type)
	check(_path(th.get_font("font", "SmallLabel")).ends_with("pixel_operator_8.ttf"), "small: Pixel Operator 8")
	eq(th.get_font_size("font_size", "SmallLabel"), 8, "small at 8")
	for f: String in ["pixel_operator.ttf", "pixel_operator_bold.ttf", "pixel_operator_8.ttf", "jacquard_24.ttf"]:
		var ff := load("res://assets/art/ui/fonts/" + f) as FontFile
		eq(ff.antialiasing, TextServer.FONT_ANTIALIASING_NONE, "%s: no antialiasing" % f)
		eq(ff.hinting, TextServer.HINTING_NONE, "%s: no hinting" % f)


func test_every_state_uses_the_kit_pieces() -> void:
	var th := _theme()
	var pieces := {"normal": "button_normal", "hover": "button_hover", "pressed": "button_pressed",
		"disabled": "button_disabled", "focus": "button_hover"}
	for st: String in pieces:
		var sb := th.get_stylebox(st, "Button") as StyleBoxTexture
		check(sb != null and _path(sb.texture).ends_with(pieces[st] + ".png"), "button %s: %s" % [st, pieces[st]])
	var panel := th.get_stylebox("panel", "PanelContainer") as StyleBoxTexture
	check(panel != null and _path(panel.texture).ends_with("panel.png"), "panels: the wooden frame")
	eq(panel.texture_margin_left, 6.0, "panel 9-patch margin 6")
	eq(panel.content_margin_left, 8.0, "panel padding 8 (frame 6 + 2)")
	check(_path((th.get_stylebox("panel", "ParchmentPanel") as StyleBoxTexture).texture).ends_with("parchment.png"),
		"parchment")
	check(_path((th.get_stylebox("panel", "TooltipPanel") as StyleBoxTexture).texture).ends_with("tooltip.png"), "tooltips")
	check(_path((th.get_stylebox("normal", "LineEdit") as StyleBoxTexture).texture).ends_with("field.png"), "fields")
	check(_path(th.get_icon("checked", "CheckBox")).ends_with("check_on.png"), "check on")
	check(_path(th.get_icon("unchecked", "CheckBox")).ends_with("check_off.png"), "check off")
	check(_path(th.get_icon("grabber", "HSlider")).ends_with("slider_grabber.png"), "slider grabber")
	check(_path((th.get_stylebox("slider", "HSlider") as StyleBoxTexture).texture).ends_with("slider_track.png"), "slider")
	check(_path((th.get_stylebox("scroll", "VScrollBar") as StyleBoxTexture).texture).ends_with("scroll_track.png"), "scroll")
	check(_path((th.get_stylebox("grabber", "VScrollBar") as StyleBoxTexture).texture).ends_with("scroll_grabber.png"),
		"scroll grabber")
	check(_path((th.get_stylebox("tab_selected", "TabContainer") as StyleBoxTexture).texture).ends_with("tab_on.png"), "tab on")
	check(_path((th.get_stylebox("tab_unselected", "TabBar") as StyleBoxTexture).texture).ends_with("tab_off.png"), "tab off")
	check(_path((th.get_stylebox("separator", "HSeparator") as StyleBoxTexture).texture).ends_with("divider.png"), "divider")


func test_colours_come_from_the_tokens() -> void:
	var th := _theme()
	var tok: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://tools/ui/tokens.json")) as Dictionary)["color"]
	var c := func(k: String) -> Color: return Color.html(str(tok[k]))
	check(th.get_color("font_color", "Label").is_equal_approx(c.call("texto")), "text")
	check(th.get_color("font_hover_color", "Button").is_equal_approx(c.call("oro_claro")), "hover: light gold")
	check(th.get_color("font_disabled_color", "Button").is_equal_approx(c.call("texto_apagado")), "disabled text")
	check(th.get_color("font_color", "TitleLabel").is_equal_approx(c.call("oro")), "titles in gold")
	check(th.get_color("font_color", "TooltipLabel").is_equal_approx(c.call("texto_tinta")), "ink on parchment")
	check(th.get_color("font_color", "ReasonLabel").is_equal_approx(c.call("negativo")), "the reason in red")
	check((th.get_stylebox("panel", "DarkPanel") as StyleBoxFlat).bg_color.is_equal_approx(c.call("seccion")), "dark section")


func test_cursors_x2_exist() -> void:
	for p: String in [UiFeel.ARROW, UiFeel.HAND, UiFeel.WAIT]:
		var t := load(p) as Texture2D
		check(t != null, "%s loads" % p)
	eq((load(UiFeel.ARROW) as Texture2D).get_size(), Vector2(20, 30), "the arrow at ×2 (20×30)")


func test_no_panel_forces_its_own_font_size() -> void:
	var dir := DirAccess.open("res://game/ui")
	for f: String in dir.get_files():
		if f.ends_with(".tscn") and not MENU_FILES.has(f):
			var s := FileAccess.get_file_as_string("res://game/ui/" + f)
			check(not s.contains("theme_override_font_sizes"), "%s: no forced font size (the theme rules)" % f)
		if f.ends_with(".gd") and not f.begins_with("new_game_screen") and not f.begins_with("ending_screen"):
			var g := FileAccess.get_file_as_string("res://game/ui/" + f)
			check(not g.contains("add_theme_font_size_override"), "%s: no forced font size in code" % f)


func test_ui_sounds_denied_tab_seal() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio.json"))
	eq(str(cfg["ui"]["denied"]), "sfx_ui_denied", "a disabled button pressed says no")
	eq(str(cfg["ui"]["tab"]), "sfx_ui_tab", "a tab turns")
	eq(str(cfg["events"]["upgrade_started"]), "sfx_ui_seal", "an upgrade started is sealed")
	for id: String in ["sfx_ui_denied", "sfx_ui_tab", "sfx_ui_seal"]:
		check((cfg["sfx"] as Dictionary).has(id), "%s in data/audio.json" % id)
		eq(str(cfg["sfx"][id].get("bus", "")), "Ui", "%s on the Ui bus" % id)
		check(ResourceLoader.exists("res://assets/audio/sfx/%s_01.ogg" % id), "%s has its file" % id)


## A title that clips and does not fit its width in Jacquard 24 drops to Pixel Operator Bold (TitleFit), and goes back
## when it fits.
func test_a_long_title_takes_the_small_letter() -> void:
	var l := Label.new()
	l.theme = _theme()
	l.theme_type_variation = &"TitleLabel"
	l.clip_text = true
	TitleFit.hook(l)
	check(l.has_meta("title_fit"), "a clipped title is watched")
	l.size = Vector2(200, 24)
	l.text = "Libro de cuentas · Herrero"
	eq(TitleFit.check(l), &"SectionTitle", "too long for 200 px in gothic: the small letter")
	l.text = "Almacén"
	eq(TitleFit.check(l), &"TitleLabel", "a short one: back to the gothic")
	var free := Label.new()
	free.theme_type_variation = &"TitleLabel"
	TitleFit.hook(free)
	check(not free.has_meta("title_fit"), "a title that does not clip is left alone (it grows)")
	free.free()
	l.free()
