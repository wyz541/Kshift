---
slug: /docs
title: Kshift 文档
type: reference
status: review
updated: "2026-11-13"
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
| 2 | [Traceability](spec/traceability.md) | 从 Discussion 追踪到 Spec |
| 3 | [Decision Register](decisions/decision-register.md) | 查看确认、待定和拒绝状态 |
| 4 | [Open Questions](decisions/open-questions.md) | 查看 owner、截止日期和影响 |
| 5 | [ADR Index](adr/README.md) | 理解关键决策的原因和取舍 |
| 6 | [Contracts](contracts/README.md) | 实现协议和 Release 规则 |

## 状态说明

| 状态 | 含义 |
| --- | --- |
| `confirmed` | 已进入 Spec 基线 |
| `pending` | 尚未决定；不得由实现 PR 自行决定 |
| `rejected` | 明确不进入首版或永久禁止 |
| `review` | 文档可引用，等待评审确认 |
| `superseded` | 已由新文档替代 |
