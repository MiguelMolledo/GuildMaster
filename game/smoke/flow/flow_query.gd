class_name FlowQuery
extends RefCounted
## What a flow's checks can read (data/flows/*.json "expect": expressions over `q`, e.g. "q.gold() < q.was('gold')").
## Reads only: the state, the views and what the step recorded (orders given by the UI, sim events). Probes that take
## no argument or one text can be used with was()/delta(), which give the value at the start of the step.

var app: Node
var drv: UiDriver
var step_orders: Array = []    # [{type, via}] orders the UI gave during this step (Game.order_given)
var step_events: Array = []    # sim events published during this step
var flow_orders: Array = []    # the whole flow's
var _was: Dictionary = {}


func _init(a: Node, d: UiDriver) -> void:
	app = a
	drv = d


func sim() -> Sim:
	return Game.sim


func st() -> WorldState:
	return Game.sim.state if Game.sim != null else null


## Records the value of every was()/delta() probe that the checks of a step use, before the step runs.
func snapshot(exprs: Array) -> void:
	_was.clear()
	var re := RegEx.create_from_string("q\\.(?:was|delta)\\('([a-z_]+)'(?:\\s*,\\s*'([^']*)')?\\)")
	for e: Variant in exprs:
		for m: RegExMatch in re.search_all(str(e)):
			var key := m.get_string(1) + "|" + m.get_string(2)
			_was[key] = _probe(m.get_string(1), m.get_string(2))


func _probe(name: String, arg: String) -> Variant:
	if not has_method(name):
		return null
	return call(name, arg) if arg != "" else call(name)


func was(name: String, arg: String = "") -> Variant:
	return _was.get(name + "|" + arg)


func delta(name: String, arg: String = "") -> float:
	return float(_probe(name, arg)) - float(_was.get(name + "|" + arg, 0))


# --- who and where --------------------------------------------------------------------------------------------------

func fam() -> String:
	return SimQuery.player_family(st()) if st() != null else ""


## The active person (the selected one of the player's family).
func who() -> String:
	return str(app.hud().active_person())


func selected() -> String:
	return str(app.world().selected_id)


func ch(id: String = "") -> Dictionary:
	return st().characters.get(id if id != "" else who(), {})


func location() -> String:
	return str(ch().get("location", ""))


func interior() -> String:
	return str(app.interior_building)


func tile() -> Array:
	return ch().get("position", [])


## The player's own building of `type` (forge, tavern...), "" if none.
func own(type: String) -> String:
	for b: String in st().buildings:
		if str(st().buildings[b]["type"]) == type and SimQuery.building_family(st(), b) == fam():
			return b
	return ""


## The first building of `type` (any owner).
func building(type: String) -> String:
	var ids: Array = st().buildings.keys()
	ids.sort()
	for b: String in ids:
		if str(st().buildings[b]["type"]) == type:
			return b
	return ""


func owns(type: String) -> bool:
	return own(type) != ""


# --- money, items ---------------------------------------------------------------------------------------------------

func gold() -> int:
	return Money.gold(st(), fam())


func debt() -> int:
	var total := 0
	for l: Dictionary in SimQuery.loans_of(Game.sim, fam()):
		total += int(l.get("outstanding", 0))
	return total


func loans() -> int:
	return SimQuery.loans_of(Game.sim, fam()).size()


func bag(item: String) -> int:
	return Inventory.count(ch().get("inventory", {}), item)


## Items of `item` in the building shown inside, or else in the player's forge.
func storage(item: String) -> int:
	var b := interior() if interior() != "" else own("forge")
	if b == "":
		return 0
	return Inventory.count(st().buildings[b].get("inventory", {}), item)


## The market of `stall` sells now (not closed at night).
func market_open(stall: String = "resources") -> bool:
	return bool(SimQuery.market_offers(Game.sim, who(), stall).get("open", false))


func deliveries() -> int:
	return st().deliveries.size()


# --- time -----------------------------------------------------------------------------------------------------------

func minute() -> int:
	return int(st().clock["minute"])


func day() -> int:
	return int(Game.sim.now()["day"])


func hour() -> int:
	return int(Game.sim.now()["hour"])


func speed() -> int:
	return Game.speed


func paused() -> bool:
	return Game.paused


# --- business -------------------------------------------------------------------------------------------------------

func staff(type: String = "forge") -> int:
	var b := own(type)
	return SimQuery.employees(Game.sim, b).size() if b != "" else 0


func queue_len(type: String = "forge") -> int:
	var b := own(type)
	if b == "":
		return 0
	return (SimQuery.queue_view(Game.sim, b).get("entries", []) as Array).size()


func upgrades(type: String = "forge") -> int:
	var b := own(type)
	if b == "":
		return 0
	var n := 0
	n += (st().buildings[b].get("upgrades", []) as Array).size()
	n += 1 if not SimQuery.upgrade_works(Game.sim, b).is_empty() else 0
	return n


## The first upgrade of the player's forge that can be bought now ("" if none).
func upgrade_available(type: String = "forge") -> String:
	var b := own(type)
	if b == "":
		return ""
	var tree: Dictionary = SimQuery.upgrade_tree(Game.sim, who(), b)
	for br: Dictionary in tree.get("branches", []):
		for u: Dictionary in br.get("upgrades", []):
			if str(u.get("status", "")) == "available":
				return str(u["id"])
	return ""


func contracts_mine() -> int:
	var n := 0
	for c: Dictionary in st().contracts.get("accepted", []):
		if str(c.get("family", "")) == fam():
			n += 1
	return n


## The first open contract of the board whose client or item is `what` ("" if none).
func board_id(what: String) -> String:
	for c: Dictionary in st().contracts.get("board", []):
		if str(c.get("client", "")) == what or str(c.get("item", "")) == what:
			return str(c["id"])
	return ""


## The first open contract of the board that belongs to a festival (a wedding's gift...), "" if none.
func board_festival() -> String:
	for c: Dictionary in st().contracts.get("board", []):
		if str(c.get("festival_def", "")) != "":
			return str(c["id"])
	return ""


## The player's accepted contract whose client or item is `what` ("" if none).
func mine_id(what: String) -> String:
	for c: Dictionary in st().contracts.get("accepted", []):
		if str(c.get("family", "")) == fam() and (str(c.get("client", "")) == what or str(c.get("item", "")) == what):
			return str(c["id"])
	return ""


## Forja viva (03b §3b.2): what its screen shows, read as a player reads it (the colour, the template, the medium).
func _live() -> LiveForgeScreen:
	return app.interior().live_screen() if app.interior().has_method("live_screen") else null


func live_open() -> bool:
	return _live() != null and _live().visible


func live_stage() -> String:
	var b := interior() if interior() != "" else own("forge")
	return str(LiveForge.view(Game.sim, b, "anvil").get("stage", "")) if live_open() else ""


func _live_part() -> Dictionary:
	var b := interior() if interior() != "" else own("forge")
	var job: Variant = st().buildings[b]["zones"]["anvil"].get("job")
	return (job as Dictionary).get("live", {}) if job is Dictionary else {}


func _live_def() -> Dictionary:
	return LiveForge.recipe_def(Game.sim, _live().recipe) if live_open() else {}


## The iron shows the colour the recipe wants (or past it): time to pull it.
func live_heat_ok() -> bool:
	if not live_open():
		return false
	var want := (Game.sim.catalog.live_forge["heat_colors"] as Array).find(str(_live_def().get("heat", "cherry")))
	return _live().heat_index >= want


## The next strike of the template (strong / measured / finish).
func live_strike() -> String:
	var t: Array = LiveForge.template_of(Game.sim, _live_def(), _live_part())
	var done := (_live_part().get("strikes", []) as Array).size()
	return str(t[done]) if done < t.size() else ""


func live_quench() -> String:
	return LiveForge.wanted_quench(_live_def(), _live_part())


## The production window of the station: open while it blinks for the master touch.
func touch_open(zone: String) -> bool:
	var b := interior() if interior() != "" else own("forge")
	return bool(SimQuery.job_view(Game.sim, b, zone).get("window_open", false))


func working(zone: String) -> bool:
	var b := interior() if interior() != "" else own("forge")
	return not SimQuery.job_view(Game.sim, b, zone).is_empty()


## The quality of the first stack of `item` in the bag (-1 if none).
func bag_quality(item: String) -> int:
	for s: Dictionary in ch().get("inventory", {}).get("stacks", []):
		if str(s["item"]) == item:
			return int(s["quality"])
	return -1


func contracts_done() -> int:
	return events("contract_delivered")


# --- family, politics, justice, travel ------------------------------------------------------------------------------

func title() -> String:
	return Titles.current(Game.sim, fam())


func title_rank() -> int:
	return Titles.rank(Game.sim, title())


func rep() -> int:
	return Reputation.of(st(), fam())


## The head of the rival smith's family (the AI forge).
func rival() -> String:
	for f: String in st().families:
		if str(st().families[f].get("ai_profile", "")) == "rival_smith":
			return str(st().families[f].get("head", ""))
	return ""


## A townsperson seen in the town now (not of the player's family, out in the street), nearest to the active
## person; "" if none.
func npc_near() -> String:
	var w: WorldView = app.world()
	var me: Node2D = w.view_of(who())
	var best := ""
	var best_d := INF
	var ids: Array = st().characters.keys()
	ids.sort()
	for id: String in ids:
		var c: Dictionary = st().characters[id]
		var v: Node2D = w.view_of(id)
		if str(c.get("family", "")) == fam() or str(c.get("location", "")) != "" or v == null or not v.is_visible_in_tree():
			continue
		var d := v.position.distance_to(me.position) if me != null else 0.0
		if d < best_d:
			best_d = d
			best = id
	return best


## A beggar out in the street and seen in the town ("" if none).
func beggar() -> String:
	var w: WorldView = app.world()
	var ids: Array = st().characters.keys()
	ids.sort()
	for id: String in ids:
		var c: Dictionary = st().characters[id]
		if str((c.get("visitor", {}) as Dictionary).get("kind", "")) == "beggar" and str(c.get("location", "")) == "" \
				and w.view_of(id) != null and w.view_of(id).is_visible_in_tree():
			return id
	return ""


## The tutorial's chapter and step now ("" when none plays).
func tutorial_step() -> String:
	var t: Variant = app.call("tutorial")
	if t == null or str(t.get("chapter_id")) == "":
		return ""
	return "%s:%s" % [t.get("chapter_id"), t.get("index")]


## Whether unlock `id` of 03b is open for the player's family (the jugador pass waits for staff, upgrades...).
func unlocked(id: String) -> bool:
	return Game.sim != null and Unlocks.is_open(st(), fam(), id)


## Whether the tutorial's chapter `id` was played to its end.
func chapter_done(id: String) -> bool:
	var t: Variant = app.call("tutorial")
	return t != null and id in (t.call("done_chapters") as Array)


## The tutorial's step now as "chapter:step_id" ("" when it does not run; "chapter:end" on its end card): the jugador
## pass follows the tutorial as a new player.
func tut() -> String:
	var t: Variant = app.call("tutorial")
	if t == null or str(t.get("chapter_id")) == "":
		return ""
	if str(t.get("phase")) == "finished":
		return "%s:end" % t.get("chapter_id")
	var st: Dictionary = t.call("step")
	return "%s:%s" % [t.get("chapter_id"), st.get("id", t.get("index"))]


## The tutorial card's text now ("" when it is not shown).
func tut_text() -> String:
	var t: Variant = app.call("tutorial")
	var c := (t as Node).get_node_or_null("Overlay/Card") as Control if t != null else null
	if c == null or not c.is_visible_in_tree():
		return ""
	var out: PackedStringArray = []
	for l: Node in c.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			out.append((l as Label).text)
	for l: Node in c.find_children("*", "RichTextLabel", true, false):
		if (l as RichTextLabel).is_visible_in_tree():
			out.append((l as RichTextLabel).get_parsed_text())
	return " | ".join(out)


## The name of character `id` (for a "has" or "row" in a spec).
func name_of(id: String) -> String:
	return str(st().characters.get(id, {}).get("name", ""))


## The first child (alive) of the player's family head, "" if none.
func child() -> String:
	for id: String in st().characters:
		var c: Dictionary = st().characters[id]
		if str(c.get("family", "")) == fam() and bool(c.get("alive", true)) and str(id) != who() \
				and (c.get("parents", []) as Array).has(who()):
			return id
	return ""


func heir() -> String:
	return str(st().families.get(fam(), {}).get("heir", ""))


func spouse(id: String = "") -> String:
	return str(ch(id).get("spouse", ""))


func married() -> bool:
	return spouse() != ""


func relation(other: String) -> Dictionary:
	var a := who()
	var k := "%s|%s" % ([a, other] if a < other else [other, a])
	return st().relationships.get(k, {})


func offices_held() -> int:
	var n := 0
	for o: String in st().offices:
		for s: Dictionary in st().offices[o].get("seats", []):
			var h := str(s.get("holder", ""))
			if h != "" and str(st().characters.get(h, {}).get("family", "")) == fam():
				n += 1
	return n


func candidate() -> bool:
	for el: Dictionary in st().elections:
		for c: Dictionary in el.get("candidates", []):
			if str(st().characters.get(str(c.get("character", "")), {}).get("family", "")) == fam():
				return true
	return false


## The player's family has a candidate in an election whose campaign is on now.
func campaign() -> bool:
	for el: Dictionary in st().elections:
		for c: Dictionary in el.get("candidates", []):
			if str(st().characters.get(str(c.get("character", "")), {}).get("family", "")) == fam() and Elections.in_campaign(Game.sim, el):
				return true
	return false


func trials_open() -> int:
	var n := 0
	for t: Dictionary in st().trials:
		if str(t.get("status", "")) in Tribunal.OPEN:
			n += 1
	return n


func trips() -> int:
	return (st().region.get("trips", {}) as Dictionary).size()


func away() -> bool:
	return Region.is_away(st(), who())


func carts() -> int:
	return Caravans.carts(Game.sim, fam())


func caravans() -> int:
	return (st().region.get("caravans", []) as Array).size()


func treaties() -> int:
	var t: Variant = st().region.get("treaties", {})
	return (t as Dictionary).size() if t is Dictionary else (t as Array).size() if t is Array else 0


func duels_open() -> int:
	return (st().duels.get("open", {}) as Dictionary).size()


func ending() -> String:
	return str(st().ending.get("kind", ""))


func lang() -> String:
	return TranslationServer.get_locale()


func setting(key: String) -> Variant:
	return Settings.value(key)


func saves() -> int:
	var n := 0
	for s: String in Game.SLOTS:
		if FileAccess.file_exists("%s/%s.json" % [Game.SAVE_DIR, s]):
			n += 1
	return n


func map() -> String:
	return st().map_id


# --- what the step recorded -----------------------------------------------------------------------------------------

## The UI gave an order of `type` at some point of the flow.
func flow_has(type: String) -> bool:
	for o: Dictionary in flow_orders:
		if str(o["type"]) == type:
			return true
	return false


## The UI gave an order of `type` during this step.
func order(type: String) -> bool:
	for o: Dictionary in step_orders:
		if str(o["type"]) == type:
			return true
	return false


func event(type: String) -> bool:
	return events(type) > 0


func events(type: String) -> int:
	var n := 0
	for e: Dictionary in step_events:
		if str(e.get("type", "")) == type:
			n += 1
	return n


## The refusals of this step for the player's family, as "type:reason" ("" if none).
func refused() -> String:
	var out: Array = []
	for e: Dictionary in step_events:
		if str(e.get("type", "")) == "order_refused" and str(st().characters.get(str(e.get("actor", "")), {}).get("family", "")) == fam():
			out.append("%s:%s" % [e.get("order", e.get("order_type", "")), e.get("reason", "")])
	return ", ".join(out)


# --- the screen -----------------------------------------------------------------------------------------------------

func visible(name: String) -> bool:
	var n := drv.node(name)
	return n != null and n is CanvasItem and (n as CanvasItem).is_visible_in_tree()


func shown(spec: Variant) -> bool:
	return not drv.find(spec).has("error")


## The control of `spec` is shown and disabled.
func disabled(spec: Variant) -> bool:
	var f := drv.find(spec)
	return not f.has("error") and f["node"] is BaseButton and (f["node"] as BaseButton).disabled


## The tooltip of the control of `spec` ("" if none or not found): the reason of a disabled button.
func tip(spec: Variant) -> String:
	var f := drv.find(spec)
	return "" if f.has("error") else (f["node"] as Control).tooltip_text


func text(name: String) -> String:
	var n := drv.node(name)
	return UiDriver.text_of(n as Control) if n is Control else ""


func has_text(t: String) -> bool:
	for c: Control in drv.all_controls():
		if c.is_visible_in_tree() and UiDriver.text_of(c).to_lower().contains(t.to_lower()):
			return true
	return false


func menu() -> bool:
	return bool(app.menu_open())


func focus() -> String:
	var f := drv.root.gui_get_focus_owner()
	return str(f.name) if f != null else ""
