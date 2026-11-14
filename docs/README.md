---
slug: /docs
title: Kshift 文档
type: reference
status: active
updated: "2026-11-14"
keywords:
  - 文档入口
  - Active Spec
  - Issue
  - 合同
  - Kshift
description: 提供 Kshift Active Spec、决策过程、合同和历史材料的阅读入口。
---

# Kshift 文档

结论：先读 Active Spec。Issue 用于追溯决策过程。ADR 只提供历史背景。

## 阅读顺序

| 顺序 | 文档 | 用途 |
| ---: | --- | --- |
| 1 | [Active Spec 索引](specs/index.md) | 查看领域 Spec、ID、生命周期和迁移目标 |
| 2 | [KS-GOV](specs/governance.md) | 查看当前工程治理规则 |
| 3 | [KS-PLAN](specs/plan-depth.md) | 查看 R3 计划深度规则 |
| 4 | [Spec v0.1](spec/kshift-spec-v0.1.md) | 查看尚未迁移的领域规则 |
| 5 | [Traceability](spec/traceability.md) | 从 Discussion 追踪到 Spec |
| 6 | [Contracts](contracts/README.md) | 实现协议和 Release 规则 |
| 7 | [Issue Relations](governance/issue-relations.md) | 查询原生事项关系和执行审计 |
| 8 | [Labels and Project](governance/labels-and-project.md) | 查看标签、Project 字段和迁移映射 |
| 9 | [R0 Spec Review](reviews/2026-11-13-r0-spec-review.md) | 查看正式评审结论和证据 |
| 10 | [Decision Register](decisions/decision-register.md) | 查看冻结的历史决策记录 |
| 11 | [Open Questions](decisions/open-questions.md) | 查看待迁移的未决问题 |
| 12 | [ADR Index](adr/README.md) | 追溯历史决策原因 |
| 13 | [R4/R5](r4-r5/README.md) | 运维、部署、发布和验收 |
| 14 | [Local Build](local-build.md) | DerivedData、Debug App 和 Test Runner 的本地规则 |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| `draft` | 尚未约束实现 |
| `active` | 当前生效的 Active Spec 或入口 |
| `historical` | 只用于追溯 |
| `superseded` | 已有新入口替代 |

## 规范边界

- 新规则只写入 Active Spec。
- 新决策在新 Issue 中形成。
- PR 同时链接 Issue、Active Spec 和证据。
- 旧 ADR、Decision Register 和 Open Questions 不批量删除。
