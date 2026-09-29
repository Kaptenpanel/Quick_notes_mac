#!/bin/bash
# Builds QuickNotes.app, signs it for this Mac, and installs it to /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="QuickNotes"
BUNDLE="build/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"
cp -R Resources/Fonts "${BUNDLE}/Contents/Resources/Fonts"

echo "==> Signing (ad-hoc, for this Mac only)"
codesign --force --sign - "${BUNDLE}"

if [[ "${1:-}" == "--no-install" ]]; then
    echo "==> Built ${BUNDLE} (not installed)"
    exit 0
fi

echo "==> Quitting running copy, if any"
osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
sleep 1

echo "==> Installing to ${INSTALL_PATH}"
rm -rf "${INSTALL_PATH}"
cp -R "${BUNDLE}" "${INSTALL_PATH}"

echo "==> Opening"
open "${INSTALL_PATH}"
