class_name HelpPanel
extends Control
## The help (docs/ui/01_hud.md §6, maqueta hud_ayuda): parchment over the veil with the map of keys by sections (KEYS,
## two columns), the «Ahora mismo» block (the current objective, how to do it, the debt; the HUD fills it with
## set_now) and, under it, the longer help of each mechanic (LINES). F1, "?", the HUD's "?" button or ESC close it;
## it does not pause the game. Texts in i18n/strings.csv (help.*), the look in game/ui/help_panel.tscn.
## The «Tutorial» block (docs/ui/05_tutorial.md §2): a button per chapter (set_chapters, filled by the HUD from the
## Tutorial), «hecho» on the ones done, off with the reason when they cannot be played now; a click emits
## chapter_requested(id) (the HUD closes the help and the app starts it).

signal chapter_requested(chapter: String)

## The map of keys: [column, section title key, [[key text key, what it does key], ...]] (help.key.<id> /
## help.key.<id>_do). Every key of HudKeys and the app is here (§9).
const KEYS: Array = [
	[0, "help.keys_map", ["click_left", "double_click", "click_right", "camera", "wheel"]],
	[0, "help.keys_time", ["space", "speeds"]],
	[1, "help.keys_family", ["group", "tree", "inventory"]],
	[1, "help.keys_panels", ["ledger", "offices", "trials", "build", "inside", "confirm", "esc", "help", "tutorial"]],
]
## The longer help, in order: "#" + key = a section title, else a line.
const LINES: Array[String] = ["#help.map", "help.map_select", "help.map_right", "help.map_manage",
	"help.map_camera", "help.map_time", "#help.inside", "help.inside_work", "help.inside_touch", "help.inside_exit",
	"#help.panels", "help.panels_keys", "help.panels_forge", "help.panels_esc", "#help.family", "help.family_group",
	"help.family_tree", "help.family_routine", "#help.town", "help.town_npc", "help.town_mev", "#help.titles",
	"help.titles_rep", "help.titles_hall", "#help.offices", "help.offices_chart", "help.offices_campaign",
	"help.offices_powers", "#help.trials", "help.trials_accused", "help.trials_hearing", "help.trials_accuse",
	"#help.kin_ai", "help.kin_ai_directives", "help.kin_ai_needs", "#help.money", "help.money_how"]
const WIDTH: float = 560.0   # wrapped lines need a width
const KEY_W: float = 92.0    # the key cap column

var _built: bool = false


## Builds the keys and the lines once (also outside the tree: the tests).
func build() -> void:
	if _built:
		return
	_built = true
	(get_node("%HelpTitle") as Label).text = tr("help.title")
	(get_node("%CloseHint") as Label).text = tr("help.close_hint")
	(get_node("%NowTitle") as Label).text = tr("help.now")
	(get_node("%MoreTitle") as Label).text = tr("help.more")
	(get_node("%TutorialTitle") as Label).text = tr("tutorial.ui.help_title")
	(get_node("%TutorialHint") as Label).text = tr("tutorial.ui.help_hint")
	for sec: Array in KEYS:
		var col := get_node("%KeysRight" if int(sec[0]) == 1 else "%KeysLeft") as VBoxContainer
		var t := Label.new()
		t.theme_type_variation = &"InkTitleLabel"
		t.text = tr(str(sec[1]))
		col.add_child(t)
		for k: String in sec[2]:
			col.add_child(_key_row(k))
	var box := get_node("%HelpLines") as VBoxContainer
	for k: String in LINES:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(WIDTH, 0)
		if k.begins_with("#"):
			l.text = tr(k.substr(1))
			l.theme_type_variation = &"InkTitleLabel"
		else:
			l.text = "· " + tr(k)
			l.theme_type_variation = &"InkLabel"
		box.add_child(l)


## One row of the key map: the key on a cap (gold on the sunken field) and what it does in ink.
func _key_row(id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Key_" + id
	row.add_theme_constant_override("separation", 6)
	var cap := PanelContainer.new()
	cap.theme_type_variation = &"KeyCap"
	cap.custom_minimum_size = Vector2(KEY_W, 0)
	cap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var k := Label.new()
	k.theme_type_variation = &"GoldLabel"
	k.text = tr("help.key." + id)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(k)
	row.add_child(cap)
	var d := Label.new()
	d.theme_type_variation = &"InkLabel"
	d.text = tr("help.key.%s_do" % id)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(170, 0)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(d)
	return row


## The tutorial's chapters: [{id, name, done, reason}] (reason: why it cannot be played now, "" = it can). Hidden
## when there are none.
func set_chapters(list: Array) -> void:
	build()
	var box := get_node("%Chapters") as HFlowContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for ch: Dictionary in list:
		var b := Button.new()
		var id := str(ch.get("id", ""))
		b.name = "Chapter_" + id
		b.text = str(ch.get("name", id)) + ("  · " + tr("tutorial.ui.help_done") if bool(ch.get("done", false)) else "")
		b.disabled = str(ch.get("reason", "")) != ""
		b.tooltip_text = tr(str(ch.get("reason", ""))) if b.disabled else str(ch.get("desc", ""))
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: chapter_requested.emit(id))
		box.add_child(b)
	for n: String in ["%SepTutorial", "%TutorialTitle", "%TutorialHint", "%Chapters"]:
		(get_node(n) as Control).visible = not list.is_empty()


## «Ahora mismo»: what to do now (the HUD sends it before opening).
func set_now(text: String) -> void:
	build()
	(get_node("%NowText") as Label).text = text if text != "" else tr("help.now_nothing")


## The ids of every key row (for the tests: every key of the game is in the help).
static func key_ids() -> Array[String]:
	var out: Array[String] = []
	for sec: Array in KEYS:
		for k: String in sec[2]:
			out.append(k)
	return out


func toggle() -> void:
	build()
	visible = not visible
	if OS.is_debug_build():
		print("[Help] %s" % ("on" if visible else "off"))


func close() -> void:
	visible = false


## F1 or "?" toggles it. True if the key was used.
static func is_help_key(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	return k.keycode == KEY_F1 or k.physical_keycode == KEY_F1 or k.keycode == KEY_QUESTION or k.unicode == 63   # 63 = "?"
