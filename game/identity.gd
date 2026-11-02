class_name Identity
extends RefCounted
## Visual identity of a person (GDD 4.10.9): hair and skin from the palette swap (indices in the state, colours in
## data/view.json "palette"), the clothes in the family's colours. Presentation only: the walker figure, the portraits
## and their border read it; no rule does.


static func hair_color(index: int) -> Color:
	var pal: Array = ViewConfig.value("palette", {}).get("hair", ["#5a3a22"])
	return ViewConfig.color(str(pal[clampi(index, 0, pal.size() - 1)]))


static func skin_color(index: int) -> Color:
	var pal: Array = ViewConfig.value("palette", {}).get("skin", ["#e0b48c"])
	return ViewConfig.color(str(pal[clampi(index, 0, pal.size() - 1)]))


## {hair, skin, primary, secondary, female, dead} of a character from the state.
static func of(state: WorldState, chr: String) -> Dictionary:
	var ch: Dictionary = state.characters.get(chr, {})
	var fam: Dictionary = state.families.get(str(ch.get("family", "")), {})
	var colors: Dictionary = fam.get("colors", {})
	var vis: Dictionary = ch.get("visual", {}) if ch.get("visual") is Dictionary else {}
	return {"hair": hair_color(int(vis.get("hair", 0))), "skin": skin_color(int(vis.get("skin", 0))),
		"primary": ViewConfig.color(str(colors.get("primary", "#808080"))),
		"secondary": ViewConfig.color(str(colors.get("secondary", "#c0c0c0"))),
		"female": bool(ch.get("female", false)), "dead": not bool(ch.get("alive", true))}
