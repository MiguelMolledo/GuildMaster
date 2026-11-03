class_name CreditsScreen
extends MenuScreen
## The credits (docs/ui/02_menu_inicial.md §5): a parchment with the logo, sections in gothic and names in ink, the
## seal at the foot and "Thanks for playing". The texts come from i18n; the names, from data/credits.json (with the
## licences of the fonts: OFL asks for the name and the licence). Back (Esc) returns.

const PATH: String = "res://data/credits.json"

var _bound: bool = false


func _ready() -> void:
	_bind()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	(%BackButton as Button).pressed.connect(func() -> void: back_requested.emit())


static func load_credits() -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK or not json.data is Dictionary:
		push_warning("credits: cannot read %s" % PATH)
		return {}
	return json.data


func _refresh() -> void:
	_bind()
	var box := %Sections as VBoxContainer
	MenuKit.clear(box)
	for sec: Dictionary in load_credits().get("sections", []):
		var t := MenuKit.label(SimQuery.t_(str(sec.get("title_key", ""))), &"InkTitleLabel")
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(t)
		for line: Dictionary in sec.get("lines", []):
			var text := str(line.get("text", "")) if line.has("text") else SimQuery.t_(str(line.get("key", "")))
			if line.has("license"):
				text += " (%s)" % str(line["license"])
			var l := MenuKit.label(text, &"InkLabel")
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(l)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		box.add_child(gap)
	(%Thanks as Label).text = SimQuery.t_("credits.thanks")
	(%BackButton as Button).text = SimQuery.t_("ui.menu.back")
	MenuKit.add_hint(%BackButton as Button, SimQuery.t_("ui.key.esc"))
