---
slug: /specs/plan-depth
title: KS-PLAN Kshift 计划深度规范
type: standard
status: active
updated: "2026-11-14"
keywords:
  - 计划深度
  - 子任务
  - 依赖
  - 附件
  - 历史回退
  - 报告
description: 定义 Kshift R3 的子任务、依赖、跨日排期、附件、历史和报告规则。
---

# KS-PLAN Kshift 计划深度规范

> 结论：R3 计划深度使用 revisioned snapshot。Rust core 是业务权威。PostgreSQL 和 SwiftUI 只使用该切片生成的 snapshot。

## 1. 适用范围

本 Spec 适用于 macOS/iOS 计划深度页面、`kshift-core::plan_depth`、`kshift-plan-store` 和 R3 PostgreSQL schema。

本 Spec 不改变 R1 同步合同和 R2 日计划入口。

## 2. 规范规则

### 2.1 子任务和依赖

- 父任务和子任务必须属于同一项目。
- 子任务层级禁止形成循环。
- 任务依赖必须属于同一项目。
- 任务依赖禁止直接或间接形成循环。
- 删除父任务前，用户必须删除或移动子任务。
- 过期 revision 必须返回冲突。过期任务 version 必须返回冲突。

### 2.2 跨日排期

- 每个任务必须包含 `starts_on` 和 `due_on`。
- `starts_on` 不得晚于 `due_on`。
- `starts_on == due_on` 表示单日任务。
- `starts_on != due_on` 表示跨日任务。
- 甘特条只使用 snapshot 中的自然日期。

### 2.3 附件

- 附件按项目内 SHA-256 去重。
- 单文件上限为 10 MiB。
- Server 必须校验 MIME type、文件扩展名和文件内容。
- 允许的类型为 Markdown、纯文本、CSV、JSON、PNG、JPEG、GIF、WebP、PDF 和 ZIP。
- 文件名只保留 basename。
- 同一内容可以链接多个任务。

### 2.4 历史和回退

- 每次成功写入创建一个新 revision。
- 历史 row 必须保存 before state、after state、actor、action、summary 和内容 SHA-256。
- 历史 row 不可原地修改。
- 回退只允许 Admin。
- 回退必须选择更早的 retained revision。
- 回退创建新 revision，不删除已有历史。
- 回退 row 必须记录 `restored_from_revision` 和恢复内容 SHA-256。

### 2.5 报告和导出

- 报告必须固定一个 `source_revision`。
- 工作报告、统计、打印和 PNG 导出必须读取同一个 report snapshot。
- 报告必须列出任务、负责人、日期、工时、依赖数、子任务数和附件数。
- 打印和图片导出不得重新读取 live project state。

### 2.6 共享 UI

- macOS 和 iOS 必须使用同一个 `KshiftPlanDepthFeatureView`。
- `KshiftRootView` 必须提供可见的计划深度入口。
- 看板任务卡使用 Apple 原生 Liquid Glass。
- 甘特、历史和报告使用稳定内容底板。
- AppKit 和 UIKit 只处理保存、打印、分享和触觉反馈。

## 3. 关联合同

- `migrations/0002_plan_depth.sql`
- `Sources/KshiftPresentation/PlanDepth/KshiftPlanDepthModels.swift`
- `Sources/KshiftPresentation/PlanDepth/KshiftPlanDepthPresentation.swift`
- `crates/kshift-core/src/plan_depth.rs`
- `crates/kshift-plan-store/src/lib.rs`

## 4. 验收入口

- Rust unit tests: `cargo test --workspace`
- PostgreSQL integration: `./scripts/test-plan-store.sh`
- Swift package tests: `swift test`
- macOS build: `xcodebuild -scheme Kshift-macOS`
- iOS build and R3 UI audit: `xcodebuild -scheme Kshift-iOS`
- Detailed matrix: [R3 验收](../r3-plan-depth.md)

## 5. 变更和回滚

- 规则变化必须在同一个 PR 更新本 Spec、测试和证据。
- 合同变化必须保持向后兼容。破坏性变化需要新 contract version。
- schema 变化必须新增 migration。禁止编辑已应用 migration。
- 回滚应用或 migration 前必须备份数据库。
- 回退 R3 时恢复应用和 schema 到同一 commit。已有 R3 数据必须先导出或恢复备份。
