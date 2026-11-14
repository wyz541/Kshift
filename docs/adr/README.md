---
slug: /adr
title: Kshift ADR 索引
type: reference
status: active
updated: "2026-11-13"
keywords:
  - ADR
  - 架构决策
  - Kshift
description: 列出 Kshift v1 的架构决策记录、状态和关联章节。
---

# Kshift ADR 索引

> 结论：ADR 解释关键决策的原因和取舍。Spec 是执行规则的权威入口。

## 1. 状态

| 状态 | 含义 |
| --- | --- |
| `proposed` | 待评审 |
| `accepted` | 已进入当前基线 |
| `superseded` | 已被新 ADR 替代 |
| `rejected` | 未采用 |

## 2. ADR 列表

| ADR | 决策 | 状态 | Decision |
| --- | --- | --- | --- |
| [0001](0001-rust-authority-and-swiftui-host.md) | Rust 业务权威和 SwiftUI host | `accepted` | `DEC-001`、`DEC-007` |
| [0002](0002-macos-ios-first.md) | macOS/iOS 首版和共享 SwiftUI | `accepted` | `DEC-002` 至 `DEC-004` |
| [0003](0003-native-liquid-glass-boundary.md) | 原生 Liquid Glass 边界 | `accepted` | `DEC-005` |
| [0004](0004-postgresql18-single-host.md) | PostgreSQL 18 单机部署 | `accepted` | `DEC-006`、`DEC-011` |
| [0005](0005-revisioned-snapshot-outbox.md) | revision snapshot 和 outbox | `accepted` | `DEC-009`、`DEC-010`、`DEC-012` |
| [0006](0006-grpc-protobuf-ffi.md) | gRPC、protobuf 和 C ABI | `accepted` | `DEC-007`、`DEC-008` |
| [0007](0007-github-release-orchestrator.md) | GitHub Release orchestrator | `accepted` | `DEC-013` |
| [0008](0008-task-ownership-and-time-zones.md) | 任务负责人和时区语义 | `accepted` | `DEC-028` 至 `DEC-030` |
| [0009](0009-single-day-plan-ui.md) | 唯一日计划 UI | `accepted` | `DEC-003`、`DEC-031` |
| [0010](0010-plan-depth-snapshot-history.md) | R3 计划深度快照和历史状态 | `accepted` | Issue #8 |

## 3. 模板

新增 ADR 使用 [template.md](template.md)。文件名格式如下。

```text
NNNN-short-title.md
```

编号按创建顺序递增。编号不复用。

## 4. 变更规则

- ADR 进入 `accepted` 后不静默修改决策。
- 修正文字时保留决策内容。
- 改变决策时新建 ADR，并把旧 ADR 标为 `superseded`。
- 旧 ADR 保留，不删除。
- ADR 必须链接 Spec、Decision Register 和合同。
