class_name OptionsScreen
extends MenuScreen
## The options (docs/ui/02_menu_inicial.md §4), from the title or the pause menu. Every change is applied and saved at
## once (Settings, user://settings.cfg; never in the game). Sound: one slider per bus and "lower the sound when the
## window is not active"; language; display: full screen (F11), whole scale (only the ones that fit the screen; the
## others off with the reason), text size (decision 1: Large = bold and more line spacing); game: speed on load,
## which notices pop up, pause when the window loses the focus, the help line, objective hints. "Defaults" without
## confirmation. The choices of a row are its buttons in the order of Settings.CHOICES.

const SLIDERS: Dictionary = {"audio/master": "Master", "audio/music": "Music", "audio/sfx": "Sfx",
	"audio/ambient": "Ambient", "audio/voice": "Voice", "audio/ui": "Ui"}
const CHECKS: Dictionary = {"audio/mute_unfocused": "MuteUnfocused", "display/fullscreen": "Fullscreen",
	"game/pause_unfocused": "PauseUnfocused", "game/help_line": "HelpLine", "game/objective_hints": "ObjectiveHints"}
const ROWS: Dictionary = {"lang/locale": "Locale", "display/scale": "Scale", "display/text": "Text",
	"game/load_speed": "LoadSpeed", "game/notices": "Notices"}

var _bound: bool = false
var _filling: bool = false


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%BackButton as Button).pressed.connect(func() -> void: back_requested.emit())
	(%CloseButton as Button).pressed.connect(func() -> void: back_requested.emit())
	(%DefaultsButton as Button).pressed.connect(func() -> void:
		Settings.reset()
		_refresh())
	for key: String in SLIDERS:
		var k := key
		(get_node("%" + str(SLIDERS[key])) as HSlider).value_changed.connect(func(v: float) -> void:
			_value_label(k)
			if not _filling:
				Settings.set_value(k, int(v)))
	for key: String in CHECKS:
		var k := key
		(get_node("%" + str(CHECKS[key])) as CheckBox).toggled.connect(func(on: bool) -> void:
			if not _filling:
				Settings.set_value(k, on))
	for key: String in ROWS:
		var box := get_node("%" + str(ROWS[key])) as HBoxContainer
		var choices: Array = Settings.CHOICES[key]
		var group := ButtonGroup.new()
		for i: int in mini(box.get_child_count(), choices.size()):
			var b := box.get_child(i) as Button
			var k := key
			var v: Variant = choices[i]
			b.toggle_mode = true
			b.button_group = group
			b.pressed.connect(func() -> void:
				if not _filling:
					Settings.set_value(k, v)
					if k == "lang/locale":
						_refresh())
	Settings.notifier.changed.connect(func(key: String, _v: Variant) -> void:
		if visible and key == "display/fullscreen":
			_fill())


func _refresh() -> void:
	_bind()
	_texts()
	_fill()


## The slider / check / choice of `key` (tests).
func control_of(key: String) -> Control:
	for table: Dictionary in [SLIDERS, CHECKS, ROWS]:
		if table.has(key):
			return get_node("%" + str(table[key])) as Control
	return null


## The button of value `v` in the row of `key`.
func choice_button(key: String, v: Variant) -> Button:
	var i: int = (Settings.CHOICES[key] as Array).find(v)
	var box := get_node("%" + str(ROWS[key])) as HBoxContainer
	return box.get_child(i) as Button if i >= 0 and i < box.get_child_count() else null


func _fill() -> void:
	_filling = true
	for key: String in SLIDERS:
		(get_node("%" + str(SLIDERS[key])) as HSlider).value = int(Settings.value(key))
		_value_label(key)
	for key: String in CHECKS:
		(get_node("%" + str(CHECKS[key])) as CheckBox).button_pressed = bool(Settings.value(key))
	var fits := Settings.fitting_scales()
	for key: String in ROWS:
		var choices: Array = Settings.CHOICES[key]
		var box := get_node("%" + str(ROWS[key])) as HBoxContainer
		for i: int in mini(box.get_child_count(), choices.size()):
			var b := box.get_child(i) as Button
			b.set_pressed_no_signal(choices[i] == Settings.value(key))
			if key == "display/scale":
				b.disabled = not int(choices[i]) in fits or bool(Settings.value("display/fullscreen"))
	(%ScaleNote as Label).text = SimQuery.t_("ui.options.scale_full") if bool(Settings.value("display/fullscreen")) \
		else SimQuery.t_("ui.options.scale_note")
	_filling = false


func _value_label(key: String) -> void:
	var s := get_node("%" + str(SLIDERS[key])) as HSlider
	(get_node("%" + str(SLIDERS[key]) + "Value") as Label).text = "%d %%" % int(s.value)


func _texts() -> void:
	(%Title as Label).text = SimQuery.t_("ui.options.title")
	(%SoundTitle as Label).text = SimQuery.t_("ui.options.sound")
	for key: String in SLIDERS:
		(get_node("%" + str(SLIDERS[key]) + "Label") as Label).text = SimQuery.t_("ui.options." + key.get_slice("/", 1))
	(%MuteUnfocused as CheckBox).text = SimQuery.t_("ui.options.mute_unfocused")
	(%LangTitle as Label).text = SimQuery.t_("ui.options.language")
	(%DisplayTitle as Label).text = SimQuery.t_("ui.options.display")
	(%Fullscreen as CheckBox).text = SimQuery.t_("ui.options.fullscreen")
	(%ScaleLabel as Label).text = SimQuery.t_("ui.options.scale")
	(%TextLabel as Label).text = SimQuery.t_("ui.options.text")
	(%TextNote as Label).text = SimQuery.t_("ui.options.text_note")
	var text_box := %Text as HBoxContainer
	(text_box.get_child(0) as Button).text = SimQuery.t_("ui.options.text_normal")
	(text_box.get_child(1) as Button).text = SimQuery.t_("ui.options.text_large")
	(%GameTitle as Label).text = SimQuery.t_("ui.options.game")
	(%LoadSpeedLabel as Label).text = SimQuery.t_("ui.options.load_speed")
	(%NoticesLabel as Label).text = SimQuery.t_("ui.options.notices")
	var notices := %Notices as HBoxContainer
	(notices.get_child(0) as Button).text = SimQuery.t_("ui.options.notices_urgent")
	(notices.get_child(1) as Button).text = SimQuery.t_("ui.options.notices_all")
	(%PauseUnfocused as CheckBox).text = SimQuery.t_("ui.options.pause_unfocused")
	(%HelpLine as CheckBox).text = SimQuery.t_("ui.options.help_line")
	(%ObjectiveHints as CheckBox).text = SimQuery.t_("ui.options.objective_hints")
	(%DefaultsButton as Button).text = SimQuery.t_("ui.options.defaults")
	(%AppliedNote as Label).text = SimQuery.t_("ui.options.applied")
	(%BackButton as Button).text = SimQuery.t_("ui.menu.back")
	MenuKit.add_hint(%BackButton as Button, SimQuery.t_("ui.key.esc"))
