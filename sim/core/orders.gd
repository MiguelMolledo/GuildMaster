class_name Orders
extends RefCounted
## Every change an actor starts comes in as an order (GDD 05 §5.5): a Dictionary {"type": String, "actor": String, ...}.
## The UI, the bots, family AI and rival families give the same orders; nobody changes the state another way.
## apply() validates first and returns {"ok": bool, "reason": String}. A refused order changes nothing; its reason is
## an id the UI shows through i18n ("reason.<id>").
##
## Orders today: wait, transfer, move_to; H2: enter_building, exit_building, go_to_station, equip, unequip, work_at,
## stop_work, master_touch (handlers live with their system; docs/contratos/h2_forja.md); H3: buy, sell,
## repay_loan, read_notices, accept_contract, deliver_contract, abandon_contract (docs/contratos/h3_mercado.md); H4: hire,
## fire, promote, bonus, queue_add, queue_remove, queue_move, queue_loop, queue_pause, set_role
## (docs/contratos/h4_empleados.md); H5: buy_upgrade (docs/contratos/h5_mejoras.md); H8: court_talk, court_gift,
## propose, designate_heir, school_choice, assign_building, close_dynasty, set_schedule, set_directives
## (docs/contratos/h8_familia.md); H7: npc_talk, npc_gift, npc_flatter, npc_insult, npc_threaten, resolve_microevent
## (docs/contratos/h7_ciudad.md); H9: request_title (docs/contratos/h9_titulos.md); H10: run_for_office,
## campaign_action, use_office_power (docs/contratos/h10_cargos.md); H11: accuse, witness_action, trial_cross,
## trial_rest, trial_verdict (docs/contratos/h11_tribunal.md); duelo: duel_challenge, duel_answer, duel_withdraw,
## duel_move, duel_auto, duel_brawl (docs/contratos/duelo.md); juegos: game_play, game_bet (docs/contratos/juegos.md); vida:
## resolve_incident, give_alms (docs/contratos/vida.md). Each milestone adds
## its own (GDD 05 §5.5 has the full list).


static func apply(sim: Sim, order: Dictionary) -> Dictionary:
	var type := str(order.get("type", ""))
	match type:
		"wait":
			return ok()
		"transfer":
			return _transfer(sim, order)
		"move_to":
			return _move_to(sim, order)
		# H2 · buildings and items (sim/world/buildings.gd, sim/econ/equipment.gd)
		"enter_building":
			return Buildings.order_enter(sim, order)
		"exit_building":
			return Buildings.order_exit(sim, order)
		"go_to_station":
			return Buildings.order_go_to_station(sim, order)
		"equip":
			return Equipment.order_equip(sim, order)
		"unequip":
			return Equipment.order_unequip(sim, order)
		# H2 · production (sim/econ/production.gd)
		"work_at":
			return Production.order_work_at(sim, order)
		"stop_work":
			return Production.order_stop_work(sim, order)
		"master_touch":
			return Production.order_master_touch(sim, order)
		# H3 · market, money, contracts (sim/econ/market.gd, loans.gd, contracts.gd)
		"buy":
			return Market.order_buy(sim, order)
		"sell":
			return Market.order_sell(sim, order)
		"repay_loan":
			return Loans.order_repay(sim, order)
		"read_notices":
			return Notices.order_read(sim, order)
		"accept_contract":
			return Contracts.order_accept(sim, order)
		"deliver_contract":
			return Contracts.order_deliver(sim, order)
		"abandon_contract":
			return Contracts.order_abandon(sim, order)
		# H4 · employees (sim/econ/staff.gd) and the production queue (sim/econ/work_queue.gd)
		"hire":
			return Staff.order_hire(sim, order)
		"fire":
			return Staff.order_fire(sim, order)
		"promote":
			return Staff.order_promote(sim, order)
		"bonus":
			return Staff.order_bonus(sim, order)
		"queue_add":
			return WorkQueue.order_add(sim, order)
		"queue_remove":
			return WorkQueue.order_remove(sim, order)
		"queue_move":
			return WorkQueue.order_move(sim, order)
		"queue_loop":
			return WorkQueue.order_loop(sim, order)
		"queue_pause":
			return WorkQueue.order_pause(sim, order)
		"set_role":
			return WorkQueue.order_set_role(sim, order)
		# H5 · upgrades (sim/econ/upgrades.gd)
		"buy_upgrade":
			return Upgrades.order_buy(sim, order)
		# H8 · family (sim/family/*.gd, docs/contratos/h8_familia.md)
		"court_talk":
			return Courtship.order_talk(sim, order)
		"court_gift":
			return Courtship.order_gift(sim, order)
		"propose":
			return Courtship.order_propose(sim, order)
		"designate_heir":
			return Lifecycle.order_designate_heir(sim, order)
		"school_choice":
			return Lifecycle.order_school_choice(sim, order)
		"assign_building":
			return Lifecycle.order_assign_building(sim, order)
		"close_dynasty":
			return Lifecycle.order_close_dynasty(sim, order)
		"set_schedule":
			return Schedules.order_set(sim, order)
		"set_directives":
			return Schedules.order_set_directives(sim, order)
		# H7 · the living town (sim/town/*.gd, docs/contratos/h7_ciudad.md)
		"npc_talk":
			return NpcActions.order(sim, order, "talk")
		"npc_gift":
			return NpcActions.order(sim, order, "gift")
		"npc_flatter":
			return NpcActions.order(sim, order, "flatter")
		"npc_insult":
			return NpcActions.order(sim, order, "insult")
		"npc_threaten":
			return NpcActions.order(sim, order, "threaten")
		"resolve_microevent":
			return Microevents.order_resolve(sim, order)
		# H9 · titles (sim/politics/titles.gd, docs/contratos/h9_titulos.md)
		"request_title":
			return Titles.order_request(sim, order)
		# H10 · offices and elections (sim/politics/offices.gd, elections.gd, docs/contratos/h10_cargos.md)
		"run_for_office":
			return Elections.order_run(sim, order)
		"campaign_action":
			return Elections.order_campaign(sim, order)
		"use_office_power":
			return Offices.order_power(sim, order)
		# H11 · the court (sim/politics/tribunal.gd, docs/contratos/h11_tribunal.md)
		"accuse":
			return Tribunal.order_accuse(sim, order)
		"witness_action":
			return Tribunal.order_witness(sim, order)
		"trial_cross":
			return Tribunal.order_cross(sim, order)
		"trial_rest":
			return Tribunal.order_rest(sim, order)
		"trial_verdict":
			return Tribunal.order_verdict(sim, order)
		# Duelo · duels of honour (sim/combat/duels.gd, docs/contratos/duelo.md)
		"duel_challenge":
			return Duels.order_challenge(sim, order)
		"duel_answer":
			return Duels.order_answer(sim, order)
		"duel_withdraw":
			return Duels.order_withdraw(sim, order)
		"duel_move":
			return Duels.order_move(sim, order)
		"duel_auto":
			return Duels.order_auto(sim, order)
		"duel_brawl":
			return Duels.order_brawl(sim, order)
		# Viajes (sim/region/*.gd, docs/gdd/09b_region.md §9b.5)
		"travel":
			return Travel.order_travel(sim, order)
		"return":
			return Travel.order_return(sim, order)
		"city_buy":
			return CityTrade.order_buy(sim, order)
		"city_sell":
			return CityTrade.order_sell(sim, order)
		"city_accept":
			return CityTrade.order_accept(sim, order)
		"city_deliver":
			return CityTrade.order_deliver(sim, order)
		"buy_cart":
			return Caravans.order_buy_cart(sim, order)
		"caravan_send":
			return Caravans.order_send(sim, order)
		"sign_treaty":
			return Treaties.order_sign(sim, order)
		"propose_town_treaty":
			return Treaties.order_propose_town(sim, order)
		"cancel_treaty":
			return Treaties.order_cancel(sim, order)
		# Juegos · games and competitions (sim/games/, docs/contratos/juegos.md)
		"game_play":
			return Games.replay(sim, order)
		"game_bet":
			return Betting.order_bet(sim, order)
		"game_enter":
			return FestivalGames.order_enter(sim, order)
		# Fiestas (sim/fest/festivals.gd, docs/gdd/04f_vida_y_fiestas.md 4.25.5)
		"festival_sponsor":
			return Festivals.order_sponsor(sim, order)
		"festival_host_wedding":
			return Festivals.order_host_wedding(sim, order)
		# Vida (sim/life/*.gd, docs/gdd/04f_vida_y_fiestas.md §4.24, docs/contratos/vida.md)
		"resolve_incident":
			return Incidents.order_resolve(sim, order)
		"give_alms":
			return Visitors.order_alms(sim, order)
	return fail("unknown_order")


## Management orders: given from a panel, they act at once and never touch the actor's order queue (a bonus does
## not stop someone walking; given in pause they apply on resume instead of waiting behind the walk).
const MANAGEMENT: Array[String] = ["hire", "fire", "promote", "bonus", "set_role", "queue_add", "queue_remove",
	"queue_move", "queue_loop", "queue_pause", "repay_loan", "read_notices", "abandon_contract", "buy_upgrade",
	"designate_heir", "school_choice", "assign_building", "close_dynasty", "set_schedule", "set_directives",
	"resolve_microevent", "run_for_office", "use_office_power", "accuse", "trial_cross", "trial_rest", "trial_verdict",
	"duel_answer", "duel_withdraw", "duel_move", "duel_auto",
	"buy_cart", "caravan_send", "propose_town_treaty", "cancel_treaty", "travel", "return", "city_buy", "city_sell",
	"city_accept", "city_deliver", "sign_treaty",
	"game_play", "game_bet", "game_enter", "festival_sponsor", "festival_host_wedding",
	"resolve_incident"]


static func is_management(type: String) -> bool:
	return type in MANAGEMENT


static func ok() -> Dictionary:
	return {"ok": true, "reason": ""}


static func fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## {"type": "transfer", "actor", "from", "to", "item", "quality", "qty"}: moves items between two inventories.
## The actor must control the source: be it, or own the building it is (its own or its family's), and be near
## (GDD 04 §4.3.4, _near). A character's weight limit counts its equipment (Equipment): too_heavy.
static func _transfer(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var from := str(o.get("from", ""))
	var to := str(o.get("to", ""))
	if not st.characters.has(actor):
		return fail("unknown_actor")
	if from == to:
		return fail("same_inventory")
	var src := st.inventory_of(from)
	var dst := st.inventory_of(to)
	if src.is_empty() or dst.is_empty():
		return fail("no_inventory")
	if not _controls(st, actor, from):
		return fail("not_yours")
	var near := _near(st, from, to)
	if near == "" and actor != from and actor != to:
		near = _near(st, actor, from)  # an owner moving its building's goods must be inside it too
	if near != "":
		return fail(near)
	var item := str(o.get("item", ""))
	var quality := int(o.get("quality", 0))
	var qty := int(o.get("qty", 0))
	if qty <= 0:
		return fail("bad_quantity")
	if Inventory.count(src, item, quality) < qty:
		return fail("not_enough")
	if not Inventory.can_add(dst, sim.catalog, item, quality, qty):
		return fail("too_heavy" if st.characters.has(to) else "no_room")  # a character's limit counts its equipment
	Inventory.remove(src, item, quality, qty)
	Inventory.add(dst, sim.catalog, item, quality, qty)
	sim.events.append({"type": "items_moved", "actor": actor, "from": from, "to": to, "item": item,
		"quality": quality, "qty": qty})
	return ok()


## {"type": "move_to", "actor", "tile": [col, row]}: walk there by the cheapest route (GDD 05 §5.4, D3).
## Reasons: unknown_actor, dead, no_map, out_of_bounds, blocked, unreachable. The rules live in Movement.
## Inside a building a character does not walk the map: not_inside_map until it leaves (exit_building).
static func _move_to(sim: Sim, o: Dictionary) -> Dictionary:
	var actor := str(o.get("actor", ""))
	if str(sim.state.characters.get(actor, {}).get("location", "")) != "":
		return fail("not_inside_map")
	return Movement.move_to(sim, actor, o.get("tile"))


static func _controls(st: WorldState, actor: String, entity: String) -> bool:
	if entity == actor:
		return true
	return Buildings.owns(st, actor, entity)


## Physical proximity for a transfer (GDD 4.3.4): "" when near, else the reason. Character <-> building: the
## character is inside it. Character <-> character: same family, and same tile on the map or inside the same building.
static func _near(st: WorldState, a: String, b: String) -> String:
	if st.characters.has(a) and st.characters.has(b):
		var ca: Dictionary = st.characters[a]
		var cb: Dictionary = st.characters[b]
		if str(ca.get("family", "")) == "" or str(ca.get("family", "")) != str(cb.get("family", "")):
			return "not_family"
		var la := str(ca.get("location", ""))
		if la != str(cb.get("location", "")):
			return "too_far"
		if la != "":
			return ""
		var pa: Array = ca.get("position", [])
		var pb: Array = cb.get("position", [])
		return "" if pa.size() == 2 and pb.size() == 2 and int(pa[0]) == int(pb[0]) and int(pa[1]) == int(pb[1]) \
			else "too_far"
	if st.characters.has(a) and st.buildings.has(b):
		return "" if str(st.characters[a].get("location", "")) == b else "not_inside"
	if st.buildings.has(a) and st.characters.has(b):
		return "" if str(st.characters[b].get("location", "")) == a else "not_inside"
	return "too_far"  # building <-> building: somebody has to carry it
