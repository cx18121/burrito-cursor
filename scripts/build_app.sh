#!/bin/bash
set -euo pipefail

APP_NAME=BurritoCursor
BUILD_DIR=.build/release
BUNDLE="$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED="$INSTALL_DIR/$BUNDLE"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

swift build -c release

# Build bundle in a staging dir, sign there, then atomic-move into place.
# Signing in staging means a failure after this point leaves the existing
# installed app untouched.
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
STAGED_BUNDLE="$STAGING/$BUNDLE"
mkdir -p "$STAGED_BUNDLE/Contents/MacOS"
mkdir -p "$STAGED_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$STAGED_BUNDLE/Contents/MacOS/"
cp Resources/Info.plist "$STAGED_BUNDLE/Contents/Info.plist"

# Sign the staged bundle. Without this step:
#   1. The binary keeps its `linker-signed` signature, which only covers the
#      Mach-O — Info.plist is `not bound`, so any change to the bundle
#      invalidates TCC and macOS won't trust accessibility grants.
#   2. The signing identifier defaults to the executable name (`BurritoCursor`)
#      instead of `CFBundleIdentifier` (`com.charliexue.burritocursor`), which
#      makes TCC grants keyed to the wrong identity.
#
# Prefer a stable Apple Development cert if one is in the keychain — that gives
# the bundle a stable TeamIdentifier so TCC accessibility grants persist across
# rebuilds (without it, every `swift build` produces a new cdhash and TCC sees
# each build as a new app). Falls back to ad-hoc if no cert is present.
#
# Pinned to the cert's SHA-1 (not the substring "Apple Development") so that
# a second Apple Development identity in keychain — e.g. from a different team
# — can't ambiguously match. Override with `SIGN_IDENTITY=<sha1> bash …`.
SIGN_IDENTITY="${SIGN_IDENTITY:-B34F936CCB151247A80B25244A2BF6E35AFC66DC}"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$STAGED_BUNDLE"
else
    echo "No matching cert ($SIGN_IDENTITY) in keychain, falling back to ad-hoc."
    echo "(TCC accessibility grants will reset on every rebuild.)"
    codesign --force --sign - "$STAGED_BUNDLE"
fi

# Install into ~/Applications — Raycast/Spotlight index this location.
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED"
mv "$STAGED_BUNDLE" "$INSTALLED"

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
