#!/bin/zsh
# Build "Deadlock Launcher.app" (launcher/Launcher.swift) and bin/dl-helper. Needs Xcode or its Command Line Tools;
# releases ship both prebuilt, so players never run this.
#   launcher/make-app.sh [out dir, default: build/]      the app looks for bin/deadlock in this checkout
#   DL_APP_DIR=<dir> launcher/make-app.sh ...             ...or in <dir> (the installer's location)
set -euo pipefail
here=${0:A:h} repo=${0:A:h:h}
out=${1:-$repo/build}
APP="$out/Deadlock Launcher.app"
version=$(git -C "$repo" describe --tags --always 2>/dev/null || print dev)
target=arm64-apple-macos15
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -target $target -o "$APP/Contents/MacOS/DeadlockLauncher" "$here/Launcher.swift"
swiftc -O -target $target -o "$repo/bin/dl-helper" "$repo/helper/dl-helper.swift"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DeadlockLauncher</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.deadlock-mac.launcher</string>
    <key>CFBundleName</key>
    <string>Deadlock Launcher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${version#v}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>DLApp</key>
    <string>${DL_APP_DIR:-$repo}</string>
</dict>
</plist>
EOF
codesign -f -s - "$APP" >/dev/null 2>&1 || true
print "✓ built $APP and bin/dl-helper"
