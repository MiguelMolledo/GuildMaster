extends SceneTree
## Audit of the interiors in place (docs/interior3d.md, «Revisión de los edificios de oficio»): every
## data/interiors/<type>_sitio*.json at each level it serves, as written and mirrored, without upgrades and with all
## of them, built with Interior3DBuilder (the real boxes of the pieces) and checked for:
##   stairs  foot and landing free with a free tile beside them, the flight does not cut the way to any place (nor
##           makes it go round more than 2 tiles), it does not stand on the door, a counter or a shop window, the
##           landing is not against a partition or a piece, and it does not climb towards the camera of the open
##           house (the town opens a house looking at its front: a flight that climbs to the front is seen edge-on)
##   ways    from the street door and from each landing to every place, seat, bed and counter; no place reached only
##           through another one; the main way (door -> counter -> places -> stair) one tile wide with nothing on it
##   trade   every fire under its chimney and its flue up through the floors above, the anvil by the furnace and the
##           quench at hand, the counter open to the customers, the store by the workshop, beds upstairs and not in
##           the workshop, nothing behind the door, no piece through a wall or a partition, floating or sunk, no two
##           pieces inside each other, seats with a back looking at their table
## Run:  godot --headless --path . -s tools/rv_auditoria.gd [-- --solo=forge,tavern_inn:2] [--salida=out/rv_auditoria.json]
##       python3 tools/rv_tabla.py        the table of docs/interior3d.md from out/rv_auditoria.json

const BEDS := ["cama_estrecha", "cama_huesped", "cama_dosel", "litera", "jergon", "catre"]
const QUENCH := ["quench_tub", "stone_trough", "pila"]
const FOCUS := ["mesa", "escritorio", "hogar", "barra", "estrado", "mesa_concejo", "mostrador", "atril"]
const BACK_SEATS := ["sillon", "silla_alcalde", "banco_respaldo"]
const ZONE_NAMES := {"furnace": "Fragua", "anvil": "Yunque", "counter": "Mostrador", "storage": "Almacén"}
const WALL_IN := 0.31   # the kit wall stands 0.31 m inside the line of the house

var args := {}
var out := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var list := SituShell.all()
	if args.has("solo"):
		var keep := []
		for e: Dictionary in list:
			for s: String in String(args.solo).split(","):
				if e.type == s.get_slice(":", 0) and (not s.contains(":") or int(s.get_slice(":", 1)) == int(e.level)):
					keep.append(e)
		list = keep
	var t0 := Time.get_ticks_msec()
	for e: Dictionary in list:
		var lv := maxi(int(e.level), 1)
		var key := "%s:%d" % [e.type, lv]
		var row := {"type": e.type, "level": lv, "path": e.path, "runs": {}}
		for mirror in [false, true]:
			for ups in ["base", "todas"]:
				var tag: String = ("espejo_" if mirror else "") + String(ups)
				row.runs[tag] = audit(String(e.path), String(e.type), lv, mirror, ups == "todas")
		# what fails anywhere, once
		var fails := {}
		var notes := {}
		for tag in row.runs:
			for f: String in row.runs[tag].fails:
				if not fails.has(f):
					fails[f] = []
				fails[f].append(tag)
			for n: String in row.runs[tag].notes:
				notes[n] = true
		row.fails = fails
		row.notes = notes.keys()
		out[key] = row
		print("[RvAuditoria] %s: %d fallos, %d avisos%s" % [key, fails.size(), notes.size(), ("\n    - " + "\n    - ".join(fails.keys().map(func(k): return "%s  [%s]" % [k, ", ".join(fails[k])]))) if not fails.is_empty() else ""])
	var path := String(args.get("salida", "res://reports/kit3d/rv_auditoria.json"))
	if not path.begins_with("res://") and not path.begins_with("/"):
		path = "res://" + path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(out, "  "))
	fa.close()
	print("[RvAuditoria] %d interiores en %.1f s -> %s" % [out.size(), (Time.get_ticks_msec() - t0) / 1000.0, path])
	quit()


# ---------------------------------------------------------------------------------------------------------- one build
func audit(path: String, type: String, level: int, mirror: bool, all_ups: bool) -> Dictionary:
	var sd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var opts := {"mirror": mirror}
	if all_ups:
		opts.upgrades = (sd.get("upgrades", {}) as Dictionary).keys()
	var B := Interior3DBuilder.new(path, "res://data/view3d/interiors/props_catalog.json", "res://data/view3d/interiors/lights.json", opts)
	_build(B)
	var r := {"fails": [], "notes": [], "stairs": [], "free": []}
	var used := {}
	for c: Dictionary in B.d.get("cast", []):
		for stp: Dictionary in c.get("steps", []):
			for k in ["sit", "lie"]:
				if stp.has(k):
					used[String(stp[k])] = true
	var ctx := {"B": B, "type": type, "level": level, "r": r, "pieces": _pieces(B), "used": used, "def": _def(type, level, path, mirror)}
	for f in B.floors:
		r.free.append(_free(B, f).size())
	_stairs(ctx)
	_ways(ctx)
	_trade(ctx)
	_walls(ctx)
	B.root.free()
	return r


func _def(type: String, level: int, path: String, mirror: bool) -> Dictionary:
	## the house the interior lives in, as the town builds it: the type's def on a lot whose yard and door fit, with
	## what the interior asks (SituShell.apply: shop front, chimneys over its hearths; mirrored when the yard is on the
	## other side, as the town does); {} if no lot of the type takes it that way
	for k in 16:
		var sdc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var extra := {}
		if sdc.shell.has("door_cell"):
			extra.door_cell = int(sdc.shell.door_cell)
		var res := BuildingTypes.for_lot(type, level, 4 + k, Vector2i.ZERO, extra)
		var def: Dictionary = res.def
		if SituShell.apply(def, sdc, res.yard) == "" and bool(sdc.get("_mirror", false)) == mirror:
			return def
	if not mirror:
		return {}
	# no lot of the type puts its yard on the other side: the house of the unmirrored one, with what SituShell.apply
	# changes when it mounts mirrored (the type's shop front on the mirrored cell, a chimney over each hearth)
	var def := _def(type, level, path, false)
	if def.is_empty():
		return def
	var sd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var m := SituShell.mirrored(sd)
	if m.shell.has("shop"):
		def.shop = (m.shell.shop as Dictionary).duplicate()
	elif def.has("shop") and (def.shop as Dictionary).has("cells"):
		def.shop = (def.shop as Dictionary).duplicate()
		def.shop.cells = (def.shop.cells as Array).map(func(i): return int(def.w) / 2 - 1 - int(i))
	if m.shell.has("chimneys"):
		def.chimneys = m.shell.chimneys
	else:
		var over := SituShell.hearths(m)
		if not over.is_empty():
			def.chimneys = over.map(func(q): return SituShell.chimney_over(def, q.x, q.y))
	def["_simulated"] = true
	return def


func _build(B: Interior3DBuilder) -> void:
	## Interior3DBuilder.build() without the last step (_merge_static frees the holders of the pieces, whose boxes we read)
	B.root = Node3D.new()
	for f in B.floors:
		var level := Node3D.new()
		level.name = "Floor%d" % f
		level.set_meta("level", f)
		B.root.add_child(level)
		B._partitions(level, f)
	for p in B.placed:
		B._place(p)
	for s in B.d.get("stairs", []):
		B._stair_run(s)
	B._block_real()
	B._auto_upgrades()


func fail(ctx: Dictionary, msg: String) -> void:
	if not (ctx.r.fails as Array).has(msg):
		ctx.r.fails.append(msg)


func note(ctx: Dictionary, msg: String) -> void:
	if not (ctx.r.notes as Array).has(msg):
		ctx.r.notes.append(msg)


func _free(B: Interior3DBuilder, f: int) -> Array:
	var o := []
	for t: Vector2i in B.room_of[f]:
		if not B.blocked[f].has(t) and not B.rooms[B.room_of[f][t]].get("annex", false):
			o.append(t)
	return o


func _pieces(B: Interior3DBuilder) -> Array:
	## every piece placed: {id, name, floor, rect (plan, house-local), y0, y1, blocks, hang, on (lifted), mb, rot, pos}
	var o := []
	var mbs := Interior3DBuilder.muebles()
	for h: Array in B._holders:
		var p: Dictionary = h[0]
		var n: Node3D = h[1]
		var box := [AABB(), 0]
		B._aabb_of(n, B.root, box)
		if box[1] == 0:
			continue
		var b: AABB = box[0]
		var parts := []
		_parts(B, n, parts)
		var id := String(p.id)
		var mb: Dictionary = mbs.get(id, {})
		o.append({"id": id, "name": String(p.get("name", p.get("zone", ""))), "zone": String(p.get("zone", "")), "floor": int(p.floor),
			"rect": Rect2(b.position.x, b.position.z, b.size.x, b.size.z), "parts": parts, "y0": b.position.y - int(p.floor) * B.FLOOR_H, "y1": b.end.y - int(p.floor) * B.FLOOR_H,
			"blocks": B._blocks(p), "hang": bool(mb.get("hang", false)), "on": p.has("y") or p.has("lift"), "mb": mb, "rot": float(n.rotation_degrees.y),
			"pos": Vector2(n.position.x, n.position.z), "upg": String(p.get("_upg", "")), "walk": bool(p.get("walk", false)) or bool(mb.get("walk", false)), "flat": bool(mb.get("flat", false)) or id.begins_with("alfombra")})
	return o


func _parts(B: Interior3DBuilder, n: Node, out: Array) -> void:
	## the plan boxes of each mesh of a piece (a furnace with a log beside it is two boxes, not one big one)
	if n is MeshInstance3D and n.mesh:
		var b: AABB = B._rel(n, B.root) * (n.mesh as Mesh).get_aabb()
		if b.size.y > 0.04:
			out.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	for c in n.get_children():
		_parts(B, c, out)


func _hit(p: Dictionary, rc: Rect2) -> float:
	## the plan area of piece p inside rc, by its meshes
	var a := 0.0
	for q: Rect2 in p.parts:
		a = maxf(a, q.intersection(rc).get_area())
	return a


func _tile_rect(B: Interior3DBuilder, t: Vector2i) -> Rect2:
	return Rect2(B.origin.x + t.x * B.TILE, B.origin.y + t.y * B.TILE, B.TILE, B.TILE)


func _base(B: Interior3DBuilder, f: int) -> Array:
	## where people come into floor f: the street door (floor 0) and the landing of every flight that reaches it
	var o := []
	if f == 0:
		o.append(Vector2i(B.d.entrance.tile[0], B.d.entrance.tile[1]))
	for s: Dictionary in B.stair_runs:
		if int(s.to_floor) == f:
			o.append(s.to)
		if int(s.floor) == f and f > 0:
			o.append(s.from)
	return o


func _stair_tiles(B: Interior3DBuilder) -> Array:
	## [{floor, to_floor, tiles: [Vector2i]}] from the data
	var o := []
	for s: Dictionary in B.d.get("stairs", []):
		o.append({"floor": int(s.floor), "to_floor": int(s.to_floor), "tiles": (s.get("tiles", []) as Array).map(func(t): return Vector2i(t[0], t[1]))})
	return o


func _zname(B: Interior3DBuilder, z: String) -> String:
	return String(B.d.stations.get(z, {}).get("name", ZONE_NAMES.get(z, z)))


func _targets(ctx: Dictionary) -> Array:
	## where people have to get to: {what, floor, tile}: the places of the stations, and a free tile by each seat and bed
	var B: Interior3DBuilder = ctx.B
	var o := []
	for z in B.zones:
		var zf := int(B.zones[z].floor)
		if B.room_of.has(zf) and B.room_of[zf].has(B.zones[z].stand):
			o.append({"what": "puesto %s" % _zname(B, z), "floor": zf, "tile": B.zones[z].stand, "zone": z})
	for p: Dictionary in ctx.pieces:
		var mb: Dictionary = p.mb
		if not (mb.get("seat", false) or mb.has("lie")) or p.zone != "":
			continue
		var at := Vector3(p.pos.x, p.floor * B.FLOOR_H, p.pos.y)
		var reach := 1.8 if mb.has("lie") else 1.3
		var t := B.near_free(p.floor, at, reach)
		if t == Vector2i(-99, -99) and mb.get("seat", false):
			# a long seat (a bench, a settle) is sat on from either end too
			var rc: Rect2 = p.rect
			var long_x := rc.size.x >= rc.size.y
			for k in [-1.0, 1.0]:
				var half := (rc.size.x if long_x else rc.size.y) / 2.0 - 0.3
				var end := at + (Vector3(k * half, 0, 0) if long_x else Vector3(0, 0, k * half))
				if t == Vector2i(-99, -99):
					t = B.near_free(p.floor, end, reach)
		var what := "%s %s" % ["cama" if mb.has("lie") else "asiento", p.name if p.name != "" else p.id]
		if t == Vector2i(-99, -99):
			if (ctx.used as Dictionary).has(p.name):
				fail(ctx, "%s (planta %d): sin casilla libre a menos de %.1f m" % [what, p.floor, reach])
			else:
				note(ctx, "%s (planta %d): sin casilla libre a menos de %.1f m (no lo usa nadie del reparto)" % [what, p.floor, reach])
			continue
		o.append({"what": what, "floor": p.floor, "tile": t})
	return o


# ---------------------------------------------------------------------------------------------------------- stairs
func _stairs(ctx: Dictionary) -> void:
	var B: Interior3DBuilder = ctx.B
	var st := _stair_tiles(B)
	var door := Vector2i(B.d.entrance.tile[0], B.d.entrance.tile[1])
	var counters := []
	for e: Dictionary in B.d.get("customers", {}).get("counter", []):
		counters.append(Vector2i(e.tile[0], e.tile[1]))
	for i in B.stair_runs.size():
		var s: Dictionary = B.stair_runs[i]
		var f := int(s.floor)
		var tf := int(s.to_floor)
		var tiles: Array = st[i].tiles if i < st.size() else []
		var tag := "escalera %d→%d" % [f, tf]
		var info := {"floor": f, "to_floor": tf, "from": [s.from.x, s.from.y], "to": [s.to.x, s.to.y]}
		# the foot and the landing: free, inside, with somewhere to step to
		for e in [[f, s.from, "pie"], [tf, s.to, "llegada"]]:
			var ef: int = e[0]
			var et: Vector2i = e[1]
			if not B.room_of[ef].has(et):
				fail(ctx, "%s: el %s (%d, %d) cae fuera de la planta" % [tag, e[2], et.x, et.y])
			elif B.blocked[ef].has(et):
				fail(ctx, "%s: el %s (%d, %d) está ocupado por un mueble" % [tag, e[2], et.x, et.y])
			else:
				var nb := 0
				for d4 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if B.passable(ef, et, et + d4) and not tiles.has(et + d4):
						nb += 1
				if nb == 0:
					fail(ctx, "%s: el %s (%d, %d) no tiene casilla libre al lado" % [tag, e[2], et.x, et.y])
				# a piece that leans into the tile even if it does not take it
				for p: Dictionary in ctx.pieces:
					if p.floor == ef and p.blocks and not p.flat and not p.hang:
						var a := _hit(p, _tile_rect(B, et).grow(-0.2))
						if a > 0.02:
							fail(ctx, "%s: %s invade el %s (%d, %d)" % [tag, p.name if p.name != "" else p.id, e[2], et.x, et.y])
		# the landing: the top of the flight and the landing tile on the same side of any partition
		var top_t := B.world_to_tile(Vector3(s.top.x, 0, s.top.z))
		if not tiles.is_empty():
			var best: Vector2i = tiles[0]
			for t: Vector2i in tiles:
				if Vector2(t - top_t).length() < Vector2(best - top_t).length():
					best = t
			top_t = best
		if B.room_of[tf].has(top_t) and B.room_of[tf].has(s.to) and (top_t - s.to).abs().x + (top_t - s.to).abs().y == 1:
			var ra: String = B.room_of[tf][top_t]
			var rb: String = B.room_of[tf][s.to]
			if ra != rb and not B.open_pairs.has("%s|%s" % [ra, rb]) and not _door_between(B, tf, top_t, s.to):
				fail(ctx, "%s: la llegada da contra un tabique (de %s a %s)" % [tag, ra, rb])
		# on the door, a counter or the tile right behind the door
		for t: Vector2i in tiles:
			if f == 0 and (t == door or t == door + Vector2i(0, -1)):
				fail(ctx, "%s: el tramo está en la puerta o justo detrás (%d, %d)" % [tag, t.x, t.y])
			if counters.has(t + Vector2i(0, 1)) or counters.has(t):
				fail(ctx, "%s: el tramo tapa el mostrador de la calle (%d, %d)" % [tag, t.x, t.y])
			for dr: Dictionary in B.d.get("doors", []):
				if Vector2i(dr.tile[0], dr.tile[1]) == t and (int(dr.floor) == f or int(dr.floor) == tf):
					fail(ctx, "%s: el tramo (o su hueco) está en la puerta de un tabique (%d, %d)" % [tag, t.x, t.y])
		# the way it climbs, against the camera of the open house (front 3/4, pitch 52): a flight that climbs towards
		# the camera shows its underside nearly edge-on (56 degrees against 52)
		var run := Vector2(s.top.x - s.foot.x, s.top.z - s.foot.z)
		info.climbs = "fachada" if run.y > 0.3 else ("fondo" if run.y < -0.3 else ("derecha" if run.x > 0 else "izquierda"))
		if run.y > 0.3:
			fail(ctx, "%s: sube hacia la fachada; abierta desde la calle (cámara del pueblo al frente) se ve de canto" % tag)
		# cut: with the flight out of the way, how much shorter are the ways to every place
		var saved := {}
		for t: Vector2i in tiles:
			if B.blocked[f].has(t):
				saved[t] = true
				B.blocked[f].erase(t)
		var without := _lengths(ctx, f)
		for t in saved:
			B.blocked[f][t] = true
		var with_ := _lengths(ctx, f)
		for k in without:
			if not with_.has(k):
				fail(ctx, "%s: el tramo corta el paso a %s" % [tag, k])
			elif int(with_[k]) - int(without[k]) > 2:
				fail(ctx, "%s: el tramo obliga a rodear %d casillas para llegar a %s" % [tag, int(with_[k]) - int(without[k]), k])
		# the windows of the wall it climbs along that the shell takes away
		info.blind = _blind(B, i)
		if int(info.blind.size()) > 0:
			note(ctx, "%s: sin ventana en %s" % [tag, ", ".join(info.blind)])
		ctx.r.stairs.append(info)


func _door_between(B: Interior3DBuilder, f: int, a: Vector2i, b: Vector2i) -> bool:
	if b.x == a.x + 1:
		return B.is_door(f, b, "nw")
	if b.x == a.x - 1:
		return B.is_door(f, a, "nw")
	if b.y == a.y + 1:
		return B.is_door(f, b, "ne")
	return B.is_door(f, a, "ne")


func _lengths(ctx: Dictionary, f: int) -> Dictionary:
	## from the door (floor 0) or the first landing: steps to each target of floor f
	var B: Interior3DBuilder = ctx.B
	var bases := _base(B, f)
	var o := {}
	if bases.is_empty():
		return o
	for t: Dictionary in _targets(ctx):
		if int(t.floor) != f:
			continue
		var p := B.path(f, bases[0], t.tile)
		if not p.is_empty():
			o[t.what] = p.size()
	return o


func _blind(B: Interior3DBuilder, i: int) -> Array:
	var s: Dictionary = B.d.stairs[i]
	var sh: Dictionary = B.d.shell
	var w := int(sh.w)
	var d := int(sh.d)
	var a := Vector2(B.origin.x + (float(s.foot[0]) + 0.5) * B.TILE, B.origin.y + (float(s.foot[1]) + 0.5) * B.TILE)
	var b := Vector2(B.origin.x + (float(s.top[0]) + 0.5) * B.TILE, B.origin.y + (float(s.top[1]) + 0.5) * B.TILE)
	var o := []
	if absf(b.y - a.y) > absf(b.x - a.x):
		for side in ["left", "right"]:
			var x := minf(a.x, b.x) if side == "left" else maxf(a.x, b.x)
			if (side == "left" and x < -w / 2.0 + 0.6) or (side == "right" and x > w / 2.0 - 0.6):
				for c in SituShell._cells_along(w, d, side, minf(a.y, b.y), maxf(a.y, b.y), 0.4):
					o.append("%s %d" % [{"left": "muro izquierdo", "right": "muro derecho"}[side], c])
	return o


# ---------------------------------------------------------------------------------------------------------- ways
func _ways(ctx: Dictionary) -> void:
	var B: Interior3DBuilder = ctx.B
	var targets := _targets(ctx)
	var stands := {}
	for z in B.zones:
		stands[z] = B.zones[z].stand
	var main := {}  # floor -> {tile: true}: the main way
	for t: Dictionary in targets:
		var f := int(t.floor)
		var bases := _base(B, f)
		if bases.is_empty():
			fail(ctx, "%s (planta %d): no se llega a esa planta" % [t.what, f])
			continue
		for b: Vector2i in bases:
			if B.path(f, b, t.tile).is_empty():
				fail(ctx, "%s (planta %d): no se llega desde %s" % [t.what, f, "la puerta" if f == 0 and b == bases[0] else "la escalera (%d, %d)" % [b.x, b.y]])
		# only through another place
		if t.has("zone"):
			var extra := {}
			for z in stands:
				if z != t.zone and int(B.zones[z].floor) == f and stands[z] != t.tile and not bases.has(stands[z]):
					extra[stands[z]] = true
			var p := B.path(f, bases[0], t.tile, extra)
			if p.is_empty() and not B.path(f, bases[0], t.tile).is_empty():
				var through := []
				for z in stands:
					if int(B.zones[z].floor) == f and extra.has(stands[z]) and B.path(f, bases[0], t.tile).has(stands[z]):
						through.append(_zname(B, z))
				if int(B.d.shell.w) <= 4:
					note(ctx, "%s: solo se llega pasando por el sitio de otro puesto (%s); casa de 4 m: un pasillo de una casilla" % [t.what, ", ".join(through)])
				else:
					fail(ctx, "%s: solo se llega pasando por el sitio de otro puesto (%s)" % [t.what, ", ".join(through)])
			if stands[t.zone] == Vector2i(B.d.entrance.tile[0], B.d.entrance.tile[1]) and f == 0:
				fail(ctx, "%s: quien trabaja ahí está en la puerta" % t.what)
			for s: Dictionary in B.stair_runs:
				if (int(s.floor) == f and s.from == t.tile) or (int(s.to_floor) == f and s.to == t.tile):
					fail(ctx, "%s: quien trabaja ahí está en el pie o la llegada de la escalera" % t.what)
			for z in stands:
				if z != t.zone and int(B.zones[z].floor) == f and stands[z] == t.tile:
					note(ctx, "%s y %s comparten el sitio de quien trabaja" % [t.what, _zname(B, z)])
		# the main way: door -> counter -> workshop places -> stair foot (floor 0); landing -> places (above), round
		# what stands in the middle of a tile (a stool) when there is a way round it
		if t.has("zone"):
			var soft := _soft(ctx, f)
			soft.erase(t.tile)
			var pw := B.path(f, bases[0], t.tile, soft)
			if pw.is_empty():
				pw = B.path(f, bases[0], t.tile)
			for tt in pw:
				if not main.has(f):
					main[f] = {}
				main[f][tt] = true
	for s: Dictionary in B.stair_runs:
		var f := int(s.floor)
		var bases := _base(B, f)
		if not bases.is_empty():
			var soft := _soft(ctx, f)
			soft.erase(s.from)
			var p := B.path(f, bases[0], s.from, soft)
			if p.is_empty():
				p = B.path(f, bases[0], s.from)
			if p.is_empty():
				fail(ctx, "escalera %d→%d: no se llega a su pie desde %s" % [f, s.to_floor, "la puerta" if f == 0 else "la llegada"])
			for tt in p:
				if not main.has(f):
					main[f] = {}
				main[f][tt] = true
	# nothing standing on the main way (a stool, an armchair, a corner of a table): the middle 0.5 m of each tile clear
	ctx.r.main = {}
	for f in main:
		ctx.r.main[str(f)] = main[f].size()
		for tt: Vector2i in main[f]:
			var mid := _tile_rect(B, tt).grow(-0.25)
			for p: Dictionary in ctx.pieces:
				if p.floor != f or p.flat or p.hang or p.on or p.walk:
					continue
				if p.mb.get("seat", false) or p.zone != "":
					var own := false  # a seat or the piece of a station on a station's place: who works there sits on it
					for z in B.zones:
						own = own or (int(B.zones[z].floor) == f and B.zones[z].stand == tt)
					if own:
						continue
				if _hit(p, mid) > 0.01:
					fail(ctx, "paso principal (planta %d): %s estorba en (%d, %d)%s" % [f, p.name if p.name != "" else p.id, tt.x, tt.y, " [mejora %s]" % p.upg if p.upg != "" else ""])
	# isolated free tiles
	for f in B.floors:
		var bases := _base(B, f)
		if bases.is_empty():
			continue
		var iso := []
		for t: Vector2i in _free(B, f):
			if t != bases[0] and B.path(f, bases[0], t).is_empty():
				iso.append("(%d, %d)" % [t.x, t.y])
		if not iso.is_empty():
			fail(ctx, "planta %d: casillas libres sin acceso %s" % [f, ", ".join(iso)])


func _soft(ctx: Dictionary, f: int) -> Dictionary:
	## free tiles of floor f with something standing in their middle (a stool, an armchair, a basket)
	var B: Interior3DBuilder = ctx.B
	var o := {}
	for t: Vector2i in _free(B, f):
		var mid := _tile_rect(B, t).grow(-0.25)
		for p: Dictionary in ctx.pieces:
			if p.floor == f and not (p.flat or p.hang or p.on or p.walk) and _hit(p, mid) > 0.01:
				o[t] = true
	for b in _base(B, f):
		o.erase(b)
	return o


# ---------------------------------------------------------------------------------------------------------- the trade
func _trade(ctx: Dictionary) -> void:
	var B: Interior3DBuilder = ctx.B
	var type: String = ctx.type
	var sh: Dictionary = B.d.shell
	var w := float(sh.w)
	var dd := float(sh.d)
	var floors := int(sh.floors)
	# fires and chimneys
	var fires := []
	for fi: Dictionary in B.fires:
		if not (String(fi.id).begins_with("hogar") or String(fi.id) == "boca_horno"):
			continue  # candles and lamps
		fires.append({"floor": int(fi.floor), "at": Vector2(fi.at.x, fi.at.z), "id": String(fi.id)})
	for z in B.zones:
		if String(z).begins_with("furnace") and B.zone_pos.has(z):
			fires.append({"floor": int(B.zones[z].floor), "at": Vector2(B.zone_pos[z].x, B.zone_pos[z].z), "id": "fragua"})
	var chimneys := []
	var def: Dictionary = ctx.def
	if def.get("_simulated", false):
		note(ctx, "ninguna parcela del tipo lo pide en espejo: casa de la parcela normal con lo que SituShell.apply cambia al reflejar")
	if def.is_empty():
		note(ctx, "ninguna parcela del tipo monta este trazado %s: sin comprobar chimeneas ni tienda" % ("en espejo" if B.d.get("_mirror", false) else "tal cual"))
	for c in def.get("chimneys", []):
		var cx := float(c.get("x", 0.5)) if c is Dictionary else float(c)
		var cy := float(c.get("y", 0.5)) if c is Dictionary else 0.5
		if def.get("ridge", "y") == "x":
			chimneys.append(Vector2(-cy * w / 2.0, -cx * dd / 2.0))
		else:
			chimneys.append(Vector2(cx * w / 2.0, -cy * dd / 2.0))
	for fi: Dictionary in fires:
		if fi.id == "boca_horno":
			continue  # the oven stands outside, behind the wall: its own chimney is the oven's (BuildingTypes)
		var best := 99.0
		for c: Vector2 in chimneys:
			best = minf(best, c.distance_to(fi.at))
		if best > 0.9:
			fail(ctx, "%s (planta %d): sin chimenea encima (la más cercana a %.1f m)" % [fi.id, fi.floor, best])
		# the flue up through every floor above
		for f2 in range(int(fi.floor) + 1, floors):
			var flue := false
			var hit := []
			for p: Dictionary in ctx.pieces:
				if p.floor != f2:
					continue
				var c: Vector2 = (p.rect as Rect2).get_center()
				if (p.id == "tiro" or String(p.id).begins_with("hogar")) and c.distance_to(fi.at) < 0.75:
					flue = true
				elif p.blocks and not p.flat and _hit(p, Rect2(fi.at - Vector2(0.25, 0.25), Vector2(0.5, 0.5))) > 0.02:
					hit.append(p.name if p.name != "" else p.id)
			if not flue and fi.id != "fragua":
				fail(ctx, "%s (planta %d): falta el tiro en la planta %d" % [fi.id, fi.floor, f2])
			if not hit.is_empty():
				fail(ctx, "%s (planta %d): %s en la columna del tiro, planta %d" % [fi.id, fi.floor, ", ".join(hit), f2])
	for c: Vector2 in chimneys:
		var best := 99.0
		for fi: Dictionary in fires:
			best = minf(best, c.distance_to(fi.at))
		if best > 0.9:
			note(ctx, "chimenea en (%.1f, %.1f) sin fuego debajo (el más cercano a %.1f m)" % [c.x, c.y, best])
	# the forge: the anvil by the furnace, the quench at hand
	if B.zones.has("anvil") and B.zones.has("furnace"):
		var p := B.path(0, B.zones.furnace.stand, B.zones.anvil.stand)
		if p.size() - 1 > 2:
			fail(ctx, "yunque lejos de la fragua (%d pasos entre los dos sitios)" % (p.size() - 1))
		var anv: Vector3 = B.zone_pos.get("anvil", Vector3.ZERO)
		var q := 99.0
		for pc: Dictionary in ctx.pieces:
			if QUENCH.has(pc.id) or pc.name == "pila":
				q = minf(q, (pc.rect as Rect2).get_center().distance_to(Vector2(anv.x, anv.z)))
		if q > 2.0:
			fail(ctx, "pila de temple lejos del yunque (%.1f m)" % q)
	# counters: the customers' side reachable from the street
	var door := Vector2i(B.d.entrance.tile[0], B.d.entrance.tile[1])
	for z in B.zones:
		var s: Dictionary = B.d.stations.get(z, {})
		var piece := String(s.get("prop", ""))
		var mb: Dictionary = Interior3DBuilder.muebles().get(piece, {})
		if String(s.get("kind", "")) != "sales" and not mb.get("counter", false):
			continue
		if not s.has("prop") and int(s.tile[1]) >= int(B.d.size[1]):  # a fold-down counter on the shop window
			var shop: Array = def.get("shop", {}).get("cells", [])
			var cells := HouseBuilder._wall_cells(int(w), int(dd), "front")
			var x := B.origin.x + (int(s.tile[0]) + 0.5) * B.TILE
			var cell := -1
			for k in cells.size():
				if absf((cells[k] as Vector2).x - x) <= 1.0:
					cell = k
			if def.is_empty():
				pass
			elif not shop.has(float(cell)) and not shop.has(cell):
				fail(ctx, "%s: el mostrador abatible cae en la celda %d de la fachada y el frente de tienda está en %s" % [_zname(B, z), cell, shop])
			continue
		var at: Vector3 = B.zone_pos.get(z, Vector3.ZERO)
		var face := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(float(B.named.get(z, {}).get("rot", 0.0))))
		var cli := B.world_to_tile(at + face * 0.75)
		var stand: Vector2i = B.zones[z].stand
		var st_side := (B.tile_pos(0, stand) - at).dot(face)
		if st_side > 0.05:
			fail(ctx, "%s: quien atiende está del lado de los clientes" % _zname(B, z))
		var f := int(B.zones[z].floor)
		if not B.room_of[f].has(cli) or B.blocked[f].has(cli) or B.path(f, door, cli, {stand: true}).is_empty():
			fail(ctx, "%s: no se llega al lado de los clientes (%d, %d) desde la puerta sin pasar por detrás" % [_zname(B, z), cli.x, cli.y])
	# the store by the workshop
	for z in B.zones:
		if String(B.d.stations.get(z, {}).get("kind", "")) != "storage":
			continue
		var f := int(B.zones[z].floor)
		var best := 99
		for z2 in B.zones:
			if String(B.d.stations.get(z2, {}).get("kind", "")) in ["craft", "service", "sales"] and int(B.zones[z2].floor) == f and z2 != z:
				var p := B.path(f, B.zones[z].stand, B.zones[z2].stand)
				if not p.is_empty():
					best = mini(best, p.size() - 1)
		if best == 99:
			note(ctx, "%s: en una planta sin taller (planta %d)" % [_zname(B, z), f])
		elif best > 4:
			var craft := false
			for z2 in B.zones:
				craft = craft or (String(B.d.stations.get(z2, {}).get("kind", "")) == "craft" and int(B.zones[z2].floor) == f)
			if craft:
				fail(ctx, "%s lejos del taller (%d pasos)" % [_zname(B, z), best])
			else:
				note(ctx, "%s a %d pasos del puesto más cercano (sala aparte)" % [_zname(B, z), best])
	# beds: upstairs, not in the workshop
	for p: Dictionary in ctx.pieces:
		if not BEDS.has(p.id) or p.zone == "cot" or p.name.begins_with("catre") and type == "clinic":
			continue
		var t := B.world_to_tile(Vector3((p.rect as Rect2).get_center().x, 0, (p.rect as Rect2).get_center().y))
		var room := String(B.rooms.get(B.room_at(p.floor, t), {}).get("type", ""))
		if p.floor == 0 and room in ["workshop", "shop", "storage"]:
			if floors > 1:
				fail(ctx, "%s en el taller de la planta baja (hay planta alta)" % (p.name if p.name != "" else p.id))
			else:
				note(ctx, "%s en el taller: la casa no tiene planta alta" % (p.name if p.name != "" else p.id))
	# nothing behind the door
	var inner := door + Vector2i(0, -1)
	for t: Vector2i in [door, inner]:
		var say := (func(m): fail(ctx, m)) if t == door else (func(m): note(ctx, m + " (se entra de lado)"))
		if B.blocked[0].has(t):
			say.call("puerta: la casilla %s (%d, %d) está ocupada" % ["de la puerta" if t == door else "de detrás de la puerta", t.x, t.y])
			continue
		var mid := _tile_rect(B, t).grow(-0.2)
		for p: Dictionary in ctx.pieces:
			if p.floor == 0 and not p.flat and not p.hang and not p.on and _hit(p, mid) > 0.01:
				say.call("puerta: %s en la casilla %s (%d, %d)%s" % [p.name if p.name != "" else p.id, "de la puerta" if t == door else "de detrás de la puerta", t.x, t.y, " [mejora %s]" % p.upg if p.upg != "" else ""])
	# seats with a back look at what they are for
	for p: Dictionary in ctx.pieces:
		if not BACK_SEATS.has(p.id):
			continue
		var f3 := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(p.rot))
		var face := Vector2(f3.x, f3.z)
		var best := 99.0
		var dirv := Vector2.ZERO
		var what := ""
		for q: Dictionary in ctx.pieces:
			if q.floor != p.floor or q == p:
				continue
			var ok := false
			for pre in FOCUS:
				if String(q.id).begins_with(pre):
					ok = true
			if not ok:
				continue
			var dv: Vector2 = (q.rect as Rect2).get_center() - (p.rect as Rect2).get_center()
			if dv.length() < best:
				best = dv.length()
				dirv = dv
				what = q.name if q.name != "" else q.id
		if best < 2.2 and face.dot(dirv.normalized()) < 0.2:
			fail(ctx, "%s mira hacia otro lado (%s a %.1f m)" % [p.name if p.name != "" else p.id, what, best])


# ---------------------------------------------------------------------------------------------------------- walls
func _walls(ctx: Dictionary) -> void:
	var B: Interior3DBuilder = ctx.B
	var sh: Dictionary = B.d.shell
	var hw := float(sh.w) / 2.0 - WALL_IN
	var hd := float(sh.d) / 2.0 - WALL_IN
	var bounds := Rect2(-hw, -hd, 2 * hw, 2 * hd)
	var ps: Array = ctx.pieces
	for p: Dictionary in ps:
		var nm: String = p.name if p.name != "" else p.id
		var rc: Rect2 = p.rect
		var t := B.world_to_tile(Vector3(rc.get_center().x, 0, rc.get_center().y))
		if B.rooms.get(B.room_at(p.floor, t), {}).get("annex", false) or not B.room_of[p.floor].has(t):
			continue  # under the shed or in the yard
		var tol := 0.12 if p.hang else 0.05
		if not bounds.grow(tol).encloses(rc):
			var o := maxf(maxf(bounds.position.x - rc.position.x, rc.end.x - bounds.end.x), maxf(bounds.position.y - rc.position.y, rc.end.y - bounds.end.y))
			fail(ctx, "%s (planta %d) atraviesa el muro exterior %.2f m%s" % [nm, p.floor, o, " [mejora %s]" % p.upg if p.upg != "" else ""])
		if not p.hang and not p.on and String(p.id) != "tiro" and p.y0 > 0.06:
			fail(ctx, "%s (planta %d) flota a %.2f m del suelo" % [nm, p.floor, p.y0])
		if p.y0 < -0.1 and not p.hang:
			fail(ctx, "%s (planta %d) se hunde %.2f m en el suelo" % [nm, p.floor, -p.y0])
		if p.on:
			var held := false
			for q: Dictionary in ps:
				if q != p and q.floor == p.floor and (q.rect as Rect2).grow(0.05).has_point(rc.get_center()) and float(q.y0) <= float(p.y0) + 0.05 and float(q.y1) >= float(p.y0) - 0.2:
					held = true
			if not held and not String(p.id).begins_with("palmatoria") and p.y0 > 0.1:
				note(ctx, "%s (planta %d) a %.2f m sin nada debajo que lo sostenga" % [nm, p.floor, p.y0])
	# through a partition
	for f in B.floors:
		var rof: Dictionary = B.room_of[f]
		for t: Vector2i in rof:
			for e in [[t + Vector2i(-1, 0), true], [t + Vector2i(0, -1), false]]:
				var other := String(rof.get(e[0], ""))
				var room := String(rof[t])
				if other == "" or other == room or B.open_pairs.has("%s|%s" % [room, other]) or B.rooms[room].get("annex", false) or B.rooms[other].get("annex", false):
					continue
				var tr := _tile_rect(B, t)
				for p: Dictionary in ps:
					if p.floor != f or p.flat:
						continue
					var cross := false
					for rc: Rect2 in p.parts:
						if e[1]:
							var x := tr.position.x
							cross = cross or (rc.position.x < x - 0.12 and rc.end.x > x + 0.12 and minf(rc.end.y, tr.end.y) - maxf(rc.position.y, tr.position.y) > 0.1)
						else:
							var z := tr.position.y
							cross = cross or (rc.position.y < z - 0.12 and rc.end.y > z + 0.12 and minf(rc.end.x, tr.end.x) - maxf(rc.position.x, tr.position.x) > 0.1)
					if cross:
						fail(ctx, "%s (planta %d) atraviesa el tabique entre %s y %s" % [p.name if p.name != "" else p.id, f, room, other])
	# two pieces inside each other
	for i in ps.size():
		var a: Dictionary = ps[i]
		if not a.blocks or a.flat or a.hang or a.on:
			continue
		for j in range(i + 1, ps.size()):
			var b: Dictionary = ps[j]
			if b.floor != a.floor or not b.blocks or b.flat or b.hang or b.on:
				continue
			var ia := 0.0
			for qa: Rect2 in a.parts:
				for qb: Rect2 in b.parts:
					ia = maxf(ia, qa.intersection(qb).get_area())
			var small := minf((a.rect as Rect2).get_area(), (b.rect as Rect2).get_area())
			if ia > 0.25 * small and ia > 0.03:
				var seat_table: bool = (a.mb.get("seat", false) and String(b.id).begins_with("mesa")) or (b.mb.get("seat", false) and String(a.id).begins_with("mesa"))
				var msg := "%s y %s se meten uno en otro (planta %d, %.2f m²)" % [a.name if a.name != "" else a.id, b.name if b.name != "" else b.id, a.floor, ia]
				if seat_table:
					note(ctx, msg + ": banco bajo la mesa")
				else:
					fail(ctx, msg + ((" [mejora %s]" % (a.upg if a.upg != "" else b.upg)) if a.upg != "" or b.upg != "" else ""))
