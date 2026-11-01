class_name DayNight
extends RefCounted
## Day/night look (GDD 4.15): the global tint of each phase, blended in from the previous phase over
## transition_minutes, and how far the current phase has gone (HUD bar). Reads the clock config; decides nothing.

const ORDER: Array[String] = ["dawn", "day", "dusk", "night"]


## {"phase", "start", "length", "elapsed"} of the phase at `minute` + `frac` (minutes of the day; night wraps).
static func phase_span(minute: int, frac: float, time: Dictionary) -> Dictionary:
	var starts: Dictionary = time["phase_starts"][Clock.season(minute, time)]
	var m := Clock.minute_of_day(minute) + frac
	var ph := Clock.phase(minute, time)
	var i := ORDER.find(ph)
	var start := float(int(starts[ph]))
	var next_start := float(int(starts[ORDER[(i + 1) % ORDER.size()]]))
	var length := next_start - start
	if length <= 0.0:
		length += Clock.MINUTES_PER_DAY
	var elapsed := m - start
	if elapsed < 0.0:
		elapsed += Clock.MINUTES_PER_DAY
	return {"phase": ph, "start": start, "length": length, "elapsed": elapsed}


## 0..1: how much of the current phase has passed.
static func phase_progress(minute: int, frac: float, time: Dictionary) -> float:
	var s := phase_span(minute, frac, time)
	return clampf(float(s["elapsed"]) / float(s["length"]), 0.0, 1.0)


## The colour of the canvas at `minute` + `frac`: the phase colour (pulled towards white by tint_strength),
## blended from the previous phase's colour during the first transition_minutes of the phase.
static func tint(minute: int, frac: float, time: Dictionary, cfg: Dictionary) -> Color:
	var colors: Dictionary = cfg["colors"]
	var strength := float(cfg.get("tint_strength", 1.0))
	var s := phase_span(minute, frac, time)
	var ph: String = s["phase"]
	var prev: String = ORDER[(ORDER.find(ph) + ORDER.size() - 1) % ORDER.size()]
	var t := clampf(float(s["elapsed"]) / maxf(1.0, float(cfg.get("transition_minutes", 1))), 0.0, 1.0)
	var c := ViewConfig.color(str(colors[prev])).lerp(ViewConfig.color(str(colors[ph])), t)
	return Color.WHITE.lerp(c, strength)
