#!/bin/zsh
# Builds the release binary and wraps it in an ad hoc signed .app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="build/Tidy Fixer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns Resources/menubarTemplate*.png "$APP/Contents/Resources/"
cp .build/release/TidyFixer "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
