---
slug: /adr
title: Kshift ADR 历史索引
type: reference
status: superseded
updated: "2026-11-14"
keywords:
  - ADR
  - 历史
  - 迁移
  - Kshift
description: 列出已迁移和待迁移的 ADR 历史来源。
---

# Kshift ADR 历史索引

> 结论：ADR 只用于追溯历史原因。当前规则只存在于 Active Spec。新提案不再创建 ADR。

## 1. 当前入口

- [Active Spec 索引](../specs/index.md)
- [KS-GOV](../specs/governance.md)
- [Issue #34 Spec-first 决策](https://github.com/wyz541/Kshift/issues/34)

## 2. ADR 列表

| ADR | 历史决策 | 状态 | 目标 Spec |
| --- | --- | --- | --- |
| [0001](0001-rust-authority-and-swiftui-host.md) | Rust 业务权威和 SwiftUI host | `superseded` | `KS-ARCH` |
| [0002](0002-macos-ios-first.md) | macOS/iOS 首版和共享 SwiftUI | `superseded` | `KS-UI` |
| [0003](0003-native-liquid-glass-boundary.md) | 原生 Liquid Glass 边界 | `superseded` | `KS-UI` |
| [0004](0004-postgresql18-single-host.md) | PostgreSQL 18 单机部署 | `superseded` | `KS-OPS` |
| [0005](0005-revisioned-snapshot-outbox.md) | revision snapshot 和 outbox | `superseded` | `KS-ARCH` |
| [0006](0006-grpc-protobuf-ffi.md) | gRPC、protobuf 和 C ABI | `superseded` | `KS-ARCH` |
| [0007](0007-github-release-orchestrator.md) | GitHub Release orchestrator | `superseded` | `KS-RELEASE` |
| [0008](0008-task-ownership-and-time-zones.md) | 任务负责人和时区语义 | `superseded` | `KS-DOMAIN` |
| [0009](0009-single-day-plan-ui.md) | 唯一日计划 UI | `superseded` | `KS-UI` |
| [0010](0010-issue-pr-and-local-build-governance.md) | Issue/PR 与本地构建治理 | `superseded` | `KS-GOV` |

## 3. 历史规则

- ADR 文件保留原位。
- ADR 状态为 `superseded`。
- ADR 不进入权威顺序。
- ADR 不接收新决策。
- ADR 删除需要独立 Issue、迁移映射和明确确认。
- Git 历史保存 ADR 的旧版本。

## 4. 模板

[template.md](template.md) 只说明历史 ADR 格式。禁止用该模板创建新决策。
