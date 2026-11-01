class_name Production
extends RefCounted
## Work cycles at stations, quality, work modes and master touch (GDD 4.4). Owner: subgrim «produccion».
## Contract: docs/contratos/h2_forja.md. Stub until implemented.


static func order_work_at(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


static func order_stop_work(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


static func order_master_touch(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


static func order_buy_raw(_sim: Sim, _o: Dictionary) -> Dictionary:
	return Orders.fail("not_implemented")


static func step(_sim: Sim) -> void:
	pass
