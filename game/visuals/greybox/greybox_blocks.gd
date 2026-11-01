@tool
class_name GreyboxBlocks
extends Node2D
## Greybox of a building seen from outside (H2): one BlockView per footprint tile, centred on the footprint (the
## building scene's Feet). Needs Y-sort on (each block sorts with the walkers by its own tile). The footprint here is
## the editor preview: in the game the view applies the building's footprint from data/ (a rule of the sim).
## Delete this node when the building's sprite arrives.

@export var footprint: Vector2i = Vector2i(3, 4):
	set(v):
		footprint = Vector2i(maxi(1, v.x), maxi(1, v.y))
		_rebuild()
@export var height: float = 40.0:
	set(v):
		height = v
		_rebuild()
@export var color: Color = Color(0.5, 0.5, 0.5):
	set(v):
		color = v
		_rebuild()


func _ready() -> void:
	y_sort_enabled = true
	if _dirty:
		build()


## The game's footprint (data/buildings/<type>.json), which may differ from the preview.
func apply_footprint(f: Vector2i) -> void:
	footprint = f
	if _dirty:
		build()


## The blocks, in world pixels from the footprint's centre.
func block_offsets() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var centre := Iso.tilef_to_world(Vector2(footprint.x - 1, footprint.y - 1) / 2.0)
	for dr: int in footprint.y:
		for dc: int in footprint.x:
			out.append(Iso.tile_to_world(Vector2i(dc, dr)) - centre)
	return out


var _dirty: bool = true


## Live edits in the editor rebuild at once; otherwise build() runs on _ready (or when the view calls it).
func _rebuild() -> void:
	_dirty = true
	if is_inside_tree():
		build()


## (Re)creates the pieces from the exported values. Works outside the tree too (the views' tests).
func build() -> void:
	_dirty = false
	for n: Node in get_children():
		remove_child(n)
		n.queue_free()
	for p: Vector2 in block_offsets():
		var b := BlockView.new()
		b.height = height
		b.color = color
		b.position = p
		add_child(b)
