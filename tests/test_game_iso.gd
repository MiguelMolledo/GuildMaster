extends "res://tests/test_case.gd"
## The one isometric projection (GDD 05 §5.10).

func test_iso_projection_round_trip() -> void:
	for t: Vector2i in [Vector2i(0, 0), Vector2i(3, 5), Vector2i(-4, 7), Vector2i(40, 40)]:
		eq(Iso.world_to_tile(Iso.tile_to_world(t)), t, "tile %s" % t)
	eq(Iso.tile_to_world(Vector2i(1, 0)), Vector2(32, 16), "one column = half a diamond right and down")
