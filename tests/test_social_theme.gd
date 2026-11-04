extends "res://tests/test_case.gd"
## The social block in the shared theme: the variations it needs exist in greybox_theme.tres (and no social panel forces
## colours by code any more), the bars drawn by code read their colours from the theme, and the two fixes of the
## ConfirmModal: the key hint never sits over a long action text, and «No se puede deshacer» shows once.

const THEME := "res://game/ui/greybox_theme.tres"
const VARIATIONS: Array[String] = ["PositiveInkLabel", "BlockedRow", "TitleStep", "TitleStepCurrent", "TitleStepFar",
	"WitnessBadgeFavor", "WitnessBadgeNeutral", "WitnessBadgeAgainst", "OfficeGold", "OfficeBronze", "OfficeSilver",
	"OfficeCopper", "GothicGoldTitle", "UrgentBar"]
const SOCIAL: Array[String] = ["npc_panel", "board_panel", "microevent_card", "courtship_panel", "family_tree_panel",
	"family_tree_node", "family_card", "succession_card", "wedding_card", "town_hall_panel", "title_card",
	"reputation_view", "offices_panel", "office_card", "trial_panel", "trial_card", "families_panel", "social_kit",
	"relation_bar", "election_calendar"]


func _modal() -> ConfirmModal:
	return (load("res://game/ui/confirm_modal.tscn") as PackedScene).instantiate() as ConfirmModal


func test_the_variations_are_in_the_theme() -> void:
	var t := load(THEME) as Theme
	for v: String in VARIATIONS:
		check(t.get_type_variation_base(v) != &"", "%s is a variation of the theme" % v)
	for pair: Array in [["RelationBar", "plus"], ["RelationBar", "minus"], ["ThresholdBar", "mark"],
			["ElectionCalendar", "registration"], ["TrialBalance", "defense"], ["FamilyTree", "line"]]:
		check(t.has_color(StringName(pair[1]), StringName(pair[0])), "%s/%s in the theme" % pair)
	eq(SocialKit.theme_color(&"RelationBar", &"minus"), t.get_color(&"minus", &"RelationBar"), "the bars read it")


func test_no_social_panel_forces_colours() -> void:
	for f: String in SOCIAL:
		var s := FileAccess.get_file_as_string("res://game/ui/%s.gd" % f)
		check(not s.contains("add_theme_color_override") and not s.contains("self_modulate") and not s.contains(
			"StyleBoxFlat.new") or f == "family_tree_panel", "%s: no colours forced by code" % f)
		check(not s.contains("Color(0.") and not s.replace("Color(1, 1, 1,", "").contains("Color(1,"),
			"%s: no colour literals (a fade of white is not a colour)" % f)


func test_long_action_text_leaves_room_for_the_key() -> void:
	var m := _modal()
	m.ask({"title": "¿Pedir la mano de Agnès Soler?", "action": "Pedir la mano y celebrar la boda"})
	var ok := m.get_node("%ConfirmButton") as Button
	var text_w := float(ok.get_meta("fit_text_w"))
	var hint_w := float(ok.get_meta("fit_hint_w"))
	check(hint_w > 0.0, "the button has its key hint")
	check((ok.custom_minimum_size.x - text_w) / 2.0 >= hint_w + 6.0, "the centred text leaves the hint its room (%.0f, %.0f, %.0f)" % [
		ok.custom_minimum_size.x, text_w, hint_w])
	m.ask({"title": "x", "action": "Sí"})
	check(ok.custom_minimum_size.x < 130.0, "a short one stays about its usual size (%.0f)" % ok.custom_minimum_size.x)
	m.free()


func test_cannot_be_undone_shows_once() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var m := _modal()
	var warn := TranslationServer.translate("ui.confirm.irreversible")
	m.ask({"title": "¿Insultar?", "body": "Relación −10. " + warn, "irreversible": true})
	var body := (m.get_node("%Body") as Label).text
	check(not body.contains(warn), "not in the body (%s)" % body)
	eq(body, "Relación −10.", "the rest stays")
	check((m.get_node("%Warn") as Label).visible, "once, on its line")
	m.ask({"title": "¿Borrar?", "body": TranslationServer.translate("ui.menu.cannot_undo")})
	check(not (m.get_node("%Body") as Label).visible, "a body that was only the warning is hidden")
	check((m.get_node("%Warn") as Label).visible, "and the warning line says it")
	m.free()
	TranslationServer.set_locale(before)


## The menus' confirmation (quit, overwrite: ConfirmDialog) and every button with a key name (MenuKit.add_hint) leave
## the key its room: on entering the tree the button is wide enough that its centred text never reaches the hint.
func test_menu_buttons_leave_room_for_the_key() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	var d := (load("res://game/ui/confirm_dialog.tscn") as PackedScene).instantiate() as ConfirmDialog
	d.ask("¿Salir al título?", "Se pierde lo jugado.", [{"id": "cancel", "text": "Cancelar", "hint": "Esc"},
		{"id": "discard", "text": "Sin guardar"}, {"id": "save", "text": "Guardar y salir", "primary": true}])
	var c := d.button("cancel")
	check(c != null and c.get_node_or_null("Hint") != null, "Cancel has its key")
	if c != null:
		check(not c.tree_entered.get_connections().is_empty(), "it fits itself when it enters the tree")
		MenuKit.fit_hint(c)  # what entering the tree does (the tests run without a tree)
		var text_w := float(c.get_meta("fit_text_w", 0.0))
		var hint_w := float(c.get_meta("fit_hint_w", 0.0))
		check(text_w > 0.0 and hint_w > 0.0, "measured in the theme's fonts (%.0f, %.0f)" % [text_w, hint_w])
		check((c.get_combined_minimum_size().x - text_w) / 2.0 >= hint_w + 6.0,
			"«Cancelar» leaves «Esc» its room (%.0f wide, text %.0f, key %.0f)" % [c.get_combined_minimum_size().x, text_w,
			hint_w])
	var plain := d.button("discard")
	check(plain != null and plain.custom_minimum_size.x == 104.0, "a button without a key keeps its size")
	d.free()
	TranslationServer.set_locale(before)
