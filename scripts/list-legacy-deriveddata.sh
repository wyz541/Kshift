#!/bin/zsh
set -euo pipefail

legacy_root="${KSHIFT_LEGACY_DERIVED_DATA_ROOT:-$HOME/Library/Developer/Xcode/DerivedData}"

printf '# Kshift legacy DerivedData manifest\n\n'
printf 'Generated: %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'Root: `%s`\n\n' "$legacy_root"

if [[ ! -d "$legacy_root" ]]; then
  printf 'No legacy DerivedData root exists.\n'
  exit 0
fi

paths=()
for derived_path in "$legacy_root"/Kshift-*(N/); do
  paths+=("$derived_path")
done

if (( ${#paths} == 0 )); then
  printf 'No Kshift legacy DerivedData directories found.\n'
  exit 0
fi

printf '| Path | Size | Modified | Debug products |\n'
printf '| --- | --- | --- | --- |\n'

for derived_path in "${paths[@]}"; do
  size="$(du -sh "$derived_path" | awk '{print $1}')"
  modified="$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$derived_path")"
  products_list=()
  while IFS= read -r product; do
    products_list+=("${product#$derived_path/}")
  done < <(find "$derived_path/Build/Products" -type d \( -name 'Kshift*.app' -o -name 'Kshift*.xctest' \) -print 2>/dev/null || true)
  if (( ${#products_list} == 0 )); then
    products='none'
  else
    products="${(j:<br>:)products_list}"
  fi
  printf '| `%s` | %s | %s | %s |\n' "$derived_path" "$size" "$modified" "$products"
done

printf '\nReview every exact path before removal. This manifest does not delete files.\n'
