---
slug: /spec/traceability
title: Kshift Spec 追踪表
type: reference
status: active
updated: "2026-11-14"
keywords:
  - 追踪
  - Discussion
  - Spec
  - 历史来源
description: 把 Discussion #1 的章节映射到领域 Active Spec、决策过程和历史来源。
source: https://github.com/wyz541/Kshift/discussions/1
---

# Kshift Spec 追踪表

> 结论：每个核心章节能追踪到 Discussion #1、Decision Issue 和 Active Spec。历史 ADR 只补充来源。

## 1. 来源基线

| 项目 | 值 |
| --- | --- |
| Discussion | [#1](https://github.com/wyz541/Kshift/discussions/1) |
| Discussion 更新时间 | `2026-11-13T02:22:36Z` |
| Active Spec 索引 | [docs/specs/index.md](../specs/index.md) |
| 正式评审 | [2026-11-13 R0 Spec Review](../reviews/2026-11-13-r0-spec-review.md) |
| 历史 Spec | [Kshift Spec v0.1](kshift-spec-v0.1.md) |

## 2. 章节映射

| Discussion #1 章节 | Active Spec | Decision | 历史来源 |
| --- | --- | --- | --- |
| 产品目标与基线 | [KS-CORE](../specs/core.md) | `DEC-001`、`DEC-002` | [0001](../adr/0001-rust-authority-and-swiftui-host.md) |
| 已确认的首版范围 | [KS-CORE](../specs/core.md) | `DEC-003` 至 `DEC-013` | [0002](../adr/0002-macos-ios-first.md) |
| 首版运行约束 | [KS-OPS](../specs/operations.md) | `DEC-006`、`DEC-007` | [0004](../adr/0004-postgresql18-single-host.md) |
| 首版架构边界 | [KS-ARCH](../specs/architecture.md) | `DEC-001` 至 `DEC-008` | [0001](../adr/0001-rust-authority-and-swiftui-host.md) |
| 平台与技术决策 | [KS-UI](../specs/ui.md) | `DEC-002` 至 `DEC-005` | [0002](../adr/0002-macos-ios-first.md) |
| 复用边界 | [KS-UI](../specs/ui.md) | `DEC-003`、`DEC-004` | [0002](../adr/0002-macos-ios-first.md) |
| Liquid Glass 视觉基线 | [KS-UI](../specs/ui.md) | `DEC-005` | [0003](../adr/0003-native-liquid-glass-boundary.md) |
| UI 验收门禁 | [KS-UI](../specs/ui.md) | `DEC-005`、`DEC-016` | [0003](../adr/0003-native-liquid-glass-boundary.md) |
| 产品路线 | [KS-CORE](../specs/core.md) | `DEC-015` | [0002](../adr/0002-macos-ios-first.md) |
| R2 日计划 MVP | [KS-DOMAIN](../specs/domain.md)、[KS-UI](../specs/ui.md) | `DEC-015`、`DEC-031` | [0009](../adr/0009-single-day-plan-ui.md) |
| 负责人和时区语义 | [KS-DOMAIN](../specs/domain.md) | `DEC-028` 至 `DEC-030` | [0008](../adr/0008-task-ownership-and-time-zones.md) |
| 跨阶段门禁 | [KS-RELEASE](../specs/release.md) | `DEC-008`、`DEC-014`、`DEC-016` | [0001](../adr/0001-rust-authority-and-swiftui-host.md) |
| 技术决策摘要 | [KS-ARCH](../specs/architecture.md)、[KS-OPS](../specs/operations.md) | `DEC-006` 至 `DEC-009` | [0004](../adr/0004-postgresql18-single-host.md) |
| 组件边界 | [KS-ARCH](../specs/architecture.md) | `DEC-007`、`DEC-008` | [0006](../adr/0006-grpc-protobuf-ffi.md) |
| PostgreSQL 18 | [KS-ARCH](../specs/architecture.md)、[KS-OPS](../specs/operations.md) | `DEC-006` | [0004](../adr/0004-postgresql18-single-host.md) |
| Rust client/server 协议 | [KS-ARCH](../specs/architecture.md) | `DEC-007` | [0006](../adr/0006-grpc-protobuf-ffi.md) |
| 命令与并发前提 | [KS-DOMAIN](../specs/domain.md)、[KS-ARCH](../specs/architecture.md) | `DEC-009` | [0005](../adr/0005-revisioned-snapshot-outbox.md) |
| 实时同步 | [KS-ARCH](../specs/architecture.md) | `DEC-009` | [0005](../adr/0005-revisioned-snapshot-outbox.md) |
| 并发上限与背压 | [KS-OPS](../specs/operations.md) | `DEC-010` | [0005](../adr/0005-revisioned-snapshot-outbox.md) |
| 备份、恢复与保留 | [KS-OPS](../specs/operations.md) | `DEC-011` | [0004](../adr/0004-postgresql18-single-host.md) |
| 客户端缓存 | [KS-ARCH](../specs/architecture.md) | `DEC-012` | [0005](../adr/0005-revisioned-snapshot-outbox.md) |
| Rust 质量门禁 | [KS-RELEASE](../specs/release.md) | `DEC-008`、`DEC-014` | [0006](../adr/0006-grpc-protobuf-ffi.md) |
| 仍需确认的 Spec 问题 | [Open Questions](../decisions/open-questions.md) | `DEC-017` 至 `DEC-026` | [0007](../adr/0007-github-release-orchestrator.md) |
| 协议大小上限 | [KS-ARCH](../specs/architecture.md)、[KS-OPS](../specs/operations.md) | `DEC-027` | [0006](../adr/0006-grpc-protobuf-ffi.md) |
| GitHub 多平台 Release | [KS-RELEASE](../specs/release.md) | `DEC-013` | [0007](../adr/0007-github-release-orchestrator.md) |
| GitHub 事项分流与治理 | [KS-GOV](../specs/governance.md) | Issue #23、Issue #34 | [Active Spec 索引](../specs/index.md) |

## 3. 下游 Issue 入口

后续 Issue 必须链接 Active Spec 和 Decision Issue。

| Issue | 主要 Active Spec | 历史 ADR | 合同 |
| --- | --- | --- | --- |
| [#4](https://github.com/wyz541/Kshift/issues/4) | [KS-ARCH](../specs/architecture.md)、[KS-OPS](../specs/operations.md)、[KS-RELEASE](../specs/release.md) | 0004、0005、0006 | protobuf |
| [#5](https://github.com/wyz541/Kshift/issues/5) | [KS-ARCH](../specs/architecture.md)、[KS-OPS](../specs/operations.md) | 0001、0005、0006 | protobuf |
| [#6](https://github.com/wyz541/Kshift/issues/6) | [KS-UI](../specs/ui.md)、[KS-ARCH](../specs/architecture.md) | 0001、0002、0003 | protobuf |
| [#7](https://github.com/wyz541/Kshift/issues/7) | [KS-DOMAIN](../specs/domain.md)、[KS-UI](../specs/ui.md) | 0002、0003、0008 | protobuf |
| [#8](https://github.com/wyz541/Kshift/issues/8) | [KS-DOMAIN](../specs/domain.md)、[KS-ARCH](../specs/architecture.md)、[KS-RELEASE](../specs/release.md) | 0001、0005 | protobuf |
| [#9](https://github.com/wyz541/Kshift/issues/9) | [KS-OPS](../specs/operations.md)、[KS-RELEASE](../specs/release.md)、[KS-GOV](../specs/governance.md) | 0004、0007 | protobuf、Release schema |

## 4. 变更规则

Spec 修改后必须同步检查本表。Decision 记录不重用。ADR 保留原路径，并标记为 `superseded`。
