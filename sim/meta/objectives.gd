class_name Objectives
extends RefCounted
## The start objectives (GDD 4.16): a chain per family, read from data/objectives/ (each one with its condition as
## data: event and parameters). Watches the events of the step; each one done goes to the notices log.
## Owner: subgrim «cuentas». Contract: docs/contratos/h3_mercado.md.


## Reads sim.events of this step (it runs after every system that emits) and advances the chains.
static func step(_sim: Sim) -> void:
	pass


## {} | {current: obj_id | "", done: [obj_id], progress: [{have, need}]} of `fam`, for the HUD.
static func view(_sim: Sim, _fam: String) -> Dictionary:
	return {}
