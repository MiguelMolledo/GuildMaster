extends "res://tests/test_case.gd"
## Transfers need physical proximity (GDD 4.3.4; docs/contratos/h2_forja.md): character <-> building only from
## inside; character <-> character of the family only on the same tile or inside the same building.

var cat := Catalog.load_from()

const HUGO := "chr_0001"
const ELENA := "chr_0002"
const MARTA := "chr_0004"
const FORGE := "bld_0001"


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("town_e_start", 1)["state"], cat)


func _chr(sim: Sim, id: String) -> Dictionary:
	return sim.state.characters[id]


func _move(actor: String, from: String, to: String, qty: int = 1) -> Dictionary:
	return {"type": "transfer", "actor": actor, "from": from, "to": to, "item": "iron", "quality": 0, "qty": qty}


func _result(sim: Sim, order: Dictionary) -> String:
	var ev := sim.step([order])
	var r: Array = ev.filter(func(e: Dictionary) -> bool: return e["type"] == "order_refused")
	return "ok" if r.is_empty() else str(r[0]["reason"])


func _inside(sim: Sim, id: String) -> void:
	_chr(sim, id)["location"] = FORGE


func test_character_and_building_only_from_inside() -> void:
	var sim := _sim()
	eq(_result(sim, _move(HUGO, FORGE, HUGO)), "not_inside", "from the street")
	_inside(sim, HUGO)
	eq(_result(sim, _move(HUGO, FORGE, HUGO, 3)), "ok", "from inside (family forge)")
	eq(Inventory.count(_chr(sim, HUGO)["inventory"], "iron"), 3, "in the bag")
	eq(_result(sim, _move(HUGO, HUGO, FORGE, 1)), "ok", "and back")
	eq(_result(sim, _move(HUGO, FORGE, ELENA)), "not_inside", "to Elena outside")
	_inside(sim, ELENA)
	eq(_result(sim, _move(HUGO, FORGE, ELENA)), "ok", "to Elena inside")
	_chr(sim, HUGO)["location"] = ""
	eq(_result(sim, _move(HUGO, FORGE, ELENA)), "not_inside", "the owner must be inside too")


func test_another_family_cannot_take() -> void:
	var sim := _sim()
	_chr(sim, MARTA)["location"] = FORGE  # even if she were inside
	eq(_result(sim, _move(MARTA, FORGE, MARTA)), "not_yours", "not her forge")


func test_family_hands_over_on_the_same_tile() -> void:
	var sim := _sim()
	Inventory.add(_chr(sim, HUGO)["inventory"], cat, "iron", 0, 4)
	eq(_result(sim, _move(HUGO, HUGO, ELENA)), "too_far", "different tiles")
	_chr(sim, ELENA)["position"] = (_chr(sim, HUGO)["position"] as Array).duplicate()
	eq(_result(sim, _move(HUGO, HUGO, ELENA)), "ok", "same tile")
	eq(Inventory.count(_chr(sim, ELENA)["inventory"], "iron"), 1, "Elena has it")
	_inside(sim, HUGO)
	eq(_result(sim, _move(HUGO, HUGO, ELENA)), "too_far", "one inside, one outside")
	_inside(sim, ELENA)
	_chr(sim, ELENA)["position"] = [0, 0]
	eq(_result(sim, _move(HUGO, HUGO, ELENA)), "ok", "both inside the same building")
	_chr(sim, MARTA)["position"] = (_chr(sim, HUGO)["position"] as Array).duplicate()
	_chr(sim, MARTA)["location"] = FORGE
	eq(_result(sim, _move(HUGO, HUGO, MARTA)), "not_family", "not to another family")


func test_too_heavy_counts_the_equipment() -> void:
	var sim := _sim()
	_inside(sim, HUGO)
	Inventory.add(sim.state.buildings[FORGE]["inventory"], cat, "hammer", 0, 1)
	Inventory.add(sim.state.buildings[FORGE]["inventory"], cat, "iron", 0, 10)  # 20 iron in the storage
	eq(_result(sim, {"type": "transfer", "actor": HUGO, "from": FORGE, "to": HUGO, "item": "hammer", "quality": 0,
		"qty": 1}), "ok", "takes the hammer (6 kg)")
	eq(_result(sim, {"type": "equip", "actor": HUGO, "item": "hammer", "quality": 0}), "ok", "equips it")
	# 30 kg in all: 6 worn, so 12 iron (24 kg) fit and a 13th does not.
	eq(_result(sim, _move(HUGO, FORGE, HUGO, 13)), "too_heavy", "the hammer still weighs")
	eq(_result(sim, _move(HUGO, FORGE, HUGO, 12)), "ok", "up to the limit")
	near(Equipment.carried_weight(sim, HUGO), 30.0, 0.001, "full load")
