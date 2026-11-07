#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Star Defender.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc main.swift -o "$APP/Contents/MacOS/StarDefender" -framework Cocoa -module-cache-path "${TMPDIR:-/tmp}/star-defender-module-cache"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StarDefender</string>
<key>CFBundleIdentifier</key><string>local.arcade.stardefender</string>
<key>CFBundleName</key><string>Star Defender</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s/%s\n' "$PWD" "$APP"
