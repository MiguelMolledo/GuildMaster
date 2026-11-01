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
	check(not d._stream("sfx_hammer"), "no file yet: no stream")
	check(not d._stream("nope"), "unknown id: no stream")
	d.free()


func test_phase_music_and_event_sounds() -> void:
	var d := _director()
	eq(d.music_for_phase("day"), "music_city_day", "day music")
	eq(d.music_for_phase("night"), "music_night", "night music")
	var events: Dictionary = d.config["events"]
	for type: String in events:
		check(d.section_of(str(events[type])) != "", "event %s -> a known id" % type)
	d.free()
