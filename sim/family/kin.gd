class_name Kin
extends RefCounted
## Who is who in a family (GDD 4.10, H8): ages, the residence and the workplace of a family, the controllable group,
## descendants and the valid heir. Pure queries over the state (plus the v7 shape of a new character and family).
## Contract: docs/contratos/h8_familia.md. Figures: data/family.json (Catalog.family).
##
## Family events draw from their own deterministic stream (roll/randi_range): a RandomNumberGenerator seeded with the
## world seed and a key (system, day, people), so a birth or a death does not move the draws of the economy (and the
## H3-H5 targets stay where they were) and the same game gives the same family.


## The v7 fields of a new character (NewGame, births). `birth_day` in days (negative before the game starts).
static func character_fields(birth_day: int, char_class: String, profession: String, hair: int, skin: int,
		directives: Array) -> Dictionary:
	return {"birth_day": birth_day, "death_day": -1, "class": char_class, "profession": profession, "spouse": "",
		"parents": [], "children": [], "assigned": "", "directives": directives.duplicate(), "schedule": null,
		"visual": {"hair": hair, "skin": skin}, "life": {}}


## The v7 fields of a new family (NewGame): its head and founder (the first member), generation 1.
static func family_fields(head: String, fam_class: String) -> Dictionary:
	return {"head": head, "heir": "", "founder": head, "generation": 1, "regent": "", "class": fam_class,
		"goals_done": []}


## The birth day of someone `age` years old at `minute`, born at the start of a calendar year (ages change together).
static func birth_day_for(age: int, minute: int, time: Dictionary) -> int:
	var dpy := Clock.days_per_year(time)
	return (floori(float(Clock.day(minute)) / dpy) - age) * dpy


static func age(sim: Sim, chr: String) -> int:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	if ch.is_empty():
		return 0
	var at := int(sim.state.clock["minute"])
	if not bool(ch.get("alive", true)) and int(ch.get("death_day", -1)) >= 0:
		at = int(ch["death_day"]) * Clock.MINUTES_PER_DAY
	return Clock.age_years(int(ch.get("birth_day", 0)), at, sim.catalog.time)


static func is_adult(sim: Sim, chr: String) -> bool:
	return age(sim, chr) >= int(sim.catalog.family.get("life", {}).get("majority_age", 16))


static func alive(st: WorldState, chr: String) -> bool:
	return st.characters.has(chr) and bool(st.characters[chr].get("alive", true))


## Single = alive with no living spouse.
static func is_single(st: WorldState, chr: String) -> bool:
	if not alive(st, chr):
		return false
	var sp := str(st.characters[chr].get("spouse", ""))
	return sp == "" or not alive(st, sp)


## The family's head ("" if none or dead).
static func head(st: WorldState, fam: String) -> String:
	var h := str(st.families.get(fam, {}).get("head", ""))
	return h if alive(st, h) else ""


## Where the family lives: its first building (by id) whose type includes housing (the forge, a house). "" if none.
static func residence(sim: Sim, fam: String) -> String:
	var best := ""  # the lowest id that qualifies (the first in id order), without sorting every building
	for b: String in sim.state.buildings:
		if best != "" and b > best:
			continue
		var bld: Dictionary = sim.state.buildings[b]
		if str(bld.get("owner", "")) == fam \
				and bool(sim.catalog.buildings().get(str(bld.get("type", "")), {}).get("includes_housing", false)):
			best = b
	return best


## Where the family works by default: its first building (by id) with craft stations. "" if none.
static func workplace(sim: Sim, fam: String) -> String:
	var best := ""  # the lowest id that qualifies, as residence()
	for b: String in sim.state.buildings:
		if best != "" and b > best:
			continue
		var bld: Dictionary = sim.state.buildings[b]
		if str(bld.get("owner", "")) == fam and not (bld.get("zones", {}) as Dictionary).is_empty():
			best = b
	return best


## The building a family member works at: the assigned one if the family still owns it, else the workplace.
static func assigned_building(sim: Sim, chr: String) -> String:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	var fam := str(ch.get("family", ""))
	var a := str(ch.get("assigned", ""))
	if a != "" and str(sim.state.buildings.get(a, {}).get("owner", "")) == fam:
		return a
	return workplace(sim, fam)


## The home of a character: its house (townsfolk) or its family's residence.
static func home_of(sim: Sim, chr: String) -> String:
	var ch: Dictionary = sim.state.characters.get(chr, {})
	var h := str(ch.get("home", ""))
	if h != "" and sim.state.buildings.has(h):
		return h
	return residence(sim, str(ch.get("family", "")))


## The controllable group (GDD 4.10.5): living members with controlled_by "human", the head (or the regent) first,
## then by age (oldest first), then id.
static func group(st: WorldState, fam: String) -> Array:
	var out: Array = []
	for m: Variant in st.families.get(fam, {}).get("members", []):
		var id := str(m)
		if alive(st, id) and str(st.characters[id].get("controlled_by", "")) == "human":
			out.append(id)
	var lead := head(st, fam)
	var regent := str(st.families.get(fam, {}).get("regent", ""))
	out.sort_custom(func(a: String, b: String) -> bool:
		var ka := 0 if a == regent else (1 if a == lead else 2)
		var kb := 0 if b == regent else (1 if b == lead else 2)
		if ka != kb:
			return ka < kb
		var ba := int(st.characters[a].get("birth_day", 0))
		var bb := int(st.characters[b].get("birth_day", 0))
		if ba != bb:
			return ba < bb
		return a < b)
	return out


## Every living descendant of `chr` (children, grandchildren...), oldest first then id.
static func descendants(st: WorldState, chr: String) -> Array:
	var out: Array = []
	var todo: Array = (st.characters.get(chr, {}).get("children", []) as Array).duplicate()
	var seen := {}
	while not todo.is_empty():
		var c := str(todo.pop_front())
		if seen.has(c) or not st.characters.has(c):
			continue
		seen[c] = true
		if alive(st, c):
			out.append(c)
		todo.append_array(st.characters[c].get("children", []))
	out.sort_custom(func(a: String, b: String) -> bool:
		var ba := int(st.characters[a].get("birth_day", 0))
		var bb := int(st.characters[b].get("birth_day", 0))
		return ba < bb if ba != bb else a < b)
	return out


## Whether `chr` may inherit from `from` (GDD 4.10.4): a living descendant of `from` in the same family, adult, or a
## minor if `from` leaves a living spouse (the regent until the heir comes of age).
static func can_inherit(sim: Sim, from: String, chr: String) -> bool:
	var st := sim.state
	if not chr in descendants(st, from):
		return false
	if str(st.characters[chr].get("family", "")) != str(st.characters.get(from, {}).get("family", "")):
		return false
	if is_adult(sim, chr):
		return true
	var sp := str(st.characters.get(from, {}).get("spouse", ""))
	return sp != "" and alive(st, sp)


## The heir of the family's head now: the designated one if valid, else the oldest valid descendant (adults first,
## GDD 4.10.4 "por defecto: el hijo mayor >= 16"). "" if there is none.
static func heir(sim: Sim, fam: String) -> String:
	var st := sim.state
	var h := str(st.families.get(fam, {}).get("head", ""))
	if not st.characters.has(h):
		return ""
	var designated := str(st.families[fam].get("heir", ""))
	if designated != "" and can_inherit(sim, h, designated):
		return designated
	var minors: Array = []
	for d: String in descendants(st, h):
		if not can_inherit(sim, h, d):
			continue
		if is_adult(sim, d):
			return d
		minors.append(d)
	return str(minors[0]) if not minors.is_empty() else ""


## The family's title (H9 brings it; until then the default of data/upgrade_rules.json).
static func title(sim: Sim, fam: String) -> String:
	return Upgrades.family_title(sim, fam)


## A float in [0, 1) from the family stream: same world seed + same key = same number.
static func roll(st: WorldState, key: String) -> float:
	return _rng(st, key).randf()


## An int in [from, to] from the family stream.
static func randi_range(st: WorldState, key: String, from: int, to: int) -> int:
	return _rng(st, key).randi_range(from, to)


static func _rng(st: WorldState, key: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = ("%d|%s" % [st.world_seed, key]).hash()
	return r


static func _sorted(d: Dictionary) -> Array:
	var ids: Array = d.keys()
	ids.sort()
	return ids
