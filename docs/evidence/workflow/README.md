---
slug: /evidence/workflow
title: Project Workflow Evidence
type: report
status: active
updated: "2026-11-16"
keywords:
  - workflow
  - drawio
  - evidence
description: Records the rendered project workflow, source files and verification result.
---

# Project Workflow Evidence

> 结论：The exact project workflow source is imported. Page 3 is the normative baseline, and the rendered image matches that page.

## Files

| File | Purpose | SHA-256 |
| --- | --- | --- |
| [`docs/workflow.drawio`](../../workflow.drawio) | Normative editable source | `9defce4eb388cf58089ee43e8da4791fd4169676d4c1fd0959bac1889d8f2055` |
| [`docs/workflow.md`](../../workflow.md) | Text mirror | `N/A` |
| [`project-workflow.png`](project-workflow.png) | Rendered visual check of page 3 | `3faca4e1c03216ca385dd4ba6d5d568b48cd0a164b0c15f2e089ca7c4618af4c` |

## Checks

| Check | Result |
| --- | --- |
| `python3 scripts/check_docs.py` | Passed: 66 Markdown files, 4 JSON files, 63 unique slugs |
| Draw.io XML parse and edge target check | Passed: 3 pages with unique cell IDs and valid edge targets |
| Rendered visual inspection | Passed: page 3 shows the five-stage workflow and its return paths |
| Absolute local path scan | Passed: no source-workstation path is committed |

## Source Note

The imported file matches ObsidianVault commit `d63af060ac0e53ff508e4436198205e919569743`. The repository copy is the project authority. The source workstation path is only provenance and is not a runtime dependency.
