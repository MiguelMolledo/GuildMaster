extends "res://tests/test_case.gd"
## The options (docs/ui/02_menu_inicial.md §4): applied at once and remembered in their own file (a fresh read is a
## restart), one volume per bus, the choices, the defaults, the screen that changes them.


func _use_temp() -> String:
	var p := "user://test_menu_settings_%d.cfg" % randi()
	Settings.path = p
	Settings.reread()
	return p


func _restore(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	Settings.path = Settings.PATH
	Settings.reread()
	for k: String in Settings.BUSES:
		Settings.apply(k)


func test_music_at_zero_mutes_the_bus_and_is_remembered() -> void:
	var p := _use_temp()
	var music := AudioServer.get_bus_index("Music")
	check(music >= 0, "the Music bus of default_bus_layout.tres")
	var base := Settings.bus_db("Music", 100)
	check(Settings.set_value("audio/music", 0), "set")
	check(AudioServer.is_bus_mute(music), "music at 0 % is silent at once")
	Settings.reread()  # what a restart does
	eq(int(Settings.value("audio/music")), 0, "remembered")
	Settings.set_value("audio/music", 100)
	Settings.apply_all()
	check(not AudioServer.is_bus_mute(music), "back on")
	near(AudioServer.get_bus_volume_db(music), base, 0.01, "100 % is the layout's volume")
	Settings.set_value("audio/sfx", 50)
	near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Sfx")), Settings.bus_db("Sfx", 100) + linear_to_db(0.5),
		0.01, "50 % is half the amplitude")
	_restore(p)


func test_choices_are_checked_and_defaults_come_back() -> void:
	var p := _use_temp()
	check(not Settings.set_value("display/scale", 5), "×5 is not a choice")
	check(not Settings.set_value("nope/key", 1), "an unknown key")
	check(Settings.set_value("game/load_speed", 4), "×4 on load")
	check(Settings.set_value("game/notices", "urgent"), "only urgent notices")
	var heard: Array = []
	var cb := func(k: String, v: Variant) -> void: heard.append([k, v])
	Settings.notifier.changed.connect(cb)
	Settings.set_value("game/help_line", true)
	eq(heard, [["game/help_line", true]], "the change is told")
	Settings.reset()
	eq(int(Settings.value("game/load_speed")), 1, "defaults back")
	eq(str(Settings.value("game/notices")), "all", "notices: all (01, decision 1)")
	eq(bool(Settings.value("game/help_line")), false, "no help line (01, decision 2)")
	Settings.notifier.changed.disconnect(cb)
	_restore(p)


func test_language_changes_the_locale() -> void:
	var p := _use_temp()
	var before := TranslationServer.get_locale()
	Settings.set_value("lang/locale", "en")
	eq(TranslationServer.get_locale(), "en", "English at once")
	eq(SimQuery.t_("ui.title.new_game"), "New game", "texts follow")
	Settings.set_value("lang/locale", "es")
	eq(SimQuery.t_("ui.title.new_game"), "Partida nueva", "and back")
	TranslationServer.set_locale(before)
	_restore(p)


func test_large_text_changes_the_theme_in_memory_and_back() -> void:
	var p := _use_temp()
	var theme := load(Settings.THEME_PATH) as Theme
	var body_font := theme.get_font("font", "BodyLabel")
	var spacing := theme.get_constant("line_spacing", "BodyLabel")
	Settings.set_value("display/text", "large")
	eq(theme.get_font("font", "BodyLabel"), theme.get_font("font", "BoldLabel"), "large = bold")
	eq(theme.get_constant("line_spacing", "BodyLabel"), spacing + 2, "with more line spacing")
	Settings.set_value("display/text", "normal")
	eq(theme.get_font("font", "BodyLabel"), body_font, "normal font back")
	eq(theme.get_constant("line_spacing", "BodyLabel"), spacing, "normal spacing back")
	_restore(p)


func test_the_options_screen_applies_what_is_touched() -> void:
	var p := _use_temp()
	var s: OptionsScreen = (load("res://game/ui/options_screen.tscn") as PackedScene).instantiate()
	s.open()
	var slider := s.control_of("audio/ambient") as HSlider
	eq(int(slider.value), 100, "starts at the saved value")
	slider.value = 40
	slider.value_changed.emit(40.0)  # out of the tree a Range does not emit it by itself
	eq(int(Settings.value("audio/ambient")), 40, "the slider saves")
	eq((s.get_node("%AmbientValue") as Label).text, "40 %", "and shows it")
	(s.control_of("game/pause_unfocused") as CheckBox).button_pressed = false
	eq(bool(Settings.value("game/pause_unfocused")), false, "a check saves")
	s.choice_button("game/load_speed", 2).pressed.emit()
	eq(int(Settings.value("game/load_speed")), 2, "a choice saves")
	check(s.choice_button("display/scale", 2) != null and not s.choice_button("display/scale", 2).disabled, "×2 always fits")
	(s.get_node("%DefaultsButton") as Button).pressed.emit()
	eq(int(Settings.value("audio/ambient")), 100, "defaults")
	eq(int((s.control_of("audio/ambient") as HSlider).value), 100, "and the screen shows them")
	var back: Array = []
	s.back_requested.connect(func() -> void: back.append(1))
	(s.get_node("%BackButton") as Button).pressed.emit()
	eq(back.size(), 1, "Back")
	s.free()
	_restore(p)
