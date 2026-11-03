class_name ConfirmDialog
extends MenuScreen
## A confirmation over the screens (docs/ui/00_lenguaje_visual.md §5 "Peligro", 02 §3 overwrite, §6 quit): the
## question as the title, what is lost, an optional warning ("No se puede deshacer") and its buttons, Cancel (Esc)
## on the left and the action (Enter, focused) on the right. ask() opens it; the answer comes as chosen(id), Esc is
## "cancel".

signal chosen(id: String)

var _primary: Button = null


func _ready() -> void:
	back_requested.connect(func() -> void: _choose("cancel"))


## buttons: [{id, text, hint?, primary?}], left to right. The primary one (else the last) has the focus.
func ask(title: String, body: String, buttons: Array, warn: String = "") -> void:
	(%Title as Label).text = title
	(%Body as Label).text = body
	(%Body as Label).visible = body != ""
	(%Warn as Label).text = warn
	(%Warn as Label).visible = warn != ""
	var box := %Buttons as HBoxContainer
	MenuKit.clear(box)
	_primary = null
	for b: Dictionary in buttons:
		var id := str(b.get("id", ""))
		var btn := MenuKit.button(str(b.get("text", id)), str(b.get("hint", "")))
		btn.name = id.to_pascal_case()
		btn.custom_minimum_size = Vector2(104, 20)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void: _choose(id))
		box.add_child(btn)
		if bool(b.get("primary", false)):
			_primary = btn
	if _primary == null and box.get_child_count() > 0:
		_primary = box.get_child(box.get_child_count() - 1) as Button
	ViewConfig.info("Confirm", "ask (title=%s, buttons=%d)" % [title, buttons.size()])
	open()


func default_focus() -> Control:
	return _primary


func button(id: String) -> Button:
	return (%Buttons as HBoxContainer).get_node_or_null(id.to_pascal_case()) as Button


func _choose(id: String) -> void:
	if not visible:
		return
	ViewConfig.info("Confirm", "chosen %s" % id)
	close()
	chosen.emit(id)
