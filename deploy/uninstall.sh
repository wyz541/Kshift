#!/bin/zsh
set -euo pipefail

confirm='no'
purge_data='no'
for argument in "$@"; do
  case "$argument" in
    --confirm) confirm='yes' ;;
    --purge-data) purge_data='yes' ;;
    -h|--help)
      printf '%s\n' 'Usage: sudo deploy/uninstall.sh --confirm [--purge-data]'
      exit 0
      ;;
    *) echo "unknown argument: $argument" >&2; exit 2 ;;
  esac
done
if [[ $EUID -ne 0 ]]; then
  echo 'uninstall.sh must run as root' >&2
  exit 2
fi
if [[ "$confirm" != 'yes' ]]; then
  echo 'uninstall requires --confirm' >&2
  exit 2
fi

plist_root='/Library/LaunchDaemons'
for label in \
  com.wyz541.kshift.health \
  com.wyz541.kshift.backup-monthly \
  com.wyz541.kshift.backup-weekly \
  com.wyz541.kshift.backup-4h \
  com.wyz541.kshift.server; do
  launchctl bootout system "$plist_root/$label.plist" >/dev/null 2>&1 || true
  rm -f "$plist_root/$label.plist"
done
rm -f /etc/newsyslog.d/com.wyz541.kshift.conf

if [[ "$purge_data" == 'yes' ]]; then
  echo 'Purging databases, backups, logs and installed versions.' >&2
  rm -rf '/Library/Application Support/Kshift' '/Library/Logs/Kshift'
else
  echo 'Service removed. Data, backups and logs were preserved.'
fi
