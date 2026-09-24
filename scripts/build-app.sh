#!/bin/zsh
set -euo pipefail

TASK_ROOT=${0:A:h:h}
BUILD_ROOT="$TASK_ROOT/.build"
APP_PATH="$TASK_ROOT/dist/Seven Day Todo.app"

cd "$TASK_ROOT"

CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swiftpm-module-cache" \
swift build \
    --configuration release \
    --disable-sandbox \
    --cache-path "$BUILD_ROOT/cache" \
    --config-path "$BUILD_ROOT/config" \
    --security-path "$BUILD_ROOT/security"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BUILD_ROOT/out/Products/Release/SevenDayTodo" "$APP_PATH/Contents/MacOS/SevenDayTodo"
cp "$TASK_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$TASK_ROOT/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_PATH"

echo "$APP_PATH"
