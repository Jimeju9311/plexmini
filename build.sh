#!/usr/bin/env bash
set -euo pipefail

APP_NAME=PlexMini
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT/${APP_NAME}.app"
SRC="$ROOT/src"
BUILD="$ROOT/.build"

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

TARGET_FLAGS=(-target armv7s-apple-ios9.0 -isysroot "$SDK" -fuse-ld="$TC/ld" -w)

# The server address can be supplied without editing (and accidentally committing)
# PlexConfig.h: either export PLEX_SERVER_URL, or drop the URL in a "server.local"
# file, which is gitignored.
if [ -z "${PLEX_SERVER_URL:-}" ] && [ -f "$ROOT/server.local" ]; then
  PLEX_SERVER_URL="$(tr -d '[:space:]' < "$ROOT/server.local")"
fi
if [ -n "${PLEX_SERVER_URL:-}" ]; then
  echo "==> server: $PLEX_SERVER_URL"
  TARGET_FLAGS+=("-DPLEX_SERVER=@\"$PLEX_SERVER_URL\"")
fi
FRAMEWORKS=(
  -framework UIKit -framework Foundation -framework CoreGraphics
  -framework QuartzCore -framework AVFoundation -framework AVKit -framework CoreMedia
)

rm -rf "$BUILD"
mkdir -p "$BUILD" "$APP_DIR"
cp "$ROOT/Info.plist" "$APP_DIR/Info.plist"

# rt_shims.c supplies runtime symbols (_Unwind_SjLj_*) the armv7s toolchain omits.
echo "==> compiling rt_shims.c"
"$TC/clang" "${TARGET_FLAGS[@]}" -c "$SRC/rt_shims.c" -o "$BUILD/rt_shims.o"

OBJECTS=("$BUILD/rt_shims.o")
for src_file in "$SRC"/*.m; do
  obj="$BUILD/$(basename "${src_file%.m}").o"
  echo "==> compiling $(basename "$src_file")"
  "$TC/clang" "${TARGET_FLAGS[@]}" -fobjc-arc -I"$SRC" -c "$src_file" -o "$obj"
  OBJECTS+=("$obj")
done

echo "==> linking"
"$TC/clang" "${TARGET_FLAGS[@]}" -fobjc-arc -lobjc "${FRAMEWORKS[@]}" \
  -o "$APP_DIR/$APP_NAME" "${OBJECTS[@]}"

"$TC/ldid" -S "$APP_DIR/$APP_NAME"
tar -C "$ROOT" -czf "$ROOT/${APP_NAME}.app.tar.gz" "${APP_NAME}.app"
echo "Built $APP_DIR"
