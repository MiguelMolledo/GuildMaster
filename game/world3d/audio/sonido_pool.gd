extends RefCounted
## The sound library and the players of the town (scripts/audio/sonido.gd).
## - Library: a sound id -> its files, assets/audio/<section>/<id>.ogg or the variants <id>_01.ogg, <id>_02.ogg...
##   (one at random each time). Loaded once; loops are flagged at load. A missing id is silence (one log line).
## - One-shots in their place: a fixed pool of AudioStreamPlayer3D. The distance gain is ours (attenuation off, so
##   the pan still follows the listener): gain = (1 - d / radius)^2 on the ground. Per-tag limit (`max`) and a
##   global limit of voices; when the pool is full the quietest playing one is taken if the new one is louder.
## - One-shots without place (far bells, dogs far away, thunder): a small pool of AudioStreamPlayer.

const SECTIONS := ["sfx", "ambient", "music", "voice"]

var host: Node
var _lib := {}       # id -> Array[AudioStream] (empty: no file)
var _loops := {}     # id -> true when its streams loop
var _missing := {}
var pool: Array = [] # {p: AudioStreamPlayer3D, tag, gain, until}
var flat: Array = [] # {p: AudioStreamPlayer, tag, until}
var stats := {"played": 0, "refused": 0, "stolen": 0, "peak": 0}
var rng := RandomNumberGenerator.new()


func _init(h: Node, n_pool: int) -> void:
	host = h
	rng.randomize()
	for i in n_pool:
		var p := AudioStreamPlayer3D.new()
		p.name = "Golpe%02d" % i
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.max_polyphony = 1
		p.panning_strength = 1.0
		host.add_child(p)
		pool.append({p = p, tag = "", gain = 0.0, until = 0.0})
	for i in 4:
		var q := AudioStreamPlayer.new()
		q.name = "Lejano%d" % i
		host.add_child(q)
		flat.append({p = q, tag = "", until = 0.0})


static func dbg(msg: String) -> void:
	if OS.is_debug_build():
		print("[Sonido] " + msg)


## GuildMaster-3d: where the streams of an id come from (AudioDirector.streams); unset in the prueba (by file).
static var resolver: Callable = Callable()


func _load_file(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path)
	if FileAccess.file_exists(path):
		return AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	return null


## streams of an id (cached). loop: the ambient beds and the music loop, the one-shots do not.
func streams(id: String, loop := false) -> Array:
	if _lib.has(id):
		return _lib[id]
	var out: Array = []
	if resolver.is_valid():   # GuildMaster: by id through the AudioDirector (data/audio.json)
		out = resolver.call(id)
	for sec in SECTIONS if not resolver.is_valid() else []:
		var base := "res://assets/audio/%s/%s" % [sec, id]
		var s := _load_file(base + ".ogg")
		if s:
			out.append(s)
		for i in range(1, 10):
			var v := _load_file("%s_%02d.ogg" % [base, i])
			if v == null:
				break
			out.append(v)
		if not out.is_empty():
			break
	for s in out:
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = loop
	_lib[id] = out
	if out.is_empty() and not _missing.has(id):
		_missing[id] = true
		dbg("no file for %s (silence)" % id)
	elif OS.is_debug_build():
		dbg("loaded %s: %d file(s)%s" % [id, out.size(), " loop" if loop else ""])
	return out


func has(id: String) -> bool:
	return not streams(id).is_empty()


func pick(id: String, loop := false) -> AudioStream:
	var a := streams(id, loop)
	return null if a.is_empty() else a[rng.randi() % a.size()]


func missing() -> Array:
	return _missing.keys()


func _now() -> float:
	return float(host.clock)


func count(tag: String) -> int:
	var n := 0
	var now := _now()
	for e in pool:
		if e.tag == tag and e.until > now:
			n += 1
	for e in flat:
		if e.tag == tag and e.until > now:
			n += 1
	return n


func busy() -> int:
	var n := 0
	var now := _now()
	for e in pool:
		if e.until > now:
			n += 1
	for e in flat:
		if e.until > now:
			n += 1
	return n


## A one-shot at a ground point. gain: linear 0..1 from the distance (the caller's curve); db: level of the sound.
## opts: bus, tag (limit group), max (per tag), jitter (pitch), limit (global voices). Returns false if refused.
func play_at(id: String, pos: Vector3, gain: float, db: float, opts := {}) -> bool:
	if gain <= 0.003:
		return false
	var s := pick(id)
	if s == null:
		return false
	var tag := String(opts.get("tag", id))
	var now := _now()
	if count(tag) >= int(opts.get("max", 3)) or busy() >= int(opts.get("limit", 20)):
		stats.refused += 1
		return false
	var slot: Dictionary = {}
	for e in pool:
		if e.until <= now:
			slot = e
			break
	if slot.is_empty():
		var low: Dictionary = pool[0]
		for e in pool:
			if e.gain < low.gain:
				low = e
		if low.gain >= gain:
			stats.refused += 1
			return false
		slot = low
		stats.stolen += 1
	var p: AudioStreamPlayer3D = slot.p
	p.stream = s
	p.bus = String(opts.get("bus", "Efectos"))
	p.volume_db = db + linear_to_db(gain)
	p.pitch_scale = 1.0 + rng.randf_range(-1.0, 1.0) * float(opts.get("jitter", 0.05))
	p.global_position = pos
	p.play()
	slot.tag = tag
	slot.gain = gain
	slot.until = now + s.get_length() / p.pitch_scale + 0.05
	stats.played += 1
	stats.peak = maxi(int(stats.peak), busy())
	return true


## A one-shot with no place (heard from far away: on the Lejos bus by default).
func play_flat(id: String, db: float, opts := {}) -> bool:
	var s := pick(id)
	if s == null:
		return false
	var tag := String(opts.get("tag", id))
	var now := _now()
	if count(tag) >= int(opts.get("max", 2)):
		stats.refused += 1
		return false
	for e in flat:
		if e.until <= now:
			var p: AudioStreamPlayer = e.p
			p.stream = s
			p.bus = String(opts.get("bus", "Lejos"))
			p.volume_db = db
			p.pitch_scale = 1.0 + rng.randf_range(-1.0, 1.0) * float(opts.get("jitter", 0.04))
			p.play()
			e.tag = tag
			e.until = now + s.get_length() / p.pitch_scale + 0.05
			stats.played += 1
			return true
	stats.refused += 1
	return false
