extends "res://tests/test_case.gd"
## H5 view (GDD 4.8, 4.6.2, 4.6.4): the upgrade tree panel of the real interior scene gives the exact buy_upgrade of
## docs/contratos/h5_mejoras.md and shows each upgrade's status with its reason; the works in progress show in the
## panel, under the interior's title and over the building on the map (scaffold + bar); the upgrade visuals (nodes
## under Upgrades of the interior and exterior scenes) appear when an upgrade finishes (scenarios forge_upgrades and
## forge_upgrade_works); the upgrade notices read with names. Windowless: the scenes are built by hand and the orders
## are caught by a sink.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()
var _orders: Array = []


func _sim(scenario: String) -> Sim:
	var r := NewGame.from_scenario(scenario)
	check(bool(r["ok"]), "scenario %s loads" % scenario)
	return Sim.new(r["state"], cat)


func _sink(o: Dictionary) -> void:
	_orders.append(o.duplicate(true))


func _interior(sim: Sim, who: String = "", manage: bool = true) -> InteriorView:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.order_sink = _sink
	v.setup(sim, BLD, who, manage)
	_orders.clear()
	return v


func _world(sim: Sim) -> WorldView:
	var v: WorldView = (load("res://game/world/world_view.tscn") as PackedScene).instantiate()
	v.setup(sim.state, cat, sim)
	v.refresh_upgrades()
	return v


func _open_panel(v: InteriorView) -> UpgradePanel:
	var b := v.get_node("%UpgradesButton") as Button
	b.toggled.emit(true)
	return v.upgrade_panel()


func _same(got: Dictionary, want: Dictionary, msg: String) -> void:
	eq(SaveFile.canonical(got), SaveFile.canonical(want), msg)


func _texts(n: Node) -> String:
	var out: PackedStringArray = []
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c: Node in n.get_children():
		out.append(_texts(c))
	return " ".join(out)


func _es() -> String:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	return before


# --- the panel ---------------------------------------------------------------------------------------------------------

func test_upgrades_button_opens_the_tree_with_its_eight_branches() -> void:
	var sim := _sim("forge_upgrades")
	var v := _interior(sim)
	var b := v.get_node("%UpgradesButton") as Button
	check(b.visible and not b.disabled, "the Upgrades button is there and usable")
	var p := _open_panel(v)
	check(p.visible, "the panel opens")
	check(not v.staff_panel().visible and not v.production_panel().visible and not v.storage_panel().visible,
		"the other panels are closed")
	eq(p.cell_of("forge_production_1") != null, true, "a cell per upgrade")
	var n := 0
	for br: String in sim.catalog.upgrade_rules["branches"]:
		for l: int in range(1, 4):
			check(p.cell_of("forge_%s_%d" % [br, l]) != null, "cell forge_%s_%d" % [br, l])
			n += 1
	eq(n, 24, "8 branches × 3 levels")
	for id: String in ["forge_production_1", "forge_capacity_1", "forge_quality_1", "forge_staff_1"]:
		eq(p.status_of(id), "owned", "%s built in the scenario" % id)
	eq(p.status_of("forge_capacity_2"), "available", "capacity 2 can be bought (materials and gold are there)")
	eq(p.status_of("forge_commerce_3"), "needs_upgrade", "commerce 3 needs the stone facade")
	eq(p.status_of("forge_facade_3"), "needs_upgrade", "facade 3 needs facade 2 first")
	v.free()


func test_buy_gives_the_exact_buy_upgrade() -> void:
	var sim := _sim("forge_upgrades")
	var v := _interior(sim)
	var p := _open_panel(v)
	p.cell_of("forge_capacity_2").pressed.emit()
	eq(p.selected, "forge_capacity_2", "the click shows its detail")
	var buy := p.get_node("%BuyButton") as Button
	check(buy.visible and not buy.disabled, "Buy is usable for an available upgrade")
	buy.pressed.emit()
	eq(_orders.size(), 1, "one order")
	_same(_orders.back() if not _orders.is_empty() else {}, {"type": "buy_upgrade", "actor": HUGO, "building": BLD,
		"upgrade": "forge_capacity_2"}, "buy_upgrade with the actor, the building and the upgrade")
	v.free()


func test_the_order_is_signed_by_the_selected_member_inside() -> void:
	var sim := _sim("forge_upgrades")
	var v := _interior(sim, HUGO, false)
	var p := _open_panel(v)
	p.select("forge_quality_2")
	(p.get_node("%BuyButton") as Button).pressed.emit()
	eq(str(_orders.back().get("actor", "")) if not _orders.is_empty() else "", HUGO, "signed by the selected person")
	v.free()


func test_a_locked_upgrade_says_why_and_cannot_be_bought() -> void:
	var before := _es()
	var sim := _sim("forge_upgrades")
	var v := _interior(sim)
	var p := _open_panel(v)
	p.select("forge_commerce_3")
	var buy := p.get_node("%BuyButton") as Button
	check(buy.disabled, "Buy disabled")
	var status := (p.get_node("%DetailStatus") as Label).text
	check(status.contains(SimQuery.reason_text("needs_upgrade")), "the reason (%s)" % status)
	var req := _texts(p.get_node("%DetailLines"))
	check(req.contains(SimQuery.upgrade_name(cat, "forge_facade_1")), "the required upgrade by name (%s)" % req)
	check(req.contains("25") or req.contains(str(int(cat.upgrade("forge_commerce_3")["cost"]["gold"]))),
		"the gold cost (%s)" % req)
	eq(_orders.size(), 0, "no order")
	p.select("forge_secrets_2")
	var lines := _texts(p.get_node("%DetailLines"))
	check(lines.contains("Sigilo 3"), "the attribute with its minimum (%s)" % lines)
	check(lines.contains(SimQuery.item_name(cat, "wood")), "the materials (%s)" % lines)
	TranslationServer.set_locale(before)
	v.free()


func test_missing_materials_and_gold_are_shown() -> void:
	var sim := _sim("forge_upgrades")
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	for q: int in range(0, 4):
		Inventory.remove(inv, "wood", q, Inventory.count(inv, "wood", q))
	var v := _interior(sim)
	var p := _open_panel(v)
	eq(p.status_of("forge_capacity_2"), "missing_materials", "no wood: missing materials")
	p.select("forge_capacity_2")
	check((p.get_node("%BuyButton") as Button).disabled, "Buy disabled")
	var cost := p.get_node("%DetailLines").find_child("Cost", true, false) as Control
	var marked := false
	for c: Node in cost.get_children() if cost != null else []:
		marked = marked or (c is Label and (c as Label).theme_type_variation == &"ReasonLabel")
	check(marked, "the missing material is marked")
	v.free()


func test_effects_are_written_with_percentages_and_names() -> void:
	var before := _es()
	eq(SimQuery.effect_text(cat, {"kind": "protection", "amount": 0.2}), "Protección 20 %", "protection as a percentage")
	eq(SimQuery.effect_text(cat, {"kind": "inspection_risk", "amount": 0.05}), "Riesgo de inspección +5 %", "risk")
	eq(SimQuery.effect_text(cat, {"kind": "production_speed", "mult": 1.2}), "Velocidad de producción ×1.2", "speed")
	check(SimQuery.effect_text(cat, {"kind": "new_zone", "zone": "anvil_2", "like": "anvil"}).contains("Segundo yunque"),
		"the new station by name")
	TranslationServer.set_locale(before)


# --- works in progress -------------------------------------------------------------------------------------------------

func test_works_in_progress_in_the_panel_and_the_interior() -> void:
	var before := _es()
	var sim := _sim("forge_upgrade_works")
	var v := _interior(sim)
	var p := _open_panel(v)
	eq(p.status_of("forge_capacity_2"), "in_works", "capacity 2 is being built")
	eq(p.status_of("forge_quality_2"), "busy", "nothing else while the works last")
	check((p.get_node("%WorksBox") as Control).visible, "the works box shows")
	var wl := (p.get_node("%WorksLabel") as Label).text
	check(wl.contains(SimQuery.upgrade_name(cat, "forge_capacity_2")), "what is being built (%s)" % wl)
	check(wl.contains("12 h"), "the time left (%s)" % wl)
	near((p.get_node("%WorksBar") as ProgressBar).value, 50.0, 0.5, "half way")
	p.select("forge_quality_2")
	check((p.get_node("%BuyButton") as Button).disabled, "Buy disabled while busy")
	var il := v.get_node("%WorksLabel") as Label
	check(il.visible and il.text.contains("12 h"), "the interior says it is under works (%s)" % il.text)
	Upgrades.complete(sim, BLD, "forge_capacity_2")
	v.sync()
	p.refresh()
	check(not (p.get_node("%WorksBar") as Control).visible, "no works bar once finished (the strip says there are none)")
	eq(p.status_of("forge_capacity_2"), "owned", "built")
	v.refresh_works()
	check(not il.visible, "the interior label goes away")
	TranslationServer.set_locale(before)
	v.free()


func test_the_map_shows_the_scaffold_and_the_works_bar() -> void:
	var sim := _sim("forge_upgrade_works")
	var w := _world(sim)
	var scaffold := w.scaffold_of(BLD)
	check(scaffold != null, "the forge scene has its Works node")
	# the fal facade draws the works itself (LookConstruction, WorldView._apply_looks): scaffold or works facade
	check(w.works_shown(BLD), "the works show while under works")
	var bar := w.works_bar_of(BLD)
	check(bar != null and bar.visible, "the works bar shows")
	near(bar.progress, 0.5, 0.01, "half way")
	check(bar.text().contains("12"), "the time left (%s)" % bar.text())
	Upgrades.complete(sim, BLD, "forge_capacity_2")
	w.refresh_upgrades()
	check(not w.works_shown(BLD) and not bar.visible, "the works and the bar go away when the works end")
	w.free()
	var plain := _world(_sim("forge_upgrades"))
	check(not plain.works_shown(BLD) and not plain.works_bar_of(BLD).visible, "no works without works")
	plain.free()


# --- upgrade visuals ---------------------------------------------------------------------------------------------------

func test_interior_visuals_follow_the_finished_upgrades() -> void:
	var sim := _sim("forge_upgrades")
	var v := _interior(sim)
	for n: String in ["forge_bellows", "forge_anvil_2", "forge_quench_trough", "upgrade_bunks"]:
		check(v.upgrade_visual(n) != null and v.upgrade_visual(n).visible, "%s shows (finished)" % n)
	for n: String in ["forge_tempering_tub", "upgrade_storage_shelves", "upgrade_counter", "upgrade_strongbox"]:
		check(v.upgrade_visual(n) != null and not v.upgrade_visual(n).visible, "%s hidden (not built)" % n)
	check(v.station_view("anvil_2") != null, "the second anvil is a station")
	check(v.station_view("furnace_2") == null, "the second furnace is not yet")
	Upgrades.complete(sim, BLD, "forge_capacity_2")
	Upgrades.complete(sim, BLD, "forge_production_2")
	Upgrades.complete(sim, BLD, "forge_capacity_3")
	v.refresh_upgrades()
	check(v.upgrade_visual("upgrade_storage_shelves").visible, "the shelves appear with capacity 2")
	check(v.upgrade_visual("forge_tempering_tub").visible, "the tempering tub appears with production 2")
	check(not v.upgrade_visual("forge_bellows").visible, "production shows only its last level")
	check(v.upgrade_visual("forge_anvil_2").visible, "capacity shows every level")
	check(v.station_view("furnace_2") != null, "the second furnace appears as a station")
	v.free()


func test_exterior_visuals_follow_the_finished_upgrades() -> void:
	var sim := _sim("forge_upgrades")
	var w := _world(sim)
	var ups := w.building_visual(BLD).get_node("Upgrades")
	for u: Node in ups.get_children():
		check(not (u as CanvasItem).visible, "%s hidden at first (no exterior upgrade built)" % u.name)
	Upgrades.complete(sim, BLD, "forge_security_1")
	Upgrades.complete(sim, BLD, "forge_facade_1")
	w.refresh_upgrades()
	check((ups.get_node("upgrade_reinforced_lock") as CanvasItem).visible, "the lock appears")
	check((ups.get_node("upgrade_stone_facade") as CanvasItem).visible, "the stone facade appears")
	Upgrades.complete(sim, BLD, "forge_facade_2")
	Upgrades.complete(sim, BLD, "forge_security_2")
	Upgrades.complete(sim, BLD, "forge_commerce_1")
	Upgrades.complete(sim, BLD, "forge_commerce_2")
	w.refresh_upgrades()
	check((ups.get_node("upgrade_garden") as CanvasItem).visible, "the garden appears")
	check(not (ups.get_node("upgrade_stone_facade") as CanvasItem).visible, "the facade shows only its last level")
	check((ups.get_node("upgrade_reinforced_lock") as CanvasItem).visible and (ups.get_node("upgrade_guard") as CanvasItem).visible,
		"security shows every level")
	check((ups.get_node("upgrade_shop_window") as CanvasItem).visible, "the shop window appears (commerce 2)")
	w.free()


func test_visual_nodes_keep_only_the_last_level_of_latest_only_branches() -> void:
	var sim := _sim("forge_upgrades")
	eq(SimQuery.upgrade_visual_nodes(sim, BLD, "interior"), ["forge_bellows", "forge_anvil_2", "forge_quench_trough",
		"upgrade_bunks"], "the scenario's four, in finishing order")
	Upgrades.complete(sim, BLD, "forge_production_2")
	var nodes := SimQuery.upgrade_visual_nodes(sim, BLD, "interior")
	check(not "forge_bellows" in nodes and "forge_tempering_tub" in nodes, "production: the last level replaces (%s)" % [nodes])


# --- notices -----------------------------------------------------------------------------------------------------------

func test_upgrade_and_inspection_notices_read_with_names() -> void:
	var before := _es()
	var sim := _sim("forge_upgrades")
	var t := SimQuery.notice_text(sim.state, cat, {"key": "notice.upgrade_done", "params": {"building": BLD,
		"upgrade": "forge_capacity_2"}})
	check(t.contains(SimQuery.upgrade_name(cat, "forge_capacity_2")), "the upgrade by name (%s)" % t)
	check(t.contains(SimQuery.building_label(sim.state, cat, BLD)), "the building by name (%s)" % t)
	var f := SimQuery.notice_text(sim.state, cat, {"key": "notice.inspection_fined", "params": {"building": BLD,
		"amount": 30}})
	check(f.contains("30") and f.contains(SimQuery.building_label(sim.state, cat, BLD)), "the fine (%s)" % f)
	TranslationServer.set_locale(before)


func test_inspections_show_when_the_building_has_a_risk() -> void:
	var before := _es()
	var sim := _sim("forge_upgrades")
	var v := _interior(sim)
	var p := _open_panel(v)
	check(not (p.get_node("%InspectionLabel") as Label).visible, "no risk: no inspections line")
	Upgrades.complete(sim, BLD, "forge_secrets_1")
	p.refresh(true)
	var l := p.get_node("%InspectionLabel") as Label
	check(l.visible and l.text.contains("5%"), "the risk of the double ledger (%s)" % l.text)
	TranslationServer.set_locale(before)
	v.free()


# --- end to end with the sim (buy_upgrade of «arbol») -------------------------------------------------------------------

func test_buying_from_the_panel_starts_the_works_and_the_visual_appears_at_the_end() -> void:
	var sim := _sim("forge_upgrades")
	var v := _interior(sim)
	var w := _world(sim)
	var p := _open_panel(v)
	p.select("forge_capacity_2")
	(p.get_node("%BuyButton") as Button).pressed.emit()
	var r := Orders.apply(sim, _orders.back())
	check(bool(r.get("ok", false)), "the sim takes the panel's order (%s)" % [r])
	p.refresh()
	eq(p.status_of("forge_capacity_2"), "in_works", "the panel shows it under construction")
	check((p.get_node("%WorksBox") as Control).visible, "with its works bar")
	w.refresh_upgrades()
	check(w.works_shown(BLD) and w.works_bar_of(BLD).visible, "the works go up on the map")
	var end := int(Upgrades.work(sim.state, BLD).get("end", 0))
	var guard := 0
	while int(sim.state.clock["minute"]) < end and guard < 3000:
		sim.step()
		guard += 1
	check(Upgrades.has(sim.state, BLD, "forge_capacity_2"), "the works finished (Upgrades.step)")
	v.sync()
	w.refresh_upgrades()
	check(v.upgrade_visual("upgrade_storage_shelves").visible, "the shelves appear inside")
	check(not w.works_shown(BLD) and not w.works_bar_of(BLD).visible, "the works come down")
	var found := false
	for n: Dictionary in Notices.list(sim, "fam_0001"):
		if str(n.get("key", "")) == "notice.upgrade_done":
			found = true
	check(found, "the notice of the finished works is in the book")
	v.free()
	w.free()
