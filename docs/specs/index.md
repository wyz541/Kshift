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
description: 定义 Kshift 的领域 Spec 划分、稳定 ID、生命周期和 ADR 迁移目标。
---

# Kshift Active Spec 索引

> 结论：当前规范按稳定领域拆成 Spec。Issue 保存决策过程。Git 历史保存旧版规范。ADR 只作为历史来源。

## 1. 规范职责

| 对象 | 职责 |
| --- | --- |
| Discussion | 形成问题、约束和候选方向 |
| Issue | 保存决策发起、证据、结论和关闭原因 |
| Active Spec | 保存当前生效的项目规则 |
| 合同 | 定义接口、数据和 Release 的兼容边界 |
| Git 历史 | 保存旧版 Spec 和变更过程 |

Conflict 按以下顺序处理。

1. Active Spec。
2. 版本化合同。
3. Issue 和 PR 的实施说明。

ADR 不在权威顺序中。ADR 只解释历史原因。

## 2. Spec 领域

| ID | 路径 | 状态 | 范围 |
| --- | --- | --- | --- |
| `KS-GOV` | [governance.md](governance.md) | `active` | Issue、PR、标签、Project、证据和本地构建 |
| `KS-CORE` | `core.md` | `planned` | 目标、用户、场景、产品范围和路线 |
| `KS-DOMAIN` | `domain.md` | `planned` | 项目、成员、任务、日期、历史和附件 |
| `KS-ARCH` | `architecture.md` | `planned` | 运行时边界、同步、缓存和数据库 |
| `KS-OPS` | `operations.md` | `planned` | 安全、容量、备份、恢复和部署 |
| `KS-UI` | `ui.md` | `planned` | 平台、共享 UI、Liquid Glass 和无障碍 |
| `KS-RELEASE` | `release.md` | `planned` | 质量门禁、Release、签名和回滚 |

在领域 Spec 合并前，[Spec v0.1](../spec/kshift-spec-v0.1.md) 保留该领域的当前规则。领域 Spec 合并后，旧章节只保留入口。

## 3. ID、路径和生命周期

- 每个领域只使用一个 Spec ID。
- Active Spec 的文件名不包含版本号。
- Active Spec 不移动到新路径。路径改变需要新的迁移 Issue。
- 一个规则只出现在一个 Active Spec。
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
| ADR-0001 | `KS-ARCH` | 业务权威、FFI 和 SwiftUI host 边界 |
| ADR-0002 | `KS-UI` | 平台范围、共享 UI 和 adapter 边界 |
| ADR-0003 | `KS-UI` | Liquid Glass 和无障碍边界 |
| ADR-0004 | `KS-OPS` | PostgreSQL、部署、备份和恢复 |
| ADR-0005 | `KS-ARCH` | revision snapshot、outbox 和冲突处理 |
| ADR-0006 | `KS-ARCH` | gRPC、protobuf、TLS 和 C ABI |
| ADR-0007 | `KS-RELEASE` | Release orchestrator、manifest 和 Promote |
| ADR-0008 | `KS-DOMAIN` | 负责人和时区语义 |
| ADR-0009 | `KS-UI` | 唯一日计划 UI |
| ADR-0010 | `KS-GOV` | Issue、PR、标签、Project、证据和本地构建 |

[ADR 索引](../adr/README.md) 只用于历史追溯。新提案不再创建 ADR。

## 5. Decision Register 和 Open Questions

- `docs/decisions/decision-register.md` 冻结为迁移来源。
- `docs/decisions/open-questions.md` 冻结为迁移来源。
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

## 7. 后续迁移

物理迁移由后续 Task [#35](https://github.com/wyz541/Kshift/issues/35) 完成。

1. 创建其余领域 Spec。
2. 把总 Spec 的规则迁入唯一领域 Spec。
3. 更新合同、模板、Issue 和 PR 入口。
4. 运行文档、合同和关系检查。
5. 保留旧 ADR 和旧 Spec 供 Git 历史追溯。

迁移 Task 只能更新目标入口。迁移 Task 不得改变已确认规则。
