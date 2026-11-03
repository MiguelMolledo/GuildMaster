class_name Identity
extends RefCounted
## Visual identity of a person (GDD 4.10.9): hair and skin from the palette swap (indices in the state, colours in
## data/view.json "palette"), the clothes in the family's colours and (población) the base portrait of its type, age
## and sex (data/cast.json portraits). Presentation only: the walker figure, the portraits and their border read it;
## no rule does.


static func hair_color(index: int) -> Color:
	var pal: Array = ViewConfig.value("palette", {}).get("hair", ["#5a3a22"])
	return ViewConfig.color(str(pal[clampi(index, 0, pal.size() - 1)]))


static func skin_color(index: int) -> Color:
	var pal: Array = ViewConfig.value("palette", {}).get("skin", ["#e0b48c"])
	return ViewConfig.color(str(pal[clampi(index, 0, pal.size() - 1)]))


## {hair, skin, primary, secondary, female, dead, portrait} of a character from the state. portrait (población):
## {type, stage, variant} of its base portrait; the stage comes from its age now (the portrait changes with age), the
## age of its death for the dead.
static func of(state: WorldState, chr: String) -> Dictionary:
	var ch: Dictionary = state.characters.get(chr, {})
	var fam: Dictionary = state.families.get(str(ch.get("family", "")), {})
	var colors: Dictionary = fam.get("colors", {})
	var vis: Dictionary = ch.get("visual", {}) if ch.get("visual") is Dictionary else {}
	var at := int(state.clock.get("minute", 0))
	if not bool(ch.get("alive", true)) and int(ch.get("death_day", -1)) >= 0:
		at = int(ch["death_day"]) * Clock.MINUTES_PER_DAY
	var pt: Dictionary = vis.get("portrait", {}) if vis.get("portrait") is Dictionary else {}
	var ptype := str(pt.get("type", "")) if not pt.is_empty() else _type_of(fam)
	return {"hair": hair_color(int(vis.get("hair", 0))), "skin": skin_color(int(vis.get("skin", 0))),
		"primary": ViewConfig.color(str(colors.get("primary", "#808080"))),
		"secondary": ViewConfig.color(str(colors.get("secondary", "#c0c0c0"))),
		"female": bool(ch.get("female", false)), "dead": not bool(ch.get("alive", true)),
		"portrait": {"type": ptype, "variant": int(pt.get("variant", str(chr).get_slice("_", 1).to_int())),
			"stage": stage(Clock.age_years(int(ch.get("birth_day", 0)), at, _time()))}}


## The portrait stage of `age` (data/cast.json portraits.stages: the first whose to_age >= age).
static func stage(age: int) -> String:
	var stages: Array = _cast().get("portraits", {}).get("stages", [])
	for s: Dictionary in stages:
		if age <= int(s.get("to_age", 0)):
			return str(s.get("id", "adult"))
	return str((stages.back() as Dictionary).get("id", "adult")) if not stages.is_empty() else "adult"


## The base portrait texture of an identity (Identity.of / a proposal of the new-game screen), null without art.
static func portrait_texture(id: Dictionary, size: int = 32) -> Texture2D:
	var pt: Dictionary = id.get("portrait", {}) if id.get("portrait") is Dictionary else {}
	if pt.is_empty():
		return null
	return VisualPaths.portrait(str(pt.get("type", "townsfolk")), str(pt.get("stage", "adult")),
		bool(id.get("female", false)), int(pt.get("variant", 0)), size)


static func _type_of(fam: Dictionary) -> String:
	if str(fam.get("controlled_by", "")) == "human":
		return str(fam.get("class", "artisan"))
	return "rival" if str(fam.get("ai_profile", "")) != "" else "townsfolk"


static var _cast_cfg: Dictionary = {}
static var _time_cfg: Dictionary = {}


static func _cast() -> Dictionary:
	if _cast_cfg.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cast.json"))
		_cast_cfg = d if d is Dictionary else {"_": true}
	return _cast_cfg


static func _time() -> Dictionary:
	if _time_cfg.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/time.json"))
		_time_cfg = d if d is Dictionary else {"_": true}
	return _time_cfg
