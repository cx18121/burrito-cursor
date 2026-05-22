#!/bin/bash
set -euo pipefail

APP_NAME=BurritoCursor
BUILD_DIR=.build/release
BUNDLE="$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED="$INSTALL_DIR/$BUNDLE"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

swift build -c release

# Build bundle in a staging dir, then atomic-move into place.
STAGING=$(mktemp -d)
mkdir -p "$STAGING/$BUNDLE/Contents/MacOS"
mkdir -p "$STAGING/$BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$STAGING/$BUNDLE/Contents/MacOS/"
cp Resources/Info.plist "$STAGING/$BUNDLE/Contents/Info.plist"

# Install into ~/Applications — Raycast/Spotlight index this location.
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED"
mv "$STAGING/$BUNDLE" "$INSTALLED"
rm -rf "$STAGING"

# Re-register with LaunchServices so Raycast/Spotlight see it immediately
# (otherwise it can take minutes for the index to refresh on its own).
"$LSREGISTER" -f "$INSTALLED" 2>/dev/null || true

# Convenience symlink at repo root so `open ./BurritoCursor.app` still works.
rm -rf "./$BUNDLE"
ln -s "$INSTALLED" "./$BUNDLE"

echo
echo "Installed: $INSTALLED"
echo "Symlinked: ./$BUNDLE → $INSTALLED"
echo "Launch:    open '$INSTALLED'"
echo "           (or via Raycast / Spotlight — search 'Burrito Cursor')"
