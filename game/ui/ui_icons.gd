class_name UiIcons
extends RefCounted
## Greybox icons drawn from a few pixels until the UI art arrives (assets/art). Built once and cached.

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
