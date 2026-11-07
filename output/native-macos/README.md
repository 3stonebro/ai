# Star Defender for macOS

Double-click **Star Defender.app** to play.

- Press Return or click the game window to start or restart.
- Use the left and right arrow keys to move the tank.
- Hold Space to fire bullets.
- Destroy 10 stars to win. Let 3 fall past the bottom and you lose.
- The game pauses while its window is inactive.
- Press Command-Q to quit.

This is a native Swift/AppKit application with no web view or external assets.

To rebuild with the macOS Command Line Tools installed:

```sh
bash native-macos/build.sh
```

The build produces a locally signed app for your Mac's architecture.
