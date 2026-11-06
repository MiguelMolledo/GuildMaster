extends "res://tests/test_case.gd"
## Posada · the tavern's panel with the keyboard (verifica 2026-11-06: «inn_make_bed» was not reached with the
## keyboard). Every control of every tab takes the focus (KeyNav), the bed's button is there when a bed is dirty and
## Enter on it gives the order, and an Esc that Godot takes to hide a tooltip (the mouse resting on a button) is sent
## again, so that it closes the panel.

const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func _setup() -> Dictionary:
	var sim := Sim.new(NewGame.from_scenario("innkeeper_start", 1)["state"], cat)
	var t := ""
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		if Inn.is_inn(sim, b):
			t = b
	var given: Array = []
	var panel: InnPanel = (load("res://game/inn/inn_panel.tscn") as PackedScene).instantiate()
	panel.order_sink = func(o: Dictionary) -> void:
		given.append(o)
		sim.step([o])
	panel.setup(sim, t, HERO)
	return {"sim": sim, "t": t, "panel": panel, "given": given}


## What KeyNav does to every control made (node_added), here by hand: no tree in the rule tests.
func _key_nav(n: Node) -> void:
	for c: Node in n.find_children("*", "Control", true, false):
		if c is BaseButton or c is LineEdit or c is Range and not c is ProgressBar:
			KeyNav._apply(c)


func _buttons(n: Node) -> Array:
	return n.find_children("*", "BaseButton", true, false).filter(func(b: BaseButton) -> bool: return b.visible)


func test_every_tab_takes_the_keyboard() -> void:
	var r := _setup()
	var panel: InnPanel = r["panel"]
	for tab: String in InnPanel.TABS:
		panel.show_tab(tab)
		_key_nav(panel)
		var bs := _buttons(panel)
		check(bs.size() > InnPanel.TABS.size(), "%s: its own controls besides the tabs" % tab)
		for b: BaseButton in bs:
			check(b.focus_mode != Control.FOCUS_NONE, "%s: %s takes the focus" % [tab, b.name])
	panel.free()


func test_the_dirty_bed_button_is_pressed_with_the_keyboard() -> void:
	var r := _setup()
	var sim: Sim = r["sim"]
	var t := str(r["t"])
	var panel: InnPanel = r["panel"]
	panel.show_tab("rooms")
	(Inn.ensure(sim, t)["beds"] as Array)[1]["state"] = "dirty"
	panel.refresh()
	_key_nav(panel)
	var mk: Button = null
	for b: BaseButton in _buttons(panel):
		if b is Button and (b as Button).text == SimQuery.t_("ui.inn.make_bed"):
			mk = b as Button
	check(mk != null, "the dirty bed has its button")
	if mk == null:
		panel.free()
		return
	check(not mk.disabled and mk.focus_mode == Control.FOCUS_ALL, "enabled and focusable")
	mk.pressed.emit()   # Enter on the focused button
	var orders: Array = (r["given"] as Array).filter(func(o: Dictionary) -> bool: return str(o["type"]) == "inn_make_bed")
	eq(orders.size(), 1, "the order is given")
	eq(int(orders[0]["bed"]) if orders.size() > 0 else -1, 1, "for that bed")
	eq(str((Inn.ensure(sim, t)["beds"] as Array)[1]["state"]), "making", "and the bed is being made")
	panel.free()


func test_esc_sees_a_tooltip() -> void:
	var btn := Button.new()
	var tip := PopupPanel.new()
	tip.set_flag(Window.FLAG_NO_FOCUS, true)
	btn.add_child(tip)
	var menu := PopupPanel.new()   # a popup that takes the focus (a menu) is not a tooltip: Esc is for it
	menu.visible = true
	check(not KeyNav.tooltip_shown([tip, menu]), "a hidden tooltip and a menu: no tooltip")
	tip.visible = true
	check(KeyNav.tooltip_shown([tip, menu]), "the tooltip on screen: the Esc goes again")
	btn.free()
	menu.free()
