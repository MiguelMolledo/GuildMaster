extends "res://tests/test_case.gd"
## H11 bot crook (docs/contratos/h11_tribunal.md): BotArtisanExpert with crook = 1 puts the double accounting first in
## its upgrade plan and, at the hearing of its trial, questions the witnesses against and rests. The criterion (it ends
## in court with the expected frequency) is the target `crook` of data/targets.json (--bots=crook).

const HERO: String = "chr_0001"
const FAM: String = "fam_0001"

var cat := Catalog.load_from()


func _bot(on: int) -> BotArtisanExpert:
	var b := BotArtisanExpert.new()
	b.crook = on
	return b


func test_crook_wants_the_double_accounting() -> void:
	var sim := Sim.new(NewGame.from_scenario("office_campaign", 1)["state"], cat)
	eq(_bot(1)._next_upgrade(sim), "forge_secrets_1", "Secrets 1 first")
	check(_bot(0)._next_upgrade(sim) != "forge_secrets_1", "artisan_expert keeps its H5 plan")


func test_crook_defends_itself_at_the_hearing() -> void:
	var sim := Sim.new(NewGame.from_scenario("trial_hearing", 1)["state"], cat)
	var bot := _bot(1)
	var crossed := 0
	var verdict := ""
	for i: int in 60:
		for e: Dictionary in sim.step(bot.orders(sim)):
			if str(e["type"]) == "trial_cross":
				crossed += 1
			elif str(e["type"]) == "trial_verdict":
				verdict = str(e["verdict"])
	eq(crossed, 2, "it questions the two witnesses against")
	check(verdict != "", "and rests the defense before the hearing ends (%s)" % verdict)
