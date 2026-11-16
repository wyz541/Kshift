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

> 结论：The workflow source and text mirror are checked in. The rendered image matches the `WF-01` to `WF-08` flow.

## Files

| File | Purpose | SHA-256 |
| --- | --- | --- |
| [`docs/workflow.drawio`](../../workflow.drawio) | Editable visual source | `N/A` |
| [`docs/workflow.md`](../../workflow.md) | Text mirror | `N/A` |
| [`project-workflow.png`](project-workflow.png) | Rendered visual check | `8d66fffdfd978cba3b49614a068e46c9720de757b7e2f7f4941f532daaef3fb6` |

## Checks

| Check | Result |
| --- | --- |
| `python3 scripts/check_docs.py` | Passed: 64 Markdown files, 4 JSON files, 61 unique slugs |
| Draw.io XML parse and edge target check | Passed: 36 cells and 13 edges |
| Rendered visual inspection | Passed: all eight workflow IDs are visible and connected |
| Absolute local path scan | Passed: no source-workstation path is committed |

## Source Note

The implementation session could not read the source workstation path. This version is a repository-native reconstruction from `KS-GOV`, `CONTRIBUTING.md` and the existing delivery flow. Replace the drawio file in a later PR only after the original source is available.
