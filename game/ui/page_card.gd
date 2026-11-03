class_name PageCard
extends PanelContainer
## A narrative window built with the page kit (docs/ui/04_kit_de_pagina.md §3): show_page(data) clears the card and
## mounts one of four templates from a dictionary, so the event card, the wedding and the rest only translate the
## state into data:
##   template  "card" (Carta: illustration on top faded into the paper, the title on a ribbon, body, seal and buttons) ·
##             "plate" (Lámina: the illustration ×2 in the picture frame, ribbon on top, text on the veil) ·
##             "sheet" (Ficha: the portrait ×2 faded on one side, the data on the other; without portrait «solo ficha») ·
##             "notice" (aviso corto: the card in small, 236 wide, inside a framed box)
##   title, ribbon (the ribbon's text if it is not the title), image (Texture2D; 240×135 in cards, 192×108 in notices),
##   portrait (Texture2D, 64), subtitle (lines under the name in a sheet), dark (dark paper),
##   blocks [{type: paragraph | effects | figures | quote | divider | portraits, ...}] (§3 «Bloques»),
##   seal {text} (the wax seal with a letter or a word), buttons [{id, text, primary}], seconds (closes by itself),
##   footer_figures [{label, value}] (cartouches at the left of the foot), sticky (a click on the card does not close
##   it: cards that ask for a decision).
## The page is a StyleBoxTexture with the measured 9-slice margins; Body takes the measured safe area as margins, so no
## text can land on the ornament. Decor (frames, corners) is drawn over everything and ignores the mouse. A slot the
## kit lacks falls back to the theme of today (PageKit). `parts` says what was used (tests and logs).
## Reads only; gives no orders. A button emits button_pressed(id) and closes the card.

signal button_pressed(id: String)
signal closed

const WIDTH: Dictionary = {"card": 400, "notice": 236, "sheet": 356}
const IMAGE_OVERLAP: int = 18      # the ribbon covers the faded foot of the illustration
const RIBBON_MIN: int = 160
const PLATE_SIZE: Vector2i = Vector2i(480, 270)

var data: Dictionary = {}
var parts: Dictionary = {}          # slot -> file used ("" = fallback of the theme)
var safe: Dictionary = {}           # the safe area of this card: {left, top, right, bottom} in px
var column_width: int = 0
var _left: float = 0.0

@onready var _body: MarginContainer = %Body
@onready var _column: VBoxContainer = %Column
@onready var _decor: Control = %Decor


func _ready() -> void:
	_bind()
	gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and not bool(data.get("sticky", false)):
			close())


func _bind() -> void:
	if _body == null:
		_body = get_node("%Body") as MarginContainer
		_column = get_node("%Column") as VBoxContainer
		_decor = get_node("%Decor") as Control


## Builds the card for `d` and shows it centred (closes by itself after d.seconds if > 0).
func show_page(d: Dictionary) -> void:
	build(d)
	visible = true
	_left = float(d.get("seconds", 0.0))
	reset_size()
	if is_inside_tree():
		position = ((get_viewport_rect().size - size) / 2.0).round()
	if OS.is_debug_build():
		print("[PageCard] %s «%s» (piezas=%s, zona segura=%s, %s)" % [str(d.get("template", "card")),
			str(d.get("title", "")), parts, safe, size])


func close() -> void:
	if not visible:
		return
	visible = false
	_left = 0.0
	closed.emit()


func _process(delta: float) -> void:
	if visible and _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			close()


## Mounts the template of `d` (without showing it).
func build(d: Dictionary) -> void:
	_bind()
	data = d.duplicate()
	parts = {}
	for n: Node in [_column, _decor]:
		for c: Node in n.get_children():
			n.remove_child(c)
			c.queue_free()
	match str(d.get("template", "card")):
		"plate":
			_build_plate(d)
		"sheet":
			_build_sheet(d)
		"notice":
			_build_notice(d)
		_:
			_build_card(d)
	for side: String in ["left", "top", "right", "bottom"]:
		_body.add_theme_constant_override("margin_" + side, int(safe.get(side, 8)))


## The rectangle where text may go, in the card's coordinates.
func safe_rect() -> Rect2:
	return Rect2(float(safe["left"]), float(safe["top"]), size.x - float(safe["left"]) - float(safe["right"]),
		size.y - float(safe["top"]) - float(safe["bottom"]))


## Lays the card out now (tests, and before the first frame): its minimum size, then every container top-down.
func layout_now() -> void:
	for _i: int in 2:
		size = get_combined_minimum_size()
		_sort(self)


static func _sort(n: Node) -> void:
	if n is Container:
		(n as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c: Node in n.get_children():
		_sort(c)


# --- Templates ------------------------------------------------------------------------------------------------------

func _build_card(d: Dictionary) -> void:
	_page("page_bg_dark" if bool(d.get("dark", false)) else "page_bg", int(WIDTH["card"]))
	_corners()
	var img: Texture2D = d.get("image") as Texture2D
	if img != null:
		var head := VBoxContainer.new()
		head.name = "Head"
		head.add_theme_constant_override("separation", -IMAGE_OVERLAP)
		head.add_child(_masked(img, "mask_foot_240", 1, "Illustration"))
		head.add_child(_ribbon(_ribbon_text(d)))
		_column.add_child(head)
	else:
		_column.add_child(_ribbon(_ribbon_text(d)))
	_blocks(d)
	_footer(d)


func _build_notice(d: Dictionary) -> void:
	_box_page(int(WIDTH["notice"]))
	var img: Texture2D = d.get("image") as Texture2D
	if img != null:
		var head := VBoxContainer.new()
		head.name = "Head"
		head.add_theme_constant_override("separation", -IMAGE_OVERLAP + 4)
		head.add_child(_masked(img, "mask_foot_192", 1, "Illustration"))
		head.add_child(_ribbon(_ribbon_text(d)))
		_column.add_child(head)
	else:
		_column.add_child(_ribbon(_ribbon_text(d)))
	_blocks(d)
	_footer(d)


func _build_sheet(d: Dictionary) -> void:
	_page("page_bg_tall", int(WIDTH["sheet"]))
	_corners()
	var por: Texture2D = d.get("portrait") as Texture2D
	if por != null:
		var top := HBoxContainer.new()
		top.name = "Top"
		top.add_theme_constant_override("separation", 4)
		top.add_child(_masked(por, "mask_side", 2, "Portrait"))
		var side := VBoxContainer.new()
		side.name = "Side"
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.add_theme_constant_override("separation", 2)
		var w := column_width - por.get_width() * 2 - 4
		side.add_child(_ribbon(_ribbon_text(d), w))
		for line: Variant in d.get("subtitle", []):
			side.add_child(_label(str(line), &"PageInkDim", w))
		top.add_child(side)
		_column.add_child(top)
	else:
		_column.add_child(_ribbon(_ribbon_text(d)))
		for line: Variant in d.get("subtitle", []):
			var l := _label(str(line), &"PageInkDim")
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_column.add_child(l)
	_blocks(d)
	_footer(d)


func _build_plate(d: Dictionary) -> void:
	var v := PageKit.variant("plate_frame")
	var bar := {"left": 8, "top": 8, "right": 8, "bottom": 8}
	var back := StyleBoxFlat.new()
	back.bg_color = Color("#1a1209")
	add_theme_stylebox_override("panel", back)
	if not v.is_empty():
		var fr := Panel.new()
		fr.name = "Frame"
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.set_anchors_preset(Control.PRESET_FULL_RECT)
		fr.add_theme_stylebox_override("panel", PageKit.frame_style(v))
		_decor.add_child(fr)
		var b: Dictionary = (v.get("nine", {}) as Dictionary).get("bar", {})
		for k: String in bar:
			bar[k] = int(b.get(k, 8))
		parts["plate_frame"] = str(v["file"])
	else:
		parts["plate_frame"] = ""
	safe = bar
	column_width = PLATE_SIZE.x
	var plate := Control.new()
	plate.name = "Plate"
	plate.custom_minimum_size = Vector2(PLATE_SIZE)
	plate.clip_contents = true
	var img: Texture2D = d.get("image") as Texture2D
	if img != null:
		var t := TextureRect.new()
		t.name = "Illustration"
		t.texture = img
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		plate.add_child(t)
	var top := CenterContainer.new()
	top.name = "RibbonRow"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 6
	top.add_child(_ribbon(_ribbon_text(d), PLATE_SIZE.x - 48))
	plate.add_child(top)
	var vv := PageKit.variant("veil")
	var band := MarginContainer.new()
	band.name = "TextBand"
	band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	band.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for k: String in ["left", "right"]:
		band.add_theme_constant_override("margin_" + k, 16)
	band.add_theme_constant_override("margin_top", 26)
	band.add_theme_constant_override("margin_bottom", 8)
	if not vv.is_empty():
		var veil := TextureRect.new()
		veil.name = "Veil"
		veil.texture = PageKit.texture_of(vv)
		veil.stretch_mode = TextureRect.STRETCH_TILE
		veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		veil.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		veil.offset_top = -96
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(veil)
		parts["veil"] = str(vv["file"])
	else:
		var flat := ColorRect.new()
		flat.name = "Veil"
		flat.color = Color("#d4b896")
		flat.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		flat.offset_top = -64
		plate.add_child(flat)
		parts["veil"] = ""
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.add_theme_constant_override("separation", 2)
	band.add_child(inner)
	plate.add_child(band)
	_column.add_child(plate)
	var col := _column
	_column = inner
	column_width = PLATE_SIZE.x - 32
	_blocks(d)
	_footer(d)
	_column = col
	column_width = PLATE_SIZE.x
	band.offset_top = -band.get_combined_minimum_size().y


# --- Pieces ---------------------------------------------------------------------------------------------------------

## The page background of `slot` (or the plain parchment of the theme) and the safe area as Body margins.
func _page(slot: String, width: int) -> void:
	var v := PageKit.variant(slot)
	if v.is_empty() and slot != "page_bg":
		v = PageKit.variant("page_bg")
	if v.is_empty():
		var sb := PageKit.theme().get_stylebox("panel", "ParchmentPanel").duplicate() as StyleBox
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			sb.set_content_margin(side, 0)
		add_theme_stylebox_override("panel", sb)
		safe = {"left": 8, "top": 8, "right": 8, "bottom": 8}
		parts["page"] = ""
	else:
		add_theme_stylebox_override("panel", PageKit.page_style(v))
		safe = PageKit.safe_margins(v)
		parts["page"] = str(v["file"])
	custom_minimum_size = Vector2(width, 0)
	column_width = width - int(safe["left"]) - int(safe["right"])


## The notice's page: a box of the light tile with the small frame (fallback: the parchment).
func _box_page(width: int) -> void:
	var t := PageKit.variant("tile_light")
	var f := PageKit.variant("box_frame")
	if t.is_empty():
		_page("page_bg_none", width)  # straight to the fallback chain
		return
	add_theme_stylebox_override("panel", PageKit.tile_style(t, 0))
	parts["page"] = str(t["file"])
	var bar := 4
	if not f.is_empty():
		var fr := Panel.new()
		fr.name = "Frame"
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.set_anchors_preset(Control.PRESET_FULL_RECT)
		var st := PageKit.frame_style(f)
		fr.add_theme_stylebox_override("panel", st)
		_decor.add_child(fr)
		bar = int(maxf(st.content_margin_left, st.content_margin_top))
		parts["box_frame"] = str(f["file"])
	else:
		parts["box_frame"] = ""
	safe = {"left": bar + 4, "top": bar + 4, "right": bar + 4, "bottom": bar + 4}
	custom_minimum_size = Vector2(width, 0)
	column_width = width - 2 * (bar + 4)


## The four corner ornaments, at the corners of the safe area, outside it (skipped where they do not fit).
func _corners() -> void:
	var v := PageKit.variant("page_corner")
	parts["page_corner"] = str(v.get("file", ""))
	var tex := PageKit.texture_of(v) if not v.is_empty() else null
	if tex == null:
		return
	var w := tex.get_width()
	var h := tex.get_height()
	for i: int in 4:
		var right := i % 2 == 1
		var bottom := i >= 2
		var c := TextureRect.new()
		c.name = "Corner%d" % i
		c.texture = tex
		c.flip_h = right
		c.flip_v = bottom
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.anchor_left = 1.0 if right else 0.0
		c.anchor_right = c.anchor_left
		c.anchor_top = 1.0 if bottom else 0.0
		c.anchor_bottom = c.anchor_top
		var inset_x := maxi(2, int(safe["right" if right else "left"]) - w + 4)
		var inset_y := maxi(2, int(safe["bottom" if bottom else "top"]) - h + 4)
		c.offset_left = -inset_x - w if right else inset_x
		c.offset_top = -inset_y - h if bottom else inset_y
		c.offset_right = c.offset_left + w
		c.offset_bottom = c.offset_top + h
		_decor.add_child(c)


func _ribbon_text(d: Dictionary) -> String:
	return str(d.get("ribbon", d.get("title", "")))


## The title on the ribbon (3-slice of the kit; fallback: the title in ink, centred).
func _ribbon(text: String, max_w: int = -1) -> Control:
	var maxw := column_width if max_w < 0 else max_w
	var v := PageKit.variant("ribbon")
	var l := Label.new()
	l.name = "RibbonText"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tw := int(ceilf(_text_width(l, text, &"PageRibbon")))
	if not v.is_empty() and tw + _ribbon_caps(v) + 8 > maxw:  # the turn's ribbon is too narrow: another that fits
		var fit: Dictionary = {}
		for c: Dictionary in PageKit.chosen("ribbon"):
			if tw + _ribbon_caps(c) + 8 <= maxw:
				fit = c
				break
		v = fit
	if v.is_empty():
		parts["ribbon"] = ""
		l.theme_type_variation = &"InkTitleLabel"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(maxw, 0)
		l.name = "Ribbon"
		return l
	parts["ribbon"] = str(v["file"])
	l.theme_type_variation = &"PageRibbon"
	var p := PanelContainer.new()
	p.name = "Ribbon"
	var st := PageKit.ribbon_style(v)
	p.add_theme_stylebox_override("panel", st)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tex := PageKit.texture_of(v)
	var caps := _ribbon_caps(v)
	p.custom_minimum_size = Vector2(clampi(tw + caps + 8, mini(RIBBON_MIN, maxw), maxw), tex.get_height())
	l.clip_text = true
	p.add_child(l)
	return p


func _ribbon_caps(v: Dictionary) -> int:
	var st := PageKit.ribbon_style(v)
	return int(st.content_margin_left + st.content_margin_right)


func _text_width(l: Label, text: String, variation: StringName) -> float:
	var th := PageKit.theme()
	var font := th.get_font("font", variation) if th.has_font("font", variation) else l.get_theme_default_font()
	var fs := th.get_font_size("font_size", variation) if th.has_font_size("font_size", variation) else 16
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## An image faded with the next variant of `mask_slot` (×`scale`, centred). Without mask: the image as it is.
func _masked(tex: Texture2D, mask_slot: String, scale: int, node_name: String) -> TextureRect:
	var t := TextureRect.new()
	t.name = node_name
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.custom_minimum_size = Vector2(tex.get_width() * scale, tex.get_height() * scale)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := PageKit.variant(mask_slot)
	var m := PageKit.mask_material(v) if not v.is_empty() else null
	if m != null:
		t.material = m
	parts[mask_slot] = str(v.get("file", "")) if m != null else ""
	return t


func _label(text: String, variation: StringName, width: int = -1) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(column_width if width < 0 else width, 0)
	return l


func _blocks(d: Dictionary) -> void:
	var i := 0
	for b: Dictionary in d.get("blocks", []):
		var n: Control = null
		match str(b.get("type", "")):
			"paragraph":
				n = _label(str(b.get("text", "")), &"PageInk")
			"effects":
				n = _effects(b.get("items", []) as Array)
			"figures":
				n = _figures(b.get("items", []) as Array)
			"quote":
				n = _quote(str(b.get("text", "")), str(b.get("who", "")))
			"divider":
				n = _divider()
			"portraits":
				n = _portraits(b)
		if n != null:
			n.name = "Block%d_%s" % [i, str(b.get("type", ""))]
			_column.add_child(n)
			i += 1


## Effects: one line each with «·»; sign "+" good (green ink), "-" bad (wax red), "" neutral. Two columns from 4 up.
func _effects(items: Array) -> Control:
	var cols := 2 if items.size() >= 4 and column_width >= 280 else 1
	var probe := Label.new()
	for it: Dictionary in items:  # two columns only if every line fits in half the column
		if _text_width(probe, "· " + str(it.get("text", "")), &"PageInk") > (column_width - 8) / 2:
			cols = 1
	probe.free()
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 0)
	var w := (column_width - 8 * (cols - 1)) / cols
	for it: Dictionary in items:
		var sign := str(it.get("sign", ""))
		var v: StringName = &"PageGood" if sign == "+" else (&"PageBad" if sign == "-" else &"PageInk")
		g.add_child(_label("· " + str(it.get("text", "")), v, w))
	return g


## Figures in the cartouche of the kit (fallback: bold ink), side by side.
func _figures(items: Array) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.custom_minimum_size = Vector2(column_width, 0)
	for it: Dictionary in items:
		row.add_child(_figure(str(it.get("label", "")), str(it.get("value", ""))))
	return row


func _figure(label: String, value: String) -> Control:
	var text := ("%s %s" % [label, value]).strip_edges()
	var v := PageKit.variant("folio")
	var l := Label.new()
	l.name = "Figure"
	l.text = text
	l.theme_type_variation = &"PageInkBold"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if v.is_empty():
		parts["folio"] = ""
		return l
	parts["folio"] = str(v["file"])
	var p := PanelContainer.new()
	p.name = "Cartouche"
	var st := PageKit.folio_style(v)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(0, PageKit.texture_of(v).get_height())
	p.add_child(l)
	return p


## A quote in a box of the light tile with the small frame; the signature on the right.
func _quote(text: String, who: String) -> Control:
	var box := _box()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	var inner_w := column_width - int(box.get_meta("pad", 8)) * 2
	vb.add_child(_label("«%s»" % text, &"PageInkDim", inner_w))
	if who != "":
		var w := _label("— " + who, &"PageSmall", inner_w)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vb.add_child(w)
	(box.get_node("Pad") as MarginContainer).add_child(vb)
	return box


## A box: tile_light behind, box_frame on top, a padding of the frame's bar + 4. Fallback: the theme's field.
func _box() -> PanelContainer:
	var box := PanelContainer.new()
	var t := PageKit.variant("tile_light")
	var f := PageKit.variant("box_frame")
	if not t.is_empty():
		box.add_theme_stylebox_override("panel", PageKit.tile_style(t, 0))
	else:
		box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var pad := 6
	var pad_x := 6
	var pc := MarginContainer.new()
	pc.name = "Pad"
	if not f.is_empty():  # clear of the bar above and below, of the corner ornaments at the sides
		var st := PageKit.frame_style(f)
		pad = int(maxf(st.content_margin_left, st.content_margin_top)) + 3
		pad_x = maxi(pad, int(maxf(st.texture_margin_left, st.texture_margin_right)) + 2)
	for side: String in ["top", "bottom"]:
		pc.add_theme_constant_override("margin_" + side, pad)
	for side: String in ["left", "right"]:
		pc.add_theme_constant_override("margin_" + side, pad_x)
	box.add_child(pc)
	if not f.is_empty():
		var fr := Panel.new()
		fr.name = "Frame"
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.add_theme_stylebox_override("panel", PageKit.frame_style(f))
		box.add_child(fr)
	box.set_meta("pad", pad_x)
	return box


## The divider of the kit, centred and cropped to the column (fallback: the theme's DividerSeparator).
func _divider() -> Control:
	var v := PageKit.variant("divider")
	var tex := PageKit.texture_of(v) if not v.is_empty() else null
	if tex == null:
		parts["divider"] = ""
		var s := HSeparator.new()
		s.theme_type_variation = &"DividerSeparator"
		return s
	parts["divider"] = str(v["file"])
	var t := TextureRect.new()
	t.texture = tex
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.clip_contents = true
	t.custom_minimum_size = Vector2(mini(tex.get_width(), column_width), tex.get_height())
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Two portraits faded at their corner, a mark between them and the names below. A side may bring a node instead of
## a texture (`left_node`: a PortraitFrame of the game, whose identity is drawn by a shader and cannot take the mask:
## it keeps its frame of the theme) and a band under the name (`left_band`: the family's colours).
func _portraits(b: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(column_width, 0)
	for k: String in ["left", "right"]:
		var vb := VBoxContainer.new()
		vb.name = "Left" if k == "left" else "Right"
		vb.add_theme_constant_override("separation", 2)
		var slot := CenterContainer.new()
		slot.name = vb.name + "Slot"
		var tex: Texture2D = b.get(k) as Texture2D
		var node: Control = b.get(k + "_node") as Control
		if node != null:
			slot.add_child(node)
		elif tex != null:
			var p := _masked(tex, "mask_corner", 1, "Face")
			p.flip_h = k == "right"
			slot.add_child(p)
		vb.add_child(slot)
		var n := _label(str(b.get(k + "_name", "")), &"PageInkBold", 120)
		n.name = vb.name + "Name"
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(n)
		var band: Control = b.get(k + "_band") as Control
		if band != null:
			band.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vb.add_child(band)
		row.add_child(vb)
		if k == "left":
			var mid: Variant = b.get("mid")
			if mid is Texture2D:
				var m := TextureRect.new()
				m.name = "Mid"
				m.texture = mid
				m.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(m)
			else:
				var ml := _label(str(mid) if mid != null else "", &"PageTitle", 24)
				ml.name = "Mid"
				ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(ml)
	return row


## Figures marked "footer" go left in the foot, the seal and the buttons right.
func _footer(d: Dictionary) -> void:
	var foot := HBoxContainer.new()
	foot.name = "Footer"
	foot.add_theme_constant_override("separation", 6)
	foot.custom_minimum_size = Vector2(column_width, 0)
	for it: Dictionary in d.get("footer_figures", []):
		var f := _figure(str(it.get("label", "")), str(it.get("value", "")))
		f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(f)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	var seal: Dictionary = d.get("seal", {}) if d.get("seal") is Dictionary else {}
	if not seal.is_empty():
		foot.add_child(_seal(str(seal.get("text", ""))))
	for btn: Dictionary in d.get("buttons", []):
		var b := Button.new()
		b.name = "Button_" + str(btn.get("id", ""))
		b.text = str(btn.get("text", ""))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if bool(btn.get("primary", false)):
			b.theme_type_variation = &"PrimaryButton"
		var id := str(btn.get("id", ""))
		b.pressed.connect(func() -> void:
			button_pressed.emit(id)
			close())
		foot.add_child(b)
	if foot.get_child_count() > 1:
		_column.add_child(foot)


func _seal(text: String) -> Control:
	var tex := load("res://assets/art/ui/marks/seal.png") as Texture2D
	var c := TextureRect.new()
	c.name = "Seal"
	c.texture = tex
	c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.stretch_mode = TextureRect.STRETCH_SCALE
	c.custom_minimum_size = Vector2(32, 32)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.name = "SealText"
	l.text = text
	l.theme_type_variation = &"PageSeal"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(l)
	return c
