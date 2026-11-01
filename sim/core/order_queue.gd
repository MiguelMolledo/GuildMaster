class_name OrderQueue
extends RefCounted
## Active pause (GDD 4.1): orders given while paused wait in the actor's order_queue and start in order.
## Owner: subgrim «edificio». Contract: docs/contratos/h2_forja.md.
##
## Sim.step pushes the orders marked "queued" (Game.give in pause); an order given live clears the actor's queue.
## step(): an actor that is free (no path, no job of its own at a station) takes the first order of its queue and
## applies it; a refused one gives order_refused and the next one is tried in the same minute.
## A job counts as finished at the end of its cycle when there are orders waiting: Production does not repeat it
## (has_pending). A walking enter_building stays first in the queue until Buildings.step lets the actor in.


static func push(sim: Sim, o: Dictionary) -> void:
	var actor := str(o.get("actor", ""))
	if sim.state.characters.has(actor):
		var clean := o.duplicate(true)
		clean.erase("queued")
		var queue: Array = sim.state.characters[actor].get("order_queue", [])
		queue.append(clean)
		sim.state.characters[actor]["order_queue"] = queue
		sim.events.append({"type": "order_queued", "actor": actor, "order": clean.duplicate(true)})
		if OS.is_debug_build():
			print("[OrderQueue] %s encola %s (en cola=%d)" % [actor, str(clean.get("type", "")), queue.size()])


static func clear_for(sim: Sim, actor: String) -> void:
	if sim.state.characters.has(actor):
		sim.state.characters[actor]["order_queue"] = []


## Whether the actor has orders waiting (Production: do not repeat the cycle).
static func has_pending(sim: Sim, actor: String) -> bool:
	return not (sim.state.characters.get(actor, {}).get("order_queue", []) as Array).is_empty()


## Free = not walking and no job of its own in its cycle at a station. A job whose cycle ended but whose output
## waits for room (blocked, "result" set) counts as finished: the queue goes on (exit/stop give the goods back).
static func is_free(sim: Sim, actor: String) -> bool:
	var ch: Dictionary = sim.state.characters.get(actor, {})
	if ch.is_empty() or not (ch.get("path", []) as Array).is_empty():
		return false
	var zone := Buildings.job_zone(sim, actor)
	if zone == "":
		return true
	var job: Dictionary = sim.state.buildings[str(ch["location"])]["zones"][zone]["job"]
	return job.get("result") is Dictionary


static func step(sim: Sim) -> void:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		var ch: Dictionary = sim.state.characters[id]
		var queue: Array = ch.get("order_queue", [])
		while not queue.is_empty() and is_free(sim, id):
			var o: Dictionary = queue.pop_front()
			o.erase("walking")
			sim.events.append({"type": "order_started", "actor": id, "order": o.duplicate(true)})
			var r := Orders.apply(sim, o)
			if OS.is_debug_build():
				print("[OrderQueue] %s empieza %s (ok=%s, quedan=%d)" % [id, str(o.get("type", "")), r["ok"], queue.size()])
			if not r["ok"]:
				sim.events.append({"type": "order_refused", "order": str(o.get("type", "")), "actor": id,
					"reason": r["reason"]})
			queue = ch.get("order_queue", [])
