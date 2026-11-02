class_name Lifecycle
extends RefCounted
## Life cycle, death and succession (GDD 4.2.5, 4.10.4, 4.17). Everybody turns a year older together at year_changed:
## the school at 8 (+1 to a stat: the player chooses with school_choice; AI families take ai_school_stat), the trade at
## 12 (the family's), coming of age at 16 (joins the controllable group if there is room, an inventory of its own, the
## default routine), the decline of data/family.json life.decline and, from death.from_age, the yearly death roll
## (p = base × growth^(age − from_age) × (1 − (constitution − 5) × constitution_step); certain at certain_age).
## A death of the family's head passes the family on to its heir (Kin.heir): the family keeps its gold, buildings
## (with their upgrades and employees), loans and title; the heir gets the dead's inventory and equipment, becomes the
## head and joins the group; a minor heir is managed by the surviving spouse (regent) until 16. Without a valid heir
## the human family's game ends (state.ending kind "game_over", with the dynasty score); an AI family dies out.
## Orders: designate_heir, school_choice, assign_building, close_dynasty (D19: off by data).
## Contract: docs/contratos/h8_familia.md.


## Once per minute, after Buildings (before Staff): on year_changed, birthdays then deaths, in order of id.
static func step(sim: Sim) -> void:
	var year_change := false
	for e: Dictionary in sim.events:
		if str(e["type"]) == "year_changed":
			year_change = true
	if not year_change:
		return
	var st := sim.state
	var ids: Array = st.characters.keys()
	ids.sort()
	for id: String in ids:
		if Kin.alive(st, id):
			_birthday(sim, id)
	for id: String in ids:
		if Kin.alive(st, id) and _death_roll(sim, id):
			die(sim, id, "old_age")


static func _birthday(sim: Sim, chr: String) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	var life: Dictionary = sim.catalog.family.get("life", {})
	var age := Kin.age(sim, chr)
	var fam := str(ch.get("family", ""))
	var human := str(st.families.get(fam, {}).get("controlled_by", "")) == "human"
	if not ch.get("life") is Dictionary:
		ch["life"] = {}
	if age == int(life.get("school_age", 8)):
		if human:
			ch["life"]["school"] = "pending"
			Notices.add(sim, fam, "info", "notice.school_choice", {"name": str(ch.get("name", ""))}, chr)
		else:
			_add_stat(sim, chr, str(life.get("ai_school_stat", "craft")), 1)
			ch["life"]["school"] = str(life.get("ai_school_stat", "craft"))
	if age == int(life.get("apprentice_age", 12)) and str(ch.get("profession", "")) == "":
		var h := Kin.head(st, fam)
		ch["profession"] = str(st.characters.get(h, {}).get("profession", "")) if h != "" else ""
		ch["assigned"] = Kin.workplace(sim, fam)
		if human:
			Notices.add(sim, fam, "info", "notice.apprentice", {"name": str(ch.get("name", "")),
				"profession": str(ch["profession"])}, chr)
	if age == int(life.get("majority_age", 16)):
		come_of_age(sim, chr)
	for d: Dictionary in life.get("decline", []):
		if int(d.get("age", -1)) == age:
			for k: String in d.get("stats", {}):
				_add_stat(sim, chr, k, int(d["stats"][k]))
	sim.events.append({"type": "birthday", "character": chr, "family": fam, "age": age})


## Coming of age (16): its own inventory; in the human family it joins the group if there is room (with the default
## routine). The minor heir's regent hands over.
static func come_of_age(sim: Sim, chr: String) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	var fam := str(ch.get("family", ""))
	var f: Dictionary = st.families.get(fam, {})
	ch["inventory"]["limit"] = float(sim.catalog.family.get("life", {}).get("adult_carry_weight", 30.0))
	if str(f.get("controlled_by", "")) != "human":
		return
	if str(f.get("regent", "")) != "" and str(f.get("head", "")) == chr:
		var reg := str(f["regent"])
		f["regent"] = ""
		if Kin.alive(st, reg):
			st.characters[reg]["controlled_by"] = "ai"
			st.characters[reg]["schedule"] = null
		sim.events.append({"type": "regency_ended", "family": fam, "regent": reg, "heir": chr})
	join_group(sim, chr)
	Notices.add(sim, fam, "info", "notice.came_of_age", {"name": str(ch.get("name", ""))}, chr)


## Puts `chr` (an adult of the human family) in the controllable group if there is room. True if it is in it.
static func join_group(sim: Sim, chr: String) -> bool:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	if str(ch.get("controlled_by", "")) == "human":
		return true
	var fam := str(ch.get("family", ""))
	if Kin.group(st, fam).size() >= int(sim.catalog.family.get("group", {}).get("max", 3)):
		return false
	ch["controlled_by"] = "human"
	if ch.get("schedule") == null:
		ch["schedule"] = Schedules.default_schedule(sim, chr)
	sim.events.append({"type": "group_changed", "family": fam, "character": chr, "joined": true})
	if OS.is_debug_build():
		print("[Lifecycle] %s entra en el grupo controlable de %s" % [chr, fam])
	return true


static func _add_stat(sim: Sim, chr: String, stat: String, amount: int) -> void:
	var stats: Dictionary = sim.state.characters[chr].get("stats", {})
	if not stats.has(stat):
		return
	var life: Dictionary = sim.catalog.family.get("life", {})
	stats[stat] = clampi(int(stats[stat]) + amount, int(life.get("stat_min", 1)), int(life.get("stat_max", 10)))


## The yearly death probability of `chr` now (0 before death.from_age).
static func death_chance(sim: Sim, chr: String) -> float:
	var d: Dictionary = sim.catalog.family.get("life", {}).get("death", {})
	var age := Kin.age(sim, chr)
	if age < int(d.get("from_age", 55)):
		return 0.0
	if age >= int(d.get("certain_age", 75)):
		return 1.0
	var con := int(sim.state.characters[chr].get("stats", {}).get("constitution", 5))
	var p := float(d.get("base", 0.02)) * pow(float(d.get("growth", 1.25)), age - int(d.get("from_age", 55))) \
		* (1.0 - (con - 5) * float(d.get("constitution_step", 0.05)))
	return clampf(p, 0.0, 1.0)


static func _death_roll(sim: Sim, chr: String) -> bool:
	var p := death_chance(sim, chr)
	if p <= 0.0:
		return false
	return Kin.roll(sim.state, "death|%d|%s" % [Clock.day(int(sim.state.clock["minute"])), chr]) < p


## `chr` dies now: out of the map and of any job or station, the spouse is widowed, chronicle "death". If it was the
## head of its family, the succession (or the end).
static func die(sim: Sim, chr: String, cause: String) -> void:
	var st := sim.state
	var ch: Dictionary = st.characters[chr]
	var fam := str(ch.get("family", ""))
	var age := Kin.age(sim, chr)
	var loc := str(ch.get("location", ""))
	if loc != "":
		var zone := Production.job_zone(sim, chr, loc)
		if zone != "":
			Production.interrupt(sim, loc, zone)
		var station := str(ch.get("station", ""))
		var zones: Dictionary = st.buildings.get(loc, {}).get("zones", {})
		if zones.has(station) and str(zones[station].get("occupant", "")) == chr:
			zones[station]["occupant"] = ""
	ch["alive"] = false
	ch["death_day"] = Clock.day(int(st.clock["minute"]))
	ch["path"] = []
	ch["order_queue"] = []
	ch["station"] = ""
	ch["location"] = ""
	if ch.get("job") is Dictionary:
		var bld := str(ch["job"].get("building", ""))
		ch["job"] = null
		sim.events.append({"type": "employee_left", "family": str(st.buildings.get(bld, {}).get("owner", "")),
			"building": bld, "employee": chr, "reason": "died"})
	var was_controlled := str(ch.get("controlled_by", "")) == "human"
	ch["controlled_by"] = "ai"
	var sp := str(ch.get("spouse", ""))
	if sp != "" and Kin.alive(st, sp):
		var s: Dictionary = st.characters[sp]
		s["spouse"] = ""
		if not s.get("life") is Dictionary:
			s["life"] = {}
		var former: Array = s["life"].get("former_spouses", [])
		former.append(chr)
		s["life"]["former_spouses"] = former
	Chronicle.add(st, "death", {"family": fam, "character": chr, "age": age, "cause": cause})
	sim.events.append({"type": "character_died", "family": fam, "character": chr, "age": age, "cause": cause})
	if OS.is_debug_build():
		print("[Lifecycle] muere %s «%s» (%s, %d años, causa=%s)" % [chr, ch.get("name", ""), fam, age, cause])
	var f: Dictionary = st.families.get(fam, {})
	if f.is_empty():
		return
	if str(f.get("controlled_by", "")) == "human":
		Notices.add(sim, fam, "urgent", "notice.death", {"name": str(ch.get("name", "")), "age": age}, chr)
	if str(f.get("regent", "")) == chr:
		f["regent"] = ""
	if str(f.get("head", "")) == chr:
		succeed(sim, fam, chr)
	elif was_controlled:
		_refill_group(sim, fam)


## The family passes from the dead head `from` to its heir (Kin.heir, computed as if `from` were alive), or ends.
static func succeed(sim: Sim, fam: String, from: String) -> void:
	var st := sim.state
	var f: Dictionary = st.families[fam]
	var heir := _heir_of(sim, fam, from)
	if heir == "":
		_no_heir(sim, fam, from)
		return
	var h: Dictionary = st.characters[heir]
	var dead: Dictionary = st.characters[from]
	# The dead's inventory and equipment: to the heir, what does not fit to the family residence, the rest is lost.
	var home := Kin.residence(sim, fam)
	for s: Dictionary in (dead.get("inventory", {}).get("stacks", []) as Array).duplicate():
		_bequeath(sim, heir, home, str(s["item"]), int(s["quality"]), int(s["qty"]))
	dead["inventory"]["stacks"] = []
	for slot: String in dead.get("equipment", {}):
		var it: Variant = dead["equipment"][slot]
		if it is Dictionary:
			_bequeath(sim, heir, home, str(it["item"]), int(it.get("quality", 0)), 1)
			dead["equipment"][slot] = null
	f["head"] = heir
	f["heir"] = ""
	f["generation"] = int(f.get("generation", 1)) + 1
	var human := str(f.get("controlled_by", "")) == "human"
	var regent := ""
	if not Kin.is_adult(sim, heir):
		regent = str(dead.get("spouse", ""))
		f["regent"] = regent
		if human and Kin.alive(st, regent):
			st.characters[regent]["controlled_by"] = "ai"
			join_group(sim, regent)
	elif human:
		if not join_group(sim, heir):  # the group is full: the heir takes the place of the youngest adult
			var g := Kin.group(st, fam)
			var last := str(g[g.size() - 1])
			st.characters[last]["controlled_by"] = "ai"
			join_group(sim, heir)
	Chronicle.add(st, "inheritance", {"family": fam, "from": from, "heir": heir, "generation": int(f["generation"]),
		"regent": regent})
	sim.events.append({"type": "inheritance", "family": fam, "from": from, "heir": heir,
		"generation": int(f["generation"]), "regent": regent})
	if human:
		Notices.add(sim, fam, "urgent", "notice.inheritance", {"name": str(h.get("name", "")),
			"generation": int(f["generation"])}, heir)
	if OS.is_debug_build():
		print("[Lifecycle] herencia en %s: %s -> %s (generación %d, regente=%s, oro=%d)" % [fam, from, heir,
			int(f["generation"]), regent, Money.gold(st, fam)])
	Dynasty.check_goals(sim, fam)


## The heir of a head that has just died: Kin.heir with the head still recorded, but its spouse counted as it was.
static func _heir_of(sim: Sim, fam: String, from: String) -> String:
	var st := sim.state
	var dead: Dictionary = st.characters[from]
	var sp := str(dead.get("spouse", ""))
	var designated := str(st.families[fam].get("heir", ""))
	if designated != "" and _can_inherit_dead(sim, from, designated, sp):
		return designated
	var minors: Array = []
	for d: String in Kin.descendants(st, from):
		if not _can_inherit_dead(sim, from, d, sp):
			continue
		if Kin.is_adult(sim, d):
			return d
		minors.append(d)
	return str(minors[0]) if not minors.is_empty() else ""


static func _can_inherit_dead(sim: Sim, from: String, chr: String, spouse: String) -> bool:
	var st := sim.state
	if not chr in Kin.descendants(st, from) or str(st.characters[chr].get("family", "")) != str(st.characters[from].get("family", "")):
		return false
	return Kin.is_adult(sim, chr) or (spouse != "" and Kin.alive(st, spouse))


static func _bequeath(sim: Sim, heir: String, home: String, item: String, q: int, qty: int) -> void:
	var inv: Dictionary = sim.state.characters[heir].get("inventory", {})
	for i: int in qty:
		if Inventory.add(inv, sim.catalog, item, q, 1):
			continue
		if home != "" and Inventory.add(sim.state.buildings[home]["inventory"], sim.catalog, item, q, 1):
			continue
		if OS.is_debug_build():
			print("[Lifecycle] la herencia pierde %s q%d (no cabe)" % [item, q])


## No valid heir: the human family's game ends with the dynasty score (GDD 4.17); an AI family dies out.
static func _no_heir(sim: Sim, fam: String, from: String) -> void:
	var st := sim.state
	var f: Dictionary = st.families[fam]
	if TownLife.is_household(st, fam):
		# H7: a household goes on with its first living member (the housemate); it only dies out when nobody is left.
		for m: Variant in f.get("members", []):
			if Kin.alive(st, str(m)):
				f["head"] = str(m)
				if OS.is_debug_build():
					print("[Lifecycle] el hogar %s sigue con %s" % [fam, m])
				return
	f["head"] = ""
	Chronicle.add(st, "extinct", {"family": fam, "last": from})
	sim.events.append({"type": "family_extinct", "family": fam, "last": from})
	if str(f.get("controlled_by", "")) == "human" and st.ending.is_empty():
		end_game(sim, fam, "game_over")
	if OS.is_debug_build():
		print("[Lifecycle] %s se queda sin heredero al morir %s" % [fam, from])


## The end of the game (GDD 4.17): state.ending with the dynasty summary and score; event game_over.
static func end_game(sim: Sim, fam: String, kind: String) -> void:
	var st := sim.state
	st.ending = {"kind": kind, "family": fam, "minute": int(st.clock["minute"]),
		"score": Dynasty.score(sim, fam)["total"]}
	sim.events.append({"type": "game_over", "kind": kind, "family": fam})
	if OS.is_debug_build():
		print("[Lifecycle] fin de la partida (%s) para %s: %s" % [kind, fam, Dynasty.score(sim, fam)])


## After a group member dies: the oldest adult blood member outside the group (not a spouse) takes the place.
static func _refill_group(sim: Sim, fam: String) -> void:
	var st := sim.state
	var h := Kin.head(st, fam)
	if h == "":
		return
	for d: String in Kin.descendants(st, h):
		if Kin.is_adult(sim, d) and str(st.characters[d].get("family", "")) == fam:
			if Kin.group(st, fam).size() >= int(sim.catalog.family.get("group", {}).get("max", 3)):
				return
			join_group(sim, d)


# --- Orders ----------------------------------------------------------------------------------------------------------

## {"type": "designate_heir", "actor", "heir"}: a member of the family names the head's heir (GDD 4.10.4, from the
## family tree). "" = back to the default rule.
static func order_designate_heir(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var heir := str(o.get("heir", ""))
	if not Kin.alive(st, actor):
		return Orders.fail("unknown_actor")
	var fam := str(st.characters[actor].get("family", ""))
	var h := Kin.head(st, fam)
	if h == "":
		return Orders.fail("no_head")
	if heir != "" and not Kin.can_inherit(sim, h, heir):
		return Orders.fail("not_an_heir")
	st.families[fam]["heir"] = heir
	sim.events.append({"type": "heir_designated", "family": fam, "heir": heir, "actor": actor})
	if OS.is_debug_build():
		print("[Lifecycle] %s designa heredero de %s a %s" % [actor, fam, heir])
	return Orders.ok()


## {"type": "school_choice", "actor", "child", "stat"}: +1 to a stat of a child of the family whose school choice is
## pending (GDD 4.2.5, age 8).
static func order_school_choice(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var child := str(o.get("child", ""))
	var stat := str(o.get("stat", ""))
	if not Kin.alive(st, actor):
		return Orders.fail("unknown_actor")
	if not Kin.alive(st, child) or str(st.characters[child].get("family", "")) != str(st.characters[actor].get("family", "")):
		return Orders.fail("not_family")
	if str(st.characters[child].get("life", {}).get("school", "")) != "pending":
		return Orders.fail("no_choice")
	if not (st.characters[child].get("stats", {}) as Dictionary).has(stat):
		return Orders.fail("unknown_stat")
	_add_stat(sim, child, stat, 1)
	st.characters[child]["life"]["school"] = stat
	sim.events.append({"type": "school_chosen", "character": child, "stat": stat})
	return Orders.ok()


## {"type": "assign_building", "actor", "character", "building"}: where a family member works (GDD 4.10.7); a
## building of the family, or "" for the default (its workplace).
static func order_assign_building(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var who := str(o.get("character", ""))
	var bld := str(o.get("building", ""))
	if not Kin.alive(st, actor):
		return Orders.fail("unknown_actor")
	var fam := str(st.characters[actor].get("family", ""))
	if not Kin.alive(st, who) or str(st.characters[who].get("family", "")) != fam:
		return Orders.fail("not_family")
	if bld != "" and str(st.buildings.get(bld, {}).get("owner", "")) != fam:
		return Orders.fail("not_your_building")
	st.characters[who]["assigned"] = bld
	sim.events.append({"type": "building_assigned", "character": who, "building": bld})
	return Orders.ok()


## {"type": "close_dynasty", "actor"}: the player ends the dynasty (GDD 4.17 voluntary close). D19 is pending: refused
## while data/family.json succession.voluntary_close is false.
static func order_close_dynasty(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	if not Kin.alive(st, actor):
		return Orders.fail("unknown_actor")
	if not bool(sim.catalog.family.get("succession", {}).get("voluntary_close", false)):
		return Orders.fail("disabled")
	var fam := str(st.characters[actor].get("family", ""))
	if str(st.families.get(fam, {}).get("controlled_by", "")) != "human" or not st.ending.is_empty():
		return Orders.fail("not_your_family")
	Chronicle.add(st, "dynasty_closed", {"family": fam, "by": actor})
	end_game(sim, fam, "closed")
	return Orders.ok()
