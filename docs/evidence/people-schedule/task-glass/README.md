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
- 优先级改为系统色 tint 和 3pt 语义色指示条。
- 标题和状态图标使用主要文本色和语义色。
- 状态选择器只在状态图标悬停或点击时打开。
- 同人员行的任务条共用一个 `GlassEffectContainer`。
- 增加 Reduce Transparency、Increase Contrast 和键盘焦点回退。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| `make swift-test` | 通过；42 项执行，2 项 live 测试跳过，0 项失败 |
| macOS Debug build | 通过 |
| iOS `testPeopleScheduleIsDefaultViewAndCoreControlsWork` | 通过 |
| Swift Package 编译 | 通过 |

## 候选截图

| 文件 | 内容 | SHA-256 |
| --- | --- | --- |
| `macos-task-bar-2026-11-14.png` | macOS Demo 人员排期任务条 | `8373311ca700571b280d5c7066d1dab3b4c464a9f88ac0ff978fe208b8ccccf9` |
| `ios-task-bar-2026-11-14.png` | iPhone 18 Pro Simulator 人员排期任务条 | `9b427fb831ed504b1121f82489d2d1c40e1f2a98440b1152436b4c6f2b9a23b2` |

## 未覆盖

- 用户视觉验收尚未完成。
- Dark Mode、Increase Contrast 和 Reduce Transparency 截图尚未生成。
- macOS 和 iOS 人工拖拽录屏尚未生成。

本文件中的 `通过` 只表示自动检查结果。用户视觉验收通过前，Issue #42 保持打开。
