class_name Iso
extends RefCounted
## The one isometric projection (GDD 05 §5.10): 2:1 diamonds of 64×32. Tile (col, row) -> pixel at the diamond's
## centre, and the inverse for the mouse. The sim never knows about pixels.

const TILE_W: int = 64
const TILE_H: int = 32


static func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2((tile.x - tile.y) * TILE_W / 2.0, (tile.x + tile.y) * TILE_H / 2.0)


static func world_to_tile(p: Vector2) -> Vector2i:
	var col := p.x / TILE_W + p.y / TILE_H
	var row := p.y / TILE_H - p.x / TILE_W
	return Vector2i(roundi(col), roundi(row))
