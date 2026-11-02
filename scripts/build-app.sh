#!/bin/zsh
set -euo pipefail

TASK_ROOT=${0:A:h:h}
BUILD_ROOT="$TASK_ROOT/.build/app-release"
APP_PATH="$TASK_ROOT/dist/Seven Day Todo.app"
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
ARCHITECTURE=$(uname -m)
source_files=("$TASK_ROOT"/Sources/SevenDayTodo/**/*.swift)
mkdir -p "$BUILD_ROOT/module-cache"
cd "$BUILD_ROOT"

# This dependency-free AppKit app needs only the standard Swift compiler. Keep
# every build/cache output local; no manifest execution or nested sandbox is needed.
xcrun swiftc -parse-as-library -swift-version 6 -O -whole-module-optimization -g \
    -target "$ARCHITECTURE-apple-macosx14.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_ROOT/module-cache" \
    -module-name SevenDayTodo \
    "${source_files[@]}" \
    -o "$BUILD_ROOT/SevenDayTodo"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_ROOT/SevenDayTodo" "$APP_PATH/Contents/MacOS/SevenDayTodo"
cp "$TASK_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$TASK_ROOT/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --sign - --options runtime --timestamp=none "$APP_PATH"
codesign --verify --strict "$APP_PATH"
# Signal bundle changes to Finder/Dock after rebuilding in place.
touch "$APP_PATH"

echo "$APP_PATH"
