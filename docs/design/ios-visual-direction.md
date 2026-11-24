---
slug: /design/ios-visual-direction
title: Kshift iOS 视觉方向
type: design
status: review
updated: "2026-11-24"
owner: "@wyz541"
keywords:
  - iOS
  - Visual Direction
  - Liquid Glass
  - Accessibility
  - People Schedule
  - States
description: 定义 Kshift iOS 主要规划界面的视觉层级、材质、状态表达和无障碍验收方向。
---

# Kshift iOS 视觉方向

> 结论：Kshift iOS 应呈现为“安静、紧凑、可行动的规划工作台”。内容层级优先于装饰，Liquid Glass 只承担交互与上下文分组，关键状态必须同时通过文字、形状和颜色表达。`KS-UI` 仍是唯一 Active Spec authority；本文只负责设计方向和验收映射。

## 1. 设计论点

Kshift 的 iOS 界面不是展示页，而是每天反复使用的规划工具。用户需要快速回答三个问题：

1. 我现在看的是哪个项目和时间范围？
2. 我的团队此刻在做什么，哪里受阻？
3. 下一步能采取什么操作，且不会误改或误删？

因此，视觉系统遵循“Plan first, chrome second”：

- 项目、日期、人员、任务和状态是主内容。
- 导航和操作是次级层级，但必须始终可达。
- 玻璃材质用于建立操作组和空间层次，不作为重复装饰。
- 紧凑屏通过重排、折叠和溢出菜单保持控制可达，不通过缩小触控目标硬塞内容。
- 商业级成熟度来自稳定的层级、完整的异常状态和可重复的无障碍证据，不来自更多效果。

## 2. 视觉原则

### 2.1 One screen, one primary action

每个界面只保留一个视觉最强的主操作。People Schedule 的主操作是新增任务；Board 的主操作是新增任务或当前列操作；Task editor 的主操作是保存；Filter Popover 的主操作是完成筛选。

次要操作使用 neutral surface 或系统 toolbar item。多个 accent glass 控件不得并排竞争。

### 2.2 Glass is a state, not wallpaper

Liquid Glass 只用于：

- 系统 Sheet、Popover、菜单和 toolbar group。
- 可交互的任务条、任务卡和同组浮动控件。
- 需要表达层级或选中状态的容器。

正文、表格、密集筛选内容和长文本编辑使用清晰内容底板。禁止：

- 为每个 field 单独叠加玻璃。
- 玻璃嵌套玻璃。
- 用透明度表达优先级或业务状态。
- 自绘模糊、渐变、高光或阴影模拟系统玻璃。

### 2.3 Reflow before compression

iPhone portrait 和 Accessibility XXXL 下优先：

1. 将次要操作收进 overflow。
2. 将横向 metrics 重排到名称下方。
3. 使用单行 week strip 和固定 toolbar。
4. 让内容滚动，而不是裁切。
5. 保持 44pt 最小外接触控目标。

禁止依赖横向滚动才能发现主要筛选、排序、刷新或设置动作。

### 2.4 Status is never color-only

优先级和状态必须同时使用：

- 稳定文字标签，例如 `P0`、`进行中`、`受阻`。
- 图形或形状差异，例如 icon、badge、outline、checkmark。
- 颜色作为增强，不作为唯一识别手段。

## 3. 视觉系统

### 3.1 Typography hierarchy

| Role | Compact iOS | Regular iOS | Weight | Usage |
| --- | --- | --- | --- | --- |
| Project title | 30–34pt | 34–40pt | Bold | 项目身份，保持单行或两行内 |
| Page date | 22–24pt | 28–30pt | Semibold | 当前工作日或期间 |
| Section title | 17–20pt | 22–24pt | Semibold | 人员、列、筛选组、编辑器分组 |
| Primary body | 16–17pt | 17pt | Regular | 任务标题、正文 |
| Task metadata | 12–13pt | 13–14pt | Medium | 日期、计数、角色、badge |
| Control label | 15–17pt | 15–17pt | Semibold | 主操作和 segmented control |
| Caption | 11–12pt | 12pt | Regular | 辅助说明、空状态提示 |

要求：

- 使用系统 Dynamic Type text style 或 `@ScaledMetric`。
- 任务条标题优先 tail truncate；完整标题通过详情或可访问值提供。
- Accessibility XXXL 下 persona header 的 role 和 metrics 必须重排到名称下方。
- 不通过固定字号和高密度布局阻止系统文字缩放。

### 3.2 Spacing scale

使用 `4 / 8 / 12 / 16 / 24 / 32pt` 六档：

| Token | Usage |
| --- | --- |
| 4pt | badge、chip 内部和紧邻 icon |
| 8pt | 同一控件组、任务条内文字与 icon |
| 12pt | 卡片内部、列表行上下间距 |
| 16pt | compact page margin、card gap |
| 24pt | regular page margin、section gap |
| 32pt | 大状态页和编辑区呼吸空间 |

规则：

- 默认 compact page margin 为 16pt。
- 相邻同级表面的外间距不得小于 12pt。
- 不使用不可解释的大块空白来制造“高级感”；空白必须服务信息分组或主操作。
- 工具栏、week strip 和人员表头使用固定高度与一致内边距。

### 3.3 Color roles

| Role | Direction | Notes |
| --- | --- | --- |
| App background | System background | 随 Light/Dark 自动切换 |
| Dense surface | System secondary background | Board columns、calendar grid、table rows |
| Elevated surface | System material or grouped background | Sheet、Popover body、task detail |
| Primary text | `.primary` | 保持最高信息权重 |
| Secondary text | `.secondary` | 项目日期、计数、辅助信息 |
| Tertiary text | `.tertiary` | 仅用于非关键信息 |
| Separator | System separator | Hairline；不得用过重边框切割每个元素 |
| Accent | App tint | 只用于选中、主操作和低透明度 ambient context |
| Success | System green | 必须配 checkmark 或文字 |
| Warning / in-progress | System blue | 必须配 icon 或文字 |
| Blocked / destructive | System red | 必须配 icon、文字或 destructive role |
| Priority P0 | Red | 必须显示 `P0` |
| Priority P1 | Amber | 必须显示 `P1`；禁止作为白字 solid fill |
| Priority P2 | Blue | 必须显示 `P2` |
| Priority P3 | Neutral | 必须显示 `P3` |

禁止用 brightness 或 glass opacity 映射业务状态。

### 3.4 Material、border、elevation

| Element | Material direction | Border / elevation |
| --- | --- | --- |
| Navigation / toolbar | Native system material | Hairline separator only |
| Grouped toolbar actions | One-level native glass group | No double border |
| People Schedule task bar | `Glass.regular.tint(...).interactive()` capsule | Status icon + tint；无自定义阴影 |
| Board task card | `Glass.regular` group | One outer border；content remains legible |
| Dense list/table | Solid secondary background | Hairline row separator |
| Task editor / detail | Single translucent surface | Group-level glass containers；flat fields inside |
| Filter Popover | System anchored surface | Fixed header/footer；chips independent but not nested glass |
| Empty/error state | Solid content panel | One outlined recovery card；no decorative glass |

Elevation 最多两级：

1. 页面内容底板。
2. 当前操作 surface、Popover、Sheet 或浮动主操作。

禁止用多重阴影制造多层 Z 轴。

### 3.5 Shape and target size

- 任务条使用 continuous capsule。
- 卡片和面板使用 `12–20pt` continuous corner radius。
- Chip 使用 capsule 或 `10–12pt` rounded rectangle，同一 Popover 内保持一致。
- 最小外接触控目标为 44pt；视觉高度可以更小。
- 图标按钮必须提供 accessibility label、hint 和 selected state。

## 4. Screen-level direction

### 4.1 Planner shell

- Project identity、日期与 view switch 构成第一层级。
- People Schedule 放在 view picker 首位。
- 当前 view 使用 tint、outline 或 selected fill，不只依赖字重。
- Toolbar 中的 filter、sort、refresh、settings 必须有稳定位置。
- Compact 下只有一个 schedule navigation row；不重复显示日期导航。

### 4.2 People Schedule

- 人员 header 保持为独立可扫描层级：头像、姓名、角色、任务数、in-progress 和 P0。
- Week strip 固定在 schedule toolbar 下方，只显示有任务的周，并始终包含本周和当前周。
- 任务条必须显示完整日期范围；左右截断只用 capsule 边缘提示，不裁掉日期文字。
- 同一人员泳道内任务条不得重叠；跨周任务必须在重叠周计数。
- 人员 header 和任务条使用统一垂直节奏；不出现 unexplained dead space。
- 未分配任务作为独立人员行，不与真实成员混合。

### 4.3 Board

- 列标题与计数在首屏可读。
- Task card 使用一个 glass 外层，内容区域保持高对比。
- Priority、status、assignee、date 和 selection 同时有非颜色提示。
- Empty column 使用紧凑说明和一个恢复/新增动作，不占用整屏。

### 4.4 Calendar

- Selected day、today 和 task density 使用三种不同视觉状态。
- Selected 使用 tint + outline；today 使用 label 或 marker；density 使用 shape/count。
- 网格不得因为 glass 高光降低日期可读性。
- Compact 下保持月份切换和当前日期可达。

### 4.5 Table

- 以 dense content surface 为主，不使用大面积 glass。
- Row hover/selected/focused 状态清晰但不过度强调。
- Column alignment 和 truncation 规则稳定。
- Destructive action 不在主行内直接暴露，必须经过菜单或确认。

### 4.6 Task editor and detail

- 使用单一 translucent backdrop。
- Task name、Markdown、priority/status、schedule metadata、tags 使用少量 group-level glass surfaces。
- Surface 内 field 使用 flat fill，禁止逐个 field glass。
- Fixed footer 保留 Cancel 和 Save；Save 是唯一 accent primary action。
- Conflict inline surface 位于编辑上下文中，提供重新加载或审查最新版本的明确动作。

### 4.7 Filter Popover

- Header 固定，显示 active-condition count 和 reset。
- Filter groups 使用 compact chips，而不是纵向 switch rows。
- Selected chip 同时显示 tint、outline、checkmark 和 accessibility selected state。
- Footer 固定，显示结果计数和 `完成`。
- Popover 不得 clipping、overlap、dead space 或 nested glass。

## 5. Interaction and state language

| State | Visual treatment | Recovery / accessibility |
| --- | --- | --- |
| Pressed | Scale 或 tint 的短促变化，不改变布局 | 保持原 label；Reduce Motion 下取消位移 |
| Selected | Tint + outline + checkmark/selected value | `accessibilityAddTraits(.isSelected)` |
| Focused | 系统 focus ring 或清晰 outline | 键盘和 Switch Control 可定位 |
| Disabled | Reduced opacity，但仍可读 | 使用 `.disabled(true)`，不得只改颜色 |
| Loading | Inline progress，不阻塞已完成内容 | 保留 cancel 或说明；避免全屏空白 spinner |
| Empty | 一句结果说明 + 一个主恢复动作 | 文本明确空的是哪个范围 |
| Error | Error panel，说明原因和下一步 | 保留原输入与重试入口 |
| Conflict | Inline warning surface，显示当前 revision/version 信息 | 提供重新加载、审查或取消，不静默覆盖 |
| Destructive | Red role + confirmation copy + explicit object name | 默认动作不放在最显眼位置 |
| Success | Brief confirmation 或状态更新 | 不依赖 toast 作为唯一结果 |

### 5.1 Motion

- 选择、Popover 和 editor mode switch 使用短促系统动画。
- Reduce Motion 下移除位移和缩放，保留即时状态变化。
- 不用持续 pulse、循环 glow 或装饰动画。
- 性能优先：同屏 glass effect 数量受 `KS-UI` 性能门禁约束。

## 6. Accessibility color and contrast

- 正文与背景至少满足 WCAG AA；关键小字和 status label 需要更高对比。
- Increase Contrast 下加强文字、outline 和 selected state；不依赖材料透明度。
- Reduce Transparency 下将 glass surface 替换为稳定 content background。
- Light/Dark 下保持相同语义，不复制一套平台专属视觉规则。
- Accessibility XXXL 下允许 reflow、scroll 和 multi-line，不允许裁切或移除主要动作。
- 所有 interactive element 必须有 accessibility label；compact icon-only control 还必须有 hint。
- 图表和 status 不能只通过色相区分。

## 7. #105 acceptance mapping

| #105 criterion | Evidence / deliverable | Current position |
| --- | --- | --- |
| Written visual direction | 本文 | 由 #129 交付，等待评审合并 |
| Primary hierarchy / no unexplained blank space | Current screenshots + #108 | 部分满足；Planner、Board、Calendar、Table 仍需统一复审 |
| Compact People Schedule actions | [People Schedule evidence](../evidence/ios-commercial-visual-maturity/README.md) | 已满足 #106/#108 范围 |
| Task expression without color-only meaning | People Schedule evidence + focused UI tests | 部分满足；Board/Calendar/Table 需要统一验收 |
| Editor / Filter surface language | [Task editor evidence](../evidence/task-editor-popover/README.md)、[People Schedule evidence](../evidence/people-schedule/README.md) | 主要交付已存在，等待最终一致性验收 |
| Loading / empty / error / conflict / destructive states | Source review + screenshots | 部分满足；需要补齐状态截图 |
| Light / Dark screenshots | [Accessibility evidence](../evidence/accessibility/README.md) | 已有基线；最终验收前需刷新当前提交 |
| Increase Contrast / Reduce Transparency / AXXXL | [Accessibility evidence](../evidence/accessibility/README.md) | 已有自动化基线；最终验收前需刷新当前提交 |
| Focused UI tests | iOS focused tests | 持续满足；Acceptance 需要汇总最终命令 |
| Manual UX acceptance | Acceptance #130 | 等待 `@wyz541` 签收 |

## 8. Known gaps and next work

1. 生成当前 `main` 的 Light/Dark、Increase Contrast、Reduce Transparency 和 Accessibility XXXL 截图，并替换旧基线。
2. 复审 Planner、Board、Calendar、Table 的首屏层级和 empty state。
3. 为 loading、error、conflict、destructive 状态补截图和 focused tests。
4. 对齐 Task editor、Filter Popover 和 People Schedule 的 surface 间距与 accent 使用。
5. 在 #130 中执行最终矩阵，并由 `@wyz541` 给出 commercial UX signoff。

## 9. Review gate

本文合并前必须满足：

- 不新增与 `KS-UI` 冲突的规则。
- 所有 gap 均保留为未完成项，不把部分证据写成通过。
- 设计方向能直接指导后续 iOS Task 和 #130 Acceptance。

合并后，后续实现 Task 必须：

- 链接本文和具体 `KS-UI` rule IDs。
- 在 PR 中提供 Before/After 截图。
- 记录 Light、Dark 和 accessibility 状态。
- 不通过放宽 accessibility 或裁切内容换取视觉密度。
