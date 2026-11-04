class_name FamilyCard
extends PanelContainer
## The life cards of the player's family (docs/ui/mecanicas/familia.md §2, «tarjeta de vida»), in the left column
## under the objective, not blocking: a birth (the baby's portrait in the family's colours, its parents and whose hair
## or skin it has), a coming of age and the death of a member who is not the head (the head's death is the
## succession card). Each lasts view.json family_card_seconds and stays in the book. And the school at 8: while a
## child's choice waits (life.school = "pending"), a card with the stat to raise, its preview «Artesanía 3 → 4» and
## «Elegir» (asks first: it is for ever); «Más tarde» folds it (it does not expire). Reads the state, listens to the
## events (Events, or show_event from the tests) and gives school_choice (order_sink, Game.give by default).

var order_sink: Callable = Callable()
var sim: Sim = null
var shown: Dictionary = {}      # the life event on the card ({} = none): {type, character, ...}
var school_child: String = ""   # the child whose school choice waits ("" = none)
var folded: bool = false
var _left: float = 0.0          # real seconds the event card stays
var _queue: Array = []
var _bound: bool = false

const STATS: Array[String] = ["charisma", "empathy", "negotiation", "arcane", "dexterity", "craft", "martial",
	"constitution", "rhetoric", "stealth"]


func _ready() -> void:
	_bind()
	var ev := get_node_or_null("/root/Events")
	if ev != null:
		ev.connect("sim_event", func(e: Dictionary) -> void:
			var g := get_node_or_null("/root/Game")
			if g != null and g.get("sim") != null:
				show_event(g.get("sim"), e))
	var g := get_node_or_null("/root/Game")
	if g != null and not order_sink.is_valid():
		order_sink = Callable(g, "give")


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%PickButton as Button).pressed.connect(request_school)
	(%LaterButton as Button).pressed.connect(func() -> void:
		folded = not folded
		_show())
	(%StatOption as OptionButton).item_selected.connect(func(_i: int) -> void: _preview())


func _process(delta: float) -> void:
	var g := get_node_or_null("/root/Game")
	if g != null and g.get("sim") != null:
		follow(g.get("sim"))
	if not shown.is_empty():
		_left -= delta
		if _left <= 0.0:
			shown = {}
			if not _queue.is_empty():
				_take(_queue.pop_front())
			_show()


## A sim event: a birth, a coming of age or a death in the player's family puts a card up (queued if one is shown).
func show_event(s: Sim, e: Dictionary) -> void:
	if s != sim and sim != null:
		shown = {}
		_queue.clear()
	sim = s
	var fam := SimQuery.player_family(s.state)
	var t := str(e.get("type", ""))
	var chr := str(e.get("character", ""))
	if fam == "" or str(e.get("family", s.state.characters.get(chr, {}).get("family", ""))) != fam:
		return
	var card := {}
	match t:
		"child_born":
			card = {"type": "birth", "character": chr}
		"birthday":
			if int(e.get("age", 0)) == int(s.catalog.family.get("life", {}).get("majority_age", 16)):
				card = {"type": "of_age", "character": chr}
		"character_died":
			if chr != "" and not was_head(s.state, chr) and str(s.state.families.get(fam, {}).get("head", "")) != "":
				card = {"type": "death", "character": chr, "age": int(e.get("age", 0))}
	if card.is_empty():
		return
	ViewConfig.info("FamilyCard", "life card %s" % [card])
	if shown.is_empty():
		_take(card)
	else:
		_queue.append(card)
	_show()


## Whether `chr` was the head of its family when it died (its death is the succession card, not a life card).
static func was_head(st: WorldState, chr: String) -> bool:
	if str(st.families.get(str(st.characters.get(chr, {}).get("family", "")), {}).get("head", "")) == chr:
		return true
	for c: Dictionary in st.chronicle:
		if str(c.get("kind", "")) == "inheritance" and str(c.get("from", "")) == chr:
			return true
	return false


func _take(card: Dictionary) -> void:
	shown = card
	_left = float(ViewConfig.value("family_card_seconds", 8.0))


## The school card: the first child of the player's family whose choice waits.
func follow(s: Sim) -> void:
	_bind()
	if s != sim and sim != null:
		shown = {}   # another game was loaded: its cards are not this one's
		_queue.clear()
	sim = s
	var fam := SimQuery.player_family(s.state)
	var child := ""
	for m: Variant in s.state.families.get(fam, {}).get("members", []):
		var ch: Dictionary = s.state.characters.get(str(m), {})
		if bool(ch.get("alive", true)) and ch.get("life") is Dictionary and str(ch["life"].get("school", "")) == "pending":
			child = str(m)
			break
	if child != school_child:
		school_child = child
		_show()
	elif visible != (not shown.is_empty() or school_child != ""):
		_show()


func _show() -> void:
	visible = sim != null and (not shown.is_empty() or school_child != "")
	if not visible:
		return
	var st := sim.state
	var who := str(shown.get("character", school_child)) if not shown.is_empty() else school_child
	var ch: Dictionary = st.characters.get(who, {})
	var slot := %PortraitSlot as Control
	SocialKit.clear(slot)
	var school := shown.is_empty()
	if not ch.is_empty():  # a birth or coming of age is a celebration: the gilded frame
		slot.add_child(SocialKit.portrait(st, who, {"gold": not school and str(shown.get("type", "")) in ["birth",
			"of_age"]}))
	(%SchoolBox as Control).visible = school and not folded
	(%Body as Label).visible = not (school and folded)
	(%LaterButton as Button).visible = school
	var nm := str(ch.get("name", who))
	if not school:
		match str(shown["type"]):
			"birth":
				(%Title as Label).text = SimQuery.t_("ui.life.born") % nm
				(%Body as Label).text = birth_text(who)
			"of_age":
				(%Title as Label).text = SimQuery.t_("ui.life.of_age") % nm
				(%Body as Label).text = SimQuery.t_("ui.life.of_age_body") % Kin.age(sim, who)
			"death":
				(%Title as Label).text = SimQuery.t_("ui.life.died") % nm
				(%Body as Label).text = SimQuery.t_("ui.life.died_body") % int(shown.get("age", 0))
		reset_size()
		return
	(%Title as Label).text = SimQuery.t_("ui.life.school") % nm
	(%Body as Label).text = SimQuery.t_("ui.life.school_body") % int(sim.catalog.family.get("life", {}).get("school_age", 8))
	(%LaterButton as Button).text = SimQuery.t_("ui.life.open" if folded else "ui.life.later")
	(%PickButton as Button).text = SimQuery.t_("ui.family.school_pick")
	var opt := %StatOption as OptionButton
	if opt.item_count != STATS.size():
		opt.clear()
		for k: String in STATS:
			opt.add_item(SimQuery.t_("stat." + k))
			opt.set_item_metadata(opt.item_count - 1, k)
		opt.select(STATS.find("craft"))
	_preview()
	reset_size()


## «Hija de Hugo y Agnès. Tiene el pelo de su madre.» (whose hair or skin: GDD 4.10.9, presentation).
func birth_text(chr: String) -> String:
	var st := sim.state
	var ch: Dictionary = st.characters.get(chr, {})
	var ps: Array = ch.get("parents", [])
	var names: PackedStringArray = []
	for p: Variant in ps:
		names.append(str(st.characters.get(str(p), {}).get("name", "")))
	var key := "ui.life.daughter_of" if bool(ch.get("female", false)) else "ui.life.son_of"
	var out := SimQuery.t_(key) % " y ".join(names) if not names.is_empty() else ""
	var vis: Dictionary = ch.get("visual", {}) if ch.get("visual") is Dictionary else {}
	for p: Variant in ps:
		var pc: Dictionary = st.characters.get(str(p), {})
		var pv: Dictionary = pc.get("visual", {}) if pc.get("visual") is Dictionary else {}
		var parent := SimQuery.t_("ui.life.mother" if bool(pc.get("female", false)) else "ui.life.father")
		if int(pv.get("hair", -1)) == int(vis.get("hair", -2)):
			return out + " " + SimQuery.t_("ui.life.hair_of") % parent
		if int(pv.get("skin", -1)) == int(vis.get("skin", -2)):
			return out + " " + SimQuery.t_("ui.life.skin_of") % parent
	return out


func _stat() -> String:
	var opt := %StatOption as OptionButton
	return str(opt.get_item_metadata(opt.selected)) if opt.selected >= 0 else ""


func _preview() -> void:
	var k := _stat()
	if k == "" or school_child == "":
		return
	var v := int(sim.state.characters.get(school_child, {}).get("stats", {}).get(k, 0))
	(%Preview as Label).text = SimQuery.t_("ui.family.school_preview") % [SimQuery.t_("stat." + k), v, v + 1]


## «Elegir» asks first (it is for ever) and gives school_choice for the child (actor: the head or the selected).
func request_school() -> void:
	var k := _stat()
	if k == "" or school_child == "":
		return
	var child := school_child
	var fam := SimQuery.player_family(sim.state)
	var actor := SimQuery.family_actor(sim.state, fam, Kin.head(sim.state, fam))
	var who := str(sim.state.characters.get(child, {}).get("name", child))
	SocialKit.ask(self, SimQuery.t_("ui.family.school_q") % [SimQuery.t_("stat." + k), who], SimQuery.t_("ui.family.school_body"),
		SimQuery.t_("ui.family.school_pick"), func() -> void:
			var o := {"type": "school_choice", "actor": actor, "child": child, "stat": k}
			ViewConfig.info("FamilyCard", "order %s" % [o])
			if order_sink.is_valid():
				order_sink.call(o), SimQuery.t_("ui.menu.cannot_undo"))
