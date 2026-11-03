class_name TitleScreen
extends MenuScreen
## The title screen (docs/ui/02_menu_inicial.md §1): the logo, the column of buttons over a stepped veil on the left
## and the version, over the real town paused at dusk (decision 2). Continue (only with a readable saved game: the
## most recent one, autosave or slot) with the family and the game date below; New game; Load (off with its reason
## when there is nothing saved); Options; Credits; Quit (no confirmation: there is nothing to lose). The app does
## what each button asks. While another menu is open over it (load, options, credits) the column hides (covered).

signal continue_pressed(slot: String)
signal new_game_pressed
signal load_pressed
signal options_pressed
signal credits_pressed
signal quit_pressed

var continue_slot: String = ""   # the slot Continue loads ("" = none)
var time_config: Dictionary = {}  # the catalog's calendar (for the date line)
var _bound: bool = false


func _ready() -> void:
	esc_goes_back = false
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%ContinueButton as Button).pressed.connect(func() -> void: continue_pressed.emit(continue_slot))
	(%NewGameButton as Button).pressed.connect(func() -> void: new_game_pressed.emit())
	(%LoadButton as Button).pressed.connect(func() -> void: load_pressed.emit())
	(%OptionsButton as Button).pressed.connect(func() -> void: options_pressed.emit())
	(%CreditsButton as Button).pressed.connect(func() -> void: credits_pressed.emit())
	(%QuitButton as Button).pressed.connect(func() -> void: quit_pressed.emit())


func _refresh() -> void:
	_bind()
	set_covered(false)
	var last := SaveSlots.most_recent()
	continue_slot = str(last.get("slot", ""))
	var has_save := continue_slot != ""
	(%ContinueButton as Button).visible = has_save
	(%ContinueInfo as Label).visible = has_save
	if has_save:
		(%ContinueInfo as Label).text = MenuKit.continue_label(last["header"], time_config)
	var any_file := false
	for e: Dictionary in SaveSlots.list(true):
		any_file = any_file or bool(e["exists"])
	(%LoadButton as Button).disabled = not any_file
	(%LoadReason as Label).visible = not any_file
	(%ContinueButton as Button).text = SimQuery.t_("ui.title.continue")
	(%NewGameButton as Button).text = SimQuery.t_("ui.title.new_game")
	(%LoadButton as Button).text = SimQuery.t_("ui.title.load")
	(%LoadReason as Label).text = SimQuery.t_("ui.title.no_saves")
	(%OptionsButton as Button).text = SimQuery.t_("ui.title.options")
	(%CreditsButton as Button).text = SimQuery.t_("ui.title.credits")
	(%QuitButton as Button).text = SimQuery.t_("ui.title.quit")
	(%Version as Label).text = SimQuery.t_("ui.title.version") % str(ProjectSettings.get_setting("application/config/version", ""))
	ViewConfig.info("Title", "refresh (continue=%s, any_file=%s)" % [continue_slot, any_file])


## Another menu is drawn over the title: the column and the logo hide (the town and the music stay).
func set_covered(covered: bool) -> void:
	(%Column as Control).visible = not covered
	(%Logo as Control).visible = not covered
	(%Veil as Control).visible = not covered
	(%Version as Control).visible = not covered
	if not covered and visible:
		focus_default.call_deferred()


func is_covered() -> bool:
	return not (%Column as Control).visible


## The first useful button: Continue if there is a game, else New game (first time). None while covered.
func default_focus() -> Control:
	if is_covered():
		return null
	return (%ContinueButton as Button) if (%ContinueButton as Button).visible else (%NewGameButton as Button)
