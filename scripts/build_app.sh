#!/bin/bash
set -euo pipefail

APP_NAME=BurritoCursor
BUILD_DIR=.build/release
BUNDLE=$APP_NAME.app

swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE/Contents/MacOS/"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

echo
echo "Built $BUNDLE"
echo "Launch:  open ./$BUNDLE"
echo "Install: mv $BUNDLE /Applications/"
