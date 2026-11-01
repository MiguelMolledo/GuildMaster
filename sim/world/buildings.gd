class_name Buildings
extends RefCounted
## Entering, leaving and moving between stations of a building (GDD 4.6.4). Owner: subgrim «edificio».
## Contract: docs/contratos/h2_forja.md. Stub until implemented.


static func order_enter(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


static func order_exit(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


static func order_go_to_station(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


static func step(_sim: Sim) -> void:
	pass
