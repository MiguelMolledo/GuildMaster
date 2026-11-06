class_name OrderBubble
extends Node2D
## The bubble over a customer inside (docs/gdd/04g_interiores.md 4.6.5.4): what it comes to buy (the icon of the
## product the counter would sell it, Counter.best_product), «…» while it waits in the queue, and its patience bar
## (green to red as patience_minutes runs out) or, once someone serves it, the gold bar of the sale. Drawn by code
## (it is dynamic); InteriorStage fills it from the state every frame.

var item: String = ""
var waiting: bool = false
var patience: float = 1.0   # 1 = just came, 0 = goes away
var served: float = -1.0    # -1 = nobody serves it yet; 0..1 = the sale under way

var _tex: Texture2D = null  # the icon drawn, kept: a texture loaded inside _draw and not held is freed before the
var _tex_item: String = ""  # frame is rendered (it drew a white square for an icon nothing else had loaded)

const PAPER: Color = Color("#d4b896")
const INK: Color = Color("#1a1209")
const GOLD: Color = Color("#c8a84e")


func _draw() -> void:
	var r := Rect2(-11, -22, 22, 20)
	draw_rect(r.grow(1.0), INK)
	draw_rect(r, PAPER)
	# the tail, pointing down at the head
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(0, 2)]), PAPER)
	draw_polyline(PackedVector2Array([Vector2(-3, -2), Vector2(0, 2), Vector2(3, -2)]), INK, 1.0)
	if _tex_item != item:
		_tex_item = item
		_tex = VisualPaths.icon_small(item) if item != "" else null
	var tex := _tex if not waiting else null
	if tex != null:
		draw_texture(tex, Vector2(-8, -20))
	else:
		for i: int in 3:  # «…»: waiting its turn (or nothing for sale it wants)
			draw_rect(Rect2(-6 + i * 5, -12, 2, 2), INK)
	var bar := Rect2(-10, -27, 20, 3)
	draw_rect(bar.grow(1.0), INK)
	if served >= 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * served, bar.size.y)), GOLD)
	else:
		var c := Color("#c85050").lerp(Color("#7ec87e"), patience)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * patience, bar.size.y)), c)
