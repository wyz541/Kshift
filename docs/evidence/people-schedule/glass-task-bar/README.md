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

用户要求任务条使用 SwiftUI Liquid Glass，不使用纯黑背景。Desktop 和 Mobile 必须用红、黄、蓝分别表达 P0、P1 和 P2。任务条必须扁平、紧凑、单行，并增加工作区可见任务数量。第二轮视觉反馈指出三个问题：任务条未统一左对齐、标题溢出胶囊、状态符号不清晰。后续视觉反馈指出 toolbar buttons 过高且 glass 颜色过深。Window primaryAction toolbar 也出现 multiple deep accent-tinted actions。

## 修复内容

- 任务条使用 SwiftUI `Button`、`.buttonStyle(.plain)` 和原生 `.glassEffect(.regular.tint(...).interactive(), in: Capsule(style: .continuous))`。
- 禁止把 `.buttonStyle(.glass)` 用作最终任务条。该样式在当前 Dark Mode 中呈现接近黑色的表面。
- Light Mode 使用优先级颜色作为 tint，opacity 为 `0.28`。
- Dark Mode 使用优先级颜色作为 tint，opacity 为 `0.45`。
- Desktop 任务条和 Mobile 任务条分别使用一个 `GlassEffectContainer` 分组相邻 glass effect。
- 任务条视觉高度为 36pt，完整交互区域为 44pt。
- 日期 slice 使用统一的 8pt 水平 inset。任务条保留日期间距，不贴边绘制。
- 标题使用任务条剩余宽度、tail truncation 和胶囊边界 clipping。标题不得绘制到胶囊外部。
- Desktop 使用人员×日期时间轴。Mobile 使用按人员分组的纵向列表。
- 桌面紧凑、标准和宽松密度的任务行间距分别为 40pt、48pt 和 56pt。
- 状态控件位于任务条前端。状态选择继续使用原生 `Menu`。
- 状态徽章使用 26pt 外框、3pt 状态语义色环、白色中性内盘和 `13pt` heavy 符号。
- `todo` 使用 `circle.dashed` 和灰色。
- `inProgress` 使用 `clock.fill` 和蓝色。
- `blocked` 使用 `exclamationmark.octagon.fill` 和红色。
- `done` 使用 `checkmark` 和绿色；accent 为 `#30D158`，glyph 为 `#0F7A3D`。
- 状态菜单保持 44pt 触控区域。
- 优先级继续由 task bar tint 表达：P0 使用 `#D92D3A`，P1 使用 `#FFC400`，P2 使用 `#0066FF`，P3 使用 `#5F6368`。
- 禁止纯黑任务条背景、自绘玻璃、渐变、模糊和阴影。
- Planner toolbar 和 PeopleSchedule toolbar 使用 `KshiftCompactGlassButtonStyle`。
- Toolbar buttons 使用 neutral `.glassEffect(.regular.interactive())` 和 primary content。
- Toolbar visual height 为 34pt。Outer hit target 为 44pt。
- Schedule toolbar 的 vertical padding 为 4pt，minimum height 为 52pt。
- Toolbar buttons 不使用 accent-tinted `.buttonStyle(.glass)`。
- Window primaryAction toolbar 对 filter、refresh 和 audit 使用 neutral `KshiftCompactGlassButtonStyle`。
- New Task 使用 `KshiftCompactAccentGlassButtonStyle`。Accent glass opacity 为 `0.18` in Light Mode and `0.30` in Dark Mode。
- Window toolbar 只保留 one accent action。
- macOS work area 使用 `AppKitScrollWheelRouter`。Vertical wheel 驱动 vertical scroll view。Shift + wheel 驱动 horizontal timeline。
- Blank day cell click 使用 clicked person 和 clicked date 创建 local `TaskDraft`。
- Blank day cell click 打开 responsive `TaskEditorView` popover。Popover default size 为 400pt × 560pt。
- Regular PeopleSchedule 隐藏 duplicated global date navigation row。
- Single schedule toolbar 包含 date picker、period control、density、sort、clear selection 和 settings。
- Sidebar footer 使用 gear button，并打开 `KshiftAppSettingsView`。
- Settings surface 包含 schedule layout、system accessibility shortcut 和 about information。
- PeopleSchedule 不显示 legacy Plan Depth entry。
- Other planner modes 保留 Plan Depth entry。
- Plan Depth sheet 有 explicit Close button。Regular presentation 使用 `860pt × 700pt` minimum size。

## 视觉证据

截图使用固定日期 `2026-11-15` 和 Demo 数据。截图显示 P0、P1、P2 任务条在 Light Mode 和 Dark Mode 中保留优先级颜色、玻璃高光和单行紧凑布局。任务条保留统一的日期间距，不贴边绘制；单日标题完整显示或被 tail truncation 裁切；状态符号使用白芯高对比徽章，完成状态为绿色。Toolbar buttons 使用紧凑 neutral glass，不再出现 high-height accent-tinted blocks。Window toolbar 只保留 New Task as one pale-accent primary action。Regular PeopleSchedule uses one date and period navigation row。The sidebar gear button opens the application settings surface。PeopleSchedule no longer exposes the legacy Plan Depth entry。Shift + wheel moved the month timeline horizontally。Blank day cell click opened and saved a responsive task popover。

| 文件 | 环境 | 内容 | SHA-256 |
| --- | --- | --- | --- |
| [`macos-task-bar-light-2026-11-15.png`](./macos-task-bar-light-2026-11-15.png) | macOS 27.0.1；Xcode 27.2；Light Mode | Desktop 人员×日期时间轴 | `b635f517f5991b917e67119b2d1448ea46c8bec232a330d6d728a9bd970182d3` |
| [`macos-task-bar-dark-2026-11-15.png`](./macos-task-bar-dark-2026-11-15.png) | macOS 27.0.1；Xcode 27.2；Dark Mode | Desktop 人员×日期时间轴 | `4f9aa2754a4f5c5dccdf1760ce016acc32b820c8c0b29cf9bda79fcdf38c3a43` |
| [`ios-task-bar-light-2026-11-15.png`](./ios-task-bar-light-2026-11-15.png) | iPhone 18 Pro Simulator；iOS 27.0；Light Mode | Mobile 人员分组列表 | `78cedcbbf9ca3711e9bc549623202536f950db65374a6602a8c2140ab735a738` |
| [`ios-task-bar-dark-2026-11-15.png`](./ios-task-bar-dark-2026-11-15.png) | iPhone 18 Pro Simulator；iOS 27.0；Dark Mode | Mobile 人员分组列表 | `6f5623633bc8a8ef973a1770ec52b1a3e99abf6bf1785200b7c59c2be4145389` |
| [`macos-task-editor-popover-2026-11-15.png`](./macos-task-editor-popover-2026-11-15.png) | macOS 27.0.1；Light Mode | Blank day cell click 和 responsive task editor popover | `e43b611faeb3c182886b459f46a8e0d52ea15ec92c53478a1d45328d67cabca9` |
| [`macos-settings-2026-11-15.png`](./macos-settings-2026-11-15.png) | macOS 27.0.1；Light Mode | Sidebar settings button 和 `KshiftAppSettingsView` | `4933cff27082a3cf6be4579f7af5a14836727913453bea468c6a17ff57315271` |

旧文件 `macos-task-bar-2026-11-14.png` 和 `ios-task-bar-2026-11-14.png` 是上一版 `.buttonStyle(.glass)` 候选。它们不表示最终视觉结论。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| `make swift-test` | 通过；44 core tests + 5 adapter tests，2 项 live 测试跳过，0 项失败 |
| macOS Debug build | 通过 |
| iOS Debug build | 通过 |
| `testCreateTaskThroughSharedPlanner` | 通过 |
| `testPeopleScheduleAccessibilityAudit` | 通过 |
| `testPeopleScheduleStatusControlOpensNativeMenu` | 通过 |
| `testPeopleScheduleIsDefaultViewAndCoreControlsWork` | 通过 |
| `testAccessibilityTextSizeKeepsCoreActionsAvailable` | 通过 |
| `testCoreActionsMeetMinimumTouchTargets` | 通过 |
| `testPlanDepthFlowAndAccessibilityAudit` | 通过；native toolbar Close 的 scoped contrast/Dynamic Type false positives |
| `./scripts/check-r0.sh` | 通过 |
| `make check-build-governance` | 通过 |
| Operations CI | 见 PR #68 checks |

SwiftUI 无障碍审计将 `今天`、`未分配` 和 `无负责人 · 1 项任务` 报为 glass background contrast diagnostic。审计还将 `编辑者 · 1 项任务` 报为 compact layout dynamic type diagnostic。截图显示这些 labels 为高对比文字。测试只豁免这些 scoped diagnostics。Status glyph 与 white inner disc 的人工对比度为 `todo` `8.67:1`、`inProgress` `6.57:1`、`blocked` `7.52:1`、`done` `5.42:1`。

## 未覆盖

- 用户视觉验收尚未完成。
- Increase Contrast 和 Reduce Transparency 截图尚未生成。
- macOS 和 iOS 人工拖拽录屏尚未生成。
- 50 人、30 日、每人 20 项任务的渲染性能尚未用 Instruments 测量。

本文件中的“通过”只表示自动检查结果。用户明确确认视觉验收通过前，Issue #42 保持打开。
