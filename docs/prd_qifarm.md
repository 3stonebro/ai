元气农场 — iOS App Requirements

## General

- Create a native iOS app and web-based app and save the project to `./lei/output`.
- Name the app **元气农场**.
- For the iOS app, add an iOS app icon.
- For the web-based app, add a logo  

## Interface

The main screen should include:
- A button labeled **“iPhone Health App”**.
- A display next to the button showing the total qualifying activity time in minutes.
- A Unfiltered page showing the grouped groups
- A Filtered page showing filtered groups 

When the button is tapped, request permission to read step data from Apple Health, retrieve all available step data, and display the results according to the rules below.

## Processing and Display Rules

1. Group consecutive periods when the break between them is **less than 5 minutes**.
3. Show the resluting groups in the Unfiltered page with 
- total active minutes
- total steps
- average steps per minutes (excluding break minutes)
- total break minutes
- start and end time 

4. Keep merged periods that meet both conditions:
   - Elapsed time excluding breaks from start to end is **more than 30 minutes**.
   - Average cadence excluding breaks is **greater than 60 steps per minute**, calculated using active time only, excluding breaks.
5. On the filtered page, for each qualifying period, display:
   - Total steps.
   - Active time in minutes, excluding breaks.
   - Start time.
   - End time.
6. Group qualifying periods by date and display:
   - Total qualifying active time for each date.
   - Total qualifying active time across all dates.
7. Also show a bar chart of total walking minutes by date
8. Notes:
   - Continuous activity means the break between steps is **less than 1 minute**.
   - Periods spanning midnight should be treated as separate groups.
   - Use current date as the end date. 
