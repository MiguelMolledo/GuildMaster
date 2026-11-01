extends "res://tests/test_case.gd"
## Own inventory (GDD 05 §5.9, lessons L5, BUG-001/002/003/025): qualities never mix, never negative, all or nothing.

var cat := Catalog.load_from()


func test_qualities_do_not_mix() -> void:
	var inv := Inventory.create("stacks", 10)
	check(Inventory.add(inv, cat, "sword", Inventory.NORMAL, 3), "adds normal")
	check(Inventory.add(inv, cat, "sword", Inventory.GOOD, 2), "adds good")
	eq(Inventory.count(inv, "sword", Inventory.NORMAL), 3, "normal")
	eq(Inventory.count(inv, "sword", Inventory.GOOD), 2, "good")
	eq(Inventory.count(inv, "sword"), 5, "all")
	eq((inv["stacks"] as Array).size(), 2, "two stacks")


func test_cannot_remove_more_than_held() -> void:
	var inv := Inventory.create("stacks", 10)
	Inventory.add(inv, cat, "iron", Inventory.NORMAL, 5)
	check(not Inventory.remove(inv, "iron", Inventory.NORMAL, 6), "refuses 6 of 5")
	eq(Inventory.count(inv, "iron"), 5, "nothing taken")
	check(not Inventory.remove(inv, "iron", Inventory.GOOD, 1), "no good iron")
	check(Inventory.remove(inv, "iron", Inventory.NORMAL, 5), "takes all")
	eq((inv["stacks"] as Array).size(), 0, "empty stack removed")


func test_stack_limit_and_max_stack() -> void:
	var inv := Inventory.create("stacks", 2)
	check(Inventory.add(inv, cat, "iron", Inventory.NORMAL, 150), "150 iron in two stacks of 99")
	eq((inv["stacks"] as Array).size(), 2, "two stacks")
	check(Inventory.can_add(inv, cat, "iron", Inventory.NORMAL, 48), "48 more fit in the open stack")
	check(not Inventory.can_add(inv, cat, "iron", Inventory.NORMAL, 49), "49 do not")
	check(not Inventory.add(inv, cat, "coal", Inventory.NORMAL, 1), "no third stack")
	eq(Inventory.count(inv, "coal"), 0, "all or nothing")


func test_weight_limit() -> void:
	var inv := Inventory.create("weight", 30.0)
	check(Inventory.add(inv, cat, "iron", Inventory.NORMAL, 15), "15 iron = 30 kg")
	check(not Inventory.add(inv, cat, "herbs", Inventory.NORMAL, 1), "full")
	near(Inventory.weight(inv, cat), 30.0, 0.001, "weight")


func test_unknown_item_or_bad_quality_refused() -> void:
	var inv := Inventory.create("stacks", 10)
	check(not Inventory.add(inv, cat, "unobtainium", 0, 1), "unknown item")
	check(not Inventory.add(inv, cat, "iron", 3, 1), "bad quality")
	check(not Inventory.add(inv, cat, "iron", 0, 0), "zero")
