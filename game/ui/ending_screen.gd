class_name EndingScreen
extends Control
## The end of the game (GDD 4.17, D18): shown when state.ending is set (event game_over). H3 has one ending, the
## ruin (the moneylender seized the forge): title, what happened, the day and the family. New game / Quit.
## The app pauses the game while it is shown (the sim does not stop by itself).

signal new_game_pressed
signal quit_pressed

var kind: String = ""
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%NewGameButton as Button).pressed.connect(func() -> void: new_game_pressed.emit())
	(%QuitButton as Button).pressed.connect(func() -> void: quit_pressed.emit())


## Fills the screen with `state.ending` ({kind, family, minute}).
func show_ending(state: WorldState) -> void:
	_bind()
	var e: Dictionary = state.ending
	kind = str(e.get("kind", "ruin"))
	var fam: Dictionary = state.families.get(str(e.get("family", "")), {})
	var minute := int(e.get("minute", state.clock["minute"]))
	(%Title as Label).text = SimQuery.t_("ui.ending.%s.title" % kind)
	(%Body as Label).text = SimQuery.t_("ui.ending.%s.body" % kind).format({"family": str(fam.get("name", ""))})
	(%Summary as Label).text = SimQuery.t_("ui.ending.summary") % SimQuery.minute_label(minute)
	(%NewGameButton as Button).text = SimQuery.t_("ui.ending.new_game")
	(%QuitButton as Button).text = SimQuery.t_("ui.ending.quit")
	visible = true
	ViewConfig.info("Ending", "show (kind=%s, family=%s, minute=%d)" % [kind, e.get("family", ""), minute])


## While shown, no key reaches the town or the HUD below (pause, speeds, ESC): this screen is drawn over them.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and is_inside_tree():
		get_viewport().set_input_as_handled()
