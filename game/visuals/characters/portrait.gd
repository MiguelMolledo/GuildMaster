@tool
class_name Portrait
extends Node2D
## Greybox portrait (GDD 4.10.7, 4.10.9): head and shoulders made of editable Polygon2D nodes (no drawing by code).
## The hair, the skin and the clothes come from the person (Identity.of): the family is told apart by the clothes and
## the children by the hair or skin of a parent. Dead: greyed out with a cross. 32×32, Feet at the bottom centre.
## Población: with a base portrait (art, Identity.portrait_texture) the Art sprite shows it through the identity shader
## and the greybox keeps only its back.

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
## Población: the base portrait (assets/art/portraits, keyed colours of 4.10.9 painted by the identity shader on the
## Art node); null = the greybox.
@export var art: Texture2D = null:
	set(v):
		art = v
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
	art = Identity.portrait_texture(id, 32)


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
	var sprite := get_node_or_null("Art") as Sprite2D
	if sprite != null:
		sprite.texture = art
		sprite.visible = art != null
		sprite.modulate = g.modulate
		var mat := sprite.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("hair", hair)
			mat.set_shader_parameter("skin", skin)
			mat.set_shader_parameter("primary", primary)
			mat.set_shader_parameter("secondary", secondary)
	for n: Node in g.get_children():  # with art only the dark back of the greybox stays (the art has no background)
		if n is CanvasItem and n.name != "Back":
			(n as CanvasItem).visible = art == null and (n.name != "HairLong" or female)


func _paint(parent: Node, node: String, c: Color) -> void:
	var p := parent.get_node_or_null(node) as Polygon2D
	if p != null:
		p.color = c
