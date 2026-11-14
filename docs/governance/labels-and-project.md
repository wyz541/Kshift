---
slug: /governance/labels-and-project
title: Kshift 标签与 Project 配置
type: reference
status: active
version: "0.1"
updated: "2026-11-14"
keywords:
  - 标签
  - Project
  - Issue
  - 工作流
  - 迁移
description: 记录 Kshift 的标签集合、Project 字段、Issue 迁移映射和审计方法。
---

# Kshift 标签与 Project 配置

> 结论：每个开放 Issue 只有 1 个 `type:` 标签，并且至少有 1 个 `area:` 标签。Project `Status` 是唯一状态来源。规则来源为 [ADR-0010](../adr/0010-issue-pr-and-local-build-governance.md)。

## 1. 权威边界

| 对象 | 规则 |
| --- | --- |
| `type:` | 每个事项只能有 1 个类型标签 |
| `area:` | 每个开放 Issue 至少有 1 个领域标签 |
| `risk:`、`needs:` | 按风险或工作需求增加，不替代类型和领域标签 |
| `accessibility` | 可以与任意类型和领域标签共存 |
| Project `Status` | 唯一状态来源；禁止创建状态标签 |
| Project `Priority` | 唯一优先级来源；禁止创建优先级标签 |
| Project `Target` | 唯一里程碑来源 |

旧通用标签保留到治理验收完成。历史关闭 Issue 不批量改写标签。

迁移期间，Issue 正文的 `Status:` 行只镜像 Project `Status`。评审和查询必须使用 Project `Status`。治理验收后移除正文状态行。

## 2. 标签

| 标签 | 颜色 | 说明 |
| --- | --- | --- |
| `type:feature` | `1D76DB` | 功能级交付，包含多个子任务和验收 |
| `type:acceptance` | `5319E7` | 独立验收事项，只记录证据和结论 |
| `type:task` | `0E8A16` | 可独立完成的实现、文档或治理任务 |
| `type:bug` | `D73A4A` | 已观察到的缺陷或回归 |
| `type:research` | `D4C5F9` | 需要先形成决策的研究 |
| `type:docs` | `0075CA` | 文档新增、修订或校验 |
| `type:release` | `FBCA04` | 构建、签名、分发或回滚 |
| `type:security` | `B60205` | 安全修复、审计或披露 |
| `area:server` | `006B75` | Rust server、API、鉴权和事务 |
| `area:client` | `1D76DB` | Rust client、同步、缓存和重试 |
| `area:ffi` | `5319E7` | C ABI 和跨语言边界 |
| `area:ui` | `C5DEF5` | 共享 SwiftUI 界面和交互 |
| `area:macos` | `0E8A16` | macOS 平台适配 |
| `area:ios` | `BFDADC` | iOS 平台适配 |
| `area:data` | `006B75` | PostgreSQL、迁移、备份和数据模型 |
| `area:release` | `FBCA04` | 构建、签名、发布和回滚 |
| `area:governance` | `6E7781` | Issue、PR、标签、Project 和协作规则 |
| `risk:data-loss` | `B60205` | 可能删除、损坏或不可恢复地修改数据 |
| `risk:security` | `D93F0B` | 可能影响认证、授权、机密性或安全边界 |
| `needs:design` | `F9D0C4` | 需要先完成交互或视觉设计 |
| `needs:evidence` | `FEF2C0` | 需要补充运行、测试或人工验收证据 |

`accessibility` 是保留标签。它表示影响残障用户使用的障碍。

## 3. Project 字段

Project：[Kshift Project #9](https://github.com/users/wyz541/projects/9)

| 字段 | 选项 |
| --- | --- |
| `Status` | `Inbox`、`Triage`、`Ready`、`In Progress`、`In Review`、`Blocked`、`Done` |
| `Priority` | `P0`、`P1`、`P2`、`P3` |
| `Target` | `R0`、`R1`、`R2`、`R3`、`R4`、`R5`、`v1.0` |

迁移时开放 Issue 已全部加入 Project。当前状态、优先级和 Target 只从 Project 读取。

## 4. Issue 标签迁移记录

旧标签不删除。新标签只补充类型和领域信息。Issue #23 在迁移后关闭。

| Issue | 新类型 | 新领域 | 保留的旧标签 |
| --- | --- | --- | --- |
| #2 | `type:feature` | `area:server`、`area:client`、`area:ui`、`area:data`、`area:release`、`area:governance` | `enhancement` |
| #8 | `type:feature` | `area:server`、`area:client`、`area:ui`、`area:data` | `enhancement` |
| #9 | `type:feature` | `area:server`、`area:data`、`area:release`、`area:governance` | `enhancement` |
| #22 | `type:feature` | `area:governance` | `enhancement` |
| #23 | `type:research` | `area:governance` | `documentation`、`enhancement`、`question` |
| #24 | `type:task` | `area:governance` | `documentation`、`enhancement` |
| #25 | `type:task` | `area:governance` | `enhancement` |
| #26 | `type:task` | `area:governance` | `documentation`、`enhancement` |
| #27 | `type:task` | `area:macos`、`area:ios` | `enhancement` |
| #28 | `type:acceptance` | `area:governance`、`needs:evidence` | `enhancement` |

## 5. 迁移与回滚

迁移步骤：

1. 创建目标标签。
2. 创建 Project 和 3 个字段。
3. 把开放 Issue 加入 Project。
4. 增加类型、领域和关注点标签。
5. 设置 Project 状态、优先级和 Target。
6. 运行审计命令。
7. 在 Acceptance Issue #28 通过后移除正文迁移期 `Status:` 行。

回滚步骤：

1. 按映射表移除新增标签。
2. 恢复 Project 字段或解除仓库链接。
3. 保留旧通用标签。
4. 如果 Project 不可用，使用正文原有 `Status:` 行。

禁止删除历史关闭 Issue 的 `accessibility` 或其他旧标签。Issue #23 已关闭，但其迁移标签保留。

## 6. 审计

检查目标标签都有说明。

```bash
gh label list --limit 100 --json name,description \
  --jq '[.[] | select(.name | test("^(type|area|risk|needs):")) | select(.description == "")]'
```

预期结果：`[]`。

检查每个开放 Issue 只有 1 个类型标签，并且至少有 1 个领域标签。

```bash
gh issue list --state open --limit 100 --json number,labels \
  --jq '[.[] | {number, type_count: ([.labels[].name | select(startswith("type:"))] | length), area_count: ([.labels[].name | select(startswith("area:"))] | length)}]'
```

预期结果：每项的 `type_count` 为 `1`，`area_count` 大于或等于 `1`。

检查 Project 字段。

```bash
gh project field-list 9 --owner wyz541 --format json \
  --jq '[.fields[] | select(.name == "Status" or .name == "Priority" or .name == "Target") | {name, options: [.options[].name]}]'
```

检查 Project item 字段。

```bash
gh project item-list 9 --owner wyz541 --limit 100 --format json \
  --jq '[.items[] | select(.content.type == "Issue") | {number: .content.number, status, priority, target}]'
```
