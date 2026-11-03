extends "res://tests/test_case.gd"
## Storage and the person's sheet (docs/ui/mecanicas/almacen_y_personaje.md §10): every square of the storage seen, the
## locked row of the upgrade, «Solo caben 3 de 8», Take products by weight, quality as separate squares, the line of the
## management mode, the hammer's effect written in the sheet, an errand «en camino». Orders through the sim.

const BLD := "bld_0001"
const HUGO := "chr_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start")["state"], cat)


func _inside(sim: Sim) -> void:
	sim.step([{"type": "enter_building", "actor": HUGO, "building": BLD}])
	for i: int in 600:
		if str(sim.state.characters[HUGO]["location"]) == BLD:
			break
		sim.step()


func _only(sim: Sim, stacks: Array) -> void:
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	inv["stacks"] = []
	for s: Array in stacks:
		Inventory.add(inv, cat, str(s[0]), int(s[1]), int(s[2]))


func _bag(sim: Sim, kg_free: float) -> void:
	sim.state.characters[HUGO]["inventory"]["stacks"] = []
	var used := SimQuery.carried_weight(sim, HUGO)
	var room := SimQuery.max_weight(sim, HUGO) - used
	var stones := int(floor((room - kg_free) / float(cat.item("stone").get("weight", 3.0))))
	if stones > 0:
		Inventory.add(sim.state.characters[HUGO]["inventory"], cat, "stone", 0, stones)


func _panel(sim: Sim) -> StoragePanel:
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.setup(sim, BLD, HUGO, false)
	v.show_storage(true)
	return v.storage_panel()


func test_every_square_and_the_locked_row() -> void:
	var sim := _sim()
	_inside(sim)
	_only(sim, [["iron", 0, 8], ["coal", 0, 4], ["sword", 0, 1]])
	var p := _panel(sim)
	var grid := p.get_node("%BuildingGrid") as GridContainer
	var empty := 0
	var locked := 0
	for c: Node in grid.get_children():
		empty += 1 if (c as ItemSlot).state == "empty" else 0
		locked += 1 if (c as ItemSlot).state == "locked" else 0
	var limit := int(sim.state.buildings[BLD]["inventory"]["limit"])
	eq(empty, limit - 3, "3 stacks in %d: %d empty squares" % [limit, limit - 3])
	check(locked > 0, "a row of locked squares")
	check((p.get_node("%LockedLine") as Label).text.contains(SimQuery.upgrade_name(cat, "forge_capacity_2")), "with the upgrade's name")
	p.get_parent().get_parent().get_parent().get_parent().free()


func test_only_three_of_eight_fit() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	_inside(sim)
	_only(sim, [["iron", 0, 8]])
	_bag(sim, 6.0)
	var p := _panel(sim)
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	var fits := Inventory.fit_count(sim.state.characters[HUGO]["inventory"], cat, "iron", 0, 8)
	p.move_to_actor("iron", 0, 8)
	eq(int(got[0]["qty"]), fits, "moves what fits (%d)" % fits)
	check(p.last_reason().begins_with("Solo caben %d de 8" % fits), "and says it (%s)" % p.last_reason())
	TranslationServer.set_locale(before)
	p.get_parent().get_parent().get_parent().get_parent().free()


func test_take_products_by_weight() -> void:
	var sim := _sim()
	_inside(sim)
	_only(sim, [["sword", 0, 2], ["hammer", 0, 1]])
	_bag(sim, 20.0)
	var p := _panel(sim)
	var got: Array = []
	p.order_sink = func(o: Dictionary) -> void: got.append(o)
	p.take_products()
	var swords := got.filter(func(o: Dictionary) -> bool: return str(o["item"]) == "sword")
	var hammers := got.filter(func(o: Dictionary) -> bool: return str(o["item"]) == "hammer")
	check(swords.size() == 1 and int(swords[0]["qty"]) == 2, "both swords (16 kg)")
	check(hammers.is_empty(), "the hammer (6 kg) is left")
	check(p.last_reason() != "", "with the reason")
	p.get_parent().get_parent().get_parent().get_parent().free()


func test_qualities_are_separate_squares() -> void:
	var sim := _sim()
	_inside(sim)
	_only(sim, [["sword", 0, 1], ["sword", 1, 1]])
	var p := _panel(sim)
	var good := p.row_of("sword", 1, true) as ItemSlot
	var plain := p.row_of("sword", 0, true) as ItemSlot
	check(good != null and plain != null and good != plain, "two squares")
	eq(good.quality, 1, "the good one has its dot")
	p.get_parent().get_parent().get_parent().get_parent().free()


func test_management_mode_says_why_nothing_moves() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	var v: InteriorView = (load("res://game/interior/interior_view.tscn") as PackedScene).instantiate()
	v.setup(sim, BLD, "", true)
	v.show_storage(true)
	var p := v.storage_panel()
	check((p.get_node("%Hint") as Label).text.begins_with("Entra con un personaje"), "the line says why")
	check(not (p.get_node("%Shortcuts") as Control).visible, "no shortcuts to move")
	TranslationServer.set_locale(before)
	v.free()


func test_the_sheet_says_what_the_hammer_gives() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var sim := _sim()
	sim.state.characters[HUGO]["equipment"]["tool"] = {"item": "hammer", "quality": 0}
	var p: CharacterPanel = (load("res://game/ui/character_panel.tscn") as PackedScene).instantiate()
	p.setup(sim, HUGO)
	var eff := p.get_node("%Slots").get_node("tool").find_child("Effect", true, false) as Label
	check(eff != null and eff.visible and eff.text.contains("10 %") and eff.text.contains("Forja"),
		"the tool's effect in the Forge: " + (eff.text if eff != null else ""))
	TranslationServer.set_locale(before)
	p.free()


func test_an_errand_is_seen_on_the_way() -> void:
	var sim := _sim()
	_inside(sim)
	var fam := SimQuery.building_family(sim.state, BLD)
	sim.state.deliveries.append({"id": "dlv_0099", "family": fam, "actor": HUGO, "stall": "resources", "to": BLD,
		"item": "iron", "quality": 0, "qty": 6, "arrive": int(sim.state.clock["minute"]) + 90})
	var p := _panel(sim)
	var rows := (p.get_node("%Errands") as Node).get_children()
	eq(rows.size(), 1, "one errand on its way")
	check((rows[0] as Label).text.contains("6"), "with its quantity")
	p.get_parent().get_parent().get_parent().get_parent().free()
