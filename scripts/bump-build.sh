#!/usr/bin/env bash
# Sets CURRENT_PROJECT_VERSION (CFBundleVersion) for all targets/configurations in the Xcode project.
#
#   scripts/bump-build.sh          # timestamp, e.g. 202611171045
#   scripts/bump-build.sh 42       # explicit build number
#
# App Store Connect requires a build number that increases with every upload of the same version.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/IndoorCoach.xcodeproj/project.pbxproj"
BUILD="${1:-$(date +%Y%m%d%H%M)}"

if [[ ! "$BUILD" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "Fehler: ungültige Build-Nummer '$BUILD' (erlaubt: 1–3 Zahlen mit Punkt, z. B. 42 oder 1.0.3)." >&2
  exit 1
fi
if ! grep -q 'CURRENT_PROJECT_VERSION = ' "$PBXPROJ"; then
  echo "Fehler: CURRENT_PROJECT_VERSION nicht in $PBXPROJ gefunden." >&2
  exit 1
fi

sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD;/g" "$PBXPROJ"
echo "CURRENT_PROJECT_VERSION = $BUILD ($(grep -c "CURRENT_PROJECT_VERSION = $BUILD;" "$PBXPROJ") Konfigurationen)"
