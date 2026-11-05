class_name LiveForgeScreen
extends Control
## Forja viva (docs/gdd/03b_diversion_y_ritmo.md §3b.2): the short screen over the forge's interior while a piece is
## forged by hand in mode "live". Three steps on one panel: Calentar (the iron changes colour in the forge; «Sacar»
## pulls it at the colour shown), Batir (three or four strikes against the template: fuerte, medido, de acabado) and
## Templar (agua, aceite o al aire). «Resolver sin jugar» (Esc) ends the decisions: the piece comes out as in mode
## normal. Then the result: the quality, what the decisions gave (traits) and, if it came out a masterwork, its name on
## a PageCard. Reads LiveForge.view (the sim) every frame and gives only live_forge orders through order_sink; the
## colour's pace on screen is presentation (data/live_forge.json heat_seconds_per_color, real seconds); the verdict is
## the sim's. While it is open the game runs at ×1 (the session's speed comes back when it closes).
## Keys: Espacio = Sacar; 1 / 2 / 3 = the strikes or the media; Esc = Resolver sin jugar (then closes).
## Art by VisualPaths.forge_art (assets/art/ui/forge/: the hearth, the iron of each colour, the strike on the anvil, the
## media of the quench and the trait icons), each with a visible placeholder (the iron's own colour, a flat box) until
## its file exists; the masterwork's illustration events/masterwork.

signal closed
signal stage_shown(stage: String)   # the smoke script takes its captures here

const HEAT_TONES: Dictionary = {"dark_red": "#6b1a12", "cherry": "#b3261e", "orange": "#e0701c", "yellow": "#f2c94c",
	"white": "#f4efe0"}
const TRAIT_COLORS: Dictionary = {"oil_tempered": "#7a5a2a", "hard": "#4a6a8a", "soft": "#a8b0b8",
	"fine_edge": "#b8b8b0", "master_mark": "#c8a84e", "masterwork": "#c8a84e"}
const ICON_COLORS: Dictionary = {"strong": "#8a2a1e", "measured": "#7a6a4a", "finish": "#c8a84e", "water": "#4a6a8a",
	"oil": "#7a5a2a", "air": "#a8b0b8"}
const BLOCKS_CARDS: StringName = &"blocks_unlock_cards"   # while open, the unlock cards wait (UnlockCard)
const KEYS_STRIKE: Array[String] = ["strong", "measured", "finish"]
const KEYS_QUENCH: Array[String] = ["water", "oil", "air"]

var order_sink: Callable = Callable()
var sim: Sim
var building: String = ""
var zone: String = ""
var actor: String = ""
var recipe: String = ""
var heat_index: int = 0          # the colour on screen now (index of heat_colors)
var shown_stage: String = ""
var result: Dictionary = {}      # live_forge_done of this piece ({} until it comes)
var _heat_left: float = 0.0
var _sent: Dictionary = {}       # "stage|n" -> true: an order already given for that decision (one per step)
var _speed_before: int = 0
var _bound: bool = false


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%PullButton as Button).pressed.connect(pull)
	(%SkipButton as Button).pressed.connect(skip)
	(%CloseButton as Button).pressed.connect(close)
	for k: String in KEYS_STRIKE:
		(get_node("%Strike_" + k) as Button).pressed.connect(strike.bind(k))
	for k: String in KEYS_QUENCH:
		(get_node("%Quench_" + k) as Button).pressed.connect(quench.bind(k))
	(%Masterwork as PageCard).button_pressed.connect(func(_id: String) -> void: close())


## Opens on the live job of `zone` at `bld` (the interior calls it on work_started with mode live).
func open_for(s: Sim, bld: String, zone_id: String) -> void:
	_bind()
	sim = s
	building = bld
	zone = zone_id
	var v := LiveForge.view(s, bld, zone_id)
	if v.is_empty():
		return
	actor = str(v["actor"])
	recipe = str(v["recipe"])
	result = {}
	_sent = {}
	heat_index = 0
	_heat_left = _heat_seconds()
	shown_stage = ""
	(%Masterwork as PageCard).visible = false
	_texts()
	visible = true
	add_to_group(BLOCKS_CARDS)
	var g := get_node_or_null("/root/Game")
	if g != null and _speed_before == 0:
		_speed_before = int(g.get("speed"))
		g.call("set_speed", 1)
	refresh()
	ViewConfig.info("LiveForge", "open (building=%s, zone=%s, actor=%s, recipe=%s)" % [bld, zone_id, actor, recipe])


## Closes, or, after a result, goes on to the next piece if the cycle already repeated in live («Seguir»).
func close() -> void:
	if not visible:
		return
	if not result.is_empty():
		var v := LiveForge.view(sim, building, zone)
		if not v.is_empty() and str(v["actor"]) == actor and str(v["stage"]) != "done":
			ViewConfig.info("LiveForge", "next piece (recipe=%s)" % str(v["recipe"]))
			open_for(sim, building, zone)
			return
	visible = false
	remove_from_group(BLOCKS_CARDS)
	(%Masterwork as PageCard).visible = false
	var g := get_node_or_null("/root/Game")
	if g != null and _speed_before > 0:
		g.call("set_speed", _speed_before)
	_speed_before = 0
	ViewConfig.info("LiveForge", "close (recipe=%s, result=%s)" % [recipe, result.get("quality", "-")])
	closed.emit()


func _texts() -> void:
	(%Title as Label).text = SimQuery.t_("live.title") % SimQuery.recipe_name(sim.catalog, recipe)
	(%StepHeat as Label).text = SimQuery.t_("live.step.heat")
	(%StepStrike as Label).text = SimQuery.t_("live.step.strike")
	(%StepQuench as Label).text = SimQuery.t_("live.step.quench")
	(%PullButton as Button).text = SimQuery.t_("live.pull")
	(%SkipButton as Button).text = SimQuery.t_("live.skip")
	(%CloseButton as Button).text = SimQuery.t_("live.close")
	for k: String in KEYS_STRIKE:
		var b := get_node("%Strike_" + k) as Button
		b.text = SimQuery.t_("live.strike." + k)
		b.tooltip_text = SimQuery.t_("live.strike." + k + ".tip")
		b.icon = VisualPaths.forge_art("hammer", Vector2i(32, 32), Color(str(ICON_COLORS.get(k, "#888888"))))
		b.add_theme_constant_override("icon_max_width", 16)   # the strike itself shows on the anvil (StrikeArt)
	for k: String in KEYS_QUENCH:
		var b := get_node("%Quench_" + k) as Button
		b.text = SimQuery.t_("live.quench." + k)
		b.tooltip_text = SimQuery.t_("live.quench." + k + ".tip")
		b.icon = VisualPaths.forge_art("quench_" + k, Vector2i(64, 64), Color(str(ICON_COLORS.get(k, "#888888"))))
		b.add_theme_constant_override("icon_max_width", 32)
	(%Hearth as TextureRect).texture = VisualPaths.forge_art("hearth", Vector2i(64, 64), Color("#5a2a14"))


func _heat_seconds() -> float:
	return maxf(0.3, float(sim.catalog.live_forge.get("heat_seconds_per_color", 2.4))) if sim != null else 2.4


func _colours() -> Array:
	return sim.catalog.live_forge.get("heat_colors", []) if sim != null else []


func _process(delta: float) -> void:
	if not visible or sim == null:
		return
	var v := LiveForge.view(sim, building, zone)
	if not v.is_empty() and str(v["stage"]) == "heat" and not _sent.has("heat"):
		_heat_left -= delta
		if _heat_left <= 0.0 and heat_index < _colours().size() - 1:
			heat_index += 1
			_heat_left = _heat_seconds()
	refresh()


## Everything the panel shows, from the sim.
func refresh() -> void:
	if sim == null:
		return
	var v := LiveForge.view(sim, building, zone)
	var stage := "result" if not result.is_empty() else (str(v.get("stage", "done")) if not v.is_empty() else "done")
	(%Progress as ProgressBar).value = float(v.get("progress", 1.0)) * 100.0
	for pair: Array in [[%StepHeat, "heat"], [%StepStrike, "strike"], [%StepQuench, "quench"]]:
		var l := pair[0] as Label
		l.theme_type_variation = &"SectionTitle" if str(pair[1]) == stage else &"DimLabel"
	(%HeatBox as Control).visible = stage == "heat"
	(%StrikeBox as Control).visible = stage == "strike"
	(%QuenchBox as Control).visible = stage == "quench"
	(%WaitBox as Control).visible = stage == "done" or stage == "result"
	(%SkipButton as Button).visible = stage in ["heat", "strike", "quench"]
	(%CloseButton as Button).visible = stage == "result"
	var know: Dictionary = v.get("learned", {})
	match stage:
		"heat":
			var cols := _colours()
			var c := str(cols[clampi(heat_index, 0, cols.size() - 1)]) if not cols.is_empty() else ""
			(%Iron as ColorRect).color = Color(str(HEAT_TONES.get(c, "#888888")))
			var iron := VisualPaths.forge_art("iron_" + c, Vector2i(64, 64), Color(str(HEAT_TONES.get(c, "#888888"))))
			(%IronArt as TextureRect).texture = iron   # the placeholder is the colour itself
			(%HeatName as Label).text = SimQuery.t_("live.heat." + c)
			var hint := ""
			if c == str(v.get("near_heat", "")) and c != "":
				hint = SimQuery.t_("live.heat.near")
			if c == str(sim.catalog.live_forge.get("burnt", "")):
				hint = SimQuery.t_("live.heat.burnt")
			(%HeatHint as Label).text = hint
			(%HeatKnown as Label).text = SimQuery.t_("live.known_heat") % SimQuery.t_("live.heat." + str(know["heat"])) \
				if know.has("heat") else SimQuery.t_("live.unknown_heat")
		"strike":
			_draw_template(v)
			var done: Array = v.get("strikes", [])
			var art := "strike_" + str(done.back()) if not done.is_empty() else "anvil"
			(%StrikeArt as TextureRect).texture = VisualPaths.forge_art(art, Vector2i(80, 96), Color(str(
				ICON_COLORS.get(str(done.back()) if not done.is_empty() else "", "#4a4a4a"))))
		"quench":
			var need := SimQuery.t_(str(v.get("hint_key", ""))) if str(v.get("hint_key", "")) != "" else ""
			var spec: Dictionary = v.get("spec", {})
			if not spec.is_empty() and str((spec.get("want", {}) as Dictionary).get("id", "")) != "":
				need = SimQuery.t_("spec.%s.desc" % str(spec["want"]["id"]))
			elif know.has("quench"):
				need += "  " + SimQuery.t_("live.known_quench") % SimQuery.t_("live.quench." + str(know["quench"]))
			(%QuenchNeed as Label).text = need
		"done":
			(%WaitLabel as Label).text = SimQuery.t_("live.waiting")
		"result":
			(%WaitLabel as Label).text = _result_text()
	_draw_traits(stage)
	if stage != shown_stage:
		shown_stage = stage
		ViewConfig.info("LiveForge", "stage %s (recipe=%s)" % [stage, recipe])
		stage_shown.emit(stage)


func _draw_template(v: Dictionary) -> void:
	var row := %Template as HBoxContainer
	var size := int(v.get("template_size", 0))
	while row.get_child_count() < size:
		var l := Label.new()
		l.custom_minimum_size = Vector2(58, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(l)
	for i: int in row.get_child_count():
		var l := row.get_child(i) as Label
		l.visible = i < size
		if i >= size:
			continue
		var done: Array = v.get("strikes", [])
		var shown: Array = v.get("template", [])
		var want := str(shown[i]) if i < shown.size() else ""
		if i < done.size():
			var k := str(done[i])
			var ok := want == "" or want == k
			l.text = SimQuery.t_("live.strike.%s.short" % k) + (" ✓" if ok else " ✗")
			l.theme_type_variation = &"PositiveLabel" if ok else &"WarningLabel"
		else:
			l.text = SimQuery.t_("live.strike.%s.short" % want) if want != "" else "?"
			l.theme_type_variation = &"DimLabel"
	(%TemplateHint as Label).text = SimQuery.t_("live.template_seen") if str((v.get("template", [""]) as Array).front()) != "" \
		else SimQuery.t_("live.template_hidden")


## The result's trait icons (and the masterwork's), 32 px with their name as tooltip.
func _draw_traits(stage: String) -> void:
	var row := %Traits as HBoxContainer
	var want: Array = (result.get("traits", []) as Array).duplicate() if stage == "result" else []
	if stage == "result" and str(result.get("masterwork", "")) != "":
		want.append("masterwork")
	if stage == "done":
		want = ["_cold"]   # quenched: the cold piece waits for the cycle to end
	var key := ",".join(want.map(func(t: Variant) -> String: return str(t)))
	if row.get_meta("key", "") == key:
		return
	row.set_meta("key", key)
	for c: Node in row.get_children():
		row.remove_child(c)
		c.queue_free()
	row.visible = not want.is_empty()
	for t: Variant in want:
		var r := TextureRect.new()
		r.name = "Trait_" + str(t)
		r.texture = VisualPaths.forge_art("trait_" + str(t), Vector2i(32, 32), Color(str(TRAIT_COLORS.get(str(t), "#888888"))))
		if str(t) == "_cold":
			r.texture = VisualPaths.forge_art("iron_cold", Vector2i(64, 64), Color("#5a5a5a"))
			r.custom_minimum_size = Vector2(64, 64)
		r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		if str(t) != "_cold":
			r.custom_minimum_size = Vector2(32, 32)
			r.tooltip_text = SimQuery.t_("live.trait." + str(t))
		row.add_child(r)


func _result_text() -> String:
	var q := int(result.get("quality", 0))
	var lines: Array[String] = [SimQuery.t_("live.result") % SimQuery.item_label(sim.catalog,
		str(sim.catalog.recipes().get(recipe, {}).get("output", {}).get("item", "")), q)]
	var steps := int(result.get("steps", 0))
	lines.append(SimQuery.t_("live.steps_%s" % ("up" if steps > 0 else ("down" if steps < 0 else "same"))))
	var traits: Array = result.get("traits", [])
	if not traits.is_empty():
		lines.append(", ".join(traits.map(func(t: Variant) -> String: return SimQuery.t_("live.trait." + str(t)))))
	return "\n".join(lines)


# --- Decisions (orders) ----------------------------------------------------------------------------------------------

## Sacar: pulls the iron at the colour on screen.
func pull() -> void:
	var cols := _colours()
	if cols.is_empty() or _sent.has("heat"):
		return
	_sent["heat"] = true
	_give({"step": "heat", "choice": str(cols[clampi(heat_index, 0, cols.size() - 1)])})


func strike(kind: String) -> void:
	var v := LiveForge.view(sim, building, zone)
	if v.is_empty() or str(v["stage"]) != "strike":
		return
	var n := (v["strikes"] as Array).size()
	if _sent.has("strike|%d" % n):
		return
	_sent["strike|%d" % n] = true
	_give({"step": "strike", "choice": kind})


func quench(medium: String) -> void:
	if _sent.has("quench"):
		return
	_sent["quench"] = true
	_give({"step": "quench", "choice": medium})


## Resolver sin jugar: the decisions end here (the piece comes out as mode normal with what was decided).
func skip() -> void:
	if not _sent.has("skip"):
		_sent["skip"] = true
		_give({"step": "skip"})


func _give(o: Dictionary) -> void:
	var full := {"type": "live_forge", "actor": actor, "building": building, "zone": zone}
	full.merge(o, true)
	ViewConfig.info("LiveForge", "order %s" % [full])
	if order_sink.is_valid():
		order_sink.call(full)


## Keys while open. True if used.
func handle_key(event: InputEvent) -> bool:
	if not visible or not event is InputEventKey or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return false
	var k := (event as InputEventKey).keycode
	var v := LiveForge.view(sim, building, zone)
	var stage := str(v.get("stage", "")) if result.is_empty() else "result"
	if k == KEY_ESCAPE:
		if stage == "result" or stage == "done" or v.is_empty():
			close()
		else:
			skip()
		return true
	if k == KEY_SPACE and stage == "heat":
		pull()
		return true
	var i := [KEY_1, KEY_2, KEY_3].find(k)
	if i >= 0 and stage == "strike":
		strike(KEYS_STRIKE[i])
		return true
	if i >= 0 and stage == "quench":
		quench(KEYS_QUENCH[i])
		return true
	return false


## The sim's events for this station: the piece's result (live_forge_done) and its masterwork.
func on_sim_event(e: Dictionary) -> void:
	if not visible or str(e.get("building", "")) != building:
		return
	match str(e.get("type", "")):
		"live_forge_done":
			if str(e.get("actor", "")) == actor:
				result = e.duplicate(true)
				refresh()
				if str(e.get("masterwork", "")) != "":
					_show_masterwork(str(e["masterwork"]))
		"work_started":
			pass  # the next piece waits behind the result: «Seguir» (close) opens it


func _show_masterwork(id: String) -> void:
	var m: Dictionary = {}
	for p: Dictionary in LiveForge.masterworks_of(sim.state, ""):
		if str(p["id"]) == id:
			m = p
	if m.is_empty():
		return
	var card := %Masterwork as PageCard
	card.show_page({"template": "card", "title": SimQuery.t_("live.masterwork.title"),
		"image": VisualPaths.illustration("events", "masterwork"), "sticky": true,
		"blocks": [{"type": "quote", "text": masterwork_name(sim, m), "who": ""},
			{"type": "paragraph", "text": SimQuery.t_("live.masterwork.body")}],
		"seal": {"text": "M"}, "buttons": [{"id": "ok", "text": SimQuery.t_("live.close"), "primary": true}]})
	card.visible = true
	ViewConfig.info("LiveForge", "masterwork %s: %s" % [id, masterwork_name(sim, m)])


## «La espada de San Martín de los Herrero».
static func masterwork_name(s: Sim, m: Dictionary) -> String:
	return SimQuery.t_("masterwork.name.%s" % str(m.get("item", ""))) % [SimQuery.t_("masterwork.patron." +
		str(m.get("patron", ""))), str(m.get("family_name", ""))]
