extends Node
## Hands the events of each sim step to the game layer (GDD 05 §5.6). Views listen here; they never call the sim.

signal sim_event(event: Dictionary)
signal step_done(events: Array)


func publish(events: Array) -> void:
	for e: Dictionary in events:
		sim_event.emit(e)
	step_done.emit(events)
