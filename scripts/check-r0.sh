#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 scripts/check_docs.py
python3 scripts/test_audit_issue_relations.py
python3 scripts/test_audit_worktrees.py
python3 scripts/check_spec_governance.py

if command -v buf >/dev/null 2>&1; then
  buf lint
else
  npx --yes @bufbuild/buf lint
fi

npx --yes --package ajv-cli@5 --package ajv-formats@3 \
  ajv validate --spec=draft2019 --strict=false -c ajv-formats \
  -s schemas/release-manifest.schema.json \
  -d schemas/examples/release-manifest.example.json

npx --yes --package ajv-cli@5 --package ajv-formats@3 \
  ajv validate --spec=draft2019 --strict=false -c ajv-formats \
  -s schemas/release-fragment.schema.json \
  -r schemas/release-manifest.schema.json \
  -d schemas/examples/release-fragment.example.json

if [[ -n "${MERMAID_EXTRACTOR:-}" && -f "${MERMAID_EXTRACTOR}" ]]; then
  find . -name '*.md' -not -path './.git/*' -print0 |
    while IFS= read -r -d '' file; do
      if grep -q '^```mermaid$' "$file"; then
        python3 "$MERMAID_EXTRACTOR" "$file" --diagram all >/dev/null
        printf 'mermaid: %s ok\n' "$file"
      fi
    done
else
  printf 'mermaid: skipped; set MERMAID_EXTRACTOR to enable parsing\n'
fi

printf 'R0 checks passed\n'
