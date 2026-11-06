extends "res://tests/test_case.gd"
## The verification through the interface (docs/gdd/07_testing.md §7.6): every flow of data/flows/ is well formed (its
## id is its file name, it says where it starts, each step has one action or a wait, its checks and conditions parse as
## expressions over FlowQuery); the visual audit measures contrast as WCAG does and finds a text cut in its box, an
## i18n key and a bracketed id on screen; the driver finds a control by its name, its text and its row.

const ACTIONS: Array[String] = ["click", "right_click", "double_click", "popup", "spin", "key", "hold", "type", "world",
	"station", "inn", "door", "wheel", "pan", "release_focus", "restart", "key_audit", "context_setup", "harness_game"]
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


## Every scenario a flow starts in (or restarts in) is in data/scenarios/: a flow never fails for a missing start.
func test_flow_scenarios_exist() -> void:
	for f: String in _flows():
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/flows/" + f))
		var starts: Array = [d.get("start", {})]
		for s: Dictionary in d.get("steps", []):
			if s.get("restart") is Dictionary:
				starts.append(s["restart"])
		for st: Dictionary in starts:
			if st.has("scenario"):
				check(FileAccess.file_exists("res://data/scenarios/%s.json" % st["scenario"]),
					"%s: the scenario %s exists" % [f, st["scenario"]])


## The judge of the family (verificación D, tribunal.md §2 «Presidir»): in judge_family Hugo holds the judge's seat,
## is no party to the rival's trial and may rule it once its hearing starts.
func test_judge_family_can_rule() -> void:
	var r := NewGame.from_scenario("judge_family")
	check(bool(r["ok"]), "judge_family loads")
	if not bool(r["ok"]):
		return
	var sim := Sim.new(r["state"], Catalog.load_from())
	var open: Array = Tribunal.open_trials(sim)
	check(open.size() == 1, "one trial open (%d)" % open.size())
	if open.is_empty():
		return
	var tid := str(open[0]["id"])
	eq(Tribunal.verdict_status(sim, "chr_0001", tid, "innocent"), "trial_not_in_hearing", "before the hearing, not yet")
	sim.run_minutes(10)
	eq(str(Tribunal.trial(sim.state, tid)["status"]), "hearing", "the hearing has started")
	eq(Tribunal.verdict_status(sim, "chr_0001", tid, "innocent"), "", "Hugo may rule")


class FakeGame extends Node:
	var paused: bool = true
	var orders: Array = []

	func pending() -> Array:
		return orders


## An order given in pause (verificación E1): the screen that paused knows it waits, and lists it with its label; with
## the clock running nothing waits.
func test_paused_orders_wait_and_are_listed() -> void:
	var r := NewGame.from_scenario("patron_treaties")
	check(bool(r["ok"]), "patron_treaties loads")
	if not bool(r["ok"]):
		return
	var sim := Sim.new(r["state"], Catalog.load_from())
	var g := FakeGame.new()
	g.orders = [{"type": "propose_town_treaty", "actor": "chr_0001", "city": "hamlet", "kind": "exemption", "queued": true}]
	check(PausedOrders.waiting(g, "propose_town_treaty", {"city": "hamlet"}), "the town treaty waits")
	check(not PausedOrders.waiting(g, "propose_town_treaty", {"city": "abbey"}), "not another city's")
	var ls := PausedOrders.lines(g, sim, "fam_0001")
	check(ls.size() == 1 and ls[0].contains("Vilablat"), "its line names the city (%s)" % [ls])
	g.paused = false
	check(not PausedOrders.waiting(g, "propose_town_treaty"), "with the clock running nothing waits")
	g.free()


## The portrait by age (verificación E2): each age takes its band, and a tone kept for age (the white, index 5) is
## drawn with its natural one: a girl of 8 whose mother has it in the data is not white-haired.
func test_portrait_band_and_no_white_hair_when_young() -> void:
	for pair: Array in [[0, "child"], [8, "child"], [12, "youth"], [16, "youth"], [45, "mature"], [62, "elder"]]:
		eq(Identity.stage(int(pair[0])), str(pair[1]), "age %d" % pair[0])
	check(Identity.natural_hair(5) != 5, "the white is not a natural tone")
	eq(Identity.natural_hair(2), 2, "a natural tone stays")
	var r := NewGame.from_scenario("family_ages")
	check(bool(r["ok"]), "family_ages loads")
	if not bool(r["ok"]):
		return
	var st: WorldState = r["state"]
	var grey := ViewConfig.color(str((ViewConfig.value("portraits", {}) as Dictionary).get("greying", {}).get("grey", "#d8d0c0")))
	for c: String in st.characters:
		var ch: Dictionary = st.characters[c]
		if str(ch.get("family", "")) != "fam_0001" or str(ch.get("name", "")) != "Elvira":
			continue
		eq(int(ch["visual"]["hair"]), 5, "Elvira carries the white in the data")
		var id := Identity.of(st, c)
		eq(str(id["portrait"]["stage"]), "child", "Elvira's band")
		check(not (id["hair"] as Color).is_equal_approx(grey), "Elvira is not drawn white-haired (%s)" % id["hair"])
		var tex := Identity.portrait_texture(id, 64)
		check(tex != null and tex.resource_path.contains("/f/child/"), "a girl's child portrait (%s)" % (tex.resource_path if tex else "null"))


## A kept portrait id that is no longer of the person's sex or age band (it changes at the year change) gives way to one
## of its band and sex now (verificación E2): a boy of 0 never shows a girl's portrait, a man of 62 never a child's.
func test_kept_portrait_of_another_band_gives_way() -> void:
	var boy := {"female": false, "portrait": {"id": "f_child_artisan_04", "type": "artisan", "stage": "child", "seed": 22}}
	var tex := Identity.portrait_texture(boy, 64)
	check(tex != null and tex.resource_path.contains("/m/child/"), "a boy's child portrait (%s)" % (tex.resource_path if tex else "null"))
	var old := {"female": false, "portrait": {"id": "m_child_artisan_02", "type": "artisan", "stage": "elder", "seed": 1}}
	tex = Identity.portrait_texture(old, 64)
	check(tex != null and tex.resource_path.contains("/m/elder/"), "an elder's portrait (%s)" % (tex.resource_path if tex else "null"))
	var same := {"female": true, "portrait": {"id": "f_child_artisan_04", "type": "artisan", "stage": "child", "seed": 9}}
	tex = Identity.portrait_texture(same, 64)
	check(tex != null and tex.resource_path.ends_with("f_child_artisan_04.png"), "a fitting id is kept")
