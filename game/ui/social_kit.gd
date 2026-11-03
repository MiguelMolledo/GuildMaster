class_name SocialKit
extends RefCounted
## Pieces shared by the social panels (docs/ui/mecanicas/_social.md): the portrait with the family colour, the
## relation as a word (bands in data/view.json social.relation_bands), the odds of a skill check as a band (Fácil /
## Dudoso / Difícil, GDD 4.2.4: threshold = base + (actor − target) × step, data/town.json skill_check), the reason
## line under a row of actions, the two-line button (what it does + its effects), the confirmation of irreversible
## actions (rule 2) and the family ribbon. Presentation only: no rule is computed here that the sim does not compute.
##
## Confirmations: ask() keeps the question on the panel (pending(), accept_pending() for the tests) and, inside the
## game, shows it in the HUD's ConfirmModal (docs/ui/01_hud.md §5); its answer clears or runs the pending one.

const PORTRAIT: String = "res://game/ui/portrait_frame.tscn"
const RELATION_BANDS_DEFAULT: Array = [[-60, "enemy"], [-25, "hostile"], [-6, "cold"], [5, "neutral"], [49, "cordial"],
	[100, "friend"]]


const THEME: String = "res://game/ui/greybox_theme.tres"
const OFFICE_VARIATIONS: Dictionary = {"mayor": &"OfficeGold", "major": &"OfficeBronze", "middle": &"OfficeSilver",
	"minor": &"OfficeCopper"}


## A colour of the shared theme (the bars drawn by code take theirs from it: RelationBar, ThresholdBar...).
static func theme_color(type: StringName, color: StringName) -> Color:
	var t := load(THEME) as Theme
	return t.get_color(color, type) if t != null and t.has_color(color, type) else Color.MAGENTA


## A portrait (32 inside a 40 frame) of `chr` with its family's border. flags as PortraitFrame.show_character.
static func portrait(state: WorldState, chr: String, flags: Dictionary = {}) -> Control:
	var p: Control = (load(PORTRAIT) as PackedScene).instantiate()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.call("show_character", state, chr, flags)
	return p


## The relation word of -100..100 ("enemy" … "friend"): the first band whose upper bound is >= v.
static func relation_band(v: int) -> String:
	var bands: Array = (ViewConfig.value("social", {}) as Dictionary).get("relation_bands", RELATION_BANDS_DEFAULT)
	for b: Array in bands:
		if v <= int(b[0]):
			return str(b[1])
	return str((bands.back() as Array)[1])


static func relation_word(v: int) -> String:
	return SimQuery.t_("relation_band." + relation_band(v))


## The odds of a skill check: {band: "easy" | "doubtful" | "hard", threshold, actor_stat, target_stat}.
static func check_band(sim: Sim, actor: String, target: String, actor_stat: String, target_stat: String,
		target_value: int = -1, modifier: int = 0) -> Dictionary:
	var cfg: Dictionary = sim.catalog.town.get("skill_check", {})
	var a := SkillCheck.stat(sim, actor, actor_stat)
	var t := target_value if target_value >= 0 else SkillCheck.stat(sim, target, target_stat)
	var th := int(cfg.get("base", 50)) + (a - t) * int(cfg.get("step", 5)) + modifier
	var band := "doubtful"
	if th >= 65:
		band = "easy"
	elif th <= 35:
		band = "hard"
	return {"band": band, "threshold": th, "actor_stat": a, "target_stat": t}


## "Carisma 4 contra Empatía 6: difícil" of a check_band.
static func check_text(b: Dictionary, actor_stat: String, target_stat: String) -> String:
	if target_stat == "":
		return SimQuery.t_("ui.social.check_value") % [SimQuery.t_("stat." + actor_stat), int(b["actor_stat"]),
			int(b["target_stat"]), SimQuery.t_("check_band." + str(b["band"]))]
	return SimQuery.t_("ui.social.check") % [SimQuery.t_("stat." + actor_stat), int(b["actor_stat"]),
		SimQuery.t_("stat." + target_stat) if target_stat != "" else "", int(b["target_stat"]),
		SimQuery.t_("check_band." + str(b["band"]))]


## A label with the reason a button is off, in red (empty text hides it).
static func reason_label(name: String = "Reason") -> Label:
	var l := Label.new()
	l.name = name
	l.theme_type_variation = &"ReasonLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l


static func set_reason(l: Label, text: String) -> void:
	l.text = text
	l.visible = text != ""


## A button of two lines: the action in bold and its effects below in body font (_social §4, microevent choices).
static func two_line_button(title: String, effects: String, name: String = "") -> Button:
	var b := Button.new()
	if name != "":
		b.name = name
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = effects
	var box := VBoxContainer.new()
	box.name = "Lines"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", -2)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)
	box.offset_left = 6
	box.offset_top = 1
	box.offset_right = -6
	var t := Label.new()
	t.name = "Title"
	t.text = title
	t.theme_type_variation = &"BoldLabel"
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.clip_text = true
	box.add_child(t)
	var e := Label.new()
	e.name = "Effects"
	e.text = effects
	e.theme_type_variation = &"DimLabel"
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	e.clip_text = true
	box.add_child(e)
	b.add_child(box)
	b.custom_minimum_size = Vector2(0, 34)
	return b


## A one-line text of a button made by two_line_button (tests, captures).
static func button_lines(b: Button) -> String:
	var box := b.get_node_or_null("Lines")
	if box == null:
		return b.text
	return "%s · %s" % [(box.get_node("Title") as Label).text, (box.get_node("Effects") as Label).text]


# --- confirmation of irreversible actions (_social rule 2) ----------------------------------------------------------

## Asks before `on_yes` runs. The question stays on `owner` (pending) until answered; in the tree, a dialog shows it.
static func ask(owner: Node, title: String, body: String, yes_text: String, on_yes: Callable, warn: String = "",
		seal: bool = false) -> void:
	owner.set_meta("pending_confirm", {"title": title, "body": body, "yes": yes_text, "warn": warn, "seal": seal,
		"on_yes": on_yes})
	ViewConfig.info("SocialKit", "ask (%s: %s)" % [owner.name, title])
	if not owner.is_inside_tree():
		return
	show_in(ConfirmModal.of(owner.get_tree()), owner)   # the HUD's modal (docs/ui/01_hud.md §5)


## Shows the question waiting on `owner` in modal `m`; its answer runs or drops it.
static func show_in(m: ConfirmModal, owner: Node) -> void:
	var p := pending(owner)
	if m == null or p.is_empty():
		return
	if m.answered.is_connected(_on_answered):
		m.answered.disconnect(_on_answered)
	m.answered.connect(_on_answered.bind(owner), CONNECT_ONE_SHOT)
	m.ask({"title": str(p["title"]), "body": str(p["body"]), "action": str(p["yes"]), "irreversible": str(p["warn"]) != "",
		"seal": bool(p["seal"])})


## The question waiting on `owner` ({} if none).
static func pending(owner: Node) -> Dictionary:
	return owner.get_meta("pending_confirm", {}) if owner.has_meta("pending_confirm") else {}


## Answers yes to the question waiting on `owner` (the dialog's button, or a test). False if there was none.
static func accept_pending(owner: Node) -> bool:
	var p := pending(owner)
	if p.is_empty():
		return false
	owner.remove_meta("pending_confirm")
	var cb: Callable = p["on_yes"]
	if cb.is_valid():
		cb.call()
	return true


static func cancel_pending(owner: Node) -> void:
	if owner.has_meta("pending_confirm"):
		owner.remove_meta("pending_confirm")


static func _on_answered(yes: bool, owner: Node) -> void:
	if not is_instance_valid(owner):
		return
	if yes:
		accept_pending(owner)
	else:
		cancel_pending(owner)


# --- small pieces ---------------------------------------------------------------------------------------------------

## A family ribbon: a small swatch of its two colours (identity, never good or bad: _social rule 4).
static func ribbon(state: WorldState, fam: String, size: Vector2 = Vector2(8, 14)) -> Control:
	var f: Dictionary = state.families.get(fam, {})
	var c: Dictionary = f.get("colors", {})
	var box := VBoxContainer.new()
	box.name = "Ribbon"
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := ColorRect.new()
	top.color = ViewConfig.color(str(c.get("primary", "#808080")))
	top.custom_minimum_size = Vector2(size.x, roundf(size.y * 0.66))
	box.add_child(top)
	var bottom := ColorRect.new()
	bottom.color = ViewConfig.color(str(c.get("secondary", "#c0c0c0")))
	bottom.custom_minimum_size = Vector2(size.x, size.y - roundf(size.y * 0.66))
	box.add_child(bottom)
	box.tooltip_text = str(f.get("name", ""))
	return box


## A thin bar 0..1 (ProgressBar of the theme) of `w` × 6.
static func bar(value: float, w: float = 120.0, name: String = "Bar") -> ProgressBar:
	var p := ProgressBar.new()
	p.name = name
	p.show_percentage = false
	p.min_value = 0.0
	p.max_value = 1.0
	p.step = 0.0
	p.value = clampf(value, 0.0, 1.0)
	p.custom_minimum_size = Vector2(w, 6)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## "+5" / "−5" (the minus sign of the texts, not a hyphen).
static func signed(n: int) -> String:
	return ("+%d" % n) if n >= 0 else ("−%d" % absi(n))


## A bar 0..max with a 1 px gold mark at `mark` (the threshold: afinidad 80, votos, defensa), its own `w` × 6.
static func threshold_bar(value: float, max_value: float, mark: float, w: float = 120.0, name: String = "Bar") -> ProgressBar:
	var p := bar(value / maxf(1.0, max_value), w, name)
	var m := ColorRect.new()
	m.name = "Mark"
	m.color = theme_color(&"ThresholdBar", &"mark")
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := clampf(mark / maxf(1.0, max_value), 0.0, 1.0)
	m.anchor_left = r
	m.anchor_right = r
	m.anchor_top = 0.0
	m.anchor_bottom = 1.0
	m.offset_left = 0.0
	m.offset_right = 1.0
	m.offset_top = -2.0
	m.offset_bottom = 2.0
	p.add_child(m)
	p.set_meta("mark", mark)
	return p


static func clear(n: Node) -> void:
	for c: Node in n.get_children():
		n.remove_child(c)
		c.queue_free()


static func label(text: String, variation: StringName = &"", name: String = "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if name != "":
		l.name = name
	return l


## "1 d 4 h" / "3 h" / "20 min" of game minutes.
static func duration_text(minutes: int) -> String:
	var m := maxi(0, minutes)
	var d := m / Clock.MINUTES_PER_DAY
	var h := (m % Clock.MINUTES_PER_DAY) / 60
	if d > 0:
		return SimQuery.t_("ui.social.days_hours") % [d, h] if h > 0 else SimQuery.t_("ui.social.days") % d
	if h > 0:
		return SimQuery.t_("ui.social.hours") % h
	return SimQuery.t_("ui.social.minutes") % (m % 60)
