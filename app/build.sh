#!/bin/sh
# Builds Beckon.app into app/build/ using swiftc + clang directly (no Xcode project needed).
# Usage: ./build.sh [--run]
set -e
cd "$(dirname "$0")"
mkdir -p build/obj
echo "compiling beckon-hook (C, universal)…"
clang -O2 -Wall -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -o build/obj/beckon-hook Sources/beckon-hook/main.c
# The macOS 26/27 SDKs implement SwiftUI's @State as a macro whose plugin only ships with full Xcode;
# with Command Line Tools we build against the newest SDK that predates that (15.x), which is fine for a 14.0 target.
SDK=""
for c in /Library/Developer/CommandLineTools/SDKs/MacOSX15*.sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk; do
  [ -d "$c" ] && SDK="$c"
done
[ -z "$SDK" ] && SDK="$(xcrun --show-sdk-path)"
ARCHS="${BECKON_ARCHS:-arm64 x86_64}"
SLICES=""
for ARCH in $ARCHS; do
  echo "compiling Beckon (Swift, $ARCH) against $(basename "$SDK")…"
  swiftc -O -target "$ARCH-apple-macosx14.0" -swift-version 5 -sdk "$SDK" \
    -module-name Beckon \
    -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement \
    -o "build/obj/Beckon-$ARCH" Sources/Beckon/*.swift
  SLICES="$SLICES build/obj/Beckon-$ARCH"
done
lipo -create $SLICES -output build/obj/Beckon
APP=build/Beckon.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/obj/Beckon "$APP/Contents/MacOS/Beckon"
cp build/obj/beckon-hook "$APP/Contents/MacOS/beckon-hook"
cp Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -f Resources/brand/menubar-18.png ] && cp Resources/brand/menubar-18.png "$APP/Contents/Resources/menubar.png"
[ -f Resources/brand/menubar-36.png ] && cp Resources/brand/menubar-36.png "$APP/Contents/Resources/menubar@2x.png"
mkdir -p "$APP/Contents/Resources/Fonts"; cp Resources/Fonts/*.ttf Resources/Fonts/OFL-*.txt "$APP/Contents/Resources/Fonts/" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
if [ "$1" = "--run" ]; then pkill -x Beckon 2>/dev/null || true; sleep 0.3; open "$APP"; fi
