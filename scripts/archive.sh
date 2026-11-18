#!/usr/bin/env bash
# Archives IndoorCoach (Release) and exports an App Store Connect / TestFlight build.
#
#   DEVELOPMENT_TEAM=ABCDE12345 scripts/archive.sh            # build/export/IndoorCoach.ipa
#   DEVELOPMENT_TEAM=ABCDE12345 UPLOAD=1 scripts/archive.sh   # upload straight to App Store Connect
#
# Signing is automatic (an Xcode account with access to the team must be signed in).
#
# Optional (CI, see docs/13-APP-STORE-RELEASE.md) – without these variables nothing changes:
#   ASC_KEY_PATH + ASC_KEY_ID + ASC_ISSUER_ID   App Store Connect API key instead of an Xcode login (all three or none)
#   BUNDLE_ID                                   overrides PRODUCT_BUNDLE_IDENTIFIER
#   MARKETING_VERSION                           overrides the app version (e.g. 1.2.3)
set -euo pipefail

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Fehler: DEVELOPMENT_TEAM ist nicht gesetzt." >&2
  echo "Team-ID (10 Zeichen) aus developer.apple.com → Account → Membership, dann z. B.:" >&2
  echo "  DEVELOPMENT_TEAM=ABCDE12345 scripts/archive.sh" >&2
  exit 1
fi

ASC_SET=0
for v in "${ASC_KEY_PATH:-}" "${ASC_KEY_ID:-}" "${ASC_ISSUER_ID:-}"; do
  [[ -n "$v" ]] && ASC_SET=$((ASC_SET + 1))
done
if [[ "$ASC_SET" -ne 0 && "$ASC_SET" -ne 3 ]]; then
  echo "Fehler: API-Key-Anmeldung unvollständig – ASC_KEY_PATH, ASC_KEY_ID und ASC_ISSUER_ID müssen alle drei gesetzt sein (oder keine)." >&2
  exit 1
fi
if [[ "$ASC_SET" -eq 3 && ! -f "$ASC_KEY_PATH" ]]; then
  echo "Fehler: ASC_KEY_PATH zeigt auf keine Datei: $ASC_KEY_PATH" >&2
  exit 1
fi
if [[ -n "${MARKETING_VERSION:-}" && ! "$MARKETING_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "Fehler: ungültige MARKETING_VERSION '$MARKETING_VERSION' (erlaubt: z. B. 1.2.3)." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
ARCHIVE_PATH="$BUILD_DIR/IndoorCoach.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

AUTH_ARGS=()
if [[ "$ASC_SET" -eq 3 ]]; then
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
SETTING_ARGS=()
[[ -n "${BUNDLE_ID:-}" ]] && SETTING_ARGS+=("PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID")
[[ -n "${MARKETING_VERSION:-}" ]] && SETTING_ARGS+=("MARKETING_VERSION=$MARKETING_VERSION")

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
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  ${SETTING_ARGS[@]+"${SETTING_ARGS[@]}"}

echo "==> Export (app-store-connect)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}

if [[ "${UPLOAD:-0}" == "1" ]]; then
  echo "Fertig: Build an App Store Connect übertragen (erscheint nach der Verarbeitung in TestFlight)."
else
  echo "Fertig: $EXPORT_PATH – .ipa mit Transporter oder dem Xcode Organizer hochladen."
fi
