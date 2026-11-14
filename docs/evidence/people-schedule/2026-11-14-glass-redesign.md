---
slug: /evidence/people-schedule/2026-11-14-glass-redesign
title: 人员排期任务条 Liquid Glass 重设计
type: report
status: review
updated: "2026-11-14"
keywords:
  - People Schedule
  - Liquid Glass
  - SwiftUI
  - visual acceptance
description: 记录人员排期任务条的 Liquid Glass 重设计、平台截图、自动门禁和待完成的视觉验收。
---

# 人员排期任务条 Liquid Glass 重设计

结论：任务条改用原生 Liquid Glass 和优先级色调。自动门禁通过。Issue #42 所有者仍需完成视觉验收。

## 设计变更

- 任务条改为原生 `glassEffect` 胶囊。
- 优先级颜色使用半透明玻璃色调。
- 标题使用主文本颜色和 `callout` 半粗字重。
- Reduce Transparency 使用不透明 Material 和色调叠加。
- 状态按钮保留 44 pt 触控区域。
- 已完成任务使用更低的色调透明度。

## 截图

| 文件 | 平台 | 设置 |
| --- | --- | --- |
| `macos-glass-compact.png` | macOS 27.0.1 | 紧凑密度 |
| `macos-glass-standard.png` | macOS 27.0.1 | 标准密度 |
| `macos-glass-loose.png` | macOS 27.0.1 | 宽松密度 |
| `ios-glass-light.png` | iOS 27.0 Simulator | 亮色 |
| `ios-glass-dark.png` | iOS 27.0 Simulator | Dark Mode |
| `ios-glass-large-text.png` | iOS 27.0 Simulator | Accessibility XXXL |
| `ios-glass-reduce-transparency.png` | iOS 27.0 Simulator | Reduce Transparency |

## 自动门禁

| 检查 | 结果 |
| --- | --- |
| `make mac-build` | 通过 |
| `make ios-build` | 通过 |
| `make swift-test` | 通过；42 项执行，2 项 live-only 测试跳过 |
| `testPeopleScheduleAccessibilityAudit` | 通过 |
| `testPeopleScheduleIsDefaultViewAndCoreControlsWork` | 通过 |
| `testCoreActionsMeetMinimumTouchTargets` | 通过 |

## 视觉验收

| 项目 | 状态 |
| --- | --- |
| 自动截图 | 完成 |
| 自动门禁 | 通过 |
| 所有者视觉验收 | 待完成 |

Issue #42 只能在所有者明确回复“视觉验收通过”后关闭。
