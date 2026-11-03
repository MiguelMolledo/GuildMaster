class_name Settings
extends RefCounted
## The player's options (docs/ui/02_menu_inicial.md §4): kept in user://settings.cfg, never in the saved game, and
## applied the moment they change. Keys are "<section>/<name>" (DEFAULTS). The sound sliders scale each bus of
## default_bus_layout.tres from the volume it has in the layout (100 % = the layout's volume, 0 % = muted). The
## display ones only act with a real window (not headless). The "game/*" keys are read by whoever needs them
## (the app: load_speed and pause_unfocused; the HUD: notices, help_line, objective_hints).
## Everybody listens to Settings.notifier.changed(key, value).

const PATH: String = "user://settings.cfg"
const BUSES: Dictionary = {"audio/master": "Master", "audio/music": "Music", "audio/sfx": "Sfx",
	"audio/ambient": "Ambient", "audio/voice": "Voice", "audio/ui": "Ui"}
const DEFAULTS: Dictionary = {
	"audio/master": 100, "audio/music": 100, "audio/sfx": 100, "audio/ambient": 100, "audio/voice": 100, "audio/ui": 100,
	"audio/mute_unfocused": true,
	"lang/locale": "es",
	"display/fullscreen": false, "display/scale": 2, "display/text": "normal",
	"game/load_speed": 1, "game/notices": "all", "game/pause_unfocused": true, "game/help_line": false,
	"game/objective_hints": true,
}
const CHOICES: Dictionary = {"lang/locale": ["es", "en"], "display/scale": [2, 3, 4], "display/text": ["normal", "large"],
	"game/load_speed": [1, 2, 4], "game/notices": ["urgent", "all"]}
const SCALES: Array[int] = [2, 3, 4]
const BASE_SIZE: Vector2i = Vector2i(960, 540)
const UNFOCUSED_DB: float = -15.0   # "lower the sound when the window is not active"
const THEME_PATH: String = "res://game/ui/greybox_theme.tres"

class Notifier extends RefCounted:
	signal changed(key: String, value: Variant)

static var notifier: Notifier = Notifier.new()
static var path: String = PATH              # tests point it elsewhere
static var _cfg: ConfigFile = null
static var _base_db: Dictionary = {}        # bus name -> its volume in the layout (read once)
static var _unfocused: bool = false
static var _theme_saved: Dictionary = {}    # what "large text" changed in the theme, to put it back


static func _ensure() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	var e := _cfg.load(path)
	if e != OK and e != ERR_FILE_NOT_FOUND:
		push_warning("settings: cannot read %s (%s): defaults" % [path, error_string(e)])
		_cfg = ConfigFile.new()


## Forgets what was read (tests; another path).
static func reread() -> void:
	_cfg = null
	_ensure()


static func value(key: String) -> Variant:
	_ensure()
	var def: Variant = DEFAULTS.get(key)
	var v: Variant = _cfg.get_value(key.get_slice("/", 0), key.get_slice("/", 1), def)
	if def is int and v is float:
		v = int(v)
	if CHOICES.has(key) and not v in CHOICES[key]:
		return def
	return v


## Changes, saves and applies one option. False if the key or the value is not known.
static func set_value(key: String, v: Variant) -> bool:
	if not DEFAULTS.has(key):
		push_warning("settings: unknown key %s" % key)
		return false
	if CHOICES.has(key) and not v in CHOICES[key]:
		return false
	if BUSES.has(key):
		v = clampi(int(v), 0, 100)
	_ensure()
	_cfg.set_value(key.get_slice("/", 0), key.get_slice("/", 1), v)
	var e := _cfg.save(path)
	if e != OK:
		push_warning("settings: cannot save %s (%s)" % [path, error_string(e)])
	_log("set %s=%s" % [key, v])
	apply(key)
	notifier.changed.emit(key, v)
	return true


## Back to DEFAULTS ("Valores por defecto": no confirmation, they are only options).
static func reset() -> void:
	for k: String in DEFAULTS:
		set_value(k, DEFAULTS[k])


## Applies every option (at start-up). `lang_from_cmdline`: --lang was given, it wins over the saved language.
static func apply_all(lang_from_cmdline: bool = false) -> void:
	for k: String in DEFAULTS:
		if k == "lang/locale" and lang_from_cmdline:
			continue
		apply(k)


static func apply(key: String) -> void:
	if BUSES.has(key):
		_apply_bus(str(BUSES[key]), int(value(key)))
	elif key == "lang/locale":
		TranslationServer.set_locale(str(value(key)))
	elif key == "display/fullscreen" or key == "display/scale":
		_apply_window()
	elif key == "display/text":
		_apply_text(str(value(key)))


## The volume in dB a bus gets for `percent` of its layout volume.
static func bus_db(bus: String, percent: int) -> float:
	var base := float(_base_of(bus))
	var extra := UNFOCUSED_DB if bus == "Master" and _unfocused and bool(value("audio/mute_unfocused")) else 0.0
	return base + linear_to_db(clampf(percent / 100.0, 0.0001, 1.0)) + extra


static func _base_of(bus: String) -> float:
	if not _base_db.has(bus):
		var i := AudioServer.get_bus_index(bus)
		_base_db[bus] = AudioServer.get_bus_volume_db(i) if i >= 0 else 0.0
	return float(_base_db[bus])


static func _apply_bus(bus: String, percent: int) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	_base_of(bus)
	AudioServer.set_bus_mute(i, percent <= 0)
	AudioServer.set_bus_volume_db(i, bus_db(bus, percent))


## The window lost or got the focus: the master bus goes down (if the option says so).
static func set_unfocused(u: bool) -> void:
	if u == _unfocused:
		return
	_unfocused = u
	_apply_bus("Master", int(value("audio/master")))


## The whole scales that fit the screen the window is on (D2). ×2 always (the game's size).
static func fitting_scales() -> Array[int]:
	var out: Array[int] = [2]
	if DisplayServer.get_name() == "headless":
		return out
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	for k: int in [3, 4]:
		if BASE_SIZE.x * k <= usable.x and BASE_SIZE.y * k <= usable.y:
			out.append(k)
	return out


static func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var full := bool(value("display/fullscreen"))
	if full:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var k := int(value("display/scale"))
	if not k in fitting_scales():
		k = 2
	var size := BASE_SIZE * k
	if DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)
		var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
	_log("window x%d (%s)" % [k, size])


## "Large" text (decision 1 of 02): the same size in bold and with more line spacing. Changes the body variations of
## the theme in memory (never the file), and puts them back for "normal".
static func _apply_text(mode: String) -> void:
	var theme := load(THEME_PATH) as Theme
	if theme == null:
		return
	if _theme_saved.is_empty():
		for t: String in ["Label", "BodyLabel", "InkLabel"]:
			_theme_saved[t] = {"font": theme.get_font("font", t) if theme.has_font("font", t) else null,
				"line_spacing": theme.get_constant("line_spacing", t) if theme.has_constant("line_spacing", t) else null}
	var bold: Font = theme.get_font("font", "BoldLabel") if theme.has_font("font", "BoldLabel") else null
	for t: String in _theme_saved:
		var saved: Dictionary = _theme_saved[t]
		if mode == "large":
			if t != "Label" and bold != null:
				theme.set_font("font", t, bold)
			theme.set_constant("line_spacing", t, (int(saved["line_spacing"]) if saved["line_spacing"] != null else 0) + 2)
		else:
			if saved["font"] != null:
				theme.set_font("font", t, saved["font"])
			elif theme.has_font("font", t):
				theme.clear_font("font", t)
			if saved["line_spacing"] != null:
				theme.set_constant("line_spacing", t, int(saved["line_spacing"]))
			elif theme.has_constant("line_spacing", t):
				theme.clear_constant("line_spacing", t)


static func _log(msg: String) -> void:
	ViewConfig.info("Settings", msg)
