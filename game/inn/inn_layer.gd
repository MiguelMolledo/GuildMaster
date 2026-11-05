class_name InnLayer
extends Node2D
## The Taberna-Posada inside its interior (docs/gdd/04f_vida_y_fiestas.md §4.27.4): the guests of the turn seated at
## the seats of the room scene (Seats/Seat00..: game/visuals/interiors/tavern_inn.tscn), each one a CharacterView
## (the townsperson it is, or a figure of its group) with its order over the head (the dish's icon, or a disc with its
## letter until the icon exists) and its patience bar; the beds of the rooms at Beds/Bed0.. in their state (made,
## occupied, dirty, being made); the minstrel. A view only: it reads Inn's state and gives orders (inn_serve on a
## click on a waiting guest, inn_make_bed on a click on a dirty bed) through the interior's order sink.
## The art: the kit's floor and walls from VisualPaths.inn_art("interior", floor / wall_ne / ...) when they exist.

signal message(text: String)

const GROUP_COLORS: Dictionary = {"comarca": ["#6a5a2a", "#c8b890"], "neighbours": ["#7a5230", "#d8c8a0"], "merchants": ["#2e4a6b", "#c8a84e"],
	"pilgrims": ["#6a6a5a", "#e0d8c0"], "soldiers": ["#8b2e2e", "#b8b8b0"], "nobles": ["#5a2e6b", "#e8c860"],
	"gamblers": ["#2e5a3a", "#d0b070"]}
const BED_COLORS: Dictionary = {"made": "#6a9a4a", "occupied": "#4a6a9a", "dirty": "#9a5a3a", "making": "#c8a84e"}
const HEAD: float = 60.0
const BED_SCALE: float = 0.6

var sim: Sim = null
var building: String = ""
var interior: InteriorView = null
var _views: Dictionary = {}      # guest id -> CharacterView
var _icons: Dictionary = {}      # guest id -> Sprite2D: the dish's icon over the disc of its order (sync)
var _seat_pos: Array = []        # Vector2 by seat index
var _bed_pos: Array = []         # Vector2 by bed index
var _font: Font = null


func setup(s: Sim, bld: String, view: InteriorView) -> void:
	sim = s
	building = bld
	interior = view
	z_index = 40
	_font = ThemeDB.fallback_font
	_seat_pos.clear()
	_bed_pos.clear()
	var room := view.room()
	for holder: Array in [["Seats", _seat_pos], ["Beds", _bed_pos]]:
		var n := room.get_node_or_null(str(holder[0])) if room != null else null
		if n == null:
			continue
		var marks: Array = n.get_children().filter(func(c: Node) -> bool: return c is Marker2D)
		marks.sort_custom(func(a: Node, b: Node) -> bool: return str(a.name) < str(b.name))
		for m: Marker2D in marks:
			(holder[1] as Array).append(m.position + (n as Node2D).position)
	_apply_kit_art()
	for v: Variant in _views.values():
		(v as Node).queue_free()
	_views.clear()
	ViewConfig.info("InnLayer", "setup (building=%s, seats=%d, beds=%d)" % [bld, _seat_pos.size(), _bed_pos.size()])
	sync()


## The kit's textures from the tavern's art, when they exist (else the kit keeps its colours).
func _apply_kit_art() -> void:
	var k := interior.kit()
	if k == null:
		return
	var set_any := false
	for pair: Array in [["floor_texture", "floor"], ["wall_texture_ne", "wall_ne"], ["wall_texture_nw", "wall_nw"],
			["door_texture_ne", "wall_door_ne"], ["door_texture_nw", "wall_door_nw"]]:
		var t := VisualPaths.inn_art("interior", str(pair[1]))
		if t != null:
			k.set(str(pair[0]), t)
			set_any = true
	if set_any:
		k.ensure_built()


## A person of the room for the view: the townsperson of a local guest, else one made from its group and number.
func guest_person(g: Dictionary) -> Dictionary:
	var chr := str(g.get("chr", ""))
	if chr != "" and sim.state.characters.has(chr):
		var ch: Dictionary = (sim.state.characters[chr] as Dictionary).duplicate()
		ch["id"] = str(g["id"])
		ch["controlled_by"] = ""
		return ch
	var n := int(g.get("name_n", 0))
	return {"id": str(g["id"]), "name": SimQuery.t_("inn.group." + str(g.get("group", ""))), "female": n % 3 == 1,
		"visual": {"hair": n % 6, "skin": n % 3}, "controlled_by": "", "family": ""}


func guest_family(g: Dictionary) -> Dictionary:
	var chr := str(g.get("chr", ""))
	if chr != "" and sim.state.characters.has(chr):
		return sim.state.families.get(str(sim.state.characters[chr].get("family", "")), {})
	var c: Array = GROUP_COLORS.get(str(g.get("group", "")), ["#808080", "#c0c0c0"])
	return {"name": "", "colors": {"primary": str(c[0]), "secondary": str(c[1])}}


## Follows the turn: a view per guest inside, at its seat; gone guests' views go.
func sync() -> void:
	if sim == null:
		return
	var seen := {}
	for g: Dictionary in Inn.guests(sim, building):
		var gid := str(g["id"])
		var seat := int(g.get("seat", -1))
		if seat < 0 or seat >= _seat_pos.size():
			continue
		seen[gid] = true
		if not _views.has(gid):
			var v := CharacterView.new()
			v.setup(guest_person(g), guest_family(g))
			interior.objects().add_child(v)
			_views[gid] = v
		var view: CharacterView = _views[gid]
		view.position = (_seat_pos[seat] as Vector2).round()
		view.play_motion("idle", "se" if seat % 2 == 0 else "sw")
	for gid: String in _views.keys():
		if not seen.has(gid):
			(_views[gid] as Node).queue_free()
			_views.erase(gid)
	_sync_icons()
	queue_redraw()


## The icon of each waiting guest's order (a Sprite2D over the disc _draw paints); none while it has no icon.
func _sync_icons() -> void:
	var want := {}
	for g: Dictionary in Inn.guests(sim, building):
		var gid := str(g["id"])
		if str(g.get("state", "")) != "waiting" or not _views.has(gid):
			continue
		var d := str(g.get("order", ""))
		var tex := VisualPaths.inn_dish_icon(d)
		if tex == null:
			tex = VisualPaths.icon_small(str(Inn.dish(sim, d).get("item", d)))
		if tex == null:
			continue
		want[gid] = true
		if not _icons.has(gid):
			var sp := Sprite2D.new()
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(sp)
			_icons[gid] = sp
		var icon: Sprite2D = _icons[gid]
		icon.texture = tex
		icon.position = (_views[gid] as Node2D).position - position + Vector2(0, -HEAD)
	for gid: String in _icons.keys():
		if not want.has(gid):
			(_icons[gid] as Node).queue_free()
			_icons.erase(gid)


func guest_count() -> int:
	return _views.size()


func _draw() -> void:
	if sim == null:
		return
	var now := int(sim.state.clock["minute"])
	var inn := Inn.state_of(sim, building)
	# beds
	var beds: Array = inn.get("beds", [])
	for i: int in mini(beds.size(), _bed_pos.size()):
		var b: Dictionary = beds[i]
		var p: Vector2 = _bed_pos[i] - position
		var c := Color.html(str(BED_COLORS.get(str(b.get("state", "")), "#808080")))
		var good := i == 0 and Upgrades.flag(sim, building, "inn_good_room")
		_bed(p, c, good)
		if str(b.get("state", "")) == "making":
			var span := float(sim.catalog.inn.get("rules", {}).get("make_bed_minutes", 20))
			var left := clampf(float(int(b.get("until", now)) - now) / maxf(1.0, span), 0.0, 1.0)
			_bar(p + Vector2(0, -30), 1.0 - left, Color.html("#c8a84e"))
	# guests: the order and the patience
	for g: Dictionary in Inn.guests(sim, building):
		var gid := str(g["id"])
		if not _views.has(gid):
			continue
		var p: Vector2 = (_views[gid] as Node2D).position - position + Vector2(0, -HEAD)
		match str(g.get("state", "")):
			"waiting":
				_order(p, str(g.get("order", "")))
				var span2 := maxf(1.0, float(int(g["until"]) - int(g["since"])))
				var left2 := clampf(float(int(g["until"]) - now) / span2, 0.0, 1.0)
				_bar(p + Vector2(0, -16), left2, Color(1.0 - left2, 0.3 + 0.6 * left2, 0.2))
			"eating":
				draw_circle(p + Vector2(0, 4), 4.0, Color.html("#e8dcc0"))
				draw_arc(p + Vector2(0, 4), 4.0, 0.0, TAU, 12, Color.html("#5a4030"), 1.0)
	if bool(inn.get("night", {}).get("minstrel", false)):
		var mz := interior.station_view("minstrel_corner")
		var at: Vector2 = (mz.position - position) if mz != null else Vector2(-120, 60)
		draw_string(_font, at + Vector2(-6, -46), "♪", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.html("#f0d070"))


func _bed(p: Vector2, c: Color, good: bool) -> void:
	var art := VisualPaths.inn_art("interior", "bed")
	if art != null:  # the art's bed (feet at its bottom centre), tinted by its state, and a dot of the state's colour
		var tint := Color.WHITE.lerp(c, 0.35)
		var sz := Vector2(art.get_size()) * BED_SCALE  # the room holds up to 8 beds a tile apart: drawn smaller
		draw_texture_rect(art, Rect2(p - Vector2(sz.x / 2.0, sz.y - 6.0), sz), false, tint)
		draw_circle(p + Vector2(0, -sz.y + 10.0), 3.0, c)
		if good:
			draw_line(p + Vector2(-14, -sz.y + 4.0), p + Vector2(14, -sz.y + 4.0), Color.html("#c8a84e"), 2.0)
		return
	var hw := 16.0
	var hh := 8.0
	var up := Vector2(0, -7)
	var frame := Color.html("#5a3a22")
	# the frame's two front faces, then the blanket on top (its colour is the bed's state) and the pillow
	draw_colored_polygon(PackedVector2Array([p + Vector2(-hw, 0), p + Vector2(0, hh), p + Vector2(0, hh) + up, p + Vector2(-hw, 0) + up]), frame.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, hh), p + Vector2(hw, 0), p + Vector2(hw, 0) + up, p + Vector2(0, hh) + up]), frame)
	var pts := PackedVector2Array([p + Vector2(0, -hh) + up, p + Vector2(hw, 0) + up, p + Vector2(0, hh) + up, p + Vector2(-hw, 0) + up])
	draw_colored_polygon(pts, c)
	pts.append(pts[0])
	draw_polyline(pts, Color.html("#2a1f14"), 1.0)
	draw_circle(p + up + Vector2(-8, -3), 3.0, Color.html("#f0e8d8"))
	if good:
		draw_line(p + Vector2(-hw, 0), p + Vector2(-hw, -24), Color.html("#c8a84e"), 2.0)
		draw_line(p + Vector2(hw, 0), p + Vector2(hw, -24), Color.html("#c8a84e"), 2.0)
		draw_line(p + Vector2(-hw, -24), p + Vector2(hw, -24), Color.html("#8a2e4a"), 3.0)


func _bar(p: Vector2, frac: float, c: Color) -> void:
	var w := 18.0
	draw_rect(Rect2(p + Vector2(-w / 2.0, 0), Vector2(w, 3)), Color.html("#1e1812"))
	draw_rect(Rect2(p + Vector2(-w / 2.0, 0), Vector2(w * clampf(frac, 0.0, 1.0), 3)), c)


## The order over the head: the item's small icon (assets/art/icons/small/<item>.png), else a disc with its first two
## letters (a visible placeholder).
func _order(p: Vector2, dish: String) -> void:
	var item := str(Inn.dish(sim, dish).get("item", dish))
	var tex := VisualPaths.inn_dish_icon(dish)
	if tex == null:
		tex = VisualPaths.icon_small(item)
	var kind := str(Inn.dish(sim, dish).get("kind", "drink"))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-4, 8), p + Vector2(4, 8), p + Vector2(0, 13)]), Color.html("#f4ead0"))
	draw_circle(p, 10.0, Color.html("#f4ead0"))
	draw_arc(p, 10.0, 0.0, TAU, 20, Color.html("#c8a84e") if kind == "drink" else Color.html("#9a3a24"), 2.0)
	if tex == null:
		var letter := SimQuery.t_("item." + item).substr(0, 2)
		draw_string(_font, p + Vector2(-8, 4), letter, HORIZONTAL_ALIGNMENT_CENTER, 16, 10, Color.html("#3a2414"))


## The guest under `world` (in the interior's coordinates), "" if none.
func pick_guest(world: Vector2) -> String:
	var best := ""
	var best_y := -INF
	for gid: String in _views:
		var v: CharacterView = _views[gid]
		if Rect2(v.position + Vector2(-9, -HEAD - 12), Vector2(18, HEAD + 14)).has_point(world) and v.position.y > best_y:
			best = gid
			best_y = v.position.y
	return best


func pick_bed(world: Vector2) -> int:
	for i: int in _bed_pos.size():
		if (world - (_bed_pos[i] as Vector2)).length() < 14.0:
			return i
	return -1


## Left click in the room: serve a waiting guest, or make a dirty bed (by whoever of the family is inside). True if
## used.
func handle_click(world: Vector2) -> bool:
	var gid := pick_guest(world)
	if gid != "":
		var g := Inn.guest(sim, building, gid)
		var who := server()
		if str(g.get("state", "")) != "waiting":
			message.emit(SimQuery.t_("ui.inn.guest_" + str(g.get("state", "seated"))))
			return true
		if who == "":
			message.emit(SimQuery.t_("ui.inn.nobody_to_serve"))
			return true
		interior._give({"type": "inn_serve", "actor": who, "building": building, "guest": gid})
		return true
	var bed := pick_bed(world)
	if bed >= 0:
		var beds: Array = Inn.state_of(sim, building).get("beds", [])
		if bed < beds.size() and str(beds[bed].get("state", "")) == "dirty":
			var who2 := server()
			if who2 != "":
				interior._give({"type": "inn_make_bed", "actor": who2, "building": building, "bed": bed})
			else:
				message.emit(SimQuery.t_("ui.inn.nobody_to_serve"))
		else:
			message.emit(SimQuery.t_("ui.inn.bed_" + str(beds[bed].get("state", "made")) if bed < beds.size() else ""))
		return true
	return false


## Who serves by hand: the selected person if it is inside and of the family, else the first of the player's family
## inside ("" if nobody).
func server() -> String:
	var a := interior.actor()
	if a != "" and (Buildings.owns(sim.state, a, building) or Staff.works_at(sim.state, a, building)):
		return a
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: Variant in ids:
		var ch: Dictionary = sim.state.characters[id]
		if str(ch.get("controlled_by", "")) == "human" and str(ch.get("location", "")) == building:
			return str(id)
	return ""


func clear() -> void:
	for v: Variant in _views.values() + _icons.values():
		(v as Node).queue_free()
	_views.clear()
	_icons.clear()
	sim = null
	queue_redraw()
