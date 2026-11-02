extends "res://tests/test_case.gd"
## Audio by id (data/audio.json, default_bus_layout.tres): the AudioDirector resolves sections and buses, stays
## silent without files (no error), picks the music of the phase and only sounds the player's family's events.


func _director() -> AudioDirector:
	var d := AudioDirector.new()
	d.load_config()
	return d


func test_sections_and_buses() -> void:
	var d := _director()
	eq(d.section_of("music_city_day"), "music", "a music id")
	eq(d.section_of("sfx_hammer"), "sfx", "a sound id")
	eq(d.section_of("nope"), "", "unknown")
	eq(d.bus_of("music_night"), "Music", "music goes to Music")
	eq(d.bus_of("sfx_coins"), "Sfx", "sounds go to Sfx")
	eq(d.bus_of("sfx_ui_click"), "Ui", "unless the id names its bus")
	d.free()


func test_bus_layout_has_the_fixed_buses() -> void:
	var text := FileAccess.get_file_as_string("res://default_bus_layout.tres")
	for b: String in ["Master", "Music", "Sfx", "Ambient", "Voice", "Ui"]:
		check(text.contains('name = &"%s"' % b), "bus %s" % b)


func test_silence_without_files() -> void:
	var d := _director()
	d.config["sfx"]["sfx_test_without_file"] = {}
	check(not d._stream("sfx_test_without_file"), "no file yet: no stream")
	check(not d._stream("nope"), "unknown id: no stream")
	d.free()


func test_every_id_has_its_file() -> void:
	var d := _director()
	for id: String in d.ids():
		check(d._stream(str(id)) != null, "%s has a file" % id)
	eq(VisualPaths.audio_files("sfx", "sfx_hammer").size(), 3, "hammer: three variants")
	d.free()


func test_music_and_ambient_loop() -> void:
	var d := _director()
	for sec: String in ["music", "ambient"]:
		for id: String in (d.config[sec] as Dictionary):
			var s := d._stream(str(id)) as AudioStreamOggVorbis
			check(s != null and s.loop, "%s loops" % id)
	d.free()


func test_ambient_by_phase_and_interior() -> void:
	var d := _director()
	eq(d.ambient_for("day", ""), "ambient_town_day", "town by day")
	eq(d.ambient_for("night", ""), "ambient_night", "town by night")
	eq(d.ambient_for("night", "forge"), "ambient_forge", "inside the forge, any phase")
	eq(d.ambient_for("day", "house"), "", "a type without an interior ambient is quiet")
	for key: String in ["phase_ambient", "interior_ambient"]:
		for k: String in (d.config[key] as Dictionary):
			eq(d.section_of(str(d.config[key][k])), "ambient", "%s.%s is an ambient" % [key, k])
	d.free()


func test_notice_sounds_by_key_then_severity() -> void:
	var d := _director()
	eq(d.sound_for({"type": "notice_added", "key": "notice.objective_done", "severity": "info"}), "sfx_objective_done",
		"the key wins")
	eq(d.sound_for({"type": "notice_added", "key": "notice.objective_failed", "severity": "warning"}),
		"sfx_objective_failed", "the key wins over the severity")
	eq(d.sound_for({"type": "notice_added", "key": "notice.contract_due", "severity": "warning"}), "sfx_notice",
		"else the severity")
	eq(d.sound_for({"type": "notice_added", "key": "notice.loan_due_soon", "severity": "urgent"}), "sfx_alarm",
		"urgent")
	eq(d.sound_for({"type": "notice_added", "key": "notice.promotion_offered", "severity": "info"}), "",
		"plain info notices are quiet")
	eq(d.sound_for({"type": "upgrade_done"}), "sfx_upgrade_done", "a plain event")
	eq(d.sound_for({"type": "nothing_here"}), "", "an event without sound")
	d.free()


func test_phase_music_and_event_sounds() -> void:
	var d := _director()
	eq(d.music_for_phase("day"), "music_city_day", "day music")
	eq(d.music_for_phase("night"), "music_night", "night music")
	var events: Dictionary = d.config["events"]
	for type: String in events:
		var v: Variant = events[type]
		for id: Variant in (v if v is Array else [v]):
			check(d.section_of(str(id)) != "", "event %s -> a known id" % type)
	d.free()


func test_event_sounds_by_value_and_lists() -> void:
	var d := _director()
	eq(d.sound_for({"type": "work_started", "zone": "furnace"}), "sfx_furnace", "the furnace has its own sound")
	eq(d.sound_for({"type": "work_started", "zone": "anvil"}), "", "the anvil starting is quiet")
	eq(d.sound_for({"type": "work_done", "zone": "anvil"}), "sfx_hammer", "else the plain type")
	eq(d.sound_for({"type": "phase_changed", "phase": "dawn"}), "sfx_rooster", "dawn")
	eq(d.sound_for({"type": "phase_changed", "phase": "night"}), "", "night: none")
	eq(d.sound_for({"type": "gold_changed", "category": "counter_sales"}), "sfx_sale", "counter sale")
	eq(d.sound_for({"type": "gold_changed", "category": "wages"}), "", "other gold changes are quiet")
	eq(d.sounds_for({"type": "market_bought"}), ["sfx_coins", "voice_market_deal"] as Array[String], "a list")
	d.free()


func test_ui_sounds_and_panels() -> void:
	var d := _director()
	eq(d.ui_sound("button"), "sfx_ui_click", "buttons click")
	check(d.is_panel("market_panel") and d.is_panel("board_panel"), "market and board are panels")
	check(not d.is_panel("character_panel"), "the character panel follows the selection: quiet")
	eq(d.panel_open_extra("market_panel"), "voice_market_vendor", "the vendor greets")
	eq(d.panel_open_extra("board_panel"), "voice_board_crier", "the crier calls")
	for what: String in ["button", "pause", "resume", "panel_open", "panel_close"]:
		check(d.section_of(d.ui_sound(what)) != "", "ui %s -> a known id" % what)
	var b := Button.new()
	d._on_node_added(b)
	d._on_node_added(b)
	eq(b.pressed.get_connections().size(), 1, "a button is hooked once")
	d._dummy = true
	b.pressed.emit()
	check(d._last.has("sfx_ui_click"), "pressing a hooked button clicks")
	var p := Control.new()
	p.scene_file_path = "res://game/ui/market_panel.tscn"
	d._on_node_added(p)
	d._on_node_added(p)
	eq(p.visibility_changed.get_connections().size(), 1, "a panel is hooked once")
	b.free()
	p.free()
	d.free()


func test_cooldown_keeps_voices_from_repeating() -> void:
	var d := _director()
	d._dummy = true
	check(d.play("voice_market_vendor"), "first time: it sounds")
	check(not d.play("voice_market_vendor"), "again at once: the cooldown holds it")
	check(d.play("sfx_coins"), "an id without cooldown always sounds")
	check(d.play("sfx_coins"), "and again")
	d.free()
