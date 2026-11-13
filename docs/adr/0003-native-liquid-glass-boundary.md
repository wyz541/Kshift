---
slug: /adr/0003-native-liquid-glass-boundary
title: ADR-0003 原生 Liquid Glass 边界
type: decision
status: active
version: "1.0"
updated: "2026-11-13"
keywords:
  - Liquid Glass
  - HIG
  - 无障碍
  - 性能
description: 固定 Kshift 使用原生 Liquid Glass 的交互边界和无障碍门禁。
---

# ADR-0003 原生 Liquid Glass 边界

> 结论：导航、操作表面和可交互任务卡片使用 Apple 原生 Liquid Glass。正文、密集表格和长文本编辑使用清晰内容底板。

## 1. 状态

`accepted`

## 2. 背景

Liquid Glass 是 Apple 的功能层材质。可交互卡片需要明确层级和操作反馈。

纯内容长期放在玻璃上会降低对比度和性能。自绘材质会偏离系统行为。

## 3. 决策

| 表面 | 决策 |
| --- | --- |
| 窗口、侧栏、导航、标签栏、工具栏 | 使用 SwiftUI 系统组件 |
| Sheet、Popover、菜单 | 使用系统原生材质 |
| 主要操作 | `.buttonStyle(.glassProminent)` |
| 次要和浮动操作 | `.buttonStyle(.glass)` 或 `.glassEffect(...)` |
| 可交互任务卡片 | `Glass.regular` 外表面，内容放在稳定底板 |
| 相邻玻璃卡片 | 共用一个 `GlassEffectContainer` |
| AppKit 专属区域 | `NSGlassEffectView` 和 SwiftUI wrapper |
| 正文、密集表格、长文本编辑 | 标准材质或清晰内容底板 |

禁止自绘模糊、折射、噪点、渐变和高光。禁止固定透明度和颜色来模拟系统玻璃。

同屏 effect 和 container 必须有性能上限。预算不足时保留导航和当前操作卡片。

## 4. 备选方案

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| 所有表面使用玻璃 | 视觉统一 | 对比差；性能风险 | 拒绝 |
| 完全不用玻璃 | 稳定 | 丢失系统交互语义 | 拒绝 |
| 按交互语义使用原生玻璃 | 层级清楚；遵循系统 | 需要视觉和性能验收 | 采用 |

## 5. 后果

- 每个页面需要普通、Reduce Transparency、Increase Contrast 和 Reduce Motion 证据。
- 需要 VoiceOver、键盘、触控目标和系统文字大小检查。
- 需要滚动、拖拽、Sheet 和窗口缩放性能读数。
- 卡片文字和控件需要独立内容底板。
- 玻璃不能作为状态唯一载体。

## 6. 验证

- 两端 P0 页面使用同一共享 SwiftUI 样式入口。
- 可交互卡片使用 `Glass.regular`。
- 同组卡片共用一个 `GlassEffectContainer`。
- 无障碍和性能门禁有运行证据。

## 7. 关联

- Spec: [6.3 Liquid Glass 边界](../spec/kshift-spec-v0.1.md#63-liquid-glass-边界)
- Decision: `DEC-005`
- Source: [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
