class_name RivalAI
extends RefCounted
## The rival smith's simple AI (GDD 4.5.5): plays like a bot, only through orders. Sim.step asks it every minute
## right after the orders from outside and before the clock ticks; it gives orders for the characters of the AI
## families with an ai_profile (data/ai_profiles/). Owner: subgrim «rival». Contract: docs/contratos/h3_mercado.md.


## The orders of this minute for every AI family with a profile (sorted by family id: deterministic).
static func orders(_sim: Sim) -> Array:
	return []
