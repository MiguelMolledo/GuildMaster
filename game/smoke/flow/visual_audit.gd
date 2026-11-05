class_name VisualAudit
extends RefCounted
## Automatic checks on what is on screen (docs/gdd/07_testing.md §7.6, docs/ui/00_lenguaje_visual.md §6): every
## visible text and control of the GUI is measured; with a capture (a window) the contrast is read from its pixels.
## A finding: {kind, severity ("fallo" | "aviso"), screen, node, text, rect: [x, y, w, h], detail}. Kinds:
##   cut         the text does not fit in its control (cut, clipped or with fewer lines than it needs)
##   outside     the text leaves its panel, or the control leaves the screen
##   small_font  the letter is below the legible minimum (8 px, Pixel Operator 8)
##   bad_size    a font at a size that is not its own (00 §6: only those sizes; another one deforms the letters)
##   font        a font that is not one of the theme's four (Godot's default, a system font, Silkscreen...)
##   contrast    text against its background under 3:1 (aviso) or 2:1 (fallo); needs a capture
##   overlap     two controls (or two texts) on top of each other
##   i18n        an i18n key on screen instead of its text
##   covered     a notice or the toast that just appeared is under an open panel
##   placeholder a greybox piece shows its id (the art is missing)
##   mute        a disabled button that does not say why (no tooltip, no reason line next to it)
## The allowed fonts and sizes come from tools/ui/tokens.json ("fuente").

const MIN_SIZE: int = 8
const CONTRAST_WARN: float = 3.0
const CONTRAST_FAIL: float = 2.0
const FONT_DIR: String = "res://assets/art/ui/fonts/"

var allowed: Dictionary = {}     # font file -> [sizes]
var keys: Dictionary = {}        # i18n keys (strings.csv)
var _key_re: RegEx = RegEx.create_from_string("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$")
var _bracket_re: RegEx = RegEx.create_from_string("\\[[a-z][a-z0-9_.]+\\]")   # «[noble_wedding]»: a missing name
var _seen_notices: Dictionary = {}   # instance id -> true: the notices already checked


func _init() -> void:
	var tok: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/ui/tokens.json"))
	if tok is Dictionary:
		for role: String in (tok as Dictionary).get("fuente", {}):
			var f: Dictionary = tok["fuente"][role]
			var file := str(f["fichero"])
			if not allowed.has(file):
				allowed[file] = []
			if not (allowed[file] as Array).has(int(f["tam"])):
				(allowed[file] as Array).append(int(f["tam"]))
	var csv := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	if csv != null:
		csv.get_csv_line()
		while not csv.eof_reached():
			var row := csv.get_csv_line()
			if row.size() > 0 and row[0] != "":
				keys[row[0]] = true


## The name of the screen a control belongs to: the scene it was made from (ledger_panel, hud, interior_view...).
static func screen_of(c: Node) -> String:
	var n: Node = c
	while n != null:
		var path := n.scene_file_path
		if path != "" and not path.ends_with("/app.tscn"):
			var base := path.get_file().get_basename()
			if not base in ["item_slot", "portrait_frame", "page_card", "family_tree_node", "manage_slot"]:
				return base
		n = n.get_parent()
	return "app"


static func _rect(r: Rect2) -> Array:
	return [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]


func _finding(out: Array, kind: String, sev: String, c: Control, r: Rect2, detail: String) -> void:
	out.append({"kind": kind, "severity": sev, "screen": screen_of(c), "node": UiDriver.path_of(c),
		"text": UiDriver.text_of(c).left(60), "rect": _rect(r), "detail": detail})


## Every check on the controls shown now. `img` is the capture (960×540) or null (no window: no contrast).
func scan(root: Window, img: Image) -> Array:
	var out: Array = []
	var vp := root.get_visible_rect()
	var controls: Array = []
	_collect(root, controls)
	var texts: Array = []      # [Control, Rect2 of its text]
	var clicks: Array = []     # interactive controls
	var covers: Array = []     # [Control, Rect2]: panels and veils that hide what is drawn under them
	for c: Control in controls:
		if c.is_visible_in_tree() and _alpha(c) > 0.4 and not in_world(c) and \
				(c is PanelContainer or c is Panel or (c is ColorRect and (c as ColorRect).color.a * _alpha(c) > 0.35) \
				or ((c is TextureRect or c is NinePatchRect) and c.get_global_rect().get_area() > 12000.0) \
				or (c.get_parent() is PageCard and c.get_global_rect().get_area() > 4000.0)):   # a card's page
			covers.append([c, screen_rect(c)])
	for c: Control in controls:
		if not c.is_visible_in_tree() or c.modulate.a < 0.05 or _alpha(c) < 0.05:
			continue
		var r := screen_rect(c)
		if not vp.intersects(r) or r.size.x < 2.0 or r.size.y < 2.0:
			continue   # off screen (the town scrolls; a row scrolled away) or squeezed to nothing
		if _hidden_under(c, r, covers):
			continue   # under a card, a modal or its veil: not what the player sees now
		var clip := _clip_of(c)
		if clip != null and not screen_rect(clip).intersects(r):
			continue   # scrolled out of its list
		var world := in_world(c)
		var txt := UiDriver.text_of(c).strip_edges()
		if (c is BaseButton or c is LineEdit or c is Range and not c is ProgressBar) and not world:
			if r.size.x >= 2 and r.size.y >= 2:
				clicks.append(c)
		if c is BaseButton and (c as BaseButton).disabled and not world and c.tooltip_text.strip_edges() == "" \
				and _reason_near(c) == "" and not (c is BaseButton and (c as BaseButton).toggle_mode and (c as BaseButton).button_pressed):
			_finding(out, "mute", "fallo", c, r, "botón apagado sin decir por qué (ni tooltip ni línea de motivo)")
		if txt == "" or not (c is Label or c is Button or c is RichTextLabel or c is LineEdit):
			continue
		if c is Label and (c as Label).visible_characters == 0:
			continue
		if screen_of(c) == "_greybox":   # the greybox kit names its piece with its id: a placeholder, not a text
			_finding(out, "placeholder", "aviso", c, r, "rótulo de greybox: se ve el id «%s» (falta su arte)" % txt.left(30))
			continue
		_check_font(out, c, r)
		_check_fit(out, c, r, txt, vp, world, clip)
		_check_key(out, c, r, txt)
		var tr := _text_rect(c, r, txt)
		if clip != null:
			tr = tr.intersection(screen_rect(clip))   # what a scroll list hides is not on screen
		if not world and not c.get_parent() is Label:   # a «+42» rising from a figure is a passing effect
			texts.append([c, tr])
		if img != null:
			_check_contrast(out, c, tr, img)
	_check_overlaps(out, clicks, texts)
	_check_notices(out, root, controls)
	return out


## A reason line next to `c` (a visible label whose name says Reason, two levels up), "" if none.
static func _reason_near(c: Control) -> String:
	var n: Node = c
	for i: int in 3:
		n = n.get_parent()
		if n == null:
			return ""
		for pat: String in ["*Reason*", "*Why*"]:
			for d: Node in n.find_children(pat, "Label", true, false):
				if (d as Label).is_visible_in_tree() and (d as Label).text.strip_edges() != "":
					return (d as Label).text
	return ""


## Whether a panel or a veil drawn over `c` covers the centre of `c`.
static func _hidden_under(c: Control, r: Rect2, covers: Array) -> bool:
	var at := r.get_center()
	var lc := _layer_of(c)
	for pair: Array in covers:
		var o: Control = pair[0]
		if not (pair[1] as Rect2).has_point(at) or _related(o, c):
			continue
		var lo := _layer_of(o)
		if lo > lc or (lo == lc and o.is_greater_than(c)):
			return true
	return false


## Where `c` is on the screen (viewport pixels): through its canvas layer and, in the town, the camera.
static func screen_rect(c: Control) -> Rect2:
	return c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)


## A label of the town or a room (a sign, a name over a person): it lives in the world, under a Node2D.
static func in_world(c: Node) -> bool:
	var n := c.get_parent()
	while n != null:
		if n is Node2D:
			return true
		if n is CanvasLayer:
			return false
		n = n.get_parent()
	return false


## The nearest ancestor that clips its children (a scroll list), or null.
static func _clip_of(c: Control) -> Control:
	var n := c.get_parent()
	while n != null and n is Control:
		if (n as Control).clip_contents:
			return n as Control
		n = n.get_parent()
	return null


## The outermost panel `c` sits in (two texts of different panels on top of each other are a panel over another).
static func _top_panel(c: Node) -> Node:
	var top: Node = null
	var n := c.get_parent()
	while n != null and not n is CanvasLayer:
		if n is PanelContainer or n is Panel:
			top = n
		n = n.get_parent()
	return top


func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control:
		out.append(n)
	for c: Node in n.get_children():
		_collect(c, out)


## The product of the alphas of `c` and its ancestors (a fading panel is not checked).
static func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n != null and n is CanvasItem:
		a *= (n as CanvasItem).modulate.a * (n as CanvasItem).self_modulate.a if n == c else (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a


func _font_of(c: Control) -> Font:
	if c is RichTextLabel:
		return c.get_theme_font("normal_font")
	return c.get_theme_font("font")


func _size_of(c: Control) -> int:
	if c is RichTextLabel:
		return c.get_theme_font_size("normal_font_size")
	return c.get_theme_font_size("font_size")


## The font file under a Font (FontVariation and FontFile with fallbacks): "" for Godot's default or a system font.
static func _font_file(f: Font) -> String:
	if f == null:
		return ""
	if f is FontVariation and (f as FontVariation).base_font != null:
		return _font_file((f as FontVariation).base_font)
	if f is FontFile and f.resource_path != "":
		return f.resource_path.get_file()
	return ""


func _check_font(out: Array, c: Control, r: Rect2) -> void:
	var f := _font_of(c)
	var file := _font_file(f)
	var own := _size_of(c)
	var scale := c.get_global_transform_with_canvas().get_scale().y
	var size := int(round(own * scale))
	if file == "" or not allowed.has(file):
		var name := "la fuente por defecto de Godot" if file == "" else file
		_finding(out, "font", "fallo", c, r, "%s a %d (el theme usa %s)" % [name, size, ", ".join(allowed.keys())])
		return
	if size < MIN_SIZE:
		_finding(out, "small_font", "fallo", c, r, "%s a %d px, por debajo del mínimo de %d" % [file, size, MIN_SIZE])
	elif not (allowed[file] as Array).has(own) and not (allowed[file] as Array).has(size):
		_finding(out, "bad_size", "aviso", c, r, "%s a %d px; su tamaño es %s (otro deforma la letra)" % [file, own,
			allowed[file]])


## Whether the text fits: one line wider than its box, wrapped lines that do not fit, a box out of its panel or
## out of the screen.
func _check_fit(out: Array, c: Control, r: Rect2, txt: String, vp: Rect2, world: bool, clip: Control) -> void:
	var f := _font_of(c)
	var size := _size_of(c)
	if c is Label:
		var l := c as Label
		var sb := l.get_theme_stylebox("normal")
		var room := r.size.x - (sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb != null else 0.0)
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var widest := 0.0
			for line: String in txt.split("\n"):
				widest = maxf(widest, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
			if widest > room + 1.0:
				var how := "recortado con «…»" if l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING else \
					("recortado" if l.clip_text else "se sale de su caja")
				_finding(out, "cut", "aviso" if l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING else "fallo", c, r,
					"el texto mide %d px y caben %d: %s" % [widest, room, how])
		else:
			if l.get_line_count() > l.get_visible_line_count() and l.max_lines_visible < 0:
				_finding(out, "cut", "fallo", c, r, "%d líneas y se ven %d" % [l.get_line_count(), l.get_visible_line_count()])
	elif c is Button:
		var b := c as Button
		var sb := b.get_theme_stylebox("normal")
		var room := r.size.x - (sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb != null else 0.0)
		if b.icon != null and not b.expand_icon:
			room -= b.icon.get_width() + b.get_theme_constant("h_separation")
		var w := 0.0
		for line: String in txt.split("\n"):
			w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		if w > room + 1.0 and b.autowrap_mode == TextServer.AUTOWRAP_OFF:
			_finding(out, "cut", "aviso" if b.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING or b.clip_text else "fallo",
				c, r, "el rótulo mide %d px y caben %d" % [w, room])
	elif c is RichTextLabel:
		var rt := c as RichTextLabel
		if not rt.scroll_active and not rt.fit_content and rt.get_content_height() > r.size.y + 2:
			_finding(out, "cut", "fallo", c, r, "el texto pide %d px de alto y tiene %d" % [rt.get_content_height(), r.size.y])
	if world:
		return
	var bounds := vp if clip == null else vp.intersection(screen_rect(clip))
	if not bounds.grow(1).encloses(r) and clip == null:
		_finding(out, "outside", "fallo", c, r, "se sale de la pantalla (%s)" % [_rect(r)])
	if clip != null and not screen_rect(clip).intersection(vp).grow(1).encloses(screen_rect(clip)):
		_finding(out, "outside", "fallo", clip, screen_rect(clip), "la lista %s se sale de la pantalla" % clip.name)
	var box := _panel_of(c)
	if box != null:
		var br := screen_rect(box).grow(1)
		if not br.encloses(r) and br.intersects(r):
			_finding(out, "outside", "aviso", c, r, "se sale de su panel %s" % box.name)


## The panel a control sits in (the nearest PanelContainer or Panel above it).
static func _panel_of(c: Control) -> Control:
	var n := c.get_parent()
	while n != null:
		if n is PanelContainer or n is Panel:
			return n as Control
		if n is ScrollContainer:
			return null   # inside a scroll the rows leave the box by design
		n = n.get_parent()
	return null


## The area the text really covers inside its control (for overlaps and contrast).
func _text_rect(c: Control, r: Rect2, txt: String) -> Rect2:
	if not c is Label:
		return r
	var f := _font_of(c)
	var size := _size_of(c)
	var l := c as Label
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return r
	var w := minf(f.get_string_size(txt.split("\n")[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, r.size.x)
	var x := r.position.x
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x += (r.size.x - w) / 2.0
		HORIZONTAL_ALIGNMENT_RIGHT:
			x += r.size.x - w
	var lines := txt.split("\n").size()
	var h := minf(r.size.y, (f.get_height(size) + l.get_theme_constant("line_spacing")) * lines)
	var y := r.position.y
	match l.vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			y += (r.size.y - h) / 2.0
		VERTICAL_ALIGNMENT_BOTTOM:
			y += r.size.y - h
	return Rect2(x, y, w, h)


func _check_key(out: Array, c: Control, r: Rect2, txt: String) -> void:
	var m := _bracket_re.search(txt)
	if m != null and m.get_string() == txt.strip_edges():   # alone: the greybox of a missing illustration names its id
		_finding(out, "placeholder", "aviso", c, r, "se ve «%s»: falta su ilustración" % txt.strip_edges())
		return
	if m != null:
		_finding(out, "i18n", "fallo", c, r, "se ve «%s» en una frase: un id entre corchetes, sin su texto" % m.get_string())
		return
	for word: String in txt.split(" ", false):
		var w := word.strip_edges().trim_suffix(":").trim_suffix(".").trim_suffix(",")
		if keys.has(w) or (_key_re.search(w) != null and w.count(".") >= 1 and w.contains("_") or keys.has(txt)):
			_finding(out, "i18n", "fallo", c, r, "se ve la clave «%s» en vez de su texto" % w)
			return


## WCAG contrast of the text colour against the most common colour under the text in the capture.
func _check_contrast(out: Array, c: Control, tr: Rect2, img: Image) -> void:
	var fg := c.get_theme_color("font_color")
	if c is BaseButton and (c as BaseButton).disabled:
		fg = c.get_theme_color("font_disabled_color")
	var rect := Rect2i(tr).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if rect.size.x < 3 or rect.size.y < 3:
		return
	var counts: Dictionary = {}
	var step := maxi(1, rect.size.x * rect.size.y / 600)
	var i := 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			i += 1
			if i % step != 0:
				continue
			var p := img.get_pixel(x, y)
			var k := p.to_rgba32() & 0xF8F8F8FF
			counts[k] = int(counts.get(k, 0)) + 1
	var best := 0
	var bg_key := 0
	for k: int in counts:
		if int(counts[k]) > best:
			best = int(counts[k])
			bg_key = k
	var bg := Color.hex(bg_key)
	var ratio := contrast(fg * c.modulate, bg)
	if ratio < CONTRAST_WARN:
		# a town sign is drawn over the art (the most common colour under it is a guess): only a warning there
		_finding(out, "contrast", "fallo" if ratio < CONTRAST_FAIL and not in_world(c) else "aviso", c, tr,
			"contraste %.1f:1 (texto #%s sobre #%s; mínimo %.0f:1)" % [ratio, fg.to_html(false), bg.to_html(false), CONTRAST_WARN])


static func _lum(c: Color) -> float:
	var ch := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * ch.call(c.r) + 0.7152 * ch.call(c.g) + 0.0722 * ch.call(c.b)


static func contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _related(a: Node, b: Node) -> bool:
	return UiDriver.is_inside(a, b) or UiDriver.is_inside(b, a)


static func _layer_of(c: Node) -> int:
	var n := c
	while n != null:
		if n is CanvasLayer:
			return (n as CanvasLayer).layer
		n = n.get_parent()
	return 0


## Two buttons of the same layer on top of each other, or two texts that cross.
func _check_overlaps(out: Array, clicks: Array, texts: Array) -> void:
	for i: int in clicks.size():
		for j: int in range(i + 1, clicks.size()):
			var a: Control = clicks[i]
			var b: Control = clicks[j]
			if _related(a, b) or _layer_of(a) != _layer_of(b) or _top_panel(a) != _top_panel(b):
				continue
			var inter := screen_rect(a).intersection(screen_rect(b))
			if inter.size.x > 2 and inter.size.y > 2:
				_finding(out, "overlap", "fallo", a, inter, "se solapa con %s «%s»" % [UiDriver.path_of(b),
					UiDriver.text_of(b).left(30)])
	for i: int in texts.size():
		for j: int in range(i + 1, texts.size()):
			var a: Control = texts[i][0]
			var b: Control = texts[j][0]
			if _related(a, b) or _layer_of(a) != _layer_of(b) or _top_panel(a) != _top_panel(b):
				continue
			var inter := (texts[i][1] as Rect2).intersection(texts[j][1] as Rect2)
			if inter.size.x > 2 and inter.size.y > 3:
				_finding(out, "overlap", "fallo", a, inter, "el texto pisa a %s «%s»" % [UiDriver.path_of(b),
					UiDriver.text_of(b).left(30)])


## A notice (or the toast) that appeared since the last scan, under a panel that is drawn over it.
func _check_notices(out: Array, root: Window, controls: Array) -> void:
	var fresh: Array = []
	var pop := root.find_child("NoticePopups", true, false)
	if pop != null:
		for n: Node in pop.get_children():
			if n is Control and (n as Control).is_visible_in_tree() and not _seen_notices.has(n.get_instance_id()):
				_seen_notices[n.get_instance_id()] = true
				fresh.append(n)
	var toast := root.find_child("ToastLabel", true, false)
	if toast is Control and (toast as Control).is_visible_in_tree() and not _seen_notices.has(toast.get_instance_id()):
		_seen_notices[toast.get_instance_id()] = true
		fresh.append(toast)
	elif toast is Control and not (toast as Control).is_visible_in_tree():
		_seen_notices.erase(toast.get_instance_id())
	for n: Control in fresh:
		var nr := screen_rect(n)
		for c: Control in controls:
			if not c.is_visible_in_tree() or not (c is PanelContainer or c is Panel or c is ColorRect and c.name == "Veil"):
				continue
			if _related(c, n) or c.mouse_filter == Control.MOUSE_FILTER_IGNORE and not c is PanelContainer:
				continue
			var above := _layer_of(c) > _layer_of(n) or (_layer_of(c) == _layer_of(n) and c.is_greater_than(n))
			var inter := screen_rect(c).intersection(nr)
			if above and inter.get_area() > nr.get_area() * 0.25:
				_finding(out, "covered", "fallo", n, nr, "el aviso «%s» queda debajo de %s" % [UiDriver.text_of(_first_text(n)).left(40),
					UiDriver.path_of(c)])
				break


static func _first_text(n: Node) -> Control:
	if (n is Label or n is Button or n is RichTextLabel) and UiDriver.text_of(n as Control).strip_edges() != "":
		return n as Control
	for c: Node in n.get_children():
		var t := _first_text(c)
		if t != null and UiDriver.text_of(t).strip_edges() != "":
			return t
	return n as Control if n.get_parent() == null else null


## A crop of the capture around `rect` with a red frame (×2, nearest), for the report.
static func mark(img: Image, rect: Array, path: String) -> void:
	var r := Rect2i(int(rect[0]), int(rect[1]), maxi(int(rect[2]), 1), maxi(int(rect[3]), 1))
	var area := r.grow(28).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if area.size.x < 4 or area.size.y < 4:
		return
	var crop := img.get_region(area)
	crop.convert(Image.FORMAT_RGBA8)
	var red := Color(1, 0.15, 0.1)
	var local := Rect2i(r.position - area.position, r.size).intersection(Rect2i(Vector2i.ZERO, crop.get_size()))
	for t: int in 2:
		var g := local.grow(1 + t)
		crop.fill_rect(Rect2i(g.position.x, g.position.y, g.size.x, 1).intersection(Rect2i(Vector2i.ZERO, crop.get_size())), red)
		crop.fill_rect(Rect2i(g.position.x, g.end.y - 1, g.size.x, 1).intersection(Rect2i(Vector2i.ZERO, crop.get_size())), red)
		crop.fill_rect(Rect2i(g.position.x, g.position.y, 1, g.size.y).intersection(Rect2i(Vector2i.ZERO, crop.get_size())), red)
		crop.fill_rect(Rect2i(g.end.x - 1, g.position.y, 1, g.size.y).intersection(Rect2i(Vector2i.ZERO, crop.get_size())), red)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png(path)
