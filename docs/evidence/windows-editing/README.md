---
slug: /evidence/windows-editing
title: Windows task editing evidence
type: report
status: review
updated: "2026-11-26"
owner: "@wyz541"
keywords:
  - Windows
  - task editor
  - conflict
  - gpui
  - FFI
description: 记录 Issue #136/#157 的 Windows typed task editing、conflict projection、fixture smoke、Windows CI save/conflict 自动证据和仍待执行的桌面截图。
---

# Windows task editing evidence

Issue: #136
Worktree: `~/repo/_worktrees/Kshift/issue-136-windows-task-editing`
Branch: `issue/136-windows-task-editing`
Date: 2026-11-24

## Scope

This evidence covers the typed FFI command boundary, Windows editor draft and
conflict projections, fixture read-only behavior, and the gpui editor smoke
path. Windows CI remains the authoritative Windows build/runtime evidence.

## Local deterministic checks

| Check | Command | Result |
| --- | --- | --- |
| FFI and Windows tests | `cargo test --locked -p kshift-windows -p kshift-ffi` | PASS: 9 FFI tests, 19 Windows tests |
| Windows library clippy | `cargo clippy --locked -p kshift-windows --all-targets -- -D warnings` | PASS |
| FFI clippy | `cargo clippy --locked -p kshift-ffi --all-targets -- -D warnings` | PASS |
| gpui formatting | `cargo fmt --check` in `crates/kshift-windows-gpui` | PASS |
| gpui check | `cargo check --all-targets` in `crates/kshift-windows-gpui` | PASS |
| gpui clippy | `cargo clippy --all-targets -- -D warnings` in `crates/kshift-windows-gpui` | PASS |
| R0 governance | `./scripts/check-r0.sh` | PASS |

The tests verify:

- bounded FFI host command JSON and parsing failures;
- expected project revision and expected task version projection;
- only editor-owned fields are set, so `starts_on`, `due_on`, tags, parent and
  dependency fields stay `Unset`;
- conflict errors retain `current_revision` and `entity_version`;
- typed success outcomes retain the new revision;
- UTF-8-safe text editing and assignee toggles.

## gpui smoke on the development host

The gpui client was built and launched from the fixture with the task editor
opened at startup:

```text
kshift-windows: snapshot loaded project=Launch Room tasks=8 editable=false
kshift-windows: editor opened at startup task=aaaaaaaa-0000-4000-8000-000000000001 editable=false
kshift-windows: window opened
kshift-windows: smoke window alive; exiting
```

This run used the macOS development host and therefore is not recorded as
Windows desktop evidence. The workflow now runs a second `windows-latest`
window smoke with `--open-task`.

## Windows CI

- Workflow: `.github/workflows/windows-client.yml`
- PR: #138
- Commit: `2f8bad2c06decefbc349d091edf56c4e587b62c6`
- Run: [45376500802](https://github.com/wyz541/Kshift/actions/runs/45376500802)
- Result: **PASS**
- Environment: `windows-latest`, stable Rust, `x86_64-pc-windows-msvc`

Actual log summaries:

```text
kshift-windows: 19 tests passed
kshift-ffi: 9 tests passed
```

Schedule window smoke:

```text
kshift-windows: snapshot loaded project=Launch Room tasks=8 editable=false
kshift-windows: window opened
kshift-windows: smoke window alive; exiting
```

Read-only editor window smoke:

```text
kshift-windows: snapshot loaded project=Launch Room tasks=8 editable=false
kshift-windows: editor opened at startup task=aaaaaaaa-0000-4000-8000-000000000001 editable=false
kshift-windows: window opened
kshift-windows: smoke window alive; exiting
```

The Windows workflow also passed `cargo clippy -p kshift-windows --all-targets
-- -D warnings`, gpui formatting, gpui clippy, and the release build.

## Windows CI save/conflict evidence

Issue: #157
Commit: `e13959aa4e85d8401c0ad5b90161d600f733aba5`
Run: [45773375694](https://github.com/wyz541/Kshift/actions/runs/45773375694)

The Windows workflow now starts a local TLS mock server, opens the gpui editor
against that server, edits the task, and checks two deterministic scenarios.
The mock server response and UI log remain in the workflow artifact
`windows-client-log`.

Successful save:

```text
kshift-windows: snapshot loaded project=Kshift smoke tasks=1 editable=true
kshift-windows: editor opened at startup task=aaaaaaaa-0000-4000-8000-000000000001 editable=true
kshift-windows: window opened
kshift-windows: save committed task=aaaaaaaa-0000-4000-8000-000000000001 revision=2 command=fbfbe02b-699a-426b-8ef7-5fd25447354a
kshift-windows: smoke window alive; exiting
```

Stale-version conflict:

```text
kshift-windows: snapshot loaded project=Kshift smoke tasks=1 editable=true
kshift-windows: editor opened at startup task=aaaaaaaa-0000-4000-8000-000000000001 editable=true
kshift-windows: window opened
kshift-windows: save conflict task=aaaaaaaa-0000-4000-8000-000000000001 current_revision=Some(2) current_entity_version=Some(2) draft_preserved=true
kshift-windows: smoke window alive; exiting
```

Automated interpretation:

- Click-to-open path is exercised by `--open-task` and logs `editor opened`.
- Save path uses the real FFI host command against a TLS gRPC mock server and
  commits revision 2.
- Stale version returns `conflict`, reports the latest revision/version, and
  keeps the editor draft.
- This is CI automation, not a substitute for human visual inspection.

## Windows visual evidence

- 1280x800 at 150% zoom: **NOT RUN**.
- Reason: no Windows interactive desktop is available in this session.
- The workflow save/conflict automation is not reported as visual evidence.
