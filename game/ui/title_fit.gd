class_name TitleFit
extends RefCounted
## Titles that must fit their box (docs/ui/00_lenguaje_visual.md §6): a TitleLabel (Jacquard 24) that clips its text
## and does not fit the width it has (a panel's title with a long building or family name: «Libro de cuentas ·
## Herrero» next to the gold) drops to SectionTitle (Pixel Operator Bold 16), and goes back when it fits again. Checked
## whenever the label redraws (a new text or a new size). install() hooks every such label added to the tree.
## View only.

const BIG: StringName = &"TitleLabel"
const SMALL: StringName = &"SectionTitle"


static func install(tree: SceneTree) -> void:
	if not tree.node_added.is_connected(hook):
		tree.node_added.connect(hook)
	for n: Node in tree.root.find_children("*", "Label", true, false):
		hook(n)


static func hook(n: Node) -> void:
	var l := n as Label
	if l == null or not l.clip_text or l.has_meta("title_fit"):
		return
	if l.theme_type_variation != BIG:
		return
	l.set_meta("title_fit", true)
	l.draw.connect(check.bind(l))


## SectionTitle if the text in TitleLabel's font is wider than the label, TitleLabel if it fits. Returns the variation.
static func check(l: Label) -> StringName:
	if l.size.x <= 1.0 or l.text == "":
		return l.theme_type_variation
	var th := l.get_theme_default_font()
	var font := l.get_theme_font("font", BIG) if l.has_theme_font("font", BIG) else th
	var fs := l.get_theme_font_size("font_size", BIG)
	var need := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var want := BIG if need <= l.size.x + 0.5 else SMALL
	if want != l.theme_type_variation:
		if l.is_inside_tree():  # inside the draw: a change now would not be drawn until something else redraws
			l.set_deferred("theme_type_variation", want)
		else:
			l.theme_type_variation = want
		if OS.is_debug_build():
			print("[TitleFit] «%s»: %s (needs %d, has %d)" % [l.text, want, int(need), int(l.size.x)])
	return want
