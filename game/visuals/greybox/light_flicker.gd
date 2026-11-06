class_name LightFlicker
extends Node2D
## A firelight halo that breathes (docs/arte/interiores.md): it moves its alpha between `low` and `high` with two slow
## waves and a little noise, and its scale by `wobble`. Visual only (the sim never reads it). Put it on an additive
## Sprite2D or Polygon2D (CanvasItemMaterial blend_mode Add) over the fire.

@export_range(0.0, 1.0) var low: float = 0.7
@export_range(0.0, 1.0) var high: float = 1.0
@export var speed: float = 1.0
@export_range(0.0, 0.2) var wobble: float = 0.03

var _t: float = 0.0
var _noise: float = 0.0
var _base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	_base_scale = scale
	_t = randf() * 10.0
	if OS.is_debug_build():  # print, not Log: this scene is also loaded without the autoloads (tests, the gallery)
		print("[LightFlicker] ready (node=%s, low=%.2f, high=%.2f, speed=%.2f)" % [name, low, high, speed])


func _process(delta: float) -> void:
	_t += delta * speed
	_noise = lerpf(_noise, randf_range(-1.0, 1.0), clampf(delta * 8.0, 0.0, 1.0))
	var w := 0.5 + 0.3 * sin(_t * 2.3) + 0.15 * sin(_t * 5.7 + 1.3) + 0.15 * _noise
	var k := clampf(w, 0.0, 1.0)
	modulate.a = lerpf(low, high, k)
	scale = _base_scale * (1.0 + wobble * (k - 0.5))
