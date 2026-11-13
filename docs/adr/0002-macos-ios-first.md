---
slug: /adr/0002-macos-ios-first
title: ADR-0002 macOS/iOS 首版和共享 SwiftUI
type: decision
status: active
version: "1.0"
updated: "2026-11-13"
keywords:
  - macOS
  - iOS
  - SwiftUI
  - AppKit
  - UIKit
description: 固定首版平台、共享 SwiftUI 和平台 adapter 边界。
---

# ADR-0002 macOS/iOS 首版和共享 SwiftUI

> 结论：首版只交付 macOS 26.0+ 和 iOS 26.0+。两端共享一套 SwiftUI。平台能力只进入 AppKit 或 UIKit adapter。

## 1. 状态

`accepted`

## 2. 背景

Web、Windows 和 Android 会增加发布、同步和验收范围。首版需要验证共享任务和并发模型。

Liquid Glass API 要求 macOS 26.0 和 iOS 26.0。最低系统版本由 API 可用性决定。

## 3. 决策

- 首版平台只有 macOS 和 iOS。
- 页面、布局、组件、导航、表单、筛选和 presentation mapping 共享。
- macOS adapter 使用 AppKit。
- iOS adapter 使用 UIKit。UIKit 只处理系统集成。
- `#if os(...)` 只出现在 app entry、capability adapter 和 platform style resolver。
- Web、Windows、Android 和外部导入不进入首版。

## 4. 备选方案

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| 先做 Web 和桌面 | 覆盖更多用户 | 平台和发布范围过大 | 拒绝 |
| macOS/iOS 各写一套 UI | 平台定制自由 | 页面和规则重复 | 拒绝 |
| 共享 SwiftUI 加 adapter | 复用高；语义一致 | adapter 需要清晰边界 | 采用 |

## 5. 后果

- Android、Windows 和 Web 只在后续 Spec 中讨论。
- 共享包必须可以同时构建两个平台。
- 平台专属能力需要有 adapter 测试。
- P0 行为必须两端一致。
- 自适应布局可以不同，业务语义不能不同。

## 6. 验证

- 同一 shared feature slice 在两端构建。
- 示例页面消费同一业务状态映射。
- adapter 清单证明没有第二套产品 UI。
- P0 行为验收在两端使用同一用例。

## 7. 关联

- Spec: [6. 体验与 UI](../spec/kshift-spec-v0.1.md#6-体验与-ui)
- Decision: `DEC-002`、`DEC-003`、`DEC-004`
- Contract: [kshift.proto](../../proto/kshift/v1/kshift.proto)
