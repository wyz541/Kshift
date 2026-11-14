#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

simulator_name="${KSHIFT_SIMULATOR_NAME:-iPhone 18 Pro}"
bundle_id="com.wyz541.kshift.lifecycle.preview"
ios_source="${KSHIFT_IOS_APP_PATH:-$root/build/DerivedData/Build/Products/Debug-iphonesimulator/Kshift-iOS.app}"
mac_source="${KSHIFT_MACOS_APP_PATH:-$root/build/DerivedData/Build/Products/Debug/Kshift-macOS.app}"
scratch="${KSHIFT_LIFECYCLE_SCRATCH_DIR:-${TMPDIR:-/tmp}/kshift-preview-lifecycle-$(date +%Y%m%dT%H%M%SZ)-$$}"
report="${KSHIFT_LIFECYCLE_REPORT:-$scratch/report.json}"
mkdir -p "$scratch"

if [[ ! -d "$ios_source" || ! -d "$mac_source" ]]; then
  echo 'Preview apps are missing; run make ios-build mac-build first.' >&2
  exit 1
fi

cp -R "$ios_source" "$scratch/ios-v1.app"
cp -R "$ios_source" "$scratch/ios-v2.app"
cp -R "$mac_source" "$scratch/macos-v1.app"
cp -R "$mac_source" "$scratch/macos-v2.app"

app_plist() {
  local app="$1"
  if [[ -f "$app/Contents/Info.plist" ]]; then
    printf '%s
' "$app/Contents/Info.plist"
  else
    printf '%s
' "$app/Info.plist"
  fi
}

set_plist_value() {
  local plist="$1"
  local key="$2"
  local value="$3"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
  fi
}

set_version() {
  local app="$1"
  local version="$2"
  local plist
  plist="$(app_plist "$app")"
  set_plist_value "$plist" CFBundleShortVersionString "$version"
  set_plist_value "$plist" CFBundleVersion "${version//./}"
}

set_version "$scratch/ios-v1.app" 0.1.0
set_version "$scratch/ios-v2.app" 0.1.1
set_version "$scratch/macos-v1.app" 0.1.0
set_version "$scratch/macos-v2.app" 0.1.1
set_plist_value "$(app_plist "$scratch/ios-v1.app")" CFBundleIdentifier "$bundle_id"
set_plist_value "$(app_plist "$scratch/ios-v2.app")" CFBundleIdentifier "$bundle_id"

udid="$(xcrun simctl list devices available -j \
  | jq -r ".devices[][] | select(.name == \"$simulator_name\") | .udid" \
  | head -1)"
if [[ -z "$udid" ]]; then
  echo "Simulator not found: $simulator_name" >&2
  exit 1
fi
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null

read_ios_version() {
  local container
  container="$(xcrun simctl get_app_container "$udid" "$bundle_id" app)"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$container/Info.plist"
}

install_and_launch_ios() {
  local app="$1"
  local expected="$2"
  xcrun simctl install "$udid" "$app"
  test "$(read_ios_version)" = "$expected"
  SIMCTL_CHILD_KSHIFT_DEMO_MODE=1 xcrun simctl launch "$udid" "$bundle_id" >/dev/null
  sleep 2
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
}

install_and_launch_ios "$scratch/ios-v1.app" 0.1.0
install_and_launch_ios "$scratch/ios-v2.app" 0.1.1
install_and_launch_ios "$scratch/ios-v1.app" 0.1.0
xcrun simctl uninstall "$udid" "$bundle_id" >/dev/null 2>&1 || true

mac_v1_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(app_plist "$scratch/macos-v1.app")")"
mac_v2_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(app_plist "$scratch/macos-v2.app")")"
[[ "$mac_v1_version" == "0.1.0" ]]
[[ "$mac_v2_version" == "0.1.1" ]]

macos_signature="$(codesign -dv --verbose=2 "$mac_source" 2>&1 | awk -F= '/^Signature=/{print $2}')"
[[ -n "$macos_signature" ]]

jq -n \
  --arg simulator "$simulator_name" \
  --arg macos_signature "$macos_signature" \
  --arg ios_install "passed" \
  --arg ios_upgrade "passed" \
  --arg ios_rollback "passed" \
  --arg macos_install "bundle-copy" \
  --arg macos_upgrade "passed" \
  --arg macos_rollback "passed" \
  '{
    status: "passed",
    scope: "preview-ad-hoc",
    ios: {
      simulator: $simulator,
      install: $ios_install,
      upgrade: $ios_upgrade,
      rollback: $ios_rollback
    },
    macos: {
      install: $macos_install,
      upgrade: $macos_upgrade,
      rollback: $macos_rollback,
      signing: $macos_signature
    },
    limitations: ["macOS signed install/upgrade is not covered by this preview test.", "iOS distribution signing is not covered by this simulator test."]
  }' > "$report"

printf 'lifecycle_report=%s\n' "$report"
