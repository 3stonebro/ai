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
let merged = StepPeriod.qualifying([period(20, 35, 1200), period(0, 16, 1200)])
check(merged.count == 1 && merged[0].steps == 2400 && merged[0].elapsedMinutes == 35,
      "Merge before filtering; elapsed time includes break")
check(merged[0].walkingMinutes == 31, "Walking time excludes four-minute break")
check(abs(merged[0].averageStepsPerMinute - 2400.0 / 35) < 0.00001,
      "Cadence denominator includes breaks")
check(StepPeriod.qualifying([period(20,35,1000),period(0,16,1000)]).isEmpty,
      "Active cadence over 60 cannot qualify when elapsed cadence is below 60")
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
check(StepPeriod.qualifying([period(0, 15, 1500), period(19, 34.01, 2000)]).count == 1,
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

func trail(_ meters: Double?, minutes: Double = 60) -> TrailActivity {
    TrailActivity(id: "test", name: "Walk", start: origin, end: origin.addingTimeInterval(7200),
                  movingMinutes: minutes, distanceMeters: meters, elevationGainMeters: nil)
}
check(trail(2000).isQualifying, "Exactly 2 km/h retained")
check(trail(5000).isQualifying, "Exactly 5 km/h retained")
check(!trail(1999.99).isQualifying, "Just below 2 km/h excluded before rounding")
check(!trail(5000.01).isQualifying, "Just above 5 km/h excluded before rounding")
check(trail(2000, minutes: 30).averageSpeedKmh == 4, "Uses workout duration rather than elapsed time")
check(!trail(nil).isQualifying, "Missing distance excluded")
check(!trail(0).isQualifying, "Zero speed excluded")
check(!trail(1000, minutes: 0).isQualifying, "Zero duration excluded")
check(!trail(-1).isQualifying, "Negative distance excluded")
check(!trail(.infinity).isQualifying, "Nonfinite distance excluded")
check(!trail(3000, minutes: 150).isQualifying, "Duration exceeding elapsed time excluded")
let encodedTrails = TrailExport(version: 1, source: "alltrails", activities: [trail(2000),
    TrailActivity(id: "other", name: "Too fast", start: origin, end: origin.addingTimeInterval(7200),
                  movingMinutes: 60, distanceMeters: 6000, elevationGainMeters: nil)])
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
let decodedTrails = try TrailExport.read(encoder.encode(encodedTrails))
check(decodedTrails.count == 2 && decodedTrails.filter(\.isQualifying).count == 1, "Export/import preserves raw and processed activities")
check(decodedTrails.filter(\.isQualifying).reduce(0) { $0 + $1.movingMinutes } == 60, "Qualifying minutes exclude fast activity")
print("All overall-average-speed and export checks passed.")

check(HealthTrailWorkout.isAllTrails(sourceName: "AllTrails", bundleIdentifier: "com.example.app"), "AllTrails source name recognized")
check(HealthTrailWorkout.isAllTrails(sourceName: "Localized name", bundleIdentifier: "com.alltrails.AllTrails"), "AllTrails bundle component recognized")
check(!HealthTrailWorkout.isAllTrails(sourceName: "Apple Watch", bundleIdentifier: "com.apple.health"), "Other workout sources excluded")
check(!HealthTrailWorkout.isAllTrails(sourceName: "NotAllTrails", bundleIdentifier: "com.example.notalltrails"), "Partial source matches excluded")
print("All Health workout source checks passed.")


check(AuthCallback.message(for: URL(string: "qifarm://auth/callback#access_token=ignored")!) != nil, "App confirmation return recognized")
check(AuthCallback.message(for: URL(string: "https://auth/callback")!) == nil, "Unexpected callback scheme ignored")
check(AuthCallback.message(for: URL(string: "qifarm://other/callback")!) == nil, "Unexpected callback host ignored")
check(AuthCallback.message(for: URL(string: "qifarm://auth/other")!) == nil, "Unexpected callback path ignored")
check(AuthCallback.message(for: URL(string: "qifarm://user@auth/callback")!) == nil, "Callback credentials rejected")
check(AuthCallback.message(for: URL(string: "qifarm://auth/callback#error=access_denied&error_code=otp_expired")!)?.contains("expired") == true, "Expired link gives actionable message")
let signupComponents = URLComponents(string: AuthCallback.signupPath)!
check(signupComponents.queryItems?.first(where: { $0.name == "redirect_to" })?.value == AuthCallback.redirectURL,
      "Signup requests native confirmation return")
print("All native confirmation callback checks passed.")


check(RegistrationResponse.isDuplicate(["identities": []]), "Direct obfuscated user detected")
check(RegistrationResponse.isDuplicate(["user": ["identities": []]]), "Nested obfuscated user detected")
check(!RegistrationResponse.isDuplicate(["identities": [["id": "new-identity"]]]), "New user identity is not duplicate")
check(!RegistrationResponse.isDuplicate(["id": "unknown"]), "Missing identities does not prove a duplicate")
check(RegistrationResponse.isDuplicateError(code: "user_already_exists", message: "Conflict"), "Duplicate auth code detected")
check(RegistrationResponse.isDuplicateError(code: nil, message: "User already registered"), "Standard duplicate error detected")
check(!RegistrationResponse.isDuplicateError(code: nil, message: "Email rate limit exceeded"), "Rate limit is not duplicate registration")
print("All registration-response checks passed.")


let repeatedPeriods = StepPeriod.grouped([period(0, 40, 4000), period(0, 40, 4000)])
check(repeatedPeriods.count == 1 && repeatedPeriods[0].steps == 4000, "Repeated period does not inflate totals")
let updatedPeriods = StepPeriod.deduplicated([period(0, 40, 4000), period(0, 40, 4200)])
check(updatedPeriods.count == 1 && updatedPeriods[0].steps == 4200, "Updated period replaces same interval")
check(TrailActivity.deduplicated([trail(2000), trail(4000)]).count == 1, "Repeated workout ID stored once")
check(TrailActivity.deduplicated([trail(2000), trail(4000)])[0].distanceMeters == 4000, "Latest workout reading replaces old values")
print("All activity identity and repeated-refresh checks passed.")

check(period(0, 30, 1000).filterExplanation.contains("active time must exceed") && period(0, 30, 1000).filterExplanation.contains("cadence must exceed"), "Both failing Health rules explained")
check(period(0, 31, 1860).filterExplanation.contains("cadence must exceed"), "Exact cadence boundary explained")
check(period(0, 31, 1900).filterExplanation.hasPrefix("Passed"), "Qualifying Health group marked passed")
check(trail(nil).filterExplanation.contains("missing distance"), "Unavailable AllTrails speed explained")
check(trail(1000).filterExplanation.contains("below 2"), "Slow AllTrails activity explained")
check(trail(6000).filterExplanation.contains("above 5"), "Fast AllTrails activity explained")
print("All activity pass/fail explanation checks passed.")


let stepSnapshot = """
{"version":1,"periods":[{"start":"2026-01-01T09:00:00.000Z","end":"2026-01-01T10:00:00Z","steps":4000,"breakSeconds":60}]}
"""
let restoredSnapshot = try StepHistoryArchive.read(Data(stepSnapshot.utf8))
check(restoredSnapshot.count == 1 && restoredSnapshot[0].walkingMinutes == 59, "Cloud restore keeps active duration and supports fractional timestamps")
for invalid in ["{}", stepSnapshot.replacingOccurrences(of: "4000", with: "-1"),
                stepSnapshot.replacingOccurrences(of: "\"breakSeconds\":60", with: "\"breakSeconds\":3600"),
                stepSnapshot.replacingOccurrences(of: "10:00:00Z", with: "08:00:00Z")] {
    do { _ = try StepHistoryArchive.read(Data(invalid.utf8)); fatalError("Malformed snapshot accepted") }
    catch { }
}
print("All revised-spec snapshot restoration checks passed.")

func interval(_ start: Double, _ end: Double, _ minutes: Double) -> QualifiedActivityInterval {
    QualifiedActivityInterval(start: origin.addingTimeInterval(start*60), end: origin.addingTimeInterval(end*60), minutes: minutes)
}
check(ActivityTotals.uniqueMinutes([]) == 0, "No qualifying intervals")
check(ActivityTotals.uniqueMinutes([interval(0,60,60),interval(0,60,60)]) == 60, "Same walk from two sources counted once")
check(ActivityTotals.uniqueMinutes([interval(0,60,60),interval(30,90,60)]) == 90, "Partially overlapping walks counted once")
check(ActivityTotals.uniqueMinutes([interval(0,60,40),interval(0,60,50)]) == 50, "Overlapping summaries use highest active fraction")
check(ActivityTotals.uniqueMinutes([interval(0,60,60),interval(60,120,60)]) == 120, "Adjacent activities remain separate in total")
check(ActivityTotals.uniqueMinutes([interval(0,0,100)]) == 0, "Invalid interval ignored")
print("All cross-source overlap and elapsed-cadence checks passed.")

let farmPlace = FarmPlace(country: "Canada", province: "Ontario", city: "Toronto")
check(farmPlace.displayValue == "Canada, Ontario, Toronto", "Farm location display order")
check(FarmPlace(storedValue: farmPlace.storedValue) == farmPlace, "Structured location round trip")
check(FarmPlace().storedValue.isEmpty && FarmPlace(storedValue: "").displayValue.isEmpty, "Unspecified location remains empty")
check(FarmPlace(country: "Canada", city: "Toronto").displayValue == "Canada, Toronto", "Missing province does not add empty separators")
check(FarmPlace(storedValue: "43.7, -79.4").displayValue.isEmpty, "Old coordinates are not shown as place names")
check(FarmPlace(storedValue: "Canada, Ontario, Toronto") == farmPlace, "Existing place names remain readable")
check(FarmPlace(storedValue: "Toronto").city == "Toronto", "Legacy manual city remains available")
print("All country/province/city location checks passed.")
