---
slug: /docs
title: Kshift 文档
type: reference
status: active
updated: "2026-11-14"
keywords:
  - 文档入口
  - Spec
  - ADR
  - Contract
description: 提供 Kshift Spec、ADR、决策和合同的阅读入口。
---

# Kshift 文档

结论：先读 Spec，再按任务读取 ADR、决策记录或合同。

## 阅读顺序

| 顺序 | 文档 | 用途 |
| ---: | --- | --- |
| 1 | [Spec v0.1](spec/kshift-spec-v0.1.md) | 产品、技术、UI 和验收的权威规则 |
| 2 | [R0 Spec Review](reviews/2026-11-13-r0-spec-review.md) | 正式评审结论和证据 |
| 3 | [Traceability](spec/traceability.md) | 从 Discussion 追踪到 Spec |
| 4 | [Decision Register](decisions/decision-register.md) | 查看确认、待定和拒绝状态 |
| 5 | [Open Questions](decisions/open-questions.md) | 查看 owner、截止日期和影响 |
| 6 | [ADR Index](adr/README.md) | 理解关键决策的原因和取舍 |
| 7 | [Contracts](contracts/README.md) | 实现协议和 Release 规则 |
| 8 | [Issue Relations](governance/issue-relations.md) | 查询原生事项关系和执行审计 |
| 9 | [Labels and Project](governance/labels-and-project.md) | 查看标签、Project 字段和迁移映射 |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| `confirmed` | 已进入 Spec 基线 |
| `pending` | 尚未决定；不得由实现 PR 自行决定 |
| `rejected` | 明确不进入首版或永久禁止 |
| `review` | 文档可引用，等待评审确认 |
| `active` | 文档是当前有效基线 |
| `superseded` | 已由新文档替代 |
