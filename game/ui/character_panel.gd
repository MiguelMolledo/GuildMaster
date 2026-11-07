class_name CharacterPanel
extends PanelContainer
## The selected person's sheet (key I or the HUD button; docs/ui/mecanicas/almacen_y_personaje.md §4.2; GDD 4.3.4), in
## the management zone. Header: portrait, name, age · trade (and banishment / office, H10-H11) and the family's gold;
## the family buttons (tree F, Court for a single adult, the family AI). Two tabs:
##   Inventory (default): the three equipment squares (tool, clothes, accessory) with what each gives, from the data
##       (the building's right tool: +N % to go up a quality step there), a click on one unequips it (unequip); the
##       carried weight with its bar (amber at 90 %, red at 100 %); the bag as squares (ItemSlot), a click on a thing
##       with a slot equips it (equip); and what all of it is worth today at the market.
##   Routine: the routine editor (RoutineEditor, forja_interior.md §4.5).
## Sleep and food (GDD 4.2.6): a row under the header with rest and hunger, the state (Cansado, Rendido, Hambriento),
## the Rutina switch (set_needs_routine) and «Comer» at home or at the tavern (eat, after walking there).
## Only gives orders (equip / unequip / set_schedule / set_needs_routine / eat); the sim decides.

signal closed
signal tree_requested
signal court_requested(id: String)
signal kin_ai_requested(id: String)  # H14: the AI of the family (directives, needs)

const SLOTS: Array[String] = ["tool", "clothes", "accessory"]
const SILHOUETTES: Dictionary = {"tool": "slot_empty_herramienta", "clothes": "slot_empty_ropa",
	"accessory": "slot_empty_accesorio"}

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var tab: String = "inventory"
var _sig: String = ""
var _bound: bool = false


func setup(s: Sim, who: String) -> void:
	if not _bound:
		_bound = true
		(%CloseButton as Button).pressed.connect(close)
		(%TreeButton as Button).pressed.connect(func() -> void: tree_requested.emit())
		(%CourtButton as Button).pressed.connect(func() -> void: court_requested.emit(actor))
		(%KinAiButton as Button).pressed.connect(func() -> void: kin_ai_requested.emit(actor))
		(%InvTab as Button).pressed.connect(show_tab.bind("inventory"))
		(%RoutineTab as Button).pressed.connect(show_tab.bind("routine"))
		(%RoutineCheck as CheckBox).toggled.connect(func(on: bool) -> void:
			_give({"type": "set_needs_routine", "actor": actor, "character": actor, "on": on}))
		(%EatButton as Button).pressed.connect(eat_at.bind("home"))
		(%TavernButton as Button).pressed.connect(eat_at.bind("tavern"))
	sim = s
	actor = who
	(%TreeButton as Button).text = SimQuery.t_("ui.character.tree_short")
	(%TreeButton as Button).tooltip_text = SimQuery.t_("ui.family.tree")
	(%CourtButton as Button).text = SimQuery.t_("ui.family.court")
	(%KinAiButton as Button).text = SimQuery.t_("ui.kin_ai.button")
	(%KinAiButton as Button).tooltip_text = SimQuery.t_("ui.kin_ai.button_tip")
	(%RoutineCheck as CheckBox).text = SimQuery.t_("ui.needs.routine")
	(%RoutineCheck as CheckBox).tooltip_text = SimQuery.t_("ui.needs.routine_tip")
	(%EatButton as Button).text = SimQuery.t_("ui.needs.eat_home")
	(%EatButton as Button).tooltip_text = SimQuery.t_("ui.needs.eat_home_tip")
	(%TavernButton as Button).text = SimQuery.t_("ui.needs.eat_tavern")
	(%TavernButton as Button).tooltip_text = SimQuery.t_("ui.needs.eat_tavern_tip")
	(%InvTab as Button).text = SimQuery.t_("ui.character.inventory")
	(%RoutineTab as Button).text = SimQuery.t_("ui.routine.title")
	var editor := %RoutineEditor as RoutineEditor
	editor.order_sink = order_sink
	editor.setup(s, who, who)
	(%SlotsLabel as Label).text = SimQuery.t_("ui.character.equipment").to_upper()
	(%InvLabel as Label).text = SimQuery.t_("ui.character.bag").to_upper()
	show_tab(tab)
	refresh(true)


func open() -> void:
	visible = true
	refresh(true)
	if sim != null:
		(%RoutineEditor as RoutineEditor).refresh(true)
		_refresh_family()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func set_actor(who: String) -> void:
	if who != actor:
		actor = who
		(%RoutineEditor as RoutineEditor).setup(sim, who, who)
		refresh(true)


## "inventory" or "routine".
func show_tab(t: String) -> void:
	tab = t if t in ["inventory", "routine"] else "inventory"
	(%InvTab as Button).set_pressed_no_signal(tab == "inventory")
	(%RoutineTab as Button).set_pressed_no_signal(tab == "routine")
	(%InvPage as Control).visible = tab == "inventory"
	(%RoutinePage as Control).visible = tab == "routine"
	if tab == "routine" and sim != null:
		(%RoutineEditor as RoutineEditor).refresh(true)


func _process(_delta: float) -> void:
	if visible:
		refresh()
		(%RoutineEditor as RoutineEditor).refresh()
		_refresh_family()


## H8: age, trade and the family buttons (Court only for a single adult).
func _refresh_family() -> void:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	(%FamilyRow as Control).visible = not ch.is_empty()
	if ch.is_empty():
		return
	var line := SimQuery.t_("ui.family.age") % Kin.age(sim, actor)
	var prof := str(ch.get("profession", ""))
	if prof != "":
		line += " · " + SimQuery.t_("profession." + prof)
	if Tribunal.is_banished(sim.state, actor):  # H11
		line += " · " + SimQuery.t_("ui.trial.banished") % (int(sim.state.characters[actor].get("banished_until", 0)) + 1)
	var where := Offices.seat_of(sim.state, actor)  # H10: the office it holds and until when
	if not where.is_empty():
		line += " · " + SimQuery.t_("ui.offices.until") % [SimQuery.office_name(str(where["office"])),
			int(sim.state.offices[str(where["office"])]["seats"][int(where["index"])].get("until", 0)) + 1]
	(%AgeLabel as Label).text = line
	(%CourtButton as Button).visible = Kin.is_adult(sim, actor) and Kin.is_single(sim.state, actor)
	_refresh_needs()


## Sleep and food: rest, hunger and the state; the Rutina switch (controlled ones); «Comer» while it may eat.
func _refresh_needs() -> void:
	var v := Needs.view(sim, actor)
	var row := %NeedsRow as Control
	row.visible = bool(v.get("tracked", false))
	if not row.visible:
		return
	(%NeedsLabel as Label).text = SimQuery.needs_line(v)
	(%NeedsLabel as Label).tooltip_text = SimQuery.t_("ui.needs.tip")
	var check := %RoutineCheck as CheckBox
	check.visible = Needs.is_controlled(sim, actor)
	check.set_pressed_no_signal(bool(v.get("routine", true)))
	var busy := Needs.is_exhausted(sim.state, actor) or str(v.get("act", "")) == "eat"
	(%EatButton as Button).disabled = busy or Kin.home_of(sim, actor) == ""
	(%TavernButton as Button).disabled = busy or NeedsRoutine.nearest_tavern(sim, actor) == ""


## «Comer»: at home (walks home first) or at the nearest tavern's door (walks there), then eats (queued after the walk).
func eat_at(place: String) -> void:
	if sim == null or actor == "":
		return
	var ch: Dictionary = sim.state.characters.get(actor, {})
	var loc := str(ch.get("location", ""))
	if place == "home":
		var home := Kin.home_of(sim, actor)
		if home == "":
			return
		if loc != home:
			if loc != "":
				_give({"type": "exit_building", "actor": actor})
			_give({"type": "enter_building", "actor": actor, "building": home, "queued": loc != ""})
			_give({"type": "eat", "actor": actor, "place": "home", "queued": true})
		else:
			_give({"type": "eat", "actor": actor, "place": "home"})
		return
	var inn := NeedsRoutine.nearest_tavern(sim, actor)
	if inn == "":
		return
	var door: Array = sim.state.buildings[inn].get("door", [])
	if NeedsRoutine.tavern_near(sim, actor) == inn:
		_give({"type": "eat", "actor": actor, "place": "tavern"})
		return
	if loc != "":
		_give({"type": "exit_building", "actor": actor})
	_give({"type": "move_to", "actor": actor, "tile": door, "queued": loc != ""})
	_give({"type": "eat", "actor": actor, "place": "tavern", "queued": true})


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var ch: Dictionary = sim.state.characters.get(actor, {})
	var fam := str(ch.get("family", ""))
	var sig := actor + "|" + str(ch.get("inventory", {})) + "|" + str(ch.get("equipment", {})) + "|" + str(Money.gold(sim.state, fam))
	if (sig == _sig or UiFeel.hold_rebuild(self)) and not force:
		return
	_sig = sig
	(%Title as Label).text = str(ch.get("name", SimQuery.t_("ui.character.nobody")))
	(%GoldLabel as Label).text = SimQuery.t_("ui.character.gold") % Money.gold(sim.state, fam)  # family purse (H3)
	if not ch.is_empty():
		(%Portrait as PortraitFrame).show_character(sim.state, actor, {"active": true, "controlled": true})
	var w := SimQuery.carried_weight(sim, actor) if not ch.is_empty() else 0.0
	var mx := SimQuery.max_weight(sim, actor) if not ch.is_empty() else 0.0
	(%WeightLabel as Label).text = SimQuery.t_("ui.character.weight") % [w, mx]
	var bar := %WeightBar as ProgressBar
	bar.value = clampf(w / mx, 0.0, 1.0) if mx > 0.0 else 0.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.html(StationMenu._token("negativo" if bar.value >= 1.0 else ("aviso" if bar.value > 0.9 else "positivo")))
	bar.add_theme_stylebox_override("fill", fill)
	_fill_slots(ch.get("equipment", {}))
	_fill_bag(ch.get("inventory", {}))


func _fill_slots(eq: Dictionary) -> void:
	var slots := %Slots as VBoxContainer
	_clear(slots)
	for slot: String in SLOTS:
		var row := HBoxContainer.new()
		row.name = slot
		row.add_theme_constant_override("separation", 6)
		var it: Variant = eq.get(slot, null)
		var has := it is Dictionary
		var sq := ItemSlot.new()
		sq.name = "Square"
		if has:
			sq.show_item(str(it.get("item", "")), int(it.get("quality", 0)))
		else:
			sq.show_empty(UiIcons.ui(SILHOUETTES[slot]))
		sq.tooltip_text = SimQuery.t_("ui.character.unequip") if has else SimQuery.t_("ui.slot." + slot)
		sq.clicked.connect(func(_s: ItemSlot, _r: bool) -> void:
			if has:
				unequip(slot))
		row.add_child(sq)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", 0)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := Label.new()
		l.name = "Name"
		l.text = SimQuery.t_("ui.slot." + slot) + ": " + (SimQuery.item_label(sim.catalog, str(it.get("item", "")),
			int(it.get("quality", 0))) if has else SimQuery.t_("ui.character.empty_slot"))
		l.clip_text = true
		texts.add_child(l)
		var eff := Label.new()
		eff.name = "Effect"
		eff.theme_type_variation = &"PositiveLabel"
		eff.text = effect_text(str(it.get("item", ""))) if has else ""
		eff.visible = eff.text != ""
		eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(eff)
		row.add_child(texts)
		var b := Button.new()
		b.name = "Unequip"
		b.focus_mode = Control.FOCUS_NONE
		b.text = SimQuery.t_("ui.character.unequip")
		b.disabled = not has
		b.visible = has
		b.pressed.connect(unequip.bind(slot))
		row.add_child(b)
		slots.add_child(row)


## What an equipped thing gives, from the data (a building whose tool it is: +N % to go up a quality step there); ""
## when the data says nothing (the GDD's tool speed has no figure yet: not written).
func effect_text(item: String) -> String:
	var parts: PackedStringArray = []
	var chance := roundi(float(sim.catalog.production.get("tool_step_up_chance", 0.0)) * 100.0)
	for t: String in sim.catalog.buildings():
		if str(sim.catalog.buildings()[t].get("tool", "")) == item and chance > 0:
			parts.append(SimQuery.t_("ui.character.tool_effect") % [chance, SimQuery.t_("building." + t)])
	return " · ".join(parts)


func _fill_bag(inv: Dictionary) -> void:
	var list := %InvList as GridContainer
	_clear(list)
	var value := 0
	var by_stall := {}
	for s: Dictionary in inv.get("stacks", []):
		var item := str(s["item"])
		var q := int(s["quality"])
		var key := "%s_%d" % [item, q]
		if list.has_node(key):
			continue
		var n := Inventory.count(inv, item, q)
		var def := sim.catalog.item(item)
		var sq := ItemSlot.new()
		sq.name = key
		sq.show_item(item, q, n)
		var price := Market.price(sim, item, q, "sell")
		value += price * n
		var stall := str(def.get("market_stall", ""))
		if stall != "":
			by_stall[stall] = int(by_stall.get(stall, 0)) + price * n
		sq.tooltip_text = "%s ×%d · %s kg\n%s" % [SimQuery.item_label(sim.catalog, item, q), n,
			String.num(float(def.get("weight", 0.0)) * n, 1), SimQuery.t_("ui.character.equip_tip") if def.has("slot") \
			else SimQuery.t_("ui.character.no_slot")]
		if def.has("slot"):
			var equip_b := Button.new()   # the square's action, also for the keyboard and the tests
			equip_b.name = "Equip"
			equip_b.visible = false
			equip_b.pressed.connect(equip.bind(item, q))
			sq.add_child(equip_b)
		sq.clicked.connect(func(_s: ItemSlot, _r: bool) -> void:
			if def.has("slot"):
				equip(item, q))
		list.add_child(sq)
	if (inv.get("stacks", []) as Array).is_empty():
		var e := ItemSlot.new()
		e.show_item("")
		list.add_child(e)
	var parts: PackedStringArray = []
	var stalls: Array = by_stall.keys()
	stalls.sort()
	for st: Variant in stalls:
		parts.append("%s %d" % [SimQuery.stall_name(sim.catalog, str(st)), int(by_stall[st])])
	(%ValueLabel as Label).text = SimQuery.t_("ui.character.value_today") % value + (" (%s)" % " · ".join(parts) if not parts.is_empty() else "")
	(%ValueLabel as Label).visible = value > 0


func _clear(box: Node) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()


func equip(item: String, quality: int) -> void:
	_give({"type": "equip", "actor": actor, "item": item, "quality": quality})


func unequip(slot: String) -> void:
	_give({"type": "unequip", "actor": actor, "slot": slot})


func _give(o: Dictionary) -> void:
	if actor == "":
		return
	ViewConfig.info("CharacterPanel", "order %s" % [o])
	if order_sink.is_valid():
		order_sink.call(o)
