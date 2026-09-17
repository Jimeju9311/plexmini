#!/usr/bin/env bash
# Builds a .deb that installs PlexMini.app into /Applications, which is what a
# jailbroken device expects (an .ipa is for sideloading onto *non*-jailbroken
# devices and would need an Apple signing certificate).
#
# The result can be installed with Sileo/Cydia, Filza, or `dpkg -i` over SSH.
set -euo pipefail

APP_NAME=PlexMini
PACKAGE_ID=com.juan.plexmini
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT/${APP_NAME}.app"
STAGE="$ROOT/.package"

if [ ! -d "$APP_DIR" ]; then
  echo "error: $APP_DIR not found - run ./build.sh first" >&2
  exit 1
fi
if ! command -v dpkg-deb >/dev/null; then
  echo "error: dpkg-deb not found (install the 'dpkg' package)" >&2
  exit 1
fi

VERSION=$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$ROOT/Info.plist")
VERSION="${VERSION:-1.0}"
DEB="$ROOT/${PACKAGE_ID}_${VERSION}_iphoneos-arm.deb"

rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$STAGE/Applications"
cp -R "$APP_DIR" "$STAGE/Applications/"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PACKAGE_ID
Name: $APP_NAME
Version: $VERSION
Architecture: iphoneos-arm
Description: Native Plex client for 32-bit iOS 9-10 devices the official app dropped
Homepage: https://github.com/Jimeju9311/plexmini
Maintainer: Juan Carlos Jimenez
Author: Juan Carlos Jimenez
Section: Multimedia
Depends: firmware (>= 9.0)
EOF

# Registers the icon with SpringBoard so it shows up without a manual respring.
#
# uicache is detached rather than run inline because it can wedge indefinitely on
# iOS 10 (it talks to lsd/installd, which sometimes never answers). Backgrounding
# alone is not enough: dpkg reads the maintainer script's output through a pipe and
# waits for EOF, so a child still holding stdout/stderr keeps dpkg blocked forever.
# Redirecting all three descriptors to /dev/null lets dpkg finish immediately, and a
# hung uicache then costs the user a respring instead of a half-configured package.
cat > "$STAGE/DEBIAN/postinst" <<EOF
#!/bin/sh
(uicache -p /Applications/${APP_NAME}.app >/dev/null 2>&1 </dev/null &) &
exit 0
EOF

cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/sh
(uicache >/dev/null 2>&1 </dev/null &) &
exit 0
EOF

chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

# gzip rather than the modern xz default: the dpkg shipped with iOS 9/10
# jailbreaks is old and does not reliably read xz-compressed packages.
fakeroot dpkg-deb -Zgzip --build "$STAGE" "$DEB" >/dev/null

rm -rf "$STAGE"
echo "Built $DEB"
dpkg-deb --info "$DEB" | sed -n '2,12p'
