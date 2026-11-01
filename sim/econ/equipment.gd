class_name Equipment
extends RefCounted
## Equipment slots and carried weight (GDD 4.3.4). Owner: subgrim «edificio». Contract: docs/contratos/h2_forja.md.


static func order_equip(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


static func order_unequip(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")
