# 元气农场 — Native iPhone app

Requirements source: **`docs/prd_qifarm_revised.md`**. Project: `output/Qifarm/Qifarm.xcodeproj`, iOS 17+. Web development remains paused; retained `web/` files are not updated for this version.

## Install and run

Open the Xcode project, select your signing team and iPhone, and Run. HealthKit stays enabled. The existing icon, Chinese display name, Keychain sessions, and `qifarm://auth/callback` confirmation link are retained. Supabase Authentication must allow that exact redirect URL. New registration returns to My Dashboard without signing in; confirmation links return there as well. Log in explicitly after confirming email. Already signed-in users are not logged out by confirmation links.

## Required database migration

Apply these in order in the Supabase SQL Editor for project `axhsgohjnymxunvfavxe`:

1. `supabase/schema.sql` — initial profiles and source metadata (previously applied).
2. `supabase/activity-storage.sql` — normalized activity storage (previously applied).
3. **`supabase/community.sql` — new for this version.** Adds scores, private preferences, buddies/circles, aggregate statistics, and overlap-aware overall totals. Existing activities are retained.
4. `supabase/community-test.sql` — new transaction-based acceptance tests; synthetic users and data roll back. The updated `rls-test.sql` and existing `activity-storage-test.sql` remain useful regression checks.

The new migration has been parsed as SQL and PL/pgSQL but has **not** been applied or executed against the live database in this session. New community/profile requests will show setup errors until it is installed. No administrator key is placed in the app. The configured publishable key and signed-in session access the database under RLS; security-definer RPCs derive the owner from `auth.uid()` and explicitly check social membership.

## Navigation and dashboard

A three-bar menu button with a dropdown list remains visible across dashboard, source details, buddies, leaderboard, sponsors, awards, and settings. While signed out, My Dashboard shows Register / Log in and the other menu items are disabled. Confirmation guidance may also appear after registration.

The signed-in dashboard shows nickname, sign out, qualifying minutes, and **精 · Jin = 100, 气 · Qi = 0, 神 · Shen = 0** initially. The requirements define no score-growth formula; no growth rule is invented. Scores are stored privately in the user profile.

Custom app buttons retain the same 120 × 64 point style. Source details remain a separate screen with Go back. UI uses adaptive system surfaces and a forest-green accent palette. Actual-device layout, accessibility scaling, and dark-mode appearance still need visual review.

## Data sources

Data Sources contains Add source, Delete source, Refresh all, and a source menu beside Qualifying Activity. iPhone Health is offered when HealthKit is available. **Check AllTrails availability** requests Workouts read access and queries readable HealthKit source attribution; AllTrails becomes addable when its synced source is found. This checks readable data availability, not private app installation state. Enable AllTrails → Apple Health syncing and save a workout if it is not found. Existing cloud sources remain viewable even if the device cannot refresh them.

**Reopening restores saved cloud data only. It does not automatically refresh HealthKit.** Refresh all is the explicit device-query action. Add Source first creates/restores its cloud record; choose Refresh all to retrieve device data. Full successful saves replace stale activity records atomically. Activities are keyed by user/source plus HealthKit workout UUID or absolute Health period start/end. Failed retrieval/save reports an error and does not pretend a save succeeded. Ambiguous empty Health reads preserve previous nonempty results because HealthKit cannot distinguish denied read access from no readable history.

Deleting a source removes its cloud row and cascades to its activities, then clears the local source and updates totals. The original Health/AllTrails records are untouched. Failed cloud deletion preserves local data. A later stale refresh cannot recreate a deleted source.

Each detail screen has **Only show qualifying activity**. It changes visible rows/date groups, never stored records or totals. With the filter off, passed and failed activities remain visible with reasons and text/icon indicators.

### iPhone Health

Read all accessible step history through query time in monthly one-minute chunks. Positive buckets form continuous periods with gaps strictly under one minute. Merge periods across breaks strictly under five minutes, within the same local date; midnight splits groups.

**Clarified cadence rule:** total steps divided by **total elapsed minutes, including breaks**. Active time still excludes breaks. A group qualifies only if active time is **more than 30 minutes** and elapsed-time cadence is **more than 60 steps/minute**. Thresholds are tested before rounding. Exactly 30 active minutes or 60 steps/elapsed minute fails.

Data shows the source qualifying total and daily chart at the top, followed by date totals and period start/end, elapsed duration, active time, breaks, steps, cadence, and pass/fail reasons. Health minute buckets are estimates rather than exact footsteps.

### AllTrails

Read AllTrails-attributed HealthKit workouts after enabling AllTrails-to-Health sync. Average speed = recorded kilometers / Health workout duration in hours. Qualifying speed is **2–5 km/h inclusive**. Missing/invalid distance or zero/invalid duration fails. Workout duration is the app's moving-time metric and may differ from AllTrails' own calculation. Show recorded distance, optional elevation, timestamps, speed, moving time, and qualification reason. Do not apply the step-duration/cadence rules to AllTrails.

### Cross-source deduplication

Source-specific totals are unchanged. The dashboard/profile/leaderboard overall total counts overlapping activity once using a time-interval sweep. Summary records do not locate every pause: active minutes are spread uniformly across each record's elapsed interval, and overlapping intervals use the highest active fraction instead of adding fractions. Identical full-duration walks count once; partial overlaps count only their nonoverlapping portions. This is a documented overlap estimate, not guaranteed identity matching between providers.

Both native `ActivityTotals.uniqueMinutes` and SQL `qifarm_unique_minutes` use this rule. SQL reconstructs Health groups using the profile's time zone and includes breaks in cadence. Manual source refresh passes the current device time zone. Existing profiles start with UTC; restoration synchronizes the profile time zone and recomputes stored statistics when it differs from the device, without refreshing HealthKit. A one-time migration recomputes saved overall totals under the new rules. The migration also recalculates stored per-source minutes; later manual refreshes maintain them.

## Buddies and circles

Friends are a personal list added by registered email address; adding one does not expose private workouts, location, or arbitrary users' emails. The app does not send email messages or OS notifications. The friend list is unilateral; the PRD does not specify friend-request approval.

Create a named circle, then invite existing friends. Invitations are stored in-app. Only invited users can Join. Joined members can invite their own friends. A user may decline an invitation or leave a circle. Circle membership and invited/joined status are shown. Shared circle metadata is visible only through membership-scoped RPCs; raw source records remain private. Sponsors and Awards are intentional empty lists.

## Leaderboard

Shows registered-user count, global qualifying minutes, global Jin/Qi/Shen totals, the current user's values, and their percentages. A zero global denominator displays 0%. Only aggregate statistics plus the current user's own metrics are returned—no other user's private activity or location. These are account-reported activity statistics, not independently verified competition results.

## Language and location

Settings offers English and Simplified Chinese. The string catalog translates navigation, controls, account forms, source labels, qualification messages, and common detail fields. Supabase/server error text is displayed as returned and may remain English. Language selection takes effect immediately on this device; Save settings persists it to the profile for later restoration.

Registration requests optional location permission when switching to registration. Denial or failure leaves location empty and registration can continue. The app reverse-geocodes an authorized device location into country, province/state, and city. It stores those names, not GPS coordinates or a tracking history. Settings provides separate editable country, province/state, and city fields, plus current-location lookup and clear/save controls. Locations are private and absent from leaderboard/social responses.

## Validation

```sh
swiftc -module-cache-path /tmp/qifarm-swift-cache Qifarm/StepPeriod.swift tests/main.swift -o /tmp/qifarm-tests
/tmp/qifarm-tests
xcodebuild -project Qifarm.xcodeproj -scheme Qifarm -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/qifarm-community-build CODE_SIGNING_ALLOWED=NO build
```

Foundation tests cover grouping, cadence including breaks, strict boundaries, pass/fail explanations, duplicate records, snapshot validation, and cross-source overlaps. SQL acceptance tests cover initial scores, overlap totals, friend addition, circle invitation/join/leave, private-data isolation, and blocked anonymous statistics. SQL/PLpgSQL parsing is not a live database execution test. Real Supabase migration execution, authenticated social actions, language appearance, location permission, and HealthKit data require on-device/live verification.

New source/resources/SQL files under `output/` remain excluded by the repository's current `.gitignore`. Existing user changes have been preserved; nothing was committed or deployed in this task.

The navigation menu now uses a three-bar button instead of a horizontal screen list. The current screen is labeled alongside it, and the selected dropdown item is marked. Signed-out users can only choose My Dashboard. The signed-in dashboard displays **Farm location** from the private saved profile; its value remains empty when unspecified. Location changes saved in Settings update the same profile used by the dashboard. No database migration is needed for this layout update.

The shared top header now aligns the three-bar navigation button and signed-in nickname on the same row on every main/detail screen. The current screen name appears as secondary text beneath the nickname. Dashboard and source-management sections use their own headings rather than repeating the nickname. Signed-out navigation continues to show the current screen name with other destinations disabled. No database change is required.

The shared header now contains the three-bar menu, nickname/current screen, and **Log out** on one horizontal row across signed-in screens. Logout is hidden when signed out and disabled during source sync or authentication work. Duplicate logout controls were removed from dashboard/source content. A shared 120 × 64 point custom-action width keeps both header controls and other app action buttons consistently sized while leaving room for the nickname.


Farm location is now displayed in **country, province/state, city** order. Missing components are omitted; an unspecified location stays empty. The existing private `location` text column stores a compact structured JSON value, so no database migration is needed. Registration uses the same named location. Existing comma-separated place names remain readable. Older coordinate-only values are not misrepresented as names: the dashboard prompts the user to update them in Settings. Device permission, Apple reverse-geocoding service availability, and actual location results require iPhone testing. If geocoding fails, the user may leave location empty or enter names manually.

Dashboard layout follows the latest listed order: farm location, Jin/Qi/Shen scores, then qualifying activity time. Location now uses separate Country, Province / State, and City labeled rows with empty values when unspecified, instead of a single comma-separated display line. The existing structured location storage and Settings editor are retained.
