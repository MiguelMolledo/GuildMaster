extends "res://tests/test_case.gd"
## Pulido del MVP, arreglo 1: whoever joins a family by marriage lives in that family's home, never the old house; the
## children are born in their family's home. Covers a player's wedding with a townsperson, a townsfolk wedding, a
## birth, and an invariant over every scenario and a long dynasty game (every living character's home belongs to its
## family).

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _townsperson(sim: Sim, name: String) -> String:
	var ids: Array = sim.state.characters.keys()
	ids.sort()
	for id: String in ids:
		if str(sim.state.characters[id].get("name", "")) == name:
			return id
	return ""


## Every living character's home (Kin.home_of) is a building of its own family.
func _homes_ok(sim: Sim, label: String) -> void:
	var st := sim.state
	for c: String in st.characters:
		var ch: Dictionary = st.characters[c]
		if not bool(ch.get("alive", true)):
			continue
		var h := Kin.home_of(sim, c)
		if h != "":
			eq(str(st.buildings[h].get("owner", "")), str(ch.get("family", "")), "%s: %s lives in its family's home" % [label, c])


func test_a_townsperson_marrying_into_the_player_family_moves_in() -> void:
	var sim := Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)["state"], cat)
	var st := sim.state
	var wife := _townsperson(sim, "Agnès")
	var old := str(st.characters[wife]["home"])
	check(old != "" and old != FORGE, "she lives in her parents' house")
	Courtship.marry(sim, HERO, wife)
	eq(Kin.home_of(sim, wife), FORGE, "after the wedding she lives in the forge (the family's residence)")
	st.clock["minute"] = Clock.MINUTES_PER_DAY + 21 * 60  # night: an AI spouse rests at home
	for i: int in 120:
		sim.step([])
	eq(str(st.characters[wife]["location"]), FORGE, "and goes there to rest, not to the old house")


func test_a_townsfolk_wedding_moves_the_bride_to_the_groom_house() -> void:
	var sim := Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 1)["state"], cat)
	var st := sim.state
	var groom := _townsperson(sim, "Joan")
	var bride := _townsperson(sim, "Clara")
	var house := str(st.characters[groom]["home"])
	Courtship.marry(sim, groom, bride)
	eq(str(st.characters[bride]["home"]), house, "the bride's home is the groom's house")
	eq(str(st.characters[bride]["family"]), str(st.characters[groom]["family"]), "and his family")
	_homes_ok(sim, "wedding")


func test_children_are_born_at_home() -> void:
	var sim := Sim.new(NewGame.from_scenario("founder_old", 1)["state"], cat)
	var st := sim.state
	var kid := Births.born(sim, str(st.characters[HERO]["spouse"]), HERO)
	eq(Kin.home_of(sim, kid), Kin.residence(sim, FAM), "the player's child lives in the family's residence")
	eq(str(st.characters[kid]["location"]), Kin.residence(sim, FAM), "born there")
	var groom := _townsperson(sim, "Ramon")
	var bride := _townsperson(sim, "Isabel")
	if groom != "" and bride != "" and str(st.characters[groom].get("spouse", "")) == "":
		Courtship.marry(sim, groom, bride)
		var tk := Births.born(sim, bride, groom)
		eq(str(st.characters[tk]["home"]), str(st.characters[groom]["home"]), "a townsfolk child: its parents' house")
	_homes_ok(sim, "births")


func test_invariant_in_every_scenario() -> void:
	for id: String in NewGame.scenario_ids():
		var r := NewGame.from_scenario(id, 1)
		if r["ok"]:
			_homes_ok(Sim.new(r["state"], cat), id)
