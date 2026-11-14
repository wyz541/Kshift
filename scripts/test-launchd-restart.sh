#!/bin/zsh
set -euo pipefail

uid="$(id -u)"
label="com.wyz541.kshift.restart-probe.$$"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/kshift-launchd-restart.XXXXXX")"
marker="$scratch/starts.txt"
plist="$scratch/$label.plist"
report="${KSHIFT_LAUNCHD_REPORT:-${TMPDIR:-/tmp}/kshift-launchd-restart-report-$(date +%Y%m%dT%H%M%SZ).json}"

cleanup() {
  launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
  rm -rf "$scratch"
}
trap cleanup EXIT

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>printf '%s\\n' start >> '$marker'; exec sleep 300</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>1</integer>
</dict>
</plist>
PLIST
plutil -lint "$plist" >/dev/null
launchctl bootstrap "gui/$uid" "$plist"

count_starts() {
  if [[ -f "$marker" ]]; then
    wc -l < "$marker" | tr -d ' '
  else
    echo 0
  fi
}

for _ in {1..30}; do
  [[ "$(count_starts)" -ge 1 ]] && break
  sleep 0.2
done
[[ "$(count_starts)" -ge 1 ]]
old_pid="$(launchctl print "gui/$uid/$label" | awk '/^[[:space:]]*pid = /{print $3; exit}')"
[[ -n "$old_pid" ]]

kill -TERM "$old_pid"
for _ in {1..50}; do
  [[ "$(count_starts)" -ge 2 ]] && break
  sleep 0.2
done
[[ "$(count_starts)" -ge 2 ]]
new_pid="$(launchctl print "gui/$uid/$label" | awk '/^[[:space:]]*pid = /{print $3; exit}')"
[[ -n "$new_pid" ]]
[[ "$new_pid" != "$old_pid" ]]

jq -n \
  --arg label "$label" \
  --arg old_pid "$old_pid" \
  --arg new_pid "$new_pid" \
  --argjson starts "$(count_starts)" \
  '{status: "passed", label: $label, starts: $starts, old_pid: $old_pid, new_pid: $new_pid}' > "$report"

printf 'launchd_report=%s\n' "$report"
