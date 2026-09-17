#!/usr/bin/env bash
set -euo pipefail

APP_NAME=PlexMini
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT/${APP_NAME}.app"

# Override these if your Theos install lives somewhere else:
#   THEOS=/opt/theos ./build.sh
THEOS="${THEOS:-$HOME/theos}"
TC="${THEOS_TOOLCHAIN:-$THEOS/toolchain/linux/iphone/bin}"
SDK="${THEOS_SDK:-$THEOS/sdks/iPhoneOS10.3.sdk}"

if [ ! -x "$TC/clang" ]; then
  echo "error: toolchain not found at $TC (set THEOS or THEOS_TOOLCHAIN)" >&2
  exit 1
fi
if [ ! -d "$SDK" ]; then
  echo "error: SDK not found at $SDK (set THEOS_SDK)" >&2
  exit 1
fi

mkdir -p "$APP_DIR"
cp "$ROOT/Info.plist" "$APP_DIR/Info.plist"

"$TC/clang" -target armv7s-apple-ios9.0 -isysroot "$SDK" -fobjc-arc -fuse-ld="$TC/ld" -w -c "$ROOT/rt_shims.c" -o "$ROOT/rt_shims.o"

"$TC/clang" -target armv7s-apple-ios9.0 -isysroot "$SDK" -fobjc-arc -fuse-ld="$TC/ld" -w -lobjc \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
  -framework AVFoundation -framework AVKit -framework CoreMedia \
  -o "$APP_DIR/$APP_NAME" "$ROOT/main.m" "$ROOT/rt_shims.o"

"$TC/ldid" -S "$APP_DIR/$APP_NAME"
tar -C "$ROOT" -czf "$ROOT/${APP_NAME}.app.tar.gz" "${APP_NAME}.app"
echo "Built $APP_DIR"
