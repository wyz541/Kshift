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
scheme="${KSHIFT_MACOS_SCHEME:-Kshift-macOS}"
identity="${MACOS_SIGN_IDENTITY:--}"
build_root="$(mktemp -d "$TMPDIR/kshift-macos-build.XXXXXX")"
trap 'rm -rf "$build_root"' EXIT

cd "$root"
if [[ ! -d "$project" ]]; then
  if [[ -f "$root/project.yml" ]] && command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --spec "$root/project.yml"
  else
    echo "Xcode project is missing: $project (install xcodegen or set KSHIFT_XCODE_PROJECT)" >&2
    exit 2
  fi
fi

signing_args=(CODE_SIGN_IDENTITY="$identity")
if [[ "$channel" == 'stable' || "$channel" == 'hotfix' ]] && [[ "$identity" == '-' ]]; then
  echo 'stable macOS build requires MACOS_SIGN_IDENTITY' >&2
  exit 2
fi
if [[ "$channel" == 'preview' ]]; then
  signing_args+=(CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
fi

xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration Release \
  -derivedDataPath "$build_root/DerivedData" \
  -destination 'platform=macOS' \
  "${signing_args[@]}" \
  build

app="$(find "$build_root/DerivedData/Build/Products/Release" -maxdepth 1 -type d -name 'Kshift-macOS.app' -print -quit)"
if [[ -z "$app" ]]; then
  app="$(find "$build_root/DerivedData/Build/Products/Release" -maxdepth 1 -type d -name 'Kshift.app' -print -quit)"
fi
if [[ -z "$app" || ! -d "$app" ]]; then
  echo 'macOS application was not produced' >&2
  exit 2
fi
if [[ "$channel" == 'stable' || "$channel" == 'hotfix' ]]; then
  codesign --verify --deep --strict --verbose=2 "$app"
fi

mkdir -p "$output_dir"
dmg="$output_dir/kshift-$version-macos-arm64.dmg"
hdiutil create -quiet -volname Kshift -srcfolder "$app" -ov -format UDZO "$dmg"
zip="$output_dir/kshift-$version-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
shasum -a 256 "$dmg" "$zip" > "$output_dir/macos-sha256.txt"
printf '%s\n' "$dmg" "$zip"
