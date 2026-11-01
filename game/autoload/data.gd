extends Node
## Loads the catalogs of data/ at start-up and checks their cross references (GDD 05 §5.7, L9).
## In a debug build a data error stops the game: it is printed as ERROR and the game quits with 1.

var catalog: Catalog


func _ready() -> void:
	catalog = Catalog.load_from("res://data", "--dev-time" in OS.get_cmdline_user_args())
	var problems := catalog.validate()
	Log.info("Data", "catalogs loaded (items=%d, recipes=%d, buildings=%d, problems=%d)" % [
		catalog.items().size(), catalog.recipes().size(), catalog.buildings().size(), problems.size()])
	if not problems.is_empty() and OS.is_debug_build():
		for p: String in problems:
			push_error("data: " + p)
		get_tree().quit(1)
