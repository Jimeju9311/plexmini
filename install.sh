#!/usr/bin/env bash
# Deploys PlexMini.app to a jailbroken device over SSH.
#
#   ./install.sh ipaddress
#
# Requires: sshpass (or edit this to use key auth), and the device must have
# OpenSSH installed from Cydia/Sileo.
set -euo pipefail

APP_NAME=PlexMini
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT/${APP_NAME}.app"
DEVICE="${1:-}"
DEVICE_PASS="${DEVICE_PASS:-alpine}"

if [ -z "$DEVICE" ]; then
  echo "usage: ./install.sh <device-ip>   (password via DEVICE_PASS env, defaults to 'alpine')" >&2
  exit 1
fi
if [ ! -d "$APP_DIR" ]; then
  echo "error: $APP_DIR not found - run ./build.sh first" >&2
  exit 1
fi

# Old OpenSSH builds on iOS 9/10 only offer key exchange/host key algorithms that
# modern OpenSSH clients disable by default, so they have to be re-enabled here.
SSH_OPTS=(
  -o HostKeyAlgorithms=+ssh-rsa,ssh-dss
  -o PubkeyAcceptedAlgorithms=+ssh-rsa
  -o PubkeyAuthentication=no
  -o StrictHostKeyChecking=accept-new
)

run_ssh() { sshpass -p "$DEVICE_PASS" ssh "${SSH_OPTS[@]}" "root@$DEVICE" "$@"; }

# scp -r into an EXISTING directory nests the copy inside it
# (PlexMini.app/PlexMini.app/...) instead of replacing it, leaving the old binary
# in place and running. Always remove the destination first.
echo "==> removing any previous install"
run_ssh "rm -rf /Applications/${APP_NAME}.app"

echo "==> copying app bundle"
sshpass -p "$DEVICE_PASS" scp "${SSH_OPTS[@]}" -r "$APP_DIR" "root@$DEVICE:/Applications/${APP_NAME}.app"

echo "==> verifying the installed binary matches the local build"
LOCAL_SUM=$(md5sum "$APP_DIR/$APP_NAME" | cut -d' ' -f1)
REMOTE_SUM=$(run_ssh "md5sum /Applications/${APP_NAME}.app/${APP_NAME}" | cut -d' ' -f1)
if [ "$LOCAL_SUM" != "$REMOTE_SUM" ]; then
  echo "error: checksum mismatch (local $LOCAL_SUM != remote $REMOTE_SUM)" >&2
  exit 1
fi

echo "==> signing and registering"
run_ssh "chown -R root:admin /Applications/${APP_NAME}.app \
  && chmod 755 /Applications/${APP_NAME}.app/${APP_NAME} \
  && ldid -S /Applications/${APP_NAME}.app/${APP_NAME}"

# uicache/sbreload are only needed the first time, so the icon appears. They can
# hang on a device that has had a lot of install churn; if that happens, skip them
# (the icon already exists) and just kill the running process instead.
if ! run_ssh "ls /var/mobile/Library/Caches/com.apple.mobile.installation.plist" >/dev/null 2>&1; then
  true
fi
echo "==> refreshing icon cache (safe to Ctrl-C if it hangs; only needed on first install)"
run_ssh "uicache -p /Applications/${APP_NAME}.app" || echo "   (uicache failed/skipped)"

echo "==> killing any running instance so the next launch picks up the new binary"
run_ssh "ps ax | grep '${APP_NAME}.app/${APP_NAME}' | grep -v grep | while read pid rest; do kill -9 \$pid; done" || true

echo "done - launch ${APP_NAME} on the device"
