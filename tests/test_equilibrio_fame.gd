extends "res://tests/test_case.gd"
## Equilibrio 13 (docs/decisiones.json; 04g §4.6.5.7): the fame of a workshop, 0.5-2.0, from what it sold and its facts.

const FAM: String = "fam_0001"
const FORGE: String = "bld_0001"

var cat := Catalog.load_from()


func _sim() -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"], cat)


func test_starts_at_one_and_follows_quality() -> void:
	var sim := _sim()
	eq(WorkshopFame.of(sim, FORGE), 1.0, "1 at the start")
	eq(WorkshopFame.main_workshop(sim, FAM), FORGE, "the forge is the main workshop")
	sim.events = [{"type": "market_sold", "family": FAM, "item": "sword", "quality": 2, "qty": 2}]
	WorkshopFame.step(sim)
	near(WorkshopFame.of(sim, FORGE), 1.5, 0.001, "excellent pieces: +0.5")


func test_facts_and_bounds() -> void:
	var sim := _sim()
	for i: int in 10:
		WorkshopFame.add(sim, FORGE, "masterwork")
	check(WorkshopFame.of(sim, FORGE) <= 2.0, "never over 2")
	near(WorkshopFame.of(sim, FORGE), 1.75, 0.001, "the renown has its own cap")
	for i: int in 40:
		WorkshopFame.add(sim, FORGE, "contract_failed")
	near(WorkshopFame.of(sim, FORGE), 0.5, 0.001, "never under 0.5")


func test_renown_decays_at_dawn_and_old_sales_go() -> void:
	var sim := _sim()
	WorkshopFame.add(sim, FORGE, "masterwork")
	sim.events = [{"type": "counter_sold", "family": FAM, "building": FORGE, "item": "sword", "quality": 1}]
	WorkshopFame.step(sim)
	var before := WorkshopFame.of(sim, FORGE)
	sim.run_minutes(5 * Clock.MINUTES_PER_DAY)
	check(WorkshopFame.of(sim, FORGE) < before, "it fades (%.2f -> %.2f)" % [before, WorkshopFame.of(sim, FORGE)])
	eq(WorkshopFame.mean_quality(sim, FORGE), 0.0, "the sale of 5 days ago is out of the window")


func test_counter_reads_it() -> void:
	var sim := _sim()
	var p0 := Counter.price(sim, FORGE, "", "sword", 0, "")
	for i: int in 3:
		WorkshopFame.add(sim, FORGE, "masterwork")
	check(Counter.price(sim, FORGE, "", "sword", 0, "") > p0, "a famous workshop's counter sells dearer")
