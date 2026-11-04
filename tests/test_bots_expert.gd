extends "res://tests/test_case.gd"
## H5 · bot artisan_expert (sim/bots/bot_artisan_expert.gd) and the measures of tools/sim_runner.gd it feeds.


## A real new game in Normal: in 8 days the expert pays the debt, hires, fills the queue and starts an upgrade of
## the production branch, with no refused order and the book adding up.
func test_expert_runs_the_forge() -> void:
	var cat := Catalog.load_from()
	var r := NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)
	check(bool(r["ok"]), "new game")
	var sim := Sim.new(r["state"], cat)
	var bot := BotArtisanExpert.new()
	var seen := {}
	var refused: Array = []
	var gold0 := Money.gold(sim.state, "fam_0001") - Ledger.total(sim.state, "fam_0001")
	for i: int in 8 * Clock.MINUTES_PER_DAY:
		for e: Dictionary in sim.step(bot.orders(sim)):
			var t := str(e["type"])
			if t == "order_refused":
				refused.append("%s %s" % [e["order"], e["reason"]])
			elif t in ["employee_hired", "upgrade_started", "loan_repaid", "employee_assigned"]:
				if not seen.has(t):
					seen[t] = e
	eq(refused, [], "no refused orders")
	check(seen.has("loan_repaid"), "debt paid")
	check(seen.has("employee_hired"), "hired")
	check(seen.has("employee_assigned"), "the queue gave work to an employee")
	check(seen.has("upgrade_started"), "bought an upgrade")
	if seen.has("upgrade_started"):
		eq(str(seen["upgrade_started"]["upgrade"]), "forge_production_1", "production first")
	eq(Money.gold(sim.state, "fam_0001") - Ledger.total(sim.state, "fam_0001"), gold0, "ledger adds up")


## The novice keeps its habits: the hooks the expert overrides give the novice's values.
func test_novice_hooks_unchanged() -> void:
	var cat := Catalog.load_from()
	var sim := Sim.new(NewGame.from_start(cat, "artisan_blacksmith", "normal", {"cast": "fixed"}, 1)["state"], cat)
	var bot := BotArtisanNovice.new()
	eq(bot._capacity(sim), 1.0, "capacity")
	eq(bot._max_held(sim, "forge_sword"), BotArtisanNovice.MAX_HELD, "max held")
	eq(bot._batch(sim, 3), BotArtisanNovice.BATCH, "batch")
	eq(bot._extra_plan(sim), [], "extra plan")
