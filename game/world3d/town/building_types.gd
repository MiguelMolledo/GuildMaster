class_name BuildingTypes
extends RefCounted
## What every GuildMaster building type looks like in 3D, by data (data/building_types.json): type + level (1-3) +
## seed -> a HouseBuilder def. docs/construccion.md has the table.
##   BuildingTypes.def_for("forge", 2, seed, w, d, yard)   a def for a house of w x d m whose walls have that yard behind
##   BuildingTypes.for_lot("forge", 2, seed)               the same on the type's own lot: {def, at, lot, yard}
## yard: {side: [bool per cell]} (cells left to right seen from outside, as HouseBuilder numbers them): the cells of
## each wall with free ground of the lot in front of them. Sheds, ovens, hatches and yard things only go there.

const DATA := "res://data/view3d/building_types.json"
const SIDE_ROT := {"front": 0.0, "right": 90.0, "back": 180.0, "left": 270.0}

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f == null:
			push_error("[BuildingTypes] cannot open %s" % DATA)
			return {}
		var parsed = JSON.parse_string(f.get_as_text())
		if not (parsed is Dictionary):
			push_error("[BuildingTypes] %s is not valid JSON" % DATA)
			return {}
		_data = parsed
		if OS.is_debug_build():
			print("[BuildingTypes] loaded %d types from %s" % [_data.types.size(), DATA])
	return _data


static func types() -> Array:
	return data().get("types", {}).keys()


## GuildMaster's type id -> ours: "house" splits by wealth ("humble", "well", "noble").
static func type_id(type: String, wealth := "humble") -> String:
	if type == "house":
		return "house_%s" % wealth
	return type


static func lot_of(type: String) -> Vector2i:
	var t: Dictionary = data().types.get(type, {})
	var l: Array = t.get("lot", [6, 6])
	return Vector2i(int(l[0]), int(l[1]))


static func _color(v) -> Variant:
	if v is String:
		var cols: Dictionary = data().get("colors", {})
		if cols.has(v):
			return Color(cols[v])
		if (v as String).begins_with("#"):
			return Color(v)
	return v


static func _ints(v) -> Variant:
	## JSON numbers come as floats: whole ones back to int (HouseBuilder wants int sizes and cells)
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) >= 1.0:
		return int(v)
	if v is Array:
		var out := []
		for e in v:
			out.append(_ints(e))
		return out
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _ints(v[k])
		return d
	return v


static func _run_of(cells: Array) -> Array:
	## [from, to] of the longest run of true, [] if none
	var best := []
	var s := -1
	for i in cells.size() + 1:
		var on: bool = i < cells.size() and bool(cells[i])
		if on and s < 0:
			s = i
		elif not on and s >= 0:
			if best.is_empty() or i - s > best[1] - best[0] + 1:
				best = [s, i - 1]
			s = -1
	return best


## Resolves the side of an entry: "yard:<sides>" -> the first with a run of at least e.min yard cells. Leaves the run in
## e._run. False if the entry has no place (it is dropped).
static func _side(e: Dictionary, ctx: Dictionary) -> bool:
	var side: String = e.get("side", "")
	if side.begins_with("yard"):
		var prefs: PackedStringArray = side.trim_prefix("yard").trim_prefix(":").split(",", false)
		if prefs.is_empty():
			prefs = PackedStringArray(["right", "left", "back"])
		for s in prefs:
			var run := _run_of(ctx.yard.get(s, []))
			if not run.is_empty() and run[1] - run[0] + 1 >= int(e.get("min", 1)):
				e.side = s
				e["_run"] = run
				return true
		return false
	if side == "":
		side = "front"
	var n: int = (ctx.w if side in ["front", "back"] else ctx.d) / 2
	e["_run"] = [0, n - 1]
	return true


static func _cell(v, e: Dictionary, ctx: Dictionary) -> int:
	if v is String:
		var run: Array = e.get("_run", [0, 0])
		match v:
			"run0":
				return run[0]
			"run1":
				return mini(run[0] + 1, run[1])
			"runN":
				return run[1]
			"door":
				return ctx.door
			"beside1":
				return ctx.beside[0] if not ctx.beside.is_empty() else ctx.door
		return 0
	return int(v)


static func _cells(v, ctx: Dictionary) -> Array:
	if v is String:
		match v:
			"beside":
				return ctx.beside.duplicate()
			"beside1":
				return ctx.beside.slice(0, 1)
			"door":
				return [ctx.door]
		return []
	return v


static func _clean(e: Dictionary) -> Dictionary:
	for k in ["_run", "min", "max", "run"]:
		e.erase(k)
	return e


## The def of a building of that type and level (1-3) for a house of w x d metres. seed picks the variant (colours,
## windows) and the layout of windows. extra: more def keys on top (door_cell, ridge, stage, name...).
static func def_for(type: String, level: int, seed: int, w: int, d: int, yard := {}, extra := {}) -> Dictionary:
	var all := data()
	if not all.get("types", {}).has(type):
		push_warning("[BuildingTypes] unknown type %s: a plain house" % type)
		type = "house_humble"
	var t: Dictionary = all.types[type]
	var levels: Array = t.get("levels", [{}])
	level = clampi(level, 1, levels.size())
	var raw: Dictionary = (all.base as Dictionary).duplicate(true)
	raw.merge((t.get("base", {}) as Dictionary).duplicate(true), true)
	raw.merge((levels[level - 1] as Dictionary).duplicate(true), true)
	var variants: Array = t.get("variants", all.get("variants", [{}]))
	var variant: Dictionary = (variants[absi(seed) % variants.size()] as Dictionary).duplicate(true)
	for k in variant:
		if k not in ["mirror", "turn", "upper_window"]:
			raw[k] = variant[k]
	if variant.has("upper_window") and not raw.has("windows") and int(raw.floors) > 1:
		raw.windows = [raw.get("window", "Window_Wide_Round"), variant.upper_window]
	# what tells the trade apart from afar: the type's own roof, plaster, timber or stone over the variant's palette, and
	# a bigger sign (`look`: {roof, plaster, wood, stone}; `sign_scale` of the file or of the type)
	var look: Dictionary = t.get("look", {})
	if not look.is_empty():
		var pal: Dictionary = (raw.get("palette", {}) as Dictionary).duplicate()
		pal.merge(look, true)
		raw.palette = pal
	if not raw.has("sign_scale") and all.has("sign_scale"):
		raw.sign_scale = float(t.get("sign_scale", all.sign_scale))
	var def: Dictionary = _ints(raw)
	def.merge(extra.duplicate(true), true)
	def.w = w
	def.d = d
	def.seed = seed
	if not def.has("name"):
		def.name = "%s_L%d" % [type, level]
	var floors: int = int(def.floors)
	def.walls = (def.walls as Array).slice(0, floors)
	if floors >= 3:
		def.corner = "Corner_ExteriorWide_Wood"
	var n: int = w / 2
	var door := HouseBuilder.door_cell(def, n)
	var beside := []
	for i in [door + 1, door - 1]:
		if i >= 0 and i < n:
			beside.append(i)
	var ctx := {w = w, d = d, floors = floors, door = door, beside = beside, yard = yard}
	# the kit chimney is 3 m tall: on the roofs of 8 and 10 m of span it only clears the tiles near the eaves
	var span: int = d if def.get("ridge", "y") == "x" else w
	if span >= 8 and def.has("chimneys"):
		var ch := []
		for c in def.chimneys:
			ch.append(signf(float(c)) * (0.75 if span == 8 else 0.8) if not (c is Dictionary) else c)
		def.chimneys = ch
	# colours
	for k in ["shield"]:
		if def.has(k):
			def[k] = _color(def[k])
	for k in ["shop", "display"]:
		if def.has(k):
			var e: Dictionary = def[k]
			e.cells = _cells(e.get("cells", "beside"), ctx)
			if e.has("awning"):
				e.awning = _color(e.awning)
			if e.cells.is_empty():
				def.erase(k)
				if k == "shop" and e.has("sign") and not def.has("sign"):
					def.sign = e.sign
	if def.has("herbs"):
		def.herbs = _cells(def.herbs, ctx)
	# the guild banner: its colour by name, and with the ridge along the front (gables on the side walls) the gable
	# that looks over the yard
	if def.has("banner"):
		var bn: Dictionary = def.banner
		if bn.has("color"):
			bn.color = _color(bn.color)
		if def.get("ridge", "y") == "x" and not bn.has("side"):
			var most := 0
			for s: String in ["right", "left"]:
				var c: int = (yard.get(s, []) as Array).count(true)
				if c > most:
					most = c
					bn.side = s
	# things that need a yard side and a cell
	for k in ["oven", "hatch", "barn", "loft", "court"]:
		if not def.has(k):
			continue
		var e: Dictionary = def[k]
		if not _side(e, ctx):
			def.erase(k)
			continue
		if e.has("cell"):
			e.cell = _cell(e.cell, e, ctx)
		if k == "court" and e.get("gate", true) is String:
			e.gate = {"right": "first", "left": "last"}.get(e.side, "far")
		_clean(e)
	for k in ["porch", "yard", "cloth", "balcony"]:
		if not def.has(k):
			continue
		var out := []
		for e: Dictionary in def[k]:
			if k == "balcony":
				if e.get("floor", 1) is String:
					e.floor = floors - 1
				for fk in ["from", "to"]:  # "door", "door-1", "door+1": cells by the door's
					if e.get(fk) is String:
						e[fk] = clampi(door + (int(String(e[fk]).trim_prefix("door")) if String(e[fk]) != "door" else 0), 0, n - 1)
				if int(e.get("floor", 1)) >= floors:
					continue
				out.append(e)
				continue
			if not _side(e, ctx):
				continue
			if e.has("cell"):
				e.cell = _cell(e.cell, e, ctx)
			if e.get("run", false):
				var run: Array = e["_run"]
				var mx: int = int(e.get("max", 9))
				if run[1] - run[0] + 1 > mx:
					# cells run left to right seen from outside: the back end of the left wall is its first cell
					run = [run[0], run[0] + mx - 1] if e.side == "left" else [run[1] - mx + 1, run[1]]
				e.from = run[0]
				e.to = run[1]
			if k == "porch" and floors < 2:
				continue  # under the eaves of a one-storey house it does not fit
			out.append(_clean(e))
		def[k] = out
	if def.has("portal") and not def.portal:
		def.erase("portal")
	if not def.has("portal"):
		def.erase("shield")
	if OS.is_debug_build():
		print("[BuildingTypes] %s level %d seed %d -> %dx%d, %d floors, walls %s, variant %d" % [type, level, seed, w, d, floors, def.walls, absi(seed) % variants.size()])
	return def


static func _roof_ok(span: int, run: int) -> bool:
	return HouseBuilder._exists("Roof_RoundTiles_%dx%d" % [span, run])


## The building on its lot (the type's own footprint by default, in metres; the front of the lot is its -y edge and the
## lot is centred on the origin): the house stands on the front line against one side and the rest is yard.
## Returns {def, at (centre of the house on the lot, plan metres), lot, yard}.
static func for_lot(type: String, level: int, seed: int, lot := Vector2i.ZERO, extra := {}) -> Dictionary:
	var all := data()
	if not all.get("types", {}).has(type):
		type = "house_humble"
	var t: Dictionary = all.types[type]
	if lot == Vector2i.ZERO:
		lot = lot_of(type)
	var takes: Array = t.get("takes", all.get("takes", [[0, 0]]))
	var take: Array = takes[clampi(level, 1, takes.size()) - 1]
	var w := maxi(4, lot.x + int(take[0]))
	var d := maxi(4, lot.y + int(take[1]))
	var more := extra.duplicate(true)
	if not _roof_ok(w, d) and _roof_ok(d, w) and not more.has("ridge"):
		more.ridge = "x"  # the kit only has that roof with the ridge along the front (the town hall's 12x8)
	while not _roof_ok(w, d) and more.get("ridge", "y") != "x":
		if d > 4:
			d -= 2
		elif w > 4:
			w -= 2
			d = lot.y
		else:
			break
	var variants: Array = t.get("variants", all.get("variants", [{}]))
	var variant: Dictionary = variants[absi(seed) % variants.size()]
	var mirror: bool = variant.get("mirror", false)
	var yard := {}
	if lot.x - w >= 2:
		var cells := []
		cells.resize(d / 2)
		cells.fill(true)
		yard["left" if mirror else "right"] = cells
	if lot.y - d >= 2:
		var cells := []
		cells.resize(w / 2)
		cells.fill(true)
		yard["back"] = cells
	if variant.get("turn", false) and _roof_ok(d, w):
		more.ridge = "x"
	var def := def_for(type, level, seed, w, d, yard, more)
	var at := Vector2((1.0 if mirror else -1.0) * (lot.x - w) / 2.0, -(lot.y - d) / 2.0)
	return {def = def, at = at, lot = lot, yard = yard}
