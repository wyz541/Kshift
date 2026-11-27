---
slug: /evidence/task-reschedule
title: Task Reschedule Evidence
type: report
status: review
updated: "2026-11-27"
keywords:
  - Gantt
  - reschedule
  - delay
  - evidence
description: Evidence for task-level reschedule events, Gantt delay rendering, task detail, and iOS/macOS validation.
---

# Task Reschedule Evidence

Issue: [#162](https://github.com/wyz541/Kshift/issues/162)
Source Discussion: [#161](https://github.com/wyz541/Kshift/discussions/161)

## Scope

This evidence covers task-level schedule changes:

- The original committed schedule is retained.
- A later `due_on` creates an append-only reschedule event with its reason, actor, time, and revision.
- The Gantt row shows the baseline, current target, extension, original-due marker, and `延期 N 天` badge.
- Continuous same-row extensions do not add a redundant long connector.
- The task detail shows the current schedule, original schedule, cumulative delay, latest reason, and reschedule history.
- The reschedule editor saves the new dates and reason through the typed command.
- Subtask and parent-task cascade behavior is intentionally out of scope because subtask logic is not implemented.

The sample uses fixed demo dates. The delayed task is scheduled `2026-11-25` to `2026-11-28`; its retained original due date is `2026-11-26`, so the displayed cumulative delay is 2 natural days. Its reschedule event is marked as occurring after the old due date.

## Screenshots

| Evidence | Platform / state | File | SHA-256 |
| --- | --- | --- | --- |
| Before | Previous plan-depth Gantt, current schedule only | [`before-gantt.png`](./before-gantt.png) | `a7c3c42249d877bd50193c99966fa11606cdd77d05b5761e314baf1ea363fb25` |
| After | macOS 27.0.1；Light Mode；delayed row visible | [`macos-gantt-delay.png`](./macos-gantt-delay.png) | `c46ae2475dfbbd035e51212fd497797e2a96e56b07805f5a4c375b4769ae3540` |
| After | macOS 27.0.1；task detail | [`macos-delay-task-detail.png`](./macos-delay-task-detail.png) | `72b8a8d2653c4b0f979c5886e2200df52d1de03b1f659bcf2141b2f22dbfed6a` |
| After | iPhone 18 Pro Simulator；iOS 27.0；Gantt delayed row | [`ios-gantt-delay.png`](./ios-gantt-delay.png) | `dffe5cd7f230b4b951cded065bad8c77199178b18f40fa5962d350000bc0312e` |
| After | iPhone 18 Pro Simulator；task detail | [`ios-delay-task-detail.png`](./ios-delay-task-detail.png) | `36b048ecd1aef48bcba9b388601e4c7e73f39087ff8edc24703e5f807fc75a9f` |
| After | iPhone 18 Pro Simulator；reschedule editor | [`ios-reschedule-editor.png`](./ios-reschedule-editor.png) | `c9703c8229f484028c18bddce14d625ffb826106d6e5ba2292a4bb83a1ef6913` |

The iOS screenshots were exported from the final XCUITest result bundle after the test verified the delayed-row accessibility value contains `延期 2 天` and exercised the task-detail and reschedule-editor entry points.

## Verification

Results actually run on 2026-11-27:

| Check | Result |
| --- | --- |
| `cargo fmt --all -- --check` | Passed |
| `cargo clippy --workspace --all-targets -- -D warnings` | Passed |
| `cargo test --workspace` | Passed |
| `make postgres-test` | Passed; includes reschedule persistence and rollback |
| `cargo test -p kshift-server --test plan_depth_transport` with temporary PostgreSQL 18 | Passed; includes typed gRPC reschedule and revision flow |
| `make swift-test` | Passed; 70 `KshiftCoreTests` plus 6 adapter/boundary tests；3 live-environment tests skipped |
| `make mac-build` | Passed |
| `make ios-build` | Passed |
| `xcodebuild ... -only-testing:Kshift-iOS-PlannerUITests/KshiftPlanDepthUITests` | `** TEST SUCCEEDED **`；includes accessibility audit |
| Live FFI against an externally configured server | Not run in this task because `KSHIFT_ENDPOINT` and `KSHIFT_CA_PATH` were not provided |
| Dedicated Dark Mode screenshot | Not run for this task |

The Xcode build emitted linker warnings for the Rust static library built against a newer macOS SDK than the package deployment target. The build and tests succeeded; the warning is recorded here rather than reported as a clean warning-free build.
