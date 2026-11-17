# Kshift Agent Instructions

## Mandatory Workflow Authority

Before an Agent classifies work, creates an Issue, changes implementation, opens a PR, reviews a PR, or records acceptance, read these files in this order:

1. `docs/workflow.drawio`, page 3.
2. `docs/workflow.md`.
3. `docs/specs/governance.md`.
4. `CONTRIBUTING.md`.

`docs/workflow.drawio` page 3 is the authority for the project workflow. It defines stages, states, branches, return paths, roles, artifacts, and gates. `docs/workflow.md` is the required explanatory mirror. If the mirror and page 3 disagree, apply page 3 and update the mirror in the same change.

Canonical source:

- Source path: `D:\gitRep\ObsidianVault\Structure\工程实践\工作流\workflow.drawio`.
- Remote source: `https://github.com/wyz541/ObsidianVault/blob/master/Structure/工程实践/工作流/workflow.drawio`.
- Source commit: `d63af060ac0e53ff508e4436198205e919569743`.
- SHA-256: `9defce4eb388cf58089ee43e8da4791fd4169676d4c1fd0959bac1889d8f2055`.
- Runtime read path: `docs/workflow.drawio`.

The repository copy must remain byte-identical to the canonical source at the recorded commit. When the source is accessible, verify the digest before a workflow change. If the digest differs, stop and reconcile the source and repository copy before continuing. CI and Agents must read the repository copy because the local Windows path is not available on every host.

Do not infer permission to skip the workflow from a short user request. A short request still requires the full workflow preflight.

## Mandatory Preflight

1. Classify the input as Bug, Task, Feature, Research, or Acceptance.
2. If information is incomplete, use the `need-info` return path before implementation.
3. Create or identify the Issue before implementation. Do not implement first and backfill the Issue later.
4. Fill the Issue fields required by `CONTRIBUTING.md`: Spec, Decision Issue, Contract, Acceptance, and Evidence.
5. Update the affected Active Spec before product implementation when the workflow requires it.
6. Use one Issue per branch and one Issue per worktree. Record the worktree path and branch in the Issue.
7. Run the required local tests and record actual results. Never report an unrun check as passed.
8. Use the PR template. Include the required functional evidence and Before/After visual evidence for UI changes.
9. Treat merge as a stage, not completion. Complete CD Build, UX final acceptance, documentation capture, evidence migration, cleanup, and Issue closure according to the workflow.

## Issue and Project Rules

- Every open Issue has exactly one `type:` label and at least one `area:` label.
- Project `Status` is the state source. Use `Inbox`, `Triage`, `Ready`, `In Progress`, `In Review`, `Blocked`, or `Done`.
- Use native sub-issues for Feature decomposition and native dependencies for hard blockers.
- Worktree PRs use `Part of #N`. The Issue owner closes the Issue manually after evidence migration and cleanup.
- Do not use PR comments as the only location for delivery evidence.

## Conflict and Scope Rules

- `docs/workflow.drawio` page 3 overrides duplicated workflow text in this file, `docs/workflow.md`, or `KS-GOV`.
- `KS-GOV` supplies rules only where page 3 does not define the workflow behavior.
- Active Spec supplies product and engineering rules outside the workflow authority.
- Higher-level system and user instructions remain in force.
