#!/bin/bash
# Builds iMessageSearch.app — a real .app bundle, so Full Disk Access (System
# Settings → Privacy & Security) can be granted once and stays granted across
# rebuilds, instead of re-prompting for a bare `swift run` binary each time.
#
# Signed with your Apple Development identity by default, so Full Disk Access
# and Contacts grants survive rebuilds (ad-hoc signatures change their hash on
# every build, which macOS treats as a new app — that's why permissions kept
# resetting before). Override with another identity, or "-" for ad-hoc, via:
#   SIGN_IDENTITY="..." ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="iMessageSearch"
BUNDLE_ID="com.havemindmedia.imessage-search"
SIGN_IDENTITY="${SIGN_IDENTITY:-EAFBAD4EF847BDBD7203ADB5A7F7CF983B922DC2}" # Apple Development: Jason Ray (M53BL7N5AV)

swift build -c release

APP_DIR="$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSContactsUsageDescription</key><string>Used to show contact names instead of raw phone numbers/emails next to your messages.</string>
</dict>
</plist>
PLIST

codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR"

echo "Built $APP_DIR"
echo "Now: open it once, then add it in System Settings > Privacy & Security > Full Disk Access."
