class_name BotIdle
extends RefCounted
## Bot that does nothing (GDD 07 §7.2): measures that the world keeps going on its own and nothing breaks.
## Every bot is an object with orders(sim) -> Array and gives the same orders as the UI.

const ID: String = "idle"


func orders(_sim: Sim) -> Array:
	return []
