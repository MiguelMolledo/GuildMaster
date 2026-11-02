class_name HelpPanel
extends PanelContainer
## Help overlay (H5 polish): the controls and panels of the game, one line per help.* key (LINES), opened and closed
## with F1, "?" or the HUD's Help button; ESC closes it (HUD.close_top). It does not pause the game. Edit the texts in
## i18n/strings.csv (help.*), the look in game/ui/help_panel.tscn.

## In order: "#" + key = a section title, else a line.
const LINES: Array[String] = ["#help.map", "help.map_select", "help.map_right", "help.map_manage",
	"help.map_camera", "help.map_time", "#help.inside", "help.inside_work", "help.inside_touch", "help.inside_exit",
	"#help.panels", "help.panels_keys", "help.panels_forge", "help.panels_esc", "#help.family", "help.family_group",
	"help.family_tree", "help.family_routine", "#help.money", "help.money_how"]
const WIDTH: float = 480.0   # wrapped lines need a width

var _built: bool = false


## Builds the lines once (also outside the tree: the tests).
func build() -> void:
	if _built:
		return
	_built = true
	(get_node("%HelpTitle") as Label).text = tr("help.title")
	var box := get_node("%HelpLines") as VBoxContainer
	for k: String in LINES:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(WIDTH, 0)
		if k.begins_with("#"):
			l.text = tr(k.substr(1))
			l.add_theme_color_override("font_color", Color(0.85, 0.71, 0.42))
			l.add_theme_font_size_override("font_size", 11)
		else:
			l.text = "· " + tr(k)
			l.add_theme_font_size_override("font_size", 10)
		box.add_child(l)


func toggle() -> void:
	build()
	visible = not visible
	if OS.is_debug_build():
		print("[Help] %s" % ("on" if visible else "off"))


## F1 or "?" toggles it. True if the key was used.
static func is_help_key(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	return k.keycode == KEY_F1 or k.keycode == KEY_QUESTION or k.unicode == 63   # 63 = "?"
