extends CanvasLayer
## HUD of the town (H1): clock (time, date, sun/moon, phase bar, tooltip with the full date), pause and speeds
## ×1/×2/×4 (D4) by button or key (pause_toggle = Space, speed_1/2/3 = 1/2/3), the "paused" sign and a short
## message when the sim refuses an order of the human family (tr("reason.<id>")). Reads Game; only changes the
## session's speed and pause, never the world.
## H2: the selected person (portrait, name, gold) with their order queue as a numbered list (active pause, GDD 4.1:
## the state's order_queue plus the orders given during this pause), the button / key I of their panel
## (CharacterPanel), and the picked building with its "Manage" button (GDD 4.6.4).

signal manage_pressed(building_id: String)

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

var selected_id: String = ""
var building_id: String = ""
var interior_open: bool = false
var _queue_sig: String = ""

var _game: Node = null
var _toast_left: float = 0.0
var _last_minute: int = -1


func _ready() -> void:
	_game = get_node_or_null("/root/Game")
	_paused_label.text = tr("hud.paused")
	_help_label.text = tr("hud.help")
	_title_label.text = tr("app.title")
	_pause_button.text = tr("hud.pause")
	_pause_button.tooltip_text = tr("hud.pause_tip")
	_pause_button.pressed.connect(func() -> void: _game.toggle_pause())
	var group := ButtonGroup.new()
	for i: int in _speed_buttons.size():
		var b := _speed_buttons[i]
		var s: int = Game.SPEEDS[i]
		b.text = tr("hud.speed") % s
		b.tooltip_text = tr("hud.speed_tip") % [s, i + 1]
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
	Events.sim_event.connect(_on_sim_event)
	_refresh()


func _process(delta: float) -> void:
	_refresh()
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
	if minute == _last_minute:
		return
	_last_minute = minute
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
	_help_label.text = tr("hud.help_interior" if open else "hud.help")
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
	_building_name.text = SimQuery.building_name(sim.state, sim.catalog, building_id)
	_building_hint.text = tr("hud.building_own" if own else "hud.building_other")
	_manage_button.disabled = not own


func toggle_character_panel() -> void:
	if _character_panel.visible:
		_character_panel.close()
	elif selected_id != "":
		_character_panel.setup(_game.sim, selected_id)
		_character_panel.open()


## ESC: closes the character panel if open. False if there was nothing to close.
func close_top() -> bool:
	if _character_panel.visible:
		_character_panel.close()
		return true
	return false


func _refresh_selected(sim: Sim) -> void:
	var ch: Dictionary = sim.state.characters.get(selected_id, {})
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
	if (event as InputEventKey).keycode == KEY_I:
		toggle_character_panel()
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
