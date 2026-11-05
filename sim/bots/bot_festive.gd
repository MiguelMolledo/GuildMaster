class_name BotFestive
extends BotArtisanExpert
## Fiestas (04f 4.28.4): the bot «festive» plays a whole year (8 days) with the festivals on: the expert of the forge
## (it takes the festival contracts of its trade from the board like any other: the board shows them with status ok),
## plus, on the crier of every big feast, it sponsors the music while it has spare gold (festival_sponsor), and pays
## the banquet if its family marries. It measures what the calendar did (measures): every fixed feast started
## (fest_<id>), the variable ones, the criers, the contracts posted, won (by the player or by the rivals: a race has
## one winner), lost and left unclaimed, the spectacles, the sponsorships, and that nothing got stuck (a feast past its
## end or not started at its hour: fest_stuck 0). Its targets: data/targets.json festive.

const SPONSOR_PART: String = "music"
const SPONSOR_SPARE: int = 60        # gold it keeps after sponsoring

var _m: Dictionary = {}
var _sponsored: Dictionary = {}      # festival instance -> true


func orders(sim: Sim) -> Array:
	_watch(sim)
	var out: Array = []
	var fam := _fam(sim)
	for inst: Dictionary in Festivals.announced(sim) + Festivals.active(sim):  # the court (owner, 2026-11-05)
		var key := "court|" + str(inst["id"])
		if _sponsored.has(key):
			continue
		_sponsored[key] = true
		if not FestivalCourt.effect(sim, inst, "contest").is_empty() and \
				not FestivalCourt.trade_items(sim, fam).is_empty() and \
				not FestivalCourt.best_piece(sim, fam, ACTOR, FestivalCourt.trade_items(sim, fam)).is_empty():
			out.append({"type": "festival_enter_contest", "actor": ACTOR, "festival": str(inst["id"])})
		if not FestivalCourt.effect(sim, inst, "town_gift").is_empty() and \
				not FestivalCourt.best_piece(sim, fam, ACTOR, Festivals.rules(sim).get("gift", {}).get("items", [])).is_empty():
			out.append({"type": "festival_offer_gift", "actor": ACTOR, "festival": str(inst["id"])})
	for inst: Dictionary in Festivals.announced(sim):
		var id := str(inst["id"])
		if _sponsored.has(id) or str(Festivals.def_of(sim, str(inst["def"])).get("size", "")) != "big":
			continue
		_sponsored[id] = true
		var gold := int(Festivals.rules(sim).get("sponsor", {}).get("parts", {}).get(SPONSOR_PART, {}).get("gold", 0))
		if Festivals.part_taken_by(inst, SPONSOR_PART) != "":
			continue  # another house pays the music: the bot does not bid
		if Money.gold(sim.state, fam) - gold >= SPONSOR_SPARE:
			out.append({"type": "festival_sponsor", "actor": ACTOR, "festival": id, "part": SPONSOR_PART})
	if (sim.state.festivals.get("offers", {}) as Dictionary).has(fam):
		out.append({"type": "festival_host_wedding", "actor": ACTOR})
	out.append_array(super.orders(sim))
	return out


## The events of the step before (sim.events still holds them when the next orders are asked).
func _watch(sim: Sim) -> void:
	var fam := _fam(sim)
	for e: Dictionary in sim.events:
		var t := str(e.get("type", ""))
		match t:
			"festival_eve":
				_add("fest_eves")
			"festival_started":
				_add("fest_" + str(e.get("def", "")))
				_add("fest_started")
				if str(Festivals.def_of(sim, str(e.get("def", ""))).get("kind", "")) == "variable":
					_add("fest_variable")
			"festival_ended":
				_add("fest_ended")
			"festival_spectacle":
				_add("fest_spectacles")
			"festival_sponsored":
				if str(e.get("family", "")) == fam:
					_add("fest_sponsored")
				elif str(sim.state.families.get(str(e.get("family", "")), {}).get("ai_profile", "")) != "":
					_add("fest_ai_sponsored")
			"festival_contest":
				_add("fest_contests")
				if str(e.get("family", "")) == fam:
					_add("fest_contests_won_player")
			"festival_contest_entered":
				_add("fest_contest_entries")
			"festival_gift_chosen":
				_add("fest_town_gifts")
			"festival_audience":
				_add("fest_audiences")
			"contract_posted":
				if str(e.get("festival", "")) != "":
					_add("fest_contracts_posted")
			"festival_contract_done":
				_add("fest_contracts_done")
				if str(e.get("family", "")) == fam:
					_add("fest_contracts_done_player")
				if bool(e.get("chronicle", false)):
					_add("fest_chronicle")
			"contract_lost":
				if str(e.get("family", "")) == fam:
					_add("fest_contracts_lost_player")
			"festival_contract_expired":
				_add("fest_contracts_unclaimed")
			"contract_accepted":
				if str(e.get("festival", "")) != "" and str(e.get("family", "")) == fam:
					_add("fest_contracts_taken_player")
			"order_refused":
				if str(e.get("order", "")).begins_with("festival_"):
					_add("fest_refused")


func _add(k: String, n: int = 1) -> void:
	_m[k] = int(_m.get(k, 0)) + n


func measures(sim: Sim) -> Dictionary:
	_watch(sim)
	var out := _m.duplicate()
	for id: String in Festivals.defs(sim):
		if not out.has("fest_" + id):
			out["fest_" + id] = 0
	for k: String in ["fest_eves", "fest_started", "fest_variable", "fest_ended", "fest_spectacles", "fest_sponsored",
			"fest_contracts_posted", "fest_contracts_done", "fest_contracts_done_player", "fest_contracts_lost_player",
			"fest_contracts_unclaimed", "fest_contracts_taken_player", "fest_chronicle", "fest_refused",
			"fest_ai_sponsored", "fest_contests", "fest_contests_won_player", "fest_contest_entries", "fest_town_gifts",
			"fest_audiences"]:
		if not out.has(k):
			out[k] = 0
	var now := int(sim.state.clock["minute"])
	var stuck := 0
	for inst: Dictionary in sim.state.festivals.get("active", []):
		stuck += 1 if int(inst["end"]) <= now else 0
	for inst: Dictionary in sim.state.festivals.get("upcoming", []):
		stuck += 1 if int(inst["start"]) < now else 0
	out["fest_stuck"] = stuck
	var fixed := 0
	for id: String in Festivals.defs(sim):
		if str(Festivals.def_of(sim, id).get("kind", "")) == "fixed" and int(out.get("fest_" + id, 0)) > 0:
			fixed += 1
	out["fest_fixed_seen"] = fixed
	return out
