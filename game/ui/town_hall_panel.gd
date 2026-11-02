class_name TownHallPanel
extends PanelContainer
## The town hall (GDD 4.12.2, H9): the family's title and reputation, the next title with its cost and requirements
## (met in green, pending in red: have / need), what it opens, and «Ask for the title» (request_title), disabled with
## the reason in its tooltip (Titles.status). Opens when the person sent there stands on its service tile; closes with
## ESC (the HUD), X, or when they leave. Only gives the order.

signal closed

var order_sink: Callable = Callable()
var sim: Sim
var actor: String = ""
var _sig: String = ""
var _bound: bool = false


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%CloseButton as Button).pressed.connect(close)
	(%AskButton as Button).pressed.connect(_ask)


func open_for(s: Sim, who: String) -> void:
	_bind()
	sim = s
	actor = who
	(%Title as Label).text = SimQuery.t_("ui.town_hall.title")
	(%AskButton as Button).text = SimQuery.t_("ui.town_hall.ask")
	visible = true
	refresh(true)
	ViewConfig.info("TownHallPanel", "open (actor=%s)" % who)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(_delta: float) -> void:
	if visible and sim != null:
		if Titles.at_town_hall(sim, actor):
			refresh()
		else:
			close()


func refresh(force: bool = false) -> void:
	if sim == null:
		return
	var st := Titles.status(sim, actor)
	var fam := str(st["family"])
	var sig := str(st) + "|" + str(Reputation.of(sim.state, fam))
	if sig == _sig and not force:
		return
	_sig = sig
	(%CurrentLabel as Label).text = SimQuery.t_("ui.town_hall.current") % [SimQuery.title_name(str(st["current"])),
		Reputation.of(sim.state, fam)]
	var nx := str(st["next"])
	var list := %ReqList as VBoxContainer
	for c: Node in list.get_children():
		list.remove_child(c)
		c.queue_free()
	(%UnlocksLabel as Label).visible = nx != ""
	if nx == "":
		(%NextLabel as Label).text = SimQuery.t_("ui.town_hall.top")
	else:
		(%NextLabel as Label).text = SimQuery.t_("ui.town_hall.next") % [SimQuery.title_name(nx), int(st["cost"])]
		for r: Dictionary in st["requirements"]:
			var l := Label.new()
			l.name = str(r["kind"])
			var ok := bool(r["ok"])
			var mark := SimQuery.t_("ui.town_hall.ok" if ok else "ui.town_hall.missing")
			var what := SimQuery.t_("ui.town_hall.req_" + str(r["kind"]))
			if str(r["kind"]) == "event":  # a yes / no requirement
				l.text = SimQuery.t_("ui.town_hall.req_flag") % [mark, what]
			else:
				l.text = SimQuery.t_("ui.town_hall.req") % [mark, what, int(r["have"]), int(r["need"])]
			l.add_theme_color_override("font_color", Color(0.55, 0.85, 0.5) if ok else Color(1, 0.55, 0.45))
			list.add_child(l)
		(%UnlocksLabel as Label).text = SimQuery.t_("ui.town_hall.unlocks") % unlocks_text(sim.catalog, nx)
	var why := str(st["reason"])
	var ask := %AskButton as Button
	ask.visible = nx != ""
	ask.disabled = why != ""
	ask.tooltip_text = SimQuery.reason_text(why) if why != "" else SimQuery.t_("ui.town_hall.ask_tip") % int(st["cost"])
	reset_size()


## What a title opens, as text: «2 buildings, vote, minor offices».
static func unlocks_text(catalog: Catalog, title: String) -> String:
	var u: Dictionary = catalog.titles().get(title, {}).get("unlocks", {})
	var parts: PackedStringArray = []
	var mb: Variant = u.get("max_buildings", null)
	parts.append(SimQuery.t_("ui.town_hall.buildings_any") if mb == null else SimQuery.t_("ui.town_hall.buildings") % int(mb))
	if bool(u.get("vote", false)):
		parts.append(SimQuery.t_("ui.town_hall.vote"))
	var rank := str(u.get("office_rank", "none"))
	if rank != "none":
		parts.append(SimQuery.t_("ui.town_hall.offices_" + rank))
	return ", ".join(parts)


func _ask() -> void:
	if order_sink.is_valid():
		ViewConfig.info("TownHallPanel", "request_title (actor=%s)" % actor)
		order_sink.call({"type": "request_title", "actor": actor})
