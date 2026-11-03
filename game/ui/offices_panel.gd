class_name OfficesPanel
extends PanelContainer
## The town's offices (GDD 4.12.3-4.12.4, H10): the organisation chart (mayor at the top, then councillors, judge,
## constable, collector and inspector), each seat with its holder or VACANT, family and the day its term ends, the
## open election with its candidates, and «Run» for the selected person at the chosen campaign level (disabled with the
## reason as tooltip: Elections.run_status). While the person is a candidate, the campaign: days left, rivals and the
## public speech (visit, bribe and defame are on the townsperson's sheet). While the person holds an office, its
## powers (Offices.powers): regulate a price (item and ±), fine a merchant (family), set the tax; the ones of later
## milestones are shown off. Opens with the HUD's Offices button (key O) or from the town hall; closes with ESC or X.
## Only reads the state and gives orders (order_sink).

signal closed

const RANK_COLORS: Dictionary = {"mayor": Color(1, 0.85, 0.4), "major": Color(0.85, 0.7, 0.42),
	"middle": Color(0.7, 0.8, 0.95), "minor": Color(0.7, 0.9, 0.65)}

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var _sig: String = ""
var _bound: bool = false
var _level: String = "basic"
var _item: String = "sword"
var _target_family: String = ""
var _tax: int = 10


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%SpeechButton as Button).pressed.connect(_speech)
	var lv := %LevelOption as OptionButton
	lv.item_selected.connect(func(i: int) -> void:
		_level = str(lv.get_item_metadata(i))
		_sig = "")


func open_for(s: Sim, who: String) -> void:
	_bind()
	sim = s
	actor = who
	(%Title as Label).text = SimQuery.t_("ui.offices.title")
	(%LevelLabel as Label).text = SimQuery.t_("ui.offices.level")
	(%SpeechButton as Button).text = SimQuery.t_("campaign.speech")
	var lv := %LevelOption as OptionButton
	lv.clear()
	var levels: Array = sim.catalog.politics.get("elections", {}).get("level_order", [])
	for i: int in levels.size():
		lv.add_item(SimQuery.t_("campaign.level." + str(levels[i])))
		lv.set_item_metadata(i, str(levels[i]))
		if str(levels[i]) == _level:
			lv.select(i)
	visible = true
	refresh(true)
	ViewConfig.info("OfficesPanel", "open (actor=%s)" % who)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible and sim != null:
		refresh()


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var chart := Offices.chart(sim)
	var camp := Elections.campaign_of(sim, actor)
	var powers := Offices.powers(sim, actor)
	var runs: Array = []
	for row: Dictionary in chart:
		runs.append(Elections.run_status(sim, actor, str(row["office"]), _level))
	var pw: Array = []  # the cooldown by the hour: rebuilding every minute would close an open picker
	for p: Dictionary in powers:
		pw.append([p["power"], p["reason"], ceili(float(int(p["cooldown_minutes"])) / 60.0)])
	var sig := "%s|%s|%s|%s|%s|%s|%s|%d|%s" % [actor, chart, camp, pw, runs, _level, _item, _tax, _target_family] \
		+ "|%d" % (sim.state.market.get("regulations", []) as Array).size()
	if sig == _sig and not force:
		return
	_sig = sig
	var st := sim.state
	var ch: Dictionary = st.characters.get(actor, {})
	var fam := str(ch.get("family", ""))
	(%WhoLabel as Label).text = SimQuery.t_("ui.offices.who") % [str(ch.get("name", "—")),
		SimQuery.title_name(Titles.current(sim, fam)), Reputation.of(st, fam)] if not ch.is_empty() \
		else SimQuery.t_("ui.npc.no_actor")
	_fill_chart(chart, runs)
	_fill_campaign(camp)
	_fill_powers(powers)
	reset_size()


func _fill_chart(chart: Array, runs: Array) -> void:
	var box := %Chart as VBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for i: int in chart.size():
		var row: Dictionary = chart[i]
		var office := str(row["office"])
		var line := HBoxContainer.new()
		line.name = "Office_" + office
		line.add_theme_constant_override("separation", 6)
		var name_l := Label.new()
		name_l.text = SimQuery.office_name(office)
		name_l.custom_minimum_size = Vector2(112, 0)
		name_l.add_theme_color_override("font_color", RANK_COLORS.get(str(row["rank"]), Color.WHITE))
		name_l.tooltip_text = SimQuery.t_("ui.offices.office_tip") % [SimQuery.title_name(str(row["min_title"])),
			int(row["salary"]), int(row["term_years"])]
		name_l.mouse_filter = Control.MOUSE_FILTER_STOP
		line.add_child(name_l)
		var holders: PackedStringArray = []
		var vacant := 0
		for s: Dictionary in row["seats"]:
			vacant += 1 if bool(s["vacant"]) else 0
		if vacant > 1 and vacant == (row["seats"] as Array).size():  # every seat free: once, with the count
			holders.append(SimQuery.t_("ui.offices.vacant_n") % vacant)
		for s: Dictionary in row["seats"]:
			if vacant > 1 and vacant == (row["seats"] as Array).size():
				break
			if bool(s["vacant"]):
				holders.append(SimQuery.t_("ui.offices.vacant") if int(row["election_day"]) < 0 \
					else SimQuery.t_("ui.offices.vacant_vote") % (int(row["election_day"]) + 1))
			else:
				holders.append(SimQuery.t_("ui.offices.holder") % [str(s["name"]), str(s["family_name"]),
					int(s["until"]) + 1])
		var hl := Label.new()
		hl.text = " / ".join(holders)
		if vacant > 1 and vacant == (row["seats"] as Array).size() and int(row["election_day"]) >= 0:
			hl.text += SimQuery.t_("ui.offices.vote_on") % (int(row["election_day"]) + 1)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hl.clip_text = true
		hl.custom_minimum_size = Vector2(170, 0)
		line.add_child(hl)
		var b := Button.new()
		b.name = "Run"
		b.text = SimQuery.t_("ui.offices.run")
		b.focus_mode = Control.FOCUS_NONE
		var why := str(runs[i])
		b.disabled = why != ""
		b.tooltip_text = SimQuery.reason_text(why) if why != "" else SimQuery.t_("ui.offices.run_tip") % [
			SimQuery.office_name(office), SimQuery.t_("campaign.level." + _level)]
		b.pressed.connect(func() -> void: _run(office))
		line.add_child(b)
		box.add_child(line)
		var el: Dictionary = row["election"]
		if not el.is_empty():
			var names: PackedStringArray = []
			for c: Dictionary in el.get("candidates", []):
				names.append(str(sim.state.characters.get(str(c["character"]), {}).get("name", c["character"])))
			var e := Label.new()
			e.name = "Election_" + office
			e.theme_type_variation = &"DimLabel"
			e.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
			e.text = SimQuery.t_("ui.offices.election") % [int(el["day"]) + 1, int(el["campaign_day"]) + 1,
				", ".join(names) if not names.is_empty() else "—"]
			box.add_child(e)


func _fill_campaign(camp: Dictionary) -> void:
	(%CampaignBox as Control).visible = not camp.is_empty()
	if camp.is_empty():
		return
	var rivals: PackedStringArray = []
	for c: Dictionary in camp["candidates"]:
		if str(c["character"]) != actor:
			rivals.append(str(c["name"]))
	(%CampaignLabel as Label).text = SimQuery.t_("ui.offices.campaign") % [SimQuery.office_name(str(camp["office"])),
		int(camp["day"]) + 1, int(camp["days_left"]), ", ".join(rivals) if not rivals.is_empty() else "—"]
	(%CampaignHint as Label).text = SimQuery.t_("ui.offices.campaign_on") if bool(camp["on"]) \
		else SimQuery.t_("ui.offices.campaign_wait") % (int(camp["campaign_day"]) + 1)
	var why := Elections.action_status(sim, actor, "speech", "")
	var sb := %SpeechButton as Button
	sb.disabled = why != ""
	sb.tooltip_text = SimQuery.reason_text(why) if why != "" else SimQuery.t_("ui.offices.speech_tip")


func _fill_powers(powers: Array) -> void:
	(%PowersBox as Control).visible = not powers.is_empty()
	var box := %Powers as VBoxContainer
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if powers.is_empty():
		return
	var office := str(powers[0]["office"])
	(%PowersTitle as Label).text = SimQuery.t_("ui.offices.powers") % SimQuery.office_name(office)
	for p: Dictionary in powers:
		var id := str(p["power"])
		var line := HBoxContainer.new()
		line.name = "Power_" + id
		line.add_theme_constant_override("separation", 4)
		if not bool(p["ready"]):
			var l := Label.new()
			l.text = SimQuery.t_("ui.offices.power_later") % [SimQuery.t_("power." + id), str(p["from"])]
			l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.58))
			line.add_child(l)
			box.add_child(line)
			continue
		match id:
			"regulate_price":
				line.add_child(_item_picker())
				var pct := int(sim.catalog.politics.get("regulation", {}).get("percent", 10))
				for sign: int in [1, -1]:
					var args := {"item": _item, "percent": pct * sign}
					line.add_child(_power_button(id, SimQuery.t_("ui.offices.regulate") % [pct * sign], args))
			"fine_merchant":
				line.add_child(_family_picker())
				line.add_child(_power_button(id, SimQuery.t_("power." + id), {"family": _target_family}))
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
				line.add_child(_power_button(id, SimQuery.t_("power." + id), {"percent": int(spin.value)}))
			_:
				line.add_child(_power_button(id, SimQuery.t_("power." + id), {}))
		var cd := int(p["cooldown_minutes"])
		if cd > 0:
			var l := Label.new()
			l.text = SimQuery.t_("ui.offices.cooldown") % ceili(float(cd) / 60.0)
			l.theme_type_variation = &"DimLabel"
			line.add_child(l)
		box.add_child(line)
	for r: Variant in sim.state.market.get("regulations", []):  # the regulations in force, with the market price
		if not r is Dictionary or int(r.get("until", 0)) <= int(sim.state.clock["minute"]):
			continue
		var l := Label.new()
		l.name = "Regulation_" + str(r["item"])
		l.add_theme_color_override("font_color", Color(0.55, 0.85, 0.5))
		l.text = SimQuery.t_("ui.offices.regulation") % [SimQuery.item_name(sim.catalog, str(r["item"])),
			int(r["percent"]), Clock.day(int(r["until"])) + 1, Market.price(sim, str(r["item"]), 0, "sell"),
			Market.price(sim, str(r["item"]), 0, "buy")]
		box.add_child(l)


func _item_picker() -> OptionButton:
	var ob := OptionButton.new()
	ob.name = "ItemOption"
	ob.focus_mode = Control.FOCUS_NONE
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
	var why := Offices.power_status(sim, actor, power, args)
	b.disabled = why != ""
	b.tooltip_text = SimQuery.reason_text(why) if why != "" else SimQuery.t_("power." + power)
	b.pressed.connect(func() -> void: _use(power, args))
	return b


func _run(office: String) -> void:
	_give({"type": "run_for_office", "actor": actor, "office": office, "level": _level})


func _speech() -> void:
	_give({"type": "campaign_action", "actor": actor, "kind": "speech", "target": ""})


func _use(power: String, args: Dictionary) -> void:
	_give({"type": "use_office_power", "actor": actor, "power": power, "args": args})


func _give(o: Dictionary) -> void:
	ViewConfig.info("OfficesPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	_sig = ""
