#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_DIR="$PROJECT_DIR/dist/TinkerDesk.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"
SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/ModuleCache" \
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache" \
swift build -c release

BIN_DIR=$(SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/ModuleCache" \
    CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache" \
    swift build -c release --show-bin-path)

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$CONTENTS_DIR/Helpers"
cp "$BIN_DIR/TinkerDesk" "$CONTENTS_DIR/MacOS/TinkerDesk"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Vendor/PHPantom/phpantom_lsp" "$CONTENTS_DIR/Helpers/phpantom_lsp"
cp "$PROJECT_DIR/Vendor/PHPantom/LICENSE" "$CONTENTS_DIR/Resources/PHPantom-LICENSE"
chmod 755 "$CONTENTS_DIR/MacOS/TinkerDesk"
chmod 755 "$CONTENTS_DIR/Helpers/phpantom_lsp"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
