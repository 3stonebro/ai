# 元气农场 — iOS App Requirements

## 1. Scope

Create a native iPhone app named **元气农场**, including an iOS app icon. Web-app development is outside the current scope.

Save the project in `./output/Qifarm`, following the repository’s current structure. This replaces the older `./lei/output` location.

## 2. Interface

There is a menu button which three bars shown at the same level as the username and logout button, when clicked there is a dropdown list of following options, when an option is clicked, the corresponding screen is shown:
- my dashboard
- data sources
- buddie 
- leaderboard
- sponsors 
- awards
- settings

When an option is clicked, the corresponding screen shows. 

### My Dashboard
Shows the following information
- farm location (location of the user, empty if not specified) shown as country, province/state, and city
- the 精(Jin), 气(Qi), 神(Shen) scores
- initially 精(Jin) = 100, 气(Qi) = 0, 神(Shen) = 0. 
- the total qualifying activity time in minutes, across all enabled sources. 

### Data Sources
On this this screen, there are following controls:

- **Add source:** Choose from available sources, initially **iPhone Health** and **AllTrails**. A source can be showed if it is available on the device running the app and enabled only once per user. 

- **Delete source:** Choose an enabled source to remove.

- **Refresh all:** Retrieve the latest data from every enabled source, recalculate results, and save successful updates to Supabase.

- **Data sources:** A dropdown beside the **Qualifying Activity** label, listing the user’s enabled sources. Selecting a source opens its detail screen.

- **Source Detail:**
Show the selected source’s name, and shows activity records and qualification results according to the source-specific rules below. Passed and failed records remain visible for inspection. Only passed records contribute to qualifying totals and charts. 

A option "only show qualifying activity", when selected show only qualifying activity (i.e., hide failed activitiy).

The overall total is the sum of source totals. A walk recorded in both sources may be counted only once. 

### Buddies

#### Friends:
- Allow the user to add and delete friends by user emails
- When a user add a friend, the other user has to approve, once approve friends can see each other
- Show all current friends

#### Circles:
- Allow the user to create circle (friend groups) by inviting his friends 
- Show all current circles the user is in
- Allow the user to join and leave circles. 

### Leaderboard
Show global statistics
- all registered users, total qualifying activitiy time in minutes across all users, total  精(Jin), 气(Qi), 神(Shen) scores across all users.
- the total qualifying activitiy time 精(Jin), 气(Qi), 神(Shen) scores for the user and their percentage over total number across all users.

### Sponsors 
- A list of sponsors 
- currently empty

### Awards
- A list of awards the user has received 
- currently empty

### Settings
A list of options
- Language: when clicked the user can choose the language for the app, currently include Eglish, Chinese
- Location: allow user to set / change currently location. 

### Visual design
- Use a professional, consistent visual style, with clear typography, spacing, and hierarchy.
- Give custom action buttons a consistent size and consistent enabled, disabled, and selected states.
- Clearly distinguish the upper summary/navigation section from the lower activity-data section using spacing, surfaces, borders, or headings.
- Identify pass/fail results with text or icons as well as color.

## 3. Accounts and Workflows

### Registration and verification

1. Before a user signed in, and after signed out, show only **Register / Log in** button in the My Dashboard Screen and make that screen is visible.  All other menu bar option is greyed out and not clickable. 
2.  When the register/log in button is clicked, show the register / sign form. 
3. When signed in, replace that button with the user’s nickname, a sign out button in the My Dashboard Screen, and all options in the top menu bar become available to click. 
4. The registration and verification process does the following:
    - Collect email, password, and nickname for registration.
    - Collect the user's location with the user's permission. 
    - Leave the location empty if the user denied.
    - After successful registration, close the registration form and return to My Dashboard screen. Show instructions to verify the email address. Registration does not automatically sign the user in.
5. If Supabase identifies the account as already registered, show a popup stating **“User already registered.”** Closing the popup returns to the initial screen.
6. Supabase may conceal some duplicate-account states. Do not describe an ambiguous response as proof that an account exists.
7. Opening the verification email link on the iPhone returns to the app’s initial **My Dashboard** screen. The user then logs in explicitly. Do not log out an already signed-in user merely because a verification link was opened.

### Sessions and reopening

- Persist the user’s session securely so closing and reopening the app does not require another login.
- Keep the user signed in until they log out, unless Supabase invalidates the session.
- On reopening, restore saved source data and do not automatically refresh all enabled sources.
- Report network, permission, and synchronization errors without presenting failed updates as successful saves.

### Source deletion

- Let the user choose and confirm which enabled source to delete.
- Delete the source and its saved activity data from the user’s Supabase account.
- After successful deletion, remove it from the app and update qualifying totals.
- If deletion fails, keep the source and its data visible and report the error.
- Do not delete original records from Apple Health or AllTrails.
- The user may add a deleted source again later.

## 4. Supabase Storage

### User data

Use **Supabase Auth** for email/password authentication. Passwords must be managed by Supabase Auth; do not store plaintext passwords in application tables.

Store a user profile containing:

- User ID.
- Email address.
- Nickname.
- Total qualifying activity time across enabled sources.

Restrict each user’s profile and activity data to that user through authentication and row-level security.

### Source and activity data

Store each source’s ID, name, owner, activity records, qualifying total, and last-update timestamp. Preserve the raw values needed to reproduce the calculations below.

Repeated refreshes must update existing records rather than create duplicates:

- Identify a source by its owner and source ID.
- Identify an AllTrails workout by its owner, source ID, and stable HealthKit workout ID.
- Identify a Health activity period by its owner, source ID, and absolute start/end timestamps.
- Index activity dates for date-based retrieval. Use the user’s local calendar for display grouping.
- Apply source updates atomically. Replace changed values and remove obsolete records when a complete, successful refresh replaces the source dataset.
- Cascade source deletion to its saved activities and recalculate the user’s total.

### Project configuration

- **Project URL:** `https://axhsgohjnymxunvfavxe.supabase.co`
- **Publishable key:** `sb_publishable_c0lUaPKmEGVenjLk7GC-Ig_fqvIO5QE`
- **Native confirmation redirect:** `qifarm://auth/callback`

Allow the native confirmation redirect in Supabase Authentication URL Configuration. Client apps must use the publishable key and the signed-in user’s session, never an administrative or service-role key.

## 5. iPhone Health

### Retrieval and grouping

Request permission to read Steps through Apple HealthKit and retrieve all available readable step history through the current refresh time.

1. Form continuous activity periods when gaps between activity intervals are **less than 1 minute**.
2. Merge consecutive periods when the break between them is **less than 5 minutes**.
3. Split periods at local midnight before qualification; each date qualifies independently.
4. At minute-level HealthKit resolution, treat periods as estimates rather than exact individual-footstep records.

### Calculations

| Metric | Definition |
| --- | --- |
| Total duration | End time minus start time, in minutes, including breaks. |
| Active time | Total duration minus break time. |
| Total steps | Sum of steps in the merged period. |
| Average cadence | Total steps divided by total elapsed minutes, including breaks. |

A merged period **passes** only when both conditions hold:

- Active time is **more than 30 minutes**.
- Average cadence is **greater than 60 steps per elapsed minute**, including breaks.

Exactly 30 active minutes or exactly 60 steps per elapsed minute fails. Apply thresholds before display rounding. Mark every merged period **Passed** or **Failed** and explain each failed condition.

### Data tab

At the top, show the grand total qualifying active minutes and a bar chart of qualifying active minutes by date.

Group all merged periods by local date. For each date, show its total qualifying active minutes. For every period, show:

- Start and end time.
- Total duration and active time, in minutes.
- Break time, in minutes.
- Total steps.
- Average steps per elapsed minute, including breaks.
- Pass/fail result and explanation.

Failed periods remain visible but contribute zero to qualifying totals and the chart.

## 6. AllTrails

### Retrieval

Read AllTrails workouts synced to Apple Health through HealthKit. Request Workouts read permission and identify AllTrails records using their source attribution.

The user must enable AllTrails-to-Apple-Health syncing. Newly enabled syncing may not include historical activities. Show available data without assuming that fields missing from HealthKit are zero.

### Calculations and qualification

For this app, use the workout duration saved in HealthKit as moving time. Explain that it may differ from AllTrails’ own moving-time calculation.

Calculate overall average speed for each activity:

`Average speed (km/h) = distance in kilometers ÷ workout duration in hours`

An activity **passes** when its average speed is **at least 2 km/h and at most 5 km/h**. Both boundaries are included. Apply thresholds before display rounding.

Mark an activity **Failed** and explain why when:

- Average speed is below 2 km/h.
- Average speed is above 5 km/h.
- Distance is missing or invalid, or duration is invalid or zero, so average speed cannot be calculated.

### Data tab

Show the grand total qualifying moving minutes at the top. Group activities by their local start date, showing only dates that contain activity records. For each date, show its total qualifying moving minutes.

For each activity, show:

- Start and end time.
- Moving time based on HealthKit workout duration.
- Recorded distance and calculated average speed, or an unavailable indicator.
- Elevation gain, when available.
- Pass/fail result and explanation.

Failed activities remain visible for inspection but contribute zero to qualifying totals. Do not apply the Health step-duration or cadence thresholds to AllTrails workouts.
