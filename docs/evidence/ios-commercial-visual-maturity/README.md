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
