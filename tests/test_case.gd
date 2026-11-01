extends RefCounted
## Base for every test file: `extends "res://tests/test_case.gd"`.
## Write methods named `test_*() -> void` and check with the helpers below.

var failures: PackedStringArray = []
var checks: int = 0


func check(cond: bool, msg: String = "") -> void:
	checks += 1
	if not cond:
		failures.append(msg if msg != "" else "check failed")


func eq(got: Variant, want: Variant, msg: String = "") -> void:
	checks += 1
	if typeof(got) != typeof(want) or got != want:
		failures.append("%s: got %s, want %s" % [msg if msg != "" else "eq", str(got), str(want)])


func near(got: float, want: float, eps: float = 0.0001, msg: String = "") -> void:
	checks += 1
	if absf(got - want) > eps:
		failures.append("%s: got %f, want %f (±%f)" % [msg if msg != "" else "near", got, want, eps])
