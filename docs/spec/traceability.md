---
slug: /spec/traceability
title: Kshift Spec v0.1 追踪表
type: reference
status: active
updated: "2026-11-13"
keywords:
  - 追踪
  - Discussion
  - Spec
  - ADR
description: 把 Discussion #1 的章节映射到 Spec 章节、决策和 ADR。
source: https://github.com/wyz541/Kshift/discussions/1
---

# Kshift Spec v0.1 追踪表

> 结论：Spec v0.1 的每个核心章节都能追踪到 Discussion #1、decision ID 和 ADR。

## 1. 来源基线

| 项目 | 值 |
| --- | --- |
| Discussion | [#1](https://github.com/wyz541/Kshift/discussions/1) |
| Discussion 更新时间 | `2026-11-13T02:22:36Z` |
| Spec | [Kshift Spec v0.1](kshift-spec-v0.1.md) |
| 正式评审 | [2026-11-13 R0 Spec Review](../reviews/2026-11-13-r0-spec-review.md) |
| Spec 状态 | `active` |

## 2. 章节映射

| Discussion #1 章节 | Spec 章节 | Decision | ADR |
| --- | --- | --- | --- |
| 产品目标与基线 | [1. 问题与愿景](kshift-spec-v0.1.md#1-问题与愿景) | `DEC-001`、`DEC-002` | [0001](../adr/0001-rust-authority-and-swiftui-host.md) |
| 已确认的首版范围 | [3. 范围与非目标](kshift-spec-v0.1.md#3-范围与非目标) | `DEC-003` 至 `DEC-013` | [0002](../adr/0002-macos-ios-first.md) |
| 首版运行约束 | [9. 安全与隐私](kshift-spec-v0.1.md#9-安全与隐私) | `DEC-006`、`DEC-007` | [0004](../adr/0004-postgresql18-single-host.md) |
| 首版架构边界 | [7. 架构](kshift-spec-v0.1.md#7-架构) | `DEC-001` 至 `DEC-008` | [0001](../adr/0001-rust-authority-and-swiftui-host.md) |
| 平台与技术决策 | [6. 体验与 UI](kshift-spec-v0.1.md#6-体验与-ui) | `DEC-002` 至 `DEC-005` | [0002](../adr/0002-macos-ios-first.md) |
| 复用边界 | [6.2 复用门禁](kshift-spec-v0.1.md#62-复用门禁) | `DEC-003`、`DEC-004` | [0002](../adr/0002-macos-ios-first.md) |
| Liquid Glass 视觉基线 | [6.3 Liquid Glass 边界](kshift-spec-v0.1.md#63-liquid-glass-边界) | `DEC-005` | [0003](../adr/0003-native-liquid-glass-boundary.md) |
| UI 验收门禁 | [6.4 无障碍与性能](kshift-spec-v0.1.md#64-无障碍与性能) | `DEC-005`、`DEC-016` | [0003](../adr/0003-native-liquid-glass-boundary.md) |
| 产品路线 | [4. 产品路线](kshift-spec-v0.1.md#4-产品路线) | `DEC-015` | [0002](../adr/0002-macos-ios-first.md) |
| R2 日计划 MVP | [5. 功能规范](kshift-spec-v0.1.md#5-功能规范) | `DEC-015` | [0002](../adr/0002-macos-ios-first.md) |
| 跨阶段门禁 | [13. 质量与发布](kshift-spec-v0.1.md#13-质量与发布) | `DEC-008`、`DEC-016` | [0001](../adr/0001-rust-authority-and-swiftui-host.md) |
| 技术决策摘要 | [7.3 服务与数据库](kshift-spec-v0.1.md#73-服务与数据库) | `DEC-006` 至 `DEC-009` | [0004](../adr/0004-postgresql18-single-host.md) |
| 组件边界 | [7.2 Rust workspace](kshift-spec-v0.1.md#72-rust-workspace) | `DEC-007`、`DEC-008` | [0006](../adr/0006-grpc-protobuf-ffi.md) |
| PostgreSQL 18 | [7.3 服务与数据库](kshift-spec-v0.1.md#73-服务与数据库) | `DEC-006` | [0004](../adr/0004-postgresql18-single-host.md) |
| Rust client/server 协议 | [12. 合同与兼容](kshift-spec-v0.1.md#12-合同与兼容) | `DEC-007` | [0006](../adr/0006-grpc-protobuf-ffi.md) |
| 命令与并发前提 | [5.4 并发与冲突](kshift-spec-v0.1.md#54-并发与冲突) | `DEC-009` | [0005](../adr/0005-revisioned-snapshot-outbox.md) |
| 实时同步 | [8.1 写入和事件流](kshift-spec-v0.1.md#81-写入和事件流) | `DEC-009` | [0005](../adr/0005-revisioned-snapshot-outbox.md) |
| 并发上限与背压 | [10. 并发与容量](kshift-spec-v0.1.md#10-并发与容量) | `DEC-010` | [0005](../adr/0005-revisioned-snapshot-outbox.md) |
| 备份、恢复与保留 | [11. 备份与恢复](kshift-spec-v0.1.md#11-备份与恢复) | `DEC-011` | [0004](../adr/0004-postgresql18-single-host.md) |
| 客户端缓存 | [8.2 客户端缓存](kshift-spec-v0.1.md#82-客户端缓存) | `DEC-012` | [0005](../adr/0005-revisioned-snapshot-outbox.md) |
| Rust 质量门禁 | [13.1 Rust 门禁](kshift-spec-v0.1.md#131-rust-门禁) | `DEC-008`、`DEC-014` | [0006](../adr/0006-grpc-protobuf-ffi.md) |
| 仍需确认的 Spec 问题 | [15. 开放决策](kshift-spec-v0.1.md#15-开放决策) | `DEC-017` 至 `DEC-026` | [0007](../adr/0007-github-release-orchestrator.md) |
| 协议大小上限 | [12. 合同与兼容](kshift-spec-v0.1.md#12-合同与兼容) | `DEC-027` | [0006](../adr/0006-grpc-protobuf-ffi.md) |
| GitHub 多平台 Release Spec | [13.3 Release 门禁](kshift-spec-v0.1.md#133-release-门禁) | `DEC-013` | [0007](../adr/0007-github-release-orchestrator.md) |
| GitHub 事项分流与治理 | [14. 项目治理](kshift-spec-v0.1.md#14-项目治理) | `DEC-016` | [README](../adr/README.md) |

## 3. 下游 Issue 入口

后续 Issue 必须链接 Spec 和受影响 decision。当前映射如下。

| Issue | 主要 Spec 章节 | 主要 ADR | 合同 |
| --- | --- | --- | --- |
| [#4](https://github.com/wyz541/Kshift/issues/4) | 7、8、10、11、13.1 | 0004、0005、0006 | protobuf |
| [#5](https://github.com/wyz541/Kshift/issues/5) | 7、8、12 | 0001、0005、0006 | protobuf |
| [#6](https://github.com/wyz541/Kshift/issues/6) | 6、7 | 0001、0002、0003 | protobuf |
| [#7](https://github.com/wyz541/Kshift/issues/7) | 5、6、13.2 | 0002、0003 | protobuf |
| [#8](https://github.com/wyz541/Kshift/issues/8) | 5、8、13 | 0001、0005 | protobuf |
| [#9](https://github.com/wyz541/Kshift/issues/9) | 9、10、11、13.3、14 | 0004、0007 | protobuf、Release schema |

## 4. 变更规则

Spec 修改后必须同步检查本表。

Decision ID 不重用。ADR 被替代时保留原文件并增加 `superseded_by`。
