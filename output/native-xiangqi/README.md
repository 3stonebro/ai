# Xiangqi — native macOS Chinese chess

Open **Xiangqi.app** in Finder. This is a Swift/AppKit app, with no browser, network dependency, or external assets.

## Play

- **vs Computer**: play Red against a basic two-ply computer opponent.
- **Two players**: two people alternate on the same Mac.
- Click your piece, then a green destination. Red goes first.
- Every move slides smoothly for about one second, with its origin and destination highlighted. The computer pauses before replying.
- An orange ring identifies a general in check.
- **Undo** takes back your turn and the computer's reply in computer mode, or one move in two-player mode.
- **New game** restarts. Switching modes also starts a new game.
- Escape clears selection; Command-Q quits.

The game enforces palace and river boundaries, blocked horse legs and elephant eyes, cannon screens, pawn river crossing, facing generals, and king safety. Checkmate or having no legal moves loses the game.

Repeated positions are treated as a draw on their third occurrence. This is a casual-play simplification; tournament perpetual-check and perpetual-chase adjudication is not implemented.

## Build

Requires Apple's macOS Command Line Tools:

```sh
bash native-xiangqi/build.sh
```

The output is a locally signed app for your Mac's architecture.

## Engine tests

```sh
xcrun swiftc native-xiangqi/Engine.swift native-xiangqi/EngineTests.swift -o /tmp/xiangqi-tests -module-cache-path /tmp/xiangqi-test-cache
/tmp/xiangqi-tests
```
