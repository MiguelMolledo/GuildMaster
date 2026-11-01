class_name Chronicle
extends RefCounted
## The game's book of facts (GDD 04 §4.14): births, weddings, deaths, inheritances, titles, offices, trials, purchases,
## global events. Saved with the state from day one; the future AI chronicler and the dynasty score read it.

static func add(state: WorldState, kind: String, data: Dictionary = {}) -> void:
	var entry := {"minute": int(state.clock["minute"]), "kind": kind}
	entry.merge(data)
	state.chronicle.append(entry)
