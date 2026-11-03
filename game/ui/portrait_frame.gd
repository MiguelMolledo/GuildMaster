class_name PortraitFrame
extends Control
## A portrait in the kit's frame (docs/ui/00 §2, 01 §7; GDD 4.10.5, 4.10.7, 4.10.9): 38×38, the 32×32 portrait scene of
## game/visuals/characters/portrait.tscn with the person's identity inside, a 1 px ring in the family's colour just
## inside the frame, the frame gold when active (portrait_active), wood when controllable (portrait_normal), grey when
## not (portrait_dim); the heir's crown above the top right corner, the group key (1-2-3) bottom right and, in active
## pause, the number of queued orders top left. Click: `clicked(id)`; double click: `double_clicked(id)`.

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


## Shows `chr`. flags: {active, heir, controlled, key ("" or "1".."3"), queue (orders waiting, 0 = none)}.
func show_character(state: WorldState, chr: String, flags: Dictionary = {}) -> void:
	_ensure()
	char_id = chr
	var id := Identity.of(state, chr)
	if _portrait != null:
		_portrait.set_identity(id)
	var ring := (%Ring as Panel).get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	ring.border_color = id["primary"]
	(%Ring as Panel).add_theme_stylebox_override("panel", ring)
	var frame := &"FrameNormal" if bool(flags.get("controlled", false)) else &"FrameDim"
	if bool(flags.get("active", false)):
		frame = &"FrameActive"
	(%Border as Panel).theme_type_variation = frame
	(%Crown as CanvasItem).visible = bool(flags.get("heir", false))
	(%Key as Label).text = str(flags.get("key", ""))
	(%KeyBox as CanvasItem).visible = str(flags.get("key", "")) != ""
	var q := int(flags.get("queue", 0))
	(%Queue as Label).text = str(q)
	(%QueueBox as CanvasItem).visible = q > 0
	tooltip_text = str(state.characters.get(chr, {}).get("name", ""))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).double_click:
			double_clicked.emit(char_id)
		else:
			clicked.emit(char_id)
		accept_event()
