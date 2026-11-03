extends "res://tests/test_case.gd"
## Block 0 of the economy panels: one theme for everything (the menus' variations moved into greybox_theme.tres, no
## menu_overrides_theme.tres left), the confirmation modal (docs/ui/01_hud.md §5) and the animation steps (00 §8).

const THEME: String = "res://game/ui/greybox_theme.tres"


func test_menu_variations_live_in_the_shared_theme() -> void:
	var th := load(THEME) as Theme
	for v: String in ["GothicTitle", "InkBold", "SealLabel", "ThumbPanel", "DividerSeparator", "PrimaryButton", "SealButton"]:
		check(th.get_type_variation_list(v).size() > 0 or th.get_type_variation_base(v) != &"", "%s is a variation of the theme" % v)
	check(th.get_font("font", "GothicTitle").resource_path.ends_with("jacquard_24.ttf"), "GothicTitle: Jacquard 24")
	eq(th.get_font_size("font_size", "GothicTitle"), 24, "at 24")
	check((th.get_stylebox("separator", "DividerSeparator") as StyleBoxTexture).texture.resource_path.ends_with("divider.png"),
		"the divider with rhombs")
	check(not FileAccess.file_exists("res://game/ui/menu_overrides_theme.tres"), "the menus' overrides theme is gone")
	for f: String in DirAccess.get_files_at("res://game/ui"):
		if f.ends_with(".tscn") or f.ends_with(".gd"):
			check(not FileAccess.get_file_as_string("res://game/ui/" + f).contains("menu_overrides_theme"),
				"%s does not use the old overrides" % f)


func _modal() -> ConfirmModal:
	return (load("res://game/ui/confirm_modal.tscn") as PackedScene).instantiate() as ConfirmModal


func test_confirm_modal_confirms_and_cancels() -> void:
	var m := _modal()
	var calls := [0]
	var answers: Array = []
	m.answered.connect(func(yes: bool) -> void: answers.append(yes))
	m.ask({"title": "¿Comprar Acero templado?", "body": "Cuesta 25 de oro y 3 de carbón.", "action": "Comprar",
		"irreversible": true, "seal": true}, func() -> void: calls[0] += 1)
	check(m.visible, "open")
	eq((m.get_node("%Title") as Label).text, "¿Comprar Acero templado?", "the question as the title")
	check((m.get_node("%Warn") as Label).visible, "«No se puede deshacer» when irreversible")
	check((m.get_node("%Seal") as TextureRect).visible, "the seal for the expensive")
	eq((m.get_node("%ConfirmButton") as Button).theme_type_variation, &"SealButton", "the action seals")
	eq((m.get_node("%CancelButton") as Button).get_index(), 0, "Cancel on the left")
	m.confirm()
	eq(calls[0], 1, "confirm runs the action once")
	check(not m.visible, "and closes")
	m.ask({"title": "¿Despedir a Inés?"}, func() -> void: calls[0] += 1)
	m.cancel()
	eq(calls[0], 1, "cancel does not run it")
	eq(answers, [true, false], "answered(true) then answered(false)")
	m.free()


func test_confirm_modal_with_a_reason_cannot_confirm() -> void:
	var m := _modal()
	var calls := [0]
	m.ask({"title": "¿Pagar la deuda?", "reason": "No tienes oro"}, func() -> void: calls[0] += 1)
	check((m.get_node("%ConfirmButton") as Button).disabled, "the action is disabled")
	check((m.get_node("%Reason") as Label).visible, "and says why without the mouse")
	m.confirm()
	eq(calls[0], 0, "nothing happens")
	check(m.visible, "still open until cancelled")
	m.close()
	check(not m.visible, "ESC (close) cancels")
	m.free()


func test_confirm_modal_grows_up_to_400_by_160() -> void:
	var m := _modal()
	m.ask({"title": "¿Construir la Taberna?", "body": "Cuesta 600 de oro y tarda 3 días. Te quedan 140. ".repeat(6)})
	var box := m.get_node("%Box") as Control
	check(box.custom_minimum_size.x <= 400.0 and box.custom_minimum_size.y <= 160.0, "never past 400×160 (%s)" % box.custom_minimum_size)
	check(box.custom_minimum_size.x >= 280.0 and box.custom_minimum_size.y >= 120.0, "never under 280×120")
	m.free()


func test_hud_has_the_modal_over_the_panels() -> void:
	var hud := FileAccess.get_file_as_string("res://game/ui/hud.tscn")
	var modal := hud.find('[node name="ConfirmModal" parent="Root"')
	check(modal > hud.find('[node name="ModalZone"') and modal < hud.find('[node name="HelpPanel"'),
		"the modal over the panels and under the help (01 §4.1)")


func test_count_steps_end_on_the_value() -> void:
	eq(UiAnim.count_steps(30, 72, 4), [41, 51, 62, 72] as Array[int], "counts up in whole steps")
	eq(UiAnim.count_steps(72, 56, 2), [64, 56] as Array[int], "and down")
