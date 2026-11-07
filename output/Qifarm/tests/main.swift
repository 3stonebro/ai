import Foundation

let origin = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 0))
func minute(_ index: Int, _ steps: Double, duration: Double = 60) -> StepMinute {
    let start = origin.addingTimeInterval(Double(index) * 60)
    return StepMinute(start: start, end: start.addingTimeInterval(duration), steps: steps)
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
check(StepPeriod.group([]).isEmpty, "Empty history")
check(StepPeriod.group([minute(0, 0), minute(1, 0)]).isEmpty, "Zero-only groups omitted")
let periods = StepPeriod.group([minute(0, 12), minute(1, 8), minute(2, 0), minute(3, 4)])
check(periods.count == 2, "Zero minute splits periods")
check(periods[0].start == origin && periods[0].end == origin.addingTimeInterval(120), "Start/end boundaries")
check(periods[0].steps == 20 && periods[1].steps == 4, "Summed period totals")
check(StepPeriod.group([minute(0, 1), minute(2, 2)]).count == 2, "Missing minute splits periods")
let fractional = StepPeriod.group([minute(1, 0.75), minute(0, 0.5)])
check(fractional.count == 1 && fractional[0].steps == 1.25, "Positive fractions retained and input sorted")
let partial = StepPeriod.group([minute(0, 3), minute(1, 2, duration: 15)])
check(partial[0].end == origin.addingTimeInterval(75), "Current minute capped at query time")
let dst = StepPeriod.group([minute(59, 2), minute(60, 3)])
check(dst.count == 1 && dst[0].steps == 5, "Continuity uses absolute time across clock changes")
print("All walking-period grouping checks passed.")

func period(_ startMinute: Double, _ endMinute: Double, _ steps: Double) -> StepPeriod {
    StepPeriod(start: origin.addingTimeInterval(startMinute * 60),
               end: origin.addingTimeInterval(endMinute * 60), steps: steps)
}
check(StepPeriod.qualifying([]).isEmpty, "Empty periods")
check(StepPeriod.qualifying([period(0, 30, 3000)]).isEmpty, "Exactly 30 minutes excluded")
check(StepPeriod.qualifying([period(0, 31, 1860)]).isEmpty, "Exactly 60 steps/minute excluded")
check(StepPeriod.qualifying([period(0, 31, 1859)]).isEmpty, "Below 60 steps/minute excluded")
check(StepPeriod.qualifying([period(0, 31, 1861)]).count == 1, "Above both strict thresholds")
let merged = StepPeriod.qualifying([period(20, 35, 1000), period(0, 16, 1000)])
check(merged.count == 1 && merged[0].steps == 2000 && merged[0].elapsedMinutes == 35,
      "Merge before filtering; elapsed time includes break")
check(merged[0].walkingMinutes == 31, "Walking time excludes four-minute break")
check(merged[0].averageStepsPerMinute > 60 && merged[0].steps / merged[0].elapsedMinutes < 60,
      "Pace denominator excludes breaks")
check(StepPeriod.qualifying([period(0, 16, 2000), period(21, 37, 2000)]).isEmpty,
      "Exactly five-minute break must not merge")
check(StepPeriod.qualifying([period(0, 16, 2000), period(22, 38, 2000)]).isEmpty,
      "Longer break must not merge")
let chained = StepPeriod.qualifying([period(0, 11, 1000), period(15, 26, 1000), period(30, 41, 1000)])
check(chained.count == 1 && chained[0].steps == 3000, "Chained merges")
check(chained[0].walkingMinutes == 33, "Chained breaks excluded from active duration")
let midnight = StepPeriod.qualifying([period(1420, 1440, 2000), period(1440, 1455, 1500)])
check(midnight.isEmpty, "Midnight splits into independently filtered short periods")
check(StepPeriod.qualifying([period(0, 45, 0)]).isEmpty, "Zero steps ignored")
check(period(0, 0, 0).averageStepsPerMinute == 0, "Zero duration safe")
check(StepPeriod.qualifying([period(0, 20, 2398), period(24, 44, 1)]).isEmpty,
      "Filter uses aggregate pace after merging, not individual paces")
check(abs(partial[0].walkingMinutes - 1.25) < 0.0001, "Partial minute walking duration")
check([merged[0], chained[0]].reduce(0) { $0 + $1.walkingMinutes } == 64,
      "Walking totals exclude every break")
print("All merging, pace-threshold, and walking-time checks passed.")

let midnightBuckets = StepPeriod.group([minute(1439, 100), minute(1440, 100)])
check(midnightBuckets.count == 2, "Initial continuous period splits at midnight")
let qualifyingDays = StepPeriod.qualifying([period(1400, 1440, 4000), period(1440, 1480, 4000)])
check(qualifyingDays.count == 2, "Long overnight walk produces two qualifying dates")
check(qualifyingDays.reduce(0) { $0 + $1.walkingMinutes } == 80, "Midnight split preserves active total")
let subminute = StepPeriod.group([minute(0, 100, duration: 1), minute(1, 100)])
check(subminute.count == 1 && subminute[0].breakSeconds == 59, "Gap under one minute is continuous")
let exactMinute = StepPeriod.group([
    StepMinute(start: origin, end: origin.addingTimeInterval(1), steps: 100),
    StepMinute(start: origin.addingTimeInterval(61), end: origin.addingTimeInterval(120), steps: 100)])
check(exactMinute.count == 2, "Exactly one minute is not continuous")
let chunkBoundary = StepPeriod.qualifying([period(0, 20, 2000), period(20, 40, 2000)])
check(chunkBoundary.count == 1, "Same-day query boundary still merges")
print("All midnight and continuity checks passed.")

let rawShort = StepPeriod.continuous([period(0, 2, 10), period(4, 6, 10)])
check(rawShort.count == 2, "Raw page retains separate short/slow periods without five-minute merging")
check(StepPeriod.qualifying(rawShort).isEmpty, "Raw periods can exist without qualifying periods")
let rawChunks = StepPeriod.continuous([period(0, 20, 2000), period(20, 40, 2000)])
check(rawChunks.count == 1 && rawChunks[0].walkingMinutes == 40, "Raw continuity rejoins query boundaries")
check(StepPeriod.continuous([period(1439, 1440, 100), period(1440, 1441, 100)]).count == 2,
      "Raw page preserves midnight split")
check(StepPeriod.continuous([period(0, 1, 100), period(2, 3, 100)]).count == 2,
      "Raw continuity excludes exactly one-minute breaks")
print("All raw-period checks passed.")

check(StepPeriod.qualifying([period(0, 10, 1000), period(14, 24, 1000), period(28, 38, 1000)]).isEmpty,
      "Exactly 30 active minutes excluded despite 38 elapsed minutes and high cadence")
check(StepPeriod.qualifying([period(0, 15, 1500), period(19, 33, 1400)]).isEmpty,
      "Under 30 active minutes excluded despite over 30 elapsed minutes")
check(StepPeriod.qualifying([period(0, 15, 1500), period(19, 34.01, 1501)]).count == 1,
      "Just over 30 active minutes qualifies with sufficient cadence")
print("All active-duration threshold checks passed.")

let reportedGroups = StepPeriod.grouped([period(867, 915, 2493), period(917, 944, 1791)])
check(reportedGroups.count == 1, "14:27–15:15 and 15:17–15:44 merge on Grouped page")
check(reportedGroups[0].steps == 4284 && reportedGroups[0].walkingMinutes == 75,
      "Grouped example preserves steps and active minutes")
check(reportedGroups[0].breakSeconds == 120, "Grouped example displays two break minutes")
check(!reportedGroups[0].isQualifying, "Grouped example remains visible despite failing cadence")
check(StepPeriod.grouped([period(0, 15, 100), period(20, 35, 100)]).count == 2,
      "Grouped page preserves exact-five-minute boundary")
print("All grouped-page checks passed.")
