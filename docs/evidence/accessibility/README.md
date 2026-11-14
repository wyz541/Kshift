---
slug: /evidence/accessibility
title: iOS 无障碍证据
type: report
status: review
updated: "2026-11-13"
keywords:
  - iOS
  - 无障碍
  - Dynamic Type
  - 对比度
  - 截图
description: 记录 iOS 无障碍截图、SHA-256 和自动审计结果。
---

# iOS 无障碍证据

结论：6 张 iOS 截图已采集。Reduce Transparency 使用应用环境覆盖，不是系统设置开关。

## 环境

| 项目 | 值 |
| --- | --- |
| 日期 | 2026-11-13 |
| 设备 | iPhone 18 Pro Simulator |
| 系统 | iOS 27.0（24A434） |
| Xcode | 27.2（27B52） |
| 数据 | `KSHIFT_DEMO_MODE=1` |

## 截图

| 文件 | 设置 | 用途 |
| --- | --- | --- |
| `ios-light.png` | Light | 基准 |
| `ios-dark.png` | Dark | 深色外观 |
| `ios-increase-contrast.png` | Increase Contrast | 边框和对比检查 |
| `ios-large-text.png` | Accessibility Extra Extra Extra Large | 大号文字布局 |
| `ios-reduce-motion.png` | Reduce Motion | 动画降级状态 |
| `ios-reduce-transparency.png` | `KSHIFT_FORCE_REDUCE_TRANSPARENCY=1` | 不透明卡片和列底 |

`simctl ui` 不提供 Reduce Transparency 开关。脚本使用应用环境变量覆盖 SwiftUI 环境，并强制渲染不透明路径。

## SHA-256

| 文件 | SHA-256 |
| --- | --- |
| `ios-light.png` | `8a0a88432fad4129c2af5291aec2f812bf00fcbed02f9dbd0692bd102c025aa3` |
| `ios-dark.png` | `34ff1fece3beadc3950997770eea7bedb612c6730d3a206eb89e1a68c867991c` |
| `ios-increase-contrast.png` | `484fa08ed3813495abbf51b40beca471d814aa78e9fc2ffdcf50612a82c7c9e1` |
| `ios-large-text.png` | `fbee5bf12422dc318b8df0830fa4826f752e2b041f3376d83464abd869b24cd4` |
| `ios-reduce-motion.png` | `ef64ca77e2c14d0aa638734ebc8abec6fa78be926e5a8a73191f1dd934cce6ad` |
| `ios-reduce-transparency.png` | `d40c40bbd0ac275e266fe7ffe8f49acadad2cc261051a355e9475ab182f87fa4` |

## 自动检查

| 检查 | 结果 |
| --- | --- |
| 触控目标 | 通过 |
| 结构无障碍审计 | 通过 |
| 大号文字核心操作和标题/日期布局 | 通过 |
| 完整 contrast/Dynamic Type audit | 通过，2 项误报豁免 |

完整审计通过。`Launch Room` 和 `Ship brief` 的 Dynamic Type 警告是已记录的 SwiftUI 误报。两项都由大号文字 UI 测试和截图覆盖。
