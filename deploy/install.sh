#!/bin/zsh
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: sudo deploy/install.sh --bundle DIR --service-user USER --env-file FILE --version VERSION --source-commit SHA --age-recipient-file FILE [--minimum-free-gib N] [--allow-unencrypted-backup]'
}

script_dir="$(cd "$(dirname "$0")" && pwd)"

bundle=''
service_user=''
env_file=''
version=''
source_commit=''
age_recipient_file=''
allow_unencrypted_backup='no'
minimum_free_gib='10'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) bundle="$2"; shift 2 ;;
    --service-user) service_user="$2"; shift 2 ;;
    --env-file) env_file="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    --source-commit) source_commit="$2"; shift 2 ;;
    --age-recipient-file) age_recipient_file="$2"; shift 2 ;;
    --minimum-free-gib) minimum_free_gib="$2"; shift 2 ;;
    --allow-unencrypted-backup) allow_unencrypted_backup='yes'; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo 'install.sh must run as root' >&2
  exit 2
fi
if [[ -z "$bundle" || -z "$service_user" || -z "$env_file" || -z "$version" || -z "$source_commit" ]]; then
  usage >&2
  exit 2
fi
if [[ ! "$source_commit" =~ '^[0-9a-f]{40}$' ]]; then
  echo 'source commit must be 40 lowercase hexadecimal characters' >&2
  exit 2
fi
if ! id "$service_user" >/dev/null 2>&1; then
  echo "service user does not exist: $service_user" >&2
  exit 2
fi
if [[ ! -x "$bundle/bin/kshift-server" || ! -x "$bundle/bin/kshift-ops" || ! -x "$bundle/bin/kshift-server-run" || ! -x "$bundle/bin/kshift-ops-run" ]]; then
  echo 'bundle must contain executable bin/kshift-server, bin/kshift-ops, bin/kshift-server-run and bin/kshift-ops-run' >&2
  exit 2
fi
if [[ ! -f "$env_file" ]]; then
  echo "environment file is missing: $env_file" >&2
  exit 2
fi
if (( $(stat -f '%Lp' "$env_file") & 077 )); then
  echo 'environment file must not be readable by group or other users' >&2
  exit 2
fi
if [[ -n "$age_recipient_file" && ! -f "$age_recipient_file" ]]; then
  echo "age recipient file is missing: $age_recipient_file" >&2
  exit 2
fi
if [[ "$allow_unencrypted_backup" == 'no' && -z "$age_recipient_file" ]]; then
  echo 'stable installation requires --age-recipient-file' >&2
  exit 2
fi

home='/Library/Application Support/Kshift'
log_dir='/Library/Logs/Kshift'
backup_dir="$home/backups"
target="$home/versions/$version"
log_label='com.wyz541.kshift'
plist_root='/Library/LaunchDaemons'

if [[ -e "$target" ]]; then
  echo "version already installed: $version" >&2
  exit 2
fi

install -d -o "$service_user" -g staff -m 0750 "$home" "$backup_dir" "$log_dir"
install -d -o root -g wheel -m 0755 "$home/versions" "$home/etc" "$plist_root"
install -d -o "$service_user" -g staff -m 0750 "$target"
rsync -a "$bundle/" "$target/"
chown -R "${service_user}:staff" "$target"
install -o root -g staff -m 0640 "$env_file" "$home/etc/kshift.env"
if [[ -n "$age_recipient_file" ]]; then
  install -o root -g staff -m 0640 "$age_recipient_file" "$home/etc/age-recipient.txt"
  age_recipient="$home/etc/age-recipient.txt"
else
  age_recipient="$home/etc/age-recipient.txt"
fi

rm -f "$home/current.next"
ln -s "versions/$version" "$home/current.next"
mv -f "$home/current.next" "$home/current"

render_plist() {
  local source="$1"
  local destination="$2"
  sed \
    -e "s|__KSHIFT_HOME__|$home|g" \
    -e "s|__KSHIFT_LOG_DIR__|$log_dir|g" \
    -e "s|__KSHIFT_BACKUP_DIR__|$backup_dir|g" \
    -e "s|__KSHIFT_DATA_DIR__|$home|g" \
    -e "s|__KSHIFT_SERVICE_USER__|$service_user|g" \
    -e "s|__KSHIFT_AGE_RECIPIENT_FILE__|$age_recipient|g" \
    -e "s|__KSHIFT_SOURCE_COMMIT__|$source_commit|g" \
    -e "s|__KSHIFT_MIN_FREE_GIB__|$minimum_free_gib|g" \
    "$source" > "$destination"
  chmod 0644 "$destination"
}

for template in "$script_dir/../ops/launchd/"*.plist.template; do
  filename="$(basename "$template" .template)"
  destination="$plist_root/$filename"
  render_plist "$template" "$destination"
  plutil -lint "$destination" >/dev/null
done

install -d -o root -g wheel -m 0755 '/etc/newsyslog.d'
install -o root -g wheel -m 0644 "$script_dir/../ops/newsyslog/com.wyz541.kshift.conf" /etc/newsyslog.d/com.wyz541.kshift.conf
newsyslog -N >/dev/null 2>&1 || true

for label in "$log_label.server" "$log_label.backup-4h" "$log_label.backup-weekly" "$log_label.backup-monthly" "$log_label.health"; do
  plist="$plist_root/$label.plist"
  launchctl bootout system "$plist" >/dev/null 2>&1 || true
  launchctl bootstrap system "$plist"
done

sleep 2
set -a
source "$home/etc/kshift.env"
set +a
"$home/current/bin/kshift-ops" health --server-bin "$home/current/bin/kshift-server" --database-url-env KSHIFT_DATABASE_URL --disk-path "$home" --minimum-free-gib "$minimum_free_gib"
