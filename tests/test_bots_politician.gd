extends "res://tests/test_case.gd"
## H10 bot politician (docs/contratos/h10_cargos.md): BotArtisanExpert with runs_office = 1 runs for a minor office
## once Citizen and, as market inspector, regulates the price of its product. The criterion (it wins a minor office
## in a long game) is the target `politician` of data/targets.json (tools/sim_runner.gd --bots=politician).

const HERO: String = "chr_0001"

var cat := Catalog.load_from()


func _bot() -> BotArtisanExpert:
	var b := BotArtisanExpert.new()
	b.runs_office = 1
	return b


func _events(sim: Sim, bot: Object, minutes: int, type: String) -> Array:
	var out: Array = []
	for i: int in minutes:
		for e: Dictionary in sim.step(bot.orders(sim)):
			if str(e["type"]) == type:
				out.append(e)
	return out


func test_politician_runs_for_a_minor_office() -> void:
	var sim := Sim.new(NewGame.from_scenario("office_campaign", 1)["state"], cat)
	var got := _events(sim, _bot(), 30, "office_candidate")
	eq(got.size(), 1, "it registers once")
	eq(str(got[0]["character"]), HERO, "Hugo")
	eq(str(got[0]["office"]), "market_inspector", "the first minor office")


func test_expert_does_not_run() -> void:
	var sim := Sim.new(NewGame.from_scenario("office_campaign", 1)["state"], cat)
	eq(_events(sim, BotArtisanExpert.new(), 30, "office_candidate").size(), 0, "artisan_expert keeps its H5/H9 play")


func test_inspector_bot_regulates_its_product() -> void:
	var sim := Sim.new(NewGame.from_scenario("office_inspector", 1)["state"], cat)
	var got := _events(sim, _bot(), 30, "price_regulated")
	eq(got.size(), 1, "it regulates once (then the cooldown)")
	eq(int(got[0]["percent"]), 10, "+10 %")
