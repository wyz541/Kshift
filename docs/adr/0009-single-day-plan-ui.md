---
slug: /adr/0009-single-day-plan-ui
title: ADR-0009 唯一日计划 UI
type: decision
status: active
version: "1.0"
updated: "2026-11-13"
keywords:
  - 日计划
  - SwiftUI
  - UI
  - Kshift
description: 固定 KshiftRootView 为唯一日计划 UI，并归档未接入应用的并行实现。
---

# ADR-0009 唯一日计划 UI

> 结论：`KshiftRootView` 和 `AppModel` 是唯一日计划 UI。`KshiftDayPlanFeatureView` 原型已从当前树删除，并保留在 Git 历史中。

## 1. 状态

`accepted`

## 2. 背景

仓库曾有两套日计划 UI。`KshiftRootView` 已接入 macOS 和 iOS app。`KshiftRootView` 覆盖项目切换、CRUD、日历、表格、筛选、批量处理和冲突提示。

`KshiftDayPlanFeatureView` 是共享基座原型。该原型只读取单日任务和切换状态。该原型没有接入 app，也没有覆盖 P0 场景。

两套 UI 增加维护、测试和证据成本。两套 UI 也会让产品入口不明确。

## 3. 决策

- 保留 `KshiftRootView` 作为唯一日计划 UI。
- 保留 `AppModel` 作为该 UI 的共享状态模型。
- macOS 和 iOS app 只组合 `KshiftRootView`。
- 删除 `KshiftDayPlanFeatureView` 及其专用模型、组件、映射和测试。
- 不删除 `KshiftPresentation` 中的平台 capability 类型。
- 不删除 `KshiftFFI` 中的 Rust C ABI wrapper。
- 原型源码归档在 Git 提交 `84a8d1d`。

## 4. 备选方案

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| 保留 `KshiftRootView` | 已接 app；P0 覆盖完整；证据充分 | 单文件职责较多 | 采用 |
| 保留 `KshiftDayPlanFeatureView` | 状态边界较小 | 未接 app；P0 功能不足；需要补齐完整流程 | 拒绝 |
| 同时保留两套 UI | 不删除现有代码 | 入口、测试和维护重复 | 拒绝 |

## 5. 后果

- 共享 UI 测试以 `KshiftRootView` 和 `AppModel` 为入口。
- 平台边界脚本检查 `KshiftRootView`。
- 删除的原型可以从 Git 历史恢复。
- 后续需要拆分 `KshiftRootView` 时，创建内部 feature slice。不得恢复第二套 app 入口。

## 6. 验证

- macOS 和 iOS app 都组合 `KshiftRootView`。
- `Package.swift` 不再构建原型专用测试目标。
- `scripts/check-platform-boundaries.sh` 检查唯一共享日计划入口。
- 源码中不再引用 `KshiftDayPlanFeatureView`。

## 7. 关联

- Spec: [6. 体验与 UI](../spec/kshift-spec-v0.1.md#6-体验与-ui)
- Decision: `DEC-003`、`DEC-031`
- ADR: [ADR-0002](0002-macos-ios-first.md)
