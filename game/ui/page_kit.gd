class_name PageKit
extends RefCounted
## The page kit (docs/ui/04_kit_de_pagina.md): reads assets/art/ui/page_kit/kit.json (written by
## tools/art/kit_pagina.py measure) and turns each slot into what Godot draws: a StyleBoxTexture with the measured
## 9-slice margins and the safe area as content margins (page backgrounds, frames, the ribbon, the cartouche), a
## texture (corners, divider, tiles) or a mask material. The chosen variants of a slot alternate like RolApp's
## kit-variants.ts: every call to variant() takes the next one (the page slots are asked once per card, the element
## slots once per element, the masks once per image). A slot without a usable variant is missing: has() is false and
## PageCard falls back to the theme of today (ParchmentPanel, InkTitleLabel, DividerSeparator).
## View only: no rules, nothing of this is saved.

const DIR: String = "res://assets/art/ui/page_kit/"
const KIT_PATH: String = DIR + "kit.json"
const MASK_SHADER: String = "res://game/ui/page_mask.gdshader"
const THEME_PATH: String = "res://game/ui/greybox_theme.tres"

static var _kit: Dictionary = {}
static var _loaded: bool = false
static var _turns: Dictionary = {}        # slot -> how many times it was asked (the next variant is turns mod k)
static var _textures: Dictionary = {}     # file -> Texture2D (null = it does not load)


## The kit (cached). Tests swap it with use_kit().
static func kit() -> Dictionary:
	if not _loaded:
		_loaded = true
		_kit = {}
		if FileAccess.file_exists(KIT_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_PATH))
			if parsed is Dictionary:
				_kit = parsed
		if OS.is_debug_build():
			print("[PageKit] kit: %d huecos (%s)" % [(_kit.get("slots", {}) as Dictionary).size(), KIT_PATH])
	return _kit


## Tests: use this kit instead of the file (null = read the file again). Resets the turns.
static func use_kit(k: Variant) -> void:
	if k == null:
		_loaded = false
		_kit = {}
	else:
		_loaded = true
		_kit = (k as Dictionary).duplicate(true)
	_turns = {}


static func reset_turns() -> void:
	_turns = {}


## The variants of `slot` that are chosen and whose file loads, in their rotation order.
static func chosen(slot: String) -> Array:
	var s: Dictionary = (kit().get("slots", {}) as Dictionary).get(slot, {})
	var by_file: Dictionary = {}
	for v: Dictionary in s.get("variants", []):
		by_file[str(v.get("file", ""))] = v
	var out: Array = []
	for f: Variant in s.get("chosen", []):
		var v: Dictionary = by_file.get(str(f), {})
		if not v.is_empty() and texture_of(v) != null:
			out.append(v)
	return out


static func has(slot: String) -> bool:
	return not chosen(slot).is_empty()


## The next variant of `slot` ({} if the slot is missing): the N-th call uses the variant N mod k (nextVariant of
## RolApp's kit-variants.ts).
static func variant(slot: String) -> Dictionary:
	var c := chosen(slot)
	if c.is_empty():
		return {}
	var n := int(_turns.get(slot, 0))
	_turns[slot] = n + 1
	return c[n % c.size()]


static func texture_of(v: Dictionary) -> Texture2D:
	var f := str(v.get("file", ""))
	if f == "":
		return null
	if not _textures.has(f):
		var path := DIR + f
		_textures[f] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[f]


static func _side(d: Variant, key: String, default: int = 0) -> int:
	return int((d as Dictionary).get(key, default)) if d is Dictionary else default


## A page background: texture margins = the measured band (the ornament never stretches), the centre and the edges
## tiled at their natural size (a card smaller than the paper shows its top-left part, cropped, not scaled), content
## margins 0 (PageCard puts the safe area on its Body).
static func page_style(v: Dictionary) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture_of(v)
	var tm: Dictionary = v.get("texture_margin", {})
	sb.texture_margin_left = _side(tm, "left", 8)
	sb.texture_margin_top = _side(tm, "top", 8)
	sb.texture_margin_right = _side(tm, "right", 8)
	sb.texture_margin_bottom = _side(tm, "bottom", 8)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, 0)
	return sb


## The safe area of a page background as margins {left, top, right, bottom} (px).
static func safe_margins(v: Dictionary) -> Dictionary:
	var cm: Dictionary = v.get("content_margin", {})
	return {"left": _side(cm, "left", 12), "top": _side(cm, "top", 12), "right": _side(cm, "right", 12),
		"bottom": _side(cm, "bottom", 12)}


## A frame (box_frame, plate_frame) cut in 9 with the measured slice; the centre is empty. Content margins = the bar.
static func frame_style(v: Dictionary) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture_of(v)
	var n: Dictionary = v.get("nine", {}) if v.get("nine") is Dictionary else {}
	var sl: Dictionary = n.get("slice", {})
	var bar: Dictionary = n.get("bar", {})
	sb.texture_margin_left = _side(sl, "left", 4)
	sb.texture_margin_top = _side(sl, "top", 4)
	sb.texture_margin_right = _side(sl, "right", 4)
	sb.texture_margin_bottom = _side(sl, "bottom", 4)
	sb.content_margin_left = _side(bar, "left", 4)
	sb.content_margin_top = _side(bar, "top", 4)
	sb.content_margin_right = _side(bar, "right", 4)
	sb.content_margin_bottom = _side(bar, "bottom", 4)
	sb.draw_center = false
	return sb


## The ribbon cut in 3: the end caps keep, the flat middle stretches; content margins put the text on the cloth.
static func ribbon_style(v: Dictionary) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture_of(v)
	var cap: Dictionary = v.get("cap", {})
	var text: Dictionary = v.get("text", {})
	sb.texture_margin_left = _side(cap, "left", 8)
	sb.texture_margin_right = _side(cap, "right", 8)
	sb.content_margin_left = _side(cap, "left", 8) + 2
	sb.content_margin_right = _side(cap, "right", 8) + 2
	sb.content_margin_top = _side(text, "top", 4)
	sb.content_margin_bottom = _side(text, "bottom", 4)
	return sb


## The cartouche around a short figure: its ends keep, its middle stretches, the text sits in the measured hole.
static func folio_style(v: Dictionary) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture_of(v)
	var hole: Dictionary = v.get("hole", {})
	var w := int(v.get("width", 96))
	var l := clampi(_side(hole, "left", w / 5), 2, w / 2 - 2)
	var r := clampi(_side(hole, "right", w / 5), 2, w / 2 - 2)
	sb.texture_margin_left = l
	sb.texture_margin_right = r
	sb.content_margin_left = l + 2
	sb.content_margin_right = r + 2
	sb.content_margin_top = _side(hole, "top", 4)
	sb.content_margin_bottom = _side(hole, "bottom", 4)
	return sb


## A repeating texture (tile_light, tile_dark) as the background of a box.
static func tile_style(v: Dictionary, margin: int = 6) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture_of(v)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, margin)
	return sb


## The material that fades a TextureRect with mask variant `v` (null if missing).
static func mask_material(v: Dictionary) -> ShaderMaterial:
	var tex := texture_of(v)
	if tex == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = load(MASK_SHADER) as Shader
	m.set_shader_parameter("mask", tex)
	return m


## The shared theme (for the fallbacks: ParchmentPanel and friends).
static func theme() -> Theme:
	return load(THEME_PATH) as Theme
