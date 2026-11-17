---
slug: /evidence/task-editor-popover
title: Task editor Popover 证据
type: report
status: active
updated: "2026-11-17"
keywords:
  - Task editor
  - Popover
  - macOS
  - iOS
  - SwiftUI
description: 记录 Issue #93 的 anchored task-edit Popover、取消行为和跨平台证据。
---

# Task editor Popover 证据

结论：Existing-task quick edit 已从 root Sheet 改为 shared SwiftUI anchored Popover。New-task Popover 和 task-detail Sheet 保持现有行为。

## 环境

| 项目 | 值 |
| --- | --- |
| 日期 | 2026-11-17 |
| macOS | 27.0.1 |
| Xcode | 27.2（27B52） |
| Swift | 6.4.2 |
| iOS Simulator | iPhone 18 Pro，iOS 27.0 |
| 数据 | Debug Demo data |

## 命令结果

| 检查 | 结果 |
| --- | --- |
| `swift build --target KshiftUI` | 通过 |
| `make swift-test` | 通过：50 core tests、5 adapter tests；2 live FFI tests skipped |
| `make mac-build` | 通过 |
| Focused iOS UI test：`testEditTaskUsesAnchoredPopover` | 通过 |
| Focused iOS UI test：`testTableRowEditUsesAnchoredPopover` | 通过 |
| `git diff --check` | 通过 |

## 自动化行为

- Task-card menu 的 `编辑` action 打开 `task-editor-popover`。
- Popover 包含 editable title field。
- Cancelled interaction 关闭 Popover。
- Task detail sheet 不打开。
- Table-row context-menu `编辑` action 使用同一 anchored Popover。
- New-task Popover 保持原路径。

## 截图

| 文件 | 平台 | 内容 | SHA-256 |
| --- | --- | --- | --- |
| `macos-edit-task-popover-2026-11-17.png` | macOS | Task-card menu 的编辑 Popover，dark mode | `748c32e29aa5218448b24524ddfd1b5a3dbb40b2e87a091643cb9170b641ceb0` |
| `ios-edit-task-popover-2026-11-17.png` | iOS Simulator | Task-card menu 的编辑 Popover，standard simulator layout | `bc1e602aba7a32cc2dc2578464c66716783a5aeef9d561b1165656f3f9a029e4` |

macOS 截图显示 Popover anchor 指向 task card。iOS 截图显示 Popover 标题、editable title field、取消和保存 actions。

## 未覆盖

- Table-row context menu 的 dedicated screenshot 未采集；focused UI test 已通过。
- macOS large-text 和 iOS large-text 的 independent visual pass 未采集。
- Task-detail Sheet 仍是完整编辑 surface；本 Task 不把 detail Sheet 改为 quick-edit Popover。
