extends "res://tests/test_case.gd"
## The tutorial's engine (docs/ui/05_tutorial.md): a trigger moves the step on, Next against an action, a condition
## of the state, a step skipped by its "if", the end of a chapter, a hidden target lights what opens it, the focus
## follows the node when it moves, the first-time hints (seen, off, not during a chapter), the data in data/tutorial/
## and the progress kept out of the saved game.


class FakeCtx extends TutorialContext:
	var roots: Array = []
	var values: Dictionary = {}     # condition name -> bool
	var family_events: bool = true

	func ui_roots() -> Array:
		return roots

	func state_value(name: String, _t: Dictionary) -> bool:
		return bool(values.get(name, false))

	func mine(_e: Dictionary) -> bool:
		return family_events


const SCENE: String = "res://game/ui/tutorial/tutorial.tscn"


## A tutorial in the tree with chapter "t" made of `steps` (and the data's openers), progress in memory.
func _tutorial(steps: Array, ctx: TutorialContext = null, extra: Dictionary = {}) -> Tutorial:
	var tut: Tutorial = (load(SCENE) as PackedScene).instantiate()
	tut._ready()   # outside the tree (the tests run before the main loop)
	tut.use_settings = false
	tut.memory = {"game/tutorial_hints": true, "game/tutorial_guided": false, "tutorial/done": [], "tutorial/seen": []}
	tut.config = {"chapters": ["t", "u"], "openers": extra.get("openers", {}), "hints": extra.get("hints", []),
		"look": {"pad": 3}}
	tut.chapters = {"t": {"id": "t", "name_key": "tutorial.chapter.first_steps", "steps": steps},
		"u": {"id": "u", "name_key": "tutorial.chapter.produce", "steps": [{"id": "a", "text": "x", "advance": "next"}]}}
	tut.setup(ctx if ctx != null else FakeCtx.new())
	return tut


func _button(name: String, at: Vector2, parent: Node) -> Button:
	var b := Button.new()
	b.name = name
	b.position = at
	b.size = Vector2(40, 16)
	parent.add_child(b)
	return b


func test_a_trigger_moves_the_step_on() -> void:
	var tut := _tutorial([
		{"id": "ingots", "text": "x", "advance": "action",
			"done": {"sim": "work_done", "match": {"item": "iron_ingot"}, "count": 2}},
		{"id": "menu", "text": "x", "when": {"ui": "panel_opened", "match": {"panel": "StationMenu"}}, "advance": "next"},
	])
	tut.start("t")
	eq(tut.phase, "show", "the first step shows at once")
	tut.on_event("sim", "work_done", {"item": "coal"})
	tut.on_event("sim", "work_done", {"item": "iron_ingot"})
	eq(tut.index, 0, "one ingot is not two")
	tut.on_event("ui", "work_done", {"item": "iron_ingot"})
	eq(tut.index, 0, "a UI event of the same name is not the sim's")
	tut.on_event("sim", "work_done", {"item": "iron_ingot"})
	eq(tut.index, 1, "the second ingot moves it on")
	eq(tut.phase, "wait", "the next one waits for its trigger")
	tut.on_event("ui", "panel_opened", {"panel": "StoragePanel"})
	eq(tut.phase, "wait", "another panel does not show it")
	tut.on_event("ui", "panel_opened", {"panel": "StationMenu", "zone": "furnace"})
	eq(tut.phase, "show", "its panel shows it")
	tut.free()


func test_events_of_other_families_do_not_count() -> void:
	var ctx := FakeCtx.new()
	ctx.family_events = false
	var tut := _tutorial([{"id": "a", "text": "x", "advance": "action", "done": {"sim": "market_sold"}},
		{"id": "b", "text": "x", "advance": "action", "done": {"sim": "world_event_started", "anyone": true}}], ctx)
	tut.start("t")
	tut.on_event("sim", "market_sold", {"actor": "chr_rival"})
	eq(tut.index, 0, "the rival's sale is not yours")
	tut.skip_step()
	tut.on_event("sim", "world_event_started", {"event": "war"})
	eq(tut.phase, "finished", "anyone: true takes everybody's")
	tut.free()


func test_next_only_explains_and_an_action_needs_the_action() -> void:
	var tut := _tutorial([
		{"id": "explain", "text": "x", "advance": "next"},
		{"id": "do", "text": "x", "advance": "action", "done": {"ui": "order_given", "match": {"type": "move_to"}}},
	])
	tut.start("t")
	tut.on_event("ui", "order_given", {"type": "move_to"})
	eq(tut.index, 0, "an event does not pass a step that only explains")
	tut.paint()
	check(tut.overlay.card.press("next"), "it has «Siguiente»")
	eq(tut.index, 1, "Next passes it")
	tut.next()
	eq(tut.index, 1, "Next does not pass an action")
	tut.paint()
	check(tut.overlay.card.button("next") == null and tut.overlay.card.button("skip") != null, "an action offers Skip, not Next")
	tut.on_event("ui", "order_given", {"type": "work_at"})
	eq(tut.index, 1, "another order is not it")
	tut.on_event("ui", "order_given", {"type": "move_to", "actor": "chr_0001"})
	eq(tut.phase, "finished", "the order passes it: the chapter ends")
	tut.free()


func test_a_condition_of_the_state_and_the_if() -> void:
	var ctx := FakeCtx.new()
	var tut := _tutorial([
		{"id": "resume", "text": "x", "advance": "action", "done": {"state": "paused", "is": false}},
		{"id": "trial", "text": "x", "advance": "next", "if": {"state": "has_trial", "is": true}},
		{"id": "end", "text": "x", "advance": "next"},
	], ctx)
	tut.start("t")
	tut.tick(0.1)
	eq(tut.index, 0, "not yet")
	ctx.values["paused"] = true
	tut.tick(0.1)
	eq(tut.step().get("id", ""), "end", "the condition passes it, and the trial step is skipped without a trial")
	tut.free()


func test_the_end_of_a_chapter_marks_it_and_offers_the_next() -> void:
	var tut := _tutorial([{"id": "a", "text": "x", "advance": "next"}])
	var finished: Array = []
	tut.chapter_finished.connect(func(id: String) -> void: finished.append(id))
	tut.start("t")
	tut.next()
	eq(tut.phase, "finished", "finished")
	eq(finished, ["t"], "chapter_finished")
	eq(tut.done_chapters(), ["t"], "kept as done")
	tut.paint()
	check(tut.overlay.card.button("next_chapter") != null, "the end card offers the next chapter")
	tut.overlay.card.press("next_chapter")
	eq(tut.chapter_id, "u", "and starts it")
	tut.skip_chapter()
	eq(tut.phase, "", "Shift+Tab: the chapter goes")
	check(not tut.overlay.visible, "and the focus with it")
	tut.free()


## A small UI: the book's button on screen and the book closed with its Debts tab inside.
func _ui() -> Control:
	var root := Control.new()
	root.name = "FakeHud"
	root.size = Vector2(960, 540)
	_button("LedgerButton", Vector2(300, 6), root)
	var panel := PanelContainer.new()
	panel.name = "LedgerPanel"
	panel.position = Vector2(600, 58)
	panel.size = Vector2(356, 430)
	panel.visible = false
	root.add_child(panel)
	var box := Control.new()
	box.name = "Box"
	box.size = Vector2(356, 430)
	panel.add_child(box)
	_button("Debts", Vector2(120, 20), box)
	return root


const OPENERS: Dictionary = {"LedgerPanel": {"target": {"ui": "LedgerButton"}, "text": "tutorial.open.ledgerpanel"}}


func test_a_hidden_target_lights_what_opens_it() -> void:
	var root := _ui()
	var ctx := FakeCtx.new()
	ctx.roots = [root]
	var r := TutorialTargets.resolve({"ui": "Debts", "in": "LedgerPanel"}, ctx, OPENERS)
	check(bool(r["found"]) and bool(r["opener"]), "found through its opener")
	eq(r["rect"], (root.get_node("LedgerButton") as Control).get_global_rect(), "the book's button is lit")
	eq(r["text"], "tutorial.open.ledgerpanel", "with what to do")
	(root.get_node("LedgerPanel") as Control).visible = true
	ctx.clear_cache()
	r = TutorialTargets.resolve({"ui": "Debts", "in": "LedgerPanel"}, ctx, OPENERS)
	check(bool(r["found"]) and not bool(r["opener"]), "open: the tab itself")
	eq(r["rect"], (root.get_node("LedgerPanel/Box/Debts") as Control).get_global_rect(), "its rect")
	var none := TutorialTargets.resolve({"ui": "Nowhere"}, ctx, OPENERS)
	check(not bool(none["found"]), "a target that is nowhere and has no opener is not found")
	(root.get_node("LedgerPanel") as Control).visible = false
	var tut := _tutorial([{"id": "pay", "text": "x", "advance": "next", "target": {"ui": "Debts", "in": "LedgerPanel"}}],
		ctx, {"openers": OPENERS})
	tut.start("t")
	tut.tick(0.0)
	check(tut.overlay.veil_on, "the veil is on")
	eq(tut.overlay.hole, (root.get_node("LedgerButton") as Control).get_global_rect().grow(3), "the hole on the opener")
	check(str(tut.overlay.card.data.get("lead", "")) != "", "the card says what opens it")
	tut.free()
	root.free()


func test_the_focus_follows_the_node_when_it_moves() -> void:
	var root := _ui()
	var ctx := FakeCtx.new()
	ctx.roots = [root]
	var tut := _tutorial([{"id": "book", "text": "x", "advance": "next", "target": {"ui": "LedgerButton"}}], ctx)
	tut.start("t")
	tut.tick(0.0)
	var b := root.get_node("LedgerButton") as Control
	eq(tut.overlay.hole, b.get_global_rect().grow(3), "on the button")
	b.position += Vector2(37, 11)   # a panel sliding in moves it (UiAnim)
	tut.tick(0.0)
	eq(tut.overlay.hole, b.get_global_rect().grow(3), "the next frame the focus is where it went")
	check(not Rect2(tut.overlay.card.position, tut.overlay.card.size).intersects(tut.overlay.hole), "the card does not cover it")
	b.position = Vector2(470, 500)   # near the bottom edge: the card goes above
	tut.tick(0.0)
	check(not Rect2(tut.overlay.card.position, tut.overlay.card.size).intersects(tut.overlay.hole), "nor near the edge")
	check(Rect2(Vector2.ZERO, Vector2(960, 540)).encloses(Rect2(tut.overlay.card.position, tut.overlay.card.size)),
		"and stays on the screen")
	tut.free()
	root.free()


func test_guided_mode_lets_clicks_through_only_on_the_target() -> void:
	var tut := _tutorial([])
	var o := tut.overlay
	o.show_focus(Rect2(100, 100, 40, 20), true, true, [Rect2(720, 4, 30, 30)], {})
	check(not o._has_point(Vector2(110, 110)), "inside the hole the click goes through")
	check(not o._has_point(Vector2(730, 10)), "the pause button too")
	check(o._has_point(Vector2(400, 300)), "elsewhere the veil takes it")
	eq(o.mouse_filter, Control.MOUSE_FILTER_STOP, "and stops it")
	o.show_focus(Rect2(100, 100, 40, 20), true, false, [], {})
	check(not o._has_point(Vector2(400, 300)) and o.mouse_filter == Control.MOUSE_FILTER_IGNORE, "not guided: nothing taken")
	tut.free()


func test_first_time_hints() -> void:
	var root := _ui()
	var ctx := FakeCtx.new()
	ctx.roots = [root]
	var hints := [{"id": "wedding", "when": {"sim": "wedding"}, "target": {"ui": "LedgerButton"}, "text": "tutorial.hint.wedding"},
		{"id": "ledger", "when": {"state": "panel_open", "is": "LedgerPanel"}, "text": "tutorial.hint.ledger"}]
	var tut := _tutorial([{"id": "a", "text": "x", "advance": "next"}], ctx, {"hints": hints})
	tut.on_event("sim", "wedding", {"family": "fam_0001"})
	eq(str(tut.hint.get("id", "")), "wedding", "the first wedding shows its hint")
	tut.paint()
	check(not tut.overlay.veil_on and tut.overlay.hole.has_area(), "a hint frames without veil")
	check(tut.overlay.card.press("got_it"), "Got it")
	check(tut.hint.is_empty(), "closes it")
	eq(tut.seen_hints(), ["wedding"], "and it is seen")
	tut.on_event("sim", "wedding", {"family": "fam_0001"})
	check(tut.hint.is_empty(), "a seen hint does not come back")
	(root.get_node("LedgerPanel") as Control).visible = true
	tut.start("t")
	tut.tick(0.0)
	check(tut.hint.is_empty(), "no hint while a chapter runs")
	tut.stop()
	ctx.clear_cache()
	tut.tick(0.0)
	eq(str(tut.hint.get("id", "")), "ledger", "after the chapter, the open book's hint")
	(root.get_node("LedgerPanel") as Control).visible = false
	ctx.clear_cache()
	tut.tick(0.0)
	check(tut.hint.is_empty(), "the panel closed: its hint goes (not seen, it comes back next time)")
	eq(tut.seen_hints(), ["wedding"], "not marked as seen")
	(root.get_node("LedgerPanel") as Control).visible = true
	ctx.clear_cache()
	tut.tick(0.0)
	tut.overlay.card.press("never")
	check(not tut.hints_on(), "«No volver a mostrar» turns every hint off")
	tut.memory["tutorial/seen"] = []
	tut.on_event("sim", "wedding", {"family": "fam_0001"})
	check(tut.hint.is_empty(), "off: none")
	tut.free()
	root.free()


## verifica #19: the first night, the hint of «Saltar hasta…» on the button by the clock (data/tutorial.json night_skip):
## a phase change is nobody's, so it is "anyone"; the day does not show it.
func test_the_first_night_shows_the_skip_hint() -> void:
	var root := _ui()
	_button("SkipButton", Vector2(300, 10), root)
	var ctx := FakeCtx.new()
	ctx.roots = [root]
	ctx.family_events = false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json"))
	var hints: Array = (data["hints"] as Array).filter(func(h: Dictionary) -> bool: return str(h["id"]) == "night_skip")
	eq(hints.size(), 1, "the hint is in the data")
	var tut := _tutorial([{"id": "a", "text": "x", "advance": "next"}], ctx, {"hints": hints})
	tut.on_event("sim", "phase_changed", {"phase": "day"})
	check(tut.hint.is_empty() or str(tut.hint.get("id", "")) != "night_skip", "not by day")
	tut.on_event("sim", "phase_changed", {"phase": "night"})
	eq(str(tut.hint.get("id", "")), "night_skip", "the night shows it")
	tut.free()
	root.free()


func test_the_data_loads_and_has_its_texts() -> void:
	var tut: Tutorial = (load(SCENE) as PackedScene).instantiate()
	tut.load_data()
	check(tut.chapter_ids().size() >= 14, "the chapters of 05_tutorial.md (%d)" % tut.chapter_ids().size())
	eq(str(tut.chapter_ids()[0]), "first_steps", "first steps first")
	eq(str(tut.chapter_ids()[1]), "produce", "then producing")
	for id: Variant in tut.chapter_ids():
		var ch: Dictionary = tut.chapters[str(id)]
		check(tr(str(ch["name_key"])) != str(ch["name_key"]), "%s has a name" % id)
		for st: Dictionary in ch["steps"]:
			check(tr(str(st["text"])) != str(st["text"]), "%s.%s has its text" % [id, st["id"]])
			check(str(st["advance"]) in ["action", "next"], "%s.%s advance" % [id, st["id"]])
	check((tut.config.get("openers", {}) as Dictionary).has("@interior"), "the openers")
	tut.free()


func test_the_progress_is_in_the_settings_not_in_the_game() -> void:
	var old := Settings.path
	Settings.path = "user://test_tutorial_settings_%d.cfg" % randi()
	Settings.reread()
	eq(Settings.value("tutorial/done"), [], "nothing done at first")
	check(bool(Settings.value("game/tutorial_hints")), "hints on by default")
	check(not bool(Settings.value("game/tutorial_guided")), "guided off by default")
	Settings.set_value("tutorial/done", ["first_steps"])
	Settings.set_value("tutorial/asked", true)
	Settings.reset()
	eq(Settings.value("tutorial/done"), ["first_steps"], "«Valores por defecto» keeps the progress")
	check(bool(Settings.value("tutorial/asked")), "and that a game was started")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.path = old
	Settings.reread()
	var src := FileAccess.get_file_as_string("res://sim/core/world_state.gd")
	check(not src.contains("tutorial"), "the saved game knows nothing of the tutorial")


## upgrade_preview.gd (found by the tutorial's smoke: «Infinite loop detected» in the Armory): the gold pulse is a
## looped tween; it only runs on a node in the tree and at a sane time scale, and it is bound to the node.
func test_the_upgrade_preview_pulse_never_loops_on_nothing() -> void:
	var n := Node2D.new()
	check(not UpgradePreview.pulse_allowed(n, 1.0), "a node out of the tree does not pulse")
	check(not UpgradePreview.pulse_allowed(null, 1.0), "nor no node")
	var pv := UpgradePreview.new()
	pv._light(n)
	eq(n.modulate, UpgradePreview.GOLD, "it is lit in gold anyway")
	check(pv._tween == null, "with no tween behind")
	pv._unlight()
	eq(n.modulate, Color.WHITE, "and unlit")
	var src := FileAccess.get_file_as_string("res://game/ui/upgrade_preview.gd")
	check(src.contains("bind_node(n)"), "the tween is bound to the lit node")
	check(UpgradePreview.MAX_PULSE_TIME_SCALE <= 16.0, "and stops pulsing when time is sped up a lot")
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:   # with a main loop: in the tree it pulses, sped up it does not
		tree.root.add_child(n)
		check(UpgradePreview.pulse_allowed(n, 1.0), "in the tree, at ×1, it pulses")
		check(not UpgradePreview.pulse_allowed(n, 100.0), "at ×100 it does not")
		check(not UpgradePreview.pulse_allowed(n, 0.0), "nor with time stopped")
	pv.free()
	n.free()


## The ribbon of the tutorial's card carries only the chapter (its short name if it has one) and fits one line of the
## notice's ribbon in Spanish and English, whichever ribbon of the kit is up; the step count goes in the card.
func test_the_chapter_fits_one_line_of_the_ribbon() -> void:
	var before := TranslationServer.get_locale()
	var tut: Tutorial = (load(SCENE) as PackedScene).instantiate()
	tut.load_data()
	for loc: String in ["es", "en"]:
		TranslationServer.set_locale(loc)
		for id: Variant in tut.chapter_ids():
			var name := tut.ribbon_name(str(id))
			check(not name.contains("/"), "%s %s: no step count on the ribbon" % [loc, id])
			for turn: int in 2:
				PageKit.use_kit(null)
				for _i: int in turn:
					PageKit.variant("ribbon")
				for _i: int in turn:
					PageKit.variant("box_frame")
				var page := (load("res://game/ui/page_card.tscn") as PackedScene).instantiate() as PageCard
				page.build({"template": "notice", "ribbon": name, "blocks": [{"type": "paragraph", "text": "·"}]})
				var r := page.get_node("%Decor").get_node_or_null("Ribbon")
				var l := r.get_node("RibbonText") as Label if r != null else null
				check(l != null and int(l.get_meta("lines", 1)) == 1 and l.text_overrun_behavior ==
					TextServer.OVERRUN_NO_TRIMMING, "%s «%s» (%s): one line, whole" % [loc, name, page.parts.get("ribbon",
					"")])
				page.free()
	TranslationServer.set_locale(before)
	PageKit.use_kit(null)
	tut.free()


## Past the basics no chapter is chained (jugador J4: after «Deuda» the tutorial offered «Empleados», still closed);
## a chapter whose mechanic is not open says it comes later.
func test_past_the_basics_no_chapter_is_chained() -> void:
	var tut := _tutorial([{"id": "a", "text": "x", "advance": "next"}])
	tut.config["basics"] = ["t"]
	eq(tut.next_chapter("t"), "", "u is not a basic: not offered after t")
	tut.config["basics"] = ["t", "u"]
	eq(tut.next_chapter("t"), "u", "within the basics, the next one")
	eq(tut.next_chapter("u"), "", "the last basic offers none")
	tut.config["basics"] = []
	tut.chapters["u"]["requires"] = {"state": "unlocked", "is": "staff"}
	var ctx := tut.ctx as FakeCtx
	if ctx != null:
		ctx.values["unlocked"] = false
		eq(tut.cannot_play("u"), "tutorial.ui.help_later", "a closed mechanic: later")
		ctx.values["unlocked"] = true
		eq(tut.cannot_play("u"), "", "open: it can be played")
	tut.free()
