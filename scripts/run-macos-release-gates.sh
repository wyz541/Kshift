#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != 'Darwin' ]]; then
  echo 'macOS release gates require macOS' >&2
  exit 2
fi
: "${KSHIFT_MACOS_STABLE_DMG:?KSHIFT_MACOS_STABLE_DMG must point to the Stable DMG}"
: "${KSHIFT_MACOS_STABLE_ZIP:?KSHIFT_MACOS_STABLE_ZIP must point to the Stable ZIP}"
: "${KSHIFT_MACOS_PREVIOUS_ZIP:?KSHIFT_MACOS_PREVIOUS_ZIP must point to the previous macOS ZIP}"
for command in hdiutil ditto unzip codesign plutil jq python3 git node shasum rg open pgrep ioreg swiftc; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "missing required command: $command" >&2
    exit 2
  }
done

if [[ "$(ioreg -n Root -d1 -a | plutil -extract IOConsoleLocked raw -o - - 2>/dev/null)" == 'true' ]]; then
  echo 'macOS release gates require an unlocked console session for window and accessibility evidence' >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
version="${KSHIFT_VERSION:-0.1.0}"
channel="${KSHIFT_CHANNEL:-stable}"
source_commit="$(git rev-parse HEAD)"
if [[ "$channel" != 'stable' && "$channel" != 'hotfix' ]]; then
  echo 'macOS release gates require KSHIFT_CHANNEL=stable or hotfix' >&2
  exit 2
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo 'macOS release gates require a clean source tree' >&2
  exit 2
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/kshift-macos-release-gates.XXXXXX")"
report="${KSHIFT_MACOS_RUNTIME_EVIDENCE_OUTPUT:-${TMPDIR:-/tmp}/kshift-macos-runtime-evidence-$(date +%Y%m%dT%H%M%SZ).json}"
assets="${KSHIFT_MACOS_EVIDENCE_ASSET_DIR:-$scratch/assets}"
accessibility_audit_tool="$scratch/macos-accessibility-audit"
dmg_mount="$scratch/dmg"
mkdir -p "$scratch/stable-zip" "$scratch/previous-zip" "$dmg_mount" "$assets"
swiftc scripts/audit-macos-accessibility.swift -o "$accessibility_audit_tool"
mounted=no

cleanup() {
  pkill -f 'kshift-macos-release-gates\..*/Applications/Kshift-macOS\.app/Contents/MacOS/Kshift-macOS' >/dev/null 2>&1 || true
  if [[ "$mounted" == 'yes' ]]; then
    hdiutil detach "$dmg_mount" -force -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT

hdiutil attach "$KSHIFT_MACOS_STABLE_DMG" -readonly -nobrowse -mountpoint "$dmg_mount" -quiet
mounted=yes
stable_dmg_app="$(find "$dmg_mount" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$stable_dmg_app" ]]
ditto "$stable_dmg_app" "$scratch/stable-from-dmg.app"
unzip -q "$KSHIFT_MACOS_STABLE_ZIP" -d "$scratch/stable-zip"
unzip -q "$KSHIFT_MACOS_PREVIOUS_ZIP" -d "$scratch/previous-zip"
stable_zip_app="$(find "$scratch/stable-zip" -maxdepth 1 -type d -name '*.app' -print -quit)"
previous_app="$(find "$scratch/previous-zip" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$stable_zip_app" && -n "$previous_app" ]]
stable_app="$scratch/stable-from-dmg.app"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

bundle_id="$(plist_value "$stable_app" CFBundleIdentifier)"
short_version="$(plist_value "$stable_app" CFBundleShortVersionString)"
build_version="$(plist_value "$stable_app" CFBundleVersion)"
previous_bundle_id="$(plist_value "$previous_app" CFBundleIdentifier)"
previous_short_version="$(plist_value "$previous_app" CFBundleShortVersionString)"
[[ "$bundle_id" == 'com.wyz541.kshift.mac' ]]
[[ "$previous_bundle_id" == "$bundle_id" ]]
[[ "$short_version" == "$version" ]]
[[ "$build_version" == "$version" ]]
codesign --verify --deep --strict --verbose=2 "$stable_app" >/dev/null
codesign --verify --deep --strict --verbose=2 "$stable_zip_app" >/dev/null
codesign --verify --deep --strict --verbose=2 "$previous_app" >/dev/null

stable_signature_raw="$(codesign -dv --verbose=4 "$stable_app" 2>&1 | awk -F= '/^Signature=/{print $2; exit}')"
if [[ "$stable_signature_raw" == 'adhoc' ]]; then
  stable_signature='ad-hoc'
elif [[ -n "$stable_signature_raw" ]]; then
  stable_signature='signed'
else
  echo 'Stable application has no code signature' >&2
  exit 1
fi
stable_executable="$(plist_value "$stable_app" CFBundleExecutable)"
[[ -n "$stable_executable" ]]
stable_executable_sha256="$(shasum -a 256 "$stable_app/Contents/MacOS/$stable_executable" | awk '{print $1}')"
zip_executable_sha256="$(shasum -a 256 "$stable_zip_app/Contents/MacOS/$stable_executable" | awk '{print $1}')"
[[ "$stable_executable_sha256" == "$zip_executable_sha256" ]]
application_payload_sha256="$(
  node release/tools/runtime-evidence.mjs tree-digest \
    --root "$stable_app" \
    --exclude 'Contents/Info.plist,Contents/_CodeSignature' | jq -r '.sha256'
)"

install_root="$scratch/Applications"
installed_app="$install_root/Kshift-macOS.app"
mkdir -p "$install_root"

launch_with_evidence() {
  local app="$1"
  local prefix="$2"
  local screenshot="$assets/$prefix.png"
  local metrics="$scratch/$prefix-metrics.json"
  local log="$scratch/$prefix.log"
  local args=(
    -n -W -o "$log" --stderr "$log"
    --env "KSHIFT_DEMO_MODE=1"
    --env "KSHIFT_USE_FFI=0"
    --env "KSHIFT_RESET_PLANNER_VIEW_STATE=1"
    --env "KSHIFT_CAPTURE_PNG=$screenshot"
    --env "KSHIFT_CAPTURE_METRICS_PATH=$metrics"
  )
  open "${args[@]}" "$app"
  [[ -s "$screenshot" ]]
  [[ -s "$metrics" ]]
  [[ "$(jq -r '.model_loaded' "$metrics")" == 'true' ]]
  [[ "$(jq -r '.screenshot_error' "$metrics")" == 'null' ]]
  printf '%s\n' "$screenshot"
}

launch_previous_app() {
  local app="$1"
  local real_app
  real_app="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$app")"
  open -n "$app"
  sleep 3
  pgrep -f "$real_app/Contents/MacOS/Kshift-macOS" >/dev/null
  pkill -f "$real_app/Contents/MacOS/Kshift-macOS" >/dev/null 2>&1 || true
}

ditto "$previous_app" "$installed_app"
rm -rf "$installed_app"
ditto "$stable_app" "$installed_app"
install_screenshot="$(launch_with_evidence "$installed_app" macos-liquid-glass-light)"

rm -rf "$installed_app"
ditto "$previous_app" "$installed_app"
rm -rf "$installed_app"
ditto "$stable_app" "$installed_app"
upgrade_screenshot="$(launch_with_evidence "$installed_app" macos-upgrade)"

accessibility_screenshot="$(launch_with_evidence "$installed_app" macos-accessibility)"
accessibility_audit="$scratch/macos-accessibility-audit.json"
real_installed_app="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$installed_app")"
open -n \
  --env "KSHIFT_DEMO_MODE=1" \
  --env "KSHIFT_USE_FFI=0" \
  --env "KSHIFT_RESET_PLANNER_VIEW_STATE=1" \
  "$installed_app"
accessibility_pid=''
for _ in {1..40}; do
  accessibility_pid="$(pgrep -f "$real_installed_app/Contents/MacOS/Kshift-macOS" | head -1)"
  [[ -n "$accessibility_pid" ]] && break
  sleep 0.25
done
[[ -n "$accessibility_pid" ]]
sleep 2
"$accessibility_audit_tool" "$accessibility_pid" "$accessibility_audit" >/dev/null
jq -e '.audit_passed == true and .issue_count == 0' "$accessibility_audit" >/dev/null
kill "$accessibility_pid" >/dev/null 2>&1 || true
cp "$accessibility_audit" "$assets/macos-accessibility-audit.json"

export KSHIFT_FORCE_COLOR_SCHEME=dark
launch_with_evidence "$installed_app" macos-liquid-glass-dark >/dev/null
unset KSHIFT_FORCE_COLOR_SCHEME
export KSHIFT_FORCE_DYNAMIC_TYPE=accessibility3
launch_with_evidence "$installed_app" macos-large-text >/dev/null
unset KSHIFT_FORCE_DYNAMIC_TYPE
export KSHIFT_FORCE_REDUCE_TRANSPARENCY=1
launch_with_evidence "$installed_app" macos-reduce-transparency >/dev/null
unset KSHIFT_FORCE_REDUCE_TRANSPARENCY

performance_samples=()
for iteration in 1 2 3; do
  launch_with_evidence "$installed_app" "macos-performance-$iteration" >/dev/null
  performance_samples+=("$(jq -r '.launch_to_evidence_ready_ms' "$scratch/macos-performance-$iteration-metrics.json")")
done
performance="$(
  python3 - "${performance_samples[@]}" <<'PY'
import json
import statistics
import sys
values = [float(value) for value in sys.argv[1:]]
print(json.dumps({
    'metric': 'launch-to-evidence-ready',
    'iterations': len(values),
    'average_ms': statistics.mean(values),
    'maximum_ms': max(values),
    'samples_ms': values,
}, sort_keys=True))
PY
)"
[[ "$(jq -r '.iterations' <<<"$performance")" -ge 3 ]]
[[ "$(jq -r '.average_ms' <<<"$performance")" -le 5000 ]]
[[ "$(jq -r '.maximum_ms' <<<"$performance")" -le 8000 ]]

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -u "$installed_app" >/dev/null 2>&1 || true
rm -rf "$installed_app"
[[ ! -e "$installed_app" ]]
installed_real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$installed_app")"
if pgrep -f "$installed_real/Contents/MacOS/Kshift-macOS" >/dev/null; then
  echo 'stable application process is still running after uninstall' >&2
  exit 1
fi

rm -rf "$installed_app"
ditto "$previous_app" "$installed_app"
launch_previous_app "$installed_app"
cmp -s "$stable_app/Contents/MacOS/$stable_executable" "$previous_app/Contents/MacOS/$stable_executable" && {
  echo 'rollback application unexpectedly matches the Stable executable' >&2
  exit 1
}
rm -rf "$installed_app"

rg -q 'GlassEffectContainer' Sources/KshiftUI
rg -q 'glassEffect\(\.regular' Sources/KshiftUI
normal_sha256="$(shasum -a 256 "$install_screenshot" | awk '{print $1}')"
accessibility_sha256="$(shasum -a 256 "$accessibility_screenshot" | awk '{print $1}')"
source_inputs="$(node release/tools/runtime-evidence.mjs source-digest --root "$root" --platform macos)"
source_inputs_sha256="$(jq -r '.sha256' <<<"$source_inputs")"

jq -n \
  --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg version "$version" \
  --arg channel "$channel" \
  --arg source_commit "$source_commit" \
  --arg source_inputs_sha256 "$source_inputs_sha256" \
  --arg bundle_id "$bundle_id" \
  --arg short_version "$short_version" \
  --arg build_version "$build_version" \
  --arg signature "$stable_signature" \
  --arg executable_sha256 "$stable_executable_sha256" \
  --arg application_payload_sha256 "$application_payload_sha256" \
  --arg previous_short_version "$previous_short_version" \
  --arg normal_sha256 "$normal_sha256" \
  --arg accessibility_sha256 "$accessibility_sha256" \
  --arg os_version "$(sw_vers -productVersion)" \
  --arg hardware_model "$(sysctl -n hw.model)" \
  --slurpfile audit "$accessibility_audit" \
  --argjson performance "$performance" \
  '{
    schema_version: "1",
    kind: "runtime-release-evidence",
    product: "Kshift",
    version: $version,
    channel: $channel,
    platform: "macos",
    generated_at: $generated,
    source: {
      commit: $source_commit,
      tree_state: "clean",
      input_algorithm: "kshift-runtime-inputs-v1",
      input_scope: "macos",
      input_sha256: $source_inputs_sha256
    },
    host: {
      os: "macOS",
      os_version: $os_version,
      architecture: "arm64",
      hardware_model: $hardware_model
    },
    artifact: {
      bundle_id: $bundle_id,
      short_version: $short_version,
      build_version: $build_version,
      signature: $signature,
      executable_sha256: $executable_sha256,
      application_payload_sha256: $application_payload_sha256
    },
    gates: [
      {
        name: "install",
        status: "passed",
        detail: {
          installed: true,
          launched: true,
          source: "Stable DMG",
          candidate_version: $short_version,
          screenshot_sha256: $normal_sha256
        }
      },
      {
        name: "upgrade",
        status: "passed",
        detail: {
          replaced: true,
          launched: true,
          previous_version: (if $previous_short_version == "" then "0.1.0-preview.4" else $previous_short_version end),
          candidate_version: $short_version
        }
      },
      {
        name: "uninstall",
        status: "passed",
        detail: {
          app_absent: true,
          process_stopped: true,
          scope: "isolated application directory"
        }
      },
      {
        name: "rollback",
        status: "passed",
        detail: {
          restored_previous: true,
          launched: true,
          previous_version: (if $previous_short_version == "" then "0.1.0-preview.4" else $previous_short_version end)
        }
      },
      {
        name: "liquid-glass",
        status: "passed",
        detail: {
          glass_container: true,
          glass_regular: true,
          screenshot_sha256: $normal_sha256,
          modes: ["light", "dark", "large-text", "reduce-transparency"]
        }
      },
      {
        name: "accessibility",
        status: "passed",
        detail: {
          audit_passed: $audit[0].audit_passed,
          issue_count: $audit[0].issue_count,
          element_count: $audit[0].element_count,
          scope: $audit[0].scope,
          screenshot_sha256: $accessibility_sha256
        }
      },
      {
        name: "performance",
        status: "passed",
        detail: $performance
      }
    ],
    limitations: [
      "Lifecycle gates use an isolated application directory on the internal Apple-silicon macOS host.",
      "The previous artifact is v0.1.0-preview.4 and does not embed a CFBundleShortVersionString.",
      "Increase Contrast and Reduce Motion source branches are statically checked; system-level toggling was not automated."
    ]
  }' > "$report"

node release/tools/runtime-evidence.mjs verify \
  --root "$root" \
  --evidence "$report" \
  --platform macos \
  --version "$version" \
  --channel "$channel" \
  --candidate-commit "$source_commit" \
  --application "$stable_app" \
  --expected-gates 'install,upgrade,uninstall,rollback,liquid-glass,accessibility,performance' \
  --output "$scratch/verified-gates.json" >/dev/null

printf 'macos_runtime_evidence=%s\n' "$report"
printf 'macos_evidence_assets=%s\n' "$assets"
