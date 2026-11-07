# 元气农场 — longer walking periods

Native SwiftUI iPhone app for iOS 17+, named **元气农场**, in `output/Qifarm`. The Xcode project and target remain named Qifarm.

## Run

1. Open `Qifarm.xcodeproj` in Xcode.
2. Select your development team in Signing & Capabilities, use a unique bundle identifier, and keep HealthKit enabled.
3. Connect/select your iPhone, enable Developer Mode if prompted, and Run.
4. Tap **iPhone Health App** and allow **Steps** read access. Tap again to refresh.

The main interface places the **iPhone Health App** button beside a **Total Time** display showing walking minutes across all qualifying periods, excluding breaks. Before loading it shows a dash; while loading it shows “Calculating…”, and an empty successful result shows 0.0 minutes.

After loading, the main page links to two separate pages:

- **Unfiltered** shows all groups after merging breaks under five minutes, before qualification filters. Each entry shows total active minutes, steps, total break minutes, start/end times, and average cadence. Groups are organized by local date, with daily and overall active-time totals. Short and slower groups remain visible. The page also shows the query cutoff captured from the current date at refresh.
- **Filtered** shows only groups exceeding both 30 active minutes and 60 steps per active minute. It displays the required period details, daily and overall qualifying active-time totals, and the bar chart.

The native Swift Charts bar chart uses the same qualifying totals as the filtered date headings. It excludes breaks, starts near the latest activity, and scrolls horizontally through history with a roughly two-week window. Dates without qualifying activity have no bar. VoiceOver reads each bar’s date and minutes. Both pages provide guidance when empty.

The former raw page has been replaced by Unfiltered. For example, same-day periods 14:27–15:15 and 15:17–15:44 now appear as one group there, since their break is two minutes. With 2,493 + 1,791 steps and otherwise continuous activity, the group has 4,284 steps, 75 active minutes, and two break minutes. Its cadence is 57.12 steps per active minute, so it remains absent from Filtered periods.

All periods are HealthKit minute-level estimates, not individual footstep records.

## Calculation rules

1. Form initial periods from consecutive one-minute HealthKit buckets with positive steps. Continuity uses a gap strictly under one minute between readable intervals. A zero or missing bucket ends a period; zero-step groups are omitted.
2. Merge successive periods when the gap from the previous end to the next start is strictly less than five minutes. Exactly five minutes does not merge. Merging continues through a chain of short breaks within the same local date. Midnight is a hard boundary.
3. Keep merged periods only when active time excluding breaks is strictly more than 30 minutes **and** average pace strictly more than 60 steps per walking minute. Average pace is total steps divided by walking minutes excluding breaks. Exactly 60 steps per minute does not qualify. Thresholds apply before display rounding. Both selection thresholds exclude merged breaks. Exactly 30 active minutes does not qualify, even if the start-to-end duration is longer. Displayed walking time subtracts those breaks. Each date and all dates have walking-time totals for qualifying periods only; overnight activity splits into separate date groups before merging and filtering, and each date must qualify independently.

The button analyzes all readable step history, without a fixed cutoff, using monthly query chunks to bound minute allocation. Same-day chunk boundaries do not split the final merged periods. Walks split at local midnight; both endpoint dates are shown. Progress indicates the month being analyzed. Long histories can take time to load.

Periods are estimates at one-minute resolution. HealthKit can distribute longer samples across buckets, so exact gaps between individual steps cannot be recovered. The under-one-minute continuity rule is an estimate based on readable bucket boundaries, not a guarantee about individual footsteps. Start/end times are bucket boundaries, not exact footstep timestamps. The latest bucket ends at query time; today's latest period may be incomplete. Positive fractional step values are retained until display rounding.

Dates use the current calendar/time zone; absolute timestamps determine breaks and elapsed time, including across daylight saving transitions. UTC offsets distinguish repeated hours. HealthKit aggregates sources rather than the app summing overlapping raw samples.

Only Steps read permission is requested, as needed for this feature. Data stays on the device, without uploads or a separate persisted copy. Refresh clears prior results. Empty results may mean no qualifying walks, no data, or denied read access; HealthKit does not disclose which. Manage access in Health → profile → Apps → 元气农场 (menus vary by iOS).

## App icon

An opaque 1024×1024 teal footsteps icon is included in the AppIcon asset catalog and configured for the iOS target. Its vector drawing source is `Tools/GenerateIcon.swift`; regenerate with `swift Tools/GenerateIcon.swift Qifarm/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Verification

```sh
swiftc Qifarm/StepPeriod.swift tests/main.swift -o /tmp/qifarm-period-tests
/tmp/qifarm-period-tests
xcodebuild -project Qifarm.xcodeproj -scheme Qifarm -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/qifarm-minute-build CODE_SIGNING_ALLOWED=NO build
```

Grouping tests cover zero/missing buckets, fractional values, sorting, boundaries, and partial minutes. Merging tests cover strict 5-minute break, 30-minute active-time, and 60-steps-per-minute boundaries, both selection conditions, chain merging, elapsed time including breaks, midnight splits and same-day query boundaries, break-excluded walking duration, and totals.

On an iPhone, validate real Health data, multiple sources, a long history, cross-midnight periods, daylight saving changes, denied/revoked access, query errors, and refresh after edits in Health. Actual Health authorization and data access require device verification.

HealthKit aggregation follows [Apple’s statistics collection query documentation](https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries).

## Web app

Open `web/index.html` in a modern browser, or serve `web/` with a static HTTP server. The app has no runtime dependencies, network requests, account, or server storage. A custom SVG sprout logo is included. This follows the repository’s reorganized `output/` layout rather than recreating the old ignored `lei/output/` directory.

Browsers cannot request HealthKit authorization. On iPhone, read Health data in the native app, tap **Export activity for web app**, and save the JSON file. Transfer that file to the browser’s device and choose **iPhone Health App → Import activity JSON**. Both devices must use the same time zone. Exports contain sensitive activity timestamps and counts; share them only with the intended device. The web app processes them in memory and clears them on reload or **Clear data**.

The web app merges native continuous periods using the same strict five-minute rule, applies the strict active-duration and cadence thresholds, and shows Filtered and Unfiltered views, daily totals, an overall qualifying total, and a daily qualifying-minutes chart. Unfiltered includes cadence and break duration. Invalid, overlapping, future-dated, or cross-midnight input is rejected without replacing existing results. The native export already splits periods at midnight and uses HealthKit’s aggregation across sources. Raw Apple Health XML is not supported because summing its overlapping samples would not reproduce that aggregation.

**Explore demo** loads clearly labeled illustrative activity; it never represents Health authorization or real data. Empty imports display zero minutes. Only dates with qualifying walks have bars.

The version 1 JSON format is `{ "version": 1, "periods": [{ "start": "ISO-8601 timestamp", "end": "ISO-8601 timestamp", "steps": 100, "breakSeconds": 0 }] }`. Periods must not overlap or cross local midnight. Use native exports for correct minute estimates.

Web calculation verification (Node.js): `node web/activity.test.cjs`. Real Health permissions, device export/import, and visual browser layout still need device/browser verification.
