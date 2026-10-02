# Dragon Chess · 象棋

Native iOS 17+ Chinese chess using SwiftUI and SceneKit. Open `DragonChess.xcodeproj` in Xcode, choose the DragonChess scheme, and run on an iPhone or iPad simulator. To run on a physical device, select your signing team and a unique bundle identifier under Signing & Capabilities.

- Raised 3D pieces with Chinese characters, a wooden board, river and palace markings. Each army’s characters face its opponent.
- Red-and-gold “帥” Home Screen icon and the app name “Dragon Chess”.
- Local two-player mode, or play Red against the computer.
- Easy uses random legal moves; Medium searches two plies; Hard searches three plies with alpha-beta pruning.
- Tap a piece and then a teal destination. A gold ring shows selection.
- Moves animate over 0.8 seconds; input waits until animation and computer response finish.
- Undo reverses one turn in local play or a complete human/computer round. New Game resets immediately.
- Rules cover cannon screens, horse legs, elephant eyes and river restrictions, palaces, flying generals, self-check and no-legal-move losses (including stalemate).

The title and controls use large native fonts. The 3D board uses touch interaction; individual board squares are not yet exposed to VoiceOver. Repetition adjudication, clocks, saved games and online play are outside this PRD.

## Validation

Build without signing:

```sh
xcodebuild -project DragonChess.xcodeproj -scheme DragonChess -sdk iphonesimulator -derivedDataPath /tmp/DragonChessBuild CODE_SIGNING_ALLOWED=NO build
```

Run the portable rule checks from this directory:

```sh
swiftc -module-cache-path /tmp/DragonChessModuleCache Sources/Chess.swift Tests/main.swift -o /tmp/DragonChessRulesTests
/tmp/DragonChessRulesTests
```
