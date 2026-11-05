class_name OfficesPanel
extends PanelContainer
## The town's offices (GDD 4.12.3-4.12.4, H10; docs/ui/mecanicas/cargos_y_elecciones.md), a big modal. Left, the tree
## of seats (mayor at the top, then councillors, judge and constable, collector and inspector): each seat with its
## holder's portrait in its family colour or «?» VACANTE, until when or the vote day, an «urna» mark while its election
## is open and «tuyo» if it is the family's; a click picks the seat. Right, three tabs:
## · Cargos: the picked seat (salary, term, passives and powers, the title it asks and whether the family has it), its
##   calendar line (registration · campaign · vote, today marked), the candidates and one «Presentarse» at the chosen
##   level, off with its reason and when it opens again; a level that costs gold asks first.
## · Campaña (while the selected person is a candidate): office, days left, the calendar, «cómo vas» as a band
##   (Elections.forecast, worked out at dawn), the candidates with their level and what they did (speech today,
##   bribes), the public speech (off with its reason and the odds as a band) and «Elegir vecino en el mapa» (closes
##   the chart: visit, bribe and defame are on the townsperson's sheet).
## · Poderes (while the selected person holds an office): what is in force (regulations, tax) with its end, one row per
##   power with its arguments, its cooldown as a bar, the later ones off with their milestone; using one asks first.
## Opens with key O, the HUD's Offices button or from the town hall; closes with ESC or X. Only gives orders.

signal closed

const ROWS: Array = [["mayor"], ["councillor"], ["judge", "constable"], ["tax_collector", "market_inspector"]]

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var office: String = ""        # the picked seat's office
var tab: String = "offices"    # offices | campaign | powers
var _sig: String = ""
var _bound: bool = false
var _level: String = "basic"
var _item: String = "sword"
var _target_family: String = ""
var _tax: int = 10
var _forecast_day: int = -1
var _forecast: Dictionary = {}


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%SpeechButton as Button).pressed.connect(_speech)
	(%RunButton as Button).pressed.connect(request_run)
	(%PickNeighbour as Button).pressed.connect(close)
	for t: String in ["offices", "campaign", "powers"]:
		var k := t
		(get_node("%Tab_" + t) as Button).pressed.connect(func() -> void: show_tab(k))
	var lv := %LevelOption as OptionButton
	lv.item_selected.connect(func(i: int) -> void:
		_level = str(lv.get_item_metadata(i))
		_sig = "")


func open_for(s: Sim, who: String) -> void:
	_bind()
	sim = s
	actor = who
	(%Title as Label).text = SimQuery.t_("ui.offices.title_town")
	(%LevelLabel as Label).text = SimQuery.t_("ui.offices.level")
	(%SpeechButton as Button).text = SimQuery.t_("campaign.speech")
	(%RunButton as Button).text = SimQuery.t_("ui.offices.run")
	(%PickNeighbour as Button).text = SimQuery.t_("ui.offices.pick_neighbour")
	(%CampaignHint as Label).text = SimQuery.t_("ui.offices.sheet_hint")
	(%Legend as Label).text = SimQuery.t_("ui.offices.legend")
	for t: String in ["offices", "campaign", "powers"]:
		(get_node("%Tab_" + t) as Button).text = SimQuery.t_("ui.offices.tab_" + t)
	var lv := %LevelOption as OptionButton
	lv.clear()
	var levels: Array = sim.catalog.politics.get("elections", {}).get("level_order", [])
	var lvs: Dictionary = sim.catalog.politics.get("elections", {}).get("levels", {})
	for i: int in levels.size():
		var g := int(lvs.get(str(levels[i]), {}).get("gold", 0))
		lv.add_item(SimQuery.t_("campaign.level." + str(levels[i])))
		lv.set_item_metadata(i, str(levels[i]))
		if str(levels[i]) == _level:
			lv.select(i)
	var notes: PackedStringArray = []
	for l: Variant in levels:
		var d: Dictionary = lvs.get(str(l), {})
		notes.append(SimQuery.t_("ui.offices.level_note") % [SimQuery.t_("campaign.level." + str(l)),
			(SimQuery.t_("ui.offices.free") if int(d.get("gold", 0)) == 0 else str(int(d.get("gold", 0)))),
			roundi(float(d.get("bonus_permil", 0)) / 10.0)])
	(%LevelsNote as Label).text = ""   # the level names already say their cost and bonus
	(%LevelsNote as Label).visible = false
	office = _default_office()
	var camp := Elections.campaign_of(sim, actor)
	tab = "campaign" if not camp.is_empty() else ("powers" if not Offices.powers(sim, actor).is_empty() and tab == "powers" else "offices")
	visible = true
	refresh(true)
	ViewConfig.info("OfficesPanel", "open (actor=%s, office=%s)" % [who, office])


## The seat picked on opening: the selected person's candidacy, then its office, then the first one it could run for.
func _default_office() -> String:
	var cc := Elections.candidacy(sim.state, actor)
	if not cc.is_empty():
		return str(cc["election"]["office"])
	var held := Offices.of_character(sim.state, actor)
	if held != "":
		return held
	for o: String in sim.catalog.office_chart():
		if Elections.run_status(sim, actor, o, "basic") == "":
			return o
	return str(sim.catalog.office_chart()[0]) if not sim.catalog.office_chart().is_empty() else ""


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func pick(o: String) -> void:
	office = o
	show_tab("offices")


func show_tab(t: String) -> void:
	tab = t
	refresh(true)


func _process(_delta: float) -> void:
	if visible and sim != null:
		refresh()


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var chart := Offices.chart(sim)
	var camp := Elections.campaign_of(sim, actor)
	var powers := Offices.powers(sim, actor)
	var pw: Array = []  # the cooldown by the hour: rebuilding every minute would close an open picker
	for p: Dictionary in powers:
		pw.append([p["power"], p["reason"], ceili(float(int(p["cooldown_minutes"])) / 60.0)])
	var cc := Elections.candidacy(sim.state, actor)
	var sig := "%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s|%s" % [actor, chart, camp, pw, office, _level, _item, _tax,
		_target_family, tab, cc.get("candidate", {}), Elections.run_status(sim, actor, office, _level)] \
		+ "|%d|%d" % [(sim.state.market.get("regulations", []) as Array).size(), Offices.today(sim)]
	if sig == _sig and not force:
		return
	_sig = sig
	var st := sim.state
	var ch: Dictionary = st.characters.get(actor, {})
	var fam := str(ch.get("family", ""))
	var tn := SimQuery.title_name(Titles.current(sim, fam))
	(%WhoLabel as Label).text = "%s · %s" % [str(ch.get("name", "—")), tn.substr(0, 1).to_upper() + tn.substr(1)] \
		if not ch.is_empty() else SimQuery.t_("ui.npc.no_actor")
	(%WhoBadge as TextureRect).texture = UiIcons.mark("badge_title_" + Titles.current(sim, fam)) if not ch.is_empty() else null
	(%Tab_campaign as Button).visible = not camp.is_empty()
	(%Tab_powers as Button).visible = not powers.is_empty()
	if tab == "campaign" and camp.is_empty() or tab == "powers" and powers.is_empty():
		tab = "offices"
	for t: String in ["offices", "campaign", "powers"]:
		(get_node("%Tab_" + t) as Button).set_pressed_no_signal(t == tab)
	(%OfficePage as Control).visible = tab == "offices"
	(%CampaignBox as Control).visible = tab == "campaign"
	(%PowersBox as Control).visible = tab == "powers"
	_fill_chart(chart)
	_fill_detail(chart)
	_fill_campaign(camp)
	_fill_powers(powers)


# --- the tree of seats ---------------------------------------------------------------------------------------------

func _fill_chart(chart: Array) -> void:
	var box := %Chart as VBoxContainer
	SocialKit.clear(box)
	var by := {}
	for row: Dictionary in chart:
		by[str(row["office"])] = row
	var my_fam := str(sim.state.characters.get(actor, {}).get("family", ""))
	var done := {}
	for line: Array in ROWS:
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 8)
		for o: Variant in line:
			if not by.has(str(o)):
				continue
			done[str(o)] = true
			var row: Dictionary = by[str(o)]
			for i: int in (row["seats"] as Array).size():
				h.add_child(_seat(row, i, my_fam))
		if h.get_child_count() > 0:
			box.add_child(h)
	for row: Dictionary in chart:  # offices of the data not in the drawing's rows
		if not done.has(str(row["office"])):
			var h := HBoxContainer.new()
			for i: int in (row["seats"] as Array).size():
				h.add_child(_seat(row, i, my_fam))
			box.add_child(h)


func _seat(row: Dictionary, i: int, my_fam: String) -> Control:
	var o := str(row["office"])
	var s: Dictionary = row["seats"][i]
	var p := PanelContainer.new()
	p.name = "Office_" + o if i == 0 else "Office_%s_%d" % [o, i + 1]
	p.custom_minimum_size = Vector2(212, 40)
	p.theme_type_variation = &"SelectedRow" if o == office else &"RowPanel"
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pick(o))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	if bool(s["vacant"]):
		var q := PanelContainer.new()
		q.theme_type_variation = &"DarkPanel"
		q.custom_minimum_size = Vector2(32, 32)
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ql := SocialKit.label("?", &"DimLabel")
		ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.add_child(ql)
		h.add_child(q)
	else:
		h.add_child(SocialKit.portrait(sim.state, str(s["holder"])))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := SocialKit.label(SimQuery.office_name(o), SocialKit.OFFICE_VARIATIONS.get("mayor" if o == "mayor" else str(row["rank"]),
		&"BoldLabel"), "Name")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	top.add_child(n)
	if not (row["election"] as Dictionary).is_empty():
		top.add_child(SocialKit.label(SimQuery.t_("ui.offices.urn_badge"), &"CaptionLabel", "Urn"))
	if str(s.get("family", "")) == my_fam and my_fam != "":
		top.add_child(SocialKit.label(SimQuery.t_("ui.offices.yours_badge"), &"CaptionLabel", "Yours"))
	col.add_child(top)
	var holder := ""
	var vote := int(row["election_day"])
	if bool(s["vacant"]):
		holder = SimQuery.t_("ui.offices.vacant_vote_short") % (vote + 1) if vote >= 0 else SimQuery.t_("ui.offices.vacant")
	else:
		holder = SimQuery.t_("ui.offices.holder_short") % [str(s["name"]), str(s["family_name"]), int(s["until"]) + 1]
	var hl := SocialKit.label(holder, &"DimLabel", "Seated")
	hl.clip_text = true
	col.add_child(hl)
	h.add_child(col)
	var last := Elections.last_result(sim.state, o)
	p.tooltip_text = SimQuery.t_("ui.offices.history") % [SimQuery.office_name(o), _history(last)]
	return p


func _history(last: Dictionary) -> String:
	if last.is_empty():
		return SimQuery.t_("ui.offices.no_history")
	var names: PackedStringArray = []
	for w: Variant in last.get("result", {}).get("winners", []):
		names.append(str(sim.state.characters.get(str(w), {}).get("name", w)))
	return SimQuery.t_("ui.offices.last_won") % [int(last.get("day", 0)) + 1, ", ".join(names) if not names.is_empty() else "—"]


## A campaign level's name without its figures («media» of «Media (50 de oro, +15 %)»).
static func level_name(level: String) -> String:
	return SimQuery.t_("campaign.level." + level).get_slice(" (", 0).to_lower()


# --- the picked seat -----------------------------------------------------------------------------------------------

func _fill_detail(chart: Array) -> void:
	var row := {}
	for r: Dictionary in chart:
		if str(r["office"]) == office:
			row = r
	if row.is_empty():
		return
	var def: Dictionary = sim.catalog.offices().get(office, {})
	(%DetailTitle as Label).text = SimQuery.t_("ui.offices.detail") % [SimQuery.office_name(office), int(row["salary"]),
		int(row["term_years"])]
	var fx: PackedStringArray = []
	for p: Dictionary in def.get("powers", []):
		fx.append(SimQuery.t_("power." + str(p.get("id", ""))).to_lower())
	(%DetailFx as Label).text = ", ".join(fx) if not fx.is_empty() else SimQuery.t_("ui.offices.no_powers")
	var fam := str(sim.state.characters.get(actor, {}).get("family", ""))
	var need := str(row["min_title"])
	var has := Offices.title_allows(sim, fam, office)
	var tn := SimQuery.title_name(need)
	(%DetailReq as Label).text = SimQuery.t_("ui.offices.needs_title_has" if has else "ui.offices.needs_title_not") % \
		(tn.substr(0, 1).to_upper() + tn.substr(1))
	(%DetailReq as Label).theme_type_variation = &"PositiveLabel" if has else &"ReasonLabel"
	_calendar(%Calendar as Control, %CalLabels as HBoxContainer, int(row["election_day"]))
	var names: PackedStringArray = []
	for c: Dictionary in (row["election"] as Dictionary).get("candidates", []):
		names.append("%s · %s" % [str(sim.state.characters.get(str(c["character"]), {}).get("name", "")),
			SimQuery.t_("ui.offices.level_of") % level_name(str(c.get("level", "basic")))])
	(%Candidates as Label).text = SimQuery.t_("ui.offices.candidates") % (", ".join(names) if not names.is_empty() \
		else SimQuery.t_("ui.offices.nobody_yet"))
	var why := Elections.run_status(sim, actor, office, _level)
	(%RunButton as Button).disabled = why != ""
	(%RunButton as Button).tooltip_text = SimQuery.reason_text(why) if why != "" else SimQuery.t_("ui.offices.run_tip") % [
		SimQuery.office_name(office), SimQuery.t_("campaign.level." + _level)]
	SocialKit.set_reason(%RunReason as Label, run_reason(why, int(row["election_day"])))


## The reason «Presentarse» is off, saying when it opens again if it is a matter of time.
func run_reason(why: String, day: int) -> String:
	match why:
		"":
			return ""
		"registration_closed":
			return SimQuery.t_("ui.offices.why_closed") % (day + 1 + 1)
		"office_needs_title":
			var tn := SimQuery.title_name(str(sim.catalog.offices().get(office, {}).get("min_title", "")))
			return SimQuery.t_("ui.offices.why_title") % (tn.substr(0, 1).to_upper() + tn.substr(1))
	return SimQuery.reason_text(why)


## The calendar of the election held on `day` (-1: none now): registration from the start of its year, the campaign
## in the last season, the vote on `day`.
func _calendar(cal: Control, labels: HBoxContainer, day: int) -> void:
	SocialKit.clear(cal)
	SocialKit.clear(labels)
	if day < 0:
		labels.add_child(SocialKit.label(SimQuery.t_("ui.offices.no_vote"), &"DimLabel"))
		return
	var dps := int(sim.catalog.time.get("days_per_season", 2))
	var start := day - Offices.days_per_year(sim)
	var camp := day - dps
	var c := ElectionCalendar.new()
	c.name = "Line"
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.set_days(start, camp, day, Offices.today(sim))
	cal.add_child(c)
	for spec: Array in [["ui.offices.cal_reg", start, camp - 1, 3.0], ["ui.offices.cal_camp", camp, day - 1, 1.0], ["ui.offices.cal_vote", day, day, 0.6]]:
		var key := str(spec[0])
		var txt := SimQuery.t_(key) % (int(spec[1]) + 1) if key == "ui.offices.cal_vote" else \
			SimQuery.t_(key) % [int(spec[1]) + 1, int(spec[2]) + 1]
		var l := SocialKit.label(txt, &"SmallLabel")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = float(spec[3])
		labels.add_child(l)


## «Presentarse» asks first when its level costs gold (cargos_y_elecciones.md §4).
func request_run() -> void:
	var o := office
	var lv: Dictionary = sim.catalog.politics.get("elections", {}).get("levels", {}).get(_level, {})
	var g := int(lv.get("gold", 0))
	if g <= 0:
		_run(o)
		return
	SocialKit.ask(self, SimQuery.t_("ui.offices.run_q") % SimQuery.office_name(o), SimQuery.t_("ui.offices.run_body") % [
		SimQuery.t_("campaign.level." + _level), g, Offices.election_day(sim, o) + 1], SimQuery.t_("ui.offices.run"),
		func() -> void: _run(o), "", true)


# --- the campaign --------------------------------------------------------------------------------------------------

func _fill_campaign(camp: Dictionary) -> void:
	if camp.is_empty():
		return
	(%CampaignLabel as Label).text = SimQuery.t_("ui.offices.campaign_short") % SimQuery.office_name(str(camp["office"]))
	(%DaysLeft as Label).text = SimQuery.t_("ui.offices.days_left") % maxi(0, int(camp["days_left"]))
	_calendar(%CampaignCalendar as Control, %CampaignCalLabels as HBoxContainer, int(camp["day"]))
	var today := Offices.today(sim)
	if today != _forecast_day:   # the poll is taken at dawn
		_forecast_day = today
		_forecast = Elections.forecast(sim, str(camp["office"]))
	var band := str(_forecast.get(actor, "close"))
	(%Forecast as Label).text = SimQuery.t_("forecast." + band)
	(%Forecast as Label).theme_type_variation = &"PositiveLabel" if band == "lead" else (&"ReasonLabel" if band == "behind" else &"WarningLabel")
	(%ForecastNote as Label).text = SimQuery.t_("ui.offices.forecast_note")
	(%ForecastTitle as Label).text = SimQuery.t_("ui.offices.forecast_title")
	var list := %CampaignList as VBoxContainer
	SocialKit.clear(list)
	var cc := Elections.candidacy(sim.state, actor)
	var el: Dictionary = cc.get("election", {})
	for c: Dictionary in el.get("candidates", []):
		var id := str(c["character"])
		var p := PanelContainer.new()
		p.name = "Cand_" + id
		p.theme_type_variation = &"RowPanel"
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		p.add_child(h)
		h.add_child(SocialKit.portrait(sim.state, id))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var top := HBoxContainer.new()
		var nm := SocialKit.label("%s · %s" % [str(sim.state.characters.get(id, {}).get("name", "")),
			str(sim.state.families.get(str(c.get("family", "")), {}).get("name", ""))], &"BoldLabel", "Name")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		var lvl := SimQuery.t_("ui.offices.level_of") % level_name(str(c.get("level", "basic")))
		if bool(c.get("incumbent", false)):
			lvl += " · " + SimQuery.t_("ui.offices.incumbent")
		top.add_child(SocialKit.label(lvl, &"DimLabel", "Level"))
		col.add_child(top)
		col.add_child(SocialKit.label(done_text(c, today), &"DimLabel", "Done"))
		h.add_child(col)
		list.add_child(p)
	var why := Elections.action_status(sim, actor, "speech", "")
	var sb := %SpeechButton as Button
	sb.disabled = why != ""
	var a: Dictionary = sim.catalog.politics.get("elections", {}).get("actions", {}).get("speech", {})
	var band_s := SocialKit.check_band(sim, actor, "", "rhetoric", "", int(a.get("target_value", 5)))
	sb.tooltip_text = SimQuery.reason_text(why) if why != "" else SimQuery.t_("ui.offices.speech_tip") + "\n" + \
		SocialKit.check_text(band_s, "rhetoric", "")
	SocialKit.set_reason(%SpeechReason as Label, speech_reason(why, el))


## What a candidate did: «discurso hoy: sí · 1 soborno · difamó hoy».
func done_text(c: Dictionary, today: int) -> String:
	var parts: PackedStringArray = []
	var d: Dictionary = c.get("done", {})
	parts.append(SimQuery.t_("ui.offices.speech_today") % SimQuery.t_("ui.yes" if int(d.get("speech", -1)) == today else "ui.no"))
	var bribes := (c.get("secured", []) as Array).size()
	if bribes > 0:
		parts.append(SimQuery.t_("ui.offices.bribes") % bribes)
	if int(d.get("defame", -1)) == today:
		parts.append(SimQuery.t_("ui.offices.defamed_today"))
	return " · ".join(parts)


func speech_reason(why: String, el: Dictionary) -> String:
	match why:
		"":
			return ""
		"campaign_not_started":
			return SimQuery.t_("ui.offices.why_campaign") % (int(el.get("campaign_day", 0)) + 1)
		"already_today":
			return SimQuery.t_("ui.offices.why_speech_today")
	return SimQuery.reason_text(why)


# --- the powers ----------------------------------------------------------------------------------------------------

func _fill_powers(powers: Array) -> void:
	var box := %Powers as VBoxContainer
	SocialKit.clear(box)
	var force := %InForce as VBoxContainer
	SocialKit.clear(force)
	if powers.is_empty():
		return
	var off := str(powers[0]["office"])
	(%PowersTitle as Label).text = SimQuery.t_("ui.offices.powers") % SimQuery.office_name(off)
	for r: Variant in sim.state.market.get("regulations", []):  # the regulations in force, with the market price
		if not r is Dictionary or int(r.get("until", 0)) <= int(sim.state.clock["minute"]):
			continue
		var l := SocialKit.label(SimQuery.t_("ui.offices.regulation") % [SimQuery.item_name(sim.catalog, str(r["item"])),
			int(r["percent"]), Clock.day(int(r["until"])) + 1, Market.price(sim, str(r["item"]), 0, "sell"),
			Market.price(sim, str(r["item"]), 0, "buy")], &"PositiveLabel", "Regulation_" + str(r["item"]))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(380, 0)
		force.add_child(l)
	var tax := Offices.tax_percent(sim)
	if tax > 0:
		force.add_child(SocialKit.label(SimQuery.t_("ui.offices.tax_in_force") % tax, &"PositiveLabel", "Tax"))
	(%InForceBox as Control).visible = force.get_child_count() > 0
	(%InForceTitle as Label).text = SimQuery.t_("ui.offices.in_force")
	for p: Dictionary in powers:
		var id := str(p["power"])
		var line := HBoxContainer.new()
		line.name = "Power_" + id
		line.add_theme_constant_override("separation", 4)
		if not bool(p["ready"]):
			line.add_child(SocialKit.label(SimQuery.t_("ui.offices.power_later") % [SimQuery.t_("power." + id), str(p["from"])],
				&"DimLabel", "Later"))
			box.add_child(line)
			continue
		var name_l := SocialKit.label(SimQuery.t_("power." + id), &"BoldLabel", "Name")
		name_l.custom_minimum_size = Vector2(120, 0)
		line.add_child(name_l)
		match id:
			"regulate_price":
				line.add_child(_item_picker())
				var pct := int(sim.catalog.politics.get("regulation", {}).get("percent", 10))
				for sign: int in [1, -1]:
					var args := {"item": _item, "percent": pct * sign}
					line.add_child(_power_button(id, SimQuery.t_("ui.offices.regulate") % [pct * sign], args))
			"fine_merchant":
				line.add_child(_family_picker())
				line.add_child(_power_button(id, SimQuery.t_("ui.offices.use"), {"family": _target_family}))
			"set_tax":
				var spin := SpinBox.new()
				var tx: Dictionary = sim.catalog.politics.get("taxes", {})
				spin.min_value = int(tx.get("min", 5))
				spin.max_value = int(tx.get("max", 15))
				spin.value = clampi(_tax, int(spin.min_value), int(spin.max_value))
				spin.suffix = "%"
				spin.focus_mode = Control.FOCUS_NONE
				spin.value_changed.connect(func(v: float) -> void:
					_tax = int(v)
					_sig = "")
				line.add_child(spin)
				line.add_child(_power_button(id, SimQuery.t_("ui.offices.use"), {"percent": int(spin.value)}))
			"declare_event":  # H13: one button per declarable event (data/events.json declarable)
				for ev: String in WorldEvents.declarable(sim):
					var b := _power_button(id, SimQuery.t_("ui.offices.declare") % SimQuery.event_name(sim.catalog, ev),
						{"event": ev})
					b.name = "Use_declare_event_" + ev
					line.add_child(b)
			"organize_festival":  # fiestas (04f 4.25.5): bulls or a joust in an announced feast
				for inst: Dictionary in Festivals.announced(sim) + Festivals.active(sim):
					for part: String in Festivals.organizable(sim, inst):
						var b := _power_button(id, SimQuery.t_("ui.offices.organize") % [SimQuery.t_("festival.part." + part),
							SimQuery.festival_name(str(inst["def"]))], {"festival": str(inst["id"]), "part": part})
						b.name = "Use_organize_%s_%s" % [part, inst["id"]]
						line.add_child(b)
			_:
				line.add_child(_power_button(id, SimQuery.t_("ui.offices.use"), {}))
		var cd := int(p["cooldown_minutes"])
		if cd > 0:
			var full := maxf(1.0, float(Offices.power_def(sim, str(p["office"]), id).get("cooldown_days", 2)) * Clock.MINUTES_PER_DAY)
			var bar := SocialKit.bar(1.0 - float(cd) / full, 50.0, "Cooldown")
			line.add_child(bar)
			line.add_child(SocialKit.label(SimQuery.t_("ui.offices.ready_in") % SocialKit.duration_text(cd), &"DimLabel", "CooldownText"))
		box.add_child(line)


func _item_picker() -> OptionButton:
	var ob := OptionButton.new()
	ob.name = "ItemOption"
	ob.focus_mode = Control.FOCUS_NONE
	ob.theme_type_variation = &"BodyButton"
	var ids: Array = sim.catalog.items().keys()
	ids.sort()
	var n := 0
	for id: String in ids:
		if RivalAI.stall_for(sim, id) == "":
			continue
		ob.add_item(SimQuery.item_name(sim.catalog, id))
		ob.set_item_metadata(n, id)
		if id == _item:
			ob.select(n)
		n += 1
	ob.item_selected.connect(func(i: int) -> void:
		_item = str(ob.get_item_metadata(i))
		_sig = "")
	return ob


func _family_picker() -> OptionButton:
	var ob := OptionButton.new()
	ob.name = "FamilyOption"
	ob.focus_mode = Control.FOCUS_NONE
	ob.theme_type_variation = &"BodyButton"
	var mine := str(sim.state.characters.get(actor, {}).get("family", ""))
	var ids: Array = sim.state.families.keys()
	ids.sort()
	var n := 0
	for f: String in ids:
		if f == mine or Titles.businesses(sim, f) < 1:
			continue
		if _target_family == "":
			_target_family = f
		ob.add_item(str(sim.state.families[f].get("name", f)))
		ob.set_item_metadata(n, f)
		if f == _target_family:
			ob.select(n)
		n += 1
	ob.item_selected.connect(func(i: int) -> void:
		_target_family = str(ob.get_item_metadata(i))
		_sig = "")
	return ob


func _power_button(power: String, text: String, args: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Use_" + power + ("" if not args.has("percent") or power != "regulate_price" else
		("_up" if int(args["percent"]) > 0 else "_down"))
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"BodyButton"
	var why := Offices.power_status(sim, actor, power, args)
	b.disabled = why != ""
	b.tooltip_text = SimQuery.reason_text(why) if why != "" else SimQuery.t_("power." + power)
	b.pressed.connect(func() -> void: request_power(power, args))
	return b


## Using a power asks first: it touches the whole market or another family (cargos_y_elecciones.md §4).
func request_power(power: String, args: Dictionary) -> void:
	var body := ""
	match power:
		"regulate_price":
			body = SimQuery.t_("ui.offices.ask_regulate") % [SimQuery.item_name(sim.catalog, str(args.get("item", ""))),
				SocialKit.signed(int(args.get("percent", 0))), int(sim.catalog.politics.get("regulation", {}).get("days", 2))]
		"fine_merchant":
			body = SimQuery.t_("ui.offices.ask_fine") % [int(sim.catalog.politics.get("regulation", {}).get("fine_gold", 20)),
				str(sim.state.families.get(str(args.get("family", "")), {}).get("name", ""))]
		"set_tax":
			body = SimQuery.t_("ui.offices.ask_tax") % int(args.get("percent", 0))
	SocialKit.ask(self, SimQuery.t_("ui.offices.ask_power") % SimQuery.t_("power." + power), body,
		SimQuery.t_("ui.offices.use"), func() -> void: _use(power, args))


func _run(o: String) -> void:
	_give({"type": "run_for_office", "actor": actor, "office": o, "level": _level})


func _speech() -> void:
	_give({"type": "campaign_action", "actor": actor, "kind": "speech", "target": ""})


func _use(power: String, args: Dictionary) -> void:
	_give({"type": "use_office_power", "actor": actor, "power": power, "args": args})


func _give(o: Dictionary) -> void:
	ViewConfig.info("OfficesPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""
