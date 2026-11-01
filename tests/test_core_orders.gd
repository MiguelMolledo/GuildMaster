extends "res://tests/test_case.gd"
## Orders (GDD 05 §5.5): validated in the sim; a refused order changes nothing and says why.

var cat := Catalog.load_from()


func _sim() -> Sim:
	var st := NewGame.fresh(cat, 1)
	st.characters["chr_0001"] = {"id": "chr_0001", "inventory": Inventory.create("weight", 30.0)}
	st.characters["chr_0002"] = {"id": "chr_0002", "inventory": Inventory.create("weight", 30.0)}
	st.buildings["bld_0001"] = {"id": "bld_0001", "owner": "chr_0001", "inventory": Inventory.create("stacks", 10)}
	Inventory.add(st.buildings["bld_0001"]["inventory"], cat, "iron", 0, 20)
	return Sim.new(st, cat)


func _move(actor: String, from: String, to: String, qty: int) -> Dictionary:
	return {"type": "transfer", "actor": actor, "from": from, "to": to, "item": "iron", "quality": 0, "qty": qty}


func test_transfer_moves_items() -> void:
	var sim := _sim()
	var ev := sim.step([_move("chr_0001", "bld_0001", "chr_0001", 5)])
	eq(Inventory.count(sim.state.characters["chr_0001"]["inventory"], "iron"), 5, "in the bag")
	eq(Inventory.count(sim.state.buildings["bld_0001"]["inventory"], "iron"), 15, "out of the forge")
	check(ev.any(func(e: Dictionary) -> bool: return e["type"] == "items_moved"), "event")


func test_refusals_change_nothing() -> void:
	var cases := [
		[_move("chr_0002", "bld_0001", "chr_0002", 1), "not_yours"],
		[_move("chr_0001", "bld_0001", "chr_0001", 16), "no_room"],
		[_move("chr_0001", "bld_0001", "chr_0001", 21), "not_enough"],
		[_move("chr_0001", "bld_0001", "chr_0001", 0), "bad_quantity"],
		[_move("chr_0009", "bld_0001", "chr_0001", 1), "unknown_actor"],
		[_move("chr_0001", "bld_0009", "chr_0001", 1), "no_inventory"],
		[{"type": "fly", "actor": "chr_0001"}, "unknown_order"],
	]
	for c: Array in cases:
		var sim := _sim()
		var before := SaveFile.canonical(sim.state.buildings)
		var ev := sim.step([c[0]])
		var refused: Array = ev.filter(func(e: Dictionary) -> bool: return e["type"] == "order_refused")
		check(refused.size() == 1 and refused[0]["reason"] == c[1], "refused with %s (got %s)" % [c[1], str(refused)])
		eq(SaveFile.canonical(sim.state.buildings), before, "nothing changed for %s" % c[1])
