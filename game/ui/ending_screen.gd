class_name EndingScreen
extends Control
## The end of the game (GDD 4.17, D18): shown when state.ending is set (event game_over). H3: the ruin (the moneylender
## seized the forge); H8: game_over (the head died without heir) and closed (voluntary close, D19 off). Title, what
## happened, the day, the family, the chronicle summary and the score. New game / Quit.
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


## Fills the screen with `state.ending` ({kind, family, minute}). H8 (GDD 4.17): with the sim, the chronicle summary
## (generations, the heads with their days, the highest wealth, the goals met) and the dynasty score broken down by
## kind of fact (Dynasty.summary / score), for any ending.
func show_ending(state: WorldState, sim: Sim = null) -> void:
	_bind()
	_fill_score(state, sim)
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


func _fill_score(state: WorldState, sim: Sim) -> void:
	var box := %ScoreBox as VBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	box.visible = sim != null
	if sim == null:
		return
	var fam := str(state.ending.get("family", ""))
	var sum := Dynasty.summary(sim, fam)
	var sc: Dictionary = sum["score"]
	_line(box, SimQuery.t_("ui.ending.generations") % int(sum["generation"]), true)
	for h: Dictionary in sum["heads"]:
		var to := int(h.get("to_day", -1))
		_line(box, SimQuery.t_("ui.ending.head") % [str(h["name"]), int(h["from_day"]) + 1,
			(str(to + 1) if to >= 0 else "—")], false)
	_line(box, SimQuery.t_("ui.ending.peak") % int(sum["peak"]), false)
	var goals: PackedStringArray = []
	for g: Variant in sum["goals_done"]:
		goals.append(SimQuery.t_("goal." + str(g)))
	_line(box, SimQuery.t_("ui.ending.goals") % (", ".join(goals) if not goals.is_empty() else "—"), false)
	_line(box, SimQuery.t_("ui.ending.score_title"), true)
	var kinds: Array = (sc["by_kind"] as Dictionary).keys()
	kinds.sort()
	for k: String in kinds:
		var n := int(sc["facts"].get(k, 0))
		_line(box, SimQuery.t_("ui.ending.score_line") % [SimQuery.t_("score." + k), n, int(sc["by_kind"][k])], false)
	_line(box, SimQuery.t_("ui.ending.score_total") % int(sc["total"]), true)


func _line(box: VBoxContainer, text: String, strong: bool) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11 if strong else 10)
	if strong:
		l.add_theme_color_override("font_color", Color(0.85, 0.71, 0.42))
	box.add_child(l)
