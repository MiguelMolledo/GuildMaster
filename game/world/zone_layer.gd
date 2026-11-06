class_name ZoneLayer
extends RefCounted
## The zones of the town map (H13, docs/gdd/10_hitos.md «mapa EA 80×80 con 6 zonas»; data/maps "zones", made by
## tools/city/organic.py from tools/city/ciudades.json): the view only, the sim never reads them. Each zone's name
## (its name_key in i18n/strings.csv) on a sign over its label tile, on the overlay, shown with the camera at its
## farthest zoom (where the quarters read as a whole) and hidden closer in, where the buildings' own signs speak.

const LIFT: float = 40.0  # px above the label tile
const SHOWN_AT_ZOOM: int = 1  # the farthest level of data/view.json zoom_levels

var world: Node = null
var shown: Dictionary = {}  # zone id -> its sign (Label), for the tests and the captures
var visible: bool = true


func setup(w: Node) -> void:
	world = w
	shown = {}


## Puts the zone signs of `map`; returns how many.
func build(map: Dictionary) -> int:
	shown = {}
	for z: Dictionary in map.get("zones", []):
		var lb: Variant = z.get("label")
		if not lb is Array or (lb as Array).size() != 2 or str(z.get("name_key", "")) == "":
			continue
		var l := Label.new()
		l.text = SimQuery.t_(str(z["name_key"]))
		WorldLabels.style(l, "flash")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.name = "zone_" + str(z.get("id", ""))
		l.reset_size()
		var at := Iso.tile_to_world(Vector2i(int(lb[0]), int(lb[1])))
		l.position = (at - Vector2(l.size.x / 2.0, LIFT + l.size.y)).round()
		world.overlay().add_child(l)
		shown[str(z.get("id", ""))] = l
	if OS.is_debug_build() and not shown.is_empty():
		print("[ZoneLayer] %d zonas: %s" % [shown.size(), shown.keys()])
	return shown.size()


## Shows the signs at the farthest zoom only.
func update(zoom: int) -> void:
	var v := zoom <= SHOWN_AT_ZOOM
	if v == visible:
		return
	visible = v
	for l: Label in shown.values():
		if is_instance_valid(l):
			l.visible = v
