class_name EndingScreen
extends MenuScreen
## The end of the game (GDD 4.17, D18; docs/ui/02_menu_inicial.md §7): shown when state.ending is set (ruin, no heir
## or voluntary close). A big parchment: the title in gothic and sealing wax by ending.kind, what happened and the
## game date, the seal top right. Left, the chronicle: the heads of the family with their portrait (dead frame), their
## days and their age at death; the facts with their mark (titles, weddings, births, offices, trials, the highest
## wealth); the dynasty goals with their box. Right, the score: one row per kind of fact (how many and points) and the
## total. Buttons: See the town (hides the parchment over the paused town, with "Back to the end"), New game, Quit to
## title. Esc does nothing (you have to choose). The app pauses the game while it is shown (the sim does not stop).
## Data: Dynasty.summary / score / goals_view, without changes in the sim.

signal new_game_pressed
signal title_pressed

const MAX_FACTS: int = 7

var kind: String = ""
var _bound: bool = false


func _ready() -> void:
	esc_goes_back = false
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	esc_goes_back = false
	(%NewGameButton as Button).pressed.connect(func() -> void: new_game_pressed.emit())
	(%TitleButton as Button).pressed.connect(func() -> void: title_pressed.emit())
	(%ViewTownButton as Button).pressed.connect(func() -> void: view_town(true))
	(%BackToEndButton as Button).pressed.connect(func() -> void: view_town(false))


## Fills the screen with `state.ending` ({kind, family, minute}). With the sim: the chronicle and the score broken down
## by kind of fact (Dynasty.summary / score), for any ending.
func show_ending(state: WorldState, sim: Sim = null) -> void:
	_bind()
	var e: Dictionary = state.ending
	kind = str(e.get("kind", "ruin"))
	var fam_id := str(e.get("family", ""))
	var fam: Dictionary = state.families.get(fam_id, {})
	var minute := int(e.get("minute", state.clock["minute"]))
	(%Title as Label).text = SimQuery.t_("ui.ending.%s.title" % kind)
	(%Body as Label).text = SimQuery.t_("ui.ending.%s.body" % kind).format({"family": str(fam.get("name", ""))})
	var time: Dictionary = sim.catalog.time if sim != null else {}
	var date := MenuKit.date_label(minute, time) if not time.is_empty() else SimQuery.minute_label(minute)
	var m := Clock.minute_of_day(minute)
	(%Summary as Label).text = SimQuery.t_("ui.ending.date") % [date, m / 60, m % 60] if not time.is_empty() else date
	(%ChronicleTitle as Label).text = SimQuery.t_("ui.ending.chronicle")
	(%GoalsTitle as Label).text = SimQuery.t_("ui.ending.goals_title")
	(%ScoreTitle as Label).text = SimQuery.t_("ui.ending.score_title")
	(%TotalLabel as Label).text = SimQuery.t_("ui.ending.total")
	(%ViewTownButton as Button).text = SimQuery.t_("ui.ending.view_town")
	(%NewGameButton as Button).text = SimQuery.t_("ui.ending.new_game")
	(%TitleButton as Button).text = SimQuery.t_("ui.ending.to_title")
	(%BackToEndButton as Button).text = SimQuery.t_("ui.ending.back_to_end")
	_fill(state, sim, fam_id)
	view_town(false)
	open()
	ViewConfig.info("Ending", "show (kind=%s, family=%s, minute=%d)" % [kind, fam_id, minute])


## Hides the parchment to look at the town (paused), or shows it again.
func view_town(on: bool) -> void:
	(%Veil as Control).visible = not on
	(%Center as Control).visible = not on
	(%BackToEnd as Control).visible = on
	mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP
	if visible:
		if on:
			(%BackToEndButton as Button).grab_focus.call_deferred()
		else:
			focus_default.call_deferred()


func is_viewing_town() -> bool:
	return (%BackToEnd as Control).visible


func default_focus() -> Control:
	return (%BackToEndButton as Button) if is_viewing_town() else (%NewGameButton as Button)


func _fill(state: WorldState, sim: Sim, fam: String) -> void:
	var heads := %Heads as VBoxContainer
	var facts := %Facts as VBoxContainer
	var goals := %Goals as VBoxContainer
	var score := %ScoreRows as VBoxContainer
	for box: Node in [heads, facts, goals, score]:
		MenuKit.clear(box)
	(%Columns as Control).visible = sim != null
	(%TotalValue as Label).text = ""
	if sim == null:
		return
	var sum := Dynasty.summary(sim, fam)
	for h: Dictionary in sum["heads"]:
		heads.add_child(_head_row(sim, h))
	var lines := _fact_lines(sim, fam)
	for i: int in mini(lines.size(), MAX_FACTS):
		facts.add_child(_mark_row(lines[i][0], str(lines[i][1]), &"InkLabel"))
	if int(sum["peak"]) > 0:
		facts.add_child(_mark_row("wealth", SimQuery.t_("ui.ending.fact.wealth_peak") % MenuKit.gold_text(int(sum["peak"])),
			&"InkLabel"))
	for g: Dictionary in Dynasty.goals_view(sim, fam):
		goals.add_child(_mark_row("goal_done" if bool(g["done"]) else "goal_open", SimQuery.t_(str(g["name_key"])),
			&"InkLabel"))
	var sc: Dictionary = sum["score"]
	var kinds: Array = (sc["by_kind"] as Dictionary).keys()
	kinds.sort()
	for k: String in kinds:
		var row := HBoxContainer.new()
		row.name = "Score_" + k
		var name_l := MenuKit.label(SimQuery.t_("score." + k), &"InkLabel")
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var n := MenuKit.label(str(int(sc["facts"].get(k, 0))) if k != "wealth_peak" else "", &"InkLabel")
		n.custom_minimum_size = Vector2(40, 0)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(n)
		var pts := MenuKit.label(str(int(sc["by_kind"][k])), &"InkBold")
		pts.name = "Points"
		pts.custom_minimum_size = Vector2(56, 0)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pts)
		score.add_child(row)
	(%TotalValue as Label).text = SimQuery.t_("ui.ending.points") % int(sc["total"])


func _head_row(sim: Sim, h: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var frame: Control = (load("res://game/ui/portrait_frame.tscn") as PackedScene).instantiate()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)
	frame.call("show_character", sim.state, str(h["character"]), {"controlled": false})
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fam_name := str(sim.state.families.get(str(sim.state.characters.get(str(h["character"]), {}).get("family", "")), {}).get("name", ""))
	texts.add_child(MenuKit.label(SimQuery.t_("ui.new_game.preview_name") % [str(h["name"]), fam_name], &"InkBold"))
	var to := int(h.get("to_day", -1))
	var line := SimQuery.t_("ui.ending.head_days") % [int(h["from_day"]) + 1, (str(to + 1) if to >= 0 else "—")]
	var ch: Dictionary = sim.state.characters.get(str(h["character"]), {})
	if not bool(ch.get("alive", true)) and int(ch.get("death_day", -1)) >= 0:
		var age := Clock.age_years(int(ch.get("birth_day", 0)), int(ch["death_day"]) * Clock.MINUTES_PER_DAY, sim.catalog.time)
		line += " · " + SimQuery.t_("ui.family.age_dead") % age
	texts.add_child(MenuKit.label(line, &"InkLabel"))
	row.add_child(texts)
	return row


## [mark, text] of the family's chronicle facts that tell its story, oldest first.
func _fact_lines(sim: Sim, fam: String) -> Array:
	var out: Array = []
	var st := sim.state
	for e: Dictionary in st.chronicle:
		if str(e.get("family", "")) != fam:
			continue
		var d := Clock.day(int(e.get("minute", 0))) + 1
		var k := str(e.get("kind", ""))
		match k:
			"title":
				var t := SimQuery.t_("title." + str(e.get("title", "")))
				out.append(["title_" + str(e.get("title", "")), SimQuery.t_("ui.ending.fact.title") % [t.substr(0, 1).to_upper() + t.substr(1), d]])
			"wedding":
				out.append(["wedding", SimQuery.t_("ui.ending.fact.wedding") % [_name(st, str(e.get("spouse", ""))), d]])
			"birth":
				out.append(["birth", SimQuery.t_("ui.ending.fact.birth") % [_name(st, str(e.get("character", ""))), d]])
			"inheritance":
				out.append(["inheritance", SimQuery.t_("ui.ending.fact.inheritance") % [_name(st, str(e.get("heir", ""))), d]])
			"office_won":
				out.append(["office_" + str(e.get("office", "")), SimQuery.t_("ui.ending.fact.office") % [SimQuery.office_name(str(e.get("office", ""))), d]])
			"trial_won":
				out.append(["trial", SimQuery.t_("ui.ending.fact.trial_won") % d])
			"sentence":
				out.append(["sentence", SimQuery.t_("ui.ending.fact.sentence") % d])
			"goal_done":
				out.append(["goal_done", SimQuery.t_("ui.ending.fact.goal") % SimQuery.t_("goal." + str(e.get("goal", "")))])
			"building_acquired":
				out.append(["building", SimQuery.t_("ui.ending.fact.building") % d])
	return out


func _name(st: WorldState, chr: String) -> String:
	return str(st.characters.get(chr, {}).get("name", "?"))


## A fact with its mark: the title or office badge of the kit, the boxes of the goals, else a small ink square.
func _mark_row(mark: String, text: String, variation: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var tex: Texture2D = null
	var path := ""
	if mark.begins_with("title_"):
		path = "res://assets/art/ui/marks/badge_%s.png" % mark
	elif mark.begins_with("office_"):
		path = "res://assets/art/ui/marks/badge_%s.png" % mark
	elif mark == "goal_done":
		path = "res://assets/art/ui/theme/check_on.png"
	elif mark == "goal_open":
		path = "res://assets/art/ui/theme/check_off.png"
	elif mark in ["wedding", "inheritance", "trial", "goal"]:
		path = "res://assets/art/ui/marks/seal.png"
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(16, 16)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr)
	else:
		var sq := ColorRect.new()
		sq.color = ViewConfig.color("#2a1f14")
		sq.custom_minimum_size = Vector2(6, 6)
		sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var hold := CenterContainer.new()
		hold.custom_minimum_size = Vector2(16, 16)
		hold.add_child(sq)
		row.add_child(hold)
	var l := MenuKit.label(text, variation)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row
