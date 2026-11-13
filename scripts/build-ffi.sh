#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target_name="${1:-all}"
if [[ -z "${CARGO_HOME:-}" ]]; then
  export CARGO_HOME="$root/.build/cargo-home"
  mkdir -p "$CARGO_HOME"
  if [[ ! -e "$CARGO_HOME/registry" && -d "$HOME/.cargo/registry" ]]; then
    ln -s "$HOME/.cargo/registry" "$CARGO_HOME/registry"
  fi
fi
if [[ -n "${CARGO:-}" ]]; then
  cargo_bin="$CARGO"
else
  toolchain_bin="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin"
  cargo_bin="$toolchain_bin/cargo"
fi
export PATH="$(dirname "$cargo_bin"):$PATH"
profile="${KSHIFT_RUST_PROFILE:-debug}"
profile_flag=()
offline_flag=()
if [[ "${KSHIFT_CARGO_OFFLINE:-0}" == "1" ]]; then
  offline_flag=(--offline)
fi
if [[ "$profile" == "release" ]]; then
  profile_flag=(--release)
fi

build_target() {
  local label="$1"
  local triple="$2"
  local source="$root/target/$triple/$profile/libkshift_ffi.a"
  local destination="$root/.build/ffi/$label"
  local host_copy="$root/target/$profile/libkshift_ffi.a"

  "$cargo_bin" build -p kshift-ffi --target "$triple" --locked ${profile_flag[@]} ${offline_flag[@]}
  mkdir -p "$destination" "$(dirname "$host_copy")"
  cp "$source" "$destination/libkshift_ffi.a"
  cp "$source" "$host_copy"
  printf 'Built %s\n' "$destination/libkshift_ffi.a"
}

case "$target_name" in
  macos)
    build_target macos aarch64-apple-darwin
    ;;
  ios-simulator)
    build_target ios-simulator aarch64-apple-ios-sim
    ;;
  ios-device)
    build_target ios-device aarch64-apple-ios
    ;;
  all)
    build_target macos aarch64-apple-darwin
    build_target ios-simulator aarch64-apple-ios-sim
    ;;
  *)
    echo "Unknown target: $target_name" >&2
    echo "Expected macos, ios-simulator, ios-device, or all" >&2
    exit 2
    ;;
esac
