class_name AudioDirector
extends Node
## Plays sounds and music by id (data/audio.json), never by file: the file of an id is found by convention
## (VisualPaths.audio_files: assets/audio/<section>/<id>.ogg|wav or its variants _01, _02...). An id without a file
## stays silent and says so once in debug. Lives inside app.tscn (not an autoload: there are at most 5). Listens to
## Events: the sound of each sim event of the player's family (audio.json "events") and the music of the phase of the
## day ("phase_music"). Ambient loops on their own player: "phase_ambient" (phase -> id, in the town) and
## "interior_ambient" (building type -> id, while an interior is shown; a type without an entry is quiet inside).
## A notice (event notice_added) sounds by its key first ("notice.objective_done") and else by its severity
## ("notice_added.urgent"), so one notice never sounds twice. Other events try "<type>.<value>" first for their zone,
## phase, category, stall, activity or def ("work_started.furnace", "phase_changed.dawn", "town_state.dice"), then the
## plain type. An entry is one id or a list of ids. Events listed in "selected_only" sound only when the selected
## person is in them (actor, a, b or character: footsteps, greetings). An id with "cooldown_s" does not sound again
## until that many real seconds have passed (voices).
## The UI ("ui"): every button of the tree clicks ("button"; not when the click itself pauses or resumes the game:
## then the pause sound is enough), the panels named in "panels" (scene names of game/ui/) sound when they open and
## close, "panel_open_by" adds a sound to one panel opening (the vendor, the crier), pausing / resuming has its own
## sound (not when a game starts nor while a screen of "screen_music" is shown), and while a screen of "screen_music" is shown its music plays instead of the
## phase's, with no ambient (the title theme on the new game screen). All from here: no panel calls the
## AudioDirector. Events of "positional" (town life: dice, greetings) sound where they happen: at the view of their
## person in the town (character, a or actor), heard as the camera nears it (max_distance, attenuation), and not while
## an interior is shown. Buses are fixed in default_bus_layout.tres (Master, Music, Sfx, Ambient, Voice, Ui): each id goes to the bus of its section unless it names another. The pitch jitter is
## random, but only in the view. With the Dummy audio driver (headless runs) nothing is heard, so no playback starts:
## Godot leaks a playback stopped while quitting there (resources still in use at exit).

const PATH: String = "res://data/audio.json"
const SECTIONS: Dictionary = {"music": "Music", "sfx": "Sfx", "ambient": "Ambient", "voice": "Voice"}
const POOL: int = 8

var config: Dictionary = {}
var music_id: String = ""            # what the music player plays now ("" = nothing)
var ambient_id: String = ""          # what the ambient player plays now ("" = nothing)
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer = null
var _ambient: AudioStreamPlayer = null
var _next: int = 0
var _silent: Dictionary = {}         # id -> true: reported once
var _game: Node = null
var _check: float = 0.0
var _dummy: bool = false             # Dummy audio driver (headless, --audio-driver Dummy): nothing is heard
var _last: Dictionary = {}           # id -> Time.get_ticks_msec() of its last play (cooldown_s)
var _paused: Variant = null          # Game.paused as last seen (null = not seen yet)
var _panels: Dictionary = {}         # panel node instance id -> visible as last heard (sound only on a real change)
var _ready_ms: int = 0               # panels setting themselves up right after start do not sound
var _started_frame: int = -100       # frame of the last Game.started (its unpause is not a "resume")
var _click_pending: bool = false     # a button click waiting for the end of the frame
var _pause_frame: int = -100         # frame in which the pause / resume sound played
var _screens: Dictionary = {}        # screen node instance id -> [node, screen name] (ui.screen_music)
const EVENT_FIELDS: Array[String] = ["zone", "phase", "category", "stall", "activity", "def"]
const SELECTED_FIELDS: Array[String] = ["actor", "a", "b", "character"]
const POSITION_FIELDS: Array[String] = ["character", "a", "actor"]
const POOL_2D: int = 6
var _players_2d: Array[AudioStreamPlayer2D] = []
var _next_2d: int = 0


func _ready() -> void:
	load_config()
	_dummy = AudioServer.get_driver_name() == "Dummy"
	for i: int in POOL:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_players.append(p)
	for i: int in POOL_2D:
		var p2 := AudioStreamPlayer2D.new()
		p2.name = "Sfx2D%d" % i
		add_child(p2)
		_players_2d.append(p2)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "Ambient"
	add_child(_ambient)
	var events := get_node_or_null("/root/Events")
	if events != null:
		events.sim_event.connect(on_sim_event)
	_game = get_node_or_null("/root/Game")
	if _game != null and _game.has_signal("started"):
		_game.connect("started", func() -> void: _started_frame = Engine.get_process_frames())
	_ready_ms = Time.get_ticks_msec()
	_check = 0.5                         # the first music waits a moment: the new game screen may be about to show
	get_tree().node_added.connect(_on_node_added)
	_hook_tree.call_deferred(get_tree().root)
	_log("ready (sounds=%d, events=%d, driver=%s)" % [ids().size(), (config.get("events", {}) as Dictionary).size(),
		AudioServer.get_driver_name()])


func load_config() -> void:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK or not json.data is Dictionary:
		push_error("audio: cannot read %s" % PATH)
		config = {}
		return
	config = json.data


## Every sound id of audio.json.
func ids() -> Array:
	var out: Array = []
	for sec: String in SECTIONS:
		out.append_array((config.get(sec, {}) as Dictionary).keys())
	return out


## The section of `id` ("" if audio.json does not know it).
func section_of(id: String) -> String:
	for sec: String in SECTIONS:
		if (config.get(sec, {}) as Dictionary).has(id):
			return sec
	return ""


## The bus of `id`: its own "bus", else its section's.
func bus_of(id: String) -> String:
	var sec := section_of(id)
	if sec == "":
		return "Master"
	return str((config[sec][id] as Dictionary).get("bus", SECTIONS[sec]))


## Plays the sound `id` once (at `at`, a world position, if it is a Vector2). False if it is unknown, has no file yet
## (silence) or is cooling down.
func play(id: String, at: Variant = null) -> bool:
	var stream := _stream(id)
	if stream == null:
		return false
	var entry: Dictionary = config[section_of(id)][id]
	var cool := int(float(entry.get("cooldown_s", 0.0)) * 1000.0)
	var now := Time.get_ticks_msec()
	if cool > 0 and _last.has(id) and now - int(_last[id]) < cool:
		return false
	_last[id] = now
	if _dummy:
		return true
	if at is Vector2:
		var q := _players_2d[_next_2d]
		_next_2d = (_next_2d + 1) % _players_2d.size()
		var pos_cfg: Dictionary = config.get("positional", {})
		q.stream = stream
		q.bus = _bus(bus_of(id))
		q.volume_db = float(entry.get("volume_db", 0.0))
		q.max_distance = float(pos_cfg.get("max_distance", 600.0))
		q.attenuation = float(pos_cfg.get("attenuation", 1.5))
		var j2 := clampf(float(entry.get("pitch_jitter", 0.0)), 0.0, 0.5)
		q.pitch_scale = 1.0 + randf_range(-j2, j2)
		q.global_position = at
		q.play()
		_log("play %s at %s (bus=%s, volume_db=%.1f)" % [id, at, q.bus, q.volume_db])
		return true
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.bus = _bus(bus_of(id))
	p.volume_db = float(entry.get("volume_db", 0.0))
	var j := clampf(float(entry.get("pitch_jitter", 0.0)), 0.0, 0.5)
	p.pitch_scale = 1.0 + randf_range(-j, j)
	p.play()
	_log("play %s (bus=%s, volume_db=%.1f)" % [id, p.bus, p.volume_db])
	return true


## Starts the music `id` (looping as its file is imported); "" stops it. Same id = keeps playing.
func play_music(id: String) -> void:
	if id == music_id:
		return
	music_id = id
	_loop_on(_music, id, "music")


## Starts the ambient loop `id`; "" stops it. Same id = keeps playing.
func play_ambient(id: String) -> void:
	if id == ambient_id:
		return
	ambient_id = id
	_loop_on(_ambient, id, "ambient")


func _loop_on(player: AudioStreamPlayer, id: String, what: String) -> void:
	player.stop()
	if id == "":
		_log("%s off" % what)
		return
	var stream := _stream(id)
	if stream == null:
		return
	if _dummy:
		_log("%s %s (dummy driver: not started)" % [what, id])
		return
	player.stream = stream
	player.bus = _bus(bus_of(id))
	player.volume_db = float((config[section_of(id)][id] as Dictionary).get("volume_db", 0.0))
	player.play()
	_log("%s %s" % [what, id])


## The music for the phase of the day (audio.json "phase_music").
func music_for_phase(phase: String) -> String:
	return str((config.get("phase_music", {}) as Dictionary).get(phase, ""))


## The ambient for the phase of the day in the town, or for the building type of the interior shown ("" = town).
func ambient_for(phase: String, interior_type: String) -> String:
	if interior_type != "":
		return str((config.get("interior_ambient", {}) as Dictionary).get(interior_type, ""))
	return str((config.get("phase_ambient", {}) as Dictionary).get(phase, ""))


## The first sound id of a sim event (audio.json "events"; "" = none). Notices: by key, else by severity.
func sound_for(e: Dictionary) -> String:
	var all := sounds_for(e)
	return all[0] if not all.is_empty() else ""


func _event_entry(e: Dictionary) -> Variant:
	var events: Dictionary = config.get("events", {})
	var type := str(e.get("type", ""))
	if type == "notice_added":
		var key := str(e.get("key", ""))
		if events.has(key):
			return events[key]
		return events.get("notice_added.%s" % str(e.get("severity", "")), null)
	for f: String in EVENT_FIELDS:
		if e.has(f) and events.has("%s.%s" % [type, str(e[f])]):
			return events["%s.%s" % [type, str(e[f])]]
	return events.get(type, null)


## Every sound of a sim event: an entry of "events" is one id or a list of ids (coins and the vendor's voice).
func sounds_for(e: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var v: Variant = _event_entry(e)
	if v is Array:
		for x: Variant in v:
			out.append(str(x))
	elif v != null and str(v) != "":
		out.append(str(v))
	return out


## A sim event: its sounds, if it concerns the player's family (and the selected person, for "selected_only").
func on_sim_event(e: Dictionary) -> void:
	var ids_ := sounds_for(e)
	if ids_.is_empty() or not _concerns_player(e):
		return
	var type := str(e.get("type", ""))
	if type in (config.get("selected_only", []) as Array) and not _has_selected(e):
		return
	var at: Variant = null
	if type in ((config.get("positional", {}) as Dictionary).get("events", []) as Array):
		at = _position_of(e)
		if at == null:
			return
	for id: String in ids_:
		play(id, at)


## Where an event happens in the town: the view of its person (null = not in the town view, or an interior is shown).
func _position_of(e: Dictionary) -> Variant:
	var app := get_parent()
	if app == null or not app.has_method("world"):
		return null
	var bld: Variant = app.get("interior_building")
	if bld != null and str(bld) != "":
		return null
	var w: Object = app.call("world")
	if w == null or not w.has_method("view_of"):
		return null
	for f: String in POSITION_FIELDS:
		if e.has(f):
			var v: Variant = w.call("view_of", str(e[f]))
			if v != null and v is Node2D:
				return (v as Node2D).global_position
	return null


func _has_selected(e: Dictionary) -> bool:
	var sel := _selected()
	if sel == "":
		return false
	for f: String in SELECTED_FIELDS:
		if str(e.get(f, "")) == sel:
			return true
	return false


## The music of a screen (audio.json ui.screen_music, by scene name of game/ui/; "" = none).
func screen_music(screen: String) -> String:
	return str(((config.get("ui", {}) as Dictionary).get("screen_music", {}) as Dictionary).get(screen, ""))


## The sound id of a UI moment ("button", "pause", "resume", "panel_open", "panel_close"; "" = none).
func ui_sound(what: String) -> String:
	return str((config.get("ui", {}) as Dictionary).get(what, ""))


## Whether `panel` (a scene name of game/ui/) sounds when it opens and closes.
func is_panel(panel: String) -> bool:
	return panel in ((config.get("ui", {}) as Dictionary).get("panels", []) as Array)


## The extra sound of `panel` opening (audio.json ui.panel_open_by; "" = none).
func panel_open_extra(panel: String) -> String:
	return str(((config.get("ui", {}) as Dictionary).get("panel_open_by", {}) as Dictionary).get(panel, ""))


func _hook_tree(n: Node) -> void:
	_on_node_added(n)
	for c: Node in n.get_children():
		_hook_tree(c)


## Every button clicks; the listed panels sound on open / close. Connected once per node.
func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		if not b.pressed.is_connected(_on_button):
			b.pressed.connect(_on_button)
	elif n is Control and n.scene_file_path != "":
		var scene := n.scene_file_path.get_file().get_basename()
		if is_panel(scene) and not _panels.has(n.get_instance_id()):
			_panels[n.get_instance_id()] = (n as Control).visible
			(n as Control).visibility_changed.connect(_on_panel_visibility.bind(n, scene))
		if screen_music(scene) != "":
			_screens[n.get_instance_id()] = [n, scene]


## The click waits for the end of the frame: if the button paused or resumed the game, the pause sound says it.
func _on_button() -> void:
	if not _click_pending:
		_click_pending = true
		_flush_click.call_deferred()


func _flush_click() -> void:
	_click_pending = false
	if _game != null and _paused != null:
		var p: Variant = _game.get("paused")
		if p != null and bool(p) != bool(_paused) and not _game_just_started():
			return                           # paused this frame and the director has not seen it yet
	if _pause_frame == Engine.get_process_frames():
		return                               # the pause sound already played this frame
	var id := ui_sound("button")
	if id != "":
		play(id)


func _game_just_started() -> bool:
	return Engine.get_process_frames() - _started_frame <= 2


## The music of the screen shown now ("" = none: the phase's music plays).
func _shown_screen_music() -> String:
	for k: Variant in _screens.keys():
		var pair: Array = _screens[k]
		if not is_instance_valid(pair[0]):
			_screens.erase(k)
			continue
		var c := pair[0] as Control
		if c.is_visible_in_tree():
			return screen_music(str(pair[1]))
	return ""


func _on_panel_visibility(n: Control, panel: String) -> void:
	var key := n.get_instance_id()
	if not n.is_inside_tree() or bool(_panels.get(key, not n.visible)) == n.visible:
		return
	_panels[key] = n.visible
	if Time.get_ticks_msec() - _ready_ms < 1000:
		return
	var id := ui_sound("panel_open" if n.visible else "panel_close")
	if id != "":
		play(id)
	if n.visible and panel_open_extra(panel) != "":
		play(panel_open_extra(panel))
	_log("panel %s %s" % [panel, "open" if n.visible else "closed"])


func _process(delta: float) -> void:
	if _game != null:
		var p: Variant = _game.get("paused")
		if p != null and _paused != null and bool(p) != bool(_paused) and not _game_just_started() \
				and _shown_screen_music() == "":
			var id := ui_sound("pause" if bool(p) else "resume")
			if id != "":
				play(id)
				_pause_frame = Engine.get_process_frames()
		_paused = p
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var screen := _shown_screen_music()
	if screen != "":
		play_music(screen)
		play_ambient("")
		return
	if _game == null or _game.get("sim") == null:
		return
	var sim: Sim = _game.get("sim")
	var phase := Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time)
	play_music(music_for_phase(phase))
	play_ambient(ambient_for(phase, _interior_type(sim)))


## The building type of the interior the app shows ("" = the town or no app).
func _interior_type(sim: Sim) -> String:
	var app := get_parent()
	if app == null:
		return ""
	var bld: Variant = app.get("interior_building")
	if bld == null or str(bld) == "":
		return ""
	return str(sim.state.buildings.get(str(bld), {}).get("type", ""))


## The person selected in the town ("" = none or no app).
func _selected() -> String:
	var app := get_parent()
	if app == null or not app.has_method("world"):
		return ""
	var w: Variant = app.call("world")
	if w == null:
		return ""
	var sel: Variant = (w as Object).get("selected_id")
	return "" if sel == null else str(sel)


func _concerns_player(e: Dictionary) -> bool:
	if _game == null or _game.get("sim") == null:
		return true
	var st: WorldState = (_game.get("sim") as Sim).state
	var fam := SimQuery.player_family(st)
	if e.has("family"):
		return str(e["family"]) == fam
	if e.has("actor"):
		return str(st.characters.get(str(e["actor"]), {}).get("family", "")) == fam
	if e.has("building"):
		return SimQuery.building_family(st, str(e["building"])) == fam
	return true


func _stream(id: String) -> AudioStream:
	var sec := section_of(id)
	if sec == "":
		if not _silent.has(id):
			_silent[id] = true
			_log("unknown sound id %s (not in data/audio.json)" % id)
		return null
	var files := VisualPaths.audio_files(sec, id)
	if files.is_empty():
		if not _silent.has(id):
			_silent[id] = true
			_log("no file for %s: silence (expected assets/audio/%s/%s.ogg or .wav)" % [id, sec, id])
		return null
	return load(files[randi() % files.size()]) as AudioStream


func _bus(name_: String) -> String:
	if AudioServer.get_bus_index(name_) >= 0:
		return name_
	_log("bus %s does not exist: Master" % name_)
	return "Master"


func _log(msg: String) -> void:
	if OS.is_debug_build():
		print("[Audio] %s" % msg)
