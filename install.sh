#!/bin/sh
# Beckon one-liner installer (from a clone): builds the app, puts it in /Applications, launches it.
# The app then offers to add its hooks to ~/.claude/settings.json with one click.
set -e
cd "$(dirname "$0")/app"
if ! xcode-select -p >/dev/null 2>&1; then echo "Xcode Command Line Tools are required: xcode-select --install"; exit 1; fi
./build.sh
pkill -x Beckon 2>/dev/null || true
rm -rf /Applications/Beckon.app
cp -R build/Beckon.app /Applications/Beckon.app
open /Applications/Beckon.app
echo "Beckon is running in your menu bar. Click “Install hooks” in the window that opened."
