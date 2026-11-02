@tool
class_name Portrait
extends Node2D
## Greybox portrait (GDD 4.10.7, 4.10.9): head and shoulders made of editable Polygon2D nodes (no drawing by code).
## The hair, the skin and the clothes come from the person (Identity.of): the family is told apart by the clothes and
## the children by the hair or skin of a parent. Dead: greyed out with a cross. 32×32, Feet at the bottom centre.
## Replace the Greybox node with the portrait art when it exists (it must keep the reserved key colours, 4.10.9).

@export var hair: Color = Color(0.35, 0.23, 0.13):
	set(v):
		hair = v
		_apply()
@export var skin: Color = Color(0.88, 0.71, 0.55):
	set(v):
		skin = v
		_apply()
@export var primary: Color = Color(0.55, 0.18, 0.18):
	set(v):
		primary = v
		_apply()
@export var secondary: Color = Color(0.78, 0.66, 0.31):
	set(v):
		secondary = v
		_apply()
@export var female: bool = false:
	set(v):
		female = v
		_apply()
@export var dead: bool = false:
	set(v):
		dead = v
		_apply()


func _ready() -> void:
	_apply()


## Sets everything from Identity.of(state, chr).
func set_identity(id: Dictionary) -> void:
	hair = id.get("hair", hair)
	skin = id.get("skin", skin)
	primary = id.get("primary", primary)
	secondary = id.get("secondary", secondary)
	female = bool(id.get("female", false))
	dead = bool(id.get("dead", false))


func _apply() -> void:
	var g := get_node_or_null("Greybox")
	if g == null:
		return
	_paint(g, "Body", primary)
	_paint(g, "Collar", secondary)
	_paint(g, "Head", skin)
	_paint(g, "Hair", hair)
	_paint(g, "HairLong", hair)
	var long := g.get_node_or_null("HairLong") as CanvasItem
	if long != null:
		long.visible = female
	var cross := get_node_or_null("Cross") as CanvasItem
	if cross != null:
		cross.visible = dead
	g.modulate = Color(0.55, 0.55, 0.55, 0.75) if dead else Color.WHITE


func _paint(parent: Node, node: String, c: Color) -> void:
	var p := parent.get_node_or_null(node) as Polygon2D
	if p != null:
		p.color = c
