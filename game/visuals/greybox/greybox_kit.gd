@tool
class_name GreyboxKit
extends Node2D
## Greybox room of an interior (GDD 4.6.4): a KitFloor per tile (child "Floor") and KitWall pieces on the two back
## edges (child "Walls"), with the door opening in the wall piece of the door tile. size and door are the room's
## layout, in tiles (only the view uses them: the sim does not know where things are inside). Edit them here.
## When the interior art arrives, replace this node with the kit sprites (or a TileMapLayer) and keep size/door.

@export var size: Vector2i = Vector2i(6, 6):
	set(v):
		size = Vector2i(maxi(1, v.x), maxi(1, v.y))
		_rebuild()
## The door tile: on the back-left wall (col 0) or the back-right wall (row 0).
@export var door: Vector2i = Vector2i(0, 0):
	set(v):
		door = v
		_rebuild()
@export var floor_color: Color = Color(0.541176, 0.462745, 0.376471):
	set(v):
		floor_color = v
		_rebuild()
@export var wall_color: Color = Color(0.352941, 0.290196, 0.235294):
	set(v):
		wall_color = v
		_rebuild()
@export var door_color: Color = Color(0.784314, 0.627451, 0.313725):
	set(v):
		door_color = v
		_rebuild()
@export var wall_height: float = 36.0:
	set(v):
		wall_height = v
		_rebuild()
@export_group("Art")
## Pixel art of the room (tools/art/dibujar_pixel.py): floor = a 64×32 diamond; walls = one 32 px segment seen from
## inside, for the back-right (ne) and back-left (nw) walls, plain and with the door. Empty = the greybox colours.
@export var floor_texture: Texture2D:
	set(v):
		floor_texture = v
		_rebuild()
@export var wall_texture_ne: Texture2D:
	set(v):
		wall_texture_ne = v
		_rebuild()
@export var wall_texture_nw: Texture2D:
	set(v):
		wall_texture_nw = v
		_rebuild()
@export var door_texture_ne: Texture2D:
	set(v):
		door_texture_ne = v
		_rebuild()
@export var door_texture_nw: Texture2D:
	set(v):
		door_texture_nw = v
		_rebuild()


func _ready() -> void:
	if _dirty:
		build()


## Builds the pieces now if they are not up to date (the view calls it before reading them).
func ensure_built() -> void:
	if _dirty:
		build()


func floor_layer() -> Node2D:
	return get_node_or_null("Floor") as Node2D


func walls() -> Node2D:
	return get_node_or_null("Walls") as Node2D


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
	var fl := Node2D.new()
	fl.name = "Floor"
	add_child(fl)
	var wl := Node2D.new()
	wl.name = "Walls"
	add_child(wl)
	for r: int in size.y:
		for c: int in size.x:
			var f := KitFloor.new()
			f.color = floor_color if (c + r) % 2 == 0 else floor_color.darkened(0.06)
			f.texture = floor_texture
			f.position = Iso.tile_to_world(Vector2i(c, r))
			fl.add_child(f)
	for c: int in size.x:
		wl.add_child(_wall(Vector2i(c, 0), "ne"))
	for r: int in size.y:
		wl.add_child(_wall(Vector2i(0, r), "nw"))


func _wall(t: Vector2i, side: String) -> KitWall:
	var w := KitWall.new()
	w.side = side
	w.height = wall_height
	w.color = wall_color
	w.door_color = door_color
	w.door = t == door and ((side == "nw" and t.x == 0) or (side == "ne" and t.y == 0))
	w.position = Iso.tile_to_world(t)
	if w.door:
		w.texture = door_texture_ne if side == "ne" else door_texture_nw
	else:
		w.texture = wall_texture_ne if side == "ne" else wall_texture_nw
	if w.door:
		w.name = "Door"
	return w
