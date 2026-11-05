class_name TutorialRules
extends RefCounted
## What the tutorial understands (docs/ui/05_tutorial.md §4): the UI events, the conditions on the state, the target
## shapes and the symbols. tools/validate_content.py reads UI_EVENTS, CONDITIONS, ZONES, WORLD_KINDS, SYMBOLS and
## PLACEHOLDERS from this file (keep one entry per line). The sim's event types are the ones the sim emits.
## A trigger is {"sim": type, "match", "count", "anyone"} · {"ui": type, "match", "count"} · {"state": name, args...}.
## Only reads: nothing here gives an order or changes the state.

const UI_EVENTS: Array[String] = [
	"panel_opened",
	"panel_closed",
	"order_given",
	"selected",
	"building_picked",
	"interior_opened",
	"interior_closed",
	"camera_moved",
	"zoom_changed",
	"paused",
	"resumed",
	"speed_changed",
	"help_opened",
	"chapter_started",
]

## condition -> the arguments it takes ("is" = the value it is compared with)
const CONDITIONS: Dictionary = {
	"paused": ["is"],
	"speed": ["is"],
	"selected": ["is"],
	"picked_building": ["is"],
	"interior": ["is"],
	"interior_type": ["is"],
	"panel_open": ["is", "tab", "stall", "zone", "mode", "building"],
	"panel_prop": ["panel", "prop", "value"],
	"node_visible": ["is", "in"],
	"camera_moved": ["px"],
	"storage_has": ["item", "qty", "building"],
	"carries": ["item", "qty"],
	"gold_gte": ["is"],
	"objective": ["is"],
	"objective_done": ["is"],
	"has_trial": ["is"],
	"event_active": ["is"],
	"profession": ["is"],
}

const ZONES: Array[String] = [
	"card",
	"status",
	"clock",
	"column",
	"manage",
	"selection",
	"notices",
	"view",
]

## world target kind -> the keys it can take (one of id / type, or at)
const WORLD_KINDS: Dictionary = {
	"building": ["id", "type"],
	"door": ["id", "type"],
	"character": ["id"],
	"station": ["id"],
	"service": ["id"],
	"tile": ["at"],
}

const SYMBOLS: Array[String] = [
	"$head",
	"$active",
	"$workshop",
	"$first_station",
	"$tavern",
]

## {name} in the texts
const PLACEHOLDERS: Array[String] = [
	"head",
	"active",
	"workshop",
	"town",
	"family",
]

## Properties of a panel that go with panel_opened (and that panel_open can ask for), if the panel has them.
const PANEL_PROPS: Array[String] = ["tab", "stall", "zone", "mode", "building"]


## "sim" | "ui" | "state" | "" (not a trigger).
static func kind(t: Variant) -> String:
	if not t is Dictionary:
		return ""
	var d: Dictionary = t
	for k: String in ["sim", "ui", "state"]:
		if d.has(k):
			return k
	return ""


## The triggers of a "done" (one or a list).
static func as_list(t: Variant) -> Array:
	if t is Array:
		return t
	if t is Dictionary:
		return [t]
	return []


## Whether event `data` of type `type` (from `source`: "sim" or "ui") is trigger `t`. `resolve` turns a "$symbol"
## into its value now (and leaves anything else as it is).
static func event_matches(t: Dictionary, source: String, type: String, data: Dictionary, resolve: Callable) -> bool:
	if kind(t) != source or str(t[source]) != type:
		return false
	return matches(data, t.get("match", {}) as Dictionary, resolve)


## Like the objectives' match (sim/meta/objectives.gd): every key of `m` is in `e` and equal (numbers as numbers),
## or within {gte, lte, ne}. String values that are symbols are resolved first.
static func matches(e: Dictionary, m: Dictionary, resolve: Callable = Callable()) -> bool:
	for k: String in m:
		if not e.has(k):
			return false
		var want: Variant = m[k]
		var got: Variant = e[k]
		if want is String and resolve.is_valid():
			want = resolve.call(want)
		if want is Dictionary:
			var w: Dictionary = want
			if w.has("gte") and not (_num(got) and float(got) >= float(w["gte"])):
				return false
			if w.has("lte") and not (_num(got) and float(got) <= float(w["lte"])):
				return false
			if w.has("ne") and same(got, w["ne"]):
				return false
		elif not same(got, want):
			return false
	return true


static func same(a: Variant, b: Variant) -> bool:
	if _num(a) and _num(b):
		return float(a) == float(b)
	if a is bool or b is bool:
		return typeof(a) == typeof(b) and a == b
	return str(a) == str(b)


static func _num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## A text with its {placeholders} filled (unknown ones are left as they are).
static func fill(text: String, args: Dictionary) -> String:
	return text.format(args)


## Whether node name `name` is `pattern` (an exact name or with * wildcards).
static func name_is(name: String, pattern: String) -> bool:
	if pattern.contains("*"):
		return name.match(pattern)
	return name == pattern
