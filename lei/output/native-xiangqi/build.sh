#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Xiangqi.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O Engine.swift main.swift -o "$APP/Contents/MacOS/Xiangqi" -framework Cocoa -module-cache-path "${TMPDIR:-/tmp}/xiangqi-module-cache"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Xiangqi</string>
<key>CFBundleIdentifier</key><string>local.arcade.xiangqi</string>
<key>CFBundleName</key><string>Xiangqi</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s/%s\n' "$PWD" "$APP"
