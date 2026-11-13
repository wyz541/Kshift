#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if rg -n '#if os\(' Sources/KshiftUI; then
  echo "Shared UI contains a platform conditional." >&2
  exit 1
fi

if rg -n 'URLSession|NWConnection|postgres|sqlx|tonic|prost' Sources/KshiftUI Sources/KshiftCore; then
  echo "Swift host crosses the Rust client boundary." >&2
  exit 1
fi

if ! rg -q 'GlassEffectContainer' Sources/KshiftUI; then
  echo "Shared UI does not use GlassEffectContainer." >&2
  exit 1
fi

if ! rg -q 'glassEffect\(\.regular' Sources/KshiftUI; then
  echo "Shared UI does not use native Glass.regular." >&2
  exit 1
fi

xcodegen generate

if [[ "${KSHIFT_SKIP_XCODE_TESTS:-0}" == "1" ]]; then
  echo "Xcode build verification skipped."
  exit 0
fi

xcodebuild \
  -project Kshift.xcodeproj \
  -scheme KshiftMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

xcodebuild \
  -project Kshift.xcodeproj \
  -scheme KshiftIOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  test
