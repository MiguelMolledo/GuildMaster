@tool
class_name InnArtSlot
extends Sprite2D
## A sprite that shows the Taberna-Posada's art when it exists (VisualPaths.inn_art(kind, id): the art worker drops
## the png at its path and it shows without touching code) and, until then, hides itself and leaves visible the
## greybox sibling `fallback` (a StationBlock or GreyboxBlocks) with a label saying what is missing.
## base_offset: where the png's top-left goes from the node (bottom-centre on Feet, like the other sprites).

@export var kind: String = "interior"
@export var id: String = ""
@export var fallback: NodePath = ^"../Greybox"
@export var label: NodePath = ^"../Label"
## Pixels from the node down to the bottom edge of the png (the art's feet are at its bottom centre).
@export var bottom: float = 0.0
## A building's facade keeps the anchor of the fal facades (offset of the png's top-left from Feet) instead.
@export var anchored: bool = false
@export var anchor_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	refresh()


func _process(_d: float) -> void:
	var l := get_node_or_null(label) as Control if not label.is_empty() else null
	if l != null and l.visible:
		var flip := signf(get_global_transform().x.x)
		if flip != 0.0 and l.scale.x != flip:
			l.scale.x = flip   # mirrored building: un-mirror the text around its centre
			l.pivot_offset = Vector2(l.size.x / 2.0, 0)


func refresh() -> void:
	var tex := VisualPaths.inn_art(kind, id)
	texture = tex
	visible = tex != null
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = false
	if tex != null:
		offset = anchor_offset if anchored else Vector2(-tex.get_width() / 2.0, bottom - tex.get_height())
	for p: NodePath in [fallback, label]:
		if p.is_empty():
			continue
		var n := get_node_or_null(p) as CanvasItem
		if n != null:
			n.visible = tex == null
