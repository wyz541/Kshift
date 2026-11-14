---
slug: /evidence/people-schedule
title: 人员排期证据
type: reference
status: active
updated: "2026-11-14"
keywords:
  - 人员排期
  - SwiftUI
  - 泳道
  - 视图偏好
  - 证据
description: 列出 Issue #42 人员排期实现的规则入口、测试、截图和证据文件。
---

# 人员排期证据

本目录保存 Issue #42 的人员排期实现和验证证据。

## 权威入口

- Active Spec：[`KS-UI`](../../specs/ui.md)
- 领域规则：[`KS-DOMAIN`](../../specs/domain.md)
- 实现入口：`Sources/KshiftUI/PeopleSchedule/PeopleScheduleView.swift`
- 布局算法：`Sources/KshiftUI/PeopleSchedule/PeopleScheduleLayout.swift`
- 单元测试：`Tests/KshiftCoreTests/PeopleScheduleTests.swift`
- iOS UI 测试：`Apps/KshiftIOSUITests/KshiftIOSUITests.swift`

## 证据文件

| 文件 | 内容 |
| --- | --- |
| `2026-11-14-local.md` | 本机命令、结果、截图和未运行项 |
| `macos-people-schedule-final.png` | macOS 人员排期主界面和跨日任务 |
| `ios-people-schedule-final.png` | iOS Simulator 人员排期主界面和跨日任务 |
| `glass-task-bar/README.md` | Desktop 时间轴和 Mobile 人员分组列表的 Liquid Glass 任务条证据 |

## 结论规则

- 未运行项必须写为“未运行”。
- 截图必须来自本 Issue 的实现提交或后续兼容提交。
- 人工拖拽、路标定位和重启恢复未录屏时，不得写成已通过。
