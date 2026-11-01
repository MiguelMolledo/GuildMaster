extends SceneTree
## Rule tests without a window. Runs every `tests/test_*.gd` and each of its `test_*` methods.
##   godot --headless --path . -s tests/run_tests.gd [-- --only=<text>]
## --only keeps the tests whose "file:method" contains <text>. Exits with 1 if anything fails.
## Every ERROR and SCRIPT ERROR that Godot logs while a test runs (a runtime error stops the test
## method half-way, push_error, an engine error) makes that test fail with its message: a Logger
## (OS.add_logger) collects them. Warnings do not count. Errors while a test file loads fail the file.


## Collects the errors Godot logs (it may be called from other threads, hence the mutex).
class ErrorCatcher:
	extends Logger
	var _lock := Mutex.new()
	var _errors: PackedStringArray = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var kind := "SCRIPT ERROR" if error_type == ERROR_TYPE_SCRIPT else "ERROR"
		var what := rationale if rationale != "" else code
		_lock.lock()
		_errors.append("%s: %s (%s:%d)" % [kind, what.strip_edges(), file.get_file(), line])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	## The errors since the last take, and forgets them.
	func take() -> PackedStringArray:
		_lock.lock()
		var out := _errors
		_errors = PackedStringArray()
		_lock.unlock()
		return out


func _init() -> void:
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var files: PackedStringArray = []
	for f: String in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var passed: int = 0
	var failed: PackedStringArray = []
	var checks: int = 0
	var t0: int = Time.get_ticks_msec()
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	for f: String in files:
		catcher.take()
		var script: GDScript = load("res://tests/" + f)
		var load_errors := catcher.take()
		if script == null or not script.can_instantiate():
			failed.append("%s: does not load%s" % [f, "" if load_errors.is_empty() else " · " + load_errors[0]])
			continue
		for msg: String in _first(load_errors):
			failed.append("%s: while loading · %s" % [f, msg])
		for m: Dictionary in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_") or (only != "" and not ("%s:%s" % [f, name]).contains(only)):
				continue
			catcher.take()
			var t: RefCounted = script.new()
			t.call(name)  # a runtime error stops the method here: the catcher has it
			checks += int(t.get("checks"))
			var fails: PackedStringArray = t.get("failures")
			fails = fails.duplicate()
			fails.append_array(_first(catcher.take()))
			if fails.is_empty():
				passed += 1
			else:
				for msg: String in fails:
					failed.append("%s:%s · %s" % [f, name, msg])
	OS.remove_logger(catcher)
	for msg: String in failed:
		print("FAIL ", msg)
	print("tests: %d passed, %d failed, %d checks, %d files, %d ms" % [passed, failed.size(), checks, files.size(), Time.get_ticks_msec() - t0])
	quit(1 if failed.size() > 0 else 0)


## The first few errors (one error often brings a cascade), and how many more there were.
static func _first(errors: PackedStringArray, keep: int = 3) -> PackedStringArray:
	var out: PackedStringArray = []
	var seen := {}
	for e: String in errors:
		if seen.has(e):
			continue
		seen[e] = true
		if out.size() < keep:
			out.append(e)
	if seen.size() > keep:
		out.append("… and %d more errors" % (seen.size() - keep))
	return out
