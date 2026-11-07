class_name BotBranch
extends RefCounted
## H6 (docs/gdd/04_diseno_de_juego.md §4.9; the full_player's pending items «Barón inalcanzable con un solo negocio»
## and «el oro se acumula sin sumidero»): the family's second workshop, for BotFullPlayer. When it pays (the title
## leaves room, the gold covers the works over the family's reserve and a spare, and a workshop of its trade is
## expected to make money: Construction.daily_net), the head builds one on the best free plot where it fits (Plots,
## the same order as the player's build mode). Once it stands it runs on its own: with mix (the default), the
## counter's stock of every product it can make, the shop counter (commerce level 1) and one «any» employee who forges
## and serves (Counter.server_of, 4.7.4); without it, as at first, the queue looping the best margin recipe, a second
## slot (staff level 1) and two employees (the better craftsman forges, the other sells at the counter); and its inputs and the upgrades' materials sent by errand (buy with deliver_to) whenever the head is at
## their stall anyway. After JUDGE_DAYS running, if it lost money it is closed (fired, pulled down) and no other opens.
## The Taberna-Posada comes first (it pays 3-4 times a forge).
## Only player orders; every one of them checked with the same rules first.

const TYPE: String = "forge"          # the trade of the branch: the family's own (the smith's)
const BUILD_SPARE: int = 1000         # gold kept on top of the reserve after paying the works
const HOME_NET: int = 300             # the main forge made at least this over the last JUDGE_DAYS (the market takes more)
const JUDGE_DAYS: int = 8             # after this many days running, a branch that loses money is closed
const HIRE_DAYS: int = 3              # gold for this many days of wages on top of the reserve before hiring
const STOCK_UNITS: int = 4            # pieces' worth of raw materials kept in the branch's storage
const COUNTER: String = "forge_commerce_1"
const UPGRADES: Array = ["forge_commerce_1", "forge_staff_1"]  # the counter, then a second slot (its seller)
const STAFF: int = 2                  # one forges ("any"), the other sells at the counter (Counter.server_of)
const MIX_UPGRADES: Array = ["forge_commerce_1"]  # mix: one «any» hand forges and serves (4.7.4): no second slot
const MIX_STAFF: int = 1
const COUNTER_STOCK: int = 2          # mix: pieces of each product kept for the counter's customers

var bld: String = ""                  # the branch's building once ordered
var why_not: String = ""              # why it has none (the report)
var raw: Array = []                   # the items the head buys at its stall anyway (the recipe uses only these)
var opened: int = -1                  # the day the branch was finished (its first day running)
var closed: bool = false              # it closed one that lost money: it does not open another
var home_bld: String = ""             # the family's main workshop (what its earnings say about the market)
## (d) Barón (the manager's decision, 2026-11-07): the branch run as the counter asks. The countryside customers ask
## for any product of the trade (Clientele._products), so it keeps COUNTER_STOCK of each it can make instead of looping
## one recipe (customers left «no_product» and its fame fell); one «any» hand forges and serves; the errands on their
## way count as stock (it bought the same coal every minute); the craft and the upgrade of every intermediate step are
## checked (the decorative sword's steel, craft 6 and forge_production_3, stopped the queue). false = as before
## (BOT_VARS branch_mix=0).
var mix: bool = true


## The management orders of the branch this minute (no walking): build it, hire, roles, queue, counter.
func manage(sim: Sim, actor: String, fam: String, home: String, reserve: int, first_ready: bool = true) -> Array:
	var out: Array = []
	var st := sim.state
	home_bld = home
	if bld != "" and (not st.buildings.has(bld) or str(st.buildings[bld].get("owner", "")) != fam):
		bld = ""  # pulled down, sold, seized
		opened = -1
	if bld == "":
		bld = _adopt(sim, fam, home)
	if bld == "":
		if closed:
			why_not = "lost_money"
			return out
		if not first_ready:
			why_not = "tavern_first"   # the Taberna-Posada pays 3-4 times a forge: it comes first
			return out
		var o := _build(sim, actor, fam, reserve)
		if not o.is_empty():
			out.append(o)
		return out
	if str(st.buildings[bld].get("state", "")) == "construction":
		return out
	var today := Clock.day(int(st.clock["minute"]))
	if opened < 0:
		opened = today
	if today - opened >= JUDGE_DAYS:
		var n := Bankruptcy.net(sim, fam, bld, today - JUDGE_DAYS, today - 1)
		if n < 0:
			return _close(sim, actor, n)
	for o: Dictionary in [_hire(sim, actor, fam, reserve), _role(sim, actor), _queue(sim, actor),
			_upgrade(sim, actor, fam, reserve)]:
		if not o.is_empty():
			out.append(o)
	return out


## A workshop of its trade the family already has besides `home` (the branch of a loaded game).
func _adopt(sim: Sim, fam: String, home: String) -> String:
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		var x: Dictionary = sim.state.buildings[b]
		if b != home and str(x.get("owner", "")) == fam and str(x.get("type", "")) == TYPE:
			return b
	return ""


func _build(sim: Sim, actor: String, fam: String, reserve: int) -> Dictionary:
	if not Plots.room_for(sim, fam, TYPE):
		why_not = "title_limit"
		return {}
	var today := Clock.day(int(sim.state.clock["minute"]))
	if today < JUDGE_DAYS or Bankruptcy.net(sim, fam, home_bld, today - JUDGE_DAYS, today - 1) < HOME_NET:
		why_not = "home_not_earning"
		return {}
	if Construction.daily_net(sim, TYPE) <= 0.0:
		why_not = "not_worth_it"
		return {}
	var best := {}
	for p: Dictionary in Plots.all(sim):
		if not Plots.is_free(p) or not TYPE in Plots.types_for(sim, p):
			continue
		var q := Plots.quote(sim, p, TYPE)
		if best.is_empty() or int(q["price"]) < int(best["price"]) or (int(q["price"]) == int(best["price"])
				and str(p["id"]) < str(best["plot"])):
			best = {"plot": str(p["id"]), "price": int(q["price"])}
	if best.is_empty():
		why_not = "no_plot"
		return {}
	if Money.gold(sim.state, fam) < reserve + int(best["price"]) + BUILD_SPARE:
		why_not = "gold_short"
		return {}
	var r := Plots.can_build(sim, actor, str(best["plot"]), TYPE)
	if not r["ok"]:
		why_not = str(r["reason"])
		return {}
	why_not = ""
	if OS.is_debug_build():
		print("[BotBranch] día %d: construye una %s en %s por %d" % [Clock.day(int(sim.state.clock["minute"])), TYPE,
			best["plot"], int(best["price"])])
	return {"type": "build", "actor": actor, "plot": str(best["plot"]), "building_type": TYPE}


func _hire(sim: Sim, actor: String, fam: String, reserve: int) -> Dictionary:
	if Staff.free_slots(sim.state, bld) <= 0 or Staff.employees_of(sim.state, bld).size() >= (MIX_STAFF if mix else STAFF):
		return {}
	var best := {}
	for c: Dictionary in Staff.candidates(sim, actor, bld):
		if str(c["status"]) != "ok":
			continue
		if best.is_empty() or int(c["stats"]["craft"]) > int(best["stats"]["craft"]):
			best = c
	if best.is_empty() or Money.gold(sim.state, fam) < reserve + HIRE_DAYS * int(best["wage"]):
		return {}
	return {"type": "hire", "actor": actor, "building": bld, "candidate": str(best["character"])}


## The better craftsman forges ("any"); with the counter and a second hand, the other one sells at it.
func _role(sim: Sim, actor: String) -> Dictionary:
	var staff: Array = Staff.employees_of(sim.state, bld)
	staff.sort_custom(func(a: String, b: String) -> bool:
		var ca := int(sim.state.characters[a].get("stats", {}).get("craft", 0))
		var cb := int(sim.state.characters[b].get("stats", {}).get("craft", 0))
		return ca > cb or (ca == cb and a < b))
	var want := {}
	for c: String in staff:
		want[c] = "any"
	if staff.size() >= 2 and Upgrades.flag(sim, bld, "counter_sales"):
		want[staff[staff.size() - 1]] = "counter"
	for c: String in want:
		var job: Variant = sim.state.characters[c].get("job")
		if job is Dictionary and str((job as Dictionary).get("role", "")) != str(want[c]):
			return {"type": "set_role", "actor": actor, "employee": c, "role": want[c]}
	return {}


## It lost money over JUDGE_DAYS: its employee goes (fire) and, once nobody works there, it is pulled down (the
## refund); the family opens no other.
func _close(sim: Sim, actor: String, n: int) -> Array:
	var fire: Array = []
	for e: String in Staff.employees_of(sim.state, bld):
		if int(sim.state.characters[e]["job"].get("end_day", -1)) < 0:
			fire.append({"type": "fire", "actor": actor, "employee": e})
	if not fire.is_empty() or not Staff.employees_of(sim.state, bld).is_empty():
		return fire   # they leave at the end of the day; it is pulled down once they are gone
	var r := Plots.can_demolish(sim, actor, bld)
	if not r["ok"]:
		return []
	if OS.is_debug_build():
		print("[BotBranch] día %d: %s pierde %d en %d días: lo derriba" % [Clock.day(int(sim.state.clock["minute"])),
			bld, n, JUDGE_DAYS])
	closed = true
	return [{"type": "demolish", "actor": actor, "building": bld}]


## The recipe the branch loops: the best margin of its building that its employee's craft allows and whose raw
## materials are all among `raw` (what the head buys anyway: an errand brings them). With mix, the product of those
## (every step within the forger's craft) the counter has fewest of, under COUNTER_STOCK; "" when all are stocked.
func recipe(sim: Sim) -> String:
	if mix:
		return _restock(sim)
	var craft := 99
	for c: String in Staff.employees_of(sim.state, bld):
		craft = mini(craft, int(sim.state.characters[c].get("stats", {}).get("craft", 0)))
	if craft == 99:
		return ""
	var best := ""
	var best_m := -999999
	var ids: Array = sim.catalog.recipes().keys()
	ids.sort()
	for rid: String in ids:
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) != TYPE or int(r.get("min_craft", 0)) > craft:
			continue
		if not str(r.get("zone", "")) in (sim.state.buildings[bld].get("zones", {}) as Dictionary).keys().map(
				func(z: Variant) -> String: return str(z).trim_suffix("_2")):
			continue
		var need := {}
		_raw_of(sim, rid, 1.0, need, 0)
		if not raw.is_empty() and need.keys().any(func(i: Variant) -> bool: return not str(i) in raw):
			continue
		var m := RivalAI.margin(sim, rid)
		if m > best_m:
			best_m = m
			best = rid
	return best


## mix: the products the branch can make: the forge's recipes of a «product» whose every step (the intermediate
## pieces made here too) the best hand's craft allows, whose stations it has and whose raw materials are in `raw`.
func products(sim: Sim) -> Array:
	var craft := -1
	for c: String in Staff.employees_of(sim.state, bld):
		craft = maxi(craft, int(sim.state.characters[c].get("stats", {}).get("craft", 0)))
	var out: Array = []
	if craft < 0:
		return out
	var zones: Array = (sim.state.buildings[bld].get("zones", {}) as Dictionary).keys().map(
		func(z: Variant) -> String: return str(z).trim_suffix("_2"))
	var ids: Array = sim.catalog.recipes().keys()
	ids.sort()
	for rid: String in ids:
		var r: Dictionary = sim.catalog.recipes()[rid]
		var item := str(r.get("output", {}).get("item", ""))
		if str(r.get("building", "")) != TYPE or str(sim.catalog.item(item).get("category", "")) != "product":
			continue
		if not _can_make(sim, rid, craft, zones, 0):
			continue
		var need := {}
		_raw_of(sim, rid, 1.0, need, 0)
		if not raw.is_empty() and need.keys().any(func(i: Variant) -> bool: return not str(i) in raw):
			continue
		out.append(rid)
	return out


func _can_make(sim: Sim, rid: String, craft: int, zones: Array, depth: int) -> bool:
	var r: Dictionary = sim.catalog.recipes()[rid]
	if int(r.get("min_stat", r.get("min_craft", 1))) > craft or not str(r.get("zone", "")) in zones:
		return false
	if str(r.get("requires_upgrade", "")) != "" and not str(r["requires_upgrade"]) in \
			(sim.state.buildings[bld].get("upgrades", []) as Array):
		return false
	for inp: Dictionary in r.get("inputs", []):
		var sub := _made_here(sim, str(inp["item"]))
		if sub != "" and depth < 3 and not _can_make(sim, sub, craft, zones, depth + 1):
			return false
	return true


func _made_here(sim: Sim, item: String) -> String:
	var ids: Array = sim.catalog.recipes().keys()
	ids.sort()
	for k: String in ids:
		var x: Dictionary = sim.catalog.recipes()[k]
		if str(x.get("building", "")) == TYPE and str(x.get("output", {}).get("item", "")) == item:
			return k
	return ""


## mix: the product the counter has fewest of (under COUNTER_STOCK), the better margin first on a tie.
func _restock(sim: Sim) -> String:
	var inv: Dictionary = sim.state.buildings[bld]["inventory"]
	var best := ""
	var best_n := COUNTER_STOCK
	var best_m := -999999
	for rid: String in products(sim):
		var n := Inventory.count(inv, str(sim.catalog.recipes()[rid]["output"]["item"]))
		var m := RivalAI.margin(sim, rid)
		if n < best_n or (n == best_n and best != "" and m > best_m):
			best = rid
			best_n = n
			best_m = m
	return best


func _queue(sim: Sim, actor: String) -> Dictionary:
	if Staff.employees_of(sim.state, bld).is_empty():
		return {}
	var q: Dictionary = sim.state.buildings[bld].get("queue", {})
	if not (q.get("entries", []) as Array).is_empty():
		return {}
	var rid := recipe(sim)
	if rid == "":
		return {}
	if mix:
		var have := Inventory.count(sim.state.buildings[bld]["inventory"], str(sim.catalog.recipes()[rid]["output"]["item"]))
		return {"type": "queue_add", "actor": actor, "building": bld, "recipe": rid, "qty": maxi(1, COUNTER_STOCK - have)}
	return {"type": "queue_add", "actor": actor, "building": bld, "recipe": rid, "qty": WorkQueue.INFINITE}


## The next of UPGRADES it has not got, when it is available (its materials in the branch's storage) and paid.
func _upgrade(sim: Sim, actor: String, fam: String, reserve: int) -> Dictionary:
	if Upgrades.blocks(sim.state, bld):
		return {}
	for id: String in (MIX_UPGRADES if mix else UPGRADES):
		if id in (sim.state.buildings[bld].get("upgrades", []) as Array):
			continue
		var gold := int(sim.catalog.upgrade(id).get("cost", {}).get("gold", 0))
		if Money.gold(sim.state, fam) < reserve + gold or Upgrades.status_of(sim, actor, bld, id) != "available":
			return {}
		return {"type": "buy_upgrade", "actor": actor, "building": bld, "upgrade": id}
	return {}


## What the branch's storage lacks: the raw materials of STOCK_UNITS pieces of its recipe (its intermediate pieces
## expanded through the building's own recipes) and the counter's materials. {item: qty}.
func needs(sim: Sim) -> Dictionary:
	var out := {}
	if bld == "" or not sim.state.buildings.has(bld) or str(sim.state.buildings[bld].get("state", "")) == "construction":
		return out
	var inv: Dictionary = sim.state.buildings[bld]["inventory"]
	var want := {}
	var rid := recipe(sim)
	if mix:
		var q: Array = sim.state.buildings[bld].get("queue", {}).get("entries", [])
		rid = str(q[0].get("recipe", "")) if not q.is_empty() else rid
		if rid == "" and not products(sim).is_empty():
			rid = str(products(sim)[0])
	if rid != "":
		_raw_of(sim, rid, float(STOCK_UNITS), want, 0)
	for id: String in (MIX_UPGRADES if mix else UPGRADES):
		if id in (sim.state.buildings[bld].get("upgrades", []) as Array):
			continue
		for c: Dictionary in sim.catalog.upgrade(id).get("cost", {}).get("items", []):
			want[str(c["item"])] = float(want.get(str(c["item"]), 0.0)) + float(c["qty"])
		break   # one upgrade's materials at a time
	var coming := {}
	if mix:   # the errands on their way count (Market: state.deliveries)
		for d: Dictionary in sim.state.deliveries:
			if str(d.get("to", "")) == bld:
				coming[str(d["item"])] = int(coming.get(str(d["item"]), 0)) + int(d["qty"])
	for item: String in want:
		var lack := ceili(float(want[item])) - Inventory.count(inv, item) - int(coming.get(item, 0))
		if lack > 0:
			out[item] = lack
	return out


func _raw_of(sim: Sim, rid: String, units: float, want: Dictionary, depth: int) -> void:
	var r: Dictionary = sim.catalog.recipes()[rid]
	var per := float(r.get("output", {}).get("qty", 1))
	for inp: Dictionary in r.get("inputs", []):
		var item := str(inp["item"])
		var qty := units * float(inp["qty"]) / maxf(per, 1.0)
		var sub := ""
		for k: String in sim.catalog.recipes():
			var x: Dictionary = sim.catalog.recipes()[k]
			if str(x.get("building", "")) == TYPE and str(x.get("output", {}).get("item", "")) == item:
				sub = k
		if sub != "" and depth < 3:
			_raw_of(sim, sub, qty, want, depth + 1)
		else:
			want[item] = float(want.get(item, 0.0)) + qty


## At a stall anyway (the head buying for its own forge): an errand of what the branch lacks and this stall sells,
## sent to the branch's storage. {} if nothing.
func supply(sim: Sim, actor: String, fam: String, reserve: int) -> Dictionary:
	var stall := Market.stall_at(sim, actor)
	if stall == "":
		return {}
	var need := needs(sim)
	var items: Array = need.keys()
	items.sort()
	for item: String in items:
		if RivalAI.stall_for(sim, item) != stall:
			continue
		var n := mini(int(need[item]), Market.max_buy(sim, actor, stall, item, Inventory.NORMAL, bld))
		var cost := n * Market.price(sim, item, Inventory.NORMAL, "buy")
		if n > 0 and Money.gold(sim.state, fam) - cost >= reserve:
			return {"type": "buy", "actor": actor, "stall": stall, "item": item, "quality": Inventory.NORMAL, "qty": n,
				"deliver_to": bld}
	return {}
