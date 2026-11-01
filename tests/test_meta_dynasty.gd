extends "res://tests/test_case.gd"
## H8 dynasty score and goals (GDD 4.17; docs/contratos/h8_familia.md): the score comes only from the chronicle (it
## can be recomputed), by kind of fact and by value, the wealth peak, the goals (five generations, fortune).

const FAM: String = "fam_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_scenario("founder_old", 1)["state"], cat)


func test_score_from_the_chronicle() -> void:
	var sim := _sim()
	var st := sim.state
	st.chronicle = []
	for f: Dictionary in [{"kind": "birth"}, {"kind": "birth"}, {"kind": "wedding"}, {"kind": "inheritance"},
			{"kind": "title", "title": "patrician"}, {"kind": "office_won", "rank": "mayor"},
			{"kind": "sentence", "severity": "medium"}, {"kind": "goal_done", "goal": "fortune"},
			{"kind": "wealth_peak", "value": 1250}, {"kind": "wealth_peak", "value": 870}, {"kind": "death"}]:
		var fact := f.duplicate()
		var kind := str(fact["kind"])
		fact.erase("kind")
		fact["family"] = FAM
		Chronicle.add(st, kind, fact)
	Chronicle.add(st, "birth", {"family": "fam_0002"})  # another family's fact does not count
	var sc := Dynasty.score(sim, FAM)
	eq(sc["by_kind"], {"birth": 20, "wedding": 20, "inheritance": 100, "title": 75, "office_won": 250, "sentence": -60,
		"goal_done": 500, "wealth_peak": 12}, "points by kind (4.17)")
	eq(int(sc["total"]), 20 + 20 + 100 + 75 + 250 - 60 + 500 + 12, "total")
	eq(int(sc["peak"]), 1250, "the highest peak")
	var again := Dynasty.score(sim, FAM)
	eq(again, sc, "recomputed: the same")


func test_wealth_peaks_and_goals() -> void:
	var sim := _sim()
	var st := sim.state
	st.chronicle = []
	var w := Dynasty.wealth(sim, FAM)
	eq(w, Money.gold(st, FAM) + int(cat.buildings()["forge"]["build_cost"]), "gold + the forge")
	Dynasty.record_peak(sim, FAM)
	eq(Dynasty.peak(st, FAM), w, "first peak")
	Dynasty.record_peak(sim, FAM)
	eq(st.chronicle.size(), 1, "no new peak without growth")
	st.families[FAM]["gold"] = int(st.families[FAM]["gold"]) + 150
	Dynasty.record_peak(sim, FAM)
	eq(Dynasty.peak(st, FAM), w + 150, "a new peak (+150 >= step 100)")
	st.families[FAM]["generation"] = 5
	Dynasty.check_goals(sim, FAM)
	eq(st.families[FAM]["goals_done"], ["five_generations"], "five generations")
	st.families[FAM]["gold"] = 25000
	Dynasty.check_goals(sim, FAM)
	eq(st.families[FAM]["goals_done"], ["five_generations", "fortune"], "fortune")
	Dynasty.check_goals(sim, FAM)
	eq(st.chronicle.filter(func(e: Dictionary) -> bool: return str(e["kind"]) == "goal_done").size(), 2, "once each")
	var gv := Dynasty.goals_view(sim, FAM)
	eq(gv.map(func(g: Dictionary) -> bool: return bool(g["done"])), [true, true, false], "goals panel (mayor waits for H10)")


func test_dawn_writes_the_peak() -> void:
	var sim := _sim()
	sim.state.chronicle = []
	sim.run_minutes(Clock.MINUTES_PER_DAY)
	check(Dynasty.peak(sim.state, FAM) > 0, "a peak at dawn")
