@tool
class_name GreyboxMasonry
extends Node2D
## Greybox of a stone facade (H5, forge_facade_1): rows of stones over the two front faces of a building's
## footprint, so the upgrade reads on the map without art. One MasonryFace per front edge tile (Y-sorted like the
## building's blocks, so walkers in front still cover it). Origin = the footprint's centre (the building scene's Feet).
## Edit footprint, height and colours in the Inspector; delete it when the facade's sprite arrives.

@export var footprint: Vector2i = Vector2i(3, 4):
	set(v):
		footprint = Vector2i(maxi(1, v.x), maxi(1, v.y))
		_rebuild()
## How high the stone goes up the wall (px; the building's greybox is 40).
@export var height: float = 40.0:
	set(v):
		height = v
		_rebuild()
@export var stone_color: Color = Color(0.784, 0.725, 0.596):
	set(v):
		stone_color = v
		_rebuild()
@export var mortar_color: Color = Color(0.353, 0.306, 0.251):
	set(v):
		mortar_color = v
		_rebuild()
## Height of a row of stones (px).
@export var course: float = 8.0:
	set(v):
		course = maxf(3.0, v)
		_rebuild()

var _dirty: bool = true


func _ready() -> void:
	y_sort_enabled = true
	if _dirty:
		build()


## The game's footprint (data/buildings/<type>.json).
func apply_footprint(f: Vector2i) -> void:
	footprint = f
	if _dirty:
		build()


func _rebuild() -> void:
	_dirty = true
	if is_inside_tree():
		build()


## (Re)creates one face piece per front edge tile: the left face along the last row, the right face along the last
## column (the corner tile has both).
func build() -> void:
	_dirty = false
	for n: Node in get_children():
		remove_child(n)
		n.queue_free()
	var centre := Iso.tilef_to_world(Vector2(footprint.x - 1, footprint.y - 1) / 2.0)
	for c: int in footprint.x:
		_add(Vector2i(c, footprint.y - 1), "left", c, centre)
	for r: int in footprint.y:
		_add(Vector2i(footprint.x - 1, r), "right", footprint.y - 1 - r, centre)


func _add(t: Vector2i, side: String, index: int, centre: Vector2) -> void:
	var f := MasonryFace.new()
	f.side = side
	f.index = index
	f.height = height
	f.stone_color = stone_color
	f.mortar_color = mortar_color
	f.course = course
	f.position = Iso.tile_to_world(t) - centre + Vector2(0, 1)   # just in front of the block of that tile
	add_child(f)
