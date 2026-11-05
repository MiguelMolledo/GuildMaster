extends Node2D
## Gallery of every visual scene of game/visuals/ at real size on the tile grid, each one with a 48 px walker
## (characters/artisan_m) beside it for scale: the first check after changing art, before launching the game.
## Open game/tools/gallery.tscn and press F6, or run the game with `-- --gallery`. Controls: WASD/arrows or the
## middle button pan, the wheel zooms (×1/×2). With --smoke it saves one shot per screen, top to bottom
## (reports/shots/gallery_01.png, _02...), and quits.
## Rows: buildings and props, stations, characters and bubbles (H7), interiors. The grid is the town's 64×32 diamonds; each
## visual stands on a tile centre by its Feet marker, so a sprite whose base misses the diamond is misplaced.

const ROWS: Array = [["buildings", "props"], ["stations", "characters", "bubbles"], ["interiors"]]
const ROW_GAP: float = 70.0
const GRID_TILES: int = 40
const MAX_W: float = 900.0     # a line of the gallery wraps past this width (one screen at ×1)
const SCREEN: Vector2 = Vector2(960, 540)

var items: Array = []        # [{kind, id, node}]
var _shot_in: float = -1.0
var _shot_n: int = 0
var _bounds: Rect2 = Rect2()


func _ready() -> void:
	(get_node("%Grid") as Node2D).draw.connect(_draw_grid)
	_build()
	_frame(0)
	for a: String in OS.get_cmdline_user_args():
		if a == "--smoke":
			_shot_in = 0.6
	if OS.is_debug_build():
		print("[Gallery] %d visuals (bounds=%s)" % [items.size(), _bounds])


## Every scene of a kind folder, sorted, the generic one last.
static func scenes_of(kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open("%s/%s" % [VisualPaths.ROOT, kind])
	if dir == null:
		return out
	for f: String in dir.get_files():
		f = f.trim_suffix(".remap")
		if f.ends_with(".tscn") and not out.has(f.get_basename()):
			out.append(f.get_basename())
	if kind == "interiors":  # 04g 4.6.5.2: the interiors built from data/interiors/<type>.json
		for f: String in DirAccess.get_files_at(InteriorDefs.DIR):
			if f.ends_with(".json") and not f.begins_with("_") and f != "lights.json" and not out.has(f.get_basename()):
				out.append(f.get_basename())
	out.sort()
	if out.has(VisualPaths.GENERIC):
		out.remove_at(out.find(VisualPaths.GENERIC))
		out.append(VisualPaths.GENERIC)
	return out


## The camera on screen `n` of the gallery (top to bottom). False past the last one.
func _frame(n: int) -> bool:
	var top := _bounds.position.y - 16.0 + n * (SCREEN.y - 40.0)
	if n > 0 and top > _bounds.end.y - 40.0:
		return false
	(get_node("%Camera") as Camera2D).position = Vector2(_bounds.position.x - 16.0, top) + SCREEN / 2.0
	return true


func _build() -> void:
	var y := 0.0
	var first := true
	for row: Array in ROWS:
		var x := 0.0
		var row_h := 0.0
		for kind: String in row:
			for id: String in scenes_of(kind):
				var node := InteriorBuilder.instantiate(id) if kind == "interiors" else VisualPaths.instantiate(kind, id)
				var slot := _slot(kind, node)   # [size, where the Feet go inside it]
				var size: Vector2 = slot[0]
				if x > 0.0 and x + size.x > MAX_W:
					x = 0.0
					y += row_h + ROW_GAP
					row_h = 0.0
				var anchor := _snap(Vector2(x, y) + (slot[1] as Vector2))
				VisualPaths.place(node, anchor)
				(get_node("%Items") as Node2D).add_child(node)
				items.append({"kind": kind, "id": id, "node": node})
				if kind != "characters":
					var ref := VisualPaths.instantiate("characters", "artisan_m")
					VisualPaths.place(ref, _snap(Vector2(x + size.x + 16.0, y + size.y - 8.0)))
					(get_node("%Items") as Node2D).add_child(ref)
					size.x += 40.0
				_label("%s/%s" % [kind, id], Vector2(x, y + size.y + 2.0), size.x)
				var r := Rect2(Vector2(x, y), size + Vector2(0, 16))
				_bounds = r if first else _bounds.merge(r)
				first = false
				x += size.x + 24.0
				row_h = maxf(row_h, size.y + 16.0)
		y += row_h + ROW_GAP


## The room a visual needs: [size, where its Feet go from the slot's top-left corner].
func _slot(kind: String, node: Node) -> Array:
	var h := VisualPaths.top_height(node, 48.0)
	match kind:
		"buildings":
			var gb := node.get_node_or_null("Greybox")
			var f: Vector2i = gb.get("footprint") if gb != null and gb.get("footprint") != null else Vector2i(3, 3)
			var half := (f.x + f.y) * Iso.TILE_H / 4.0   # half the footprint's diamond height
			return [Vector2((f.x + f.y) * Iso.TILE_W / 2.0, h + half * 2.0), Vector2((f.x + f.y) * Iso.TILE_W / 4.0, h + half)]
		"interiors":
			var k := node.get_node_or_null("Kit")
			var s: Vector2i = k.get("size") if k != null and k.get("size") != null else Vector2i(6, 6)
			var wall := float(k.get("wall_height")) if k != null else 36.0
			return [Vector2((s.x + s.y) * Iso.TILE_W / 2.0, wall + (s.x + s.y) * Iso.TILE_H / 2.0),
				Vector2(s.y * Iso.TILE_W / 2.0, wall + Iso.TILE_H / 2.0)]
		"characters":
			return [Vector2(110, h + 8.0), Vector2(55, h + 4.0)]
	return [Vector2(Iso.TILE_W, h + Iso.TILE_H), Vector2(Iso.TILE_W / 2.0, h + Iso.TILE_H / 2.0)]


func _snap(p: Vector2) -> Vector2:
	return Iso.tile_to_world(Iso.world_to_tile(p))


func _label(text: String, at: Vector2, width: float) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.05))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(maxf(width, 60.0), 12)
	l.position = at
	(get_node("%Labels") as Node2D).add_child(l)


func _draw_grid() -> void:
	var g := get_node("%Grid") as Node2D
	var hw := Iso.TILE_W / 2.0
	var hh := Iso.TILE_H / 2.0
	var a := Iso.world_to_tile(_bounds.position) - Vector2i(GRID_TILES / 4, GRID_TILES / 4)
	for r: int in range(-GRID_TILES, GRID_TILES * 2):
		for c: int in range(-GRID_TILES, GRID_TILES * 2):
			var p := Iso.tile_to_world(a + Vector2i(c, r))
			if not _bounds.grow(160.0).has_point(p):
				continue
			var col := Color(0.36, 0.30, 0.24) if (c + r) % 2 == 0 else Color(0.33, 0.27, 0.22)
			g.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -hh), p + Vector2(hw, 0), p + Vector2(0, hh),
				p + Vector2(-hw, 0)]), col)


func _process(delta: float) -> void:
	var cam := get_node("%Camera") as Camera2D
	var dir := Vector2(Input.get_axis("cam_left", "cam_right"), Input.get_axis("cam_up", "cam_down"))
	cam.position += dir * 480.0 * delta / cam.zoom.x
	if _shot_in > 0.0:
		_shot_in -= delta
		if _shot_in <= 0.0:
			_shot_n += 1
			_save_shot("gallery_%02d" % _shot_n)
			if _frame(_shot_n):
				_shot_in = 0.4
			else:
				get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var cam := get_node("%Camera") as Camera2D
	if event.is_action_pressed("cam_zoom_in"):
		cam.zoom = Vector2.ONE * 2.0
	elif event.is_action_pressed("cam_zoom_out"):
		cam.zoom = Vector2.ONE
	elif event is InputEventMouseMotion and Input.is_action_pressed("cam_drag"):
		cam.position -= (event as InputEventMouseMotion).relative / cam.zoom.x


## What the window shows, to reports/shots/<shot_name>.png (scaled by the window's whole factor, like the game's).
func _save_shot(shot_name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://reports/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	var vp := img.get_size()
	var k := maxi(1, mini(get_window().size.x / vp.x, get_window().size.y / vp.y))
	if k > 1:
		img.resize(vp.x * k, vp.y * k, Image.INTERPOLATE_NEAREST)
	img.save_png(dir.path_join(shot_name + ".png"))
	print("[Smoke] shot %s (x%d)" % [dir.path_join(shot_name + ".png"), k])
