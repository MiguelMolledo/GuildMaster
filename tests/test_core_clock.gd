extends "res://tests/test_case.gd"
## The one clock (GDD 04 §4.1): derived calendar and the events of each change.

var cat := Catalog.load_from()


func test_calendar_is_derived_from_minute() -> void:
	var t := cat.time
	var dps := int(t["days_per_season"])
	eq(Clock.describe(0, t)["day"], 1, "day counts from 1")
	eq(Clock.season(0, t), "spring", "starts in spring")
	eq(Clock.season(dps * Clock.MINUTES_PER_DAY, t), "summer", "second season")
	eq(Clock.year(Clock.days_per_year(t) * Clock.MINUTES_PER_DAY, t), 1, "a year later")
	eq(Clock.hour(7 * 60 + 59), 7, "hour")


func test_phases_follow_the_season() -> void:
	var t := cat.time
	var s: Dictionary = t["phase_starts"]["spring"]
	eq(Clock.phase(int(s["dawn"]), t), "dawn", "dawn")
	eq(Clock.phase(int(s["day"]), t), "day", "day")
	eq(Clock.phase(int(s["dusk"]), t), "dusk", "dusk")
	eq(Clock.phase(int(s["night"]), t), "night", "night")
	eq(Clock.phase(0, t), "night", "midnight")


func test_tick_emits_changes_only() -> void:
	var st := WorldState.new()
	var t := cat.time
	var counts := {}
	st.clock["minute"] = 0
	for i: int in Clock.days_per_year(t) * Clock.MINUTES_PER_DAY:
		var ev: Array = []
		Clock.tick(st, t, ev)
		for e: Dictionary in ev:
			counts[e["type"]] = int(counts.get(e["type"], 0)) + 1
	var days := Clock.days_per_year(t)
	eq(int(counts.get("hour_changed", 0)), days * 24, "one per hour")
	eq(int(counts.get("day_started", 0)), days, "one per day")
	eq(int(counts.get("season_changed", 0)), 4, "four seasons")
	eq(int(counts.get("year_changed", 0)), 1, "one year")
	eq(int(counts.get("phase_changed", 0)), days * 4, "four phases a day")


func test_calendar_d1b_and_age() -> void:
	var t := cat.time
	eq(int(t["days_per_season"]), 2, "D1(b): 2 days per season")
	eq(Clock.days_per_year(t), 8, "D1(b): 8 days per year")
	var birth := -8 * 25  # born 25 years before day 0
	eq(Clock.age_years(birth, 0, t), 25, "25 at the start")
	var last_minute_of_year := 8 * Clock.MINUTES_PER_DAY - 1
	eq(Clock.age_years(birth, last_minute_of_year, t), 25, "still 25 on the last minute of the year")
	eq(Clock.age_years(birth, last_minute_of_year + 1, t), 26, "26 when the year changes")


func test_dev_time_only_shortens_the_day() -> void:
	var dev := Catalog.load_from("res://data", true)
	eq(int(dev.time["real_seconds_per_day"]), 30, "30 s days in dev")
	eq(Clock.days_per_year(dev.time), Clock.days_per_year(cat.time), "same calendar")
