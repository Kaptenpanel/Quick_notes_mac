#!/bin/bash
# Builds QuickNotes.app, signs it for this Mac, and installs it to /Applications.
#
#   --no-install   build build/QuickNotes.app but don't install or open it
#
# Build speed: most of a slow build is the compiler re-caching Apple's frameworks
# (the module cache). It lives outside .build so it survives `rm -rf .build` and
# `swift package clean`. Don't copy or move it; to reset it, delete the folder.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="QuickNotes"
BUNDLE="build/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
MODULE_CACHE="${QUICKNOTES_MODULE_CACHE:-$HOME/Library/Caches/QuickNotes/ModuleCache}"

INSTALL=1
for arg in "$@"; do
    case "$arg" in
        --no-install) INSTALL=0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

mkdir -p "${MODULE_CACHE}"

echo "==> Building release binary"
# No debug info: faster builds, no unused dSYM, smaller binary.
swift build -c release -debug-info-format none \
    -Xswiftc -module-cache-path -Xswiftc "${MODULE_CACHE}"

# SwiftPM keeps .build/release pointing at the current platform's output.
BIN=".build/release/${APP_NAME}"

echo "==> Assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BIN}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
# Drop local symbols; must happen before signing.
strip -S -x "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"
cp -R Resources/Fonts "${BUNDLE}/Contents/Resources/Fonts"

# macOS keys the Screen Recording grant to the signature. An ad-hoc signature changes on
# every build, so the grant stops matching; a real certificate keeps it across rebuilds.
SIGN_IDENTITY="${QUICKNOTES_SIGN_IDENTITY:-QuickNotes Dev}"
if security find-certificate -c "${SIGN_IDENTITY}" >/dev/null 2>&1; then
    echo "==> Signing with \"${SIGN_IDENTITY}\""
    codesign --force --sign "${SIGN_IDENTITY}" "${BUNDLE}"
else
    echo "==> Signing (ad-hoc; Screen Recording must be re-granted after each build)"
    codesign --force --sign - "${BUNDLE}"
fi

if [[ "${INSTALL}" == 0 ]]; then
    echo "==> Built ${BUNDLE} (not installed)"
    exit 0
fi

echo "==> Quitting running copy, if any"
osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
# Wait up to 2s for it to exit.
for _ in {1..20}; do
    pgrep -x "${APP_NAME}" >/dev/null || break
    sleep 0.1
done

echo "==> Installing to ${INSTALL_PATH}"
rm -rf "${INSTALL_PATH}"
cp -R "${BUNDLE}" "${INSTALL_PATH}"

echo "==> Opening"
open "${INSTALL_PATH}"
