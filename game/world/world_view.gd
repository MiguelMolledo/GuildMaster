class_name WorldView
extends Node2D
## The town seen from outside (H1-H2): greybox ground, blocked tiles with volume, the buildings of state.buildings
## (own colour, sign and door mark), walkers, the camera and the day/night tint. Reads Game.state and the catalog;
## the only thing it sends back are orders (D3: a right click on a tile with someone selected -> move_to; on a
## building -> enter_building). It never writes the state. People inside a building (location != "") are hidden.
##
## Controls: left click on one of the human family's people selects it (left click elsewhere deselects);
## left click on a building picks it (the HUD shows its "Manage" button), double click opens it in management mode;
## right click on a tile sends the selected person there, on a building sends them in. Camera: see WorldCamera.
## H3: the market stalls and the contract board of the map get a sign; a right click on one with someone selected
## sends them to its service tile (move_to) and emits service_requested: the HUD opens its panel on arrival.
## Buildings of other families carry the family's name ("Forja de Ferrer").
## H4: the houses of the townsfolk show their sign only while the mouse is over them or when picked (data/view.json
## buildings.<type>.sign_mode = "hover"), so the town is not full of signs; the townsfolk show their name on hover and the
## employees a badge (CharacterView.set_badge); a building of the player's family with idle employees gets the idle
## icon over it (WorkQueue.idle_employees, refreshed each game minute; needs the Sim: setup(..., sim)).
## Visuals: every building, map prop (tree, block, stall, board) and walker is the scene of its id in game/visuals/
## (VisualPaths), placed by its Feet marker; its Top marker gives the height of its sign and of its click area.
## The free building tiles (#) are dressed as houses and yards (data/view.json "filler", _add_filler) and the map's
## hand-placed decoration comes from game/visuals/towns/<map id>.tscn (_add_town_decor).

const FILLER_KIND: String = "building"  # map tiles that are town blocks unless a building of the state owns them

signal selection_changed(char_id: String)
signal building_picked(building_id: String)   # "" = none
signal manage_requested(building_id: String)  # double click on a building (GDD 4.6.4, management mode)
## Right click on a stall or the board (kind "stall"|"board", id = stall id or "board", service = its service tile);
## kind "" = the selected person got another order (forget a pending one).
signal service_requested(actor: String, kind: String, id: String, service: Vector2i)

var order_sink: Callable = Callable()  # who receives the orders: Game.give in the game, a test's own in the tests
var state: WorldState
var catalog: Catalog
var sim: Sim = null         # H4: for the queries that need it (idle employees); null = no idle icons
var selected_id: String = ""
var picked_building: String = ""
var tint_color: Color = Color.WHITE
var _views: Dictionary = {}  # chr_id -> CharacterView
var _signs: Dictionary = {}  # bld_id -> BuildingMarks.Sign
var _service_signs: Dictionary = {}  # stall id | "board" -> BuildingMarks.Sign
var _services: Array = []   # SimQuery.map_services
var _building_visuals: Dictionary = {}  # bld_id -> its scene of game/visuals/buildings
var _building_heights: Dictionary = {}  # bld_id -> how high it stands (its Top marker): sign and click area
var _props: Dictionary = {}  # Vector2i -> the scene of game/visuals/props standing on that tile
var _minutes_per_tile: int = 1
var _game: Node = null      # the Game autoload, when in the tree
var _hover_signs: Dictionary = {}  # bld -> true: signs shown only on hover / pick (houses)
var _idle_marks: Dictionary = {}   # bld -> BuildingMarks.IdleMark
var _works_bars: Dictionary = {}   # bld -> BuildingMarks.WorksBar (H5: works in progress)
var hovered_building: String = ""
var hovered_character: String = ""
var _idle_minute: int = -1
var _player_family: String = ""


func _ready() -> void:
	_game = get_node_or_null("/root/Game")
	if _game == null:
		return
	order_sink = _game.give
	_game.started.connect(func() -> void: setup(_game.sim.state, _game.sim.catalog, _game.sim))
	if _game.sim != null:
		setup(_game.sim.state, _game.sim.catalog, _game.sim)


func ground() -> GroundLayer:
	return get_node("%Ground")


func objects() -> Node2D:
	return get_node("%Objects")


func camera() -> WorldCamera:
	return get_node("%Camera")


func marker() -> TargetMarker:
	return get_node("%Marker")


func overlay() -> Node2D:
	return get_node("%Overlay")


## Shown and taking input (the town), or hidden and frozen while an interior is open (GDD 4.6.4).
func set_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	camera().enabled = active
	if active and camera().is_inside_tree():
		camera().make_current()


## Builds the view of `s`. Called again whenever a new state is loaded.
func setup(s: WorldState, c: Catalog, sim_ref: Sim = null) -> void:
	state = s
	catalog = c
	sim = sim_ref
	selected_id = ""
	picked_building = ""
	hovered_building = ""
	hovered_character = ""
	_idle_minute = -1
	_player_family = SimQuery.player_family(s)
	_views.clear()
	_signs.clear()
	_hover_signs.clear()
	_idle_marks.clear()
	_works_bars.clear()
	_service_signs.clear()
	_building_visuals.clear()
	_building_heights.clear()
	_props.clear()
	for layer: Node in [objects(), overlay()]:
		for n: Node in layer.get_children():
			layer.remove_child(n)
			n.queue_free()
	_minutes_per_tile = ViewConfig.minutes_per_tile(c)
	var rows: Array = c.maps().get(s.map_id, {}).get("rows", [])
	ground().build(rows, c)
	var owned := _add_buildings()
	_services = SimQuery.map_services(s, c)
	var stall_at := {}
	for svc: Dictionary in _services:
		if str(svc["kind"]) == "stall":
			stall_at[svc["tile"]] = str(svc["id"])
	var n_blocks := 0
	var filler := {}  # free building tiles (#) dressed as houses and yards (data/view.json "filler")
	var dress := not (ViewConfig.value("filler", {}) as Dictionary).is_empty()
	var variants: Dictionary = ViewConfig.value("prop_variants", {})
	for r: int in rows.size():
		var row := str(rows[r])
		for col: int in row.length():
			var t := Vector2i(col, r)
			if owned.has(t):
				continue
			var kind := c.tile_kind_of_char(row[col])
			if dress and kind == FILLER_KIND and not stall_at.has(t):
				filler[t] = true
				continue
			var id := "stall_" + str(stall_at[t]) if stall_at.has(t) else kind
			if variants.get(id) is Array and not (variants[id] as Array).is_empty():
				var looks: Array = variants[id]
				id = str(looks[_tile_hash(t) % looks.size()])  # one of the kind's looks, the same every game
			# a tile kind stands up if it has a scene in game/visuals/props/; stalls and the board always do
			if not VisualPaths.has_scene("props", id) and kind != "stall" and kind != "board":
				continue
			var p := VisualPaths.instantiate("props", id)
			VisualPaths.place(p, Iso.tile_to_world(t))
			objects().add_child(p)
			_props[t] = p
			n_blocks += 1
	n_blocks += _add_filler(filler)
	n_blocks += _add_border_trees()
	_add_town_decor(s.map_id)
	_add_services()
	var ids: Array = s.characters.keys()
	ids.sort()
	for id: String in ids:
		_add_view(str(id))
	var cam := camera()
	if rows.is_empty():
		cam.set_bounds(Rect2())
		cam.center_on(Vector2.ZERO)
	else:
		var w := str(rows[0]).length()
		var h := rows.size()
		var left := Iso.tile_to_world(Vector2i(0, h - 1)).x
		var right := Iso.tile_to_world(Vector2i(w - 1, 0)).x
		var bottom := Iso.tile_to_world(Vector2i(w - 1, h - 1)).y
		cam.set_bounds(Rect2(left, 0.0, right - left, bottom))
		cam.center_on(_start_focus(Iso.tile_to_world(Vector2i(w / 2, h / 2))))
	sync(0.0)
	ViewConfig.info("WorldView", "setup (map=%s, rows=%d, blocks=%d, buildings=%d, characters=%d, minutes_per_tile=%d)" % [
		s.map_id, rows.size(), n_blocks, _signs.size(), _views.size(), _minutes_per_tile])


## The buildings of the state: the scene of its type (game/visuals/buildings/<type>.tscn) on the footprint's centre,
## the door mark and the sign. Returns the footprint tiles (the plain map blocks skip them).
func _add_buildings() -> Dictionary:
	var tiles := {}
	var looks: Dictionary = ViewConfig.value("buildings", {})
	var ids: Array = state.buildings.keys()
	ids.sort()
	for id: String in ids:
		var b: Dictionary = state.buildings[id]
		var look: Dictionary = looks.get(str(b.get("type", "")), {})
		var o: Array = b.get("origin", [0, 0])
		var f: Array = b.get("footprint", [1, 1])
		var top := Vector2.ZERO
		for dr: int in int(f[1]):
			for dc: int in int(f[0]):
				var t := Vector2i(int(o[0]) + dc, int(o[1]) + dr)
				tiles[t] = true
				top += Iso.tile_to_world(t)
		top /= maxf(1.0, float(int(f[0]) * int(f[1])))
		var scene_id := str(b.get("type", ""))
		var variants: Dictionary = ViewConfig.value("building_variants", {})
		if variants.get(scene_id) is Array and not (variants[scene_id] as Array).is_empty():
			var looks_of: Array = variants[scene_id]  # one of the type's looks, by its origin tile (same every game)
			scene_id = str(looks_of[_tile_hash(Vector2i(int(o[0]), int(o[1]))) % looks_of.size()])
		var visual := VisualPaths.instantiate("buildings", scene_id)
		var greybox := visual.get_node_or_null("Greybox")
		if greybox != null and greybox.has_method("apply_footprint"):
			greybox.call("apply_footprint", Vector2i(int(f[0]), int(f[1])))
		visual.name = id + "_visual"
		VisualPaths.place(visual, top)
		objects().add_child(visual)
		var height := VisualPaths.top_height(visual, 48.0)
		_building_visuals[id] = visual
		_building_heights[id] = height
		var d: Array = b.get("door", [])
		if d.size() == 2:
			var dm := BuildingMarks.DoorMark.new()
			dm.color = ViewConfig.color(str(look.get("door", "#c8a050")))
			dm.position = Iso.tile_to_world(Vector2i(int(d[0]), int(d[1])))
			dm.name = id + "_door"
			overlay().add_child(dm)  # over the blocks: the door may be on the hidden side
		var sg := BuildingMarks.Sign.new()
		sg.setup(SimQuery.building_label(state, catalog, id), ViewConfig.color(str(look.get("sign", "#e0903a"))))
		sg.position = (top + Vector2(0, -height - 20)).round()
		sg.name = id
		overlay().add_child(sg)
		_signs[id] = sg
		if str(look.get("sign_mode", "")) == "hover":
			_hover_signs[id] = true
			sg.visible = false
		var idle := BuildingMarks.IdleMark.new()
		idle.name = id + "_idle"
		idle.position = sg.position + Vector2(0, -18)
		idle.visible = false
		overlay().add_child(idle)
		_idle_marks[id] = idle
		var works := BuildingMarks.WorksBar.new()
		works.name = id + "_works"
		works.setup((ViewConfig.value("upgrades", {}) as Dictionary).get("works", {}))
		works.position = sg.position + Vector2(0, -16)
		works.visible = false
		overlay().add_child(works)
		_works_bars[id] = works
		var scaffold := visual.get_node_or_null("Works") as CanvasItem
		if scaffold != null:
			scaffold.visible = false
	return tiles


## Whether the sign of `building` is shown now (hover-only signs: while hovered or picked).
func sign_shown(building: String) -> bool:
	var sg: Node2D = _signs.get(building, null)
	return sg != null and sg.visible


func _update_signs() -> void:
	for id: String in _hover_signs:
		(_signs[id] as Node2D).visible = id == hovered_building or id == picked_building


## The idle icon of `building` (null if none).
func idle_mark_of(building: String) -> Node2D:
	return _idle_marks.get(building, null)


## The idle icons: over each building of the player's family with idle employees (WorkQueue.idle_employees).
func refresh_idle() -> void:
	for id: String in _idle_marks:
		var on := false
		if sim != null and _player_family != "" and SimQuery.building_family(state, id) == _player_family:
			on = not SimQuery.idle_employees(sim, id).is_empty()
		var m: BuildingMarks.IdleMark = _idle_marks[id]
		if m.visible != on:
			m.visible = on
			ViewConfig.info("WorldView", "idle icon %s (building=%s)" % ["on" if on else "off", id])


## The works bar of `building` (null if none).
func works_bar_of(building: String) -> BuildingMarks.WorksBar:
	return _works_bars.get(building, null)


## The scaffold of `building` (the node Works of its scene; null if its scene has none).
func scaffold_of(building: String) -> CanvasItem:
	var v: Node = _building_visuals.get(building, null)
	return v.get_node_or_null("Works") as CanvasItem if v != null else null


## The upgrade overlays of each building: the nodes under Upgrades of its scene named by its finished upgrades
## (SimQuery.upgrade_visual_nodes "exterior") are shown, the rest hidden. H5: a building under construction shows
## the node Works of its scene (the scaffold) and the works bar with the time left. Needs the Sim.
func refresh_upgrades() -> void:
	if sim == null:
		return
	for id: String in _works_bars:
		var w := SimQuery.upgrade_works(sim, id)
		var bar: BuildingMarks.WorksBar = _works_bars[id]
		var scaffold := scaffold_of(id)
		if bar.visible != not w.is_empty():
			ViewConfig.info("WorldView", "works %s (building=%s, upgrade=%s)" % ["on" if not w.is_empty() else "off", id,
				str(w.get("upgrade", ""))])
		bar.visible = not w.is_empty()
		if scaffold != null:
			scaffold.visible = not w.is_empty()
		if not w.is_empty():
			bar.progress = float(w.get("progress", 0.0))
			bar.set_text(SimQuery.t_("ui.upgrades.works_left") % SimQuery.minutes_left_label(int(w.get("minutes_left", 0))))
		var idle: Node2D = _idle_marks.get(id, null)
		if idle != null:
			idle.position = bar.position + Vector2(0, -16 if bar.visible else -2)
	for id: String in _building_visuals:
		var ups := (_building_visuals[id] as Node).get_node_or_null("Upgrades")
		if ups == null or ups.get_child_count() == 0:
			continue
		var on := {}
		for n: String in SimQuery.upgrade_visual_nodes(sim, id, "exterior"):
			on[n] = true
		for u: Node in ups.get_children():
			if u is CanvasItem and (u as CanvasItem).visible != on.has(str(u.name)):
				(u as CanvasItem).visible = on.has(str(u.name))
				ViewConfig.info("WorldView", "upgrade overlay %s %s (building=%s)" % [u.name, "on" if on.has(str(u.name)) else "off", id])


## Mouse over the map (every frame): the building and person under it (hover signs and names).
func update_hover(screen: Vector2) -> void:
	var bld := pick_building(screen)
	if bld != hovered_building:
		hovered_building = bld
		_update_signs()
	var who := pick_any_character(screen)
	if who != hovered_character:
		if _views.has(hovered_character):
			(_views[hovered_character] as CharacterView).hovered = false
		hovered_character = who
		if _views.has(who):
			(_views[who] as CharacterView).hovered = true


## Anybody visible under `screen` (the front-most figure), "" if nobody.
func pick_any_character(screen: Vector2) -> String:
	var world := camera().screen_to_world(screen)
	var best := ""
	var best_y := -INF
	for id: String in _views:
		var v: CharacterView = _views[id]
		if v.visible and v.pick_rect().has_point(world) and v.position.y > best_y:
			best = id
			best_y = v.position.y
	return best


func sign_of(building_id: String) -> Node2D:
	return _signs.get(building_id, null)


## The building's scene (game/visuals/buildings), or null.
func building_visual(building_id: String) -> Node2D:
	return _building_visuals.get(building_id, null)


## The prop standing on `tile` (game/visuals/props), or null.
func prop_at(tile: Vector2i) -> Node2D:
	return _props.get(tile, null)


## The free building tiles of the map (# not owned by a building of the state) dressed as the town's blocks
## (data/view.json "filler"): each connected group is filled with house lots (the first lot size of `lot_sizes` that
## fits, scanning row by row) and the tiles left over become yards (low props, so they never hide the base of the
## building behind): each group takes one of `yard_themes` (a vegetable plot, a work yard...) and each tile one yard
## of its theme, each one at most once per group (the theme's first yard fills the rest). A lone tile gets `single`. Which house or yard goes where depends only on the tiles, so the town
## looks the same in every game; `mirror` flips half of the houses. Returns how many visuals were placed.
func _add_filler(tiles: Dictionary) -> int:
	if tiles.is_empty():
		return 0
	var cfg: Dictionary = ViewConfig.value("filler", {})
	var houses: Array = cfg.get("houses", [])
	var themes: Array = cfg.get("yard_themes", [])
	var single := str(cfg.get("single", ""))
	var mirror := bool(cfg.get("mirror", true))
	var sizes: Array = cfg.get("lot_sizes", [[3, 4], [4, 3], [3, 3]])
	var keys: Array = tiles.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var free := tiles.duplicate()
	var placed := 0
	var lots := 0
	var seen := {}
	for start: Vector2i in keys:
		if seen.has(start):
			continue
		var group: Array = []  # the connected tiles of this block, in reading order
		var stack: Array = [start]
		seen[start] = true
		while not stack.is_empty():
			var t: Vector2i = stack.pop_back()
			group.append(t)
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				if tiles.has(t + d) and not seen.has(t + d):
					seen[t + d] = true
					stack.append(t + d)
		group.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		if group.size() == 1 and single != "":
			placed += _place_filler(single, [group[0]], false)
			free.erase(group[0])
			continue
		var last_house := -1
		if not houses.is_empty():
			for t: Vector2i in group:
				if not free.has(t):
					continue
				for sz: Array in sizes:
					var lot := _lot_at(free, t, Vector2i(int(sz[0]), int(sz[1])))
					if lot.is_empty():
						continue
					var h := _tile_hash(t)
					var k := h % houses.size()
					if k == last_house:
						k = (k + 1) % houses.size()  # two lots side by side never get the same house
					last_house = k
					placed += _place_filler(str(houses[k]), lot, mirror and (h / 7) % 2 == 1)
					for u: Vector2i in lot:
						free.erase(u)
					lots += 1
					break
		if themes.is_empty():
			continue
		var theme: Array = themes[_tile_hash(group[0] * 3 + Vector2i(1, 7)) % themes.size()]
		var used := {}
		for t: Vector2i in group:
			if free.has(t) and not theme.is_empty():
				var yard := str(theme[_tile_hash(t) % theme.size()])
				if used.has(yard):
					yard = str(theme[0])  # each yard with props once per block; the rest, the theme's first one
				used[yard] = true
				placed += _place_filler(yard, [t], false)
				free.erase(t)
	ViewConfig.info("WorldView", "filler: %d tiles -> %d house lots, %d visuals (houses=%d kinds, yard themes=%d)" % [
		tiles.size(), lots, placed, houses.size(), themes.size()])
	return placed


## The tiles of a w×h lot whose top-left corner is `at`, if all of them are free; else [].
func _lot_at(free: Dictionary, at: Vector2i, size: Vector2i) -> Array:
	var out: Array = []
	for dr: int in size.y:
		for dc: int in size.x:
			var t := at + Vector2i(dc, dr)
			if not free.has(t):
				return []
			out.append(t)
	return out


## One filler visual (game/visuals/props/<id>.tscn) on the centre of `lot`; registered as the prop of each tile.
func _place_filler(id: String, lot: Array, flip: bool) -> int:
	var centre := Vector2.ZERO
	for t: Vector2i in lot:
		centre += Iso.tile_to_world(t)
	centre /= float(lot.size())
	var p := VisualPaths.instantiate("props", id)
	if flip:
		p.scale.x = -1.0  # mirrored around its Feet (x = 0 in every filler scene)
	VisualPaths.place(p, centre)
	objects().add_child(p)
	for t: Vector2i in lot:
		_props[t] = p
	return 1


## A well-mixed number from a tile (neighbouring tiles get unrelated values), always >= 0.
static func _tile_hash(t: Vector2i) -> int:
	var h := t.x * 374761393 + t.y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h) % 1000003


## The trees of the map border (data/view.json "map_border", the ring GroundLayer draws around the map): on its
## ground tiles from `tree_from` out, with a chance growing towards the outer edge, darkened like the ground under them.
## Purely visual and outside the grid (no clicks, no paths). The same every game (by tile).
func _add_border_trees() -> int:
	var cfg: Dictionary = ViewConfig.value("map_border", {})
	var trees: Array = cfg.get("trees", [])
	var ring := int(cfg.get("tiles", 0))
	if trees.is_empty() or ring <= 0:
		return 0
	var ground := str(cfg.get("ground", "grass"))
	var from := int(cfg.get("tree_from", 3))
	var dens: Array = cfg.get("tree_density", [0.2, 0.7])
	var n := 0
	for cell: Array in ground().border_cells():
		var d := int(cell[3])
		if str(cell[1]) != ground or d < from:
			continue
		var t: Vector2i = cell[0]
		var k := float(d - from) / maxf(1.0, float(ring - from))
		var chance := lerpf(float(dens[0]), float(dens[1]), k)
		if float(_tile_hash(t) % 1000) / 1000.0 >= chance:
			continue
		var p := VisualPaths.instantiate("props", str(trees[_tile_hash(t * 7 + Vector2i(3, 1)) % trees.size()]))
		VisualPaths.place(p, Iso.tile_to_world(t) + Vector2(float(_tile_hash(t) % 13) - 6.0, float(_tile_hash(t) % 7) - 3.0))
		p.modulate = cell[2]
		p.name = "border_tree_%d_%d" % [t.x + 100, t.y + 100]
		objects().add_child(p)
		n += 1
	ViewConfig.info("WorldView", "map border: %d trees" % n)
	return n


## The hand-placed decoration of the map (game/visuals/towns/<map id>.tscn: barrels, benches, carts... placed in the
## editor in world pixels): its children join the objects layer so they sort with the walkers. Purely visual: they
## do not block the way, so they go on grass or by the walls, not in the street.
func _add_town_decor(map_id: String) -> void:
	if not VisualPaths.has_scene("towns", map_id):
		return
	var decor := VisualPaths.instantiate("towns", map_id)
	var n := 0
	for ch: Node in decor.get_children():
		if not ch is Node2D:
			continue
		decor.remove_child(ch)
		ch.owner = null
		(ch as Node2D).position += decor.position
		objects().add_child(ch)
		n += 1
	decor.free()
	ViewConfig.info("WorldView", "town decor %s: %d pieces" % [map_id, n])


## How high the stall or board of `svc` stands (its prop's Top marker).
func _service_height(svc: Dictionary) -> float:
	var p: Node2D = _props.get(svc["tile"], null)
	return VisualPaths.top_height(p, 24.0) if p != null else 24.0


## The signs of the market stalls and the board (data/view.json "services": colours; the props come from the map).
func _add_services() -> void:
	var looks: Dictionary = ViewConfig.value("services", {})
	for svc: Dictionary in _services:
		var kind := str(svc["kind"])
		var id := str(svc["id"])
		var h := _service_height(svc)
		var sg := BuildingMarks.Sign.new()
		var text := SimQuery.stall_name(catalog, id) if kind == "stall" else SimQuery.t_("ui.board.sign")
		sg.setup(text, ViewConfig.color(str(looks.get(kind + "_sign", "#d8c8a0"))))
		sg.position = (Iso.tile_to_world(svc["tile"]) + Vector2(0, -h - 16)).round()
		sg.name = "service_" + id
		overlay().add_child(sg)
		_service_signs[id] = sg


## The sign of a stall (its id) or of the board ("board"), or null.
func service_sign_of(id: String) -> Node2D:
	return _service_signs.get(id, null)


## The stall or board under `screen` ({} if none): the drawn block of its tile, else the tile itself.
func pick_service(screen: Vector2) -> Dictionary:
	var world := camera().screen_to_world(screen)
	for svc: Dictionary in _services:
		var h := _service_height(svc)
		var p := Iso.tile_to_world(svc["tile"])
		var hw := Iso.TILE_W / 2.0
		var hh := Iso.TILE_H / 2.0
		var poly := PackedVector2Array([p + Vector2(-hw, 0), p + Vector2(-hw, -h), p + Vector2(0, -hh - h),
			p + Vector2(hw, -h), p + Vector2(hw, 0), p + Vector2(0, hh)])
		if Geometry2D.is_point_in_polygon(world, poly):
			return svc
	var tile := Iso.world_to_tile(world)
	for svc: Dictionary in _services:
		if svc["tile"] == tile:
			return svc
	return {}


## Where a stall (its id) or the board ("board") is on screen: the middle of its block.
func service_screen(id: String) -> Vector2:
	for svc: Dictionary in _services:
		if str(svc["id"]) == id:
			var h := _service_height(svc)
			return camera().world_to_screen(Iso.tile_to_world(svc["tile"]) + Vector2(0, -h / 2.0))
	return Vector2(-1, -1)


## Sends the selected person to the service tile of `svc` (a stall or the board) and tells the HUD, which opens the
## panel when they stand there (at once if they already do).
func command_service(svc: Dictionary) -> void:
	if selected_id == "" or svc.is_empty():
		return
	var service: Vector2i = svc["service"]
	if not SimQuery.stands_on(state, selected_id, service):
		var order := {"type": "move_to", "actor": selected_id, "tile": [service.x, service.y]}
		ViewConfig.info("WorldView", "order move_to %s %s (actor=%s, tile=%s)" % [svc["kind"], svc["id"], selected_id, service])
		if order_sink.is_valid():
			order_sink.call(order)
		marker().show_at(service, float(ViewConfig.value("target_marker_seconds", 1.0)))
	service_requested.emit(selected_id, str(svc["kind"]), str(svc["id"]), service)


func _add_view(id: String) -> void:
	var ch: Dictionary = state.characters[id]
	if not bool(ch.get("alive", true)) or not ch.has("position"):
		return
	var v := CharacterView.new()
	v.setup(ch, state.families.get(str(ch.get("family", "")), {}))
	objects().add_child(v)
	_views[id] = v


## The first person of the human family, else `fallback`.
func _start_focus(fallback: Vector2) -> Vector2:
	var id := first_selectable()
	if id == "":
		return fallback
	var pos: Array = state.characters[id]["position"]
	return Iso.tile_to_world(Vector2i(int(pos[0]), int(pos[1])))


func first_selectable() -> String:
	var ids: Array = _views.keys()
	ids.sort()
	for id: String in ids:
		if (_views[id] as CharacterView).selectable:
			return id
	return ""


func view_of(id: String) -> CharacterView:
	return _views.get(id, null)


func _process(_delta: float) -> void:
	if state == null:
		return
	sync(_game.step_fraction() if _game != null else 0.0)
	update_hover(get_viewport().get_mouse_position())


## Follows the state: new or dead walkers, positions, the day/night tint. `frac` = how far towards the next step.
func sync(frac: float) -> void:
	for id: String in state.characters:
		if not _views.has(id):
			_add_view(id)
	for id: String in _views.keys():
		var ch: Dictionary = state.characters.get(id, {})
		if ch.is_empty() or not bool(ch.get("alive", true)):
			(_views[id] as CharacterView).queue_free()
			_views.erase(id)
			if id == selected_id:
				select("")
			continue
		var v: CharacterView = _views[id]
		if v.kin_sig != CharacterView.kin_signature(ch):  # H8: married, came of age, hired...: rebuild it
			var was := id == selected_id
			v.queue_free()
			_views.erase(id)
			_add_view(id)
			if not _views.has(id):
				continue
			v = _views[id]
			if was:
				v.selected = v.selectable
				if not v.selectable:
					select("")
		v.visible = str(ch.get("location", "")) == ""
		v.follow(ch, _minutes_per_tile, frac)
		v.follow_badge(state, _player_family)
	if int(state.clock["minute"]) != _idle_minute:
		_idle_minute = int(state.clock["minute"])
		refresh_idle()
		refresh_upgrades()
	tint_color = DayNight.tint(int(state.clock["minute"]), frac, catalog.time, ViewConfig.value("day_night", {}))
	(get_node("%Tint") as CanvasModulate).color = tint_color


func select(id: String) -> void:
	if id == selected_id:
		return
	if selected_id != "" and _views.has(selected_id):
		(_views[selected_id] as CharacterView).selected = false
	selected_id = id if _views.has(id) else ""
	if selected_id != "":
		(_views[selected_id] as CharacterView).selected = true
	ViewConfig.info("WorldView", "selected %s" % (selected_id if selected_id != "" else "nobody"))
	selection_changed.emit(selected_id)


## Screen (viewport) pixel -> tile under it, with the camera as drawn.
func screen_to_tile(screen: Vector2) -> Vector2i:
	return Iso.world_to_tile(camera().screen_to_world(screen))


func tile_to_screen(tile: Vector2i) -> Vector2:
	return camera().world_to_screen(Iso.tile_to_world(tile))


## The human family's person under `screen`: the figure first (the front-most one), else whoever stands on the tile.
func pick_character(screen: Vector2) -> String:
	var world := camera().screen_to_world(screen)
	var best := ""
	var best_y := -INF
	for id: String in _views:
		var v: CharacterView = _views[id]
		if v.selectable and v.visible and v.pick_rect().has_point(world) and v.position.y > best_y:
			best = id
			best_y = v.position.y
	if best != "":
		return best
	var tile := Iso.world_to_tile(world)
	for id: String in _views:
		var pos: Array = state.characters[id].get("position", [])
		var cv: CharacterView = _views[id]
		if cv.selectable and cv.visible and Vector2i(int(pos[0]), int(pos[1])) == tile:
			return id
	return ""


## Sends the selected person to `tile` (the sim decides whether it can).
func command_move(tile: Vector2i) -> void:
	if selected_id == "":
		return
	var order := {"type": "move_to", "actor": selected_id, "tile": [tile.x, tile.y]}
	ViewConfig.info("WorldView", "order move_to (actor=%s, tile=%s)" % [selected_id, tile])
	if order_sink.is_valid():
		order_sink.call(order)
	service_requested.emit(selected_id, "", "", Vector2i.ZERO)
	marker().show_at(tile, float(ViewConfig.value("target_marker_seconds", 1.0)))


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


## The building under `screen` ("" if none): the drawn volume of one of its footprint blocks, else its door tile.
func pick_building(screen: Vector2) -> String:
	var world := camera().screen_to_world(screen)
	var ids: Array = state.buildings.keys()
	ids.sort()
	for id: String in ids:
		var b: Dictionary = state.buildings[id]
		var h := float(_building_heights.get(id, 48.0))
		var o: Array = b.get("origin", [0, 0])
		var f: Array = b.get("footprint", [1, 1])
		for dr: int in int(f[1]):
			for dc: int in int(f[0]):
				var p := Iso.tile_to_world(Vector2i(int(o[0]) + dc, int(o[1]) + dr))
				var hw := Iso.TILE_W / 2.0
				var hh := Iso.TILE_H / 2.0
				var poly := PackedVector2Array([p + Vector2(-hw, 0), p + Vector2(-hw, -h), p + Vector2(0, -hh - h),
					p + Vector2(hw, -h), p + Vector2(hw, 0), p + Vector2(0, hh)])
				if Geometry2D.is_point_in_polygon(world, poly):
					return str(id)
	var tile := Iso.world_to_tile(world)
	for id: String in ids:
		var d: Array = state.buildings[id].get("door", [])
		if d.size() == 2 and Vector2i(int(d[0]), int(d[1])) == tile:
			return str(id)
	return ""


func pick_building_id(id: String) -> void:
	if id == picked_building:
		return
	if _signs.has(picked_building):
		(_signs[picked_building] as BuildingMarks.Sign).highlighted = false
	picked_building = id if state.buildings.has(id) else ""
	if _signs.has(picked_building):
		(_signs[picked_building] as BuildingMarks.Sign).highlighted = true
	_update_signs()
	ViewConfig.info("WorldView", "picked building %s" % (picked_building if picked_building != "" else "none"))
	building_picked.emit(picked_building)


## Sends the selected person into `building` (walks to the door, then inside; the sim decides whether it can).
func command_enter(building: String) -> void:
	if selected_id == "":
		return
	var order := {"type": "enter_building", "actor": selected_id, "building": building}
	ViewConfig.info("WorldView", "order enter_building (actor=%s, building=%s)" % [selected_id, building])
	if order_sink.is_valid():
		order_sink.call(order)
	service_requested.emit(selected_id, "", "", Vector2i.ZERO)
	var d: Array = state.buildings.get(building, {}).get("door", [])
	if d.size() == 2:
		marker().show_at(Vector2i(int(d[0]), int(d[1])), float(ViewConfig.value("target_marker_seconds", 1.0)))


## Clicks of the world: left selects a person or picks a building (double click: manage it), else deselects;
## right moves the selected person, or sends them into the building clicked. True if used.
func handle_input(event: InputEvent) -> bool:
	if state == null or not event is InputEventMouseButton or not event.is_pressed():
		return false
	var mb := event as InputEventMouseButton
	if event.is_action_pressed("select"):
		var who := pick_character(mb.position)
		if who != "":
			select(who)
			return true
		var bld := pick_building(mb.position)
		pick_building_id(bld)
		if bld == "":
			select("")
		elif mb.double_click:
			ViewConfig.info("WorldView", "manage %s (double click)" % bld)
			manage_requested.emit(bld)
		return true
	if event.is_action_pressed("command") and selected_id != "":
		var svc := pick_service(mb.position)
		if not svc.is_empty():
			command_service(svc)
			return true
		var bld := pick_building(mb.position)
		if bld != "":
			command_enter(bld)
		else:
			command_move(screen_to_tile(mb.position))
		return true
	return false
