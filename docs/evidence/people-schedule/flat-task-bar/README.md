---
slug: /evidence/people-schedule/flat-task-bar-2026-11-14
title: 人员排期纯色任务条证据（2026-11-14）
type: report
status: review
updated: "2026-11-14"
keywords:
  - 人员排期
  - 任务条
  - 纯色
  - 扁平化
  - 视觉验收
description: 记录人员排期任务条改为明亮纯色、扁平和单行紧凑样式的实现与验证证据。
---

# 人员排期纯色任务条证据（2026-11-14）

## 触发原因

用户要求继续优化 Desktop 和 Mobile 的信息密度。Desktop 需要更高效的工作区；Mobile 需要显示更多任务和完整标题。

## 修复内容

- 任务条使用 SwiftUI `Capsule(style: .continuous)` 椭圆形形状和纯色优先级背景。
- 不使用 Glass、渐变、模糊和阴影。
- Desktop 使用人员×日期时间轴。
- Mobile 使用按人员分组的纵向任务列表。
- Desktop 任务条视觉高度为 36pt，标题限制为一行。
- Mobile 任务条使用全宽胶囊行和完整标题。
- Mobile 任务条在右侧显示紧凑日期范围。
- 紧凑密度的任务行间距为 40pt。
- 标准密度的任务行间距为 48pt。
- 宽松密度的任务行间距为 56pt。
- 状态控件位于任务条前端，保留 44pt 触控区域。
- 状态选择继续使用原生 `Menu`。
- P0 使用 `#D92D3A` 红底白字。
- P1 使用 `#FFC400` 黄底黑字。
- P2 使用 `#0066FF` 蓝底白字。
- P3 使用 `#5F6368` 灰底白字。
- 任务条保留清晰边框，支持普通、悬停、键盘焦点和 Increase Contrast。
- 人员行高度使用紧凑密度间距，工作区可以显示更多任务。
- 人员排期模式隐藏重复的 SummaryStrip。
- Desktop 缩小标题和页边距。
- Mobile 缩小标题并移除摘要卡。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| `make swift-test` | 通过；42 项执行，2 项 live 测试跳过，0 项失败 |
| macOS Debug build | 通过 |
| iOS core controls、touch targets、large text、native status menu | 4 项通过 |
| iOS accessibility audit | 通过；豁免已知紧凑时间轴诊断 |
| `./scripts/check-r0.sh` | 通过 |
| `make check-build-governance` | 通过 |
| Operations CI | 见 PR #68 checks |

SwiftUI 无障碍审计返回一个没有关联元素的 contrast diagnostic。测试只豁免这个无关联诊断。任务文字和背景的手工对比度如下：P0 `4.79:1`，P1 `13.15:1`，P2 `4.83:1`，P3 `6.05:1`。

## 候选截图

| 文件 | 内容 | SHA-256 |
| --- | --- | --- |
| `macos-task-bar-2026-11-14.png` | macOS Dark Mode 人员排期时间轴 | `8c5bc32b2852a6f5da0cd296d0ed047c92a35a49f5d77849776daf8da5080b1f` |
| `ios-task-bar-2026-11-14.png` | iPhone 18 Pro Simulator Light Mode 人员分组任务列表 | `77b57cdd900a955b08348baf06f951248966323d4bef5c399f641b7eaa3cfbe3` |

## 未覆盖

- 用户视觉验收尚未完成。
- Increase Contrast 和 Reduce Transparency 截图尚未生成。
- macOS 和 iOS 人工拖拽录屏尚未生成。
- 50 人、30 日、每人 20 项任务的渲染性能尚未用 Instruments 测量。

本文件中的“通过”只表示自动检查结果。用户视觉验收通过前，Issue #42 保持打开。
