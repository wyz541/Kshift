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
| 2 | [KS-CORE](specs/core.md) | 查看产品目标、范围、用户和路线 |
| 3 | [KS-DOMAIN](specs/domain.md) | 查看项目、任务、负责人、日期和历史规则 |
| 4 | [KS-ARCH](specs/architecture.md) | 查看调用链、同步、缓存和协议规则 |
| 5 | [KS-OPS](specs/operations.md) | 查看安全、容量、备份和恢复规则 |
| 6 | [KS-UI](specs/ui.md) | 查看平台、共享 UI、Liquid Glass 和无障碍规则 |
| 7 | [KS-RELEASE](specs/release.md) | 查看质量门禁、Release 和回滚规则 |
| 8 | [KS-GOV](specs/governance.md) | 查看当前工程治理规则 |
| 9 | [Traceability](spec/traceability.md) | 从 Discussion 追踪到 Active Spec |
| 10 | [Contracts](contracts/README.md) | 实现协议和 Release 规则 |
| 11 | [Issue Relations](governance/issue-relations.md) | 查询原生事项关系和执行审计 |
| 12 | [Labels and Project](governance/labels-and-project.md) | 查看标签、Project 字段和迁移映射 |
| 13 | [R0 Spec Review](reviews/2026-11-13-r0-spec-review.md) | 查看正式评审结论和证据 |
| 14 | [Decision Register](decisions/decision-register.md) | 查看冻结的历史决策记录 |
| 15 | [Open Questions](decisions/open-questions.md) | 查看冻结的未决问题 |
| 16 | [ADR Index](adr/README.md) | 追溯历史决策原因 |
| 17 | [R4/R5](r4-r5/README.md) | 运维、部署、发布和验收 |
| 18 | [Local Build](local-build.md) | DerivedData、Debug App 和 Test Runner 的本地规则 |

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
