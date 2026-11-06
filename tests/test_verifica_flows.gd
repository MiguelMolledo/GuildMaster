extends "res://tests/test_case.gd"
## The verification through the interface (docs/gdd/07_testing.md §7.6): every flow of data/flows/ is well formed (its
## id is its file name, it says where it starts, each step has one action or a wait, its checks and conditions parse as
## expressions over FlowQuery); the visual audit measures contrast as WCAG does and finds a text cut in its box, an
## i18n key and a bracketed id on screen; the driver finds a control by its name, its text and its row.

const ACTIONS: Array[String] = ["click", "right_click", "double_click", "popup", "spin", "key", "hold", "type", "world",
	"station", "door", "wheel", "pan", "release_focus", "restart", "key_audit", "context_setup", "harness_game"]
const KEYS: Array[String] = ["id", "say", "until", "timeout", "fast", "wait", "expect", "soft", "when", "shot", "button",
	"double", "shift", "item", "times", "up", "frames", "context", "does", "may_do_nothing", "both", "camera", "settle",
	"restore", "no_dismiss", "mouse_only"]


func _flows() -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at("res://data/flows"):
		if f.ends_with(".json") and not f.begins_with("_"):
			out.append(f)
	out.sort()
	return out


func _parses(src: String) -> bool:
	var e := Expression.new()
	return e.parse(src, ["q"]) == OK


func test_flows_are_well_formed() -> void:
	var files := _flows()
	check(files.size() >= 15, "at least 15 flows (%d)" % files.size())
	for f: String in files:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/flows/" + f))
		check(d is Dictionary, "%s is JSON" % f)
		if not d is Dictionary:
			continue
		eq(str(d.get("id", "")), f.get_basename(), "%s: its id is its file name" % f)
		check(str(d.get("title", "")) != "", "%s has a title" % f)
		check(d.get("start") is Dictionary, "%s says where it starts" % f)
		var ids: Dictionary = {}
		for s: Dictionary in d.get("steps", []):
			var sid := str(s.get("id", ""))
			check(sid != "" and not ids.has(sid), "%s: step id %s is set and unique" % [f, sid])
			ids[sid] = true
			var acts := 0
			for k: String in s:
				if k in ACTIONS:
					acts += 1
				else:
					check(k in KEYS, "%s/%s: known key %s" % [f, sid, k])
			check(acts <= 1, "%s/%s: one action at most" % [f, sid])
			check(acts == 1 or s.has("until") or s.has("wait") or s.has("expect"), "%s/%s: does or checks something" % [f, sid])
			for e: Variant in s.get("expect", []):
				check(_parses(str(e)), "%s/%s: expect parses: %s" % [f, sid, e])
			for k: String in ["until", "when"]:
				if s.has(k):
					check(_parses(str(s[k])), "%s/%s: %s parses: %s" % [f, sid, k, s[k]])


func test_quick_flows_for_run_all() -> void:
	var quick := 0
	for f: String in _flows():
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/flows/" + f))
		quick += 1 if bool(d.get("quick", false)) else 0
	check(quick >= 3 and quick <= 5, "3-4 quick flows for the ui step of run_all (%d)" % quick)


func test_contrast_is_wcag() -> void:
	near(VisualAudit.contrast(Color.WHITE, Color.BLACK), 21.0, 0.01, "white on black is 21:1")
	near(VisualAudit.contrast(Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5)), 1.0, 0.001, "same colour is 1:1")
	check(VisualAudit.contrast(Color("#ece4d2"), Color("#2a1f14")) > 7.0, "the theme's text on its section reads well")


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = load("res://game/ui/greybox_theme.tres")
	return l


func test_audit_finds_cut_text_and_keys() -> void:
	var a := VisualAudit.new()
	var vp := Rect2(0, 0, 960, 540)
	var out: Array = []
	var l := _label("Un texto bastante más largo que su caja")
	l.clip_text = true
	a._check_fit(out, l, Rect2(10, 10, 60, 16), l.text, vp, false, null)
	check(out.size() == 1 and str(out[0]["kind"]) == "cut", "a clipped text is cut (%s)" % [out])
	out.clear()
	var ok := _label("Libro")
	a._check_fit(out, ok, Rect2(10, 10, 120, 16), ok.text, vp, false, null)
	check(out.is_empty(), "a short text fits (%s)" % [out])
	out.clear()
	var k := _label("ui.market.buy")
	a._check_key(out, k, Rect2(0, 0, 80, 16), k.text)
	check(out.size() == 1 and str(out[0]["kind"]) == "i18n", "an i18n key on screen (%s)" % [out])
	out.clear()
	var b := _label("Boda de [noble_wedding]")
	a._check_key(out, b, Rect2(0, 0, 80, 16), b.text)
	check(out.size() == 1 and str(out[0]["kind"]) == "i18n", "a bracketed id on screen (%s)" % [out])
	out.clear()
	var plain := _label("Comprar 2 lingotes")
	a._check_key(out, plain, Rect2(0, 0, 80, 16), plain.text)
	check(out.is_empty(), "a normal sentence is not a key (%s)" % [out])
	out.clear()
	var tiny := _label("x")
	tiny.add_theme_font_override("font", load("res://assets/art/ui/fonts/pixel_operator.ttf"))
	tiny.add_theme_font_size_override("font_size", 6)
	a._check_font(out, tiny, Rect2(0, 0, 10, 10))
	check(out.size() == 1 and str(out[0]["kind"]) == "small_font", "6 px is under the minimum (%s)" % [out])
	for n: Node in [l, ok, k, b, plain, tiny]:
		n.free()


func test_driver_finds_by_name_text_and_row() -> void:
	var root := VBoxContainer.new()
	for item: String in ["wood", "iron"]:
		var row := HBoxContainer.new()
		row.name = item + "_0"
		var n := Label.new()
		n.text = item.capitalize()
		var buy := Button.new()
		buy.name = "Buy"
		buy.text = "Comprar"
		row.add_child(n)
		row.add_child(buy)
		root.add_child(row)
	var d := UiDriver.new(null)
	var by_prefix := d.find({"within": {"prefix": "iron_", "any": true}, "node": "Buy", "any": true}, root)
	check(by_prefix.has("node") and (by_prefix["node"] as Node).get_parent().name == "iron_0", "by row name (%s)" % [by_prefix])
	var by_row := d.find({"text": "Comprar", "row": "Wood", "any": true}, root)
	check(by_row.has("node") and (by_row["node"] as Node).get_parent().name == "wood_0", "by the text of its row (%s)" % [by_row])
	check(d.find({"node": "Nope", "any": true}, root).has("error"), "a missing control says so")
	root.free()


## Every order of Orders.apply has its line for the queue (ui.order.<type>): the paused queue never shows an id.
func test_every_order_has_a_queue_label() -> void:
	var src := FileAccess.get_file_as_string("res://sim/core/orders.gd")
	var body := src.substr(src.find("match type:"))
	var types: Array = []
	for line: String in body.split("\n").slice(1):
		if line.strip_edges() != "" and not line.begins_with("\t\t"):
			break
		var m := RegEx.create_from_string("^\t\t\"([a-z_]+)\":").search(line)
		if m != null:
			types.append(m.get_string(1))
	check(types.size() > 40, "the orders are read (%d)" % types.size())
	for t: String in types:
		if t == "wait":
			continue
		var key := "ui.order." + t
		check(TranslationServer.translate(key) != key, "%s has its queue line" % t)


## The keyboard (verificación C13): a button made without focus takes it; a SpinBox gives it to its field; a control
## of the town (under a Node2D) is left alone.
func test_key_nav_makes_the_interface_focusable() -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	KeyNav._apply(b)
	eq(b.focus_mode, Control.FOCUS_ALL, "a button takes the focus")
	var sb := SpinBox.new()
	KeyNav._apply(sb)
	eq(sb.focus_mode, Control.FOCUS_NONE, "the spin box itself does not")
	eq(sb.get_line_edit().focus_mode, Control.FOCUS_ALL, "its field does")
	var town := Node2D.new()
	var w := Button.new()
	w.focus_mode = Control.FOCUS_NONE
	town.add_child(w)
	KeyNav._apply(w)
	eq(w.focus_mode, Control.FOCUS_NONE, "a control of the town is not the interface")
	for n: Node in [b, sb, town]:
		n.free()
