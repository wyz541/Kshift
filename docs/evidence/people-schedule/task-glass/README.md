---
slug: /evidence/people-schedule/task-glass-2026-11-14
title: 人员排期任务条视觉修复证据（2026-11-14）
type: report
status: review
updated: "2026-11-14"
keywords:
  - 人员排期
  - 任务条
  - Liquid Glass
  - SwiftUI
  - 视觉验收
description: 记录任务条视觉验收失败后的原生玻璃样式修复、构建结果和候选截图。
---

# 人员排期任务条视觉修复证据（2026-11-14）

## 触发原因

用户视觉验收不通过。原任务条使用不透明优先级色填充，不符合 SwiftUI 和 Liquid Glass 样式最佳实践。

## 修复内容

- 任务条改为 `Glass.regular.interactive()` 原生玻璃外表面。
- 玻璃内部增加稳定内容底板。标题和状态控件不再直接放在玻璃上。
- 优先级改为系统色 tint 和 3pt 语义色指示条。
- 单日任务使用两行标题和紧凑状态图标。
- 宽任务显示高对比优先级徽章。
- 状态控件移到任务条前端，释放标题空间。
- 状态选择使用原生 `Menu`。悬停不会自动打开菜单。
- 同人员行的任务条共用一个 `GlassEffectContainer`。
- 增加 Reduce Transparency、Increase Contrast 和键盘焦点回退。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| `make swift-test` | 通过；42 项执行，2 项 live 测试跳过，0 项失败 |
| macOS Debug build | 通过 |
| iOS core controls、touch targets、large text | 3 项测试通过 |
| iOS `testPeopleScheduleAccessibilityAudit` | 通过 |
| iOS `testPeopleScheduleStatusControlOpensNativeMenu` | 通过 |
| Operations CI | 通过 |

## 候选截图

| 文件 | 内容 | SHA-256 |
| --- | --- | --- |
| `macos-task-bar-2026-11-14.png` | macOS Dark Mode Demo 人员排期任务条 | `14851faa86e272d02f15399deb990528719e750605f681ba8145c52c2c032989` |
| `ios-task-bar-2026-11-14.png` | iPhone 18 Pro Simulator Light Mode 人员排期任务条 | `f170fefb5d7ba586ae6d929eb141363d3b4a2fe58c262253a27b2b93690a5aa7` |

## 未覆盖

- 用户视觉验收尚未完成。
- Increase Contrast 和 Reduce Transparency 截图尚未生成。
- macOS 和 iOS 人工拖拽录屏尚未生成。

本文件中的 `通过` 只表示自动检查结果。用户视觉验收通过前，Issue #42 保持打开。
