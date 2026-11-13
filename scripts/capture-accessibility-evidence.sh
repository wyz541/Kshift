#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

simulator_name="${KSHIFT_SIMULATOR_NAME:-iPhone 18 Pro}"
bundle_id="com.wyz541.kshift.ios"
app_path="${KSHIFT_APP_PATH:-}"

if [[ -z "$app_path" ]]; then
  app_path="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/Build/Products/Debug-iphonesimulator/Kshift-iOS.app" \
    -type d 2>/dev/null | head -1)"
fi
if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "Kshift-iOS.app not found. Run make ios-build first." >&2
  exit 1
fi

udid="$(xcrun simctl list devices available -j \
  | jq -r ".devices[][] | select(.name == \"$simulator_name\") | .udid" \
  | head -1)"
if [[ -z "$udid" ]]; then
  echo "Simulator not found: $simulator_name" >&2
  exit 1
fi

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$app_path"

output="$root/docs/evidence/accessibility"
mkdir -p "$output"

restart_system_ui() {
  xcrun simctl spawn "$udid" killall SpringBoard >/dev/null 2>&1 || true
  sleep 2
}

launch_app() {
  local force_reduce_transparency="${1:-0}"
  SIMCTL_CHILD_KSHIFT_DEMO_MODE=1 \
    SIMCTL_CHILD_KSHIFT_FORCE_REDUCE_TRANSPARENCY="$force_reduce_transparency" \
    xcrun simctl launch "$udid" "$bundle_id" >/dev/null
}

capture() {
  local name="$1"
  local force_reduce_transparency="${2:-0}"
  xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
  launch_app "$force_reduce_transparency"
  sleep 3
  xcrun simctl io "$udid" screenshot "$output/$name.png" >/dev/null
  printf 'Captured %s\n' "$output/$name.png"
}

reset_ui() {
  xcrun simctl ui "$udid" appearance light >/dev/null
  xcrun simctl ui "$udid" increase_contrast disabled >/dev/null
  xcrun simctl ui "$udid" content_size large >/dev/null
  xcrun simctl spawn "$udid" defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool false >/dev/null
  xcrun simctl spawn "$udid" defaults write com.apple.Accessibility ReduceMotionEnabled -bool false >/dev/null
}

reset_ui
restart_system_ui
capture "ios-light"

xcrun simctl ui "$udid" appearance dark >/dev/null
capture "ios-dark"

xcrun simctl ui "$udid" appearance light >/dev/null
xcrun simctl ui "$udid" increase_contrast enabled >/dev/null
capture "ios-increase-contrast"

xcrun simctl ui "$udid" increase_contrast disabled >/dev/null
xcrun simctl ui "$udid" content_size accessibility-extra-extra-extra-large >/dev/null
capture "ios-large-text"

xcrun simctl ui "$udid" content_size large >/dev/null
xcrun simctl spawn "$udid" defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool true >/dev/null
restart_system_ui
capture "ios-reduce-transparency" 1

xcrun simctl spawn "$udid" defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool false >/dev/null
xcrun simctl spawn "$udid" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true >/dev/null
restart_system_ui
capture "ios-reduce-motion"

reset_ui
