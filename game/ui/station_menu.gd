class_name StationMenu
extends PanelContainer
## Context menu of a station (right click in an interior, docs/ui/mecanicas/forja_interior.md §4.1; GDD 4.4.5, 4.6.4):
## one box. On top the station and who works (name · Artesanía), then the mode as a selector of three (Fast / Normal /
## Careful; the chosen one is remembered for that person and station) with what it does in one line, the station's
## recipes (Production.recipe_options) one per row: the output's icon, the name, each input as icon + have/need (red
## when short) and the real duration (Production.owner_cycle_minutes); a recipe that cannot be made is disabled with its
## reason written under it ("Falta 1 lingote de hierro", "El almacén está lleno", "Artesanía 6 (tienes 4)", "Necesita
## Forja de maestro"). Under them the chances of each quality for the recipe under the mouse (or the first one that can
## be made), Production.quality_view, and the right tool's bonus. Stop (stop_work) and "Trabajando: espada 40 %" when
## the person works here. Without anybody of the family inside (management): the job of the station and "Entra con un
## personaje para trabajar aquí" with a Production button; somebody else at the station: "Ocupado por ...". A click
## on a recipe gives work_at. It only gives orders; the sim decides.
## H12.2 (04d 4.22.5.7): a service station (the Consulta's cot, kind "service") has no modes nor quality: its recipes
## show the patient's icon and what they pay, and under them %ServiceBox: the clients waiting (and the grave ones), the
## price the owner asks with − / + (set_service_price, within its range) and the share it draws (4.22.3.2); its job
## line says «Esperando pacientes» while nobody is being seen. The stat of the station's recipes (Arcano for the
## physician) is the one shown on the head and read for the lock and the quality.

signal production_requested   # the Production button (management mode): the interior opens its panel

const QUALITY_TOKENS: Array[String] = ["texto_tenue", "pergamino", "oro"]   # normal, good, excellent

static var _remembered: Dictionary = {}   # "actor|building|zone" -> mode

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var building: String = ""
var zone: String = ""
var mode: String = ""
var _bound: bool = false
var _focus_recipe: String = ""


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%FastButton as Button).pressed.connect(choose_mode.bind("fast"))
	(%NormalButton as Button).pressed.connect(choose_mode.bind("normal"))
	(%CarefulButton as Button).pressed.connect(func() -> void: choose_mode(third_mode()))
	(%StopButton as Button).pressed.connect(stop)
	(%PriceDown as Button).pressed.connect(nudge_price.bind(-1))
	(%PriceUp as Button).pressed.connect(nudge_price.bind(1))
	(%ProductionButton as Button).pressed.connect(func() -> void:
		close()
		production_requested.emit())


## Opens the menu of `zone` for `actor` ("" = nobody of the family inside: management) at `at` (screen).
func open_for(s: Sim, who: String, bld: String, zone_id: String, at: Vector2 = Vector2.ZERO) -> void:
	_bind()
	sim = s
	actor = who
	building = bld
	zone = zone_id
	mode = str(_remembered.get(_key(), "normal"))
	if mode in ["careful", LiveForge.MODE] and mode != third_mode():
		mode = third_mode()   # 03b §3b.2: at the forge's anvil Forja viva takes the place of «con cuidado»
	_focus_recipe = ""
	spec_contract = ""
	spec_variant = {}
	(%Title as Label).text = SimQuery.zone_name(zone_id)
	(%FastButton as Button).text = SimQuery.t_("ui.station.mode_fast")
	(%NormalButton as Button).text = SimQuery.t_("ui.station.mode_normal")
	(%CarefulButton as Button).text = SimQuery.t_("ui.station.mode_live" if third_mode() == LiveForge.MODE \
		else "ui.station.mode_careful")
	(%StopButton as Button).text = SimQuery.t_("ui.station.stop")
	(%ProductionButton as Button).text = SimQuery.t_("ui.interior.production")
	refresh()
	position = at
	reset_size()
	visible = true
	ViewConfig.info("StationMenu", "open (building=%s, zone=%s, actor=%s, mode=%s, recipes=%d)" % [bld, zone_id, who, mode,
		recipe_options().size()])


func close() -> void:
	visible = false


func _key() -> String:
	return "%s|%s|%s" % [actor, building, zone]


func recipe_options() -> Array:
	if sim == null or actor == "":
		return []
	return SimQuery.recipe_options(sim, actor, building, zone)


## The station where `actor` has a job in this building ("" if none): Stop is offered then.
func _actor_job_zone() -> String:
	if sim == null or actor == "":
		return ""
	return Production.job_zone(sim, actor, building)


## Picks the mode (the selector) and redraws the recipes with its durations and chances. It does not give an order.
func choose_mode(m: String) -> void:
	mode = m
	if actor != "":
		_remembered[_key()] = m
	ViewConfig.info("StationMenu", "mode %s (zone=%s)" % [m, zone])
	refresh()


## Everything the box shows, from the sim.
func refresh() -> void:
	if sim == null:
		return
	var ch: Dictionary = sim.state.characters.get(actor, {})
	var job := SimQuery.job_view(sim, building, zone)
	var other := str(job.get("actor", "")) if not job.is_empty() and str(job.get("actor", "")) != actor else ""
	var stat := station_stat()
	(%Who as Label).text = (SimQuery.t_("ui.station.who") % [str(ch.get("name", "")), int(ch.get("stats", {}).get("craft", 0))]
		if stat == "craft" else SimQuery.t_("ui.station.who_stat") % [str(ch.get("name", "")), SimQuery.t_("stat." + stat),
		int(ch.get("stats", {}).get(stat, 0))]) if actor != "" else ""
	var why := Production.may_work(sim, actor, building) if actor != "" else ""
	var hint := ""
	if actor == "":
		hint = SimQuery.t_("ui.station.enter_to_work")
	elif other != "":
		hint = SimQuery.t_("ui.station.busy_by") % [_name(other), SimQuery.recipe_name(sim.catalog, str(job["recipe"])),
			roundi(float(job.get("progress", 0.0)) * 100.0)]
	elif why != "":
		hint = _reason_line(why)
	elif recipe_options().is_empty():
		hint = SimQuery.t_("ui.station.no_recipes")
	(%Hint as Label).text = hint
	(%Hint as Label).visible = hint != ""
	var can_pick := actor != "" and other == "" and why == ""
	for pair: Array in [["fast", "%FastButton"], ["normal", "%NormalButton"], [third_mode(), "%CarefulButton"]]:
		var b := get_node(str(pair[1])) as Button
		b.set_pressed_no_signal(str(pair[0]) == mode)
		b.disabled = not can_pick
	var svc := service()
	var field := field_station()
	if field:
		mode = "normal"  # H12 Patrón: a field is worked in normal mode, no quality
	(%Modes as Control).visible = actor != "" and svc == "" and not field
	(%ModeLine as Label).visible = (actor != "" and svc == "") or field
	(%ModeLine as Label).text = field_line() if field else _mode_line()
	_build_recipes(can_pick)
	_show_quality()
	_show_service(svc)
	var mine := _actor_job_zone() == zone and actor != ""
	(%StopButton as Button).visible = _actor_job_zone() != ""
	(%ProductionButton as Button).visible = actor == ""
	var line := ""
	if not job.is_empty() and (mine or actor == ""):
		line = SimQuery.t_("ui.station.working") % [SimQuery.recipe_name(sim.catalog, str(job["recipe"])),
			roundi(float(job.get("progress", 0.0)) * 100.0)]
		if bool(job.get("waiting_client", false)):
			line = SimQuery.t_("ui.station.waiting_patients")
		if actor == "":
			line = _name(str(job["actor"])) + " · " + line
	(%JobLine as Label).text = line
	(%Foot as Control).visible = (%StopButton as Button).visible or (%ProductionButton as Button).visible or line != ""
	reset_size()


func _name(id: String) -> String:
	return str(sim.state.characters.get(id, {}).get("name", id))


## "×1,0 tiempo · calidad con tu Artesanía (7)" (+ "· + toque de maestro" when careful).
func _mode_line() -> String:
	if sim == null or actor == "":
		return ""
	var stat := station_stat()
	var q := Production.quality_view(sim, actor, building, mode, stat)
	var out := SimQuery.t_("ui.station.mode_line") % [String.num(float(q.get("minutes_mult", 1.0)), 1).replace(".", ","),
		int(q.get("craft", 0))]
	if stat != "craft":
		out = SimQuery.t_("ui.station.mode_line_stat") % [String.num(float(q.get("minutes_mult", 1.0)), 1).replace(".", ","),
			SimQuery.t_("stat." + stat), int(q.get("craft", 0))]
	# 03b §3b.8: no «+ toque de maestro»: the master touch left the UI (the Forja viva replaces it)
	if mode == LiveForge.MODE:
		out += " · " + SimQuery.t_("ui.station.with_live")
	return out


## Forja viva (03b §3b.2) for whoever the player controls at a station with live recipes; else «con cuidado».
func third_mode() -> String:
	if sim == null or actor == "" or str(sim.state.characters.get(actor, {}).get("controlled_by", "")) != "human":
		return "careful"
	for opt: Dictionary in recipe_options():
		if not LiveForge.recipe_def(sim, str(opt.get("recipe", ""))).is_empty():
			return LiveForge.MODE
	return "careful"


func _build_recipes(can_pick: bool) -> void:
	var list := %RecipeList as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	(%Recipes as Control).visible = actor != ""
	(%Sep as Control).visible = actor != ""
	for opt: Dictionary in recipe_options():
		list.add_child(_recipe_row(opt, can_pick))
	_build_spec(list)


# --- 03b §3b.3 · made to a contract's spec ------------------------------------------------------------------------------

var spec_contract: String = ""      # the accepted contract with a spec the next piece is made for ("" = none)
var spec_variant: Dictionary = {}   # axis -> value chosen (length, guard; temper out of Forja viva)


## The family's accepted contracts with a spec whose item a recipe of this station makes.
func spec_contracts() -> Array:
	var out: Array = []
	if sim == null or actor == "":
		return out
	var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
	var items := {}
	for opt: Dictionary in recipe_options():
		items[str(sim.catalog.recipes().get(str(opt["recipe"]), {}).get("output", {}).get("item", ""))] = str(opt["recipe"])
	for c: Dictionary in Contracts.accepted_of(sim, fam):
		if c.get("spec") is Dictionary and not (c["spec"] as Dictionary).is_empty() and items.has(str(c.get("item", ""))):
			out.append(c)
	return out


func _build_spec(list: VBoxContainer) -> void:
	var cs := spec_contracts()
	if cs.is_empty():
		spec_contract = ""
		return
	var box := VBoxContainer.new()
	box.name = "SpecBox"
	var head := HBoxContainer.new()
	box.add_child(head)
	var pick := OptionButton.new()
	pick.name = "SpecContract"
	pick.focus_mode = Control.FOCUS_NONE
	pick.add_item(SimQuery.t_("ui.station.spec_none"))
	pick.set_item_metadata(0, "")
	var sel := 0
	for i: int in cs.size():
		var c: Dictionary = cs[i]
		pick.add_item(SimQuery.t_("ui.station.spec_for") % [SimQuery.t_("client." + str(c["client"])),
			SimQuery.item_name(sim.catalog, str(c["item"])).to_lower()])
		pick.set_item_metadata(i + 1, str(c["id"]))
		if str(c["id"]) == spec_contract:
			sel = i + 1
	pick.select(sel)
	pick.item_selected.connect(func(i: int) -> void:
		spec_contract = str(pick.get_item_metadata(i))
		refresh())
	head.add_child(pick)
	list.add_child(box)
	if spec_contract == "":
		return
	var c := {}
	for k: Dictionary in cs:
		if str(k["id"]) == spec_contract:
			c = k
	var desc := Label.new()
	desc.name = "SpecDesc"
	desc.text = SimQuery.t_("spec.%s.desc" % str((c.get("spec", {}) as Dictionary).get("id", "")))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(260, 0)
	desc.theme_type_variation = &"DimLabel"
	box.add_child(desc)
	var rid := ""
	for opt: Dictionary in recipe_options():
		if str(sim.catalog.recipes().get(str(opt["recipe"]), {}).get("output", {}).get("item", "")) == str(c.get("item", "")):
			rid = str(opt["recipe"])
	var axes: Array = LiveForge.axes_of(sim, rid)
	if mode != LiveForge.MODE:
		axes.append("temper")
	var row := HBoxContainer.new()
	box.add_child(row)
	for axis: Variant in axes:
		var values: Array = sim.catalog.live_forge.get("quench_media", []) if str(axis) == "temper" \
			else ((sim.catalog.live_forge.get("variants", {}) as Dictionary).get(str(axis), {}) as Dictionary).keys()
		var ob := OptionButton.new()
		ob.name = "Spec_" + str(axis)
		ob.focus_mode = Control.FOCUS_NONE
		for i: int in values.size():
			ob.add_item(SimQuery.t_("live.variant.%s.%s" % [axis, values[i]]))
			ob.set_item_metadata(i, str(values[i]))
		if not spec_variant.has(str(axis)):
			spec_variant[str(axis)] = str(values[0])
		ob.select(maxi(0, values.find(str(spec_variant[str(axis)]))))
		var a := str(axis)
		ob.item_selected.connect(func(i: int) -> void:
			spec_variant[a] = str(ob.get_item_metadata(i))
			ViewConfig.info("StationMenu", "variant %s=%s" % [a, spec_variant[a]]))
		row.add_child(ob)


## One recipe: [icon] Name · inputs have/need · duration, and the reason under it when it cannot be made.
func _recipe_row(opt: Dictionary, can_pick: bool) -> VBoxContainer:
	var rid := str(opt.get("recipe", ""))
	var status := str(opt.get("status", "ok"))
	var reason := str(opt.get("reason", ""))
	var rec: Dictionary = sim.catalog.recipes().get(rid, {})
	var box := VBoxContainer.new()
	box.name = "Row_" + rid
	box.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	var b := Button.new()
	b.name = rid
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = SimQuery.recipe_name(sim.catalog, rid)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.icon = UiIcons.lock() if status == "locked" else VisualPaths.icon_small(str(rec.get("output", {}).get("item", "")))
	if Production.is_service(rec) and status != "locked":
		b.icon = UiIcons.ui("icon_patient")
	b.disabled = status != "ok" or not can_pick
	b.tooltip_text = _status_tip(rid, status, reason)
	b.pressed.connect(choose_recipe.bind(rid))
	b.mouse_entered.connect(func() -> void:
		_focus_recipe = rid
		_show_quality())
	row.add_child(b)
	if status != "locked":
		var stock: Dictionary = opt.get("stock", {})
		for inp: Dictionary in rec.get("inputs", []):
			var item := str(inp.get("item", ""))
			var have := int(stock.get(item, 0))
			var need := int(inp.get("qty", 0))
			var icon := UiIcons.item_rect(item)
			if icon != null:
				row.add_child(icon)
			var l := Label.new()
			l.text = "%d/%d" % [have, need]
			l.theme_type_variation = &"ReasonLabel" if have < need else &""
			row.add_child(l)
		var d := Label.new()
		d.name = "Duration"
		d.text = SimQuery.duration_label(Production.owner_cycle_minutes(sim, building, rec, mode))
		d.custom_minimum_size = Vector2(44, 0)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(d)
		if Production.is_service(rec):
			var pay := Label.new()
			pay.name = "Pays"
			pay.text = SimQuery.t_("ui.station.pays") % Services.charge(sim, building, rec)
			pay.theme_type_variation = &"PositiveLabel"
			row.add_child(pay)
	var why := _recipe_reason(rid, status, reason, opt)
	if why != "":
		var r := Label.new()
		r.name = "Reason"
		r.text = why
		r.theme_type_variation = &"ReasonLabel"
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.custom_minimum_size = Vector2(260, 0)
		if status == "locked":
			r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(r)
	return box


## The reason of a recipe that cannot be made, in words with its figures (_comun.md, "Motivos de rechazo").
func _recipe_reason(rid: String, status: String, reason: String, opt: Dictionary) -> String:
	var rec: Dictionary = sim.catalog.recipes().get(rid, {})
	match reason:
		"skill_too_low":
			var st := str(rec.get("stat", "craft"))
			if st != "craft":
				return SimQuery.t_("ui.station.needs_stat") % [SimQuery.t_("stat." + st), int(rec.get("min_stat", 1)),
					int(sim.state.characters.get(actor, {}).get("stats", {}).get(st, 0))]
			return SimQuery.t_("ui.station.needs_craft") % [int(rec.get("min_craft", 0)),
				int(sim.state.characters.get(actor, {}).get("stats", {}).get("craft", 0))]
		"needs_upgrade":
			return SimQuery.t_("ui.station.needs_upgrade") % SimQuery.upgrade_name(sim.catalog, str(rec.get("requires_upgrade", "")))
		"missing_inputs":
			var stock: Dictionary = opt.get("stock", {})
			var parts: PackedStringArray = []
			for inp: Dictionary in rec.get("inputs", []):
				var short := int(inp.get("qty", 0)) - int(stock.get(str(inp.get("item", "")), 0))
				if short > 0:
					parts.append("%d × %s" % [short, SimQuery.item_name(sim.catalog, str(inp.get("item", ""))).to_lower()])
			return SimQuery.t_("ui.station.missing") % ", ".join(parts)
		"storage_full":
			return SimQuery.t_("ui.recipe.no_room")
	return "" if status == "ok" else SimQuery.reason_text(reason)


func _reason_line(why: String) -> String:
	if why == "under_works":
		var w := SimQuery.upgrade_works(sim, building)
		if not w.is_empty():
			return SimQuery.t_("ui.interior.works") % [SimQuery.upgrade_name(sim.catalog, str(w.get("upgrade", ""))),
				SimQuery.minutes_left_label(int(w.get("minutes_left", 0)))]
	return SimQuery.reason_text(why)


## The chances of each quality for the recipe under the mouse, else the first one that can be made.
func _show_quality() -> void:
	var box := %QualityBox as Control
	var options := recipe_options()
	var rid := _focus_recipe
	if rid == "":
		for opt: Dictionary in options:
			if str(opt.get("status", "")) == "ok":
				rid = str(opt["recipe"])
				break
	if rid == "" and not options.is_empty() and str(options[0].get("status", "")) != "locked":
		rid = str(options[0]["recipe"])
	box.visible = actor != "" and rid != "" and service() == "" and not field_station()
	if not box.visible:
		return
	var rec: Dictionary = sim.catalog.recipes().get(rid, {})
	var q := Production.quality_view(sim, actor, building, mode, str(rec.get("stat", "craft")))
	var chances: Array = q.get("chances", [100, 0, 0])
	var item := str(rec.get("output", {}).get("item", ""))
	(%QualityTitle as Label).text = SimQuery.t_("ui.station.quality") % SimQuery.item_name(sim.catalog, item).to_lower()
	(%QualityNumbers as Label).text = "%d · %d · %d %%" % [int(chances[0]), int(chances[1]), int(chances[2])]
	var bar := %QualityBar as HBoxContainer
	for c: Node in bar.get_children():
		bar.remove_child(c)
		c.queue_free()
	for i: int in 3:
		if int(chances[i]) <= 0:
			continue
		var seg := ColorRect.new()
		seg.name = "Q%d" % i
		seg.color = Color.html(_token(QUALITY_TOKENS[i]))
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = float(chances[i])
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg.tooltip_text = SimQuery.quality_name(i)
		bar.add_child(seg)
	var tool_line := %ToolLine as Label
	tool_line.visible = bool(q.get("tool", false))
	if tool_line.visible:
		var tool := str(sim.catalog.buildings().get(str(sim.state.buildings[building].get("type", "")), {}).get("tool", ""))
		tool_line.text = SimQuery.t_("ui.station.tool_bonus") % [SimQuery.item_name(sim.catalog, tool).to_lower(),
			roundi(float(q.get("tool_chance", 0.0)) * 100.0)]


## H12 Patrón (04d 4.22.4.8): whether this station is a field (its recipes are of kind field).
func field_station() -> bool:
	if sim == null:
		return false
	return Upgrades.zone_kind(sim, building, zone) == Fields.FIELD


## The field's line instead of the modes: its state and when it will be ready (the sowing calendar of one field):
## «Arado · sembrado hoy, listo en 4 días», «Crece: 2 de 4 · listo en 2 días», «Listo: 2 días para cosecharlo»...
func field_line() -> String:
	for row: Dictionary in Fields.view(sim, building):
		if str(row["zone"]) != zone:
			continue
		match str(row["state"]):
			"growing":
				return SimQuery.t_("ui.field.growing") % [int(row["growth"]), int(row["grow"]), int(row["days_to_ready"])]
			"ready":
				return SimQuery.t_("ui.field.ready") % maxi(0, int(row["days_left"]))
			"plowed":
				var d := Fields.sow_preview(sim, "wheat")
				return SimQuery.t_("ui.field.plowed_sow") % d if d >= 0 else SimQuery.t_("ui.field.plowed_wait")
			"rotten":
				return SimQuery.t_("ui.field.rotten")
		return SimQuery.t_("ui.field.fallow")
	return ""


## H12.2: the service of this station ("" if it makes things): the service of its first service recipe.
func service() -> String:
	if sim == null:
		return ""
	for opt: Dictionary in recipe_options():
		var rec: Dictionary = sim.catalog.recipes().get(str(opt.get("recipe", "")), {})
		if Production.is_service(rec):
			return str(rec.get("service", ""))
	return ""


## The stat the station's recipes read (their first recipe's "stat"; craft by default).
func station_stat() -> String:
	if sim == null:
		return "craft"
	for opt: Dictionary in recipe_options():
		return str(sim.catalog.recipes().get(str(opt.get("recipe", "")), {}).get("stat", "craft"))
	return "craft"


## The clients waiting, the price with − / + and the share (a service station only).
func _show_service(svc: String) -> void:
	var box := %ServiceBox as Control
	box.visible = svc != ""
	if svc == "":
		return
	var waiting: Array = Services.waiting(sim.state, building).filter(func(w: Dictionary) -> bool:
		return str(w.get("service", "")) == svc)
	var grave := waiting.filter(func(w: Dictionary) -> bool: return int(w.get("severity", 0)) >= 7).size()
	(%Waiting as Label).text = SimQuery.t_("ui.station.patients_waiting") % [waiting.size(), grave] if not waiting.is_empty() \
		else SimQuery.t_("ui.station.no_patients")
	var p := Services.price(sim, building, svc)
	var r := Services.price_range(sim, svc)
	(%PriceLabel as Label).text = SimQuery.t_("ui.station.price") % [p, int(Services.cfg(sim, svc).get("ref_price", 0))]
	var who := _price_actor()
	(%PriceDown as Button).disabled = who == "" or p <= int(r[0])
	(%PriceUp as Button).disabled = who == "" or p >= int(r[1])
	(%ShareLine as Label).text = SimQuery.t_("ui.station.patients_day") % String.num(
		Services.per_day(sim, building, svc), 1).replace(".", ",")


## Who of the family gives the price order: the one at the station, else the family's head (management).
func _price_actor() -> String:
	if sim == null:
		return ""
	var fam := str(sim.state.buildings.get(building, {}).get("owner", ""))
	if fam == "" or fam != SimQuery.player_family(sim.state):
		return ""
	if actor != "":
		return actor
	return SimQuery.family_actor(sim.state, fam, "")


## − / +: the price of the station's service one gold down or up (set_service_price).
func nudge_price(step: int) -> void:
	var svc := service()
	var who := _price_actor()
	if svc == "" or who == "":
		return
	var r := Services.price_range(sim, svc)
	var p := clampi(Services.price(sim, building, svc) + step, int(r[0]), int(r[1]))
	_give({"type": "set_service_price", "actor": who, "building": building, "service": svc, "price": p})
	refresh()


## The quality chances shown now ([normal, good, excellent] in %), for the tests.
func shown_chances() -> Array:
	var t := (%QualityNumbers as Label).text.replace(" %", "")
	var out: Array = []
	for p: String in t.split(" · "):
		out.append(p.to_int())
	return out


static func _token(id: String) -> String:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/ui/tokens.json"))
	return str((d as Dictionary).get("color", {}).get(id, "#ece4d2")) if d is Dictionary else "#ece4d2"


## The recipe buttons, one per recipe (named by its id).
func recipe_buttons() -> Array:
	var out: Array = []
	for row: Node in (%RecipeList as VBoxContainer).get_children():
		var b := row.get_child(0).get_child(0) as Button
		out.append(b)
	return out


## The reason line under a recipe ("" if it can be made), for the tests.
func reason_of(rid: String) -> String:
	var row := (%RecipeList as VBoxContainer).get_node_or_null("Row_" + rid)
	var l := row.get_node_or_null("Reason") as Label if row != null else null
	return l.text if l != null else ""


func _status_tip(rid: String, status: String, reason: String) -> String:
	var rec: Dictionary = sim.catalog.recipes().get(rid, {})
	var out := SimQuery.recipe_name(sim.catalog, rid)
	out += "\n" + SimQuery.t_("ui.recipe.duration") % float(rec.get("duration_hours", 0.0))
	match status:
		"locked":
			if reason == "needs_upgrade":
				out += "\n" + SimQuery.reason_text(reason)
			else:
				out += "\n" + SimQuery.t_("ui.recipe.locked") % int(rec.get("min_craft", 0))
		"missing_inputs":
			out += "\n" + SimQuery.t_("ui.recipe.missing_inputs")
		"no_room":
			out += "\n" + SimQuery.t_("ui.recipe.no_room")
	return out


func choose_recipe(rid: String) -> void:
	if actor == "" or mode == "":
		return
	var o := {"type": "work_at", "actor": actor, "building": building, "zone": zone, "recipe": rid, "mode": mode}
	for c: Dictionary in spec_contracts():
		if str(c["id"]) == spec_contract and str(sim.catalog.recipes().get(rid, {}).get("output", {}).get("item", "")) \
				== str(c.get("item", "")):
			o["contract"] = spec_contract
			var v := {}
			var axes := LiveForge.axes_of(sim, rid)
			for k: String in spec_variant:
				if (k == "temper" and mode != LiveForge.MODE) or k in axes:
					v[k] = spec_variant[k]
			o["variant"] = v
	_give(o)
	close()


func stop() -> void:
	if actor == "":
		return
	_give({"type": "stop_work", "actor": actor})
	close()


func _give(o: Dictionary) -> void:
	ViewConfig.info("StationMenu", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
