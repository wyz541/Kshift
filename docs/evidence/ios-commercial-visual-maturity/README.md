---
slug: /evidence/ios-commercial-visual-maturity
title: iOS commercial visual maturity evidence
type: report
status: active
updated: "2026-11-18"
owner: "@wyz541"
keywords:
  - iOS
  - People Schedule
  - visual maturity
  - layout
  - accessibility
description: Records Before and After evidence for the compact iOS People Schedule date-control cleanup.
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
