extends "res://tests/test_case.gd"
## Equipment slots and carried weight (GDD 4.3.4; docs/contratos/h2_forja.md): the slot comes from the item, equipping
## keeps the weight, swapping returns the old piece, refusals, and the round trip of a save.

var cat := Catalog.load_from()

const HUGO := "chr_0001"


func _sim() -> Sim:
	var sim := Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)
	var inv: Dictionary = sim.state.characters[HUGO]["inventory"]
	Inventory.add(inv, cat, "hammer", 0, 1)
	Inventory.add(inv, cat, "needle", 1, 1)
	Inventory.add(inv, cat, "work_clothes", 0, 1)
	Inventory.add(inv, cat, "travel_cloak", 0, 1)
	return sim


func _result(sim: Sim, order: Dictionary) -> String:
	var ev := sim.step([order])
	var r: Array = ev.filter(func(e: Dictionary) -> bool: return e["type"] == "order_refused")
	return "ok" if r.is_empty() else str(r[0]["reason"])


func _eq_of(sim: Sim) -> Dictionary:
	return sim.state.characters[HUGO]["equipment"]


func _equip(item: String, quality: int = 0) -> Dictionary:
	return {"type": "equip", "actor": HUGO, "item": item, "quality": quality}


func test_slots_come_from_the_item() -> void:
	eq(Equipment.slot_of(cat, "hammer"), "tool", "tool")
	eq(Equipment.slot_of(cat, "work_clothes"), "clothes", "work clothes")
	eq(Equipment.slot_of(cat, "armor"), "clothes", "armour")
	eq(Equipment.slot_of(cat, "travel_cloak"), "accessory", "cloak")
	eq(Equipment.slot_of(cat, "iron"), "", "raw material")


func test_equip_keeps_the_weight() -> void:
	var sim := _sim()
	var w := Equipment.carried_weight(sim, HUGO)
	near(w, 6.0 + 0.5 + 3.0 + 2.0, 0.001, "bag before")
	near(Equipment.max_weight(sim, HUGO), 30.0, 0.001, "max 30 kg")
	var ev := sim.step([_equip("hammer"), _equip("work_clothes"), _equip("travel_cloak")])
	eq(ev.filter(func(e: Dictionary) -> bool: return e["type"] == "item_equipped").size(), 3, "three events")
	eq(_eq_of(sim)["tool"], {"item": "hammer", "quality": 0}, "tool slot")
	eq(_eq_of(sim)["clothes"], {"item": "work_clothes", "quality": 0}, "clothes slot")
	eq(_eq_of(sim)["accessory"], {"item": "travel_cloak", "quality": 0}, "accessory slot")
	eq(Inventory.count(sim.state.characters[HUGO]["inventory"], "hammer"), 0, "out of the bag")
	near(Equipment.carried_weight(sim, HUGO), w, 0.001, "same total weight")
	near(Equipment.max_weight(sim, HUGO), 30.0, 0.001, "same max")


func test_swap_returns_the_old_piece() -> void:
	var sim := _sim()
	sim.step([_equip("hammer")])
	var ev := sim.step([_equip("needle", 1)])
	eq(_eq_of(sim)["tool"], {"item": "needle", "quality": 1}, "needle worn")
	eq(Inventory.count(sim.state.characters[HUGO]["inventory"], "hammer", 0), 1, "hammer back in the bag")
	eq(ev.filter(func(e: Dictionary) -> bool: return e["type"] == "item_unequipped").size(), 1, "unequip event")
	near(Equipment.max_weight(sim, HUGO), 30.0, 0.001, "max unchanged")


func test_unequip() -> void:
	var sim := _sim()
	sim.step([_equip("hammer")])
	eq(_result(sim, {"type": "unequip", "actor": HUGO, "slot": "tool"}), "ok", "unequipped")
	check(_eq_of(sim)["tool"] == null, "slot empty")
	eq(Inventory.count(sim.state.characters[HUGO]["inventory"], "hammer"), 1, "in the bag")
	near(float(sim.state.characters[HUGO]["inventory"]["limit"]), 30.0, 0.001, "bag limit back to 30")


func test_refusals() -> void:
	var sim := _sim()
	Inventory.add(sim.state.characters[HUGO]["inventory"], cat, "iron", 0, 1)
	eq(_result(sim, _equip("iron")), "not_equippable", "raw material")
	eq(_result(sim, _equip("saw")), "not_enough", "not carried")
	eq(_result(sim, _equip("hammer", 2)), "not_enough", "not in that quality")
	eq(_result(sim, {"type": "unequip", "actor": HUGO, "slot": "tool"}), "slot_empty", "nothing worn")
	eq(_result(sim, {"type": "unequip", "actor": HUGO, "slot": "hat"}), "unknown_slot", "no such slot")
	eq(_result(sim, {"type": "equip", "actor": "chr_0099", "item": "hammer"}), "unknown_actor", "missing actor")


func test_bag_limit_counts_what_is_worn() -> void:
	var sim := _sim()
	sim.step([_equip("hammer"), _equip("work_clothes")])
	var inv: Dictionary = sim.state.characters[HUGO]["inventory"]
	# 9 kg worn, 2.5 kg in the bag: 18.5 kg left -> 9 iron (18 kg) fit, a 10th does not.
	check(Inventory.can_add(inv, cat, "iron", 0, 9), "9 iron fit")
	check(not Inventory.can_add(inv, cat, "iron", 0, 10), "10 do not")


func test_save_round_trip() -> void:
	var sim := _sim()
	sim.step([_equip("hammer"), _equip("travel_cloak")])
	var path := "user://test_econ_equipment.json"
	eq(SaveFile.save(sim.state, path), OK, "saved")
	var r := SaveFile.load_file(path)
	var other := Sim.new(r["state"], cat)
	eq(other.state_hash(), sim.state_hash(), "same state")
	near(Equipment.carried_weight(other, HUGO), Equipment.carried_weight(sim, HUGO), 0.001, "same weight")
	near(Equipment.max_weight(other, HUGO), 30.0, 0.001, "same max")
	eq(_result(other, {"type": "unequip", "actor": HUGO, "slot": "tool"}), "ok", "unequips after loading")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
