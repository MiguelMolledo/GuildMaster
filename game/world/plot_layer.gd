class_name PlotLayer
extends RefCounted
## Plots of the town map (docs/gdd/04_diseno_de_juego.md §4.9.1; data/maps "plots", made by tools/city/plots.py): the
## view only, the sim never reads them (buying, building, restoring and converting are H6). A free lot is bare ground
## (props/plot_ground on each tile, on the ground layer) with a stake at each corner (props/plot_stake); a ruin is
## broken walls (props/ruin_wall stumps on its edge tiles, of uneven heights, with gaps) on rubble (props/ruin_rubble); a business
## for sale (a plot with for_sale whose site holds, in this game, a building of an AI family) has the «Se vende» sign
## by its door, on the overlay (props/for_sale_sign). A lot or a ruin on filler tiles (#) takes them out of the filler, so no house
## is drawn there. The same tiles every game (they depend only on the map).

const STAKE_SHIFT: float = 0.42  # how far from a corner tile's centre towards the lot's corner a stake stands (× half tile)
const RUIN_HEIGHTS: Array = [26.0, 12.0, 20.0, 8.0, 16.0, 22.0, 10.0]  # the broken walls, by the tile's hash
const WALL_SCALE: float = 0.55  # a stump of wall is about half a tile wide
const GAP_EVERY: int = 4        # one edge tile in this many (by hash) is a gap of rubble

var world: Node = null
var shown: Dictionary = {}  # plot id -> "lot" | "ruin" | "for_sale" (tests, smoke)


func setup(w: Node) -> void:
	world = w
	shown = {}


## Draws the plots of `map` for `state`; takes the tiles of lots and ruins out of `filler`. Returns the pieces placed.
func build(map: Dictionary, state: WorldState, filler: Dictionary) -> int:
	shown = {}
	var n := 0
	var sim: Sim = world.get("sim") as Sim if world != null and world.get("sim") != null else null
	for p: Dictionary in map.get("plots", []):
		var kind := str(p.get("state", ""))
		var sale := bool(p.get("for_sale", false)) and _ai_owned(p, state)
		if sim != null:  # H6: the plot as it is now (built on, pulled down, a business for sale after a bankruptcy)
			var now := Plots.get_plot(sim, str(p["id"]))
			kind = str(now.get("kind", kind))
			var bld := str(now.get("building", ""))
			sale = bld != "" and bool(now.get("for_sale", false)) and (str(state.buildings[bld].get("owner", "")) == ""
				or str(state.families.get(str(state.buildings[bld].get("owner", "")), {}).get("controlled_by", "")) == "ai")
		match kind:
			"lot":
				n += _lot(p, filler)
				shown[str(p["id"])] = "lot"
			"ruin":
				n += _ruin(p, filler)
				shown[str(p["id"])] = "ruin"
			_:
				if sale:
					n += _sign(p)
					shown[str(p["id"])] = "for_sale"
	ViewConfig.info("PlotLayer", "parcelas: %d piezas %s" % [n, shown])
	return n


static func tiles_of(p: Dictionary) -> Array:
	var o: Array = p.get("origin", [0, 0])
	var s: Array = p.get("size", [1, 1])
	var out: Array = []
	for dr: int in int(s[1]):
		for dc: int in int(s[0]):
			out.append(Vector2i(int(o[0]) + dc, int(o[1]) + dr))
	return out


func _lot(p: Dictionary, filler: Dictionary) -> int:
	var n := 0
	var tiles := tiles_of(p)
	for t: Vector2i in tiles:
		filler.erase(t)
		var g := VisualPaths.instantiate("props", "plot_ground")
		g.name = "plot_ground_%d_%d" % [t.x, t.y]
		VisualPaths.place(g, Iso.tile_to_world(t))
		world.ground().add_child(g)
		n += 1
	var o: Array = p["origin"]
	var s: Array = p["size"]
	var c0 := Vector2i(int(o[0]), int(o[1]))
	var c1 := c0 + Vector2i(int(s[0]) - 1, int(s[1]) - 1)
	# the four corners: each stake on its corner tile, shifted towards the lot's outer corner
	for corner: Array in [[c0, Vector2(-1, -1)], [Vector2i(c1.x, c0.y), Vector2(1, -1)], [c1, Vector2(1, 1)],
			[Vector2i(c0.x, c1.y), Vector2(-1, 1)]]:
		var t: Vector2i = corner[0]
		var d: Vector2 = corner[1]
		var toward := Iso.tile_to_world(t + Vector2i(int(d.x), int(d.y))) - Iso.tile_to_world(t)
		var st := VisualPaths.instantiate("props", "plot_stake")
		st.name = "plot_stake_%s_%d_%d" % [p["id"], t.x, t.y]
		VisualPaths.place(st, Iso.tile_to_world(t) + toward * STAKE_SHIFT)
		world.objects().add_child(st)
		n += 1
	return n


func _ruin(p: Dictionary, filler: Dictionary) -> int:
	var n := 0
	var o: Array = p["origin"]
	var s: Array = p["size"]
	for t: Vector2i in tiles_of(p):
		filler.erase(t)
		var edge := t.x == int(o[0]) or t.y == int(o[1]) or t.x == int(o[0]) + int(s[0]) - 1 or t.y == int(o[1]) + int(s[1]) - 1
		var hsh := absi(t.x * 7 + t.y * 13)
		var wall := edge and hsh % GAP_EVERY != 0  # a broken wall has gaps: rubble where it fell
		var rubble := VisualPaths.instantiate("props", "ruin_rubble")
		rubble.name = "ruin_rubble_%d_%d" % [t.x, t.y]
		VisualPaths.place(rubble, Iso.tile_to_world(t))
		world.objects().add_child(rubble)
		n += 1
		if not wall:
			continue
		# a stump of wall: half a tile wide, of its own height, standing on the rubble
		var piece := VisualPaths.instantiate("props", "ruin_wall")
		piece.name = "ruin_wall_%d_%d" % [t.x, t.y]
		var h: float = RUIN_HEIGHTS[hsh % RUIN_HEIGHTS.size()]
		piece.scale = Vector2(WALL_SCALE, WALL_SCALE)
		var g := piece.get_node_or_null("Greybox")
		if g != null:
			g.set("height", h / WALL_SCALE)
		var top := piece.get_node_or_null("Top") as Node2D
		if top != null:
			top.position.y = -h / WALL_SCALE
		VisualPaths.place(piece, Iso.tile_to_world(t))
		world.objects().add_child(piece)
		(world.get("_props") as Dictionary)[t] = piece  # what covers a walker goes see-through, like the filler
		n += 1
	return n


## Whether the plot's site holds, in this game, a building of an AI family (the one that would sell it).
static func _ai_owned(p: Dictionary, state: WorldState) -> bool:
	var o: Array = p.get("origin", [])
	for id: String in state.buildings:
		var b: Dictionary = state.buildings[id]
		var bo: Array = b.get("origin", [])
		if bo.size() == 2 and o.size() == 2 and int(bo[0]) == int(o[0]) and int(bo[1]) == int(o[1]):
			var fam: Dictionary = state.families.get(str(b.get("owner", "")), {})
			return str(fam.get("controlled_by", "")) == "ai"
	return false


func _sign(p: Dictionary) -> int:
	var door: Array = p.get("front", p.get("origin", [0, 0]))
	var sg := VisualPaths.instantiate("props", "for_sale_sign")
	sg.name = "for_sale_%s" % p["id"]
	var text := sg.get_node_or_null("%Text") as Label
	if text != null:
		text.text = SimQuery.t_("ui.plot.for_sale")
		WorldLabels.style(text, "small")   # the town's lettering (verificación B), not Godot's default (jugador J1)
	# on the overlay (like the buildings' signs): never hidden by a block in front of the door
	VisualPaths.place(sg, Iso.tile_to_world(Vector2i(int(door[0]), int(door[1]))) + Vector2(0, -4))
	world.overlay().add_child(sg)
	return 1
