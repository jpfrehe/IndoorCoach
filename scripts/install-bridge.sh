#!/bin/bash
# Builds "IndoorCoach Brücke" (Release), signs it with your Apple Development certificate and installs it to
# /Applications. No Xcode account or provisioning profile needed. Usage: scripts/install-bridge.sh [Team-ID]
#
# Without a certificate the app is signed ad hoc: it runs, but the login keychain may ask for access after every
# reinstall. The sandbox, the MyWhoosh folder permission and the local-network permission work either way.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM="${1:-${DEVELOPMENT_TEAM:-}}"
DERIVED="${TMPDIR:-/tmp}/indoorcoach-bridge-build"
APP_NAME="IndoorCoach Brücke.app"

if security find-identity -v -p codesigning | grep -q "Apple Development"; then
  SIGN=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Apple Development" PROVISIONING_PROFILE_SPECIFIER=)
  [ -n "$TEAM" ] && SIGN+=("DEVELOPMENT_TEAM=$TEAM")
  echo "Signiere mit deinem Apple-Development-Zertifikat."
else
  SIGN=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=-" DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
  echo "Kein Apple-Development-Zertifikat gefunden – signiere ad hoc."
fi

xcodebuild -project IndoorCoach.xcodeproj -scheme IndoorCoachBridge -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" "${SIGN[@]}" -quiet build

BUILT="$DERIVED/Build/Products/Release/$APP_NAME"
codesign --verify --strict "$BUILT"

# Quit a running bridge first (the binary name is ASCII on purpose, see EXECUTABLE_NAME).
if pgrep -x IndoorCoachBridge >/dev/null; then
  pkill -x IndoorCoachBridge || true
  for _ in $(seq 1 20); do pgrep -x IndoorCoachBridge >/dev/null || break; sleep 0.25; done
fi
rm -rf "/Applications/$APP_NAME"
ditto "$BUILT" "/Applications/$APP_NAME"
echo "Installiert: /Applications/$APP_NAME"
open "/Applications/$APP_NAME"
