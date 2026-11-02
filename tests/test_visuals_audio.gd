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
		check(d.section_of(str(events[type])) != "", "event %s -> a known id" % type)
	d.free()
