#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$root/build/DerivedData"
cd "$root"

./scripts/check-build-governance.py

if rg -n '#if os\(' Sources/KshiftCore Sources/KshiftUI; then
  echo "Shared UI contains a platform conditional." >&2
  exit 1
fi

if rg -n 'URLSession|NWConnection|postgres|sqlx|tonic|prost' Sources/KshiftCore Sources/KshiftPresentation Sources/KshiftFFI Sources/KshiftUI; then
  echo "Swift host crosses the Rust client boundary." >&2
  exit 1
fi

if ! rg -q 'GlassEffectContainer' Sources/KshiftCore Sources/KshiftUI; then
  echo "Shared UI does not use GlassEffectContainer." >&2
  exit 1
fi

if ! rg -q 'glassEffect\(\.regular' Sources/KshiftCore Sources/KshiftUI; then
  echo "Shared UI does not use native Glass.regular." >&2
  exit 1
fi

xcodegen generate
./scripts/check-platform-boundaries.sh

if [[ "${KSHIFT_SKIP_XCODE_TESTS:-0}" == "1" ]]; then
  echo "Xcode build verification skipped."
  exit 0
fi

xcodebuild \
  -project Kshift.xcodeproj \
  -scheme Kshift-macOS \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  build

xcodebuild \
  -project Kshift.xcodeproj \
  -scheme Kshift-iOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath "$derived_data" \
  test
