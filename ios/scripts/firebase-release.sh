#!/usr/bin/env bash
# Bouwt een ad-hoc versie van Miso en zet hem via Firebase App Distribution
# klaar voor de groep "gezin". Gebruik: ios/scripts/firebase-release.sh "wat is er nieuw"
set -euo pipefail

NOTES="${1:-Nieuwe versie van Miso}"
APP_ID="1:477971863265:ios:b928a7e65c3d4346efc9a0"
PROJECT="miso-f63e7"
HERE="$(cd "$(dirname "$0")" && pwd)"
IOS="$(dirname "$HERE")"
WORK="$(mktemp -d)"

cd "$IOS"
xcodegen generate >/dev/null
# Buildnummer = tijdstempel, zodat elke release uniek is.
BUILD="$(date +%Y%m%d%H%M)"

xcodebuild -project AHRecepten.xcodeproj -scheme AHRecepten -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$WORK/Miso.xcarchive" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" archive -quiet

# -allowProvisioningUpdates neemt nieuw geregistreerde iPhones mee in het profiel.
xcodebuild -exportArchive -archivePath "$WORK/Miso.xcarchive" \
  -exportOptionsPlist "$HERE/AdHocOptions.plist" -exportPath "$WORK/out" \
  -allowProvisioningUpdates -quiet

firebase appdistribution:distribute "$WORK/out/AHRecepten.ipa" \
  --app "$APP_ID" --project "$PROJECT" --groups gezin --release-notes "$NOTES"

echo "Klaar: build $BUILD staat in Firebase."
