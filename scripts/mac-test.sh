#!/bin/bash
# Health&I Mac build bridge. Syncs this tree to the Mac build account and runs ONE
# command there, under a lock so parallel agents never interleave builds.
#
# Usage:
#   scripts/mac-test.sh                      # swift build (core package)
#   scripts/mac-test.sh test                 # swift test
#   scripts/mac-test.sh xcode [scheme]       # xcodegen + xcodebuild for iOS simulator (default scheme HealthAndI)
#   scripts/mac-test.sh sh '<shell>'         # arbitrary shell in the synced tree
#
# Host: MAC_HOST (default host.docker.internal = MBA09M) with key /workspace/.vibe/id_ed25519_mac.
# Martin prefers the faster laptop for builds: set MAC_HOST to its hostname once its key is installed.
#
# BRIDGE DISCIPLINE: every result you rely on comes from this script's single atomic
# sync+run ssh call. Inside a subagent run it FOREGROUND with timeout 600000, never
# run_in_background.
set -e
MAC_HOST="${MAC_HOST:-host.docker.internal}"
KEY="${MAC_KEY:-/workspace/.vibe/id_ed25519_mac}"
SSH_CMD="ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new claude@$MAC_HOST"
DEST='~/builds/healthandeye/src'
MODE="${1:-build}"; shift || true
case "$MODE" in
  build) REMOTE='swift build 2>&1 | tail -40' ;;
  test)  REMOTE='swift test 2>&1 | tail -80' ;;
  xcode) SCHEME="${1:-HealthAndI}"; REMOTE='export PATH=$HOME/bin:$PATH; xcodegen generate --quiet 2>&1 | tail -20 && xcodebuild -project HealthAndI.xcodeproj -scheme '"$SCHEME"' -destination "generic/platform=iOS Simulator" -derivedDataPath ../DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: unre|BUILD|\*\* " | head -80' ;;
  sh)    REMOTE="$*" ;;
  *)     echo "unknown mode $MODE" >&2; exit 2 ;;
esac
LOCK='
acquire() {
  for i in $(seq 1 180); do
    if mkdir ~/.healthandeye-build.lock 2>/dev/null; then return 0; fi
    if [ -n "$(find ~/.healthandeye-build.lock -maxdepth 0 -mmin +15 2>/dev/null)" ]; then rmdir ~/.healthandeye-build.lock 2>/dev/null || true; continue; fi
    sleep 5
  done
  echo "mac-test: build lock still held after 15 min" >&2; exit 75
}
acquire
trap "rmdir ~/.healthandeye-build.lock 2>/dev/null" EXIT
'
tar -C /workspace --exclude .git --exclude .build --exclude Martin --exclude .vibe --exclude '*.xcodeproj' --exclude DerivedData -cf - . | $SSH_CMD "$LOCK"'
mkdir -p '"$DEST"' && cd '"$DEST"' && find . -mindepth 1 -maxdepth 1 ! -name .build ! -name "*.xcodeproj" -exec rm -rf {} + && tar -xf - && '"$REMOTE"
