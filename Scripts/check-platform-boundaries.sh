#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "Platform boundary check failed: $1" >&2
  exit 1
}

for file in $(find Sources/KshiftPresentation Sources/KshiftFFI Sources/KshiftUI -name '*.swift' -type f); do
  for framework in AppKit UIKit Network FoundationNetworking GRPC NIO PostgresNIO SQLKit SwiftProtobuf; do
    if grep -q "import ${framework}" "$file"; then
      fail "$file imports $framework"
    fi
  done
done

for file in $(find Sources Apps -name '*.swift' -type f); do
  if ! grep -q '#if os(' "$file"; then
    continue
  fi

  case "$file" in
    Apps/*|Sources/KshiftAppKitAdapter/*|Sources/KshiftUIKitAdapter/*)
      ;;
    *)
      fail "#if os is not allowed in $file"
      ;;
  esac
done

[[ -f Apps/KshiftMacOS/KshiftMacOSApp.swift ]] || fail "macOS app entry is missing"
[[ -f Apps/KshiftIOS/KshiftIOSApp.swift ]] || fail "iOS app entry is missing"
[[ -f Sources/KshiftUI/Feature/KshiftDayPlanFeatureView.swift ]] || fail "shared feature is missing"

echo "Platform boundary check passed."
