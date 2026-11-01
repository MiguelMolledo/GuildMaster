extends CanvasLayer
## HUD of the town (H1): clock (time, date, sun/moon, phase bar, tooltip with the full date), pause and speeds
## ×1/×2/×4 (D4) by button or key (pause_toggle = Space, speed_1/2/3 = 1/2/3), the "paused" sign and a short
## message when the sim refuses an order of the human family (tr("reason.<id>")). Reads Game; only changes the
## session's speed and pause, never the world.

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
	if minute == _last_minute:
		return
	_last_minute = minute
	var t := sim.now()
	_time_label.text = tr("hud.time") % [t["hour"], t["minute"]]
	_date_label.text = tr("hud.date") % [t["day"], tr("season." + str(t["season"])), t["year"]]
	_sun_moon.phase = str(t["phase"])
	_clock_panel.tooltip_text = tr("hud.clock") % [t["day"], tr("season." + str(t["season"])), t["year"], t["hour"],
		t["minute"], tr("phase." + str(t["phase"]))]


func _unhandled_input(event: InputEvent) -> void:
	if _game == null or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("pause_toggle"):
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
