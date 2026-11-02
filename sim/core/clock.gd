class_name Clock
extends RefCounted
## The one game clock (GDD 04 §4.1, 05 §5.4). The state keeps only clock.minute (minutes since day 0, 00:00);
## day, season, year and phase are derived from the time config (data/time.json, Catalog.time).
## One sim step = one game minute. Real seconds never appear here: the game layer turns them into steps.

const MINUTES_PER_DAY: int = 1440
const PHASES: Array[String] = ["dawn", "day", "dusk", "night"]


static func day(minute: int) -> int:
	return minute / MINUTES_PER_DAY


static func minute_of_day(minute: int) -> int:
	return minute % MINUTES_PER_DAY


static func hour(minute: int) -> int:
	return minute_of_day(minute) / 60


static func days_per_year(time: Dictionary) -> int:
	return int(time["days_per_season"]) * (time["seasons"] as Array).size()


static func season_index(minute: int, time: Dictionary) -> int:
	return (day(minute) / int(time["days_per_season"])) % (time["seasons"] as Array).size()


static func season(minute: int, time: Dictionary) -> String:
	return str(time["seasons"][season_index(minute, time)])


static func year(minute: int, time: Dictionary) -> int:
	return day(minute) / days_per_year(time)


## Age in years of someone born on `birth_day` (negative before the game starts), at `minute`. One calendar year
## (D1(b): 4 seasons × 2 days) is `age_years_per_calendar_year` years of age. Everybody turns a year older at the
## same time, when the calendar year changes (GDD 4.2.5, H8): the age is the difference of calendar years, so a
## child born on the last day of a year is 1 the next day.
static func age_years(birth_day: int, minute: int, time: Dictionary) -> int:
	var dpy := days_per_year(time)
	var years := floori(float(day(minute)) / dpy) - floori(float(birth_day) / dpy)
	return years * int(time.get("age_years_per_calendar_year", 1))


## The phase of the day ("dawn", "day", "dusk", "night") from the season's phase starts (minutes of the day).
static func phase(minute: int, time: Dictionary) -> String:
	var starts: Dictionary = time["phase_starts"][season(minute, time)]
	var m := minute_of_day(minute)
	if m >= int(starts["night"]) or m < int(starts["dawn"]):
		return "night"
	if m >= int(starts["dusk"]):
		return "dusk"
	if m >= int(starts["day"]):
		return "day"
	return "dawn"


## Everything the HUD shows, already derived. Day and year count from 1 for people; the sim counts from 0.
static func describe(minute: int, time: Dictionary) -> Dictionary:
	return {
		"day": day(minute) + 1,
		"day_of_season": day(minute) % int(time["days_per_season"]) + 1,
		"season": season(minute, time),
		"year": year(minute, time) + 1,
		"hour": hour(minute),
		"minute": minute_of_day(minute) % 60,
		"phase": phase(minute, time),
	}


## Advances one game minute and appends the clock events that happened (only changes, never one per minute):
## hour_changed, phase_changed, day_started, season_changed, year_changed.
static func tick(state: WorldState, time: Dictionary, events: Array) -> void:
	var before: int = int(state.clock["minute"])
	var now := before + 1
	state.clock["minute"] = now
	if hour(now) != hour(before):
		events.append({"type": "hour_changed", "hour": hour(now)})
	var ph := phase(now, time)
	if ph != phase(before, time):
		events.append({"type": "phase_changed", "phase": ph})
	if day(now) != day(before):
		events.append({"type": "day_started", "day": day(now)})
		if season_index(now, time) != season_index(before, time):
			events.append({"type": "season_changed", "season": season(now, time)})
		if year(now, time) != year(before, time):
			events.append({"type": "year_changed", "year": year(now, time)})
