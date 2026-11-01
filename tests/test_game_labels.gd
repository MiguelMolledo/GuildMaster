extends "res://tests/test_case.gd"
## Item labels (GDD 4.3.3): the quality suffix agrees with the item's grammatical gender in Spanish.

var cat := Catalog.load_from()


func test_quality_suffix_agrees_in_spanish() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("es")
	eq(SimQuery.item_label(cat, "sword", Inventory.GOOD), "Espada buena", "feminine")
	eq(SimQuery.item_label(cat, "iron_ingot", Inventory.GOOD), "Lingote de hierro bueno", "masculine")
	eq(SimQuery.item_label(cat, "hammer", Inventory.EXCELLENT), "Martillo excelente", "excellent")
	eq(SimQuery.item_label(cat, "iron", Inventory.NORMAL), "Hierro", "normal has no suffix")
	TranslationServer.set_locale("en")
	eq(SimQuery.item_label(cat, "sword", Inventory.GOOD), "Sword (good)", "english")
	TranslationServer.set_locale(before)
