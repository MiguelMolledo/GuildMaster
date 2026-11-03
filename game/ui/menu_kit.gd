class_name MenuKit
extends RefCounted
## Small pieces shared by the menu screens (docs/ui/02_menu_inicial.md): buttons and labels built by code (rows of
## lists) with the kit's type variations, the key hint on a button, the texts of a saved game's header and the
## first focus. The look itself is in the themes: greybox_theme.tres (shared) and menu_overrides_theme.tres (the
## variations the menus need that the shared theme does not have yet).

const OVERRIDES: String = "res://game/ui/menu_overrides_theme.tres"


static func button(text: String, hint: String = "", variation: StringName = &"BoldButton") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	if hint != "":
		add_hint(b, hint)
	return b


## The small key name at the bottom right of a button ("Esc", "F5", "Intro").
static func add_hint(b: Button, hint: String) -> Label:
	var l := b.get_node_or_null("Hint") as Label
	if l == null:
		l = Label.new()
		l.name = "Hint"
		l.theme_type_variation = &"KeyHint"
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.anchor_left = 1.0
		l.anchor_top = 1.0
		l.anchor_right = 1.0
		l.anchor_bottom = 1.0
		l.offset_left = -40.0
		l.offset_top = -12.0
		l.offset_right = -3.0
		l.offset_bottom = -1.0
		b.add_child(l)
	l.text = hint
	return l


static func label(text: String, variation: StringName = &"BodyLabel") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


static func clear(n: Node) -> void:
	for c: Node in n.get_children():
		n.remove_child(c)
		c.queue_free()


## The first visible, enabled control that takes the focus under `root` (in tree order), null if none.
static func first_focusable(root: Node) -> Control:
	for c: Node in root.get_children():
		if c is Control and not (c as Control).visible:
			continue
		if c is BaseButton and (c as BaseButton).disabled:
			continue
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL:
			return c as Control
		var inner := first_focusable(c)
		if inner != null:
			return inner
	return null


## "Día 5, otoño, año 1" of an absolute minute (the catalog's calendar).
static func date_label(minute: int, time: Dictionary) -> String:
	var d := Clock.describe(minute, time)
	return SimQuery.t_("ui.menu.date") % [int(d["day"]), SimQuery.t_("season." + str(d["season"])).to_lower(),
		int(d["year"])]


## "Hugo, herrero · Día 5, otoño, año 1" of a save header.
static func who_label(h: Dictionary, time: Dictionary) -> String:
	var prof := str(h.get("profession", ""))
	var who := str(h.get("head_name", ""))
	if prof != "":
		who = SimQuery.t_("ui.saves.who") % [who, SimQuery.t_("profession." + prof).to_lower()]
	var date := date_label(int(h.get("minute", 0)), time)
	return "%s · %s" % [who, date.substr(0, 1).to_upper() + date.substr(1)]


## "1.250 de oro · Ciudadano · deuda pagada" of a save header.
static func how_label(h: Dictionary) -> String:
	var parts: PackedStringArray = [SimQuery.t_("ui.saves.gold") % gold_text(int(h.get("gold", 0)))]
	var title := str(h.get("title", ""))
	if title != "":
		var t := SimQuery.t_("title." + title)
		parts.append(t.substr(0, 1).to_upper() + t.substr(1))
	var debt := int(h.get("debt", 0))
	parts.append(SimQuery.t_("ui.saves.debt") % gold_text(debt) if debt > 0 else SimQuery.t_("ui.saves.no_debt"))
	return " · ".join(parts)


## 1250 -> "1.250" (es) / "1,250" (en).
static func gold_text(n: int) -> String:
	var s := str(absi(n))
	var sep := "," if TranslationServer.get_locale().begins_with("en") else "."
	var out := ""
	while s.length() > 3:
		out = sep + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## "Los Herrero · día 5, otoño, año 1" (the line under Continue).
static func continue_label(h: Dictionary, time: Dictionary) -> String:
	return "%s · %s" % [SimQuery.t_("ui.title.family") % str(h.get("family_name", "")),
		date_label(int(h.get("minute", 0)), time).to_lower()]


## The reason a slot cannot be read ("No se puede leer: …") from SaveFile's error id.
static func broken_label(error: String) -> String:
	var why_key := "ui.saves.error." + error
	var why := SimQuery.t_(why_key)
	if why == why_key:
		why = SimQuery.t_("ui.saves.error.other") % error
	return SimQuery.t_("ui.saves.broken") % why
