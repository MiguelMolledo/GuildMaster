class_name BotGuardWatch
extends RefCounted
## Bot guard_watch (docs/gdd/04f_vida_y_fiestas.md §4.28.4): runs nights with bandit raids (the scenario life_bandits:
## year 2, raids more likely) and checks that the watch answers and that nobody ever loses more than the cap. Its family
## answers every incident card like a careful player: a raid on its building -> raise the alarm; a brawl -> watch;
## a kidnapping of its own -> pay if it can, else nothing. Gives the same orders as the UI (resolve_incident).
## Measures: raids (started), raids_called (the watch was sent), raids_arrived (a guard got there before the band
## left), raids_repelled, raids_robbed, raid_gold_share_max (gold taken / the owner's gold before, the worst raid),
## raid_items_max (pieces taken, the worst raid), player_raids / player_raids_arrived (on its own buildings: it raised
## the alarm, a guard must come), altercations, altercations_watch (parted by the watch), kidnaps,
## kidnaps_free (the victim back by the end), cards_answered.

const ID: String = "guard_watch"

var fam: String = ""
var m: Dictionary = {}
var gold_before: Dictionary = {}  # incident -> the owner's gold when the band came
var owner: Dictionary = {}        # incident -> family
var called: Dictionary = {}
var arrived: Dictionary = {}
var answered: Dictionary = {}


func orders(sim: Sim) -> Array:
	var st := sim.state
	if fam == "":
		fam = Life.player_family(st)
	for e: Dictionary in sim.events:
		var inc := str(e.get("incident", ""))
		match str(e.get("type", "")):
			"incident_started":
				match str(e.get("def", "")):
					"bandit_raid":
						_add("raids")
						var f := str(st.buildings.get(str(e.get("building", "")), {}).get("owner", ""))
						owner[inc] = f
						gold_before[inc] = Money.gold(st, f)
						if f == fam:
							_add("player_raids")
					"altercation":
						_add("altercations")
					"kidnapping":
						_add("kidnaps")
			"watch_called":
				if owner.has(inc) and not called.has(inc):
					called[inc] = true
					_add("raids_called")
			"guard_arrived":
				if owner.has(inc) and not arrived.has(inc):
					arrived[inc] = true
					_add("raids_arrived")
					if str(owner[inc]) == fam:
						_add("player_raids_arrived")
			"incident_raid_repelled":
				_add("raids_repelled")
			"incident_raid_loot":
				_add("raids_robbed")
				var before := maxi(1, int(gold_before.get(inc, 0)))
				m["raid_gold_share_max"] = maxf(float(m.get("raid_gold_share_max", 0.0)), float(int(e.get("gold", 0))) / float(before))
				var items := 0
				for it: Dictionary in e.get("items", []):
					items += int(it.get("qty", 0))
				m["raid_items_max"] = maxi(int(m.get("raid_items_max", 0)), items)
			"incident_ended":
				if str(e.get("def", "")) == "altercation" and str(e.get("outcome", "")) == "watch":
					_add("altercations_watch")
				if str(e.get("def", "")) == "kidnapping" and str(e.get("outcome", "")) in ["paid", "rescued", "ransomed", "abandoned"]:
					_add("kidnaps_free")
	var out: Array = []
	if fam == "":
		return out
	var head := Kin.head(st, fam)
	for i: Dictionary in Incidents.cards_for(st, fam):
		var id := str(i["id"])
		if answered.has(id):
			continue
		var choice := ""
		match str(i["def"]):
			"bandit_raid":
				choice = "alarm"
			"altercation":
				choice = "watch"
			"kidnapping":
				choice = "pay" if Incidents.choice_block(sim, i, "pay", head) == "" and "pay" in (i["card"]["choices"] as Array) else "nothing"
		if choice != "" and choice in (i["card"]["choices"] as Array):
			answered[id] = true
			_add("cards_answered")
			out.append({"type": "resolve_incident", "actor": head, "incident": id, "choice": choice})
	return out


func _add(k: String) -> void:
	m[k] = int(m.get(k, 0)) + 1


func measures(_sim: Sim) -> Dictionary:
	var out := {}
	for k: String in ["raids", "raids_called", "raids_arrived", "raids_repelled", "raids_robbed", "raid_items_max",
			"player_raids", "player_raids_arrived",
			"altercations", "altercations_watch", "kidnaps", "kidnaps_free", "cards_answered"]:
		out[k] = int(m.get(k, 0))
	out["raid_gold_share_max"] = float(m.get("raid_gold_share_max", 0.0))
	out["raids_called_share"] = float(out["raids_called"]) / float(maxi(1, int(out["raids"])))
	out["raids_arrived_share"] = float(out["raids_arrived"]) / float(maxi(1, int(out["raids"])))
	out["player_raids_arrived_share"] = float(out["player_raids_arrived"]) / float(maxi(1, int(out["player_raids"]))) \
		if int(out["player_raids"]) > 0 else 1.0
	return out
