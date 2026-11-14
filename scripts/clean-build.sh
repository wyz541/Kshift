#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="$root/build/DerivedData"

if (( $# > 1 )) || (( $# == 1 )) && [[ "$1" != "--dry-run" ]]; then
  echo "usage: $0 [--dry-run]" >&2
  exit 2
fi

if [[ "$target" != "$root/build/DerivedData" ]]; then
  echo "refusing unexpected build path: $target" >&2
  exit 1
fi

if [[ -L "$root/build" || -L "$target" ]]; then
  echo "refusing to clean a symlinked build path: $target" >&2
  exit 1
fi

printf 'DerivedData: %s\n' "$target"

if [[ ! -e "$target" ]]; then
  echo "DerivedData is not present."
  exit 0
fi

if [[ ! -d "$target" ]]; then
  echo "refusing to remove a non-directory DerivedData path: $target" >&2
  exit 1
fi

if [[ "${1:-}" == "--dry-run" ]]; then
  echo "Dry run: no paths removed."
  exit 0
fi

rm -rf -- "$target"
printf 'Removed DerivedData: %s\n' "$target"
