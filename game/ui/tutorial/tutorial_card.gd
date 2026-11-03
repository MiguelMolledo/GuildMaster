class_name TutorialCard
extends PanelContainer
## The tutorial's card (docs/ui/05_tutorial.md §5): parchment 236 wide with the step line («Producir · 3/12»), an
## optional lead line (what opens the target, in the title ink), the text, a small foot and the buttons.
## show_card(data) takes the same kind of dictionary as PageCard.show_page of the page kit (title, blocks → here
## step / lead / body / foot, buttons [{id, text, primary}]), so the card can become PageCard's "notice" template
## when the kit is in main. A button emits button_pressed(id). Reads nothing and gives no orders.

signal button_pressed(id: String)

var data: Dictionary = {}
var _sig: String = ""

@onready var _step: Label = %Step
@onready var _lead: Label = %Lead
@onready var _body: Label = %Body
@onready var _foot: Label = %Foot
@onready var _buttons: HBoxContainer = %Buttons


func _bind() -> void:
	if _step == null:
		_step = get_node("%Step") as Label
		_lead = get_node("%Lead") as Label
		_body = get_node("%Body") as Label
		_foot = get_node("%Foot") as Label
		_buttons = get_node("%Buttons") as HBoxContainer


## {step, lead, body, foot, buttons: [{id, text, primary}]}. The same data twice does nothing (it is called every
## frame by the overlay).
func show_card(d: Dictionary) -> void:
	_bind()
	var sig := JSON.stringify(d)
	visible = true
	if sig == _sig:
		return
	_sig = sig
	data = d.duplicate(true)
	for pair: Array in [[_step, "step"], [_lead, "lead"], [_body, "body"], [_foot, "foot"]]:
		var l := pair[0] as Label
		l.text = str(d.get(pair[1], ""))
		l.visible = l.text != ""
	for c: Node in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	for b: Dictionary in d.get("buttons", []):
		var btn := Button.new()
		btn.name = "Btn_" + str(b.get("id", ""))
		btn.text = str(b.get("text", ""))
		btn.focus_mode = Control.FOCUS_NONE
		if bool(b.get("primary", false)):
			btn.theme_type_variation = &"PrimaryButton"
		var id := str(b.get("id", ""))
		btn.pressed.connect(func() -> void: button_pressed.emit(id))
		_buttons.add_child(btn)
	_buttons.visible = _buttons.get_child_count() > 0
	reset_size()
	if OS.is_debug_build():
		print("[TutorialCard] %s · %s (buttons=%d)" % [str(d.get("step", "")), str(d.get("body", "")).left(48),
			_buttons.get_child_count()])


func close() -> void:
	visible = false
	_sig = ""


## The button `id` (tests, the smoke scripts), or null.
func button(id: String) -> Button:
	_bind()
	return _buttons.get_node_or_null("Btn_" + id) as Button


## Presses button `id` as a click would. True if it was there.
func press(id: String) -> bool:
	var b := button(id)
	if b == null:
		return false
	b.pressed.emit()
	return true
