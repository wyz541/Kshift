---
slug: /evidence/ios-commercial-visual-maturity
title: iOS commercial visual maturity evidence
type: report
status: active
updated: "2026-11-19"
owner: "@wyz541"
keywords:
  - iOS
  - People Schedule
  - visual maturity
  - layout
  - accessibility
description: Records Before and After evidence for the compact iOS People Schedule date-control cleanup and the single-row toolbar with week strip.
---

# iOS commercial visual maturity evidence

## People Schedule date-control cleanup

The compact iOS People Schedule operation bar no longer displays the duplicate schedule date range. The global planner header keeps the selected date, and the schedule grid keeps its date columns. The operation bar keeps task and people counts plus navigation and utility controls.

| File | Environment | SHA-256 |
| --- | --- | --- |
| `people-schedule-before-date-cleanup-2026-11-18.png` | iPhone 18 Pro Simulator; Demo data; previous layout | `f8d358abf53ea3a7583797e08a5e463a7faf534355643ba1ad270bcf999fbdd1` |
| `people-schedule-after-date-cleanup-2026-11-18.png` | iPhone 18 Pro Simulator; Demo data; updated layout | `2eb73935ccb6a75d0a65c763b4c4aada4d95988dd2b8b4fb271c47bc363649ab` |

## Verification

- macOS Debug build: passed.
- iPhone 18 Pro Simulator focused tests: passed.
- `testPeopleScheduleIsDefaultViewAndCoreControlsWork`: passed.
- `testAccessibilityTextSizeKeepsCoreActionsAvailable`: passed.
- `testCoreActionsMeetMinimumTouchTargets`: passed.

## People Schedule single-row toolbar and week strip

The compact iOS People Schedule hides the empty navigation bar and uses one schedule toolbar row. The row keeps period navigation, sort and filter visible; period, refresh and layout settings move into the overflow menu. A week strip lists the weeks that have tasks, plus the current and selected weeks. Tapping a week chip shows that week. The task count moves into the content area and counts only tasks in the shown period.

| File | Environment | SHA-256 |
| --- | --- | --- |
| `people-schedule-after-date-cleanup-2026-11-18.png` | Before. iPhone 18 Pro Simulator; Demo data; layout on `main` after #106 | `2eb73935ccb6a75d0a65c763b4c4aada4d95988dd2b8b4fb271c47bc363649ab` |
| `people-schedule-after-week-strip-2026-11-19.png` | After. iPhone 18 Pro Simulator; iOS 27.0; portrait; Demo data; Large text; Light Mode | `7747ac036b35d3462016b8f8f0913835f5d107c4c783fc42c4c78fd56c37e739` |

### Verification

- macOS Debug build: passed.
- `swift test --filter PeopleScheduleTests`: passed, including `testWeekBucketsCountCrossWeekTasksAndKeepIncludedEmptyWeeks`.
- iPhone 18 Pro Simulator full iOS suite: 21 passed, 1 skipped (live E2E), 1 failed. The failure is `testAccessibilityAudit` on the Board task note `## 发布准备`; it fails identically on `main` before this change.
- `testPeopleScheduleIsDefaultViewAndCoreControlsWork`: passed.
- `testPeopleScheduleAccessibilityAudit`: passed.
- `testCoreActionsMeetMinimumTouchTargets`: passed.
- `testCompactLayoutHidesEmptyNavigationBarAndKeepsSearch`: passed.
- `testWeekStripChipSwitchesShownWeek`: passed.
- Manual acceptance on iPhone simulators: passed by `@wyz541` on 2026-11-19.

## Accessibility XXXL compact schedule reflow

The 2026-11-24 pass reproduced a blocking compact-width layout at Accessibility XXXL: schedule controls overlapped, the week strip extended past the viewport, and person/task content was clipped. The reflow keeps the schedule toolbar on one 44pt control row, gives each week chip a bounded width, anchors the selected week, reflows person identity and metrics, and gives compact task capsules a readable title/date stack.

| File | Environment | SHA-256 |
| --- | --- | --- |
| `axxxl-before-2026-11-24.png` | Before. iPhone 18 Pro Simulator; iOS 27.0; portrait; Accessibility XXXL; Demo data | `e0ef7549465d9f38d49f0d75ac17cce90e9be17896a1b38b0bc605e5f8c93f41` |
| `axxxl-after-toolbar-2026-11-24.png` | After. Same environment; toolbar and selected week chip | `c99074048a96a59b809558a087e54971da1231737b7797df7c1cfba6c2c65c56` |
| `axxxl-after-task-2026-11-24.png` | After. Same environment; scrolled task content | `e53d517a7305a266c46e2f26de266af6d6cfd921cebcdeb345f5306549c84975` |

### Verification

- `testAccessibilityTextSizeKeepsCoreActionsAvailable`: passed on iPhone 18 Pro Simulator at `UICTContentSizeCategoryAccessibilityXXXL`.
- The test verifies all six schedule toolbar controls are at least 44pt, inside the window, and non-overlapping.
- The test verifies the selected/current week chip is inside the window and the Mia person header stays inside the window.
- The test verifies a task bar is discoverable by vertical scrolling and stays inside the horizontal window.
- Full iOS suite: 25 tests passed, 2 live-only tests skipped, 0 failures.
- `make swift-test`: 66 tests passed, 3 live-only tests skipped, 0 failures.
- `./scripts/check-r0.sh`: passed.
