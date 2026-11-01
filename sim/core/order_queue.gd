class_name OrderQueue
extends RefCounted
## Active pause (GDD 4.1): orders given while paused wait in the actor's order_queue and start in order.
## Owner: subgrim «edificio». Contract: docs/contratos/h2_forja.md. Stub until implemented.


static func push(sim: Sim, o: Dictionary) -> void:
	var actor := str(o.get("actor", ""))
	if sim.state.characters.has(actor):
		var clean := o.duplicate(true)
		clean.erase("queued")
		(sim.state.characters[actor]["order_queue"] as Array).append(clean)


static func clear_for(sim: Sim, actor: String) -> void:
	if sim.state.characters.has(actor):
		sim.state.characters[actor]["order_queue"] = []


static func step(_sim: Sim) -> void:
	pass
