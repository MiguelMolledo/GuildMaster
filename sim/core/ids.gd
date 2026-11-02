class_name Ids
extends RefCounted
## Stable, typed ids (GDD 05 §5.3): "<prefix>_<0001>". Never reused: the counters live in WorldState.next_ids and are saved.
## Prefixes in use: chr (character), fam (family), bld (building), par (parcel), trial; H7: mev (microevent).

static func next(state: WorldState, prefix: String) -> String:
	var n: int = int(state.next_ids.get(prefix, 1))
	state.next_ids[prefix] = n + 1
	return "%s_%04d" % [prefix, n]


## The key of a pair of characters in WorldState.relationships: both ids sorted as String, joined by "|".
static func pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
