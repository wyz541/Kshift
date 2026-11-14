---
slug: /specs/domain
title: KS-DOMAIN Kshift 任务领域规范
type: standard
status: active
updated: "2026-11-14"
owner: "@wyz541"
keywords:
  - 项目
  - 任务
  - 负责人
  - 时区
  - 历史
description: 定义 Kshift 的项目隔离、任务、负责人、自然日期、查询、并发、历史和附件语义。
---

# KS-DOMAIN Kshift 任务领域规范

> 结论：项目是数据隔离边界。任务更新必须带版本前置条件。项目时区决定自然日期。负责人是无序成员集合。

## 1. 适用范围

本 Spec 约束项目、成员、任务、负责人、自然日期、视图、并发、历史和附件的业务语义。

本 Spec 不定义传输格式、数据库事务实现、UI 外观或运维程序。接口细节见 [Protocol Contract](../contracts/protocol-v0.1.md)。

## 2. 项目与成员

- `FR-PRJ-001`：用户必须只看到已授权项目。
- `FR-PRJ-002`：项目切换必须清除旧项目的可见任务。
- `FR-PRJ-003`：服务端必须执行项目级授权。
- `FR-PRJ-004`：身份来源状态为 `pending`。客户端提交的角色不得作为授权依据。
- `FR-PRJ-005`：每个项目必须保存一个 IANA `time_zone`。
- `FR-PRJ-006`：项目时区决定自然日期。用户时区只决定绝对时间戳的显示。

## 3. 任务与负责人

- `FR-TSK-001`：任务必须包含项目、标题、状态、优先级、负责人和自然日期。
- `FR-TSK-002`：任务更新必须携带实体版本前置条件。
- `FR-TSK-003`：任务删除必须携带实体版本前置条件。
- `FR-TSK-004`：看板拖拽必须作为 typed command 提交。
- `FR-TSK-005`：批量处理必须原子提交；任一实体版本过期时整批拒绝。
- `FR-TSK-006`：R3 的子任务、依赖、附件和 Markdown 描述必须使用 v1 合同扩展点。
- `FR-TSK-007`：任务负责人是集合。集合包含 0 至 20 个唯一用户 ID。
- `FR-TSK-008`：负责人必须是当前项目的活跃成员。空集合表示未分配。
- `FR-TSK-009`：负责人写入替换完整集合。列表顺序不表示主负责人或排序优先级。
- `FR-TSK-010`：服务端输出负责人时按用户 ID 升序排列，保证相同 revision 的 snapshot 稳定。

附件缓存和传输上限分别由 [KS-ARCH](architecture.md) 和 [Protocol Contract](../contracts/protocol-v0.1.md) 定义。

## 4. 自然日期和用户时区

- 项目时区在创建项目时写入。首版禁止修改项目时区。
- 项目时区决定 `planned_on`、`starts_on`、`due_on`、人员看板、日历、报告范围、今天和逾期判断。
- 自然日期保存为 `DATE`。服务端和客户端禁止把自然日期当作 UTC 时间点。
- 用户时区来自当前设备，不作为服务端业务字段持久化。
- 用户时区只影响绝对时间戳的显示。
- 用户时区缺失或非法时，客户端回退到项目时区。
- 用户时区禁止改变任务的 `planned_on`、`starts_on` 或 `due_on`。
- 修改项目时区属于后续决策。后续实现禁止自动改写已有自然日期。

## 5. 视图与查询

- `FR-VIEW-001`：R2 必须提供人员与自然日期看板。
- `FR-VIEW-002`：R2 必须提供日历和表格视图。
- `FR-VIEW-003`：搜索、筛选和排序必须在当前项目内执行。
- `FR-VIEW-004`：基础统计必须基于同一 snapshot revision。
- `FR-VIEW-005`：报告和导出必须记录使用的项目 revision。
- `FR-VIEW-006`：人员看板、日历和自然日期筛选必须使用项目时区。
- `FR-VIEW-007`：多负责人任务必须出现在每个负责人的人员列。筛选匹配任一负责人。
- `FR-VIEW-008`：把任务拖到人员列时，负责人集合替换为目标人员。拖到未分配列时，负责人集合清空。

## 6. 并发与冲突

- `FR-CON-001`：服务端必须在事务内检查 revision 和实体版本。
- `FR-CON-002`：过期任务写入必须返回冲突。
- `FR-CON-003`：冲突结果必须包含当前项目 revision、实体 ID 和当前实体版本。
- `FR-CON-004`：客户端禁止自动合并任务内容。
- `FR-CON-005`：客户端禁止自动覆盖冲突。
- `FR-CON-006`：UI 必须允许用户刷新或重新提交。
- `FR-CON-007`：成功命令必须保持幂等。相同 `(client_id, command_id)` 返回同一结果。

## 7. 历史与审计

- `FR-HIS-001`：每次成功写入必须生成审计记录。
- `FR-HIS-002`：审计记录必须包含 actor、command、project、entity 和时间。
- `FR-HIS-003`：R3 历史回退必须生成新的审计记录。
- `FR-HIS-004`：日志禁止包含 token、数据库密码、完整敏感请求体或附件内容。
- `FR-HIS-005`：Snapshot 必须包含有界项目审计记录。Task history 从项目审计记录映射。

## 8. 关联合同

- [Protocol Contract](../contracts/protocol-v0.1.md)：ID、负责人集合、时区、命令、快照和审计记录。
- [kshift.proto](../../proto/kshift/v1/kshift.proto)：`kshift.v1` 类型定义。

## 9. 验收入口

- 负责人和时区：[Issue #16](https://github.com/wyz541/Kshift/issues/16)
- 任务和视图：[Issue #7](https://github.com/wyz541/Kshift/issues/7)、[Issue #8](https://github.com/wyz541/Kshift/issues/8)
- 历史与审计：[MVP](../MVP.md)、[R1 Acceptance](../r1-acceptance.md)
- 迁移来源：[ADR-0008](../adr/0008-task-ownership-and-time-zones.md)

## 10. 变更和回滚

改变项目隔离、任务版本、负责人或时区语义时，必须先建立 Research 或 Task Issue。合同和客户端映射必须在同一个 PR 更新。

回滚使用 Git 中上一版 Active Spec。回滚禁止自动改写已有自然日期或业务数据。
