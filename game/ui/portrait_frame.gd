class_name PortraitFrame
extends Control
## A portrait in a frame (GDD 4.10.5, 4.10.7, 4.10.9): the portrait scene of game/visuals/characters/portrait.tscn with
## the person's identity, an outer border in the family's colour, an inner ring gold (controllable) or grey (not), a
## brighter back when active, a crown for the heir and the group key (1-2-3). Click: `clicked(id)`; double click:
## `double_clicked(id)`. Only reads the state.

signal clicked(id: String)
signal double_clicked(id: String)

var char_id: String = ""
var _portrait: Portrait = null


func _ready() -> void:
	_ensure()


func _ensure() -> void:
	if _portrait != null:
		return
	var n := VisualPaths.instantiate("characters", "portrait")
	n.name = "Portrait"
	(%Holder as Node2D).add_child(n)
	_portrait = n as Portrait


## Shows `chr`. flags: {active, heir, controlled, key ("" or "1".."3")}.
func show_character(state: WorldState, chr: String, flags: Dictionary = {}) -> void:
	_ensure()
	char_id = chr
	var id := Identity.of(state, chr)
	if _portrait != null:
		_portrait.set_identity(id)
	var border := (%Border as Panel).get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	border.border_color = id["primary"]
	border.bg_color = Color(0.32, 0.27, 0.2) if bool(flags.get("active", false)) else Color(0.12, 0.09, 0.07)
	(%Border as Panel).add_theme_stylebox_override("panel", border)
	var ring := (%Ring as Panel).get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	var pal: Dictionary = ViewConfig.value("palette", {})
	var gold := ViewConfig.color(str(pal.get("border_active", "#ffd84c")))
	ring.border_color = gold if bool(flags.get("controlled", false)) else ViewConfig.color(str(pal.get("border_dead", "#6a6258")))
	var w := 2 if bool(flags.get("active", false)) else 1
	ring.border_width_left = w
	ring.border_width_right = w
	ring.border_width_top = w
	ring.border_width_bottom = w
	(%Ring as Panel).add_theme_stylebox_override("panel", ring)
	(%Crown as CanvasItem).visible = bool(flags.get("heir", false))
	(%Key as Label).text = str(flags.get("key", ""))
	(%Key as Label).visible = str(flags.get("key", "")) != ""
	tooltip_text = str(state.characters.get(chr, {}).get("name", ""))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).double_click:
			double_clicked.emit(char_id)
		else:
			clicked.emit(char_id)
		accept_event()
