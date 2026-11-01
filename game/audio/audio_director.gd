class_name AudioDirector
extends Node
## Plays sounds and music by id (data/audio.json), never by file: the file of an id is found by convention
## (VisualPaths.audio_files: assets/audio/<section>/<id>.ogg|wav or its variants _01, _02...). An id without a file
## stays silent and says so once in debug. Lives inside app.tscn (not an autoload: there are at most 5). Listens to
## Events: the sound of each sim event of the player's family (audio.json "events") and the music of the phase of the
## day ("phase_music"). Buses are fixed in default_bus_layout.tres (Master, Music, Sfx, Ambient, Voice, Ui): each id
## goes to the bus of its section unless it names another. The pitch jitter is random, but only in the view.

const PATH: String = "res://data/audio.json"
const SECTIONS: Dictionary = {"music": "Music", "sfx": "Sfx", "ambient": "Ambient", "voice": "Voice"}
const POOL: int = 8

var config: Dictionary = {}
var music_id: String = ""            # what the music player plays now ("" = nothing)
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer = null
var _next: int = 0
var _silent: Dictionary = {}         # id -> true: reported once
var _game: Node = null
var _check: float = 0.0


func _ready() -> void:
	load_config()
	for i: int in POOL:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)
	var events := get_node_or_null("/root/Events")
	if events != null:
		events.sim_event.connect(on_sim_event)
	_game = get_node_or_null("/root/Game")
	_log("ready (sounds=%d, events=%d)" % [ids().size(), (config.get("events", {}) as Dictionary).size()])


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


## Plays the sound `id` once. False if it is unknown or has no file yet (silence).
func play(id: String) -> bool:
	var stream := _stream(id)
	if stream == null:
		return false
	var entry: Dictionary = config[section_of(id)][id]
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
	_music.stop()
	if id == "":
		return
	var stream := _stream(id)
	if stream == null:
		return
	_music.stream = stream
	_music.bus = _bus(bus_of(id))
	_music.volume_db = float((config[section_of(id)][id] as Dictionary).get("volume_db", 0.0))
	_music.play()
	_log("music %s" % id)


## The music for the phase of the day (audio.json "phase_music").
func music_for_phase(phase: String) -> String:
	return str((config.get("phase_music", {}) as Dictionary).get(phase, ""))


## A sim event: its sound (audio.json "events"), if it concerns the player's family.
func on_sim_event(e: Dictionary) -> void:
	var id := str((config.get("events", {}) as Dictionary).get(str(e.get("type", "")), ""))
	if id == "" or not _concerns_player(e):
		return
	play(id)


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0 or _game == null or _game.get("sim") == null:
		return
	_check = 1.0
	var sim: Sim = _game.get("sim")
	play_music(music_for_phase(Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time)))


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
