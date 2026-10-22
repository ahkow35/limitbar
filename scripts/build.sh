#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/swift.sh build -c release
APP="$PWD/dist/LimitBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LimitBar "$APP/Contents/MacOS/LimitBar"
cp Sources/LimitBar/Resources/openai.svg "$APP/Contents/Resources/openai.svg"
cp docs/openai-mark-LICENSE.txt "$APP/Contents/Resources/openai-mark-LICENSE.txt"
./scripts/swiftc-local.sh scripts/make-icon.swift -o .build/make-icon
.build/make-icon .build/LimitBar.iconset
iconutil -c icns .build/LimitBar.iconset -o "$APP/Contents/Resources/LimitBar.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LimitBar</string>
<key>CFBundleIdentifier</key><string>local.yukai.limitbar</string>
<key>CFBundleName</key><string>LimitBar</string>
<key>CFBundleDisplayName</key><string>LimitBar</string>
<key>CFBundleIconFile</key><string>LimitBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier local.yukai.limitbar "$APP"
echo "Built $APP"
