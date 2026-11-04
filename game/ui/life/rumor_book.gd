class_name RumorBook
extends RefCounted
## The book of rumours (docs/gdd/04f_vida_y_fiestas.md §4.24.2): the «Rumores» tab of the family book (LedgerPanel).
## Every rumour the player's people heard near a corrillo, the newest first, with the day and the place; the ones that
## give useful information (prices of another town, a rival's debt, the next election, bandits seen) marked «Útil».
## Reads LifeQuery.book only.


static func fill(box: VBoxContainer, sim: Sim) -> void:
	var rows := LifeQuery.book(sim)
	var head := Label.new()
	head.text = SimQuery.t_("ui.rumors.count") % rows.size() if not rows.is_empty() else SimQuery.t_("ui.rumors.empty")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	for r: Dictionary in rows:
		var where := Label.new()
		where.text = str(r["where"]) + ("  ·  " + SimQuery.t_("ui.rumors.useful") if bool(r["useful"]) else "")
		where.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4) if bool(r["useful"]) else Color(0.7, 0.65, 0.55))
		box.add_child(where)
		var text := Label.new()
		text.text = "«%s»" % str(r["text"])
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(320, 0)
		box.add_child(text)
