class_name SuccessionCard
extends MenuScreen
## The succession card (docs/ui/mecanicas/familia.md §2-3, §6): when the head of the player's family dies and an heir
## takes over (event inheritance), a letter over a veil: the family's ribbon and name, the dead with its cross and age,
## the heir with the crown, «cabeza · generación N»; what is inherited (the family's buildings with their upgrades and
## employees, the gold, the title) and what is not (the offices the dead held: office_left died of the same step); the
## regent if the heir is a minor. Decision (a) of the document: the game pauses while it is shown and «Continuar con …»
## puts the pause back as it was; «Ver el árbol» does the same and asks for the tree. The app shows it.

signal continued
signal tree_requested

var game: Node = null
var data: Dictionary = {}     # what the card says (tests): {from, heir, regent, buildings, gold, title, vacant}
var _was_paused: bool = false
var _bound: bool = false


func _ready() -> void:
	esc_goes_back = false
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	esc_goes_back = false
	if game == null:
		game = get_node_or_null("/root/Game")
	(%ContinueButton as Button).pressed.connect(func() -> void:
		finish()
		continued.emit())
	(%TreeButton as Button).pressed.connect(func() -> void:
		finish()
		tree_requested.emit())


## Fills the card with the inheritance event `e` and the events of its step (for the vacant offices) and shows it,
## pausing the game.
func show_for(sim: Sim, e: Dictionary, events: Array = []) -> void:
	_bind()
	var st := sim.state
	var fam := str(e.get("family", ""))
	var from := str(e.get("from", ""))
	var heir := str(e.get("heir", ""))
	var regent := str(e.get("regent", ""))
	var f: Dictionary = st.families.get(fam, {})
	var dead: Dictionary = st.characters.get(from, {})
	var h: Dictionary = st.characters.get(heir, {})
	var slot := %RibbonSlot as Control
	SocialKit.clear(slot)
	slot.add_child(SocialKit.ribbon(st, fam, Vector2(10, 22)))
	(%Title as Label).text = SimQuery.t_("ui.succession.title") % str(f.get("name", ""))
	_portrait(%DeadSlot as Control, st, from, {})
	_portrait(%HeirSlot as Control, st, heir, {"heir": true, "controlled": true})
	(%DeadName as Label).text = str(dead.get("name", from))
	(%DeadLine as Label).text = SimQuery.t_("ui.succession.died_at") % Kin.age(sim, from)
	(%HeirName as Label).text = str(h.get("name", heir))
	(%HeirLine as Label).text = SimQuery.t_("ui.succession.head_gen") % int(e.get("generation", f.get("generation", 1)))
	var parts: PackedStringArray = []
	var blds: Array = []
	for b: String in st.buildings:
		if str(st.buildings[b].get("owner", "")) == fam:
			blds.append(b)
	blds.sort()
	for b: String in blds:
		var bd: Dictionary = st.buildings[b]
		var ups := (bd.get("upgrades", []) as Array).size()
		var emps := SimQuery.employees(sim, b).size()
		var n := SimQuery.building_name(st, sim.catalog, b)
		if ups > 0 or emps > 0:
			n += " " + SimQuery.t_("ui.succession.building_detail") % [ups, emps]
		parts.append(n)
	parts.append(SimQuery.t_("ui.saves.gold") % MenuKit.gold_text(Money.gold(st, fam)))
	var title := Titles.current(sim, fam)
	parts.append(SimQuery.t_("ui.succession.title_of") % SimQuery.title_name(title))
	(%Inherits as Label).text = " · ".join(parts)
	var vacant: PackedStringArray = []
	for x: Dictionary in events:
		if str(x.get("type", "")) == "office_left" and str(x.get("character", "")) == from:
			vacant.append(SimQuery.t_("ui.succession.vacant") % SimQuery.office_name(str(x.get("office", ""))))
	(%NotInherits as Label).text = ", ".join(vacant) if not vacant.is_empty() else "—"
	if regent != "" and st.characters.has(regent):
		var maj := int(sim.catalog.family.get("life", {}).get("majority_age", 16))
		(%Regent as Label).text = SimQuery.t_("ui.succession.regent") % [str(st.characters[regent].get("name", "")),
			str(h.get("name", "")), maj, maxi(0, maj - Kin.age(sim, heir))]
	else:
		(%Regent as Label).text = SimQuery.t_("ui.succession.no_regent") % str(h.get("name", ""))
	(%InheritsLabel as Label).text = SimQuery.t_("ui.succession.inherits")
	(%NotLabel as Label).text = SimQuery.t_("ui.succession.not_inherits")
	(%RegentLabel as Label).text = SimQuery.t_("ui.succession.regent_label")
	(%PausedLabel as Label).text = SimQuery.t_("ui.succession.paused")
	var cont := SimQuery.t_("ui.succession.continue") % str(h.get("name", ""))
	if regent != "" and st.characters.has(regent):
		cont = SimQuery.t_("ui.succession.continue_regent") % [str(h.get("name", "")), str(st.characters[regent].get("name", ""))]
	(%ContinueButton as Button).text = cont
	(%TreeButton as Button).text = SimQuery.t_("ui.succession.tree")
	data = {"from": from, "heir": heir, "regent": regent, "buildings": blds, "gold": Money.gold(st, fam), "title": title,
		"vacant": vacant}
	if not visible:
		_was_paused = bool(game.get("paused")) if game != null else false
		if game != null:
			game.call("set_paused", true)
	open()
	ViewConfig.info("Succession", "show (%s -> %s, regent=%s, vacant=%s)" % [from, heir, regent, vacant])


func _portrait(slot: Control, st: WorldState, chr: String, flags: Dictionary) -> void:
	SocialKit.clear(slot)
	if st.characters.has(chr):
		var p := SocialKit.portrait(st, chr, flags)
		p.scale = Vector2(2, 2)
		slot.add_child(p)


func default_focus() -> Control:
	return %ContinueButton as Button


## Closes the card and puts the pause back as it was before it.
func finish() -> void:
	close()
	if game != null:
		game.call("set_paused", _was_paused)
