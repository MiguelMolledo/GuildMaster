class_name HudKeys
extends RefCounted
## The keys of the HUD and the interior (docs/ui/01_hud.md §9) as actions of the input map, so they can be changed
## in the options later. They are registered here at start because project.godot is not shared by every branch of the
## repo; an action that is already in the input map (project.godot or the options) is left as it is, except the speeds:
## speed_1..3 move to Shift+1..3 (1-2-3 pick the group, GDD 4.10.5).

## action -> [physical keycode, shift]
const KEYS: Dictionary = {
	"group_1": [KEY_1, false], "group_2": [KEY_2, false], "group_3": [KEY_3, false],
	"speed_1": [KEY_1, true], "speed_2": [KEY_2, true], "speed_3": [KEY_3, true],
	"family_tree": [KEY_F, false], "inventory": [KEY_I, false], "ledger": [KEY_L, false],
	"offices": [KEY_O, false], "trials": [KEY_J, false], "help": [KEY_F1, false], "build_mode": [KEY_B, false],
	"panel_production": [KEY_P, false], "panel_storage": [KEY_A, false], "panel_staff": [KEY_E, false],
	"panel_upgrades": [KEY_M, false], "confirm": [KEY_ENTER, false],
}
const SHIFTED: Array[String] = ["speed_1", "speed_2", "speed_3"]

static var _done: bool = false


## Adds the missing actions (once). speed_1..3 get Shift+1..3 if they still are the old 1..3.
static func ensure() -> void:
	if _done:
		return
	_done = true
	for a: String in KEYS:
		var spec: Array = KEYS[a]
		if InputMap.has_action(a) and not (a in SHIFTED and not _has_shift(a)):
			continue
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		InputMap.action_erase_events(a)
		var e := InputEventKey.new()
		e.physical_keycode = spec[0] as Key
		e.shift_pressed = bool(spec[1])
		InputMap.action_add_event(a, e)
	var kp := InputEventKey.new()
	kp.physical_keycode = KEY_KP_ENTER
	InputMap.action_add_event("confirm", kp)
	if OS.is_debug_build():
		print("[HudKeys] input map ready (%d actions)" % KEYS.size())


static func _has_shift(a: String) -> bool:
	for e: InputEvent in InputMap.action_get_events(a):
		if e is InputEventKey and (e as InputEventKey).shift_pressed:
			return true
	return false


## Whether `event` is the press of `action`, with its modifiers exactly (1 is not Shift+1).
static func pressed(event: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action, false, true)
