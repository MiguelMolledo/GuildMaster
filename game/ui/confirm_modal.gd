class_name ConfirmModal
extends Control
## The confirmation of the game (docs/ui/01_hud.md §5, mecanicas/_comun.md): a box of 280×120 (it grows up to 400×160
## for the figures) centred over the veil, only for what is expensive or cannot be undone (build, demolish, fire a
## loyal employee, an upgrade, paying the debt below tomorrow's wages, closing the dynasty). The question as the
## title, the cost in figures, «No se puede deshacer» when it is so, and two buttons: Cancel (Esc) on the left and the
## action (Enter) on the right, focused. It never pauses the game and never gives the order itself: the caller does,
## in `on_confirm`, through its order sink (Orders.apply).
##
## There is one in the HUD (hud.tscn, over the panels, under the help). From any panel:
##   ConfirmModal.ask_in(get_tree(), {
##       "title": tr("ui.upgrades.confirm_title") % name,      # the question
##       "body": "Cuesta 25 de oro y 3 de carbón. Te quedan 5.", # the figures (one or two lines)
##       "action": tr("ui.upgrades.buy"),                      # the action button ("Confirmar" if empty)
##       "irreversible": true,                                 # adds «No se puede deshacer» (aviso)
##       "seal": true,                                         # the wax seal by the title; the button seals (ui.seal)
##       "reason": "",                                         # why the action cannot be done now: shown, disabled
##   }, func() -> void: order_sink.call({...}))
## Answers: `answered(confirmed)`; on_confirm runs only on confirm. ESC / the Cancel button / a click on the veil
## cancel; Enter / the action button confirm (no keyboard focus: Space stays the pause) (not while `reason` is set). Opening a new one replaces the old (cancelled).

signal answered(confirmed: bool)

const GROUP: StringName = &"confirm_modal"
const MAX_SIZE: Vector2 = Vector2(400, 160)

var _on_confirm: Callable = Callable()
var _can: bool = true
var _bound: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CancelButton as Button).pressed.connect(cancel)
	(%ConfirmButton as Button).pressed.connect(confirm)
	(get_node("Veil") as Control).gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			cancel())


## The modal of the HUD (the first of the group), or null outside the game.
static func of(tree: SceneTree) -> ConfirmModal:
	return tree.get_first_node_in_group(GROUP) as ConfirmModal if tree != null else null


## Opens the HUD's modal (see the header for `spec`). False if there is none (no HUD: the tests).
static func ask_in(tree: SceneTree, spec: Dictionary, on_confirm: Callable = Callable()) -> bool:
	var m := of(tree)
	if m == null:
		return false
	m.ask(spec, on_confirm)
	return true


## Shows the question. spec: {title, body, action, cancel, irreversible, seal, reason} (all optional but title).
func ask(spec: Dictionary, on_confirm: Callable = Callable()) -> void:
	_bind()
	if visible:
		_answer(false)   # a new question replaces the old one
	_on_confirm = on_confirm
	(%Title as Label).text = str(spec.get("title", ""))
	var body := strip_irreversible(str(spec.get("body", "")))
	(%Body as Label).text = body
	(%Body as Label).visible = body != ""
	(%Warn as Label).text = tr("ui.confirm.irreversible")
	(%Warn as Label).visible = bool(spec.get("irreversible", false)) or body != str(spec.get("body", "")).strip_edges()
	var reason := str(spec.get("reason", ""))
	(%Reason as Label).text = reason
	(%Reason as Label).visible = reason != ""
	_can = reason == ""
	var seal := bool(spec.get("seal", false))
	(%Seal as TextureRect).texture = UiIcons.mark("seal") if seal else null
	(%Seal as TextureRect).visible = seal
	var ok := %ConfirmButton as Button
	ok.text = str(spec.get("action", "")) if str(spec.get("action", "")) != "" else tr("ui.confirm.ok")
	ok.disabled = not _can
	ok.theme_type_variation = &"SealButton" if seal else &"PrimaryButton"   # resalted: the hover look (00 §5)
	(%CancelButton as Button).text = str(spec.get("cancel", "")) if str(spec.get("cancel", "")) != "" else tr("ui.confirm.cancel")
	MenuKit.add_hint(%CancelButton as Button, tr("ui.confirm.key_cancel"))
	MenuKit.add_hint(ok, tr("ui.confirm.key_ok"))
	fit_button(%CancelButton as Button)
	fit_button(ok)
	visible = true
	_fit()
	ViewConfig.info("Confirm", "ask (title=%s, seal=%s, reason=%s)" % [spec.get("title", ""), seal, reason])


## «No se puede deshacer» once: if the caller wrote it in the body, it is taken out (the warning line says it).
static func strip_irreversible(body: String) -> String:
	var out := body
	for k: String in ["ui.confirm.irreversible", "ui.menu.cannot_undo"]:
		var t := TranslationServer.translate(k)
		if t != k and t != "":
			out = out.replace(t, "")
	return out.strip_edges()


## The button grows so that its key hint («Intro», «Esc») never sits over its text: text + hint + margins.
static func fit_button(b: Button) -> void:
	MenuKit.fit_hint(b, 112.0)


## The box grows with its text up to 400×160 (01 §5, _comun.md).
func _fit() -> void:
	var box := %Box as PanelContainer
	box.custom_minimum_size = Vector2(280, 120)
	var need := box.get_combined_minimum_size()
	if need.x > 280.0 or need.y > 120.0:
		box.custom_minimum_size = Vector2(minf(MAX_SIZE.x, maxf(280.0, need.x)), minf(MAX_SIZE.y, maxf(120.0, need.y)))


## The action: runs on_confirm (if it can be done) and closes.
func confirm() -> void:
	if not visible or not _can:
		return
	var cb := _on_confirm
	_answer(true)
	if cb.is_valid():
		cb.call()


func cancel() -> void:
	if visible:
		_answer(false)


## ESC closes it (the HUD's close_top asks it first).
func close() -> void:
	cancel()


func _answer(yes: bool) -> void:
	visible = false
	_on_confirm = Callable()
	ViewConfig.info("Confirm", "answered %s" % ("yes" if yes else "no"))
	answered.emit(yes)


## Enter confirms and Esc cancels while it is open (before anything under it hears the keys).
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		cancel()
	elif HudKeys.pressed(event, "confirm"):   # Enter (not Space: that is the pause)
		confirm()
	else:
		return
	get_viewport().set_input_as_handled()
