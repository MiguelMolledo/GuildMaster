extends CanvasLayer
## The HUD in the town and inside a building, on the fixed zones of docs/ui/01_hud.md §4 (HudLayout.ZONES): it reads
## the state and Game, opens panels and changes the session's pause and speed; it never changes the world itself.
##   1 · Card (top left): the portraits of the group (keys 1-2-3, a click picks, a double click centres; the active
##       one with the gold frame, the heir's crown, the queued orders in pause) and the active person's name, the
##       family's gold, title badge and reputation (H8, GDD 4.10.5).
##   2 · Status bar (top centre): the debt (figure, paid bar, days left; tooltip with the due date) and the panel
##       buttons with their key: Book L, Family F, Inventory I, Build B (from H6), Offices O, Trial J (while one is
##       open), Help F1, Menu (asks for the pause menu). «EN PAUSA» hangs under it while paused.
##   3 · Clock (top right): sun / moon, time, date, the phase bar, pause and ×1 ×2 ×4 (D4; Space, Shift+1/2/3).
##       H13: next to the time, the global event in force that lasts longest and its time left (all of them in the tip).
##   4 · Column (left): the objective (it folds to its title and progress on the map after a while, or when the
##       queue would not fit) with how to do it (objective_how.<id>), the active person's queued orders (active pause,
##       GDD 4.1) and the cards that ask for a decision (MicroeventCard, H7).
##   5 · Management zone (right): one panel at a time (ManageSlot): market, board, book, townsperson's sheet,
##       courtship, town hall, family AI, inventory; the interior's panels join the same slot. The family tree, the
##       offices chart and the trial are big modals (912×440) over the veil.
##   6 · Selection (bottom centre): the picked building (Manage on your own) or the selected person; inside a
##       building the interior draws its own bar there (InteriorView).
##   7 · Notices (bottom left): the notices of the player's family that pop up, urgent (until clicked or the book is
##       opened), warning (8 s) and done (5 s); a click centres the camera on its building or person or opens the
##       book. Info notices only go to the book.
## F1 / ? / the "?" button: the help (keys by sections, «Ahora mismo» and the tutorial's chapters, whose buttons emit
## tutorial_requested). ESC is the app's (close_top); with nothing open it calls request_pause_menu(), which emits
## pause_menu_requested (the pause menu is the menus' scene).

signal manage_pressed(building_id: String)
signal select_requested(id: String)    # H8: a portrait of the group was picked (key 1-2-3 or click)
signal focus_requested(target: String)  # a notice was clicked: centre on this building / person
signal deselect_requested               # ESC with only a building picked: the world forgets it
signal pause_menu_requested             # ESC with nothing open, or the Menu button (docs/ui/02: the pause menu)
signal tutorial_requested(chapter: String)  # a chapter picked in the help (docs/ui/05_tutorial.md §2)
signal region_requested                  # R: the map of the region (docs/gdd/09b_region.md; the app opens it)

const GOLD_ICON: String = "icon_oro"

@onready var _title_label: Label = %TitleLabel
# 1 · card
@onready var _card: PanelContainer = %Card
@onready var _group_bar: HBoxContainer = %GroupBar
@onready var _name_label: Label = %NameLabel
@onready var _gold_icon: TextureRect = %GoldIcon
@onready var _family_gold: Label = %GoldLabel
@onready var _title_badge: TextureRect = %TitleBadge
@onready var _family_title: Label = %FamilyTitle          # H9: the family's title and reputation
# 2 · status bar
@onready var _status_bar: PanelContainer = %StatusBar
@onready var _debt_box: HBoxContainer = %DebtBox
@onready var _debt_caption: Label = %DebtCaption
@onready var _debt_label: Label = %DebtLabel
@onready var _debt_bar: ProgressBar = %DebtBar
@onready var _debt_days: Label = %DebtDays
@onready var _ledger_button: Button = %LedgerButton
@onready var _tree_button: Button = %TreeButton
@onready var _inventory_button: Button = %InventoryButton
@onready var _build_button: Button = %BuildButton
@onready var _offices_button: Button = %OfficesButton      # H10: the offices (key O)
@onready var _trials_button: Button = %TrialsButton        # H11: the family's trial (key J), only while one is open
@onready var _help_button: Button = %HelpButton
@onready var _menu_button: Button = %MenuButton
@onready var _paused_tag: PanelContainer = %PausedTag
@onready var _paused_label: Label = %PausedLabel
# 3 · clock
@onready var _clock_panel: PanelContainer = %ClockPanel
@onready var _event_label: Label = %EventLabel  # H13: the global events in force and their time left
@onready var _sun_moon: TextureRect = %SunMoon
@onready var _time_label: Label = %TimeLabel
@onready var _date_label: Label = %DateLabel
@onready var _phase_bar: ProgressBar = %PhaseBar
@onready var _pause_button: Button = %PauseButton
@onready var _speed_buttons: Array[Button] = [%Speed1, %Speed2, %Speed4]
# 4 · column
@onready var _objective_panel: PanelContainer = %ObjectivePanel
@onready var _objective_title: Label = %ObjectiveTitle
@onready var _objective_label: Label = %ObjectiveLabel
@onready var _objective_progress: Label = %ObjectiveProgress
@onready var _objective_sep: HSeparator = %ObjectiveSep
@onready var _objective_hint: Label = %ObjectiveHint
@onready var _queue_panel: PanelContainer = %QueuePanel
@onready var _queue_label: Label = %QueueLabel
@onready var _queue_list: VBoxContainer = %QueueList
@onready var _mev_card: MicroeventCard = %MicroeventCard
# 5 · management zone and big modals
@onready var _market_panel: MarketPanel = %MarketPanel
@onready var _board_panel: BoardPanel = %BoardPanel
@onready var _ledger_panel: LedgerPanel = %LedgerPanel
@onready var _npc_panel: NpcPanel = %NpcPanel
@onready var _court_panel: CourtshipPanel = %CourtshipPanel
@onready var _hall_panel: TownHallPanel = %TownHallPanel  # H9: the town hall (titles)
@onready var _kin_ai_panel: KinAiPanel = %KinAiPanel     # H14: directives, needs and morale of a family member
@onready var _character_panel: CharacterPanel = %CharacterPanel
@onready var _veil: ColorRect = %Veil
@onready var _tree_panel: FamilyTreePanel = %FamilyTreePanel
@onready var _offices_panel: OfficesPanel = %OfficesPanel  # H10: the chart, running, campaign and powers
@onready var _trial_panel: TrialPanel = %TrialPanel        # H11: preparation and hearing
# 6 · selection
@onready var _building_panel: PanelContainer = %SelectionBar
@onready var _selection_icon: TextureRect = %SelectionIcon
@onready var _building_name: Label = %BuildingName
@onready var _building_hint: Label = %BuildingHint
@onready var _manage_button: Button = %ManageButton
@onready var _buy_button: Button = %BuyButton  # posada: a building for sale (the Taberna-Posada, buy_building)
@onready var _table_button: Button = %TableButton  # posada: another family's tavern, its gaming table (InnVisitCard)
@onready var _selection_action: Button = %SelectionAction
# 7 · notices, toast, cards, help
@onready var _notice_popups: VBoxContainer = %NoticePopups
@onready var _toast_label: PanelContainer = %ToastLabel
@onready var _toast_text: Label = %ToastText
@onready var _title_card: TitleCard = %TitleCard          # H9: the ceremony
@onready var _office_card: OfficeCard = %OfficeCard        # H10: the result of a vote
@onready var _trial_card: TrialCard = %TrialCard           # H11: «you are accused» and the verdict
@onready var _help_panel: HelpPanel = %HelpPanel
@onready var _confirm: ConfirmModal = %ConfirmModal       # docs/ui/01 §5: the confirmation of what is expensive

var selected_id: String = ""
var building_id: String = ""
var interior_open: bool = false
var _hint_id: String = ""        # the objective whose hint is shown (a new one unfolds it again)
var _hint_left: float = 0.0      # seconds the hint stays unfolded on the map (data/view.json "hud".objective_hint_seconds)
var _hint_text_ok: bool = false  # the objective has a hint text
var _queue_sig: String = ""
var _pending_service: Dictionary = {}  # {actor, kind, id, service}: open its panel when the actor stands there
var _popups: Array = []  # [{node, left, gravity}] oldest first (left < 0: until clicked)
var _group_sig: String = ""
var _card_sig: String = ""
var _gold_family: String = ""
var _gold_shown: int = -1
var _frame_scene: PackedScene = preload("res://game/ui/portrait_frame.tscn")

var _game: Node = null
var tutorial: Tutorial = null    # the app's (its chapters go in the help)
var _toast_left: float = 0.0
var _last_minute: int = -1

static var _tok: Dictionary = {}


func _ready() -> void:
	_game = get_node_or_null("/root/Game")
	HudKeys.ensure()
	UiFeel.install(get_tree())
	KeyNav.install(get_tree())   # the keyboard in menus, panels and cards (verificación C13)
	TitleFit.install(get_tree())   # a panel title that does not fit in gothic takes the small letter
	_title_label.text = tr("app.title")
	_paused_label.text = tr("hud.paused")
	# 2 · status bar: icon + key on each button (docs/ui/01 §4, zone 2)
	_status_button(_ledger_button, UiIcons.ui("icon_libro"), "L", "hud.ledger_tip", toggle_ledger)
	_status_button(_tree_button, UiIcons.ui("icon_crown"), "F", "hud.tree_tip", toggle_tree)
	_status_button(_inventory_button, UiIcons.ui("icon_backpack"), "I", "hud.inventory_tip", toggle_character_panel)
	_status_button(_build_button, UiIcons.ui("icon_build_mode"), "B", "hud.build_tip", _build_denied)
	_build_button.disabled = true   # the building mode arrives in H6: pressed, it says why (toast)
	_status_button(_offices_button, UiIcons.mark("badge_office_mayor"), "O", "hud.offices_tip", toggle_offices)
	_status_button(_trials_button, UiIcons.mark("badge_office_judge"), "J", "hud.trials_tip", toggle_trial)
	_build_button.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_build_denied())
	_help_button.text = tr("hud.help_key")
	_help_button.tooltip_text = tr("hud.help_button_tip")
	_help_button.pressed.connect(toggle_help)
	_menu_button.text = tr("hud.menu")
	_menu_button.tooltip_text = tr("hud.menu_tip")
	_menu_button.pressed.connect(request_pause_menu)
	_debt_caption.text = tr("hud.debt_caption")
	_gold_icon.texture = UiIcons.ui(GOLD_ICON)
	_family_title.tooltip_text = tr("hud.title_rep_tip")
	# 3 · clock
	_pause_button.text = tr("hud.pause_short")
	_pause_button.tooltip_text = tr("hud.pause_tip")
	_pause_button.pressed.connect(func() -> void:
		if _game != null:
			_game.toggle_pause())
	for i: int in _speed_buttons.size():
		var b := _speed_buttons[i]
		var s: int = Game.SPEEDS[i]
		b.text = tr("hud.speed") % s
		b.tooltip_text = tr("hud.speed_tip") % [s, i + 1]  # H8: Shift+1/2/3 (1-2-3 select the group)
		b.pressed.connect(func() -> void:
			if _game != null:
				_game.set_speed(s))
	# 4 · column
	_objective_title.text = tr("hud.objective").to_upper()
	# 6 · selection
	_manage_button.text = tr("hud.manage")
	_manage_button.tooltip_text = tr("hud.manage_tip")
	_manage_button.pressed.connect(func() -> void: manage_pressed.emit(building_id))
	_buy_button.pressed.connect(func() -> void:
		var who := active_person()
		if who != "" and _game != null:
			_game.give({"type": "buy_building", "actor": who, "building": building_id}))
	_table_button.pressed.connect(func() -> void:
		var app := get_node_or_null("/root/App")
		var card := app.get_node_or_null("%InnVisitCard") as InnVisitCard if app != null else null
		if card != null and _game != null:
			card.show_for(_game.sim, building_id, active_person()))
	_selection_action.pressed.connect(toggle_character_panel)
	_toast_label.visible = false
	# panels: the orders go to Game; one management panel at a time (ManageSlot)
	if _game != null:
		for p: Control in [_character_panel, _market_panel, _board_panel, _ledger_panel, _tree_panel, _court_panel,
				_npc_panel, _mev_card, _hall_panel, _offices_panel, _trial_panel, _kin_ai_panel]:
			p.set("order_sink", _game.give)
	for p: Control in _manage_panels() + _modal_panels():
		ManageSlot.join(p)
	_ledger_panel.notice_clicked.connect(notice_action)
	_ledger_panel.visibility_changed.connect(func() -> void:
		if _ledger_panel.visible:
			_drop_urgent())   # opening the book reads the urgent pop-ups (§5)
	_hall_panel.offices_requested.connect(open_offices)
	_character_panel.kin_ai_requested.connect(open_kin_ai)
	_tree_panel.kin_ai_requested.connect(open_kin_ai)
	_trial_card.prepare_requested.connect(open_trial)
	_tree_panel.switch_requested.connect(func(id: String) -> void: select_requested.emit(id))
	_tree_panel.court_requested.connect(open_courtship)
	_character_panel.tree_requested.connect(toggle_tree)
	_character_panel.court_requested.connect(open_courtship)
	_help_panel.chapter_requested.connect(func(id: String) -> void:
		if _help_panel.visible:
			toggle_help()
		tutorial_requested.emit(id))
	Events.sim_event.connect(_on_sim_event)
	var ph := PacingHud.new()   # 03b: goals zone, «Saltar hasta…», «Nuevo» marks (game/ui/forja/pacing_hud.gd)
	ph.name = "PacingHud"
	add_child(ph)
	ph.mount(self)
	Log.info("Hud", "ready (zones=%d, manage panels=%d, modals=%d)" % [HudLayout.ZONES.size(), _manage_panels().size(),
		_modal_panels().size()])
	_refresh()


func _exit_tree() -> void:
	UiFeel.uninstall()


## A status bar button: its 16 px icon, the key in small letters after it, the tooltip, what it does.
func _status_button(b: Button, icon: Texture2D, key: String, tip: String, action: Callable) -> void:
	b.icon = icon
	b.text = key
	b.theme_type_variation = &"KeyButton"
	b.tooltip_text = tr(tip)
	b.pressed.connect(action)


## The panels of zone 5 (one at a time).
func _manage_panels() -> Array[Control]:
	return [_market_panel, _board_panel, _ledger_panel, _npc_panel, _court_panel, _hall_panel, _kin_ai_panel,
		_character_panel]


## The big modals (912×440 over the veil).
func _modal_panels() -> Array[Control]:
	return [_tree_panel, _offices_panel, _trial_panel]


func _process(delta: float) -> void:
	_refresh()
	if _game != null and _game.sim != null:
		_mev_card.follow(_game.sim, selected_id)
	_check_service()
	_tick_popups(delta)
	_tick_hint(delta)
	_veil.visible = _modal_panels().any(func(p: Control) -> bool: return p.visible)
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
	_paused_tag.visible = _game.paused
	_pause_button.set_pressed_no_signal(_game.paused)
	for i: int in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(not _game.paused and Game.SPEEDS[i] == _game.speed)
	_phase_bar.value = DayNight.phase_progress(minute, _game.step_fraction(), sim.catalog.time) * 100.0
	_trials_button.visible = family() != "" and not Tribunal.of_family(sim, family(), true).is_empty()  # H11
	_refresh_family(sim)
	_refresh_group(sim)
	_refresh_queue(sim)
	if minute == _last_minute:
		return
	_last_minute = minute
	_update_building_panel()   # the idle reason follows the queue
	var t := sim.now()
	_time_label.text = tr("hud.time") % [t["hour"], t["minute"]]
	var season := tr("season." + str(t["season"]))
	_fit(_date_label, [tr("hud.date") % [t["day"], season, t["year"]], tr("hud.date_short") % [t["day"], season, t["year"]],
		tr("hud.date_shortest") % [season, t["year"]]])   # the clock's line never cuts (verificación B10)
	_date_label.tooltip_text = tr("hud.date") % [t["day"], season, t["year"]]
	var night := str(t["phase"]) in ["dusk", "night"]
	_sun_moon.texture = UiIcons.ui("icon_moon" if night else "icon_sun")
	_clock_panel.tooltip_text = tr("hud.clock") % [t["day"], tr("season." + str(t["season"])), t["year"], t["hour"],
		t["minute"], tr("phase." + str(t["phase"]))]
	var ev_line := SimQuery.events_line(sim)  # H13 (zone 3): «Guerra 5 d +1» next to the time; the full list in the tip
	_event_label.visible = ev_line != ""
	_event_label.text = SimQuery.events_short(sim)
	_event_label.tooltip_text = tr("hud.event_tip") % ev_line if ev_line != "" else ""


## The person picked on the map or inside ("" = nobody).
func set_selected(id: String) -> void:
	selected_id = id
	_queue_sig = "-"
	_card_sig = ""
	if _game != null and _game.sim != null:
		_character_panel.setup(_game.sim, id)
		if _npc_panel.visible:
			_npc_panel.setup(_game.sim, id, _npc_panel.target)  # H7: the new selected person acts
	if id == "":
		_character_panel.close()
	_update_building_panel()


## The building picked on the map ("" = none): its name and the Manage button.
func set_building(id: String) -> void:
	building_id = id
	_update_building_panel()


func set_interior(open: bool) -> void:
	interior_open = open
	_update_building_panel()


# --- 6 · selection ---------------------------------------------------------------------------------------------------

## The selection bar: the picked building (Manage on your own), else the selected person; hidden inside a building
## (the interior draws its own bar there).
func _update_building_panel() -> void:
	if _game == null or _game.sim == null or interior_open:
		_building_panel.visible = false
		return
	var sim: Sim = _game.sim
	if building_id != "" and sim.state.buildings.has(building_id):
		_show_building(sim)
	elif _selected_person(sim) != "":
		_show_person(sim, _selected_person(sim))
	else:
		_building_panel.visible = false


func _show_building(sim: Sim) -> void:
	_building_panel.visible = true
	var own := false
	for id: String in sim.state.characters:
		var ch: Dictionary = sim.state.characters[id]
		if str(ch.get("controlled_by", "")) == "human" and SimQuery.is_own(sim.state, id, building_id):
			own = true
	_building_name.text = SimQuery.building_label(sim.state, sim.catalog, building_id)
	var color := "texto_tenue"
	var icon := "icon_llave"
	if own:
		icon = "icon_profesion_herrero"
		_building_hint.text = tr("hud.building_own")
		# H5: the idle icon over the building, explained (why the employees stand still)
		if not SimQuery.idle_employees(sim, building_id).is_empty():
			var why := str(SimQuery.queue_view(sim, building_id).get("stalled", ""))
			_building_hint.text = tr("hud.building_idle") % (SimQuery.reason_text(why) if why != "" else
				tr("hud.building_idle_unknown"))
			color = "aviso"
	elif bool(sim.state.buildings[building_id].get("for_sale", false)):
		icon = "icon_llave"   # posada: for sale (the Taberna-Posada), bought with the Buy button
		_building_hint.text = tr("hud.building_for_sale") % Inn.sale_price(sim, building_id)
		color = "oro"
	elif SimQuery.is_public(sim.state, sim.catalog, building_id):
		icon = "icon_serving"
		_building_hint.text = tr("hud.building_public")
	else:
		_building_hint.text = tr("hud.building_other")
	_building_hint.add_theme_color_override("font_color", token(color))
	_selection_icon.texture = UiIcons.ui(icon, false)
	_manage_button.disabled = not own
	_manage_button.visible = own  # another family's building cannot be managed (GDD 4.5.5)
	_selection_action.visible = false
	var sale := bool(sim.state.buildings[building_id].get("for_sale", false))
	_buy_button.visible = sale
	_table_button.visible = show_table_button(sim, building_id)
	_table_button.text = tr("hud.inn_table")
	_table_button.tooltip_text = tr("hud.inn_table_tip")
	if sale:
		var price := Inn.sale_price(sim, building_id)
		_buy_button.text = tr("hud.buy_building") % price
		_buy_button.disabled = not Money.can_pay(sim.state, family(), price)
		_buy_button.tooltip_text = tr("ui.why.bet_gold") % [price, Money.gold(sim.state, family())] \
			if _buy_button.disabled else tr("hud.buy_building_tip")   # an off button says why (verificación A7)


## posada: «Jugar en la mesa» for another family's Taberna-Posada with its gaming table (the card says whether one
## can sit now: the turn, the door, the owner).
func show_table_button(sim: Sim, bld: String) -> bool:
	if not Inn.is_inn(sim, bld) or not InnGames.has_table(sim, bld):
		return false
	var owner := str(sim.state.buildings[bld].get("owner", ""))
	return owner != "" and owner != family()


## The selected person (alive) or "".
func _selected_person(sim: Sim) -> String:
	var ch: Dictionary = sim.state.characters.get(selected_id, {})
	return selected_id if not ch.is_empty() and bool(ch.get("alive", true)) else ""


func _show_person(sim: Sim, who: String) -> void:
	_building_panel.visible = true
	var ch: Dictionary = sim.state.characters[who]
	_building_name.text = str(ch.get("name", who))
	var lines := SimQuery.queue_lines(sim, who, _game.pending(), _game.paused)
	_building_hint.text = lines[0] if not lines.is_empty() else tr("hud.selection_free")
	_building_hint.add_theme_color_override("font_color", token("texto_tenue"))
	_selection_icon.texture = UiIcons.ui("icon_working" if not lines.is_empty() else "icon_idle", false)
	_manage_button.visible = false
	_buy_button.visible = false
	_table_button.visible = false
	_selection_action.visible = str(ch.get("controlled_by", "")) == "human"
	_selection_action.text = tr("hud.inventory")
	_selection_action.tooltip_text = tr("hud.inventory_tip")


## A colour of the UI tokens (tools/ui/tokens.json "color").
static func token(id: String) -> Color:
	if _tok.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/ui/tokens.json"))
		_tok = (d as Dictionary).get("color", {}) if d is Dictionary else {}
	return Color.html(str(_tok.get(id, "#ece4d2")))


func toggle_character_panel() -> void:
	if _character_panel.visible:
		_character_panel.close()
	elif selected_id != "":
		_character_panel.setup(_game.sim, selected_id)
		_character_panel.open()


## B: the building mode arrives in H6 (the button is disabled; pressed, it says why).
func _build_denied() -> void:
	show_toast(tr("hud.build_later"))


## ESC: closes the top thing (docs/ui/01 §2): a card, the help, the management panel or big modal, then the picked
## building. False if there was nothing to close (the app then asks for the pause menu).
func close_top() -> bool:
	if _confirm.visible:
		_confirm.cancel()
		return true
	for c: Control in [_trial_card, _office_card, _title_card]:
		if c.visible:
			c.call("close")
			return true
	if _help_panel.visible:
		toggle_help()
		return true
	for p: Control in _modal_panels() + _manage_panels():
		if p.visible:
			p.call("close")
			return true
	if building_id != "" and not interior_open:
		deselect_requested.emit()
		set_building("")
		return true
	return false


## The pause menu is asked for (ESC with nothing open, or the Menu button): pause_menu_requested.
func request_pause_menu() -> void:
	Log.info("Hud", "pause menu requested")
	pause_menu_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _game == null or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	if HelpPanel.is_help_key(event):
		toggle_help()
	elif _speed_key(event) >= 0:
		_game.set_speed(Game.SPEEDS[_speed_key(event)])   # D4: Shift+1/2/3
	elif _group_key(event) >= 0:
		pick_group(_group_key(event))   # H8: 1-2-3 the group (GDD 4.10.5)
	elif HudKeys.pressed(event, "family_tree"):
		toggle_tree()
	elif HudKeys.pressed(event, "inventory"):
		toggle_character_panel()
	elif HudKeys.pressed(event, "ledger"):
		toggle_ledger()
	elif HudKeys.pressed(event, "offices"):  # H10: the offices
		toggle_offices()
	elif HudKeys.pressed(event, "trials"):  # H11: the trial
		toggle_trial()
	elif HudKeys.pressed(event, "build_mode"):
		_build_denied()
	elif HudKeys.pressed(event, "region_map") and not interior_open:
		region_requested.emit()
	elif HudKeys.pressed(event, "region_map") and interior_open:
		show_toast(tr("ui.hud.map_not_inside"))   # verificación C13: say it instead of doing nothing
	elif interior_open and _camera_key(event):
		show_toast(tr("ui.hud.camera_not_inside"))
	elif event.is_action_pressed("pause_toggle"):
		_game.toggle_pause()
	else:
		return
	get_viewport().set_input_as_handled()


## The first of `forms` (longest first) that fits `l` as it is laid out now; the last one if none does.
static func _fit(l: Label, forms: Array) -> void:
	l.set_meta("fit_forms", forms)
	if not l.resized.is_connected(_refit.bind(l)):   # the card lays out after the text: fit again when it does
		l.resized.connect(_refit.bind(l))
	var font := l.get_theme_font("font")
	var size := l.get_theme_font_size("font_size")
	var room := l.size.x if l.size.x > 1.0 else 9999.0
	for f: Variant in forms:
		if font.get_string_size(str(f), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= room:
			l.text = str(f)
			return
	l.text = str(forms[forms.size() - 1])


static func _refit(l: Label) -> void:
	var forms: Array = l.get_meta("fit_forms", [])
	if forms.is_empty():
		return
	var font := l.get_theme_font("font")
	var size := l.get_theme_font_size("font_size")
	for f: Variant in forms:
		if font.get_string_size(str(f), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= l.size.x:
			if l.text != str(f):
				l.text = str(f)
			return
	l.text = str(forms[forms.size() - 1])


## A camera key (WASD, arrows) that is not also a key of the building's panels (A is the storage there).
func _camera_key(event: InputEvent) -> bool:
	for a: String in ["cam_left", "cam_right", "cam_up", "cam_down"]:
		if event.is_action_pressed(a, false, true):
			for p: String in ["panel_production", "panel_storage", "panel_staff", "panel_upgrades"]:
				if HudKeys.pressed(event, p):
					return false
			return true
	return false


func _speed_key(event: InputEvent) -> int:
	for i: int in 3:
		if HudKeys.pressed(event, "speed_%d" % (i + 1)):
			return i
	return -1


func _group_key(event: InputEvent) -> int:
	for i: int in 3:
		if HudKeys.pressed(event, "group_%d" % (i + 1)):
			return i
	return -1


func _on_sim_event(e: Dictionary) -> void:
	if str(e.get("type", "")) == "title_granted":  # H9: the ceremony of the player's family
		if str(_game.sim.state.families.get(str(e.get("family", "")), {}).get("controlled_by", "")) == "human":
			_hall_panel.close()
			_title_card.show_for(_game.sim, e)
		return
	if str(e.get("type", "")) in ["trial_opened", "trial_hearing", "trial_verdict"]:  # H11: the court
		_on_trial_event(e)
		return
	if str(e.get("type", "")) == "election_held":  # H10: the vote of an election the player's family stood in
		if OfficeCard.concerns_human(_game.sim, e):
			_office_card.show_for(_game.sim, e)
		return
	if str(e.get("type", "")) == "notice_added":
		_on_notice(e)
		return
	if str(e.get("type", "")) != "order_refused":
		return
	var ch: Dictionary = _game.sim.state.characters.get(str(e.get("actor", "")), {})
	if not ch.is_empty() and str(ch.get("controlled_by", "")) != "human":
		return
	show_toast(tr("reason." + str(e.get("reason", ""))))


## A short message over the selection bar (a refused order says why).
## 03b: the goals zone, «Saltar hasta…» and the unlock marks.
func pacing() -> PacingHud:
	return get_node_or_null("PacingHud") as PacingHud


func show_toast(text: String) -> void:
	_toast_text.text = text
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


## The person the card speaks of: the selected one if of the shown family, else its head.
func active_person() -> String:
	var sim: Sim = _game.sim
	var fam := family()
	if fam == "":
		return ""
	if str(sim.state.characters.get(selected_id, {}).get("family", "")) == fam and _selected_person(sim) != "":
		return selected_id
	return Kin.head(sim.state, fam)


func _refresh_family(sim: Sim) -> void:
	var fam := family()
	_card.visible = fam != ""
	_status_bar.visible = fam != ""
	if fam == "":
		_objective_panel.visible = false
		return
	var who := active_person()
	var title := Titles.current(sim, fam)
	var gold := Money.gold(sim.state, fam)
	var rep := Reputation.of(sim.state, fam)
	var sig := "%s|%s|%d|%s|%d" % [fam, who, gold, title, rep]
	if sig != _card_sig:
		_card_sig = sig
		_name_label.text = str(sim.state.characters.get(who, {}).get("name", ""))
		if fam == _gold_family and _gold_shown >= 0 and gold != _gold_shown:
			UiAnim.gold_change(_family_gold, _gold_shown, gold)   # counts and «+42» rises (00 §8)
		else:
			_family_gold.text = str(gold)
		_gold_family = fam
		_gold_shown = gold
		_family_gold.tooltip_text = tr("hud.family_gold") % gold
		_title_badge.texture = UiIcons.mark("badge_title_" + title)
		# with two or three portraits the card has room for the reputation only (the title is in the badge and the tooltip)
		var full := tr("hud.title_rep") % [SimQuery.title_name(title).capitalize(), rep]
		if Kin.group(sim.state, fam).size() < 2:
			_fit(_family_title, [full, tr("hud.rep_short") % rep, tr("hud.rep_tight") % rep])
		else:
			_fit(_family_title, [tr("hud.rep_short") % rep, tr("hud.rep_tight") % rep, str(rep)])
		_family_title.tooltip_text = full + "\n" + tr("hud.title_rep_tip")
	_refresh_debt(sim, fam)
	_refresh_objective(sim, fam)


## Zone 2: the first open loan (figure, how much is paid, days left; red at 2 days or less).
func _refresh_debt(sim: Sim, fam: String) -> void:
	var loans := SimQuery.loans_of(sim, fam)
	for n: Control in [_debt_label, _debt_bar, _debt_days]:
		n.visible = not loans.is_empty()
	if loans.is_empty():
		_debt_caption.text = tr("hud.no_debt")
		_debt_box.tooltip_text = ""
		return
	var l: Dictionary = loans[0]
	var days := int(l.get("days_left", 0))
	var principal := maxi(1, int(l.get("principal", 1)))
	_debt_caption.text = tr("hud.debt_caption")
	_debt_label.text = str(int(l.get("outstanding", 0)))
	_debt_bar.value = 100.0 * float(principal - int(l.get("outstanding", 0))) / float(principal)
	_debt_days.text = tr("hud.debt_days") % days
	# mercado_y_libro.md §5: amber at 3 days or less, red at 1
	_debt_days.add_theme_color_override("font_color", token("negativo" if days <= 1 else ("aviso" if days <= 3 else "texto_tenue")))
	_debt_box.tooltip_text = tr("hud.debt_tip") % SimQuery.minute_label(int(l.get("due_minute", 0)) - 1)


func _refresh_objective(sim: Sim, fam: String) -> void:
	var ov := Objectives.view(sim, fam)
	var current := str(ov.get("current", ""))
	_objective_panel.visible = not ov.is_empty() and (current != "" or not (ov.get("done", []) as Array).is_empty())
	if not _objective_panel.visible:
		return
	_set_hint(current if current != "" else "free")
	if current == "":
		_objective_label.text = tr("hud.objectives_done")
		_objective_progress.text = ""
		return
	_objective_label.text = SimQuery.objective_name(sim.catalog, current)
	var parts: PackedStringArray = []
	for p: Dictionary in ov.get("progress", []):
		parts.append("%d/%d" % [int(p.get("have", 0)), int(p.get("need", 1))])
	_objective_progress.text = " · ".join(parts)


## How to do objective `id` (objective_how.<id>; "free" = after the start objectives); hidden without a text.
func _set_hint(id: String) -> void:
	var key := "objective_how." + id
	var text := tr(key)
	_hint_text_ok = text != key and text != ""
	if id != _hint_id:
		_hint_id = id
		_hint_left = float((ViewConfig.value("hud", {}) as Dictionary).get("objective_hint_seconds", 20.0))
	if _hint_text_ok and _objective_hint.text != text:
		_objective_hint.text = text
		_objective_panel.tooltip_text = text
		Log.info("Hud", "objective hint: %s" % id)
	_show_hint()


## The hint unfolds inside a building, and on the map only for a while after the objective changes or while the mouse
## is over the panel; it folds anyway when the queued orders would not fit in the column (HudLayout.fold_objective).
func _show_hint() -> void:
	var over := _objective_panel.visible and _objective_panel.get_global_rect().has_point(
		get_viewport().get_mouse_position()) if is_inside_tree() else false
	var show := HudLayout.hint_shown(_hint_text_ok, interior_open, _hint_left, over)
	if show:
		var full := _objective_panel.get_combined_minimum_size().y
		if not _objective_hint.visible:
			full += _objective_hint.get_combined_minimum_size().y + _objective_sep.get_combined_minimum_size().y + 4.0
		var queue_h := _queue_panel.get_combined_minimum_size().y if _queue_panel.visible else 0.0
		show = not HudLayout.fold_objective(full, queue_h, (HudLayout.ZONES["column"] as Rect2).size.y)
	if _objective_hint.visible != show:
		_objective_hint.visible = show
		_objective_sep.visible = show
		_objective_panel.reset_size()


func _tick_hint(delta: float) -> void:
	if _hint_left > 0.0:
		_hint_left = maxf(0.0, _hint_left - delta)
	if _objective_panel.visible:
		_show_hint()


## Whether the objective's hint is unfolded now.
func objective_hint_shown() -> bool:
	return _objective_hint.visible


## Zone 4: the active person's queued orders (the state's order queue plus the orders given in this pause).
func _refresh_queue(sim: Sim) -> void:
	var who := active_person()
	var lines: PackedStringArray = SimQuery.queue_lines(sim, who, _game.pending(), _game.paused) if who != "" else PackedStringArray()
	var sig := "%s|%s|%s" % [who, _game.paused, "|".join(lines)]
	if sig == _queue_sig:
		return
	_queue_sig = sig
	for c: Node in _queue_list.get_children():
		_queue_list.remove_child(c)
		c.queue_free()
	_queue_panel.visible = not lines.is_empty()
	if lines.is_empty():
		return
	var person := str(sim.state.characters.get(who, {}).get("name", who)).to_upper()
	_queue_label.text = (tr("hud.queue_paused") if _game.paused else tr("hud.queue_of")) % person
	for i: int in lines.size():
		var l := Label.new()
		l.text = "%d. %s" % [i + 1, lines[i]]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(220, 0)
		_queue_list.add_child(l)
	Log.info("Hud", "queue of %s: %d orders" % [who, lines.size()])


## The objective, the queue and the cards of the column (for the tests): their rects on screen.
func column_rects() -> Dictionary:
	var out := {}
	for p: Control in [_objective_panel, _queue_panel]:
		if p.visible:
			out[str(p.name)] = p.get_global_rect()
	return out


# --- F1 help ---------------------------------------------------------------------------------------------------------

## The confirmation modal (see ConfirmModal: ask(spec, on_confirm)).
func confirm_modal() -> ConfirmModal:
	return _confirm


func help_visible() -> bool:
	return _help_panel.visible


## F1, "?" or the "?" button: the help on / off (it does not pause the game), with «Ahora mismo» filled in.
func toggle_help() -> void:
	if not _help_panel.visible:
		_help_panel.set_now(now_text())
		_help_panel.set_chapters(tutorial_chapters())
	_help_panel.toggle()


## The tutorial's chapters for the help: [{id, name, desc, done, reason}].
func tutorial_chapters() -> Array:
	var out: Array = []
	if tutorial == null:
		return out
	var done := tutorial.done_chapters()
	for id: Variant in tutorial.chapter_ids():
		var ch: Dictionary = tutorial.chapters[str(id)]
		out.append({"id": str(id), "name": tr(str(ch.get("name_key", ""))), "desc": tr(str(ch.get("desc_key", ""))),
			"done": str(id) in done, "reason": tutorial.cannot_play(str(id))})
	return out


## «Ahora mismo» of the help: the current objective, how to do it and the debt's due date.
func now_text() -> String:
	if _game == null or _game.sim == null or family() == "":
		return ""
	var sim: Sim = _game.sim
	var parts: PackedStringArray = []
	var ov := Objectives.view(sim, family())
	var current := str(ov.get("current", ""))
	if current != "":
		parts.append(tr("help.now_objective") % SimQuery.objective_name(sim.catalog, current))
	var how := tr("objective_how." + (current if current != "" else "free"))
	if not how.begins_with("objective_how."):
		parts.append(how)
	var loans := SimQuery.loans_of(sim, family())
	if not loans.is_empty():
		parts.append(tr("help.now_debt") % [int(loans[0].get("outstanding", 0)),
			SimQuery.minute_label(int(loans[0].get("due_minute", 0)) - 1)])
	return " ".join(parts)


## Closes every panel (a new game was loaded).
func close_panels() -> void:
	_help_panel.visible = false
	_pending_service = {}
	for p: Control in _manage_panels() + _modal_panels() + [_title_card, _office_card, _trial_card, _confirm]:
		p.call("close")
	for n: Dictionary in _popups.duplicate():
		_drop_popup(n["node"])


## H7: the sheet of townsperson `npc` (actions on it by the selected person).
func open_npc(npc: String) -> void:
	if _game == null or _game.sim == null:
		return
	_npc_panel.setup(_game.sim, selected_id, npc)
	_npc_panel.open()


func npc_panel() -> NpcPanel:
	return _npc_panel


func microevent_card() -> MicroeventCard:
	return _mev_card


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
	_hall_panel.close()
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
	elif kind == "town_hall":
		open_town_hall(actor)
	else:
		open_market(actor, id)


func open_market(actor: String, stall: String) -> void:
	_market_panel.open_for(_game.sim, actor, stall)
	Log.info("Hud", "market panel (stall=%s, actor=%s)" % [stall, actor])


## H9: the town hall panel for `actor` (standing on its service tile).
func open_town_hall(actor: String) -> void:
	_hall_panel.open_for(_game.sim, actor)
	Log.info("Hud", "town hall panel (actor=%s)" % actor)


func town_hall_panel() -> TownHallPanel:
	return _hall_panel


## H10: the offices panel for the selected person (HUD button, key O, or the town hall's Offices button).
func open_offices(actor: String = "") -> void:
	if _game == null or _game.sim == null:
		return
	var who := actor if actor != "" else selected_id
	_offices_panel.open_for(_game.sim, who)
	Log.info("Hud", "offices panel (actor=%s)" % who)


func toggle_offices() -> void:
	if _offices_panel.visible:
		_offices_panel.close()
	else:
		open_offices()


## H11: the court's events for the player's family: a new accusation shows its card; the hearing pauses the game
## and opens the trial (docs/ui/mecanicas/tribunal.md); the verdict shows its card.
func _on_trial_event(e: Dictionary) -> void:
	var sim: Sim = _game.sim
	var fam := family()
	if fam == "":
		return
	var t := Tribunal.trial(sim.state, str(e.get("trial", "")))
	if t.is_empty():
		return
	if str(t["family"]) != fam and str(t["accuser_family"]) != fam:
		if str(e["type"]) == "trial_verdict" and _trial_panel.visible and _trial_panel.trial_id == str(t["id"]):
			_trial_panel.close()   # the judge has ruled: the trial of others is over
			return
		if str(e["type"]) == "trial_hearing" and presiding_judge(str(t["id"])) != "":   # tribunal.md §2: Presidir
			_game.set_paused(true)
			open_trial(str(t["id"]))
			show_toast(tr("ui.trial.presiding"))
		return
	match str(e["type"]):
		"trial_opened":
			if str(t["family"]) == fam:
				_trial_card.show_accusation(sim, str(t["id"]))
		"trial_hearing":
			_game.set_paused(true)
			open_trial(str(t["id"]))
		"trial_verdict":
			_trial_panel.close()
			_trial_card.show_verdict(sim, e)


## H11: the trial panel of `tid` (the family's open trial if ""), for the selected person (or the head).
func open_trial(tid: String = "") -> void:
	if _game == null or _game.sim == null:
		return
	var sim: Sim = _game.sim
	var id := tid
	if id == "":
		id = str(Tribunal.of_family(sim, family(), true).get("id", ""))
	if id == "":
		id = presided_hearing()
	if id == "":
		return
	var who := selected_id
	if who == "" or str(sim.state.characters.get(who, {}).get("family", "")) != family():
		who = Kin.head(sim.state, family())
	var t := Tribunal.trial(sim.state, id)
	if str(t.get("family", "")) != family() and str(t.get("accuser_family", "")) != family() and presiding_judge(id) != "":
		who = presiding_judge(id)   # a trial of others: the family's judge presides it
	_trial_panel.open_for(sim, who, id)
	Log.info("Hud", "trial panel (trial=%s, actor=%s)" % [id, who])


## The person of the family who presides trial `tid` as the town's judge ("" if none): tribunal.md §2 «Presidir (si
## eres Juez)», the trial of other families whose hearing the family's judge rules.
func presiding_judge(tid: String) -> String:
	if _game == null or _game.sim == null:
		return ""
	var sim: Sim = _game.sim
	for j: String in Offices.holders(sim, "judge"):
		if j != "" and str(sim.state.characters.get(j, {}).get("family", "")) == family() \
				and Tribunal.verdict_status(sim, j, tid, "guilty") in ["", "trial_not_in_hearing"]:
			return j
	return ""


## The open trial in its hearing that the family's judge presides ("" if none): J opens it.
func presided_hearing() -> String:
	if _game == null or _game.sim == null:
		return ""
	for t: Dictionary in Tribunal.open_trials(_game.sim):
		if str(t["status"]) == "hearing" and presiding_judge(str(t["id"])) != "":
			return str(t["id"])
	return ""


func toggle_trial() -> void:
	if _trial_panel.visible:
		_trial_panel.close()
	else:
		open_trial()


## H14: the AI panel of family member `whose` (the selected person gives the orders, else the head).
func open_kin_ai(whose: String = "") -> void:
	if _game == null or _game.sim == null:
		return
	var sim: Sim = _game.sim
	var who := selected_id
	if who == "" or str(sim.state.characters.get(who, {}).get("family", "")) != family():
		who = Kin.head(sim.state, family())
	_kin_ai_panel.open_for(sim, who, whose if whose != "" else who)
	Log.info("Hud", "kin AI panel (actor=%s, target=%s)" % [who, whose])


func kin_ai_panel() -> KinAiPanel:
	return _kin_ai_panel


func trial_panel() -> TrialPanel:
	return _trial_panel


func trial_card() -> TrialCard:
	return _trial_card


func offices_panel() -> OfficesPanel:
	return _offices_panel


func office_card() -> OfficeCard:
	return _office_card


func title_card() -> TitleCard:
	return _title_card


func open_board(actor: String) -> void:
	_board_panel.open_for(_game.sim, actor)
	Log.info("Hud", "board panel (actor=%s)" % actor)


## The management panel open now (zone 5, the wide one or a big modal, the interior's included), or null.
func open_manage_panel() -> Control:
	return ManageSlot.open_panel(get_tree()) if is_inside_tree() else null


## The screen rects that cover the town now (for the camera, §4.6): the management panel if one is open and the
## selection bar if shown.
func covered_rects() -> Array:
	var out: Array = []
	var open := open_manage_panel()
	if open != null and open.is_visible_in_tree():
		out.append(open.get_global_rect())
	if _building_panel.visible:
		out.append(_building_panel.get_global_rect())
	return out


# --- 7 · notices ------------------------------------------------------------------------------------------------------

## The notices of the player's family pop up by gravity (§5: urgent, warning, done; info only in the book).
func _on_notice(e: Dictionary) -> void:
	if str(e.get("family", "")) != SimQuery.player_family(_game.sim.state):
		return
	var cfg: Dictionary = ViewConfig.value("notices", {})
	var gravity := HudLayout.notice_gravity(str(e.get("severity", "")), str(e.get("key", "")),
		cfg.get("done_keys", []) as Array)
	if gravity == "":
		return
	var n := e.duplicate(true)
	var text := SimQuery.notice_text(_game.sim.state, _game.sim.catalog, n)
	var node := _notice_node(gravity, text)
	node.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			notice_action(n)
			_drop_popup(node))
	var left := -1.0 if gravity == "urgent" else float(cfg.get("done_seconds" if gravity == "done" else "popup_seconds", 8.0))
	var kept := HudLayout.push_notice(_popups, {"node": node, "gravity": gravity, "left": left}, int(cfg.get("popup_max", 3)))
	for p: Dictionary in _popups:
		if not kept.has(p):
			(p["node"] as Node).queue_free()   # the oldest goes; it stays in the book
	_popups = kept
	_notice_popups.add_child(node)
	UiAnim.notice_in(node.get_node("HBox") as Control)
	if gravity == "urgent":
		_blink(node.get_node("HBox/Stripe") as CanvasItem)
	Log.info("Hud", "notice %s: %s" % [gravity, text])


## A pop-up: dark box, the gravity's stripe and icon, the text (docs/ui/00 §5, «aviso»).
func _notice_node(gravity: String, text: String) -> PanelContainer:
	var tok := {"urgent": "negativo", "warning": "aviso", "done": "positivo"}
	var icons := {"urgent": "icon_warning", "warning": "icon_pending", "done": "icon_completed"}
	var p := PanelContainer.new()
	p.name = "Notice"
	p.theme_type_variation = &"NoticePanel"
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.tooltip_text = tr("hud.notice_tip")
	var h := HBoxContainer.new()
	h.name = "HBox"
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var stripe := ColorRect.new()
	stripe.name = "Stripe"
	stripe.custom_minimum_size = Vector2(3, 0)
	stripe.color = token(tok[gravity])
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(stripe)
	var icon := TextureRect.new()
	icon.texture = UiIcons.ui(icons[gravity])
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	var l := Label.new()
	l.name = "Text"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(196, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return p


## The urgent stripe blinks twice as it comes in (docs/ui/00 §8).
func _blink(c: CanvasItem) -> void:
	var t := c.create_tween()
	for i: int in 4:
		t.tween_callback(func() -> void: c.visible = not c.visible)
		t.tween_interval(0.08)


## The notices on screen now: [{gravity, text}] oldest first (for the tests and the smoke captures).
func shown_notices() -> Array:
	var out: Array = []
	for p: Dictionary in _popups:
		var n: Node = p["node"]
		if is_instance_valid(n):
			out.append({"gravity": str(p["gravity"]), "text": (n.get_node("HBox/Text") as Label).text})
	return out


func _drop_popup(b: Node) -> void:
	for i: int in _popups.size():
		if _popups[i]["node"] == b:
			_popups.remove_at(i)
			break
	if is_instance_valid(b):
		b.queue_free()


## Opening the book reads the urgent pop-ups: they go (they are in its Notices tab).
func _drop_urgent() -> void:
	for p: Dictionary in _popups.duplicate():
		if str(p["gravity"]) == "urgent":
			_drop_popup(p["node"])


func _tick_popups(delta: float) -> void:
	for p: Dictionary in _popups.duplicate():
		if float(p["left"]) < 0.0:
			continue   # urgent: until clicked or the book is opened
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


## The group of the player's family as portraits (key 1-2-3; the active one with the gold frame).
func _refresh_group(sim: Sim) -> void:
	var fam := family()
	var group := Kin.group(sim.state, fam) if fam != "" else []
	var heir := Kin.heir(sim, fam) if fam != "" else ""
	var who := active_person() if fam != "" else ""
	var counts := group.map(func(c: String) -> int:
		return SimQuery.queue_lines(sim, c, _game.pending(), true).size() if _game.paused else 0)
	var sig := "%s|%s|%s|%s|%s|%s" % [group, who, heir, group.map(func(c: String) -> Variant: return sim.state.characters[c].get("visual")),
		group.map(func(c: String) -> bool: return Tribunal.is_banished(sim.state, c) or Region.is_away(sim.state, c)), counts]
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
		f.show_character(sim.state, str(group[i]), {"active": str(group[i]) == who, "controlled": true,
			"heir": str(group[i]) == heir, "key": str(i + 1), "queue": int(counts[i])})
		if Tribunal.is_banished(sim.state, str(group[i])):  # H11: banished: greyed, with the day it ends
			f.modulate = Color(0.55, 0.55, 0.55)
			f.tooltip_text = tr("ui.trial.banished") % (int(sim.state.characters[str(group[i])].get("banished_until", 0)) + 1)
		if Region.is_away(sim.state, str(group[i])):  # viajes: on a trip (or driving a caravan): greyed, where it is
			f.modulate = Color(0.6, 0.6, 0.6)
			var p := Travel.progress(sim, str(group[i]))
			var where := str(p.get("at", "")) if str(p.get("state", "")) == "city" else str(p.get("to", ""))
			f.tooltip_text = tr("hud.away_tip") % tr(str(Region.settlement(sim, where).get("name_key", where)))
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
