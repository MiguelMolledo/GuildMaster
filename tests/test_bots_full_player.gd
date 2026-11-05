extends "res://tests/test_case.gd"
## The full player and its chaotic twin (docs/gdd/07_testing.md §7.4, sim/bots/bot_full_player.gd,
## sim/bots/bot_chaos_player.gd). The whole-game criteria are the targets full_player / chaos_player of
## data/targets.json (tools/full_player.gd); these check the composition's own rules.

var cat := Catalog.load_from()


func _new_game(s: int = 1) -> Sim:
	return Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, s)["state"], cat)


func test_full_player_plays_a_morning_without_refusals() -> void:
	var sim := _new_game()
	var bot := BotFullPlayer.new()
	var refused := 0
	var worked := 0
	for i: int in 360:
		for e: Dictionary in sim.step(bot.orders(sim)):
			if str(e["type"]) == "order_refused":
				refused += 1
			elif str(e["type"]) == "work_started" and str(e.get("actor", "")) == "chr_0001":
				worked += 1
	eq(refused, 0, "no order refused")
	check(worked > 0, "the forge works by hand")
	eq(bot.runs_office, 1, "it runs for minor offices (the politician's hook)")


func test_the_forge_follows_the_next_head() -> void:
	var sim := Sim.new(NewGame.from_scenario("founder_old", 1)["state"], cat)
	var bot := BotFullPlayer.new()
	sim.step(bot.orders(sim))
	eq(bot.ACTOR, "chr_0001", "the founder plays first")
	Lifecycle.die(sim, "chr_0001", "test")
	sim.step(bot.orders(sim))
	var head := Kin.head(sim.state, "fam_0001")
	check(head != "chr_0001" and head != "", "somebody inherits")
	eq(bot.ACTOR, head, "the bot plays the forge with the new head")
	eq(bot.heads.size(), 2, "both heads in the report")


func test_festival_contract_uses_the_real_hours_left() -> void:
	var sim := _new_game()
	var bot := BotFullPlayer.new()
	bot._fam_id = "fam_0001"
	var now := int(sim.state.clock["minute"])
	# four horseshoes (1.5 h + an ingot each) due in 10 hours, the deadline rounded up to a day: the novice's check
	# would take it; the full player does not.
	var c := {"id": "ctr_test", "item": "horseshoe", "qty": 4, "min_quality": 0, "deadline_days": 1,
		"due_at": now + 600}
	check(not bot._can_make_in_time(sim, c), "4 horseshoes do not fit in 10 h")
	c["due_at"] = now + 3 * 1440
	check(bot._can_make_in_time(sim, c), "they fit in 3 days")


func test_chaos_draws_its_own_dice() -> void:
	var sim := _new_game()
	var bot := BotChaosPlayer.new(1)
	var before := str(sim.state.rng.state)
	for i: int in 120:
		bot.orders(sim)
	eq(str(sim.state.rng.state), before, "the bot never touches state.rng")


func test_a_chaotic_day_saves_and_loads_the_same() -> void:
	var sim := _new_game(2)
	var bot := BotChaosPlayer.new(2)
	for i: int in 1440:
		sim.step(bot.orders(sim))
	var d := sim.state.to_dict()
	var r := SaveFile.from_text(JSON.stringify(d, "\t", true, true))
	check(bool(r["ok"]), "it loads")
	eq(SaveFile.canonical((r["state"] as WorldState).to_dict()).md5_text(), SaveFile.canonical(d).md5_text(),
		"same hash after save and load")
