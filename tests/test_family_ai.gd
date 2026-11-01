extends "res://tests/test_case.gd"
## H8 family module of the AI families (GDD 4.21, provisional minimum; docs/contratos/h8_familia.md): the rival smith,
## single and without heir, courts at night with the same orders as the player, marries, brings the spouse home and
## has children with the same rules; nothing is refused.

const RIVAL_FAM: String = "fam_0002"
const RIVAL: String = "chr_0002"

var cat := Catalog.load_from()


func test_the_rival_courts_marries_and_has_children() -> void:
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {}, 4)
	var sim := Sim.new(r["state"], cat)
	var st := sim.state
	eq(str(st.families[RIVAL_FAM]["head"]), RIVAL, "Bernat heads the Ferrer")
	var refused := 0
	var talks := 0
	var wedding_day := -1
	var birth_day := -1
	for d: int in 40:
		for i: int in Clock.MINUTES_PER_DAY:
			for e: Dictionary in sim.step():
				match str(e["type"]):
					"order_refused":
						if str(e["actor"]) == RIVAL:
							refused += 1
					"affinity_changed":
						if str(e["actor"]) == RIVAL and str(e["reason"]) == "talk":
							talks += 1
					"wedding":
						if str(e["character"]) == RIVAL:
							wedding_day = Clock.day(int(st.clock["minute"]))
					"child_born":
						if str(e["family"]) == RIVAL_FAM and birth_day < 0:
							birth_day = Clock.day(int(st.clock["minute"]))
		if birth_day >= 0:
			break
	eq(refused, 0, "the rival's orders are never refused")
	check(talks >= 10, "it courts night after night (%d talks)" % talks)
	check(wedding_day > 0, "it marries (day %d)" % wedding_day)
	var wife := str(st.characters[RIVAL]["spouse"])
	check(wife != "", "a spouse")
	if wife == "":
		return
	eq(str(st.characters[wife]["family"]), RIVAL_FAM, "she joins the Ferrer")
	eq(st.characters[wife].get("job"), null, "it chose someone without a job")
	check(birth_day > wedding_day + 1, "a child after the season of wait (wedding %d, birth %d)" % [wedding_day, birth_day])
	check(Kin.heir(sim, RIVAL_FAM) != "", "the Ferrer have an heir now")
	eq(str(st.characters[wife]["location"]), "bld_0002", "the spouse lives in the rival forge")
