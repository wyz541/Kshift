#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mkdir -p "$TMPDIR/codex-kshift"
scratch="$(mktemp -d "$TMPDIR/codex-kshift/r4-r5-check.XXXXXX")"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$scratch"' EXIT

python3 scripts/check_docs.py
PYTHONPATH=ops python3 -m unittest discover -s ops/tests -p 'test_*.py' -v
node --test release/test/release.test.mjs

for script in deploy/*.sh release/platform/*.sh; do
  zsh -n "$script"
done

for template in ops/launchd/*.plist.template; do
  rendered="$scratch/$(basename "$template" .template)"
  sed \
    -e 's|__KSHIFT_HOME__|/Library/Application Support/Kshift|g' \
    -e 's|__KSHIFT_LOG_DIR__|/Library/Logs/Kshift|g' \
    -e 's|__KSHIFT_BACKUP_DIR__|/Library/Application Support/Kshift/backups|g' \
    -e 's|__KSHIFT_DATA_DIR__|/Library/Application Support/Kshift|g' \
    -e 's|__KSHIFT_SERVICE_USER__|_kshift|g' \
    -e 's|__KSHIFT_AGE_RECIPIENT_FILE__|/Library/Application Support/Kshift/etc/age-recipient.txt|g' \
    -e 's|__KSHIFT_SOURCE_COMMIT__|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|g' \
    -e 's|__KSHIFT_HEALTH_URL__|http://127.0.0.1:8080/healthz|g' \
    -e 's|__KSHIFT_MIN_FREE_GIB__|10|g' \
    "$template" > "$rendered"
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$rendered"
  fi
done

if command -v actionlint >/dev/null 2>&1; then
  actionlint .github/workflows/*.yml
else
  echo 'actionlint not installed; skipped workflow lint' >&2
fi

echo 'R4/R5 checks passed'
