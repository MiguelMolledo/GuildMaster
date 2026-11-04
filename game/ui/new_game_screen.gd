class_name NewGameScreen
extends MenuScreen
## The new game screen (GDD 4.16, 4.23, D5; docs/ui/02_menu_inicial.md §2), two columns in a 752×500 panel. Left: the
## difficulty (the chosen one pressed) and what it changes in figures; the protagonist's name and gender; the family
## name and how it reads ("Los Herrero"); the family colours (12 swatches each, the chosen one framed in gold); the
## preview (portrait with the family border, "Hugo de los Herrero", age, trade and title, what they start with and the
## family shield in its two colours). Right: the stats (name, −, value, +; the free points; "−" off at the base: points
## only go up, D5) and, for the stat under the pointer or the focus, what it does. Start (Enter) is off with its
## reason next to it while the name or the family is missing; Back (Esc) returns to the title. «Con tutorial» (ticked
## the first time, Settings tutorial/asked) makes the app start the tutorial's first chapter (docs/ui/05_tutorial.md).
## Start -> NewGame.from_start(catalog, start, difficulty, choices, seed); on success emits `started(state)` (the app
## starts the game with it).
## H12: the trade inside the class (GDD 4.2.1), buttons in the header (data/professions/ of the start's class, in
## their order); choosing one plays its start (data/professions/<id>.json "start") and, if the name and the family
## still hold the defaults of the start before, puts the new start's defaults in.
## Población: the name, the family name and the look proposed come from the game's cast (Cast.proposal with the cast
## seed Cast.sub_seed(world_seed, cast_roll)); «Otra familia» (%RerollButton) adds 1 to the roll: another proposal and
## another town, the same world seed. Start sends cast and cast_seed with the choices.

signal started(state: WorldState)

const SWATCH: Vector2 = Vector2(14, 14)

var catalog: Catalog
var start_id: String = ""
var difficulty: String = "normal"
var female: bool = false
var stats_add: Dictionary = {}   # stat -> points added (only up, at most free_points in total)
var primary: String = ""
var secondary: String = ""
var world_seed: int = 1
var help_stat: String = ""       # the stat whose help is shown
var cast_mode: String = Cast.RANDOM  # población: "fixed" proposes the start's defaults (and plays today's town)
var cast_roll: int = 0           # «Otra familia» presses
var proposal: Dictionary = {}    # Cast.proposal of the start: {name_m, name_f, family_name, visual}
## Who builds the state (NewGame.from_start by default; the tests watch the call).
var from_start: Callable = NewGame.from_start
var _bound: bool = false
var _portrait: Portrait = null


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%StartButton as Button).pressed.connect(start_game)
	(%BackButton as Button).pressed.connect(func() -> void: back_requested.emit())
	(%Male as Button).pressed.connect(func() -> void: set_female(false))
	(%Female as Button).pressed.connect(func() -> void: set_female(true))
	(%NameEdit as LineEdit).text_changed.connect(func(_t: String) -> void: _update_start())
	(%FamilyEdit as LineEdit).text_changed.connect(func(_t: String) -> void: _update_start())
	(%NameEdit as LineEdit).text_submitted.connect(func(_t: String) -> void: start_game())
	(%FamilyEdit as LineEdit).text_submitted.connect(func(_t: String) -> void: start_game())
	(%RerollButton as Button).pressed.connect(reroll_cast)


func protagonist() -> Dictionary:
	return catalog.starts().get(start_id, {}).get("protagonist", {})


func free_points() -> int:
	return int(protagonist().get("free_points", 0))


func points_left() -> int:
	var used := 0
	for s: String in stats_add:
		used += int(stats_add[s])
	return free_points() - used


## Fills the screen for `c` (the start of data/view.json "new_game", its default name/family/colours).
func setup(c: Catalog, seed_value: int) -> void:
	_bind()
	catalog = c
	world_seed = seed_value
	var cfg: Dictionary = ViewConfig.value("new_game", {})
	start_id = str(cfg.get("start", ""))
	if not c.starts().has(start_id) and not c.starts().is_empty():
		var ids: Array = c.starts().keys()
		ids.sort()
		start_id = str(ids[0])
	difficulty = str(c.difficulty.get("default", "normal"))
	female = false
	stats_add.clear()
	var palette: Array = cfg.get("colors", ["#8b2e2e", "#c8a84e"])
	var dc: Array = cfg.get("default_colors", [0, 1])
	primary = str(palette[int(dc[0]) % palette.size()])
	secondary = str(palette[int(dc[1]) % palette.size()])
	var start: Dictionary = c.starts().get(start_id, {})
	(%Title as Label).text = SimQuery.t_("ui.new_game.title")
	(%StartName as Label).text = SimQuery.t_(str(start.get("name_key", "start." + start_id)))
	(%ProfessionLabel as Label).text = SimQuery.t_("ui.new_game.profession")
	(%DifficultyLabel as Label).text = SimQuery.t_("ui.new_game.difficulty")
	(%NameLabel as Label).text = SimQuery.t_("ui.new_game.name")
	(%FamilyLabel as Label).text = SimQuery.t_("ui.new_game.family")
	(%Male as Button).text = SimQuery.t_("ui.new_game.male")
	(%Female as Button).text = SimQuery.t_("ui.new_game.female")
	(%PrimaryLabel as Label).text = SimQuery.t_("ui.new_game.primary")
	(%SecondaryLabel as Label).text = SimQuery.t_("ui.new_game.secondary")
	(%StatsLabel as Label).text = SimQuery.t_("ui.new_game.stats")
	(%ColorNote as Label).text = SimQuery.t_("ui.new_game.color_note")
	(%StartInfo as Label).text = SimQuery.t_("ui.new_game.start_info")
	(%StartButton as Button).text = SimQuery.t_("ui.new_game.start")
	# docs/ui/05_tutorial.md §2: «Con tutorial», ticked the first time a game is started
	(%TutorialCheck as CheckBox).text = SimQuery.t_("tutorial.ui.new_game")
	(%TutorialCheck as CheckBox).tooltip_text = SimQuery.t_("tutorial.ui.new_game_tip")
	(%TutorialCheck as CheckBox).button_pressed = not bool(Settings.value("tutorial/asked"))
	MenuKit.add_hint(%StartButton as Button, SimQuery.t_("ui.key.enter"))
	(%BackButton as Button).text = SimQuery.t_("ui.menu.back")
	MenuKit.add_hint(%BackButton as Button, SimQuery.t_("ui.key.esc"))
	(%RerollButton as Button).text = SimQuery.t_("ui.new_game.reroll")
	(%RerollButton as Button).tooltip_text = SimQuery.t_("ui.new_game.reroll_tip")
	cast_roll = 0
	proposal = _proposal_for(start_id)
	(%NameEdit as LineEdit).text = str(proposal.get("name_m", SimQuery.t_(str(cfg.get("default_name", "")))))
	(%FamilyEdit as LineEdit).text = str(proposal.get("family_name", SimQuery.t_(str(cfg.get("default_family", "")))))
	(%ErrorLabel as Label).visible = false
	_build_difficulty()
	_build_professions()
	_build_colors(%Primary as HBoxContainer, palette, true)
	_build_colors(%Secondary as HBoxContainer, palette, false)
	set_female(false)
	_build_stats()
	show_stat_help(str((protagonist().get("stats", {}) as Dictionary).keys()[0]) if not protagonist().get("stats", {}).is_empty() else "")
	_update_start()
	ViewConfig.info("NewGame", "setup (start=%s, difficulty=%s, free_points=%d, seed=%d)" % [start_id, difficulty,
		free_points(), world_seed])


## «Con tutorial» is ticked (the app starts the first chapter).
func with_tutorial() -> bool:
	return (get_node("%TutorialCheck") as CheckBox).button_pressed


## The name field, with the caret at its end.
func default_focus() -> Control:
	(%NameEdit as LineEdit).caret_column = (%NameEdit as LineEdit).text.length()
	return %NameEdit as LineEdit


func _build_difficulty() -> void:
	var box := %Difficulty as HBoxContainer
	MenuKit.clear(box)
	var group := ButtonGroup.new()
	for lvl: String in ["easy", "normal", "hard"]:
		var def := catalog.difficulty_levels(lvl)
		if def.is_empty():
			continue
		var b := MenuKit.button(SimQuery.t_(str(def.get("name_key", "difficulty." + lvl))))
		b.name = lvl.capitalize()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = lvl == difficulty
		b.pressed.connect(func() -> void: set_difficulty(lvl))
		box.add_child(b)
	_update_difficulty_hint()


## H12: a toggle per profession of the start's class; the start's own one pressed. Hidden with a single one.
func _build_professions() -> void:
	var box := %Profession as HBoxContainer
	MenuKit.clear(box)
	var cls := str(catalog.starts().get(start_id, {}).get("class", ""))
	var ids := catalog.professions_of(cls)
	var group := ButtonGroup.new()
	for p: String in ids:
		var def: Dictionary = catalog.professions()[p]
		if not catalog.starts().has(str(def.get("start", ""))):
			continue
		var b := MenuKit.button(SimQuery.t_(str(def.get("name_key", "profession." + p))))
		b.name = p.to_pascal_case()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 18)
		b.button_pressed = str(def.get("start", "")) == start_id
		b.pressed.connect(func() -> void: set_profession(p))
		box.add_child(b)
	box.visible = box.get_child_count() > 1
	(%ProfessionLabel as Label).visible = box.visible


## H12: plays the start of profession `p` (its data/professions "start"); the name and family that still hold the
## defaults of the start before take the new one's. The stats chosen stay (every artisan start has the same base).
func set_profession(p: String) -> void:
	var def: Dictionary = catalog.professions().get(p, {})
	var sid := str(def.get("start", ""))
	if not catalog.starts().has(sid) or sid == start_id:
		return
	var before: Dictionary = catalog.starts().get(start_id, {}).get("defaults", {})
	var after: Dictionary = catalog.starts()[sid].get("defaults", {})
	var name_edit := %NameEdit as LineEdit
	var fam_edit := %FamilyEdit as LineEdit
	var name_kept := name_edit.text.strip_edges() in [str(before.get("name", "")), str(proposal.get("name_m", "")),
		str(proposal.get("name_f", "")), SimQuery.t_(str(ViewConfig.value("new_game", {}).get("default_name", "")))]
	var fam_kept := fam_edit.text.strip_edges() in [str(before.get("family_name", "")), str(proposal.get("family_name", "")),
		SimQuery.t_(str(ViewConfig.value("new_game", {}).get("default_family", "")))]
	start_id = sid
	proposal = _proposal_for(sid)  # a family of the new trade (its trade surnames), the same roll
	if fam_kept:
		fam_edit.text = str(proposal.get("family_name", after.get("family_name", fam_edit.text)))
	if name_kept:
		if bool(after.get("female", false)) != female:
			set_female(bool(after.get("female", false)))
		name_edit.text = str(proposal.get("name_f" if female else "name_m", after.get("name", name_edit.text)))
	(%StartName as Label).text = SimQuery.t_(str(catalog.starts()[sid].get("name_key", "start." + sid)))
	for b: Node in (%Profession as HBoxContainer).get_children():
		(b as Button).set_pressed_no_signal(b.name == p.to_pascal_case())
	ViewConfig.info("NewGame", "oficio %s (start=%s)" % [p, start_id])
	_update_start()


func set_difficulty(lvl: String) -> void:
	if catalog.difficulty_levels(lvl).is_empty():
		return
	difficulty = lvl
	for b: Node in (%Difficulty as HBoxContainer).get_children():
		(b as Button).set_pressed_no_signal(b.name == lvl.capitalize())
	_update_difficulty_hint()
	_update_preview()


func _update_difficulty_hint() -> void:
	var def := catalog.difficulty_levels(difficulty)
	(%DifficultyHint as Label).text = SimQuery.t_("ui.new_game.difficulty_hint") % [int(def.get("start_debt", 0)),
		int(def.get("rival_craft", 0)), roundi(float(def.get("buy_price_mult", 1.0)) * 100.0)]


func set_female(f: bool) -> void:
	var name_edit := %NameEdit as LineEdit
	if f != female and name_edit.text.strip_edges() == str(proposal.get("name_f" if female else "name_m", "\t")):
		name_edit.text = str(proposal.get("name_f" if f else "name_m", name_edit.text))  # the proposal of the other sex
	female = f
	(%Male as Button).set_pressed_no_signal(not f)
	(%Female as Button).set_pressed_no_signal(f)
	_update_preview()


func _build_stats() -> void:
	var grid := %Stats as GridContainer
	MenuKit.clear(grid)
	var base: Dictionary = protagonist().get("stats", {})
	var smax := int(protagonist().get("stat_max", 10))
	var left := points_left()
	for s: String in base:
		var add := int(stats_add.get(s, 0))
		var name_l := MenuKit.label(SimQuery.t_("stat." + s), &"BodyLabel")
		name_l.name = s + "_name"
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		name_l.mouse_entered.connect(func() -> void: show_stat_help(s))
		grid.add_child(name_l)
		var minus := MenuKit.button("−")
		minus.name = s + "_minus"
		minus.custom_minimum_size = Vector2(16, 16)
		minus.disabled = add <= 0
		minus.pressed.connect(func() -> void: add_point(s, -1))
		grid.add_child(minus)
		var val := MenuKit.label(str(int(base[s]) + add), &"PositiveLabel" if add > 0 else &"BoldLabel")
		val.name = s + "_value"
		val.custom_minimum_size = Vector2(28, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(val)
		var plus := MenuKit.button("+")
		plus.name = s + "_plus"
		plus.custom_minimum_size = Vector2(16, 16)
		plus.disabled = left <= 0 or int(base[s]) + add >= smax
		plus.pressed.connect(func() -> void: add_point(s, 1))
		grid.add_child(plus)
		for b: Button in [minus, plus]:
			b.focus_entered.connect(func() -> void: show_stat_help(s))
			b.mouse_entered.connect(func() -> void: show_stat_help(s))
	(%PointsLabel as Label).text = SimQuery.t_("ui.new_game.points") % [left, free_points()]


## +1 / −1 point on `stat`: never more than the free points in total, never below the base, never over stat_max.
func add_point(stat: String, delta: int) -> bool:
	var base: Dictionary = protagonist().get("stats", {})
	if not base.has(stat):
		return false
	var add := int(stats_add.get(stat, 0)) + delta
	if add < 0 or (delta > 0 and points_left() <= 0) or int(base[stat]) + add > int(protagonist().get("stat_max", 10)):
		return false
	if add == 0:
		stats_add.erase(stat)
	else:
		stats_add[stat] = add
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var refocus := str(focused.name) if focused != null and (%Stats as Node).is_ancestor_of(focused) else ""
	_build_stats()
	if refocus != "":
		var again := (%Stats as Node).get_node_or_null(refocus) as Button
		if again != null and not again.disabled:
			again.grab_focus()
	show_stat_help(stat)
	return true


## What `stat` does (i18n stat_help.<stat>), in the box under the stats.
func show_stat_help(stat: String) -> void:
	help_stat = stat
	(%HelpTitle as Label).text = SimQuery.t_("stat." + stat) if stat != "" else ""
	var smin := int(protagonist().get("stat_min", 1))
	var smax := int(protagonist().get("stat_max", 10))
	(%HelpBody as Label).text = (SimQuery.t_("stat_help." + stat) + " " + SimQuery.t_("ui.new_game.points_up") % [smin, smax]) \
		if stat != "" else ""


func _build_colors(box: HBoxContainer, palette: Array, is_primary: bool) -> void:
	MenuKit.clear(box)
	for hex: Variant in palette:
		var h := str(hex)
		var b := Button.new()
		b.name = h.trim_prefix("#")
		b.custom_minimum_size = SWATCH
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		var sb := StyleBoxFlat.new()
		sb.bg_color = ViewConfig.color(h)
		sb.set_border_width_all(1)
		sb.border_color = ViewConfig.color("#1a1209")
		var sel := sb.duplicate() as StyleBoxFlat
		sel.set_border_width_all(2)
		sel.border_color = ViewConfig.color("#f2d880")
		for st: String in ["normal", "hover", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		for st: String in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, sel)
		b.pressed.connect(func() -> void: set_color(is_primary, h))
		box.add_child(b)
	set_color(is_primary, primary if is_primary else secondary)


func set_color(is_primary: bool, hex: String) -> void:
	if is_primary:
		primary = hex
	else:
		secondary = hex
	var box := (%Primary if is_primary else %Secondary) as HBoxContainer
	for b: Node in box.get_children():
		(b as Button).set_pressed_no_signal(b.name == hex.trim_prefix("#"))
	_update_preview()


## The preview: the portrait in the family's colours with the primary as its border, the name, age, trade and title,
## what the start gives and the shield.
func _update_preview() -> void:
	if catalog == null or not is_inside_tree():
		return
	var start: Dictionary = catalog.starts().get(start_id, {})
	var defaults: Dictionary = start.get("defaults", {})
	var vis: Dictionary = proposal.get("visual", defaults.get("visual", {}))
	var pk := "portrait_f" if female else "portrait_m"  # población: the proposal has one portrait per sex
	var pt: Dictionary = vis.get(pk, {}) if vis.get(pk) is Dictionary else {}
	if _portrait == null:
		var n := VisualPaths.instantiate("characters", "portrait")
		n.name = "Portrait"
		(%PortraitHolder as Node2D).add_child(n)
		_portrait = n as Portrait
	if _portrait != null:
		_portrait.set_identity({"hair": Identity.hair_color(int(vis.get("hair", 0))),
			"skin": Identity.skin_color(int(vis.get("skin", 0))), "primary": ViewConfig.color(primary),
			"secondary": ViewConfig.color(secondary), "female": female, "dead": false,
			"portrait": {"id": str(pt.get("id", "")), "type": str(pt.get("type", "artisan")), "seed": 1,
				"stage": Identity.stage(int(protagonist().get("age", 20)))}})
	var border := (%PortraitBorder as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	if border != null:
		border = border.duplicate() as StyleBoxFlat
		border.border_color = ViewConfig.color(primary)
		(%PortraitBorder as Panel).add_theme_stylebox_override("panel", border)
	(%ShieldTop as ColorRect).color = ViewConfig.color(primary)
	(%ShieldBottom as ColorRect).color = ViewConfig.color(secondary)
	var ch := choices()
	var fam_name := str(ch["family_name"])
	(%FamilyRead as Label).text = SimQuery.t_("ui.title.family") % fam_name if fam_name != "" else ""
	(%PreviewName as Label).text = SimQuery.t_("ui.new_game.preview_name") % [str(ch["name"]), fam_name] \
		if str(ch["name"]) != "" and fam_name != "" else str(ch["name"])
	var p := protagonist()
	var title := SimQuery.t_("title." + str(p.get("title", "common")))
	(%PreviewAge as Label).text = SimQuery.t_("ui.new_game.preview_age") % [int(p.get("age", 20)),
		SimQuery.t_("profession." + str(start.get("profession", ""))).to_lower(), title.substr(0, 1).to_upper() + title.substr(1)]
	var debt := int(catalog.difficulty_levels(difficulty).get("start_debt", 0))
	(%PreviewStart as Label).text = SimQuery.t_("ui.new_game.preview_start.%s" % start_id) % [
		int(start.get("family", {}).get("gold", 0)), debt]


## Start is off with its reason next to it while the name or the family is missing.
func _update_start() -> void:
	var why := missing_reason()
	(%StartButton as Button).disabled = why != ""
	(%ErrorLabel as Label).text = SimQuery.t_(why) if why != "" else ""
	(%ErrorLabel as Label).visible = why != ""
	_update_preview()


## The i18n key of what is missing to start ("" = nothing).
func missing_reason() -> String:
	if (%NameEdit as LineEdit).text.strip_edges() == "":
		return "ui.new_game.need_name"
	if (%FamilyEdit as LineEdit).text.strip_edges() == "":
		return "ui.new_game.need_family"
	return ""


## What the player chose, in the shape of NewGame.from_start's `choices` (población: with the cast and its seed).
func choices() -> Dictionary:
	return {"name": (%NameEdit as LineEdit).text.strip_edges(), "female": female,
		"family_name": (%FamilyEdit as LineEdit).text.strip_edges(), "colors": {"primary": primary, "secondary": secondary},
		"stats_add": stats_add.duplicate(), "cast": cast_mode, "cast_seed": cast_seed()}


## Población: the cast seed of this screen (a sub-seed of the world seed: «Otra familia» moves only the roll).
func cast_seed() -> int:
	return Cast.sub_seed(world_seed, cast_roll)


## «Otra familia»: another roll of the cast (name, family name and look proposed, and the town's people), the same world.
func reroll_cast() -> void:
	cast_roll += 1
	proposal = _proposal_for(start_id)
	(%NameEdit as LineEdit).text = str(proposal.get("name_f" if female else "name_m", ""))
	(%FamilyEdit as LineEdit).text = str(proposal.get("family_name", ""))
	ViewConfig.info("NewGame", "otra familia (tirada=%d, semilla=%d): %s de los %s" % [cast_roll, cast_seed(),
		(%NameEdit as LineEdit).text, (%FamilyEdit as LineEdit).text])
	_update_start()


func _proposal_for(sid: String) -> Dictionary:
	return Cast.proposal(catalog, catalog.starts().get(sid, {}), cast_mode, cast_seed())


## Start: builds the game with what was chosen; on success emits started(state), else shows the error.
func start_game() -> void:
	var ch := choices()
	if str(ch["name"]) == "" or str(ch["family_name"]) == "":
		(%ErrorLabel as Label).text = SimQuery.t_(missing_reason())
		(%ErrorLabel as Label).visible = true
		return
	ViewConfig.info("NewGame", "from_start (start=%s, difficulty=%s, choices=%s, seed=%d)" % [start_id, difficulty, ch,
		world_seed])
	var r: Dictionary = from_start.call(catalog, start_id, difficulty, ch, world_seed)
	if bool(r.get("ok", false)):
		started.emit(r["state"])
		return
	ViewConfig.info("NewGame", "from_start refused (error=%s)" % r.get("error", ""))
	(%ErrorLabel as Label).text = SimQuery.t_("ui.new_game.error") % str(r.get("error", ""))
	(%ErrorLabel as Label).visible = true
