class_name PacingHud
extends Node
## The HUD pieces of «ritmo» (docs/gdd/03b_diversion_y_ritmo.md), mounted by the HUD into its own zones without
## changing them: the goals zone under the objective (§3b.5.1: this season's and this year's goals, OpenGoals.view;
## the short one is the objective panel of today), «Saltar hasta…» at the end of the clock's time row (§3b.5.2, O-D3: a menu with
## the next event, dawn and the end of the queue; Game.skip_until, ×8, any notice cuts it) and the «Nuevo» mark of the
## unlocks on the button that opens them (§3b.4, Unlocks.marks; pressing it gives unlock_seen {what: mark}). Reads the
## state; gives only unlock_seen through Game.give; changes only the session (skip).

const SKIP_ICON: String = "»"

var hud: Node = null
var goals_panel: PanelContainer = null
var goals_box: VBoxContainer = null
var skip_button: Button = null
var skip_menu: PopupMenu = null
var _marks: Dictionary = {}       # button node name -> mark Label
var _wired: Dictionary = {}       # button node name -> true (pressed connected)
var _left: float = 0.0


## Mounts the pieces into `h` (the HUD): the speeds grid gets the skip button, the column the goals panel.
func mount(h: Node) -> void:
	hud = h
	var row := (h.get_node("%TimeLabel") as Control).get_parent() as HBoxContainer   # the clock's time row
	skip_button = Button.new()
	skip_button.name = "SkipButton"
	skip_button.text = SKIP_ICON
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.custom_minimum_size = Vector2(22, 0)
	skip_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skip_button.flat = true   # no frame: the clock panel keeps its height (zone 3)
	skip_button.theme_type_variation = &"BoldLabel"
	skip_button.add_theme_color_override("font_color", Color("#c8a84e"))
	skip_button.tooltip_text = tr("hud.skip") + "\n" + tr("hud.skip_tip")
	skip_button.pressed.connect(_on_skip_pressed)
	row.add_child(skip_button)
	skip_menu = PopupMenu.new()
	skip_menu.name = "SkipMenu"
	skip_menu.id_pressed.connect(_on_skip_choice)
	var root := h.get_node_or_null("Root") as Control
	if root != null and root.theme != null:
		skip_menu.theme = root.theme   # the HUD's theme (a popup does not inherit it from a CanvasLayer)
	h.add_child(skip_menu)
	var col := h.get_node("%Column") as VBoxContainer
	goals_panel = PanelContainer.new()
	goals_panel.name = "GoalsPanel"
	goals_panel.visible = false
	goals_box = VBoxContainer.new()
	goals_box.add_theme_constant_override("separation", 1)
	goals_panel.add_child(goals_box)
	col.add_child(goals_panel)
	col.move_child(goals_panel, (h.get_node("%ObjectivePanel") as Control).get_index() + 1)
	var g := _game()
	if g != null:
		g.connect("skip_changed", _on_skip_changed)
	Log.info("PacingHud", "mounted (clock row=%d, column=%d)" % [row.get_child_count(), col.get_child_count()])


func _game() -> Node:
	return get_node_or_null("/root/Game")


func _sim() -> Sim:
	var g := _game()
	return g.get("sim") as Sim if g != null else null


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0 or hud == null:
		return
	_left = 0.25
	var sim := _sim()
	if sim == null:
		return
	refresh(sim)


## The goals and the marks, from the state.
func refresh(sim: Sim) -> void:
	var fam := SimQuery.player_family(sim.state)
	_refresh_goals(sim, fam)
	_refresh_marks(sim, fam)
	var g := _game()
	skip_button.set_pressed_no_signal(false)
	skip_button.text = "■" if g != null and str(g.get("skip_kind")) != "" else SKIP_ICON


# --- §3b.5.1 · goals -------------------------------------------------------------------------------------------------

func _refresh_goals(sim: Sim, fam: String) -> void:
	var rows: Array = []
	for v: Dictionary in OpenGoals.view(sim, fam):
		if str(v.get("horizon", "")) != "short":   # today's is the objective panel
			rows.append(v)
	goals_panel.visible = not rows.is_empty() and fam != ""
	var key := JSON.stringify(rows)
	if goals_panel.get_meta("key", "") == key:
		return
	goals_panel.set_meta("key", key)
	for c: Node in goals_box.get_children():
		goals_box.remove_child(c)
		c.queue_free()
	var title := Label.new()
	title.name = "GoalsTitle"
	title.text = tr("hud.goals").to_upper()
	title.theme_type_variation = &"CaptionLabel"
	goals_box.add_child(title)
	for v: Dictionary in rows:
		var row := HBoxContainer.new()
		row.name = "Goal_" + str(v.get("horizon", ""))
		var h := Label.new()
		h.text = tr("hud.goal." + ("dynasty" if str(v.get("from", "")) == "dynasty" else str(v["horizon"])))
		h.theme_type_variation = &"DimLabel"
		h.custom_minimum_size = Vector2(64, 0)
		row.add_child(h)
		var name := Label.new()
		name.name = "Name"
		name.text = tr(str(v.get("name_key", "")))
		name.theme_type_variation = &"BodyLabel"
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.custom_minimum_size = Vector2(110, 0)
		row.add_child(name)
		var parts: PackedStringArray = []
		for p: Dictionary in v.get("progress", []):
			parts.append("%d/%d" % [int(p["have"]), int(p["need"])])
		if not parts.is_empty():
			var pr := Label.new()
			pr.text = " · ".join(parts)
			pr.theme_type_variation = &"SmallLabel"
			pr.add_theme_color_override("font_color", Color(0.494118, 0.784314, 0.494118, 1))
			row.add_child(pr)
		goals_box.add_child(row)
	Log.info("PacingHud", "goals %s" % [rows.map(func(v: Dictionary) -> String: return str(v.get("objective", v.get("name_key", ""))))])


## The goals shown (horizon -> objective or name_key), for the tests.
func shown_goals() -> Dictionary:
	var out := {}
	var sim := _sim()
	if sim == null:
		return out
	for v: Dictionary in OpenGoals.view(sim, SimQuery.player_family(sim.state)):
		out[str(v["horizon"])] = str(v.get("objective", "")) if str(v.get("objective", "")) != "" else str(v["name_key"])
	return out


# --- §3b.4 · marks ---------------------------------------------------------------------------------------------------

func _refresh_marks(sim: Sim, fam: String) -> void:
	var want := Unlocks.marks(sim, fam)
	for n: String in want:
		var b := _button(str(n))
		if b == null:
			continue
		if not _wired.has(n):
			_wired[n] = true
			b.pressed.connect(_mark_used.bind(str(n)))
		if not _marks.has(n) or not is_instance_valid(_marks[n]):
			var l := Label.new()
			l.name = "NewMark"
			l.text = "●"
			l.tooltip_text = tr("hud.new")
			l.theme_type_variation = &"GoldLabel"
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.position = Vector2(b.size.x - 7, -5)
			b.add_child(l)
			_marks[n] = l
	for n: String in _marks.keys():
		if not want.has(n) and is_instance_valid(_marks[n]):
			(_marks[n] as Node).queue_free()
			_marks.erase(n)


## A button the mark goes on: the HUD's (%Name) or, inside a building, the interior's.
func _button(n: String) -> Button:
	var b := hud.get_node_or_null("%" + n) as Button
	if b != null:
		return b
	var app := hud.get_parent()
	while app != null and not app.has_method("interior"):
		app = app.get_parent()
	if app != null:
		var iv: Node = app.call("interior")
		if iv != null and iv.is_inside_tree():
			return iv.get_node_or_null("%" + n) as Button
	return null


func _mark_used(n: String) -> void:
	var sim := _sim()
	if sim == null:
		return
	var fam := SimQuery.player_family(sim.state)
	var id := str(Unlocks.marks(sim, fam).get(n, ""))
	var head := str(sim.state.families.get(fam, {}).get("head", ""))
	if id != "" and head != "":
		_game().call("give", {"type": "unlock_seen", "actor": head, "unlock": id, "what": "mark"})


## The buttons that carry a mark now (tests, smoke).
func marked() -> Array:
	return _marks.keys()


# --- §3b.5.2 · «Saltar hasta…» --------------------------------------------------------------------------------------

func _on_skip_pressed() -> void:
	var g := _game()
	if g == null:
		return
	if str(g.get("skip_kind")) != "":
		g.call("stop_skip", "cancel")
		return
	open_skip_menu()


func open_skip_menu() -> void:
	skip_menu.clear()
	skip_menu.add_item(tr("hud.skip.event"), 0)
	skip_menu.add_item(tr("hud.skip.dawn"), 1)
	skip_menu.add_item(tr("hud.skip.queue"), 2)
	skip_menu.set_item_disabled(2, queue_building() == "")
	var r := skip_button.get_global_rect()
	skip_menu.popup(Rect2i(Vector2i(int(r.position.x - 80), int(r.end.y + 2)), Vector2i(100, 0)))


## The family's building whose queue «que acabe la cola» waits for: the one open inside, else the first with work.
func queue_building() -> String:
	var g := _game()
	var sim := _sim()
	if g == null or sim == null:
		return ""
	var app := hud.get_parent()
	while app != null and not "interior_building" in app:
		app = app.get_parent()
	var inside := str(app.get("interior_building")) if app != null else ""
	if inside != "" and bool(g.call("skip_queue_ok", inside)):
		return inside
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: Variant in ids:
		if bool(g.call("skip_queue_ok", str(b))):
			return str(b)
	return ""


func _on_skip_choice(id: int) -> void:
	var kind: String = ["event", "dawn", "queue"][clampi(id, 0, 2)]
	skip(kind)


## Starts «Saltar hasta…» `kind` (the menu's choice; the smoke script calls it too).
func skip(kind: String) -> bool:
	var g := _game()
	if g == null:
		return false
	return bool(g.call("skip_until", kind, queue_building() if kind == "queue" else ""))


func _on_skip_changed(kind: String, reason: String) -> void:
	if hud == null or not hud.has_method("show_toast"):
		return
	if kind != "":
		hud.call("show_toast", tr("hud.skip.on") % tr("hud.skip." + kind))
	elif reason != "cancel" and reason != "order":
		hud.call("show_toast", tr("hud.skip.stopped") % tr("hud.skip.why." + reason))
