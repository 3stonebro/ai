元气农场 — iOS App Requirements

## General
- Create a native iOS app and save the project to `./lei/output`.
- Name the apps **元气农场**.
- For the iOS app, add an iOS app icon.

## Interface
1. Main page (page 1) should include
- A button to register new user or to login to an existing user
- Once logged in, the above button disappears, instead it shows the user name, and total total qualifying activity time for all data sources
- A button to add data sources from a list of available sources, including  **“iPhone Health”** and **"AllTrails"** for now.
- A button to delete exiting data sources
- A button to retrieve / refresh raw data from all existing data sources 
- A dropdown button for each of the existing data sources. show the button alongside with the Qaulifyig Acitivity label. 
- Once one data source is selected from the dropdown button, the main screen changes to a different view, there are two tabs in the view showing below it.
- A data tab showing the data extracted from the selected data source according to the rules described below.
- In the view, there is also a go back button, once clicked bring the user back to the main view. 
2. Make all buttons of the same size
3. Once the user is logged in, keep him logged in until she choose to log out. 
4. Make the UI professional look, not too simple and naive. 
5. Make the upper and lower portion of the interface more visible as two seperate section. 

## Workflow
1. When a new user registered, it main page return to the initial register/login page, instead of staying on the same page.
2. When an existing user register again, produce an popup error message say the user is already registered. The the user close the message, it return to the intial register/login page. 
3. When the user click on the verify link in the verification email, it should bring the user back to the app and the initial register/login page is shown.
4. When a data source is deleted, it and its data no longer appear in the app. The calculated total number is also updated. 
5. When user open the app again, it automatically reference all the data from all the data sources. 

## Database
1. Store user data and data from data sources in Supabase
2. For user data, store email, login password, nicename, total qualifying activity time
3. For data sources, store the data source id, data source name, the the relevant information described below. 
4. Supabase credentials
- Supabase Publishable Key: sb_publishable_c0lUaPKmEGVenjLk7GC-Ig_fqvIO5QE
- Project URL: https://axhsgohjnymxunvfavxe.supabase.co
5. Make sure data is only stored once in the database, even it is retrieved multiple time from the data source. i.e., the data should be keyed on the data source, date, activity, etc.  

## Data Sources - Apple Health
1. When the first button is tapped, request permission to read step data from Apple Health, retrieve all available step data, and display the results according to the rules below.
2. Group consecutive periods when the break between them is **less than 5 minutes**.
3. Check each merged periods to see if it meet both conditions, and mark each merged period if it passed or failed the test and why:
   - Elapsed time excluding breaks from start to end is **more than 30 minutes**.
   - Average cadence excluding breaks is **greater than 60 steps per minute**, calculated using active time only, excluding breaks.
4. Group qualifying periods by date and display in data tab with 
   - Start and end time.
   - Total duration in minutes and total active time in minutes excluding breaks.
   - Total break in minutes and total steps
   - Average steps per minutes (excluding break minutes)
   - start and end time    
5. Also show at per date level
   - Total qualifying active time for each date.
6. Also show at grand total level on the top
   - Total qualifying active time across all dates.
7. Also show a bar chart of total walking minutes by date on the top
8. Notes:
   - Continuous activity means the break between steps is **less than 1 minute**.
   - Periods spanning midnight should be treated as separate groups.
   - Use current date as the end date. 

## Data Sources - AllTrails
1. When the second button is tapped, read data from allTrails app on iphone via Apple HealthKit 
2. Process the data according the the following rules
   - Calculate the Average Speed for each activity, and add it the the data, show the resulting activity data in raw data tab
   - Checked if an activity's average speed is less than 2 km / hour or is more than 5 km / hour, then ignore the activity completely. 
   - Mark each activity if it passed or failed the test and why
   - Then show data in data tab, also show the total moving time by date, only for the data there is at lease one activity. And also show the grand total moving time in minutes for all activity. 
   
