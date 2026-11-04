class_name PortraitFrame
extends Control
## A portrait in a picture frame (docs/ui/00 §2, 01 §7; GDD 4.10.5, 4.10.7, 4.10.9): the 32×32 portrait scene of
## game/visuals/characters/portrait.tscn with the person's identity inside a carved frame like a hung painting
## (assets/art/ui/portrait_frame/, tools/art/marco_retrato.py): gilded when active, wood with a gold liner when
## controllable, dark wood when not. The family's colours on a small plaque on the frame's foot (primary over
## secondary). The heir's crown above the top right corner, the group key (1-2-3) bottom right and, in active pause, the
## number of queued orders top left. `big`: 82×82 with the portrait ×2 (64) and a wider carved frame (band 9: bead
## moulding, double liner, corner blocks with a diamond and a leaf on each bar), drawn at its own size (not the small
## one scaled). Click: `clicked(id)`; double click: `double_clicked(id)`.

signal clicked(id: String)
signal double_clicked(id: String)

const DIR: String = "res://assets/art/ui/portrait_frame/"
## side, band (the frame's width; the portrait sits inside it), corner (the carved corner and its leaves: the 9-slice
## margin, never stretched), plaque
## rect {x, y, w, h} (on the foot, over the band and the bottom of the bust), crown and key offsets.
const SIZES: Dictionary = {
	"s": {"side": 38, "band": 3, "corner": 5, "plaque": Rect2(13, 33, 12, 5), "crown": Vector2(26, -6),
		"key": Vector2(29, 28), "queue": Vector2(-1, -1)},
	"l": {"side": 82, "band": 9, "corner": 20, "plaque": Rect2(31, 72, 20, 9), "crown": Vector2(68, -8),
		"key": Vector2(71, 70), "queue": Vector2(-1, -1)},
}

@export var big: bool = false:
	set(v):
		big = v
		if is_node_ready():
			_layout()

var char_id: String = ""
var finish: String = "dark"         # gold | wood | dark (tests)
var _portrait: Portrait = null
static var _frames: Dictionary = {}  # "s_wood" -> StyleBoxTexture


func _ready() -> void:
	_ensure()
	_layout()


func _ensure() -> void:
	if _portrait != null:
		return
	var n := VisualPaths.instantiate("characters", "portrait")
	n.name = "Portrait"
	(get_node("%Holder") as Node2D).add_child(n)
	_portrait = n as Portrait


## Shows `chr`. flags: {active, heir, controlled, key ("" or "1".."3"), queue (orders waiting, 0 = none), gold (the
## gilded frame without being the active one: the celebration cards, wedding, birth, title ceremony)}.
func show_character(state: WorldState, chr: String, flags: Dictionary = {}) -> void:
	char_id = chr
	show_identity(Identity.of(state, chr), flags)
	tooltip_text = str(state.characters.get(chr, {}).get("name", ""))


## Shows an identity that is not (yet) a person of the state (the new game's proposal). flags as show_character.
func show_identity(id: Dictionary, flags: Dictionary = {}) -> void:
	_ensure()
	if _portrait != null:
		_portrait.set_identity(id)
	(get_node("%PlaqueTop") as ColorRect).color = id.get("primary", Color("#8a2e2e"))
	(get_node("%PlaqueLow") as ColorRect).color = id.get("secondary", id.get("primary", Color("#8a2e2e")))
	finish = "wood" if bool(flags.get("controlled", false)) else "dark"
	if bool(flags.get("active", false)) or bool(flags.get("gold", false)):
		finish = "gold"
	(get_node("%Crown") as CanvasItem).visible = bool(flags.get("heir", false))
	(get_node("%Key") as Label).text = str(flags.get("key", ""))
	(get_node("%KeyBox") as CanvasItem).visible = str(flags.get("key", "")) != ""
	var q := int(flags.get("queue", 0))
	(get_node("%Queue") as Label).text = str(q)
	(get_node("%QueueBox") as CanvasItem).visible = q > 0
	_layout()


## The frame of size `s` ("s" | "l") and `fin`: a 9-slice whose margins are the carved corner (never stretched); the
## straight bars between them repeat, the centre is not drawn. null if the texture is missing.
static func frame_style(s: String, fin: String) -> StyleBoxTexture:
	var key := s + "_" + fin
	if not _frames.has(key):
		var path := DIR + "frame_%s.png" % key
		var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
		var sb: StyleBoxTexture = null
		if tex != null:
			sb = StyleBoxTexture.new()
			sb.texture = tex
			var m := int(SIZES[s]["corner"])
			for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				sb.set_texture_margin(side, m)
				sb.set_content_margin(side, int(SIZES[s]["band"]))
			sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
			sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
			sb.draw_center = false
		_frames[key] = sb
	return _frames[key]


func _layout() -> void:
	var s := "l" if big else "s"
	var z: Dictionary = SIZES[s]
	var side := float(z["side"])
	var band := float(z["band"])
	custom_minimum_size = Vector2(side, side)
	size = custom_minimum_size
	var back := get_node("%Back") as ColorRect
	back.position = Vector2(band, band)
	back.size = Vector2(side - 2 * band, side - 2 * band)
	var holder := get_node("%Holder") as Node2D
	holder.position = Vector2(band, band)
	holder.scale = Vector2(2, 2) if big else Vector2.ONE
	var border := get_node("%Border") as Panel
	var sb := frame_style(s, finish)
	if sb != null:
		border.add_theme_stylebox_override("panel", sb)
	else:  # no art: the theme's frames of before
		border.remove_theme_stylebox_override("panel")
		border.theme_type_variation = {"gold": &"FrameActive", "wood": &"FrameNormal"}.get(finish, &"FrameDim")
	var pr: Rect2 = z["plaque"]
	var plaque := get_node("%Plaque") as Panel
	plaque.position = pr.position
	plaque.size = pr.size
	var top := get_node("%PlaqueTop") as ColorRect
	var low := get_node("%PlaqueLow") as ColorRect
	var inner := Rect2(Vector2.ONE, pr.size - Vector2(2, 2))
	var low_h := roundf(inner.size.y / 3.0)
	top.position = inner.position
	top.size = Vector2(inner.size.x, inner.size.y - low_h)
	low.position = Vector2(inner.position.x, inner.end.y - low_h)
	low.size = Vector2(inner.size.x, low_h)
	(get_node("%Crown") as Control).position = z["crown"]
	(get_node("%KeyBox") as Control).position = z["key"]
	(get_node("%QueueBox") as Control).position = z["queue"]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).double_click:
			double_clicked.emit(char_id)
		else:
			clicked.emit(char_id)
		accept_event()
