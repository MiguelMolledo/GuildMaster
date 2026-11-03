class_name Population
extends RefCounted
## Renewal of the town's population (the gap H8 found: the townsfolk grow old without children; a generation later
## there are no couples left). The simplest thing that keeps 15-20 townsfolk (GDD 4.11.1) [provisional]:
##   - at dawn single townsfolk marry (a man and a woman of different houses, adults of marriage_min_age, she young
##     enough to have children) with marriage_chance while more than min_singles singles are left (the player's
##     courtship candidates); the wife moves to the husband's house and family (Courtship.marry);
##   - children come through Births (H8) only while the town has fewer than max_total townsfolk (Births asks
##     room_for_child); they are born in their house and at majority age become apprentices with a trade;
##   - at year_changed, with fewer than min_adults adults, newcomers (newcomer_age, apprentices, alternating sex)
##     move into the house with fewest people.
## Contract: docs/contratos/h7_ciudad.md. Figures: data/town.json "population", data/family.json "children", "names";
## población: names and looks of the newcomers come from Cast.newcomer (data/cast.json in a generated cast).


## Once per minute, after Lifecycle (deaths and birthdays happen first at year_changed).
static func step(sim: Sim) -> void:
	var year_change := false
	var dawn := false
	for e: Dictionary in sim.events:
		match str(e.get("type", "")):
			"year_changed":
				year_change = true
			"phase_changed":
				dawn = dawn or str(e.get("phase", "")) == "dawn"
	if year_change:
		_come_of_age(sim)
		_newcomers(sim)
	if dawn:
		_weddings(sim)


## The living townsfolk (children included).
static func townsfolk(st: WorldState) -> Array:
	var out: Array = []
	for id: Variant in st.characters:
		if TownLife.is_townsperson(st, str(id)):
			out.append(str(id))
	out.sort()
	return out


## Whether a household couple may have a child: the town has fewer than max_total townsfolk.
static func room_for_child(sim: Sim) -> bool:
	return townsfolk(sim.state).size() < int(sim.catalog.town.get("population", {}).get("max_total", 20))


## The single adult townsfolk (no spouse alive).
static func singles(sim: Sim) -> Array:
	var out: Array = []
	for id: String in townsfolk(sim.state):
		if TownLife.is_adult(sim.state, sim.catalog, id) and Kin.is_single(sim.state, id):
			out.append(id)
	return out


## Townsfolk turning majority age become apprentices (a trade rank) with a trade; TownLife hands out the workplace.
static func _come_of_age(sim: Sim) -> void:
	var cfg: Dictionary = sim.catalog.town.get("population", {})
	for id: String in townsfolk(sim.state):
		var ch: Dictionary = sim.state.characters[id]
		if str(ch.get("rank", "")) == "" and TownLife.is_adult(sim.state, sim.catalog, id):
			ch["rank"] = str(cfg.get("newcomer_rank", "apprentice"))
			if str(ch.get("profession", "")) == "":
				ch["profession"] = "blacksmith"
			if OS.is_debug_build():
				print("[Population] %s «%s» es mayor de edad: aprendiz" % [id, ch.get("name", "")])
	TownLife.assign_occupations(sim.state, sim.catalog)


static func _weddings(sim: Sim) -> void:
	var st := sim.state
	var cfg: Dictionary = sim.catalog.town.get("population", {})
	var today := Clock.day(int(st.clock["minute"]))
	var free := singles(sim)
	if free.size() - 2 < int(cfg.get("min_singles", 6)):
		return
	if Kin.roll(st, "pop|wed|%d" % today) >= float(cfg.get("marriage_chance", 0.05)):
		return
	var min_age := int(cfg.get("marriage_min_age", 18))
	var max_mother := int(sim.catalog.family.get("children", {}).get("mother_max_age", 45)) - 5
	var women: Array = []
	var men: Array = []
	for id: String in free:
		var age := Kin.age(sim, id)
		if age < min_age:
			continue
		if bool(st.characters[id].get("female", false)):
			if age <= max_mother:
				women.append(id)
		else:
			men.append(id)
	if women.is_empty() or men.is_empty():
		return
	var bride: String = women[Kin.randi_range(st, "pop|bride|%d" % today, 0, women.size() - 1)]
	var groom := ""
	var gap := 1000
	for m: String in men:
		if str(st.characters[m].get("home", "")) == str(st.characters[bride].get("home", "")):
			continue
		var d := absi(Kin.age(sim, m) - Kin.age(sim, bride))
		if d < gap:
			gap = d
			groom = m
	if groom == "":
		return
	var house := str(st.characters[groom].get("home", ""))
	Courtship.marry(sim, groom, bride)
	var b: Dictionary = st.characters[bride]
	b["home"] = house
	b["controlled_by"] = "ai"
	sim.events.append({"type": "townsfolk_married", "husband": groom, "wife": bride, "house": house})
	if OS.is_debug_build():
		print("[Population] boda en el pueblo: %s y %s (casa %s)" % [groom, bride, house])


## Newcomers when the town is short of adults: young apprentices into the house with fewest people.
static func _newcomers(sim: Sim) -> void:
	var st := sim.state
	var cfg: Dictionary = sim.catalog.town.get("population", {})
	var adults := 0
	for id: String in townsfolk(st):
		if TownLife.is_adult(st, sim.catalog, id):
			adults += 1
	var want := int(cfg.get("min_adults", 14)) - adults
	var today := Clock.day(int(st.clock["minute"]))
	for i: int in want:
		var house := _emptiest_house(sim, int(cfg.get("house_capacity", 5)))
		if house == "":
			return
		_arrive(sim, house, today, i)


## The house (owned by a household family) with fewest living residents under `cap` ("" if all are full).
static func _emptiest_house(sim: Sim, cap: int) -> String:
	var st := sim.state
	var count := {}
	var ids: Array = st.buildings.keys()
	ids.sort()
	for b: String in ids:
		if str(st.buildings[b].get("type", "")) == "house" and TownLife.is_household(st, str(st.buildings[b].get("owner", ""))):
			count[b] = 0
	for id: String in townsfolk(st):
		var h := str(st.characters[id].get("home", ""))
		if count.has(h):
			count[h] = int(count[h]) + 1
	var best := ""
	for b: String in ids:
		if count.has(b) and int(count[b]) < cap and (best == "" or int(count[b]) < int(count[best])):
			best = b
	return best


static func _arrive(sim: Sim, house: String, today: int, n: int) -> String:
	var st := sim.state
	var cfg: Dictionary = sim.catalog.town.get("population", {})
	var fam := str(st.buildings[house].get("owner", ""))
	var key := "pop|new|%d|%d" % [today, n]
	var men := 0
	var women := 0
	for id: String in townsfolk(st):
		if TownLife.is_adult(st, sim.catalog, id):
			if bool(st.characters[id].get("female", false)):
				women += 1
			else:
				men += 1
	var female := women < men or (women == men and Kin.roll(st, key + "|sex") < 0.5)
	var nc := Cast.newcomer(sim, key, female)  # población: name and look from the game's cast
	var name := str(nc["name"])
	var span: Array = cfg.get("newcomer_age", [18, 24])
	var age := Kin.randi_range(st, key + "|age", int(span[0]), int(span[1]))
	var stats := {}
	for k: String in ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial", "constitution",
			"rhetoric", "stealth"]:
		stats[k] = Kin.randi_range(st, key + "|" + k, 2, 7)
	var door: Array = st.buildings[house].get("door", [0, 0])
	var id := Ids.next(st, "chr")
	st.characters[id] = {"id": id, "name": name, "female": female, "family": fam, "controlled_by": "ai", "alive": true,
		"position": [int(door[0]), int(door[1])], "path": [], "move_progress": 0, "stats": stats,
		"inventory": Inventory.create("weight", float(sim.catalog.family.get("life", {}).get("adult_carry_weight", 30.0))),
		"equipment": {"tool": null, "clothes": null, "accessory": null}, "location": house, "station": "",
		"order_queue": [], "home": house, "rank": str(cfg.get("newcomer_rank", "apprentice")), "job": null,
		"hire_bans": {}, "routine": {}, "occupation": "", "town": {}}
	st.characters[id].merge(Kin.character_fields(Kin.birth_day_for(age, int(st.clock["minute"]), sim.catalog.time),
		"artisan", "blacksmith", int(nc["hair"]), int(nc["skin"]),
		sim.catalog.family.get("directives", {}).get("default", ["work"])))
	st.characters[id]["visual"]["portrait"] = nc["portrait"]
	(st.families[fam]["members"] as Array).append(id)
	if Kin.head(st, fam) == "":
		st.families[fam]["head"] = id
	TownLife.assign_occupations(st, sim.catalog)
	sim.events.append({"type": "newcomer_arrived", "character": id, "house": house, "family": fam})
	if OS.is_debug_build():
		print("[Population] llega al pueblo %s «%s» (%d años, %s) a %s" % [id, name, age, "mujer" if female else "hombre",
			house])
	return id
