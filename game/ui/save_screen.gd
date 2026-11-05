class_name SaveScreen
extends MenuScreen
## Load and save in one screen (docs/ui/02_menu_inicial.md §3), with a mode. One 80 px row per slot: the thumbnail,
## the slot's name, who and when in the game, how it goes, and when it was saved in real life (SaveSlots).
## Load: the autosave and the three slots, Load / Delete per row (the autosave is never deleted; deleting asks first).
## A broken file says why in red and leaves Delete. Save (from the pause menu): the three slots with "Save here"; a
## slot with a game asks before overwriting it. The app does the loading and saving (load_requested / save_requested).

signal load_requested(slot: String)
signal save_requested(slot: String)

const ROW_HEIGHT: int = 80

var mode: String = "load"            # "load" | "save"
var time_config: Dictionary = {}     # the catalog's calendar
var now_unix: int = 0                # "today" for the dates (0 = the system's clock)
var _rows: Dictionary = {}           # slot -> row PanelContainer
var _bound: bool = false


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%BackButton as Button).pressed.connect(func() -> void: back_requested.emit())
	(%CloseButton as Button).pressed.connect(func() -> void: back_requested.emit())
	(%Confirm as ConfirmDialog).chosen.connect(_on_confirm)


## Opens the screen in `m` ("load" or "save").
func open_mode(m: String) -> void:
	mode = m
	open()


func _refresh() -> void:
	_bind()
	(%Title as Label).text = SimQuery.t_("ui.saves.load_title" if mode == "load" else "ui.saves.save_title")
	(%Note as Label).text = SimQuery.t_("ui.saves.auto_note") if mode == "load" else ""
	(%BackButton as Button).text = SimQuery.t_("ui.menu.back")
	MenuKit.add_hint(%BackButton as Button, SimQuery.t_("ui.key.esc"))
	var list := %Rows as VBoxContainer
	MenuKit.clear(list)
	_rows.clear()
	var now := now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())
	for e: Dictionary in SaveSlots.list(mode == "load"):
		var row := _row(e, now)
		list.add_child(row)
		_rows[str(e["slot"])] = row
	ViewConfig.info("SaveScreen", "refresh (mode=%s, rows=%d)" % [mode, _rows.size()])


func row(slot: String) -> PanelContainer:
	return _rows.get(slot) as PanelContainer


func _slot_name(slot: String) -> String:
	if slot == SaveSlots.AUTOSAVE:
		return SimQuery.t_("ui.saves.autosave")
	return SimQuery.t_("ui.saves.slot") % slot.get_slice("_", 1).to_int()


func _row(e: Dictionary, now: int) -> PanelContainer:
	var slot := str(e["slot"])
	var p := PanelContainer.new()
	p.name = "Row_" + slot
	p.theme_type_variation = &"RowPanel"
	p.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	# thumbnail
	var thumb := Panel.new()
	thumb.name = "Thumb"
	thumb.theme_type_variation = &"ThumbPanel"
	thumb.custom_minimum_size = Vector2(SaveSlots.THUMB_SIZE)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(thumb)
	var tex := SaveSlots.thumbnail(slot) if bool(e["ok"]) else null
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 1)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.add_child(tr)
	else:
		var mark := MenuKit.label("?" if bool(e["exists"]) else "—", &"DimLabel")
		mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		thumb.add_child(mark)
	# texts
	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	h.add_child(info)
	info.add_child(MenuKit.label(_slot_name(slot), &"SectionTitle"))
	if bool(e["ok"]):
		var hd: Dictionary = e["header"]
		var who := MenuKit.label(MenuKit.who_label(hd, time_config), &"BodyLabel")
		who.name = "Who"
		info.add_child(who)
		var how := MenuKit.label(MenuKit.how_label(hd), &"DimLabel")
		how.name = "How"
		info.add_child(how)
	elif bool(e["exists"]):
		var why := MenuKit.label(MenuKit.broken_label(str(e["error"])), &"ReasonLabel")
		why.name = "Broken"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size = Vector2(260, 0)
		info.add_child(why)
	else:
		var empty := MenuKit.label(SimQuery.t_("ui.saves.empty"), &"DimLabel")
		empty.name = "Empty"
		info.add_child(empty)
	if bool(e["exists"]):
		var when := MenuKit.label(SimQuery.t_("ui.saves.saved_at") % SaveSlots.when_label(int(e["saved_at"]), now), &"DimLabel")
		when.name = "When"
		info.add_child(when)
	# buttons
	var btns := VBoxContainer.new()
	btns.name = "Buttons"
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btns.add_theme_constant_override("separation", 8)
	h.add_child(btns)
	if mode == "load":
		var load_b := MenuKit.button(SimQuery.t_("ui.saves.load"))
		load_b.name = "Load"
		load_b.custom_minimum_size = Vector2(88, 20)
		load_b.disabled = not bool(e["ok"])
		load_b.tooltip_text = (SimQuery.t_("ui.why.slot_empty") if not bool(e["exists"]) else SimQuery.t_("ui.why.slot_broken")) \
			if load_b.disabled else ""
		load_b.pressed.connect(func() -> void: _on_load(slot))
		btns.add_child(load_b)
		var del := MenuKit.button(SimQuery.t_("ui.saves.delete"))
		del.name = "Delete"
		del.custom_minimum_size = Vector2(88, 20)
		del.disabled = slot == SaveSlots.AUTOSAVE or not bool(e["exists"])
		del.tooltip_text = (SimQuery.t_("ui.why.autosave_keep") if slot == SaveSlots.AUTOSAVE else SimQuery.t_("ui.why.slot_empty")) \
			if del.disabled else ""
		del.pressed.connect(func() -> void: _ask_delete(slot))
		btns.add_child(del)
	else:
		var save_b := MenuKit.button(SimQuery.t_("ui.saves.save_here"))
		save_b.name = "Save"
		save_b.custom_minimum_size = Vector2(88, 20)
		save_b.pressed.connect(func() -> void: _ask_save(e))
		btns.add_child(save_b)
	for b: Node in btns.get_children():
		(b as Button).focus_entered.connect(func() -> void: _highlight(slot))
	return p


func _highlight(slot: String) -> void:
	for s: String in _rows:
		(_rows[s] as PanelContainer).theme_type_variation = &"SelectedRow" if s == slot else &"RowPanel"


## The first enabled button of the rows, else Back.
func default_focus() -> Control:
	for s: String in _rows:
		var btns := (_rows[s] as Node).find_child("Buttons", true, false)
		for b: Node in btns.get_children():
			if not (b as Button).disabled:
				return b as Button
	return %BackButton as Button


func _on_load(slot: String) -> void:
	ViewConfig.info("SaveScreen", "load %s" % slot)
	load_requested.emit(slot)


func _ask_delete(slot: String) -> void:
	(%Confirm as ConfirmDialog).set_meta("action", ["delete", slot])
	(%Confirm as ConfirmDialog).ask(SimQuery.t_("ui.saves.delete_q") % _slot_name(slot), "",
		[{"id": "cancel", "text": SimQuery.t_("ui.menu.cancel"), "hint": SimQuery.t_("ui.key.esc")},
		{"id": "delete", "text": SimQuery.t_("ui.saves.delete"), "hint": SimQuery.t_("ui.key.enter"), "primary": true}],
		SimQuery.t_("ui.menu.cannot_undo"))


func _ask_save(e: Dictionary) -> void:
	var slot := str(e["slot"])
	if not bool(e["exists"]):
		_do_save(slot)
		return
	var body := SimQuery.t_("ui.saves.overwrite_body_broken")
	if bool(e["ok"]):
		body = SimQuery.t_("ui.saves.overwrite_body") % MenuKit.date_label(int(e["header"].get("minute", 0)), time_config).to_lower()
	(%Confirm as ConfirmDialog).set_meta("action", ["save", slot])
	(%Confirm as ConfirmDialog).ask(SimQuery.t_("ui.saves.overwrite_q") % slot.get_slice("_", 1).to_int(), body,
		[{"id": "cancel", "text": SimQuery.t_("ui.menu.cancel"), "hint": SimQuery.t_("ui.key.esc")},
		{"id": "overwrite", "text": SimQuery.t_("ui.saves.overwrite"), "hint": SimQuery.t_("ui.key.enter"), "primary": true}])


func _on_confirm(id: String) -> void:
	var action: Array = (%Confirm as ConfirmDialog).get_meta("action", ["", ""])
	if id == "delete" and str(action[0]) == "delete":
		SaveSlots.delete(str(action[1]))
		_refresh()
	elif id == "overwrite" and str(action[0]) == "save":
		_do_save(str(action[1]))
	focus_default.call_deferred()


func _do_save(slot: String) -> void:
	ViewConfig.info("SaveScreen", "save %s" % slot)
	save_requested.emit(slot)


## While the confirmation is open it takes the keys (it is below in the tree: it is a child of this screen).
func _unhandled_input(event: InputEvent) -> void:
	if (%Confirm as ConfirmDialog).visible:
		return
	super(event)
