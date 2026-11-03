class_name PauseMenu
extends MenuScreen
## The pause menu (docs/ui/02_menu_inicial.md §6). open() pauses the game and locks the orders (GDD 4.1: the one
## pause that is not active: an order given while it is open is dropped); close() unlocks them and puts the pause back
## as it was (Resume or Esc). Resume (Esc) · Save (F5) · Load (F9) · Options · Help (F1) · ─ · End the dynasty…
## (D19: off with its reason while data/family.json succession.voluntary_close is false; on, a strong confirmation)
## · Quit to title · Quit the game; below, when it was last saved. Quitting with something unsaved asks first (Cancel ·
## Without saving · Save and quit). The app does what each signal asks; this screen only pauses and asks.
## Public API: open(), close(), is_open(); signals below. `game` is the Game autoload (tests pass their own).

signal resume_requested
signal save_requested
signal load_requested
signal options_requested
signal help_requested
signal close_dynasty_confirmed
## where: "title" | "quit"; save_first: the player chose "Save and quit" (the app opens the save screen first).
signal quit_requested(where: String, save_first: bool)

var game: Node = null
var _was_paused: bool = false
var _open: bool = false
var _bound: bool = false


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	if game == null:
		game = get_node_or_null("/root/Game")
	back_requested.connect(_resume)
	(%ResumeButton as Button).pressed.connect(_resume)
	(%SaveButton as Button).pressed.connect(func() -> void: save_requested.emit())
	(%LoadButton as Button).pressed.connect(func() -> void: load_requested.emit())
	(%OptionsButton as Button).pressed.connect(func() -> void: options_requested.emit())
	(%HelpButton as Button).pressed.connect(func() -> void: help_requested.emit())
	(%CloseDynastyButton as Button).pressed.connect(_ask_close_dynasty)
	(%TitleButton as Button).pressed.connect(func() -> void: _ask_quit("title"))
	(%QuitButton as Button).pressed.connect(func() -> void: _ask_quit("quit"))
	(%Confirm as ConfirmDialog).chosen.connect(_on_confirm)


## Pauses (remembering the pause it found), locks the orders and shows the menu.
func open() -> void:
	_bind()
	if not _open:
		_open = true
		_was_paused = bool(game.get("paused")) if game != null else false
		if game != null:
			game.call("set_paused", true)
			game.call("lock_orders", true)
	super()


## Hides the menu, unlocks the orders and puts the pause back as it was.
func close() -> void:
	super()
	(%Confirm as ConfirmDialog).close()
	if _open:
		_open = false
		if game != null:
			game.call("lock_orders", false)
			game.call("set_paused", _was_paused)


func is_open() -> bool:
	return _open


## Hidden while another screen (save, load, options) is drawn over it, without unpausing.
func set_covered(covered: bool) -> void:
	(%Center as Control).visible = not covered
	if not covered and visible:
		focus_default.call_deferred()


func _resume() -> void:
	close()
	resume_requested.emit()


func _refresh() -> void:
	(%Title as Label).text = SimQuery.t_("ui.pause.title")
	var rows := {"ResumeButton": ["ui.pause.resume", "ui.key.esc"], "SaveButton": ["ui.pause.save", "ui.key.f5"],
		"LoadButton": ["ui.pause.load", "ui.key.f9"], "OptionsButton": ["ui.pause.options", ""],
		"HelpButton": ["ui.pause.help", "ui.key.f1"], "CloseDynastyButton": ["ui.pause.close_dynasty", ""],
		"TitleButton": ["ui.pause.to_title", ""], "QuitButton": ["ui.pause.quit", ""]}
	for n: String in rows:
		var b := get_node("%" + n) as Button
		b.text = SimQuery.t_(str(rows[n][0]))
		if str(rows[n][1]) != "":
			MenuKit.add_hint(b, SimQuery.t_(str(rows[n][1])))
	var can_close := can_close_dynasty()
	(%CloseDynastyButton as Button).disabled = not can_close
	(%CloseReason as Label).visible = not can_close
	(%CloseReason as Label).text = SimQuery.t_("ui.pause.close_off")
	(%LastSaved as Label).text = last_saved_text()
	set_covered(false)


## D19: the voluntary close is on in data/family.json (succession.voluntary_close).
func can_close_dynasty() -> bool:
	var sim: Variant = game.get("sim") if game != null else null
	if sim == null:
		return false
	return bool((sim as Sim).catalog.family.get("succession", {}).get("voluntary_close", false))


## "Último guardado: hace 12 min" (this session), or that nothing was saved yet.
func last_saved_text() -> String:
	var ago := ago_text()
	return SimQuery.t_("ui.pause.never_saved") if ago == "" else SimQuery.t_("ui.pause.last_saved") % ago


## "hace 12 min" / "hace un momento" since the last save of this session ("" if none).
func ago_text() -> String:
	var ms := int(game.get("last_saved_ms")) if game != null else -1
	if ms < 0:
		return ""
	var mins := int((Time.get_ticks_msec() - ms) / 60000)
	return SimQuery.t_("ui.pause.ago_now") if mins < 1 else SimQuery.t_("ui.pause.ago_min") % mins


func _key(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_F5:
			save_requested.emit()
		KEY_F9:
			load_requested.emit()
		KEY_F1:
			help_requested.emit()
		_:
			return false
	return true


func _ask_close_dynasty() -> void:
	if not can_close_dynasty():
		return
	(%Confirm as ConfirmDialog).set_meta("action", "close_dynasty")
	(%Confirm as ConfirmDialog).ask(SimQuery.t_("ui.pause.close_q"), SimQuery.t_("ui.pause.close_body"),
		[{"id": "cancel", "text": SimQuery.t_("ui.menu.cancel"), "hint": SimQuery.t_("ui.key.esc"), "primary": true},
		{"id": "close", "text": SimQuery.t_("ui.pause.close_yes")}], SimQuery.t_("ui.menu.cannot_undo"))


func _ask_quit(where: String) -> void:
	var unsaved := bool(game.call("unsaved")) if game != null else false
	if not unsaved:
		quit_requested.emit(where, false)
		return
	(%Confirm as ConfirmDialog).set_meta("action", "quit_" + where)
	var ago := ago_text()
	var body := SimQuery.t_("ui.pause.quit_body_never") if ago == "" else SimQuery.t_("ui.pause.quit_body") % ago
	(%Confirm as ConfirmDialog).ask(SimQuery.t_("ui.pause.quit_title_q" if where == "title" else "ui.pause.quit_q"), body,
		[{"id": "cancel", "text": SimQuery.t_("ui.menu.cancel"), "hint": SimQuery.t_("ui.key.esc")},
		{"id": "discard", "text": SimQuery.t_("ui.pause.without_saving")},
		{"id": "save", "text": SimQuery.t_("ui.pause.save_and_quit"), "primary": true}])


func _on_confirm(id: String) -> void:
	var action := str((%Confirm as ConfirmDialog).get_meta("action", ""))
	if action == "close_dynasty" and id == "close":
		close_dynasty_confirmed.emit()
	elif action.begins_with("quit_") and id in ["discard", "save"]:
		quit_requested.emit(action.substr(5), id == "save")
	else:
		focus_default.call_deferred()
