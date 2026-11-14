---
slug: /spec/kshift-v0.1
title: Kshift Spec v0.1
type: standard
status: historical
version: "0.2"
updated: "2026-11-14"
superseded_by: /specs
keywords:
  - 历史 Spec
  - 迁移
  - Kshift
description: 保留 Kshift Spec v0.1 的历史索引；当前规则见领域 Active Spec。
source: https://github.com/wyz541/Kshift/discussions/1
---

# Kshift Spec v0.1

> 结论：本文件只保存历史入口。当前规则已迁入 7 篇领域 Active Spec。

## 1. 历史状态

| 项目 | 内容 |
| --- | --- |
| 状态 | `historical` |
| 原版本 | `0.1` |
| Owner | `@wyz541` |
| 迁移 Issue | [#35](https://github.com/wyz541/Kshift/issues/35) |
| 当前入口 | [Active Spec 索引](../specs/index.md) |

本文件不再定义当前规则。实现、评审和 Issue 必须链接 Active Spec。

## 2. 迁移映射

| 原章节 | 当前 Active Spec |
| --- | --- |
| 0. 文档控制；1. 问题与愿景；2. 用户与关键场景；3. 范围与非目标；4. 产品路线 | [KS-CORE](../specs/core.md) |
| 5.1 项目与成员；5.2 任务；5.3 视图与查询；5.4 并发与冲突；5.5 历史与审计 | [KS-DOMAIN](../specs/domain.md) |
| 7. 架构；8. 同步与缓存；12. 合同中的协议规则 | [KS-ARCH](../specs/architecture.md) |
| 5.6 备份与管理；9. 安全与隐私；10. 并发与容量；11. 备份与恢复 | [KS-OPS](../specs/operations.md) |
| 6. 体验与 UI；13.2 UI 门禁 | [KS-UI](../specs/ui.md) |
| 13.1 Rust 门禁；13.3 Release 门禁；12. 合同中的 JSON Schema 规则 | [KS-RELEASE](../specs/release.md) |
| 14. 项目治理 | [KS-GOV](../specs/governance.md) |

## 3. 历史材料

| 材料 | 用途 |
| --- | --- |
| [Traceability](../spec/traceability.md) | 从 Discussion 追踪到 Active Spec |
| [R0 Spec Review](../reviews/2026-11-13-r0-spec-review.md) | 查看原正式评审 |
| [Decision Register](../decisions/decision-register.md) | 查看冻结的决策记录 |
| [Open Questions](../decisions/open-questions.md) | 查看冻结的未决问题 |
| [ADR Index](../adr/README.md) | 追溯历史决策原因 |
| [Discussion #1](https://github.com/wyz541/Kshift/discussions/1) | 查看原始讨论 |

## 4. 变更规则

历史文件禁止继续增加当前规则。需要改变规则时，修改目标 Active Spec。

需要追溯旧版本时，使用 Git 历史中的 `docs/spec/kshift-spec-v0.1.md`。禁止删除本文件来伪造迁移历史。

## 5. 版本记录

| 版本 | 日期 | 变更 |
| --- | --- | --- |
| 0.1 | 2026-11-13 | 形成首个版本，完成正式评审并进入 `active`。 |
| 0.2 | 2026-11-14 | 将当前规则迁入领域 Spec；本文件改为 `historical`。 |
