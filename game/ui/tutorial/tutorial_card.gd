class_name TutorialCard
extends MarginContainer
## The tutorial's card (docs/ui/05_tutorial.md §5): the page kit's short notice (PageCard, template "notice", 236 wide)
## with the chapter on its ribbon («Producir»), the step count in the card, the text as its paragraph and the buttons in
## its foot. What the notice has no block for goes into the page's column with the tutorial's own variations: the lead
## line (what opens the target, TutorialTitle) above the text and the keys line (TutorialStep) under it. The overlay
## places this node; the page inside never centres itself (build, not show_page) and never closes on a click (sticky).
## show_card(data) takes {step, count, lead, body, foot, buttons: [{id, text, primary}]}: `step` goes on the ribbon (one
## line), `count` («Paso 3 de 12») in small at the top of the card, right; a button emits button_pressed(id). Reads
## nothing and gives no orders.

signal button_pressed(id: String)

var data: Dictionary = {}
var _sig: String = ""

@onready var page: PageCard = %Page


func _ready() -> void:
	_bind()


func _bind() -> void:
	if page == null:
		page = get_node("%Page") as PageCard
	if not page.button_pressed.is_connected(_on_page_button):
		page.button_pressed.connect(_on_page_button)
		page.closed.connect(func() -> void: _sig = "")   # a button closes the page: build it again next time


func _on_page_button(id: String) -> void:
	button_pressed.emit(id)


## The same data twice does nothing (the overlay calls it every frame).
func show_card(d: Dictionary) -> void:
	_bind()
	var sig := JSON.stringify(d)
	visible = true
	if sig == _sig and page.visible:
		return
	_sig = sig
	data = d.duplicate(true)
	var blocks: Array = []
	if str(d.get("body", "")) != "":
		blocks.append({"type": "paragraph", "text": str(d["body"])})
	page.build({"template": "notice", "ribbon": str(d.get("step", "")), "blocks": blocks, "buttons": d.get("buttons", []),
		"sticky": true})
	add_theme_constant_override("margin_top", page.ribbon_overhang)   # the ribbon rises above the page: room for it
	var column := page.get_node("%Column") as VBoxContainer
	if str(d.get("lead", "")) != "":
		var lead := _line(str(d["lead"]), &"TutorialTitle", "Lead")
		column.add_child(lead)
		# under the title: the ribbon is on the page's edge (column top), or the title in ink heads the column
		var under := 1 if column.get_child_count() > 1 and column.get_child(0).name == &"Ribbon" else 0
		column.move_child(lead, mini(under, column.get_child_count() - 1))
	if str(d.get("count", "")) != "":
		var count := _line(str(d["count"]), &"TutorialStep", "Count")
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		column.add_child(count)
		var top := 1 if column.get_child_count() > 1 and column.get_child(0).name == &"Ribbon" else 0
		column.move_child(count, mini(top, column.get_child_count() - 1))   # above the lead and the text
	if str(d.get("foot", "")) != "":
		var foot := _line(str(d["foot"]), &"TutorialStep", "Keys")
		column.add_child(foot)
		var f := column.get_node_or_null("Footer")
		if f != null:
			column.move_child(foot, f.get_index())   # over the buttons
	page.visible = true
	page.layout_now()
	reset_size()
	if OS.is_debug_build():
		print("[TutorialCard] %s · %s (buttons=%d, parts=%s)" % [str(d.get("step", "")), str(d.get("body", "")).left(48),
			(d.get("buttons", []) as Array).size(), page.parts])


func _line(text: String, variation: StringName, node_name: String) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(page.column_width, 0)
	return l


func close() -> void:
	visible = false
	_sig = ""
	if page != null:
		page.visible = false


## The button `id` (tests, the smoke scripts), or null.
func button(id: String) -> Button:
	_bind()
	return page.find_child("Button_" + id, true, false) as Button


## Presses button `id` as a click would. True if it was there.
func press(id: String) -> bool:
	var b := button(id)
	if b == null:
		return false
	b.pressed.emit()
	return true
