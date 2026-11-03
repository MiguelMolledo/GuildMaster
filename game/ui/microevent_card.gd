class_name MicroeventCard
extends PanelContainer
## The card of a microevent of the player's family (H7, GDD 4.20; docs/ui/mecanicas/ciudad_viva.md §3-5), in the left
## column under the objective: not blocking, the time keeps running. Its title with where it happens, the portrait of
## who it is about and the text; one two-line button per choice (what it does, then its effects as written in
## data/microevents/<def>.json, Microevents.choice_effects: change a figure there and the card changes, no i18n
## touched), the default one marked; a choice the family cannot pay is off with the reason. Below, the clock as a bar
## that empties, «+N más» to look at the next one and «Más tarde» to fold the card to its title. Choosing gives
## resolve_microevent (a management order: it applies at once, also in pause). Only reads Microevents.active_for /
## view / choice_effects and gives orders (order_sink).

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""   # who decides: the selected person if of the family, else the head
var shown_id: String = ""
var index: int = 0       # which of the active ones is shown («+N más» moves it)
var folded: bool = false
var _bound: bool = false
var _span: int = 120     # minutes the shown one had from its start (the clock bar)


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%MoreButton as Button).pressed.connect(next)
	(%LaterButton as Button).pressed.connect(func() -> void: set_folded(not folded))


func follow(s: Sim, who: String) -> void:
	_bind()
	sim = s
	var fam := SimQuery.player_family(s.state)
	actor = SimQuery.family_actor(s.state, fam, who)
	var act := Microevents.active_for(s, fam) if fam != "" else []
	visible = not act.is_empty()
	if not visible:
		shown_id = ""
		index = 0
		return
	index = clampi(index, 0, act.size() - 1)
	var m: Dictionary = act[index]
	var v := Microevents.view(s, str(m["id"]))
	if str(v["id"]) != shown_id:
		shown_id = str(v["id"])
		_span = maxi(1, int(m.get("expires", 0)) - int(m.get("started", 0)))
		_build(v)
	var left := int(v["minutes_left"])
	(%Clock as ProgressBar).value = float(left) / float(_span)
	(%ClockText as Label).text = SocialKit.duration_text(left)
	(%MoreButton as Button).visible = act.size() > 1
	(%MoreButton as Button).text = SimQuery.t_("ui.microevent.more_short") % (act.size() - 1)
	(%LaterButton as Button).text = SimQuery.t_("ui.microevent.open" if folded else "ui.microevent.later")


## The next active microevent («+N más»).
func next() -> void:
	index += 1
	var act := Microevents.active_for(sim, SimQuery.player_family(sim.state)) if sim != null else []
	if index >= act.size():
		index = 0
	shown_id = ""
	follow(sim, actor)


func set_folded(f: bool) -> void:
	folded = f
	for n: String in ["Who", "Choices", "Default"]:
		(get_node("%" + n) as Control).visible = not f
	if sim != null:
		follow(sim, actor)
	reset_size()


func _build(v: Dictionary) -> void:
	var st := sim.state
	var bld := str(v.get("building", ""))
	(%Title as Label).text = SimQuery.t_("ui.microevent.title_at") % SimQuery.building_name(st, sim.catalog, bld) \
		if bld != "" and st.buildings.has(bld) else SimQuery.t_("ui.microevent.title")
	(%Text as Label).text = SimQuery.microevent_text(sim, v)
	var m := {}
	for x: Dictionary in st.microevents.get("active", []):
		if str(x["id"]) == str(v["id"]):
			m = x
	var target := str(m.get("target", ""))
	var slot := %PortraitSlot as Control
	SocialKit.clear(slot)
	slot.visible = st.characters.has(target)
	if slot.visible:
		slot.add_child(SocialKit.portrait(st, target))
	var box := %Choices as VBoxContainer
	SocialKit.clear(box)
	var fam := SimQuery.player_family(st)
	var def_text := ""
	for c: Dictionary in v["choices"]:
		var id := str(c["id"])
		var fx := Microevents.choice_effects(sim, str(v["def"]), id)
		var b := SocialKit.two_line_button(SimQuery.t_(str(c["text_key"])), effects_text(fx, m), id.capitalize())
		b.custom_minimum_size = Vector2(220, 34)
		if id == str(v["default"]):
			def_text = SimQuery.t_(str(c["text_key"]))
			var mark := SocialKit.label(SimQuery.t_("ui.microevent.default"), &"CaptionLabel", "DefaultMark")
			mark.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 3)
			mark.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(mark)
		var cost := cost_of(fx)
		if cost > 0 and not Money.can_pay(st, fam, cost):
			b.disabled = true
			b.tooltip_text = SimQuery.t_("ui.microevent.cannot_pay") % cost
			(b.get_node("Lines/Effects") as Label).text = SimQuery.t_("ui.microevent.cannot_pay") % cost
			(b.get_node("Lines/Effects") as Label).theme_type_variation = &"ReasonLabel"
		b.pressed.connect(func() -> void: choose(id))
		box.add_child(b)
	(%Default as Label).text = SimQuery.t_("ui.microevent.if_none") % def_text
	(%ClockIcon as TextureRect).texture = UiIcons.ui("icon_pending")
	set_folded(folded)
	reset_size()


## The gold a choice pays (its "pay" effects).
static func cost_of(effects: Array) -> int:
	var g := 0
	for e: Dictionary in effects:
		if str(e.get("kind", "")) == "pay":
			g += int(e.get("gold", 0))
	return g


## The effects of a choice in one short line, from the data ("−10 de oro · falta hoy · lealtad +5").
func effects_text(effects: Array, m: Dictionary) -> String:
	var parts: PackedStringArray = []
	for e: Dictionary in effects:
		match str(e.get("kind", "")):
			"pay":
				parts.append(SimQuery.t_("ui.mev_fx.pay") % int(e.get("gold", 0)))
			"absent":
				var span: Array = e.get("days", [0, 0])
				var a := int(span[0]) + 1
				var b := int(span[1]) + 1
				parts.append(SimQuery.t_("ui.mev_fx.absent_today") if b <= 1 else (SimQuery.t_("ui.mev_fx.absent") % [a, b]))
			"loyalty":
				parts.append(SimQuery.t_("ui.mev_fx.loyalty") % SocialKit.signed(int(e.get("amount", 0))))
			"relation":
				parts.append(SimQuery.t_("ui.mev_fx.relation") % SocialKit.signed(int(e.get("amount", 0))))
			"reputation":
				parts.append(SimQuery.t_("ui.mev_fx.reputation") % SocialKit.signed(int(e.get("amount", 0))))
			"refund_wage":
				parts.append(SimQuery.t_("ui.mev_fx.no_wage"))
			"sell":
				var d := roundi(float(e.get("discount", 0.0)) * 100.0)
				parts.append(SimQuery.t_("ui.mev_fx.sell_discount") % d if d > 0 else SimQuery.t_("ui.mev_fx.sell"))
			"emotion":
				parts.append(SimQuery.t_("ui.mev_fx.emotion") % SimQuery.t_("emotion." + str(e.get("state", ""))).to_lower())
			"leave":
				parts.append(SimQuery.t_("ui.mev_fx.leave"))
			"steal":
				parts.append(SimQuery.t_("ui.mev_fx.steal"))
			"skill_check":
				var a_stat := str(e.get("actor_stat", ""))
				var t_stat := str(e.get("target_stat", ""))
				var who := str(m.get("actor", "")) if str(m.get("actor", "")) != "" else actor
				var band := SocialKit.check_band(sim, who, str(m.get("target", "")), a_stat, t_stat,
					int(e["target_value"]) if e.has("target_value") else -1)
				parts.append(SimQuery.t_("ui.mev_fx.check") % [SimQuery.t_("stat." + a_stat), int(band["actor_stat"]),
					int(band["target_stat"]), SimQuery.t_("check_band." + str(band["band"]))])
	return " · ".join(parts) if not parts.is_empty() else SimQuery.t_("ui.mev_fx.nothing")


func choose(choice: String) -> void:
	if shown_id == "" or actor == "":
		return
	var o := {"type": "resolve_microevent", "actor": actor, "microevent": shown_id, "choice": choice}
	ViewConfig.info("MicroeventCard", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
	shown_id = ""
