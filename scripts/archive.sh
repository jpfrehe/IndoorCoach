#!/usr/bin/env bash
# Archives IndoorCoach (Release) and exports an App Store Connect / TestFlight build.
#
#   DEVELOPMENT_TEAM=ABCDE12345 scripts/archive.sh            # build/export/IndoorCoach.ipa
#   DEVELOPMENT_TEAM=ABCDE12345 UPLOAD=1 scripts/archive.sh   # upload straight to App Store Connect
#
# Signing is automatic (an Xcode account with access to the team must be signed in).
set -euo pipefail

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Fehler: DEVELOPMENT_TEAM ist nicht gesetzt." >&2
  echo "Team-ID (10 Zeichen) aus developer.apple.com → Account → Membership, dann z. B.:" >&2
  echo "  DEVELOPMENT_TEAM=ABCDE12345 scripts/archive.sh" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
ARCHIVE_PATH="$BUILD_DIR/IndoorCoach.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

# Team ID (and optionally the upload destination) go into a copy – the checked-in plist stays team-neutral.
cp "$ROOT/scripts/ExportOptions.plist" "$EXPORT_OPTIONS"
plutil -replace teamID -string "$DEVELOPMENT_TEAM" "$EXPORT_OPTIONS"
if [[ "${UPLOAD:-0}" == "1" ]]; then
  plutil -replace destination -string upload "$EXPORT_OPTIONS"
fi

echo "==> Archiv (Release, Team $DEVELOPMENT_TEAM)"
xcodebuild archive \
  -project "$ROOT/IndoorCoach.xcodeproj" \
  -scheme IndoorCoach \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"

echo "==> Export (app-store-connect)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

if [[ "${UPLOAD:-0}" == "1" ]]; then
  echo "Fertig: Build an App Store Connect übertragen (erscheint nach der Verarbeitung in TestFlight)."
else
  echo "Fertig: $EXPORT_PATH – .ipa mit Transporter oder dem Xcode Organizer hochladen."
fi
