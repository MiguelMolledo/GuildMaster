extends "res://tests/test_case.gd"
## H8 bot dynasty (10/H8): the short part of its run in a test (the whole run, ~320 days, is a ritual of sim_runner:
## --scenario=dynasty_start --bots=dynasty --days=320 --seeds=3, targets in data/targets.json). From the courtship
## scenario it walks to Agnès with the talk queued behind, proposes when it can and marries, with no refused order.

const FAM: String = "fam_0001"
const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func test_the_bot_courts_and_marries() -> void:
	var sim := Sim.new(NewGame.from_scenario("courtship", 2)["state"], cat)
	var bot := BotDynasty.new()
	var refused: Array = []
	for i: int in 3 * Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step(bot.orders(sim)):
			if str(e["type"]) == "order_refused" and str(e["actor"]) == HERO:
				refused.append(e)
		if bot.wedding_day >= 0:
			break
	eq(refused, [], "no refused orders")
	check(bot.wedding_day >= 1, "married within 3 days (day %d)" % bot.wedding_day)
	check(str(sim.state.characters[HERO]["spouse"]) != "", "Hugo has a spouse")
	var m := bot.measures(sim)
	eq(int(m["inherited"]), 0, "nobody inherited yet")
	eq(int(m["game_over"]), 0, "the game goes on")


func test_the_heir_courts_when_adult() -> void:
	var sim := Sim.new(NewGame.from_scenario("founder_old", 1)["state"], cat)
	var bot := BotDynasty.new()
	bot.orders(sim)
	var son := str(sim.state.characters[HERO]["children"][0])
	eq(bot._suitor(sim), son, "the founder is married: the adult single heir courts")
