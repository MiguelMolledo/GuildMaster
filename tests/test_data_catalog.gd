extends "res://tests/test_case.gd"
## Content (GDD 06, L9): the catalogs load and every cross reference exists.

func test_catalog_is_sound() -> void:
	var cat := Catalog.load_from()
	eq(cat.validate(), PackedStringArray(), "no data problems")
	check(cat.items().has("iron") and cat.recipes().has("forge_sword") and cat.buildings().has("forge"), "MVP content")


func test_every_name_key_has_text() -> void:
	var cat := Catalog.load_from()
	for kind: String in Catalog.KINDS:
		for id: String in cat.tables[kind]:
			var key := str(cat.tables[kind][id].get("name_key", ""))
			check(key != "" and TranslationServer.translate(key) != key, "%s/%s has text for %s" % [kind, id, key])

