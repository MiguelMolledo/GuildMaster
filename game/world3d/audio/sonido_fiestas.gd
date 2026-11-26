extends RefCounted
## The sound of the festivals in the town (scripts/fiestas_pueblo.gd; data/sonido.json `sucesos` and `fiestas`).
## The festival node is in group "suceso" and says which festival stands (`suceso`: its def id); this maps it to a
## kind (fiesta, boda, feria, carnaval, torneo, procesion...) for the music rules and the ambient layers, and puts in
## their place, read from that node: the lit bonfires (a looped fire on the players of the looped sources), the
## giants and big-heads of the carnival (drum and dulzaina following them), the bells rung "al vuelo" while a
## procession walks and around a wedding mass, and the lances and cheers of the tournament at the lists.

var S
var vida
var cfg: Dictionary
var fp = null          # the festival node (fiestas_pueblo.gd), when there is one
var def := ""          # the festival standing now (def id)
var kind := ""         # its kind (sucesos)
var acts := {}         # acts of its programme already begun -> true
var _bell_next := 0.0
var _joust_next := 0.0
var _look := 0.0
var rng := RandomNumberGenerator.new()


func _init(director, v) -> void:
	S = director
	vida = v
	cfg = director.cfg
	rng.randomize()


func dbg(msg: String) -> void:
	if OS.is_debug_build():
		print("[Sonido] " + msg)


func _now() -> float:
	return float(S.clock)


## the kind of the festival standing now ("" if none); also from --suceso= (a kind or a def id)
func kind_now(forced: String) -> String:
	if forced != "":
		return String(cfg.sucesos.get(forced, forced))
	return kind


func tick(dt: float) -> void:
	_look -= dt
	if _look <= 0.0:
		_look = 1.0
		var n = S.get_tree().get_first_node_in_group("suceso")
		fp = n if n != null and n.get("insts") != null else null
	var d := ""
	if fp != null and is_instance_valid(fp):
		d = String(fp.get("suceso"))
	if d != def:
		def = d
		kind = String(cfg.sucesos.get(def, "")) if def != "" else ""
		dbg("festival: %s (%s)" % [def if def != "" else "-", kind if kind != "" else "-"])
	_clear_emitters()
	acts.clear()
	if def == "" or fp == null:
		return
	var t: float = S.town.t_min
	var inst: Dictionary = {}
	for i in fp.insts:
		if String(i.def) == def and i.mounted:
			inst = i
			break
	if inst.is_empty():
		return
	for s in inst.schedule:
		if t >= float(s.at):
			acts[String(s.what)] = true
	var fc: Dictionary = cfg.fiestas
	_fires(fc.hoguera, t)
	_comparsa(fc.comparsa)
	_bells(fc.campanas_vuelo, inst, t)
	_joust(fc.torneo, inst, t)


# ---------------------------------------------------------------- looped: bonfires and the comparsa
func _clear_emitters() -> void:
	var keep := []
	for e in vida.emitters:
		if not String(e.key).begins_with("fp_"):
			keep.append(e)
	vida.emitters = keep


func _add(key: String, id: String, pos: Vector3, db: float, r: float) -> void:
	vida.emitters.append({key = key, kind = "fiesta", id = id, pos = pos, db = db, r = r, bus = "Efectos", bld = "", g = 0.0})


func _fires(c: Dictionary, t: float) -> void:
	var i := 0
	for f in fp.get("_flames"):
		var m = f[0]
		if not is_instance_valid(m) or not (m as Node3D).is_visible_in_tree():
			continue
		if t < float(f[2]) and f[2] != INF:
			continue
		if not _is_piece(m, String(c.piezas)):
			continue  # a torch or a candle, not a bonfire
		_add("fp_fire%d" % i, String(c.id), (m as Node3D).global_position + Vector3(0, 0.8, 0), float(c.volume_db), float(c.radius))
		i += 1


static func _is_piece(n: Node, prefix: String) -> bool:
	## the flames hang from the piece they burn on (its node is named as the catalogue piece)
	while n != null:
		if String(n.name).begins_with(prefix):
			return true
		n = n.get_parent()
	return false


func _comparsa(c: Dictionary) -> void:
	var sum := Vector3.ZERO
	var n := 0
	for w in fp.get("_walkers"):
		var node = w.get("node")
		if not String(w.inst.def) in c.defs or not is_instance_valid(node) or not (node as Node3D).is_visible_in_tree():
			continue
		sum += (node as Node3D).global_position
		n += 1
	if n > 0:
		_add("fp_comparsa", String(c.id), sum / n + Vector3(0, 1.5, 0), float(c.volume_db), float(c.radius))


# ---------------------------------------------------------------- bells "al vuelo", the tournament
func _bells(c: Dictionary, inst: Dictionary, t: float) -> void:
	var on := false
	var lay: Dictionary = fp.layouts.get(def, {})
	if lay.has("procession"):
		var pr: Dictionary = lay.procession
		var at0: float = fp.sched_at(inst, String(pr.get("at", "procession")))
		if at0 != INF and not pr.get("loop", false):
			on = t >= at0 - float(c.antes) and t <= at0 + float(pr.get("minutes", 100))
	for w in c.actos:
		var at: float = fp.sched_at(inst, String(w))
		if at != INF and t >= at - float(c.antes) and t <= at + float(c.minutos):
			on = true
	if on and _now() >= _bell_next:
		_bell_next = _now() + rng.randf_range(float(c.every[0]), float(c.every[1]))
		vida._ring(String(c.id), float(c.volume_db))
		vida._count("campanas_vuelo")


func _joust(c: Dictionary, inst: Dictionary, t: float) -> void:
	if not String(def) in c.defs:
		return
	var a: float = fp.sched_at(inst, String(c.desde))
	var b: float = fp.sched_at(inst, String(c.hasta))
	if a == INF or t < a or (b != INF and t >= b) or _now() < _joust_next:
		return
	_joust_next = _now() + rng.randf_range(float(c.every[0]), float(c.every[1]))
	var at := Vector3.INF
	for pl in inst.placed:
		if pl.get("group", false):
			var g: Vector2 = pl.g
			at = Vector3(g.x, 1.5, g.y)
			break
	if at == Vector3.INF:
		return
	var g2: float = S.gain_at(at, float(c.radius))
	if S.pool.play_at(String(c.choque), at, g2, float(c.volume_db), {"tag": "joust", "max": 1, "jitter": 0.06}):
		vida._count("lanzas")
		S.get_tree().create_timer(rng.randf_range(0.25, 0.6), false).timeout.connect(func():
			if S.pool.play_at(String(c.vitores), at, g2, float(c.vitores_db), {"tag": "cheer", "max": 1, "bus": "Voces", "jitter": 0.04}):
				vida._count("vitores"))
