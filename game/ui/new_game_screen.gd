class_name NewGameScreen
extends Control
## The new game screen (GDD 4.16, 4.23, D5): difficulty, the protagonist's name and gender, the family name, the
## free points (data/starts/<start>.json protagonist.free_points, each stat within [stat_min, stat_max]) and the
## family colours. Start -> NewGame.from_start(catalog, start, difficulty, choices, seed); on success emits
## `started(state)` (the app starts the game with it). Shown when the game runs without --scenario.

signal started(state: WorldState)

var catalog: Catalog
var start_id: String = ""
var difficulty: String = "normal"
var female: bool = false
var stats_add: Dictionary = {}   # stat -> points added (only up, at most free_points in total)
var primary: String = ""
var secondary: String = ""
var world_seed: int = 1
## Who builds the state (NewGame.from_start by default; the tests watch the call).
var from_start: Callable = NewGame.from_start
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%StartButton as Button).pressed.connect(start_game)
	(%Male as Button).pressed.connect(func() -> void: set_female(false))
	(%Female as Button).pressed.connect(func() -> void: set_female(true))


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
	(%Title as Label).text = SimQuery.t_("ui.new_game.title")
	(%StartName as Label).text = SimQuery.t_(str(c.starts().get(start_id, {}).get("name_key", "start." + start_id)))
	(%DifficultyLabel as Label).text = SimQuery.t_("ui.new_game.difficulty")
	(%NameLabel as Label).text = SimQuery.t_("ui.new_game.name")
	(%FamilyLabel as Label).text = SimQuery.t_("ui.new_game.family")
	(%Male as Button).text = SimQuery.t_("ui.new_game.male")
	(%Female as Button).text = SimQuery.t_("ui.new_game.female")
	(%PrimaryLabel as Label).text = SimQuery.t_("ui.new_game.primary")
	(%SecondaryLabel as Label).text = SimQuery.t_("ui.new_game.secondary")
	(%StartButton as Button).text = SimQuery.t_("ui.new_game.start")
	(%NameEdit as LineEdit).text = SimQuery.t_(str(cfg.get("default_name", "")))
	(%FamilyEdit as LineEdit).text = SimQuery.t_(str(cfg.get("default_family", "")))
	(%ErrorLabel as Label).visible = false
	_build_difficulty()
	_build_colors(%Primary as HBoxContainer, palette, true)
	_build_colors(%Secondary as HBoxContainer, palette, false)
	set_female(false)
	_build_stats()
	ViewConfig.info("NewGame", "setup (start=%s, difficulty=%s, free_points=%d, seed=%d)" % [start_id, difficulty,
		free_points(), world_seed])


func _clear(n: Node) -> void:
	for c: Node in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _build_difficulty() -> void:
	var box := %Difficulty as HBoxContainer
	_clear(box)
	var group := ButtonGroup.new()
	for lvl: String in ["easy", "normal", "hard"]:
		var def := catalog.difficulty_levels(lvl)
		if def.is_empty():
			continue
		var b := Button.new()
		b.name = lvl.capitalize()
		b.text = SimQuery.t_(str(def.get("name_key", "difficulty." + lvl)))
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = lvl == difficulty
		b.pressed.connect(func() -> void: set_difficulty(lvl))
		box.add_child(b)
	_update_difficulty_hint()


func set_difficulty(lvl: String) -> void:
	if catalog.difficulty_levels(lvl).is_empty():
		return
	difficulty = lvl
	for b: Node in (%Difficulty as HBoxContainer).get_children():
		(b as Button).set_pressed_no_signal(b.name == lvl.capitalize())
	_update_difficulty_hint()


func _update_difficulty_hint() -> void:
	var def := catalog.difficulty_levels(difficulty)
	(%DifficultyHint as Label).text = SimQuery.t_("ui.new_game.difficulty_hint") % [int(def.get("start_debt", 0)),
		int(def.get("rival_craft", 0)), roundi(float(def.get("buy_price_mult", 1.0)) * 100.0)]


func set_female(f: bool) -> void:
	female = f
	(%Male as Button).set_pressed_no_signal(not f)
	(%Female as Button).set_pressed_no_signal(f)


func _build_stats() -> void:
	var grid := %Stats as GridContainer
	_clear(grid)
	var base: Dictionary = protagonist().get("stats", {})
	var smax := int(protagonist().get("stat_max", 10))
	var left := points_left()
	for s: String in base:
		var add := int(stats_add.get(s, 0))
		var name_l := Label.new()
		name_l.text = SimQuery.t_("stat." + s)
		name_l.custom_minimum_size = Vector2(76, 0)
		grid.add_child(name_l)
		var minus := Button.new()
		minus.name = s + "_minus"
		minus.text = "−"
		minus.focus_mode = Control.FOCUS_NONE
		minus.disabled = add <= 0
		minus.pressed.connect(func() -> void: add_point(s, -1))
		grid.add_child(minus)
		var val := Label.new()
		val.name = s + "_value"
		val.text = str(int(base[s]) + add)
		val.custom_minimum_size = Vector2(18, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if add > 0:
			val.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		grid.add_child(val)
		var plus := Button.new()
		plus.name = s + "_plus"
		plus.text = "+"
		plus.focus_mode = Control.FOCUS_NONE
		plus.disabled = left <= 0 or int(base[s]) + add >= smax
		plus.pressed.connect(func() -> void: add_point(s, 1))
		grid.add_child(plus)
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
	_build_stats()
	return true


func _build_colors(box: HBoxContainer, palette: Array, is_primary: bool) -> void:
	_clear(box)
	for hex: Variant in palette:
		var h := str(hex)
		var b := Button.new()
		b.name = h.trim_prefix("#")
		b.custom_minimum_size = Vector2(22, 18)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		var sb := StyleBoxFlat.new()
		sb.bg_color = ViewConfig.color(h)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.25, 0.17, 0.1)
		var sel := sb.duplicate() as StyleBoxFlat
		sel.set_border_width_all(3)
		sel.border_color = Color(1.0, 0.92, 0.6)
		for st: String in ["normal", "hover", "disabled"]:
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


## What the player chose, in the shape of NewGame.from_start's `choices`.
func choices() -> Dictionary:
	return {"name": (%NameEdit as LineEdit).text.strip_edges(), "female": female,
		"family_name": (%FamilyEdit as LineEdit).text.strip_edges(), "colors": {"primary": primary, "secondary": secondary},
		"stats_add": stats_add.duplicate()}


## Start: builds the game with what was chosen; on success emits started(state), else shows the error.
func start_game() -> void:
	var ch := choices()
	var err := ""
	if str(ch["name"]) == "" or str(ch["family_name"]) == "":
		err = "ui.new_game.need_names"
	else:
		ViewConfig.info("NewGame", "from_start (start=%s, difficulty=%s, choices=%s, seed=%d)" % [start_id, difficulty, ch,
			world_seed])
		var r: Dictionary = from_start.call(catalog, start_id, difficulty, ch, world_seed)
		if bool(r.get("ok", false)):
			started.emit(r["state"])
			return
		err = "ui.new_game.error"
		ViewConfig.info("NewGame", "from_start refused (error=%s)" % r.get("error", ""))
		(%ErrorLabel as Label).text = SimQuery.t_(err) % str(r.get("error", ""))
		(%ErrorLabel as Label).visible = true
		return
	(%ErrorLabel as Label).text = SimQuery.t_(err)
	(%ErrorLabel as Label).visible = true


## While shown, no key reaches the town or the HUD below (pause, speeds, ESC): this screen is drawn over them.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and is_inside_tree():
		get_viewport().set_input_as_handled()
