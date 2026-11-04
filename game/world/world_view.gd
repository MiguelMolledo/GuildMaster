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
signal npc_picked(char_id: String)  # H7: a click on somebody who is not of the player's family (their sheet)

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
var _talker: String = ""  # H7: the townsperson who speaks to the selected person (SimQuery.nearest_talker)
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
var _see_through: Array = []  # tall visuals (buildings, filler houses) that fade while they hide the selected person


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
	ground().set_season(Clock.season(int(s.clock.get("minute", 0)), c.time))
	var owned := _add_buildings()
	_services = SimQuery.map_services(s, c)
	_add_town_hall(owned)  # H9: a site of the map drawn as a building (its tiles get no filler)
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
	n_blocks += _add_decor(c.maps().get(s.map_id, {}).get("decor", {}), filler, owned)
	n_blocks += _add_filler(filler)
	n_blocks += _add_border_trees()
	_add_town_decor(s.map_id)
	_add_services()
	_add_social_points(c, s.map_id)
	_collect_see_through()
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


## H7: the social points of the map (data/maps "social_points", GDD 4.11.3): a bench on each seat
## (game/visuals/props/bench.tscn) and the dice table in the middle of its places (dice_table). Chat points have
## no prop: people stand around them.
func _add_social_points(c: Catalog, map_id: String) -> void:
	for p: Dictionary in c.maps().get(map_id, {}).get("social_points", []):
		var slots: Array = p.get("slots", [])
		match str(p.get("kind", "")):
			"bench":
				for t: Array in slots:
					var b := VisualPaths.instantiate("props", "bench")
					VisualPaths.place(b, Iso.tile_to_world(Vector2i(int(t[0]), int(t[1]))))
					objects().add_child(b)
			"dice":
				var mid := Vector2.ZERO
				for t: Array in slots:
					mid += Iso.tile_to_world(Vector2i(int(t[0]), int(t[1])))
				var d := VisualPaths.instantiate("props", "dice_table")
				VisualPaths.place(d, (mid / maxf(1.0, float(slots.size()))).round())
				objects().add_child(d)


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
		var facing := _door_facing(b, scene_id)
		if str(facing["scene"]) != scene_id:
			scene_id = str(facing["scene"])
		var visual := VisualPaths.instantiate("buildings", scene_id)
		if bool(facing["flip"]):
			visual.scale.x = -1.0  # the drawn door on the side of the map's door (mirrored around its Feet)
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


## Which look of a building puts its drawn door on the side of its map door: {"scene", "flip"}. Each scene says where
## it draws its door with its Door marker (VisualPaths.door_of: SW = the face that looks to +row, SE = +col, NE and
## NW the hidden ones). Tried in order: the scene as drawn, mirrored (if its marker allows: mirroring swaps SW/SE and
## NE/NW), its back view (the marker's "back") and the back view mirrored; none fits: the scene as it is
## (tools/city/ciudad.py validar lists those).
const DOOR_SIDES: Dictionary = {"SW": Vector2i(0, 1), "SE": Vector2i(1, 0), "NE": Vector2i(0, -1), "NW": Vector2i(-1, 0)}
const MIRRORED_SIDE: Dictionary = {"SW": "SE", "SE": "SW", "NE": "NW", "NW": "NE"}


func _door_facing(b: Dictionary, scene_id: String) -> Dictionary:
	var out := {"scene": scene_id, "flip": false}
	var d: Array = b.get("door", [])
	var o: Array = b.get("origin", [0, 0])
	var f: Array = b.get("footprint", [1, 1])
	if d.size() != 2:
		return out
	var door := Vector2i(int(d[0]), int(d[1]))
	var side := ""
	for s: String in DOOR_SIDES:
		var inner: Vector2i = door - (DOOR_SIDES[s] as Vector2i)
		if inner.x >= int(o[0]) and inner.x < int(o[0]) + int(f[0]) and inner.y >= int(o[1]) and inner.y < int(o[1]) + int(f[1]):
			side = s
			break
	if side == "":
		return out
	var front := VisualPaths.door_of("buildings", scene_id)
	if front.is_empty():
		return out
	var tries: Array = [scene_id]
	if str(front["back"]) != "":
		tries.append(str(front["back"]))
	for sc: String in tries:
		var m := VisualPaths.door_of("buildings", sc)
		if m.is_empty():
			continue
		for flip: bool in [false, true]:
			if flip and not bool(m["mirror"]):
				continue
			var drawn := str(MIRRORED_SIDE[str(m["side"])]) if flip else str(m["side"])
			if drawn == side:
				out = {"scene": sc, "flip": flip}
				if flip or sc != scene_id:
					ViewConfig.info("WorldView", "building %s: door %s on %s -> %s%s" % [b.get("id", ""), door, side,
						sc, " (mirrored)" if flip else ""])
				return out
	return out


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
	if visible:
		UiFeel.set_hand(bld != "" or who != "")  # the hand over what can be clicked (docs/ui/00 §9)


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


## The map's dressing made by the town builder (data/maps "decor", tools/city/ciudad.py, docs/protocolos/
## generar-ciudad.md): filler lots (house / yard / single: a scene on the centre of its tiles, mirrored if `flip`,
## registered as the prop of each tile and taken out of `filler`) and props (lantern / prop / fence: a scene on the
## tile's centre + `off` pixels). An item with "site" belongs to a map site: its lots dress the site's footprint in a
## game without that building, its props (a workshop's barrels) only show with it. Purely visual, the same every game. A lot whose tiles are not all free filler (a
## building of this game stands there) or a prop on a building's tiles is skipped; the filler left falls back to
## _add_filler. Returns how many visuals were placed.
func _add_decor(decor: Dictionary, filler: Dictionary, owned: Dictionary) -> int:
	var items: Array = decor.get("items", [])
	if items.is_empty():
		return 0
	# the map sites with a building in this game (same origin and type: sites on one plot are alternatives, H12) and
	# the plots with any building: an item with "site" belongs to a site (its lots dress the whole plot)
	var built := {}
	var plot_built := {}
	var placed := {}
	for id: String in state.buildings:
		var o: Array = state.buildings[id].get("origin", [])
		if o.size() == 2:
			placed["%d,%d,%s" % [int(o[0]), int(o[1]), state.buildings[id].get("type", "")]] = true
			plot_built["%d,%d" % [int(o[0]), int(o[1])]] = true
	var sites: Dictionary = catalog.maps().get(state.map_id, {}).get("buildings", {})
	for sid: String in sites:
		var o: Array = sites[sid].get("origin", [])
		if o.size() == 2 and placed.has("%d,%d,%s" % [int(o[0]), int(o[1]), sites[sid].get("type", "")]):
			built[sid] = true
		if o.size() == 2 and plot_built.has("%d,%d" % [int(o[0]), int(o[1])]):
			plot_built[sid] = true
	var n := 0
	var skipped := 0
	var kinds := {}
	for it: Dictionary in items:
		var kind := str(it.get("kind", ""))
		var site := str(it.get("site", ""))
		if site != "":
			var is_lot := kind in ["house", "yard", "single"]
			# a site's lots only while its plot is empty; a site's props (by its door) only with that building
			if (is_lot and plot_built.has(site)) or (not is_lot and not built.has(site)):
				continue
		var at: Array = it.get("at", [0, 0])
		var size: Array = it.get("size", [1, 1])
		var flip := bool(it.get("flip", false))
		var id := str(it.get("id", ""))
		var tiles: Array = []
		for dr: int in int(size[1]):
			for dc: int in int(size[0]):
				tiles.append(Vector2i(int(at[0]) + dc, int(at[1]) + dr))
		if kind in ["house", "yard", "single"]:
			var ok := true
			for t: Vector2i in tiles:
				if not filler.has(t):
					ok = false
			if not ok:
				skipped += 1
				continue
			n += _place_filler(id, tiles, flip)
			for t: Vector2i in tiles:
				filler.erase(t)
		else:
			var t0: Vector2i = tiles[0]
			if owned.has(t0) and kind != "prop":
				skipped += 1
				continue
			var off: Array = it.get("off", [0, 0])
			var p := VisualPaths.instantiate("props", id)
			if flip:
				p.scale.x = -1.0  # mirrored around its Feet
			VisualPaths.place(p, Iso.tile_to_world(t0) + Vector2(float(off[0]), float(off[1])))
			objects().add_child(p)
			n += 1
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	ViewConfig.info("WorldView", "decor: %d visuals %s (skipped %d: a building of this game stands there)" % [n, kinds,
		skipped])
	return n


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


## H9: the town hall (data/maps "town_hall", game/visuals/buildings/town_hall.tscn) in the middle of its footprint;
## registered as the prop of its sign tile (the sign and the click use its height) and its tiles as owned.
func _add_town_hall(owned: Dictionary) -> void:
	for svc: Dictionary in _services:
		if str(svc["kind"]) != "town_hall":
			continue
		var centre := Vector2.ZERO
		for t: Vector2i in svc["tiles"]:
			owned[t] = true
			centre += Iso.tile_to_world(t)
		centre /= maxf(1.0, float((svc["tiles"] as Array).size()))
		var v := VisualPaths.instantiate("buildings", "town_hall")
		v.name = "town_hall_visual"
		VisualPaths.place(v, centre)
		objects().add_child(v)
		_props[svc["tile"]] = v
		ViewConfig.info("WorldView", "town hall at %s (%d tiles, sign %s, service %s)" % [centre, (svc["tiles"] as Array).size(),
			svc["tile"], svc["service"]])


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
		var text := SimQuery.stall_name(catalog, id) if kind == "stall" else SimQuery.t_("ui.%s.sign" % kind)
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
		if svc["tile"] == tile or (svc.get("tiles", []) as Array).has(tile):
			return svc
	var th := _town_hall_svc()  # H9: anywhere on the drawn town hall
	if not th.is_empty():
		var v: Node2D = _props.get(th["tile"], null)
		var spr := v.get_node_or_null("Sprite") as Sprite2D if v != null else null
		if spr != null and spr.visible and spr.texture != null:
			var local := spr.to_local(world)
			if Rect2(spr.offset, spr.texture.get_size()).has_point(local):
				return th
	return {}


func _town_hall_svc() -> Dictionary:
	for svc: Dictionary in _services:
		if str(svc["kind"]) == "town_hall":
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
	if catalog != null:  # the fields change with the season (data/view.json "seasonal_tiles"; a no-op if unchanged)
		ground().set_season(Clock.season(int(state.clock.get("minute", 0)), catalog.time))
	_talker = _pick_talker()
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
		v.visible = str(ch.get("location", "")) == "" and not Tribunal.is_banished(state, id)  # H11: banished: away
		v.follow(ch, _minutes_per_tile, frac)
		v.follow_badge(state, _player_family)
		_follow_town(id, v)
	spread_bubbles()
	if int(state.clock["minute"]) != _idle_minute:
		_idle_minute = int(state.clock["minute"])
		refresh_idle()
		refresh_upgrades()
	tint_color = DayNight.tint(int(state.clock["minute"]), frac, catalog.time, ViewConfig.value("day_night", {}))
	(get_node("%Tint") as CanvasModulate).color = tint_color
	_update_see_through()


## Scale B (docs/arte/escala.md): the tall visuals that may hide a person behind them: the buildings of the state,
## the town hall and the filler houses (a Sprite and a Top marker at least see_through.min_height high).
func _collect_see_through() -> void:
	_see_through.clear()
	var min_h := float((ViewConfig.value("see_through", {}) as Dictionary).get("min_height", 60.0))
	var seen := {}
	var cands: Array = _building_visuals.values() + _props.values()
	for n: Node2D in cands:
		if n == null or seen.has(n) or n.get_node_or_null("Sprite") == null:
			continue
		seen[n] = true
		if VisualPaths.top_height(n, 0.0) >= min_h:
			_see_through.append(n)
	ViewConfig.info("WorldView", "see-through: %d tall visuals" % _see_through.size())


## A tall visual goes see-through (data/view.json see_through.alpha) while the selected person stands behind it and
## its drawn pixels cover the person (feet, chest or head); back to opaque when not.
func _update_see_through() -> void:
	var who: CharacterView = _views.get(selected_id, null)
	var alpha := float((ViewConfig.value("see_through", {}) as Dictionary).get("alpha", 0.45))
	for n: Node2D in _see_through:
		var a := alpha if who != null and who.visible and _hides(n, who) else 1.0
		if not is_equal_approx(n.modulate.a, a):
			n.modulate.a = a
			ViewConfig.info("WorldView", "see-through %s %s (person=%s)" % [n.name, "on" if a < 1.0 else "off", selected_id])


## Whether `n` (a visual with a Sprite) is drawn over `who`: the person is behind it (smaller y in the y-sort) and
## one of three points of the figure falls on an opaque pixel of the sprite.
func _hides(n: Node2D, who: Node2D) -> bool:
	if who.global_position.y >= n.global_position.y:
		return false
	var spr := n.get_node("Sprite") as Sprite2D
	if not spr.visible or spr.texture == null:
		return false
	for dy: float in [-4.0, -20.0, -36.0]:
		if spr.is_pixel_opaque(spr.to_local(who.global_position + Vector2(0.0, dy))):
			return true
	return false


## Bubbles over heads that stand close (the dice table, a chat) would land on the figure behind or on each other:
## each bubble, front ones first, takes the first sideways shift (0, then ±BUBBLE_SHIFT, ±2×...) whose box covers
## neither another visible figure nor a bubble already placed. Only the bubble moves; the person stays.
const BUBBLE_SIZE: Vector2 = Vector2(26, 22)
const BUBBLE_SHIFT: float = 16.0


func spread_bubbles() -> void:
	var shown: Array = []
	for id: String in _views:
		var v: CharacterView = _views[id]
		if v.visible and v.bubble_id != "":
			shown.append(v)
	if shown.is_empty():
		return
	shown.sort_custom(func(a: CharacterView, b: CharacterView) -> bool:
		return a.position.y > b.position.y or (a.position.y == b.position.y and str(a.name) < str(b.name)))
	var bodies: Array = []
	for id: String in _views:
		var w: CharacterView = _views[id]
		if w.visible:
			bodies.append([w, w.pick_rect()])
	var placed: Array[Rect2] = []
	for v: CharacterView in shown:
		var best: Array = []      # [dx, box] clear of bubbles and figures
		var fallback: Array = []  # [dx, box] clear of bubbles only
		for k: int in [0, -1, 1, -2, 2, -3, 3]:
			var dx := float(k) * BUBBLE_SHIFT
			var box := Rect2(v.position + Vector2(dx - BUBBLE_SIZE.x / 2.0, -v.fig_height - 12.0 - BUBBLE_SIZE.y),
				BUBBLE_SIZE)
			var free_of_bubbles := true
			for p: Rect2 in placed:
				if p.intersects(box):
					free_of_bubbles = false
					break
			if not free_of_bubbles:
				continue
			if fallback.is_empty():
				fallback = [dx, box]
			var free_of_bodies := true
			for b: Array in bodies:
				if b[0] != v and (b[1] as Rect2).intersects(box.grow(-2.0)):
					free_of_bodies = false
					break
			if free_of_bodies:
				best = [dx, box]
				break
		var pick: Array = best if not best.is_empty() else fallback
		if pick.is_empty():
			v.set_bubble_shift(0.0)
			continue
		placed.append(pick[1])
		v.set_bubble_shift(float(pick[0]))


## H7: who speaks to the selected person: the nearest townsperson whose phrase would not land on the selected
## person's name (a phrase over a head standing just in front of them covers it), else nobody.
func _pick_talker() -> String:
	if sim == null or selected_id == "" or not _views.has(selected_id):
		return ""
	var me: CharacterView = _views[selected_id]
	for id: String in SimQuery.talkers(sim, selected_id):
		var v: CharacterView = _views.get(id, null)
		if v == null:
			continue
		var phrase := Rect2(v.position + Vector2(-90, -v.fig_height - 48), Vector2(180, 18))
		var name_box := Rect2(me.position + Vector2(-64, -me.fig_height - 22), Vector2(128, 18))
		if not phrase.intersects(name_box):
			return id
	return ""


## H7: the bubble (emotion first, else the social activity) and the phrase of the townsperson nearest to the selected
## person (_talker, worked out once per sync).
func _follow_town(id: String, v: CharacterView) -> void:
	if sim == null or not v.visible:
		v.set_bubble("")
		v.set_phrase("")
		return
	v.set_bubble(SimQuery.bubble_of(sim, id))
	var emos := Emotions.list(sim, id)  # ciudad_viva §6: the outline in the colour of the family it is felt towards
	if emos.is_empty():
		v.set_bubble_mark(Color(0, 0, 0, 0), 0.0)
	else:
		var src: Dictionary = sim.state.families.get(str(emos[0]["source"]), {})
		v.set_bubble_mark(ViewConfig.color(str(src.get("colors", {}).get("primary", "#808080"))),
			float(emos[0]["intensity"]) / 100.0)
	v.set_phrase(SimQuery.town_phrase(sim, id, selected_id) if id == _talker else "")


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
## right moves the selected person, or sends them into the building clicked (pulido-mvp: a walkable street tile under
## the pointer is a walk behind a see-through building or with Shift held, command_target_building). True if used.
func handle_input(event: InputEvent) -> bool:
	if state == null or not event is InputEventMouseButton or not event.is_pressed():
		return false
	var mb := event as InputEventMouseButton
	if event.is_action_pressed("select"):
		var who := pick_character(mb.position)
		if who != "":
			select(who)
			return true
		var npc := pick_any_character(mb.position)  # H7: somebody else: their sheet (actions on an NPC)
		if npc != "":
			ViewConfig.info("WorldView", "npc picked %s" % npc)
			npc_picked.emit(npc)
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
		if mb.shift_pressed and ground_walk(mb.position):  # pulido-mvp: Shift = the ground tile, whatever covers it
			command_move(screen_to_tile(mb.position))
			return true
		var svc := pick_service(mb.position)
		if not svc.is_empty():
			command_service(svc)
			return true
		var bld := command_target_building(mb.position, mb.shift_pressed)
		if bld != "":
			command_enter(bld)
		else:
			command_move(screen_to_tile(mb.position))
		return true
	return false


## Pulido del MVP (scale B): the building a right click sends the selected person into, "" = walk to the tile. As
## before, a click on a building's drawn volume enters it; but the volume of a tall building also covers street tiles
## behind it, so the ground tile under the pointer decides (a walkable tile that is not a door nor the building's own
## tile is a walk) when Shift is held (`ground`) or when that building is see-through (the selected person is behind
## it). Every hidden street tile can be reached.
func command_target_building(screen: Vector2, ground: bool = false) -> String:
	var bld := pick_building(screen)
	if bld != "" and (ground or _is_see_through(bld)) and ground_walk(screen):
		return ""
	return bld


## Whether the ground tile under `screen` is a street tile to walk to: walkable, not a door nor a building's own tile.
func ground_walk(screen: Vector2) -> bool:
	var tile := screen_to_tile(screen)
	var grid := Grid.of(catalog, state.map_id) if catalog != null else null
	if grid == null or not grid.walkable(tile.x, tile.y):
		return false
	for id: String in state.buildings:
		var b: Dictionary = state.buildings[id]
		var d: Array = b.get("door", [])
		if d.size() == 2 and Vector2i(int(d[0]), int(d[1])) == tile:
			return false
		var o: Array = b.get("origin", [0, 0])
		var f: Array = b.get("footprint", [1, 1])
		if tile.x >= int(o[0]) and tile.y >= int(o[1]) and tile.x < int(o[0]) + int(f[0]) \
				and tile.y < int(o[1]) + int(f[1]):
			return false
	return true


## Whether building `id`'s visual is see-through now (faded while it hides the selected person).
func _is_see_through(id: String) -> bool:
	var n: Variant = _building_visuals.get(id, null)
	return n is Node2D and (n as Node2D).modulate.a < 1.0
