#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
version="${KSHIFT_VERSION:?KSHIFT_VERSION is required}"
channel="${KSHIFT_CHANNEL:-preview}"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo 'version must be SemVer core MAJOR.MINOR.PATCH' >&2
  exit 2
fi
output_dir="${KSHIFT_OUTPUT_DIR:-$root/dist}"
project="${KSHIFT_XCODE_PROJECT:-$root/Kshift.xcodeproj}"
scheme="${KSHIFT_IOS_SCHEME:-Kshift-iOS}"
build_root="$(mktemp -d "$TMPDIR/kshift-ios-build.XXXXXX")"
trap 'rm -rf "$build_root"' EXIT
mkdir -p "$output_dir"

cd "$root"
if [[ ! -d "$project" ]]; then
  if [[ -f "$root/project.yml" ]] && command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --spec "$root/project.yml"
  else
    echo "Xcode project is missing: $project (install xcodegen or set KSHIFT_XCODE_PROJECT)" >&2
    exit 2
  fi
fi

ipa="$output_dir/kshift-$version-ios-arm64.ipa"
if [[ "$channel" == 'preview' ]]; then
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -configuration Release \
    -sdk iphoneos \
    -derivedDataPath "$build_root/DerivedData" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build
  app="$(find "$build_root/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -type d -name 'Kshift-iOS.app' -print -quit)"
  if [[ -z "$app" ]]; then
    app="$(find "$build_root/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -type d -name 'Kshift.app' -print -quit)"
  fi
  if [[ -z "$app" || ! -d "$app" ]]; then
    echo 'iOS application was not produced' >&2
    exit 2
  fi
  payload="$build_root/Payload"
  mkdir -p "$payload"
  cp -R "$app" "$payload/$(basename "$app")"
  (cd "$build_root" && zip -qry "$ipa" Payload)
else
  team="${APPLE_TEAM_ID:?stable iOS build requires APPLE_TEAM_ID}"
  method="${KSHIFT_IOS_EXPORT_METHOD:-app-store-connect}"
  archive="$build_root/Kshift-iOS.xcarchive"
  export_dir="$build_root/export"
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive" \
    DEVELOPMENT_TEAM="$team" \
    CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates \
    archive
  cat > "$build_root/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$method</string>
  <key>teamID</key>
  <string>$team</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$build_root/ExportOptions.plist" -exportPath "$export_dir" -allowProvisioningUpdates
  exported="$(find "$export_dir" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
  if [[ -z "$exported" ]]; then
    echo 'iOS export did not produce an IPA' >&2
    exit 2
  fi
  cp "$exported" "$ipa"
fi
unzip -tq "$ipa" >/dev/null
shasum -a 256 "$ipa" > "$ipa.sha256"
printf '%s\n' "$ipa"
