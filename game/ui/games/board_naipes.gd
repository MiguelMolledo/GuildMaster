class_name BoardNaipes
extends GameBoard
## The card table of the envite (docs/ui/mecanicas/juegos.md §Naipes; rules: EnviteMatch): the rival's three cards
## face down at the top, one's own face up at the bottom, and between them the three bazas: each one, when it is
## uncovered, shows both cards and who took it. The stake at play on the right. What each says (raise, want...)
## comes as a word over the side that said it.

const SUIT_COLOR: Dictionary = {"oros": Color(0.85, 0.68, 0.24), "copas": Color(0.72, 0.2, 0.18),
	"espadas": Color(0.3, 0.45, 0.72), "bastos": Color(0.36, 0.55, 0.28)}
const CARD: Vector2 = Vector2(48, 72)  # the art's size (assets/art/ui/games/naipes/, ui_game_naipes): whole pixels

var _shown: int = 0
var _word: Dictionary = {}     # {side, text}: what is being said now
var _shown_bazas: int = 0


func reset() -> void:
	super.reset()
	_shown = 0
	_shown_bazas = 0
	_word = {}


func new_entries(match_: GameMatch) -> Array:
	var lg := match_.log_entries()
	var out: Array = []
	for i: int in range(_shown, lg.size()):
		out.append(lg[i])
	_shown = lg.size()
	_step_time = 0.45
	return out


func _start_entry(e: Dictionary) -> void:
	if str(e["kind"]) == "say":
		_word = {"side": int(e["side"]), "text": tr("games.envite.say.%s" % str(e["action"]))}
	else:
		_word = {}


func _end_entry(e: Dictionary) -> void:
	if str(e["kind"]) == "baza":
		_shown_bazas += 1
	_word = {}


func _on_entries_done() -> void:
	if m != null:
		_shown_bazas = (m.d["bazas"] as Array).size()


func card(at: Vector2, c: String, up: bool, hot: bool = false) -> void:
	var r := Rect2(at, CARD)
	if not up:
		var back := VisualPaths.game_art("naipes", "back")
		if back != null:
			draw_texture_rect(back, r, false)
		else:
			if not "naipes/back" in missing:
				missing.append("naipes/back")
			draw_rect(r, Color(0.45, 0.18, 0.14))
			draw_rect(r.grow(-3), Color(0.6, 0.28, 0.2), false, 1.0)
			draw_rect(r, Color(0.12, 0.08, 0.05), false, 1.0)
		return
	var tex := VisualPaths.game_art("naipes", c)
	if tex != null:
		draw_texture_rect(tex, r, false)
	else:
		if not "naipes/cards" in missing:
			missing.append("naipes/cards")
		var suit := c.get_slice("_", 0)
		var rank := c.get_slice("_", 1)
		draw_rect(r, Color(0.93, 0.88, 0.76))
		draw_rect(r, Color(0.2, 0.15, 0.1), false, 1.0)
		var col: Color = SUIT_COLOR.get(suit, INK)
		text(at + Vector2(4, 16), rank, col.darkened(0.3), 16)
		draw_circle(at + CARD * Vector2(0.5, 0.68), 6.0, col)
		text(at + Vector2(3, CARD.y - 3), tr("games.envite.suit.%s" % suit).substr(0, 1), col.darkened(0.4), 8)
	if hot:
		draw_rect(r.grow(2), GOLD, false, 1.0)


func _draw() -> void:
	missing.clear()
	art_or_box("naipes", "table", Rect2(Vector2.ZERO, size), FELT.darkened(0.1), tr("games.ui.art_missing") % "naipes/table")
	if m == null:
		return
	var em := m as EnviteMatch
	var bz: Array = v.get("bazas", [])
	var nb := mini(bz.size(), _shown_bazas)
	var other := 1 - me
	var hand_me: Array = em.hand(me)
	var hand_ot: Array = em.hand(other)
	var x0 := 8.0
	var top := 4.0
	var low := size.y - CARD.y - 4.0
	# the rival's cards (top) and mine (bottom); a card already played to a baza is shown there instead
	for i: int in 3:
		var shown_ot := m.over() and not playing and int(m.d["folded"]) < 0 and _shown >= m.log_entries().size()
		if i >= nb:
			card(Vector2(x0 + i * (CARD.x + 4), top), str(hand_ot[i]), shown_ot)
			card(Vector2(x0 + i * (CARD.x + 4), low), str(hand_me[i]), true)
	# between the hands: the stake and who is mano
	var lv := int(v.get("level", 0))
	text(Vector2(x0, size.y / 2.0 + 2), tr("games.ui.stake_now") % lv, GOLD, 16)
	text(Vector2(x0, size.y / 2.0 + 12), tr("games.envite.ui.mano") % who(int(v.get("mano", 0))), DIM, 8)
	# the three bazas: the rival's card over mine, the empty slot until it is uncovered
	var bx0 := x0 + 3 * (CARD.x + 4) + 20.0
	for i: int in 3:
		var bx := bx0 + i * (CARD.x + 8)
		text(Vector2(bx, size.y / 2.0 + 4), tr("games.envite.ui.baza") % (i + 1), DIM, 8)
		if i < nb:
			var b: Dictionary = bz[i]
			var cs: Array = b["cards"]
			var w := int(b["winner"])
			card(Vector2(bx, top), str(cs[other]), true, w == other)
			card(Vector2(bx, low), str(cs[me]), true, w == me)
			if w < 0:
				text(Vector2(bx + CARD.x, size.y / 2.0 + 4), tr("games.envite.ui.parda"), DIM, 8, -1.0, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			slot(Vector2(bx, top))
			slot(Vector2(bx, low))
	if not _word.is_empty():  # what one says, over his own cards
		var y := top + CARD.y / 2.0 if int(_word["side"]) == other else low + CARD.y / 2.0
		var f := get_theme_default_font()
		var wtxt := str(_word["text"])
		var ww := f.get_string_size(wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x if f != null else 80.0
		draw_rect(Rect2(Vector2(x0 + 4, y - 14), Vector2(ww + 12, 20)), Color(0.08, 0.06, 0.04, 0.85))
		text(Vector2(x0 + 10, y + 1), wtxt, INK, 16)


## The empty place of a baza not uncovered yet (slot.png, or a dim outline).
func slot(at: Vector2) -> void:
	var tex := VisualPaths.game_art("naipes", "slot")
	if tex != null:
		draw_texture_rect(tex, Rect2(at, CARD), false)
	else:
		draw_rect(Rect2(at, CARD), Color(0, 0, 0, 0.2))
		draw_rect(Rect2(at, CARD), Color(0.5, 0.45, 0.35, 0.5), false, 1.0)


func info_busy() -> Dictionary:
	return {"title": tr("games.envite.ui.playing"), "text": "", "read": ""}


func info(view: Dictionary) -> Dictionary:
	if bool(view.get("over", false)):
		return {"title": tr("games.ui.over"), "text": tr("games.envite.how.%s" % str(m.d["how"])), "read": ""}
	var ph := str(view.get("phase", ""))
	var title := tr("games.envite.prompt.%s" % ph)
	if ph in ["answer", "answer2"]:
		title = title % who(1 - me)
	var txt := tr("games.envite.ui.odds") % roundi(float(view.get("win", 0.0)) * 100.0)
	var g := str(view.get("gesture", ""))
	if g != "":
		txt += " " + tr("games.envite.cue.%s" % g) % who(1 - me) + " " + tr("games.envite.ui.odds_gesture") % \
			roundi(float(view.get("win_gesture", 0.0)) * 100.0)
	var rd := tr("games.ui.reliable") % roundi(float(view.get("read", 0.0)) * 10.0) if g != "" else ""
	if ph in ["answer", "answer2"]:
		rd += ("  ·  " if rd != "" else "") + tr("games.envite.ui.want_at") % roundi(float(view.get("want_at", 0.0)) * 100.0)
	else:
		rd += ("  ·  " if rd != "" else "") + tr("games.ui.read_by") % [who(1 - me), roundi(float(view.get("read_by", 0.0)) * 10.0)]
	return {"title": title, "text": txt, "read": rd}


func log_line(e: Dictionary) -> String:
	if str(e["kind"]) == "baza":
		var w := int(e["winner"])
		var cs: Array = e["cards"]
		return tr("games.envite.ui.log_baza") % [int(e["round"]) + 1, _card_name(str(cs[me])), _card_name(str(cs[1 - me])),
			tr("games.envite.ui.parda") if w < 0 else who(w)]
	return tr("games.envite.ui.log_say") % [who(int(e["side"])), tr("games.envite.say.%s" % str(e["action"]))]


func _card_name(c: String) -> String:
	return tr("games.envite.card") % [tr("games.envite.rank.%s" % c.get_slice("_", 1)), tr("games.envite.suit.%s" % c.get_slice("_", 0))]
