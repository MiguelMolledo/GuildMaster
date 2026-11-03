class_name SaveSlots
extends RefCounted
## The saved games as the menus see them (docs/ui/02_menu_inicial.md §3): the autosave and the three slots (D6),
## each with its light header (SaveFile.peek: the save format does not change), when it was saved in real life (the
## file's time) and its thumbnail (user://saves/<slot>.png, the town at 1/8 when it was saved). A broken file is an
## entry with ok = false and its error, never a crash.

const AUTOSAVE: String = "auto"
const SLOTS: Array[String] = ["slot_1", "slot_2", "slot_3"]
const THUMB_SIZE: Vector2i = Vector2i(120, 68)

static var dir: String = "user://saves"   # tests point it elsewhere


static func path_of(slot: String) -> String:
	return dir.path_join(slot + ".json")


static func thumb_path(slot: String) -> String:
	return dir.path_join(slot + ".png")


static func is_slot(slot: String) -> bool:
	return slot == AUTOSAVE or slot in SLOTS


## {slot, exists, ok, error, header, saved_at (unix seconds, 0 if none), thumb ("" or its path)}.
static func entry(slot: String) -> Dictionary:
	var p := path_of(slot)
	var out := {"slot": slot, "exists": FileAccess.file_exists(p), "ok": false, "error": "missing", "header": {},
		"saved_at": 0, "thumb": ""}
	if not out["exists"]:
		return out
	out["saved_at"] = int(FileAccess.get_modified_time(p))
	var r := SaveFile.peek(p)
	out["ok"] = bool(r["ok"])
	out["error"] = "" if r["ok"] else str(r.get("error", ""))
	out["header"] = r.get("header", {})
	if FileAccess.file_exists(thumb_path(slot)):
		out["thumb"] = thumb_path(slot)
	return out


## The autosave (if `with_auto`) and the three slots, in that order.
static func list(with_auto: bool = true) -> Array:
	var out: Array = []
	if with_auto:
		out.append(entry(AUTOSAVE))
	for s: String in SLOTS:
		out.append(entry(s))
	return out


## The readable entry saved last ("Continuar"), {} if there is none.
static func most_recent() -> Dictionary:
	var best := {}
	for e: Dictionary in list(true):
		if bool(e["ok"]) and (best.is_empty() or int(e["saved_at"]) > int(best["saved_at"])):
			best = e
	return best


static func any_readable() -> bool:
	return not most_recent().is_empty()


## Deletes a slot and its thumbnail. The autosave is never deleted from the menu (D6) unless `force`.
static func delete(slot: String, force: bool = false) -> Error:
	if not is_slot(slot) or (slot == AUTOSAVE and not force):
		return ERR_INVALID_PARAMETER
	var e := OK
	if FileAccess.file_exists(path_of(slot)):
		e = DirAccess.remove_absolute(path_of(slot))
	if FileAccess.file_exists(thumb_path(slot)):
		DirAccess.remove_absolute(thumb_path(slot))
	ViewConfig.info("SaveSlots", "delete %s (%s)" % [slot, error_string(e)])
	return e


## Saves `img` (what the player saw) as the slot's thumbnail, reduced to THUMB_SIZE with nearest neighbour.
static func save_thumbnail(slot: String, img: Image) -> Error:
	if img == null or img.is_empty():
		return ERR_INVALID_DATA
	var t := img.duplicate() as Image
	t.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_NEAREST)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return t.save_png(thumb_path(slot))


## The thumbnail as a texture (null if there is none). A file of the player's, not a project resource.
static func thumbnail(slot: String) -> Texture2D:
	if not FileAccess.file_exists(thumb_path(slot)):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(thumb_path(slot)))
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## "hoy, 18:42" / "ayer, 22:10" / "1 nov, 12:03" of a unix time, in local time, against `now` (unix).
static func when_label(unix: int, now: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	var today := Time.get_datetime_dict_from_unix_time(now + bias)
	var hm := "%02d:%02d" % [int(d["hour"]), int(d["minute"])]
	var day_n := floori(float(unix + bias) / 86400.0)
	var today_n := floori(float(now + bias) / 86400.0)
	if day_n == today_n:
		return SimQuery.t_("ui.saves.today") % hm
	if day_n == today_n - 1:
		return SimQuery.t_("ui.saves.yesterday") % hm
	var month := SimQuery.t_("ui.month_short.%d" % int(d["month"]))
	if int(d["year"]) != int(today["year"]):
		return SimQuery.t_("ui.saves.on_date_year") % [int(d["day"]), month, int(d["year"]), hm]
	return SimQuery.t_("ui.saves.on_date") % [int(d["day"]), month, hm]
