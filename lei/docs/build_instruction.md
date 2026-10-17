== Install iPhone app in test mode ==

You can install it directly from Xcode onto your iPhone.
1. Connect your iPhone to your Mac with a USB cable. Unlock it and tap Trust if prompted.
2. Open native-ios/Xiangqi.xcodeproj in Xcode.
3. Go to Xcode → Settings → Apple Accounts and sign in with your Apple Account.
4. Click the blue Xiangqi project in the left sidebar, select the Xiangqi target, then open Signing & Capabilities:
   - Enable Automatically manage signing.
   - Select your Personal Team.
   - Change the Bundle Identifier to something unique, such as com.yourname.xiangqi.
5. On your iPhone, enable Settings → Privacy & Security → Developer Mode. Restart and confirm when prompted. Apple’s Developer Mode guide
6. In Xcode’s top toolbar, choose your iPhone as the run destination, then press ⌘R.
Xcode will build, install, and launch the game. Afterward, open Xiangqi from your iPhone’s Home Screen. A personal Apple Account supports testing on your own device. Apple’s installation guide


== Enable Developer Mode ==
Developer Mode appears only after you initiate pairing with Xcode. My earlier instructions missed that prerequisite. Apple’s guide
1. Connect your iPhone to your Mac with a USB cable and unlock it.
2. Tap Trust This Computer on your iPhone if prompted.
3. Open the Xiangqi project in Xcode.
4. Click the run destination at the top and select your physical iPhone. Follow any pairing prompts.
5. On your iPhone, reopen Settings → Privacy & Security, then scroll to the bottom for Developer Mode.
6. Turn it on, restart when prompted, and confirm Turn On after restarting.
If it’s still missing, does your iPhone appear in Xcode’s run destination list?


== Set Signining ==
This is a signing setup issue. In Xcode:
1. Click the blue Xiangqi project icon in the left sidebar.
2. Under TARGETS, select Xiangqi.
3. Open Signing & Capabilities.
4. Enable Automatically manage signing.
5. In Team, select your name or Personal Team.
If the Team list is empty, choose Add an Account… and sign in with your Apple Account, then select your team.
Press ⌘R again to install the game on your connected iPhone.


== Trust developer account ==
On your iPhone:
1. Tap Cancel.
2. Open Settings → General → VPN & Device Management.
3. Under Developer App, tap the Apple Development entry matching the account in your screenshot.
4. Tap Trust, then confirm. Follow any restart prompt.
5. Open Xiangqi again.
Keep your iPhone connected to the internet while verifying trust. Apple’s instructions