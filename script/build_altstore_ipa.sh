#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/Byway-AltStore-DerivedData.XXXXXX")"
PACKAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/Byway-AltStore-Package.XXXXXX")"

cleanup() {
  rm -rf "$DERIVED_DATA" "$PACKAGE_ROOT"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"

xcodebuild   -project "$ROOT_DIR/Xcode/byway.xcodeproj"   -scheme byway   -configuration Release   -destination 'generic/platform=iOS'   -derivedDataPath "$DERIVED_DATA"   CODE_SIGN_ENTITLEMENTS=byway/byway.local.entitlements   CODE_SIGNING_ALLOWED=NO   CODE_SIGNING_REQUIRED=NO   CODE_SIGN_IDENTITY=   DEVELOPMENT_TEAM=   build

APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/byway.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Byway app was not produced at $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist")"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid Byway version: $VERSION" >&2
  exit 1
}

if find "$APP_PATH" \( -name '_CodeSignature' -o -name 'embedded.mobileprovision' \) -print -quit | grep -q .; then
  echo "Unsigned AltStore build unexpectedly contains signing material." >&2
  exit 1
fi

mkdir -p "$PACKAGE_ROOT/Payload"
ditto "$APP_PATH" "$PACKAGE_ROOT/Payload/byway.app"

IPA_PATH="$OUTPUT_DIR/Byway-$VERSION.ipa"
rm -f "$IPA_PATH"
(
  cd "$PACKAGE_ROOT"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry "$IPA_PATH" Payload
)

/usr/bin/unzip -tq "$IPA_PATH"

if unzip -Z1 "$IPA_PATH" | grep -Eq '_CodeSignature|embedded\.mobileprovision|^__MACOSX/'; then
  echo "IPA validation found signing material or macOS metadata." >&2
  exit 1
fi

echo "Created $IPA_PATH"
echo "Version: $VERSION ($BUILD_VERSION)"
shasum -a 256 "$IPA_PATH"
