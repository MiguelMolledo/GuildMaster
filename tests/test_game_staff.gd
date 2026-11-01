extends "res://tests/test_case.gd"
## H4 view (GDD 4.7, 4.6.4, 4.18): the staff panel (staff and hiring) and the production queue of the real interior
## scene give the exact orders of docs/contratos/h4_empleados.md; the map tells the townsfolk and the employees apart
## (badge), shows house signs only on hover, and the idle icon; the staff notices read with names. Windowless: the
## scenes are built by hand and the orders are caught by a sink.

const BLD := "bld_0001"
const HUGO := "chr_0001"
const ELENA := "chr_0002"
const JOAN := "chr_0007"
const AGNES := "chr_0008"

var cat := Catalog.load_from()
var _orders: Array = []


func _sim(scenario: String) -> Sim:
	var r := NewGame.from_scenario(scenario)
	check(bool(r["ok"]), "scenario %s loads" % scenario)
	return Sim.new(r["state"], cat)


func _sink(o: Dictionary) -> void:
	_orders.append(o.duplicate(true))


## The interior of the forge as the game opens it (management mode by default), its orders into _orders.
func _interior(sim: Sim, who: String = "", manage: bool = true) -> InteriorView:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.order_sink = _sink
	v.setup(sim, BLD, who, manage)
	_orders.clear()
	return v


func _last() -> Dictionary:
	return _orders.back() if not _orders.is_empty() else {}


func _same(got: Dictionary, want: Dictionary, msg: String) -> void:
	eq(SaveFile.canonical(got), SaveFile.canonical(want), msg)


func _press(row: Control, button: String) -> bool:
	var b := row.find_child(button, true, false) as Button if row != null else null
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


func _free(n: Node) -> void:
	n.free()


# --- staff panel -----------------------------------------------------------------------------------------------------

func test_staff_button_opens_the_panel_with_each_employee() -> void:
	var sim := _sim("two_employees")
	var v := _interior(sim)
	var b := v.get_node("%StaffButton") as Button
	check(b.visible and not b.disabled, "the Staff button is there and usable")
	b.toggled.emit(true)
	var p := v.staff_panel()
	check(p.visible, "the staff panel opens")
	eq(p.tab, "staff", "on the staff tab")
	check(p.row_of(JOAN) != null and p.row_of(AGNES) != null, "a row per employee")
	var text := _texts(p.row_of(AGNES))
	check(text.contains("Agnès"), "the name (%s)" % text)
	check(text.contains(SimQuery.rank_name(cat, "apprentice")), "the rank")
	check(text.contains("50"), "the loyalty")
	check(text.contains(SimQuery.band_name("unhappy")), "the loyalty band")
	var role := p.row_of(AGNES).find_child("Role", true, false) as OptionButton
	eq(str(role.get_item_metadata(role.selected)), "furnace", "the current role is selected")
	check(p.row_of(AGNES).find_child("Promotion", true, false) == null, "no promotion pending")
	check(not v.production_panel().visible and not v.storage_panel().visible, "the other panels are closed")
	_free(v)


func test_staff_rows_give_set_role_bonus_and_fire() -> void:
	var sim := _sim("two_employees")
	var v := _interior(sim)
	v.show_staff(true)
	var row := v.staff_panel().row_of(JOAN)
	var role := row.find_child("Role", true, false) as OptionButton
	var roles: Array = []
	for i: int in role.item_count:
		roles.append(str(role.get_item_metadata(i)))
	eq(roles, ["any", "furnace", "anvil", "counter"], "the roles: anything and the forge's stations (no storage)")
	role.select(roles.find("counter"))
	role.item_selected.emit(roles.find("counter"))
	_same(_last(), {"type": "set_role", "actor": HUGO, "employee": JOAN, "role": "counter"}, "role -> set_role")
	check(_press(v.staff_panel().row_of(JOAN), "Bonus"), "Bonus is pressable")
	_same(_last(), {"type": "bonus", "actor": HUGO, "employee": JOAN}, "Bonus -> bonus")
	check(_press(v.staff_panel().row_of(JOAN), "Fire"), "Fire is pressable")
	_same(_last(), {"type": "fire", "actor": HUGO, "employee": JOAN}, "Fire -> fire")
	eq(_orders.size(), 3, "one order per click")
	_free(v)


func test_orders_are_signed_by_the_selected_member_of_the_family() -> void:
	var sim := _sim("two_employees")
	var v := _interior(sim, ELENA, true)
	v.show_staff(true)
	_press(v.staff_panel().row_of(JOAN), "Bonus")
	eq(str(_last().get("actor", "")), ELENA, "Elena selected: she signs")
	v.select(HUGO)
	_press(v.staff_panel().row_of(JOAN), "Bonus")
	eq(str(_last().get("actor", "")), HUGO, "Hugo selected: he signs")
	v.select("chr_0009")  # a townsperson is not of the family: its first member signs
	_press(v.staff_panel().row_of(JOAN), "Bonus")
	eq(str(_last().get("actor", "")), HUGO, "someone else selected: the family's first member")
	_free(v)


func test_pending_promotion_shows_accept_and_refuse() -> void:
	var sim := _sim("apprentice_promotion")
	sim.state.characters[AGNES]["job"]["promotion_offered"] = true
	var v := _interior(sim)
	v.show_staff(true)
	var row := v.staff_panel().row_of(AGNES)
	var promo := row.find_child("Promotion", true, false) as Control
	check(promo != null, "the promotion line is there")
	check(_texts(promo).contains(SimQuery.rank_name(cat, "journeyman")), "to journeyman")
	check(_press(row, "Accept"), "Accept")
	_same(_last(), {"type": "promote", "actor": HUGO, "employee": AGNES, "accept": true}, "Accept -> promote true")
	check(_press(v.staff_panel().row_of(AGNES), "Refuse"), "Refuse")
	_same(_last(), {"type": "promote", "actor": HUGO, "employee": AGNES, "accept": false}, "Refuse -> promote false")
	_free(v)


func test_promotion_offer_from_the_sim_reaches_the_panel() -> void:
	# the scenario: Agnès with 7 days in rank and loyalty 60, day 9 at 04:50; at dawn day 8 counts (plantilla)
	var sim := _sim("apprentice_promotion")
	var v := _interior(sim)
	v.show_staff(true)
	var notices: Array = []
	for i: int in 120:
		for e: Dictionary in sim.step():
			if str(e.get("type", "")) == "promotion_offered":
				notices.append(e)
		if not notices.is_empty():
			break
	eq(notices.size(), 1, "the sim offers the promotion at dawn")
	v.staff_panel().refresh()
	var row := v.staff_panel().row_of(AGNES)
	check(row != null and row.find_child("Promotion", true, false) != null, "the panel shows Accept / Refuse")
	var n: Array = Notices.list(sim, "fam_0001")
	var texts: Array = n.map(func(x: Dictionary) -> String: return SimQuery.notice_text(sim.state, cat, x))
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	texts = n.map(func(x: Dictionary) -> String: return SimQuery.notice_text(sim.state, cat, x))
	TranslationServer.set_locale(before)
	check(texts.has("Agnès puede ascender a Oficial"), "the notice reads with the rank's name (%s)" % [texts])
	_free(v)


func test_hire_tab_lists_candidates_and_gives_hire() -> void:
	var sim := _sim("town_e_start")
	var v := _interior(sim, HUGO, false)
	v.show_staff(true, "hire")
	var p := v.staff_panel()
	eq(p.tab, "hire", "the hire tab")
	var cands := SimQuery.candidates(sim, HUGO, BLD)
	eq(cands.size(), 16, "the 16 townsfolk without a job")
	for c: Dictionary in cands:
		check(p.row_of(str(c["character"])) != null, "a row for %s" % c["character"])
	var first: Dictionary = cands[0]
	var text := _texts(p.row_of(str(first["character"])))
	check(text.contains(str(first["name"])), "the name")
	check(text.contains(SimQuery.rank_name(cat, str(first["rank"]))), "the rank")
	check(text.contains("%s %d" % [SimQuery.t_("stat.craft"), int(first["stats"]["craft"])]), "the craft (%s)" % text)
	check(text.contains(SimQuery.t_("stat.charisma")) and text.contains(SimQuery.t_("stat.constitution")), "charisma, constitution")
	check(text.contains(str(int(first["wage"]))), "the wage")
	var ok: Array = cands.filter(func(c: Dictionary) -> bool: return str(c["status"]) == "ok")
	check(not ok.is_empty(), "someone can be hired")
	var who := str(ok[0]["character"])
	check(_press(p.row_of(who), "Hire"), "Hire is pressable")
	_same(_last(), {"type": "hire", "actor": HUGO, "building": BLD, "candidate": who}, "Hire -> hire")
	_free(v)


func test_hire_is_disabled_with_the_reason_when_no_slot() -> void:
	var sim := _sim("two_employees")   # 2 places, both taken
	var v := _interior(sim)
	v.show_staff(true, "hire")
	var p := v.staff_panel()
	var cands := SimQuery.candidates(sim, HUGO, BLD)
	check(not cands.is_empty(), "candidates are still listed")
	var row := p.row_of(str(cands[0]["character"]))
	var hb := row.find_child("Hire", true, false) as Button
	check(hb.disabled, "Hire disabled")
	var why := row.find_child("Reason", true, false) as Label
	check(why != null and why.text == SimQuery.reason_text(str(cands[0]["status"])), "the reason is shown")
	eq(str(cands[0]["status"]), "no_slot", "because there is no free place")
	check(not _press(row, "Hire"), "a disabled Hire gives nothing")
	eq(_orders.size(), 0, "no order")
	check((p.get_node("%SlotsLabel") as Label).text.contains("2/2"), "places 2/2")
	_free(v)


func test_staff_orders_through_the_sim_take_effect() -> void:
	var sim := _sim("town_e_start")
	var v := _interior(sim, HUGO, false)
	v.show_staff(true, "hire")
	var who := ""
	for c: Dictionary in SimQuery.candidates(sim, HUGO, BLD):
		if str(c["status"]) == "ok":
			who = str(c["character"])
			break
	_press(v.staff_panel().row_of(who), "Hire")
	var ev := sim.step(_orders.duplicate(true))
	_orders.clear()
	eq(ev.filter(func(e: Dictionary) -> bool: return e["type"] == "order_refused").size(), 0, "the sim takes the hire")
	eq(Staff.employer(sim.state, who), BLD, "hired at the forge")
	v.staff_panel().show_tab("staff")
	check(v.staff_panel().row_of(who) != null, "now on the staff tab")
	check(_texts(v.staff_panel().row_of(who)).contains(SimQuery.t_("ui.staff.starts") % (int(sim.state.characters[who]["job"]["start_day"]) + 1)),
		"starts tomorrow")
	_free(v)


# --- production queue ------------------------------------------------------------------------------------------------

func test_queue_shows_entries_and_gives_queue_orders() -> void:
	var sim := _sim("two_employees")
	var q: Dictionary = sim.state.buildings[BLD]["queue"]
	q["entries"].append({"id": "qen_0090", "recipe": "forge_ingot", "qty": -1, "done": 2})
	var v := _interior(sim)
	(v.get_node("%ProductionButton") as Button).toggled.emit(true)
	var p := v.production_panel()
	check(p.visible, "the production panel opens")
	var r1 := p.entry_row("qen_0001")
	var r2 := p.entry_row("qen_0090")
	check(r1 != null and r2 != null, "a row per entry")
	var t1 := (r1.find_child("Text", true, false) as Label).text
	check(t1.contains(SimQuery.recipe_name(cat, "forge_sword")) and t1.contains("0/10"), "recipe and progress (%s)" % t1)
	check(r1.find_child("Bar", true, false) != null, "a progress bar for a finite entry")
	check((r2.find_child("Text", true, false) as Label).text.contains("2/∞"), "infinite entry")
	check(r2.find_child("Bar", true, false) == null, "no bar for ∞")
	check((r1.find_child("Up", true, false) as Button).disabled, "the first cannot go up")
	check((r2.find_child("Down", true, false) as Button).disabled, "the last cannot go down")
	_press(r1, "Down")
	_same(_last(), {"type": "queue_move", "actor": HUGO, "building": BLD, "entry": "qen_0001", "to": 1}, "Down")
	_press(p.entry_row("qen_0090"), "Up")
	_same(_last(), {"type": "queue_move", "actor": HUGO, "building": BLD, "entry": "qen_0090", "to": 0}, "Up")
	_press(p.entry_row("qen_0001"), "Remove")
	_same(_last(), {"type": "queue_remove", "actor": HUGO, "building": BLD, "entry": "qen_0001"}, "Remove")
	_free(v)


func test_queue_add_loop_and_pause() -> void:
	var sim := _sim("two_employees")
	var v := _interior(sim)
	v.show_production(true)
	var p := v.production_panel()
	var opt := p.get_node("%RecipeOption") as OptionButton
	eq(opt.item_count, SimQuery.building_recipes(sim.state, cat, BLD).size(), "every forge recipe to pick")
	eq(str(opt.get_item_metadata(0)), "forge_ingot", "furnace recipes first")
	p.select_recipe("forge_sword")
	var want := {"1": 1, "5": 5, "10": 10, "Inf": -1}
	for k: String in want:
		(p.get_node("%Add" + k) as Button).pressed.emit()
		_same(_last(), {"type": "queue_add", "actor": HUGO, "building": BLD, "recipe": "forge_sword", "qty": want[k]},
			"+%s -> queue_add" % k)
	(p.get_node("%LoopButton") as Button).toggled.emit(true)
	_same(_last(), {"type": "queue_loop", "actor": HUGO, "building": BLD, "on": true}, "Loop on")
	(p.get_node("%PauseButton") as Button).toggled.emit(true)
	_same(_last(), {"type": "queue_pause", "actor": HUGO, "building": BLD, "on": true}, "Pause on")
	(p.get_node("%PauseButton") as Button).toggled.emit(false)
	_same(_last(), {"type": "queue_pause", "actor": HUGO, "building": BLD, "on": false}, "Pause off")
	eq(_orders.size(), 7, "one order per click")
	_free(v)


func test_queue_entry_warning_and_stall() -> void:
	var sim := _sim("two_employees")
	sim.state.buildings[BLD]["inventory"] = {"stacks": []}
	var v := _interior(sim)
	v.show_production(true)
	var p := v.production_panel()
	for i: int in 200:   # run until the queue says why it cannot make the swords (cola fills the statuses)
		sim.step()
		if str(SimQuery.queue_view(sim, BLD)["entries"][0]["status"]) not in ["", "ok", "working"]:
			break
	p.refresh()
	var status := str(SimQuery.queue_view(sim, BLD)["entries"][0]["status"])
	check(status not in ["", "ok", "working"], "the empty storage is a reason to skip (%s)" % status)
	var w := p.entry_row("qen_0001").find_child("Warning", true, false) as Label
	check(w != null and w.text.contains(SimQuery.reason_text(status)), "the entry shows its warning")
	var stalled := str(SimQuery.queue_view(sim, BLD)["stalled"])
	eq((p.get_node("%StalledLabel") as Label).visible, stalled != "", "the general warning when nothing can be made")
	_free(v)


# --- map -------------------------------------------------------------------------------------------------------------

func _world(sim: Sim) -> WorldView:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(sim.state, cat, sim)
	return v


func _house_screen(v: WorldView, bld: String) -> Vector2:
	var b: Dictionary = v.state.buildings[bld]
	var o: Array = b["origin"]
	return v.camera().world_to_screen(Iso.tile_to_world(Vector2i(int(o[0]) + 1, int(o[1]) + 1)) + Vector2(0, -20))


func test_house_signs_only_on_hover_or_pick() -> void:
	var sim := _sim("town_e_start")
	var v := _world(sim)
	var houses: Array = sim.state.buildings.keys().filter(func(b: String) -> bool:
		return str(sim.state.buildings[b]["type"]) == "house")
	eq(houses.size(), 8, "8 houses")
	for h: String in houses:
		check(not v.sign_shown(h), "house %s: no sign at rest" % h)
	check(v.sign_shown(BLD), "the forge's sign is always there")
	var h0 := str(houses[0])
	v.camera().center_on(Iso.tile_to_world(Vector2i(int(sim.state.buildings[h0]["origin"][0]) + 1,
		int(sim.state.buildings[h0]["origin"][1]) + 1)))
	v.update_hover(_house_screen(v, h0))
	eq(v.hovered_building, h0, "the mouse is over the house")
	check(v.sign_shown(h0), "its sign shows on hover")
	v.update_hover(Vector2(-500, -500))
	check(not v.sign_shown(h0), "and hides again")
	v.pick_building_id(h0)
	check(v.sign_shown(h0), "a picked house shows its sign")
	_free(v)


func test_employees_carry_the_badge_of_their_employer() -> void:
	var sim := _sim("two_employees")
	var v := _world(sim)
	v.sync(0.0)
	var red := ViewConfig.color(str(sim.state.families["fam_0001"]["colors"]["primary"]))
	for id: String in [JOAN, AGNES]:
		var cv := v.view_of(id)
		check(cv != null, "%s has a figure" % id)
		eq(cv.badge, red, "%s: badge in the player's colour" % id)
		check(cv.badge_own, "%s: works for the player" % id)
	var other := v.view_of("chr_0009")
	eq(other.badge.a, 0.0, "a townsperson without a job has no badge")
	var soler := ViewConfig.color(str(sim.state.families["fam_0004"]["colors"]["primary"]))
	eq(v.view_of(JOAN).primary, soler, "dressed in the colours of their own family (Soler)")
	check(not v.view_of(JOAN).selectable, "employees are not the player's to select")
	_free(v)


func test_hover_shows_the_name_and_family() -> void:
	var sim := _sim("town_e_start")
	var v := _world(sim)
	sim.state.characters["chr_0009"]["location"] = ""   # out of the house, on its door tile
	v.sync(0.0)
	var cv := v.view_of("chr_0009")
	check(cv.visible, "outside: drawn")
	v.camera().center_on(cv.position)
	v.update_hover(v.camera().world_to_screen(cv.position + Vector2(0, -20)))
	eq(v.hovered_character, "chr_0009", "the mouse is over Pau")
	var lbl := cv.name_label()
	check(lbl.visible and lbl.text == "Pau · Puig", "name and family on hover (%s)" % lbl.text)
	v.update_hover(Vector2(-500, -500))
	check(not lbl.visible, "hidden when the mouse leaves")
	_free(v)


func test_idle_icon_over_the_forge_with_idle_employees() -> void:
	var sim := _sim("two_employees")
	sim.state.buildings[BLD]["queue"]["entries"] = []   # nothing to make: at work, idle
	var v := _world(sim)
	check(not v.idle_mark_of(BLD).visible, "no icon at night (nobody at work)")
	for i: int in 240:
		sim.step()
		if not SimQuery.idle_employees(sim, BLD).is_empty():
			break
	check(not SimQuery.idle_employees(sim, BLD).is_empty(), "the employees reach the forge with nothing to do")
	v.sync(0.0)
	check(v.idle_mark_of(BLD).visible, "the idle icon is over the forge")
	for h: String in sim.state.buildings:
		if h != BLD:
			check(not v.idle_mark_of(h).visible, "no icon over %s" % h)
	_free(v)


# --- interior --------------------------------------------------------------------------------------------------------

func test_employees_at_their_stations_inside() -> void:
	var sim := _sim("two_employees")
	var v := _interior(sim)
	var both := func() -> bool:
		return str(sim.state.characters[JOAN].get("station", "")) != "" and str(sim.state.characters[AGNES].get("station", "")) != ""
	for i: int in 600:   # Joan waits for Agnès's ingots before the anvil (10:32 in this scenario)
		if both.call():
			break
		sim.step()
	check(both.call(), "both employees reach a station")
	v.sync()
	for id: String in [JOAN, AGNES]:
		var cv := v.view_of(id)
		check(cv != null, "%s is drawn inside" % id)
		check(cv.badge_own, "%s shows the badge" % id)
		check(cv.name_label().visible, "%s shows the name inside" % id)
	eq(str(sim.state.characters[JOAN]["station"]), "anvil", "Joan (anvil) at the anvil")
	eq(str(sim.state.characters[AGNES]["station"]), "furnace", "Agnès (furnace) at the furnace")
	var busy := 0
	for z: String in ["furnace", "anvil"]:
		if v.station_view(z).progress >= 0.0:
			busy += 1
	check(busy >= 1, "a station shows the progress bar of an employee's cycle")
	_free(v)


# --- helpers ---------------------------------------------------------------------------------------------------------

## Every label text under `n`, joined.
func _texts(n: Node) -> String:
	if n == null:
		return ""
	var out := ""
	if n is Label:
		out += (n as Label).text + " | "
	for c: Node in n.get_children():
		out += _texts(c)
	return out
