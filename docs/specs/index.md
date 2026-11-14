---
slug: /specs
title: Kshift Active Spec 索引
type: reference
status: active
updated: "2026-11-14"
keywords:
  - Active Spec
  - 索引
  - 领域
  - 迁移
  - Kshift
description: 列出 Kshift 的领域 Spec、稳定 ID、Owner、路径、生命周期和 ADR 迁移目标。
---

# Kshift Active Spec 索引

> 结论：当前规范按稳定领域拆成 7 篇 Active Spec。Issue 保存决策过程。Git 历史保存旧版规范。ADR 只作为历史来源。

## 1. 规范职责

| 对象 | 职责 |
| --- | --- |
| Discussion | 形成问题、约束和候选方向 |
| Issue | 保存决策发起、证据、结论和关闭原因 |
| Active Spec | 保存当前生效的项目规则 |
| 合同 | 定义接口、数据和 Release 的兼容边界 |
| Git 历史 | 保存旧版 Spec 和变更过程 |

冲突按以下顺序处理。

1. Active Spec。
2. 版本化合同。
3. Issue 和 PR 的实施说明。

ADR 不在权威顺序中。ADR 只解释历史原因。

## 2. Spec 领域

| ID | 路径 | Owner | 状态 | 范围 |
| --- | --- | --- | --- | --- |
| `KS-CORE` | [core.md](core.md) | `@wyz541` | `active` | 目标、用户、场景、产品范围、非目标和路线 |
| `KS-DOMAIN` | [domain.md](domain.md) | `@wyz541` | `active` | 项目、成员、任务、日期、查询、并发历史 |
| `KS-ARCH` | [architecture.md](architecture.md) | `@wyz541` | `active` | 运行时边界、同步、缓存、协议和数据库架构 |
| `KS-OPS` | [operations.md](operations.md) | `@wyz541` | `active` | 安全、容量、备份、恢复和部署 |
| `KS-UI` | [ui.md](ui.md) | `@wyz541` | `active` | 平台、共享 UI、Liquid Glass、无障碍和性能 |
| `KS-RELEASE` | [release.md](release.md) | `@wyz541` | `active` | 质量门禁、Release、签名、provenance 和回滚 |
| `KS-GOV` | [governance.md](governance.md) | `@wyz541` | `active` | Issue、PR、标签、Project、证据和本地构建 |

每篇 Spec 只保存一个领域的当前规则。合同保存兼容边界，不复制 Spec 的完整规则。

## 3. ID、路径和生命周期

- 每个领域只使用一个稳定 Spec ID。
- Active Spec 的文件名不包含版本号。
- Active Spec 不移动到新路径。路径改变需要新的迁移 Issue。
- 一个规则 ID 只出现在一篇 Active Spec。
- 一个规则文本只出现在一篇 Active Spec。
- Draft Spec 不约束实现。
- Active Spec 是当前根基规范。
- Historical Spec 只能用于追溯，不约束实现。
- 改变 Active Spec 时，在同一个 PR 更新规则、影响和验证。

| 状态 | 进入条件 | 退出条件 |
| --- | --- | --- |
| `draft` | 领域、ID、Owner 和范围已明确 | 评审通过并合并 |
| `active` | 规则完整，关联合同和验收入口明确 | 新 Active Spec 替代并合并 |
| `historical` | 已有替代入口 | 保留以供追溯 |

## 4. ADR 迁移

现有 ADR 保留原位。每个 ADR 标记为 `superseded`。映射如下。

| ADR | 目标 Spec | 迁移结果 |
| --- | --- | --- |
| ADR-0001 | [KS-ARCH](architecture.md) | 业务权威、FFI 和 SwiftUI host 边界 |
| ADR-0002 | [KS-UI](ui.md) | 平台范围、共享 UI 和 adapter 边界 |
| ADR-0003 | [KS-UI](ui.md) | Liquid Glass 和无障碍边界 |
| ADR-0004 | [KS-OPS](operations.md) | PostgreSQL、部署、备份和恢复 |
| ADR-0005 | [KS-ARCH](architecture.md) | revision snapshot、outbox 和冲突处理 |
| ADR-0006 | [KS-ARCH](architecture.md) | gRPC、protobuf、TLS 和 C ABI |
| ADR-0007 | [KS-RELEASE](release.md) | Release orchestrator、manifest 和 Promote |
| ADR-0008 | [KS-DOMAIN](domain.md) | 负责人和时区语义 |
| ADR-0009 | [KS-UI](ui.md) | 唯一日计划 UI |
| ADR-0010 | [KS-GOV](governance.md) | Issue、PR、标签、Project、证据和本地构建 |

[ADR 索引](../adr/README.md) 只用于历史追溯。新提案不再创建 ADR。

## 5. Decision Register 和 Open Questions

- `docs/decisions/decision-register.md` 冻结为历史来源。
- `docs/decisions/open-questions.md` 冻结为历史来源。
- 新决策过程写入 Research 或 Task Issue。
- 新未决问题建立 Research 或 Task Issue，并加入 Project。
- Active 规则只写入领域 Spec。
- 历史 Decision 和 OQ 保留，不批量重写。

## 6. Spec 模板

每篇 Active Spec 必须包含以下内容。

```text
---
slug: /specs/<domain>
title: KS-<DOMAIN> <title>
type: standard
status: active
updated: YYYY-MM-DD
owner: "@<owner>"
keywords:
  - ...
description: ...
---

# KS-<DOMAIN> <title>

> 结论：一句话说明本规范的作用。

## 1. 适用范围
## 2. 规范规则
## 3. 关联合同
## 4. 验收入口
## 5. 变更和回滚
```

Spec 不复制 Discussion 全文。Spec 不保存完整的决策选项。

## 7. 迁移结果

Issue [#35](https://github.com/wyz541/Kshift/issues/35) 完成物理迁移。

- 6 个领域 Spec 已建立，并和 KS-GOV 一起作为当前入口。
- 总 Spec 的状态改为 `historical`，只保留迁移索引。
- 10 个 ADR 的规则已有 Active Spec 入口。
- 合同、Issue Forms、PR template 和追踪表已链接 Active Spec。
- 自动检查拒绝重复规则 ID 和重复规则文本。
- 旧 ADR 和旧总 Spec 保留，用于 Git 历史追溯。

## 8. 变更和回滚

新增领域 Spec 或改变路径时，必须建立 Research 或 Task Issue。

回滚使用 Git 中上一版索引和领域 Spec。回滚禁止恢复两个 Active 规则入口。
