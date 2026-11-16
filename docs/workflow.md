---
slug: /workflow
title: Kshift Project Workflow
type: reference
status: active
updated: "2026-11-16"
keywords:
  - workflow
  - Issue
  - PR
  - Worktree
  - governance
description: Maps the Kshift Issue, decision, delivery, review, merge, cleanup and close workflow.
---

# Kshift Project Workflow

> 结论：The editable visual source is [workflow.drawio](workflow.drawio). This page is its text mirror. [KS-GOV](specs/governance.md) remains the normative rule source.

## Purpose

Use this workflow to select the next project action. Use the draw.io file to inspect the route. Use KS-GOV to resolve rule conflicts.

## Workflow Steps

| ID | Step | Owner | Trigger | Output | Completion check |
| --- | --- | --- | --- | --- | --- |
| `WF-01` | Intake | Issue owner | A problem or delivery request exists. | A Discussion or Issue with type, area, target, scope and evidence plan. | The Issue has one `type:` label, one or more `area:` labels and a Project item. |
| `WF-02` | Decide | Decision owner | The Issue is ready for a decision. | A decision record with options, evidence, impact and rollback. | The decision owner confirms the selected result. |
| `WF-03` | Prepare | Implementer | The decision requires a repository change. | An updated Active Spec or a recorded `N/A`, plus a Worktree and branch for Task or Bug work. | The branch starts from `origin/main`, and the Worktree path is registered. |
| `WF-04` | Deliver | Implementer | The branch is ready for work. | Code, documentation, tests and evidence. | The required checks run, and each unrun check has a reason. |
| `WF-05` | Review | Reviewer | The PR is open. | Review findings and updated evidence. | Trace, change summary, evidence, document impact, risk and rollback are complete. |
| `WF-06` | Merge | Reviewer or maintainer | The review passes. | A merged PR. | The PR is merged to `main`, and no required review item remains open. |
| `WF-07` | Cleanup | Implementer | A Worktree delivery is merged. | An evidence migration record and a cleanup record. | The Worktree audit passes, and an explicit approval covers the fixed Worktree path and branch. |
| `WF-08` | Close | Issue owner | Cleanup is complete, or the delivery did not use a Worktree. | The final Issue acceptance record. | The acceptance items have evidence, and the owner closes the Issue manually or the PR closes it automatically. |

## Worktree Branch

Use `WF-07` only for Task and Bug work. Feature, Research and Acceptance work do not require an implementation Worktree.

```text
(Merge)
   │
   ▼
<Worktree delivery?>
   ├─ yes ─▶ [Cleanup] ─▶ [Close]
   └─ no ──▶ [Close]
```

## Sync Rule

Change `docs/workflow.drawio` and `docs/workflow.md` in the same PR. Do not use either file to override KS-GOV.

## Evidence

- [Rendered workflow](evidence/workflow/project-workflow.png)
- [Workflow evidence record](evidence/workflow/README.md)
