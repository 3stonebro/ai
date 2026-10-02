# Xiangqi for iPhone and iPad

Native Swift/UIKit + SceneKit Chinese chess for iOS 15 or later. Includes a lit 3D wooden board and solid pieces, and three computer levels (you play Red), two players sharing one device, legal move highlights, undo, restart, and smooth 0.95-second moves with a pause before computer replies. Portrait layout scales to the available screen.

## Run in Xcode

1. Install full Xcode and an iOS Simulator runtime through Xcode's settings.
2. Open `native-ios/Xiangqi.xcodeproj`.
3. Choose the Xiangqi scheme and an iPhone or iPad simulator.
4. Press Command-R.

For a physical device, select your development team under Signing & Capabilities, change the bundle identifier to a unique value, select your connected device, and run. Device signing is managed by Xcode.

## Play

Choose vs Computer or Two players. Easy chooses random legal moves, Medium searches two plies, and Hard uses a bounded three-ply alpha-beta search. Changing the level starts a new game. Tap a piece and then a green destination. Red starts. Moves take about one second; board input is blocked during animations and computer thinking. Undo and New game remain available. Switching modes starts a new game.

Core rules include cannon screens, blocked horse legs and elephant eyes, palace/river restrictions, facing generals, check, and loss when there are no legal moves. Threefold repetition is a casual draw rule; tournament perpetual-check/chase adjudication is not implemented. Games are held in memory and reset when the app is relaunched.

## Validation

The project successfully built for both arm64 and x86_64 iOS Simulator architectures with Xcode on September 30, 2026. Engine tests, source syntax, and project/plist validation also passed. The 3D interface was launched and visually checked on the iPhone Air simulator. Physical-device testing of this revision has not been completed. No App Store packaging or distribution signing is included.

To reproduce the simulator build:

```sh
xcodebuild -project native-ios/Xiangqi.xcodeproj -scheme Xiangqi -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/xiangqi-ios-build CODE_SIGNING_ALLOWED=NO build
```

The engine is based on `native-xiangqi/Engine.swift`, with iOS-specific difficulty levels; this project is self-contained.

## Home Screen icon

The app uses a custom red-and-ivory 帥 chess-piece icon, supplied in the iPhone, iPad, and marketing sizes in `Xiangqi/Assets.xcassets/AppIcon.appiconset`. Rebuild and run from Xcode to update the installed app and its icon. The reproducible icon renderer is `tools/GenerateIcon.swift`.
