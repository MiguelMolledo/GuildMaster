class_name Upkeep
extends RefCounted
## Daily upkeep of buildings (D12, GDD 4.19): charged at dawn to the owner family (category upkeep). Unpaid upkeep
## accumulates as debt with the town (building.upkeep_debt), is charged as soon as there is gold, and after 3 days
## unpaid the building becomes damaged (D15 = b, provisional). Owner: subgrim «cuentas».
## Contract: docs/contratos/h3_mercado.md.


static func step(_sim: Sim) -> void:
	pass
