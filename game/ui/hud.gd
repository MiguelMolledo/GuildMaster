extends CanvasLayer
## HUD of the town (H1): clock (time, date, sun/moon, phase bar, tooltip with the full date), pause and speeds
## ×1/×2/×4 (D4) by button or key (pause_toggle = Space, speed_1/2/3 = 1/2/3), the "paused" sign and a short
## message when the sim refuses an order of the human family (tr("reason.<id>")). Reads Game; only changes the
## session's speed and pause, never the world.
## H2: the selected person (portrait, name, gold) with their order queue as a numbered list (active pause, GDD 4.1:
## the state's order_queue plus the orders given during this pause), the button / key I of their panel
## (CharacterPanel), and the picked building with its "Manage" button (GDD 4.6.4).
## H3: the family's gold and its debt with the due date, the account book (button / key L, LedgerPanel), the start
## objectives, urgent notices popping up (a click centres the camera on the notice's building or person, or opens
## the book), the market panel (MarketPanel) and the board (BoardPanel), opened when the person who was sent to a
## stall or the board stands on its service tile, or from the counter of a shop.
## H5 (polish): an own building with idle employees (the "zz" icon) says why in the picked building's panel; the
## help overlay (HelpPanel: key F1 or "?", the Help button; ESC closes it) lists the controls and panels, and the
## objective panel says how to do the current objective (objective_how.<id>) or, with the start objectives done,
## what to try next (objective_how.free). Inside a building the objective panel moves to the left, under the selected person, so it does not cover the building's
## panels (they open on the right).
## H8: the controllable group (GDD 4.10.5) as portraits next to the selected person (keys 1-2-3 or a click select,
## a double click centres the camera; the active one has the gold border); the speeds move to Shift+1/2/3. The family
## tree (key F, FamilyTreePanel) and the courtship panel (CourtshipPanel, from the tree or the person's sheet).

signal manage_pressed(building_id: String)
signal select_requested(id: String)  # H8: a portrait of the group was picked (key 1-2-3 or click)
signal focus_requested(target: String)  # a notice was clicked: centre on this building / person

@onready var _sun_moon: SunMoon = %SunMoon
@onready var _time_label: Label = %TimeLabel
@onready var _date_label: Label = %DateLabel
@onready var _phase_bar: ProgressBar = %PhaseBar
@onready var _clock_panel: PanelContainer = %ClockPanel
@onready var _pause_button: Button = %PauseButton
@onready var _speed_buttons: Array[Button] = [%Speed1, %Speed2, %Speed4]
@onready var _paused_label: Label = %PausedLabel
@onready var _toast_label: Label = %ToastLabel
@onready var _help_label: Label = %HelpLabel
@onready var _title_label: Label = %TitleLabel
@onready var _selected_panel: PanelContainer = %SelectedPanel
@onready var _portrait: ColorRect = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _inventory_button: Button = %InventoryButton
@onready var _queue_label: Label = %QueueLabel
@onready var _queue_list: VBoxContainer = %QueueList
@onready var _building_panel: PanelContainer = %BuildingPanel
@onready var _building_name: Label = %BuildingName
@onready var _building_hint: Label = %BuildingHint
@onready var _manage_button: Button = %ManageButton
@onready var _character_panel: CharacterPanel = %CharacterPanel
@onready var _family_panel: PanelContainer = %FamilyPanel
@onready var _family_gold: Label = %FamilyGold
@onready var _debt_label: Label = %DebtLabel
@onready var _ledger_button: Button = %LedgerButton
@onready var _objective_panel: PanelContainer = %ObjectivePanel
@onready var _objective_title: Label = %ObjectiveTitle
@onready var _objective_label: Label = %ObjectiveLabel
@onready var _objective_progress: Label = %ObjectiveProgress
@onready var _notice_popups: VBoxContainer = %NoticePopups
@onready var _market_panel: MarketPanel = %MarketPanel
@onready var _board_panel: BoardPanel = %BoardPanel
@onready var _ledger_panel: LedgerPanel = %LedgerPanel
@onready var _objective_hint: Label = %ObjectiveHint
@onready var _help_button: Button = %HelpButton
@onready var _help_panel: HelpPanel = %HelpPanel
@onready var _group_bar: HBoxContainer = %GroupBar
@onready var _tree_panel: FamilyTreePanel = %FamilyTreePanel
@onready var _court_panel: CourtshipPanel = %CourtshipPanel

var selected_id: String = ""
var building_id: String = ""
var interior_open: bool = false
var _queue_sig: String = ""
var _pending_service: Dictionary = {}  # {actor, kind, id, service}: open its panel when the actor stands there
var _popups: Array = []  # [{node, left}]
var _group_sig: String = ""
var _frame_scene: PackedScene = preload("res://game/ui/portrait_frame.tscn")

var _game: Node = null
var _toast_left: float = 0.0
var _last_minute: int = -1


func _ready() -> void:
	_game = get_node_or_null("/root/Game")
	_paused_label.text = tr("hud.paused")
	_help_label.text = tr("hud.help") + tr("hud.help_more")
	_title_label.text = tr("app.title")
	_pause_button.text = tr("hud.pause")
	_pause_button.tooltip_text = tr("hud.pause_tip")
	_pause_button.pressed.connect(func() -> void: _game.toggle_pause())
	var group := ButtonGroup.new()
	for i: int in _speed_buttons.size():
		var b := _speed_buttons[i]
		var s: int = Game.SPEEDS[i]
		b.text = tr("hud.speed") % s
		b.tooltip_text = tr("hud.speed_tip") % [s, i + 1]  # H8: Shift+1/2/3 (1-2-3 select the group)
		b.button_group = group
		b.pressed.connect(func() -> void: _game.set_speed(s))
	_toast_label.visible = false
	_inventory_button.text = tr("hud.inventory")
	_inventory_button.tooltip_text = tr("hud.inventory_tip")
	_inventory_button.pressed.connect(toggle_character_panel)
	_queue_label.text = tr("hud.queue")
	_manage_button.text = tr("hud.manage")
	_manage_button.tooltip_text = tr("hud.manage_tip")
	_manage_button.pressed.connect(func() -> void: manage_pressed.emit(building_id))
	_character_panel.order_sink = _game.give
	_market_panel.order_sink = _game.give
	_board_panel.order_sink = _game.give
	_ledger_panel.order_sink = _game.give
	_ledger_panel.notice_clicked.connect(notice_action)
	_ledger_button.text = tr("hud.ledger")
	_ledger_button.tooltip_text = tr("hud.ledger_tip")
	_ledger_button.pressed.connect(toggle_ledger)
	_objective_title.text = tr("hud.objective")
	_help_button.text = tr("hud.help_button")
	_help_button.tooltip_text = tr("hud.help_button_tip")
	_help_button.pressed.connect(toggle_help)
	_tree_panel.order_sink = _game.give
	_court_panel.order_sink = _game.give
	_tree_panel.switch_requested.connect(func(id: String) -> void: select_requested.emit(id))
	_tree_panel.court_requested.connect(open_courtship)
	_character_panel.tree_requested.connect(toggle_tree)
	_character_panel.court_requested.connect(open_courtship)
	Events.sim_event.connect(_on_sim_event)
	_refresh()


func _process(delta: float) -> void:
	_refresh()
	_check_service()
	_tick_popups(delta)
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast_label.visible = false


func _refresh() -> void:
	if _game == null or _game.sim == null:
		return
	var sim: Sim = _game.sim
	var minute := int(sim.state.clock["minute"])
	_title_label.visible = sim.state.map_id == ""
	_paused_label.visible = _game.paused
	_pause_button.set_pressed_no_signal(_game.paused)
	for i: int in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(Game.SPEEDS[i] == _game.speed)
	_phase_bar.value = DayNight.phase_progress(minute, _game.step_fraction(), sim.catalog.time) * 100.0
	_refresh_selected(sim)
	_refresh_family(sim)
	_refresh_group(sim)
	if minute == _last_minute:
		return
	_last_minute = minute
	if _building_panel.visible:
		_update_building_panel()   # the idle reason follows the queue
	var t := sim.now()
	_time_label.text = tr("hud.time") % [t["hour"], t["minute"]]
	_date_label.text = tr("hud.date") % [t["day"], tr("season." + str(t["season"])), t["year"]]
	_sun_moon.phase = str(t["phase"])
	_clock_panel.tooltip_text = tr("hud.clock") % [t["day"], tr("season." + str(t["season"])), t["year"], t["hour"],
		t["minute"], tr("phase." + str(t["phase"]))]


## The person picked on the map or inside ("" = nobody).
func set_selected(id: String) -> void:
	selected_id = id
	_queue_sig = "-"
	if _game != null and _game.sim != null:
		_character_panel.setup(_game.sim, id)
	if id == "":
		_character_panel.close()


## The building picked on the map ("" = none): its name and the Manage button.
func set_building(id: String) -> void:
	building_id = id
	_update_building_panel()


func set_interior(open: bool) -> void:
	interior_open = open
	_help_label.text = tr("hud.help_interior" if open else "hud.help") + tr("hud.help_more")
	_update_building_panel()


func _update_building_panel() -> void:
	_building_panel.visible = building_id != "" and not interior_open and _game != null and _game.sim != null
	if not _building_panel.visible:
		return
	var sim: Sim = _game.sim
	var own := false
	for id: String in sim.state.characters:
		var ch: Dictionary = sim.state.characters[id]
		if str(ch.get("controlled_by", "")) == "human" and SimQuery.is_own(sim.state, id, building_id):
			own = true
	_building_name.text = SimQuery.building_label(sim.state, sim.catalog, building_id)
	if own:
		_building_hint.text = tr("hud.building_own")
		# H5: the idle icon over the building, explained (why the employees stand still)
		if not SimQuery.idle_employees(sim, building_id).is_empty():
			var why := str(SimQuery.queue_view(sim, building_id).get("stalled", ""))
			_building_hint.text = tr("hud.building_idle") % (SimQuery.reason_text(why) if why != "" else
				tr("hud.building_idle_unknown"))
	elif SimQuery.is_public(sim.state, sim.catalog, building_id):
		_building_hint.text = tr("hud.building_public")
	else:
		_building_hint.text = tr("hud.building_other")
	_manage_button.disabled = not own
	_manage_button.visible = own  # another family's building cannot be managed (GDD 4.5.5)


func toggle_character_panel() -> void:
	if _character_panel.visible:
		_character_panel.close()
	elif selected_id != "":
		_character_panel.setup(_game.sim, selected_id)
		_character_panel.open()


## ESC: closes the top panel (help, market, board, book, then the character panel). False if there was nothing to
## close.
func close_top() -> bool:
	if _help_panel.visible:
		toggle_help()
		return true
	for p: Control in [_court_panel, _tree_panel, _market_panel, _board_panel, _ledger_panel]:
		if p.visible:
			p.call("close")
			return true
	if _character_panel.visible:
		_character_panel.close()
		return true
	return false


func _refresh_selected(sim: Sim) -> void:
	var ch: Dictionary = sim.state.characters.get(selected_id, {})
	if not ch.is_empty() and not bool(ch.get("alive", true)):
		ch = {}  # H8: a dead person (or another game's id) is nobody
	_selected_panel.visible = not ch.is_empty()
	if ch.is_empty():
		return
	var fam: Dictionary = sim.state.families.get(str(ch.get("family", "")), {})
	_portrait.color = ViewConfig.color(str(fam.get("colors", {}).get("primary", "#808080")))
	_name_label.text = str(ch.get("name", selected_id))
	_gold_label.text = tr("ui.character.gold") % Money.gold(sim.state, str(ch.get("family", "")))  # the family purse (H3)
	var lines := SimQuery.queue_lines(sim, selected_id, _game.pending(), _game.paused)
	var sig := "|".join(lines)
	if sig == _queue_sig:
		return
	_queue_sig = sig
	for c: Node in _queue_list.get_children():
		_queue_list.remove_child(c)
		c.queue_free()
	_queue_label.visible = not lines.is_empty()
	for i: int in lines.size():
		var l := Label.new()
		l.text = "%d. %s" % [i + 1, lines[i]]
		_queue_list.add_child(l)
	_selected_panel.reset_size()


func _unhandled_input(event: InputEvent) -> void:
	if _game == null or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	if HelpPanel.is_help_key(event):
		toggle_help()
		get_viewport().set_input_as_handled()
		return
	var key := (event as InputEventKey).keycode
	if key in [KEY_1, KEY_2, KEY_3]:  # H8: 1-2-3 the group (GDD 4.10.5); Shift+1/2/3 the speeds (D4)
		var i := [KEY_1, KEY_2, KEY_3].find(key)
		if (event as InputEventKey).shift_pressed:
			_game.set_speed(Game.SPEEDS[i])
		else:
			pick_group(i)
	elif key == KEY_F:
		toggle_tree()
	elif (event as InputEventKey).keycode == KEY_I:
		toggle_character_panel()
	elif (event as InputEventKey).keycode == KEY_L:
		toggle_ledger()
	elif event.is_action_pressed("pause_toggle"):
		_game.toggle_pause()
	elif event.is_action_pressed("speed_1"):
		_game.set_speed(Game.SPEEDS[0])
	elif event.is_action_pressed("speed_2"):
		_game.set_speed(Game.SPEEDS[1])
	elif event.is_action_pressed("speed_3"):
		_game.set_speed(Game.SPEEDS[2])
	else:
		return
	get_viewport().set_input_as_handled()


func _on_sim_event(e: Dictionary) -> void:
	if str(e.get("type", "")) == "notice_added":
		_on_notice(e)
		return
	if str(e.get("type", "")) != "order_refused":
		return
	var ch: Dictionary = _game.sim.state.characters.get(str(e.get("actor", "")), {})
	if not ch.is_empty() and str(ch.get("controlled_by", "")) != "human":
		return
	show_toast(tr("reason." + str(e.get("reason", ""))))


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.visible = true
	_toast_left = float(ViewConfig.value("toast_seconds", 2.5))
	Log.info("Hud", "toast: %s" % text)


# --- H3 · family purse, debt, objectives ------------------------------------------------------------------------------

func market_panel() -> MarketPanel:
	return _market_panel


func board_panel() -> BoardPanel:
	return _board_panel


func ledger_panel() -> LedgerPanel:
	return _ledger_panel


## The family whose purse the HUD shows: the selected person's, else the player's.
func family() -> String:
	var sim: Sim = _game.sim
	var fam := str(sim.state.characters.get(selected_id, {}).get("family", ""))
	if fam == "" or str(sim.state.families.get(fam, {}).get("controlled_by", "")) != "human":
		fam = SimQuery.player_family(sim.state)
	return fam


func _refresh_family(sim: Sim) -> void:
	var fam := family()
	_family_panel.visible = fam != ""
	if fam == "":
		_objective_panel.visible = false
		return
	_family_gold.text = tr("hud.family_gold") % Money.gold(sim.state, fam)
	var loans := SimQuery.loans_of(sim, fam)
	_debt_label.visible = not loans.is_empty()
	if not loans.is_empty():
		var l: Dictionary = loans[0]
		var days := int(l.get("days_left", 0))
		_debt_label.text = tr("hud.debt") % [int(l.get("outstanding", 0)), days]
		_debt_label.add_theme_color_override("font_color", Color(1, 0.5, 0.42) if days <= 2 else Color(0.93, 0.89, 0.82))
		_debt_label.tooltip_text = tr("hud.debt_tip") % SimQuery.minute_label(int(l.get("due_minute", 0)) - 1)
	var ov := Objectives.view(sim, fam)
	var current := str(ov.get("current", ""))
	_objective_panel.visible = not ov.is_empty() and (current != "" or not (ov.get("done", []) as Array).is_empty())
	if not _objective_panel.visible:
		return
	_set_hint(current if current != "" else "free")
	_place_objective()
	if current == "":
		_objective_label.text = tr("hud.objectives_done")
		_objective_progress.text = ""
		_objective_progress.visible = false
		_objective_panel.reset_size()
		return
	_objective_progress.visible = true
	_objective_label.text = SimQuery.objective_name(sim.catalog, current)
	var parts: PackedStringArray = []
	for p: Dictionary in ov.get("progress", []):
		parts.append("%d/%d" % [int(p.get("have", 0)), int(p.get("need", 1))])
	_objective_progress.text = " · ".join(parts)
	_objective_panel.reset_size()


## The objective panel: top right under the clock in the town; inside a building, top left under the selected
## person's panel and the group's portraits (the building's panels open on the right).
func _place_objective() -> void:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(960, 540)
	var y := 122.0
	var x := vp.x - _objective_panel.size.x - 6.0
	if interior_open:
		x = 6.0
		y = (_selected_panel.position.y + _selected_panel.size.y + 6.0) if _selected_panel.visible else 6.0
		if _group_bar.visible:  # H8: under the group's portraits
			y = maxf(y, _group_bar.position.y + _group_bar.size.y + 6.0)
	if _objective_panel.position != Vector2(x, y):
		_objective_panel.position = Vector2(x, y)


## How to do objective `id` (objective_how.<id>; "free" = after the start objectives); hidden without a text.
func _set_hint(id: String) -> void:
	var key := "objective_how." + id
	var text := tr(key)
	_objective_hint.visible = text != key and text != ""
	if _objective_hint.visible and _objective_hint.text != text:
		_objective_hint.text = text
		Log.info("Hud", "objective hint: %s" % id)


func help_visible() -> bool:
	return _help_panel.visible


## F1, "?" or the "?" button: the help overlay on / off (it does not pause the game).
func toggle_help() -> void:
	_help_panel.toggle()


## Closes every panel (a new game was loaded).
func close_panels() -> void:
	_help_panel.visible = false
	_pending_service = {}
	for p: Control in [_market_panel, _board_panel, _ledger_panel, _tree_panel, _court_panel]:
		p.call("close")
	_character_panel.close()


func toggle_ledger() -> void:
	if _ledger_panel.visible:
		_ledger_panel.close()
	else:
		open_ledger()


func open_ledger(tab: String = "") -> void:
	var sim: Sim = _game.sim
	var fam := family()
	if fam == "":
		return
	_market_panel.close()
	_board_panel.close()
	_ledger_panel.open_for(sim, fam, SimQuery.family_actor(sim.state, fam, selected_id), tab)


# --- H3 · stalls, shops and the board ---------------------------------------------------------------------------------

## The world sent `actor` to a stall or the board (kind ""= another order: forget it). The panel opens when they
## stand on the service tile (at once if they already do).
func request_service(actor: String, kind: String, id: String, service: Vector2i) -> void:
	if kind == "":
		if str(_pending_service.get("actor", "")) == actor:
			_pending_service = {}
		return
	_pending_service = {"actor": actor, "kind": kind, "id": id, "service": service}
	_market_panel.close()
	_board_panel.close()
	_check_service()


func _check_service() -> void:
	if _pending_service.is_empty() or _game == null or _game.sim == null:
		return
	var sim: Sim = _game.sim
	var actor := str(_pending_service["actor"])
	if not SimQuery.stands_on(sim.state, actor, _pending_service["service"]):
		return
	var kind := str(_pending_service["kind"])
	var id := str(_pending_service["id"])
	_pending_service = {}
	if kind == "board":
		open_board(actor)
	else:
		open_market(actor, id)


func open_market(actor: String, stall: String) -> void:
	_board_panel.close()
	_ledger_panel.close()
	_market_panel.open_for(_game.sim, actor, stall)
	Log.info("Hud", "market panel (stall=%s, actor=%s)" % [stall, actor])


func open_board(actor: String) -> void:
	_market_panel.close()
	_ledger_panel.close()
	_board_panel.open_for(_game.sim, actor)
	Log.info("Hud", "board panel (actor=%s)" % actor)


# --- H3 · notices -----------------------------------------------------------------------------------------------------

## Urgent notices of the player's family pop up (GDD 4.18); the rest only go to the book.
func _on_notice(e: Dictionary) -> void:
	if str(e.get("severity", "")) != "urgent" or str(e.get("family", "")) != SimQuery.player_family(_game.sim.state):
		return
	var cfg: Dictionary = ViewConfig.value("notices", {})
	while _popups.size() >= int(cfg.get("popup_max", 3)):
		(_popups.pop_front()["node"] as Node).queue_free()
	var n := e.duplicate(true)
	var b := Button.new()
	b.text = "! " + SimQuery.notice_text(_game.sim.state, _game.sim.catalog, n)
	b.tooltip_text = tr("hud.notice_tip")
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", ViewConfig.color(str(cfg.get("colors", {}).get("urgent", "#ff8070"))))
	b.pressed.connect(func() -> void:
		notice_action(n)
		_drop_popup(b))
	_notice_popups.add_child(b)
	_popups.append({"node": b, "left": float(cfg.get("popup_seconds", 8.0))})
	Log.info("Hud", "urgent notice: %s" % b.text)


func _drop_popup(b: Node) -> void:
	for i: int in _popups.size():
		if _popups[i]["node"] == b:
			_popups.remove_at(i)
			break
	b.queue_free()


func _tick_popups(delta: float) -> void:
	for p: Dictionary in _popups.duplicate():
		p["left"] = float(p["left"]) - delta
		if float(p["left"]) <= 0.0:
			_drop_popup(p["node"])


## A click on a notice: centre on its building or person (the app does it), else open the book on the notices.
func notice_action(n: Dictionary) -> void:
	var target := str(n.get("target", ""))
	if str(n.get("key", "")) == "notice.school_choice":  # H8: the choice is made in the family tree
		if not _tree_panel.visible:
			toggle_tree()
		_tree_panel.pick(target)
		return
	if target != "" and (_game.sim.state.buildings.has(target) or _game.sim.state.characters.has(target)):
		focus_requested.emit(target)
	elif not _ledger_panel.visible:
		open_ledger("notices")


# --- H8 · group, family tree, courtship -------------------------------------------------------------------------------

func tree_panel() -> FamilyTreePanel:
	return _tree_panel


func courtship_panel() -> CourtshipPanel:
	return _court_panel


## The group of the player's family as portraits (key 1-2-3; the active one with the gold border).
func _refresh_group(sim: Sim) -> void:
	var fam := family()
	var group := Kin.group(sim.state, fam) if fam != "" else []
	var heir := Kin.heir(sim, fam) if fam != "" else ""
	var sig := "%s|%s|%s|%s" % [group, selected_id, heir, group.map(func(c: String) -> Variant: return sim.state.characters[c].get("visual"))]
	if sig == _group_sig:
		return
	_group_sig = sig
	for c: Node in _group_bar.get_children():
		_group_bar.remove_child(c)
		c.queue_free()
	for i: int in group.size():
		var f := _frame_scene.instantiate() as PortraitFrame
		f.name = "Group%d" % (i + 1)
		_group_bar.add_child(f)
		f.show_character(sim.state, str(group[i]), {"active": str(group[i]) == selected_id, "controlled": true,
			"heir": str(group[i]) == heir, "key": str(i + 1)})
		f.clicked.connect(func(id: String) -> void: select_requested.emit(id))
		f.double_clicked.connect(func(id: String) -> void: focus_requested.emit(id))
	_group_bar.visible = group.size() > 0


## The i-th person of the group (0-based), if any: selected.
func pick_group(i: int) -> void:
	var fam := family()
	if fam == "":
		return
	var group := Kin.group(_game.sim.state, fam)
	if i >= 0 and i < group.size():
		Log.info("Hud", "group %d -> %s" % [i + 1, group[i]])
		select_requested.emit(str(group[i]))


func toggle_tree() -> void:
	if _tree_panel.visible:
		_tree_panel.close()
		return
	var fam := family()
	if fam == "":
		return
	_tree_panel.setup(_game.sim, fam, selected_id)
	_tree_panel.open()


func open_courtship(who: String) -> void:
	if who == "" or _game.sim == null:
		return
	_court_panel.setup(_game.sim, who)
	_court_panel.open()
