---
slug: /evidence/people-schedule/glass-task-bar-2026-11-15
title: 人员排期原生染色 Liquid Glass 任务条证据（2026-11-15）
type: report
status: review
updated: "2026-11-16"
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

用户要求任务条使用 SwiftUI Liquid Glass，不使用纯黑背景。Desktop 和 Mobile 必须用红、黄、蓝分别表达 P0、P1 和 P2。任务条必须扁平、紧凑、单行，并增加工作区可见任务数量。第二轮视觉反馈指出三个问题：任务条未统一左对齐、标题溢出胶囊、状态符号不清晰。后续视觉反馈指出 toolbar buttons 过高且 glass 颜色过深。Window primaryAction toolbar 也出现 multiple deep accent-tinted actions。后续视觉反馈指出 filter popover 的 internal content 使用过长 switch rows，不能快速 scan 和 batch select conditions，并指出 person header 的 role subtitle、task metrics 和 disclosure control 在窄人员列中碰撞。最新视觉反馈指出 task panel 的 internal custom titlebar 仍未发生可见的结构变化。

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
- Window primaryAction toolbar 使用 native toolbar group 提供的唯一 Liquid Glass surface。
- Filter、refresh 和 audit 使用 native borderless toolbar buttons。它们不得添加局部 `.glassEffect`。
- New Task 使用 native toolbar interaction 和 accent foreground。它不得添加局部 accent glass。
- Window toolbar 禁止 double glass、double border 和 custom 44pt hit frame。
- Window toolbar 只保留 one accent action。
- macOS work area 使用 `AppKitScrollWheelRouter`。Vertical wheel 驱动 vertical scroll view。Shift + wheel 驱动 horizontal timeline。
- Blank day cell click 使用 clicked person 和 clicked date 创建 local `TaskDraft`。
- Blank day cell click 打开 responsive `TaskEditorView` popover。Popover default size 为 560pt × 580pt。
- Toolbar、planner floating action、board column action、calendar action and macOS menu 的 new-task actions use the same anchored popover。Existing-task editing keeps the regular sheet。
- Sidebar planning-view selection uses typed selection and cannot overwrite the selected project ID。
- Regular PeopleSchedule 隐藏 duplicated global date navigation row。
- Single schedule toolbar 包含 date picker、period control、density、sort、filter 和 settings。
- Schedule filter action 打开 `FilterPopover`，不再占用 clear-selection slot。
- `FilterPopover` uses a `300pt × 580pt` fixed surface with fixed header and footer. The header shows active-condition count and reset action. The footer shows filtered-task count and a prominent `完成` action.
- Filter content uses compact multi-select chips. It does not use long vertical switch rows. Assignee chips use an adaptive two-column grid. Status and priority chips use four-column grids. Tag chips use an adaptive grid. Sort options use a two-column grid.
- Selected filter chips show a tint, outline, selected accessibility state and `已选择` accessibility value. Wide chips show a checkmark. Compact status and priority chips keep primary text color so bright P1 yellow and neutral todo tints do not produce low-contrast white text. Reset restores all filters and manual sort.
- The popover width avoids clipping at the right schedule-toolbar anchor. The popover height keeps all sort options visible above the fixed footer.
- Schedule sort menu 直接显示 `手动顺序`、`优先级`、`标题` 和 `最近更新`。菜单不得包含 nested `排序 >` submenu。
- Sidebar footer 使用 gear button，并打开 `KshiftAppSettingsView`。
- Settings surface 包含 schedule layout、system accessibility shortcut 和 about information。
- PeopleSchedule 不显示 legacy Plan Depth entry。
- Other planner modes 保留 Plan Depth entry。
- Plan Depth sheet 有 explicit Close button。Regular presentation 使用 `860pt × 700pt` minimum size。
- Task bars show a delayed hover preview panel。
- Hover preview contains task metadata and rendered Markdown details。
- Task details and task editor use one editable `800pt × 720pt` panel。
- Panel titlebar uses classic macOS window structure：`52pt` system-material bar, centered `13pt` title, leading red traffic-light close control and trailing neutral small `简约` / `详情` control。
- Close control uses a `28pt` macOS hit target。A `12pt` red disc remains visible at rest。The xmark appears only on pointer hover。
- Titlebar blank space uses `WindowDragGesture` on macOS。iOS compiles the same titlebar without the macOS-only drag gesture。
- A full-width `0.5pt` separator separates the titlebar from panel content。
- Panel backdrop uses translucent material with restrained accent context。
- Core fields use grouped native Liquid Glass surfaces inside `GlassEffectContainer`。Individual fields use flat fills。
- `简约` mode contains task name, Markdown workspace, priority/status strips, assignee/date/duration fields and tags。
- `详情` mode uses a large focused Markdown workspace。
- Markdown toolbar provides bold, italic, underline, strike, inline code, heading, lists, quote, link and image insert actions。
- Existing-task footer contains History, Copy, Delete, Cancel and Save。History opens a popover。
- Task editor uses one Markdown workspace。A `源码` / `预览` mode switch changes the workspace content。New tasks default to source mode；existing tasks with content default to preview mode。
- Markdown preview supports headings、lists、quotes、dividers and fenced code。
- Status and priority controls use equal-width columns。Tag editing uses removable chips and an inline input。
- Person header no longer renders task metrics as an overlay。
- Person header uses a name/disclosure row and a role/metrics row。The name and role tail-truncate before the metrics。
- Expanded person header always shows the task count。In-progress and P0 metrics appear only when their count is non-zero。
- Person header keeps separate text and metric bounds at the `168pt` minimum people-column width。

## 视觉证据

截图使用固定日期 `2026-11-15` 和 Demo 数据。截图显示 P0、P1、P2 任务条在 Light Mode 和 Dark Mode 中保留优先级颜色、玻璃高光和单行紧凑布局。任务条保留统一的日期间距，不贴边绘制；单日标题完整显示或被 tail truncation 裁切；状态符号使用白芯高对比徽章，完成状态为绿色。In-content toolbar buttons 使用紧凑 neutral glass。Window toolbar 使用一个 native Liquid Glass group；filter、refresh 和 audit 为 flat borderless icons；New Task 为 accent-blue plus。The schedule utility group shows sort、filter 和 settings。The filter action opens `FilterPopover`。The sort menu shows all four options directly at the first level and marks the current option。Regular PeopleSchedule uses one date and period navigation row。The sidebar gear button opens the application settings surface。PeopleSchedule no longer exposes the legacy Plan Depth entry。Task bars show rendered Markdown hover previews。Shift + wheel moved the month timeline horizontally。Blank day cell click opened and saved a responsive task popover。All New Task actions now use anchored popovers。The task detail titlebar now uses a visible red window-close light, a centered title, a neutral trailing mode control and a draggable chrome surface。The hover evidence shows the xmark that appears on the close control。The content uses a translucent Liquid Glass backdrop, grouped native glass surfaces, a fixed translucent footer and aligned priority/status strips。Accent color is limited to selected controls, Save and low-opacity context。The person-header evidence uses the `168pt` minimum width and shows separate role and metric bounds without overlap。The compact person header shows task count plus nonzero in-progress and P0 counts on the role line without overlap。

| 文件 | 环境 | 内容 | SHA-256 |
| --- | --- | --- | --- |
| [`macos-task-bar-light-2026-11-15.png`](./macos-task-bar-light-2026-11-15.png) | macOS 27.0.1；Xcode 27.2；Light Mode | Desktop 人员×日期时间轴 | `b635f517f5991b917e67119b2d1448ea46c8bec232a330d6d728a9bd970182d3` |
| [`macos-task-bar-dark-2026-11-15.png`](./macos-task-bar-dark-2026-11-15.png) | macOS 27.0.1；Xcode 27.2；Dark Mode | Desktop 人员×日期时间轴 | `4f9aa2754a4f5c5dccdf1760ce016acc32b820c8c0b29cf9bda79fcdf38c3a43` |
| [`ios-task-bar-light-2026-11-15.png`](./ios-task-bar-light-2026-11-15.png) | iPhone 18 Pro Simulator；iOS 27.0；Light Mode | Mobile 人员分组列表 | `78cedcbbf9ca3711e9bc549623202536f950db65374a6602a8c2140ab735a738` |
| [`ios-task-bar-dark-2026-11-15.png`](./ios-task-bar-dark-2026-11-15.png) | iPhone 18 Pro Simulator；iOS 27.0；Dark Mode | Mobile 人员分组列表 | `6f5623633bc8a8ef973a1770ec52b1a3e99abf6bf1785200b7c59c2be4145389` |
| [`ios-person-metrics-2026-11-16.png`](./ios-person-metrics-2026-11-16.png) | iPhone 18 Pro Simulator；iOS 27.0；Light Mode | Compact person header with task count、`1 进行中` and `1 P0` metrics | `6012a30bf5403731dd8574f759bfff3b9217707b0dda9766f8838293613dcffd` |
| [`macos-task-editor-popover-2026-11-15.png`](./macos-task-editor-popover-2026-11-15.png) | macOS 27.0.1；Light Mode | 560pt × 580pt toolbar New Task popover with one Markdown workspace | `80d1d80b9bed363dcca415cef891eeb63be8ee32eafe33960d3ec47d8a65311e` |
| [`macos-settings-2026-11-15.png`](./macos-settings-2026-11-15.png) | macOS 27.0.1；Light Mode | Sidebar settings button 和 `KshiftAppSettingsView` | `4933cff27082a3cf6be4579f7af5a14836727913453bea468c6a17ff57315271` |
| [`macos-task-hover-preview-2026-11-15.png`](./macos-task-hover-preview-2026-11-15.png) | macOS 27.0.1；Light Mode | Delayed task hover preview with rendered Markdown | `caeb728855c14eff128a24dc7fea4bb7f8c855d561a49c627fada63ff68bbc4a` |
| [`macos-markdown-editor-2026-11-15.png`](./macos-markdown-editor-2026-11-15.png) | macOS 27.0.1；Light Mode | Markdown preview mode inside the single task workspace | `ce4b5711e5d74fd9f406ca38c28f464a353901b6abc39e29bca71c754baca8b8` |
| [`macos-markdown-source-2026-11-15.png`](./macos-markdown-source-2026-11-15.png) | macOS 27.0.1；Light Mode | Markdown source mode with the same single task workspace | `34a983e69c73f904e9f05a24b564a5825d06d16b3d7887eddf79b3d73daab858` |
| [`macos-task-detail-liquid-glass-2026-11-16.png`](./macos-task-detail-liquid-glass-2026-11-16.png) | macOS 27.0.1；Light Mode | Liquid Glass task detail with summary, content, activity cards and glass toolbar actions | `6b3e480ebd323dbb7abd8ec1949d5e32ed15d0fa005806e7d9d4a97f37baf241` |
| [`macos-person-header-min-width-2026-11-16.png`](./macos-person-header-min-width-2026-11-16.png) | macOS 27.0.1；Light Mode；`168pt` people column；Compact density | Person header with separated name/disclosure and role/metrics rows | `f9af5d1b879a31b6d96fc5a0597a2c85f984793cd32364816296bff0313184b9` |
| [`macos-window-toolbar-native-glass-2026-11-16.png`](./macos-window-toolbar-native-glass-2026-11-16.png) | macOS 27.0.1；Light Mode | Native Liquid Glass toolbar group with flat actions and one accent New Task action | `0a22e7064f5cbe8330fd1687764883beccef27e7c598a6b39d693446bf1f1d62` |
| [`macos-schedule-filter-2026-11-16.png`](./macos-schedule-filter-2026-11-16.png) | macOS 27.0.1；Light Mode | Schedule utility group with sort, filter and settings actions | `1b9bb7a12ae80379b088cfe25f6e256f5d53972793c87eb8e3f3af3f8fe2c69d` |
| [`macos-filter-popover-compact-2026-11-16.png`](./macos-filter-popover-compact-2026-11-16.png) | macOS 27.0.1；Light Mode；`300pt × 580pt` popover | Compact chip-based filter content with fixed header, footer and complete sort grid | `24ee439cbf34132002e40a89b6205bddebb47ece312cad0fb09c0fe140ebf8e6` |
| [`macos-schedule-sort-menu-direct-2026-11-16.png`](./macos-schedule-sort-menu-direct-2026-11-16.png) | macOS 27.0.1；Light Mode | First-level sort menu with direct options and current-item checkmark | `6952cd5713431793677f2c2f0cf78893bf601b14d4b4357b9107d9aefa585325` |
| [`macos-task-panel-compact-2026-11-16.png`](./macos-task-panel-compact-2026-11-16.png) | macOS 27.0.1；Dark Mode | macOS-window titlebar with red close light and Liquid Glass task detail `简约` mode | `0d1b7516852c463f98a853502add059da50bd7f93e39fdbf4d1f32dc93031733` |
| [`macos-task-panel-detail-2026-11-16.png`](./macos-task-panel-detail-2026-11-16.png) | macOS 27.0.1；Dark Mode | macOS-window titlebar with red close light and Liquid Glass task detail `详情` mode | `cbbb4254d173de62387ca73acce12fa09225271721a7e5e4ddc3bee7ade22a03` |
| [`macos-task-panel-titlebar-hover-2026-11-16.png`](./macos-task-panel-titlebar-hover-2026-11-16.png) | macOS 27.0.1；Dark Mode；Pointer hover | Red close light with hover xmark and neutral trailing mode control | `2d1989917b44c9541dce97d8568c209627cc7ee34b8fca61254e8496543d87c5` |

旧文件 `macos-task-bar-2026-11-14.png` 和 `ios-task-bar-2026-11-14.png` 是上一版 `.buttonStyle(.glass)` 候选。`macos-task-detail-2026-11-15.png` 是 flat card candidate。它们不表示最终视觉结论。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| `make swift-test` | 通过；49 core tests + 5 adapter tests，2 项 live 测试跳过，0 项失败 |
| macOS Debug build | 通过 |
| Person-header manual visual check | 通过；`168pt` and `196pt` and `320pt` widths；compact density |
| Person-header density check | 通过；`168pt` width with compact and standard and comfortable density |
| Window-toolbar manual visual check | 通过；single native glass surface；flat filter/refresh/audit actions；accent New Task |
| Schedule-filter interaction check | 通过；filter icon opens `FilterPopover`；compact layout keeps one filter action |
| Filter-popover content visual check | 通过；`300pt × 580pt`；fixed header/footer；complete chip grids；no clipping or dead space |
| Schedule-sort menu check | 通过；first-level options；current-item checkmark updates after selection |
| Task-detail panel visual check | 通过；`简约` and `详情` modes；red close light；centered title；neutral mode control；header/body/footer remain visible |
| Task-titlebar hover check | 通过；the xmark appears on the red close light only while the pointer is over the control |
| Task-detail history check | 通过；history popover opens |
| iOS Debug build | 通过 |
| `testCreateTaskThroughSharedPlanner` | 通过 |
| `testTaskDetailPanelShowsReferenceModesAndActions` | 通过；titlebar existence；`52pt` height；centered title；close/mode control order |
| `testTaskMarkdownEditorWritesAndPreviewsBlocks` | 通过 |
| `testAccessibilityAudit` | 通过 |
| `testPeopleScheduleAccessibilityAudit` | 通过；compact person metrics use scoped Dynamic Type false-positive waivers |
| `testPeopleScheduleStatusControlOpensNativeMenu` | 通过 |
| `testPeopleScheduleIsDefaultViewAndCoreControlsWork` | 通过 |
| `testFilterPopoverUsesCompactChipSelection` | 通过；chip selection、selected state、reset and Done action |
| `testAccessibilityTextSizeKeepsCoreActionsAvailable` | 通过 |
| `testCoreActionsMeetMinimumTouchTargets` | 通过 |
| `testPlanDepthFlowAndAccessibilityAudit` | 通过；native toolbar Close 的 scoped contrast/Dynamic Type false positives |
| `./scripts/check-r0.sh` | 通过 |
| `make check-build-governance` | 通过 |
| Operations CI | 见 PR #68 checks |

SwiftUI 无障碍审计将 `今天`、`未分配` 和 `无负责人 · 1 项任务` 报为 glass background contrast diagnostic。审计还将 `编辑者 · 1 项任务` 以及 compact person metric labels such as `1 进行中` and `1 P0` 报为 dynamic type diagnostic。These labels use relative caption fonts, and the screenshot shows readable text。测试只豁免这些 scoped diagnostics。Status glyph 与 white inner disc 的人工对比度为 `todo` `8.67:1`、`inProgress` `6.57:1`、`blocked` `7.52:1`、`done` `5.42:1`。

## 未覆盖

- 用户视觉验收尚未完成。
- Increase Contrast 和 Reduce Transparency 截图尚未生成。
- macOS 和 iOS 人工拖拽录屏尚未生成。
- 50 人、30 日、每人 20 项任务的渲染性能尚未用 Instruments 测量。
- 2026-11-16 的 generic iOS `testAccessibilityAudit` rerun 仍报告 board card raw Markdown note 的 Dynamic Type clipped diagnostic。该 diagnostic 位于 `TaskCard` 文本，不在本次 Window toolbar 变更范围。本次 toolbar-focused accessibility checks 通过。

本文件中的“通过”只表示自动检查结果。用户明确确认视觉验收通过前，Issue #42 保持打开。
