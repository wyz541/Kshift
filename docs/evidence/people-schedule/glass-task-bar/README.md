---
slug: /evidence/people-schedule/glass-task-bar-2026-11-15
title: 人员排期原生染色 Liquid Glass 任务条证据（2026-11-15）
type: report
status: review
updated: "2026-11-15"
keywords:
  - 人员排期
  - 任务条
  - Liquid Glass
  - SwiftUI Button
  - 视觉验收
description: 记录人员排期任务条使用原生染色 Liquid Glass、明亮优先级颜色和紧凑胶囊布局的实现与验证证据。
---

# 人员排期原生染色 Liquid Glass 任务条证据（2026-11-15）

## 触发原因

用户要求任务条使用 SwiftUI Liquid Glass，不使用纯黑背景。Desktop 和 Mobile 必须用红、黄、蓝分别表达 P0、P1 和 P2。任务条必须扁平、紧凑、单行，并增加工作区可见任务数量。第二轮视觉反馈指出三个问题：任务条未统一左对齐、标题溢出胶囊、状态符号不清晰。

## 修复内容

- 任务条使用 SwiftUI `Button`、`.buttonStyle(.plain)` 和原生 `.glassEffect(.regular.tint(...).interactive(), in: Capsule(style: .continuous))`。
- 禁止把 `.buttonStyle(.glass)` 用作最终任务条。该样式在当前 Dark Mode 中呈现接近黑色的表面。
- Light Mode 使用优先级颜色作为 tint，opacity 为 `0.28`。
- Dark Mode 使用优先级颜色作为 tint，opacity 为 `0.45`。
- Desktop 任务条和 Mobile 任务条分别使用一个 `GlassEffectContainer` 分组相邻 glass effect。
- 任务条视觉高度为 36pt，完整交互区域为 44pt。
- 日期 slice 使用统一的 4pt 水平 inset，任务条与日期边界保持同一左基线。
- 标题使用任务条剩余宽度、tail truncation 和胶囊边界 clipping。标题不得绘制到胶囊外部。
- Desktop 使用人员×日期时间轴。Mobile 使用按人员分组的纵向列表。
- 桌面紧凑、标准和宽松密度的任务行间距分别为 40pt、48pt 和 56pt。
- 状态控件位于任务条前端。状态选择继续使用原生 `Menu`。
- 状态徽章使用 28pt 外框、3pt 优先级色环、白色中性内盘和 `13pt` heavy 符号。
- `todo` 使用 `circle.dashed`。`inProgress` 使用 `clock.fill`。`blocked` 使用 `exclamationmark.octagon.fill`。`done` 使用 `checkmark`。
- 状态菜单保持 44pt 触控区域。
- 优先级使用明亮色环和 task bar tint：P0 使用 `#D92D3A`，P1 使用 `#FFC400`，P2 使用 `#0066FF`，P3 使用 `#5F6368`。
- 禁止纯黑任务条背景、自绘玻璃、渐变、模糊和阴影。

## 视觉证据

截图使用固定日期 `2026-11-15` 和 Demo 数据。截图显示 P0、P1、P2 任务条在 Light Mode 和 Dark Mode 中保留优先级颜色、玻璃高光和单行紧凑布局。任务条左边缘对齐日期网格；单日标题完整显示或被 tail truncation 裁切；状态符号使用白芯高对比徽章。

| 文件 | 环境 | 内容 | SHA-256 |
| --- | --- | --- | --- |
| [`macos-task-bar-light-2026-11-15.png`](./macos-task-bar-light-2026-11-15.png) | macOS 27.0.1；Xcode 27.2；Light Mode | Desktop 人员×日期时间轴 | `186f67758ef370cd4e70a52882842c1a963a99e826e7966aa578accba8785aa5` |
| [`macos-task-bar-dark-2026-11-15.png`](./macos-task-bar-dark-2026-11-15.png) | macOS 27.0.1；Xcode 27.2；Dark Mode | Desktop 人员×日期时间轴 | `ef898b400b1e554509e6bde798624455f4346e83095f4c9bacafbd22eac5883f` |
| [`ios-task-bar-light-2026-11-15.png`](./ios-task-bar-light-2026-11-15.png) | iPhone 18 Pro Simulator；iOS 27.0；Light Mode | Mobile 人员分组列表 | `eb471da6fc77e6a0bc7cc4239192d84257073fe1e34ea16c0c31af017a468914` |
| [`ios-task-bar-dark-2026-11-15.png`](./ios-task-bar-dark-2026-11-15.png) | iPhone 18 Pro Simulator；iOS 27.0；Dark Mode | Mobile 人员分组列表 | `99ce479536261a4971fd6182a4ec2ec2095ee1adfb23b78000e0f47323c6766b` |

旧文件 `macos-task-bar-2026-11-14.png` 和 `ios-task-bar-2026-11-14.png` 是上一版 `.buttonStyle(.glass)` 候选。它们不表示最终视觉结论。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| `make swift-test` | 通过；43 项执行，2 项 live 测试跳过，0 项失败 |
| macOS Debug build | 通过 |
| iOS Debug build | 通过 |
| `testPeopleScheduleAccessibilityAudit` | 通过 |
| `testPeopleScheduleStatusControlOpensNativeMenu` | 通过 |
| `testPeopleScheduleIsDefaultViewAndCoreControlsWork` | 通过 |
| `testAccessibilityTextSizeKeepsCoreActionsAvailable` | 通过 |
| `testCoreActionsMeetMinimumTouchTargets` | 通过 |
| `./scripts/check-r0.sh` | 通过 |
| `make check-build-governance` | 通过 |
| Operations CI | 见 PR #68 checks |

SwiftUI 无障碍审计将 `未分配` 和 `无负责人 · 1 项任务` 报为 contrast diagnostic。截图显示这两个标签为高对比文字。测试只豁免这组无关联背景诊断。优先级徽章的人工对比度为 P0 `4.79:1`、P1 `13.15:1`、P2 `4.83:1`、P3 `6.05:1`。

## 未覆盖

- 用户视觉验收尚未完成。
- Increase Contrast 和 Reduce Transparency 截图尚未生成。
- macOS 和 iOS 人工拖拽录屏尚未生成。
- 50 人、30 日、每人 20 项任务的渲染性能尚未用 Instruments 测量。

本文件中的“通过”只表示自动检查结果。用户明确确认视觉验收通过前，Issue #42 保持打开。
