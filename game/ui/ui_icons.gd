class_name UiIcons
extends RefCounted
## Greybox icons drawn from a few pixels until the UI art arrives (assets/art). Built once and cached.
## item_rect: the item's 16×16 icon for a list row (VisualPaths.icon_small), or null without art.

static var _lock: Texture2D = null


## A 9×11 padlock (GDD 4.4.1: recipes under the skill are shown with a lock).
static func lock() -> Texture2D:
	if _lock != null:
		return _lock
	var rows := [
		"..#####..",
		".#.....#.",
		".#.....#.",
		".#.....#.",
		"#########",
		"#ooooooo#",
		"#ooo#ooo#",
		"#ooo#ooo#",
		"#ooooooo#",
		"#ooooooo#",
		"#########",
	]
	var img := Image.create(9, 11, false, Image.FORMAT_RGBA8)
	for y: int in rows.size():
		for x: int in 9:
			var ch: String = rows[y][x]
			if ch == "#":
				img.set_pixel(x, y, Color(0.12, 0.09, 0.07))
			elif ch == "o":
				img.set_pixel(x, y, Color(0.85, 0.7, 0.35))
	_lock = ImageTexture.create_from_image(img)
	return _lock


## A 16×16 TextureRect with the icon of `item_id` for the start of a list row, or null when it has no icon yet.
static func item_rect(item_id: String) -> TextureRect:
	var tex := VisualPaths.icon_small(item_id)
	if tex == null:
		return null
	var r := TextureRect.new()
	r.name = "Icon"
	r.texture = tex
	r.custom_minimum_size = Vector2(16, 16)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A kit icon of the HUD (assets/art/ui/icons, from Guild Renew): 16 px for lists, buttons and bars (small = true),
## else 32 (docs/ui/00 §7). null if it is not there.
static func ui(icon: String, small: bool = true) -> Texture2D:
	var p := "res://assets/art/ui/icons/%s%s.png" % ["small/" if small else "", icon]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## A badge of the kit (assets/art/ui/marks: badge_title_<id>, badge_office_<id>, rank_<n>, seal), or null.
static func mark(id: String) -> Texture2D:
	var p := "res://assets/art/ui/marks/%s.png" % id
	return load(p) as Texture2D if ResourceLoader.exists(p) else null
