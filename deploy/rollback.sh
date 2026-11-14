#!/bin/zsh
set -euo pipefail

version=''
allow_schema_compatibility='no'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --allow-schema-compatibility) allow_schema_compatibility='yes'; shift ;;
    -h|--help)
      printf '%s\n' 'Usage: sudo deploy/rollback.sh --version VERSION [--allow-schema-compatibility]'
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ $EUID -ne 0 ]]; then
  echo 'rollback.sh must run as root' >&2
  exit 2
fi
if [[ -z "$version" ]]; then
  echo '--version is required' >&2
  exit 2
fi
home='/Library/Application Support/Kshift'
target="$home/versions/$version"
if [[ ! -d "$target" ]]; then
  echo "installed version not found: $version" >&2
  exit 2
fi
if [[ "$allow_schema_compatibility" != 'yes' ]]; then
  echo 'Schema compatibility must be confirmed with --allow-schema-compatibility.' >&2
  echo 'For an incompatible migration, restore the pre-migration backup instead.' >&2
  exit 2
fi

rm -f "$home/current.next"
ln -s "versions/$version" "$home/current.next"
mv -f "$home/current.next" "$home/current"
launchctl kickstart -k system/com.wyz541.kshift.server
sleep 3
set -a
source "$home/etc/kshift.env"
set +a
"$home/current/bin/kshift-ops" health --server-bin "$home/current/bin/kshift-server" --database-url-env KSHIFT_DATABASE_URL --disk-path "$home" --minimum-free-gib 10
