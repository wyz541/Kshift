---
slug: /governance/close-gate
title: Kshift 关单门禁
type: standard
status: active
updated: "2026-11-24"
keywords:
  - Issue closure
  - cleanup
  - worktree
  - evidence
  - governance
description: 定义 Kshift Issue 关闭前的机器可读清理记录、校验命令和关闭后审计。
---

# Kshift 关单门禁

> 结论：Issue 只能通过 `make close-issue ISSUE=<N>` 关闭。关闭前必须在 Issue 写入机器可读清理记录，并通过 Worktree 审计、Issue 关系审计和本地状态校验。直接使用网页或 `gh issue close` 属于绕过门禁。

## 1. 适用范围

本规则适用于所有 Kshift Issue。会修改仓库的 Task 或 Bug：

- 先完成实现、证据迁移和清理批准。
- 再写入 `cleaned`、`retained` 或 `not-applicable` 记录。
- 最后通过关闭门禁关闭 Issue。

没有 Worktree、构建产物或本地临时证据的 Issue 使用 `not-applicable`，并写明具体原因。

## 2. 清理记录

Issue 的任一评论可以包含以下 HTML 注释。门禁读取最新一条匹配该 Issue 的记录。

```text
<!-- kshift-close-gate: {"schemaVersion":1,"issue":65,"status":"cleaned","worktree":"~/repo/_worktrees/Kshift/issue-65-close-gate","branch":"issue/65-close-gate","generatedArtifacts":["target/",".build/"],"evidenceTargets":["PR #201","Issue #65"],"checks":{"issueRelations":"PASS","worktreeAudit":"cleanup-candidate","mainClean":true},"approver":"@wyz541","approvedAt":"2026-11-24T16:50:40+08:00"} -->
```

使用 `~` 代替个人主目录绝对路径。禁止在公开记录中写秘密、令牌、数据库凭据或个人用户名。

### 2.1 必需字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `schemaVersion` | integer | 固定为 `1`。 |
| `issue` | integer | 本记录对应的 Issue 编号。 |
| `status` | string | `cleaned`、`retained` 或 `not-applicable`。 |
| `worktree` | string | 已登记路径；没有 Worktree 时写 `not-applicable`。 |
| `branch` | string | 已登记 branch；没有 branch 时写 `not-applicable`。 |
| `generatedArtifacts` | string[] | 已处理的生成物；无生成物时写空数组。 |
| `evidenceTargets` | string[] | 稳定证据位置，至少 1 项。 |
| `checks` | object | 至少记录 `issueRelations`、`worktreeAudit` 和 `mainClean`。 |
| `approver` | string | 清理批准人；`cleaned` 和 `retained` 必须为 `@wyz541`。 |
| `approvedAt` | ISO 8601 | 清理批准时间；`cleaned` 和 `retained` 必填。 |

### 2.2 retained 额外字段

`retained` 必须包含：

- `owner`：负责复核的人。
- `reason`：保留原因。
- `reviewAt`：复核日期，必须在 `approvedAt` 后 14 天内。

### 2.3 not-applicable 额外字段

`not-applicable` 必须包含 `notApplicableReason`。如果 Worktree 审计仍发现该 Issue 的 Worktree，门禁会拒绝关闭。

## 3. 合规关闭流程

1. 完成 PR 合并和证据迁移。
2. 取得 `@wyz541` 的明确清理批准。
3. 按批准记录移除 Worktree、删除本地 branch 并再次审计。
4. 在 Issue 写入 `kshift-close-gate` 记录。
5. 运行 dry-run：

```bash
make close-issue ISSUE=65
```

6. 检查关系审计、Worktree 审计和关闭计划。
7. 只有明确批准后才执行关闭：

```bash
make close-issue ISSUE=65 APPLY=1
```

8. 运行关闭后审计：

```bash
make audit-closed-issues LIMIT=100
```

`DRY_RUN=1` 始终只检查不关闭。未提供 `APPLY=1` 时，关闭命令必须保持 dry-run。

## 4. 状态语义

| 状态 | 含义 | 门禁要求 |
| --- | --- | --- |
| `cleaned` | Worktree 和 branch 已移除，生成物已处理。 | 记录路径不存在，branch 不存在，批准字段完整。 |
| `retained` | 经批准的 Worktree 仍需保留。 | Worktree 注册且 clean；owner、原因、批准人和 14 天复核日期完整。 |
| `not-applicable` | 本 Issue 没有本地 Worktree 或生成物。 | 写明具体原因，且不能仍有该 Issue 的 Worktree。 |

## 5. 审计和绕过边界

本地脚本无法阻止用户从网页或直接运行 `gh issue close`。因此：

- 合规入口是 `make close-issue`。
- `scripts/audit_closed_issues.py` 会报告已关闭但缺少有效记录的 Issue。
- 关闭后审计默认报告，不自动重开历史 Issue。
- 若要启用 `issues.closed` GitHub Action 自动重开违规 Issue，需要额外的事件权限、并发保护和人工复核规则；当前先采用本地 fail-closed 入口加只读关闭后审计，避免自动操作与人工清理批准竞争。

## 6. 相关入口

- [工程治理 Spec](../specs/governance.md)
- [Issue 与 PR 关系规则](issue-relations.md)
- [贡献流程](../../CONTRIBUTING.md)
- [Worktree 只读审计](../../scripts/audit_worktrees.py)
- [Issue 关系审计](../../scripts/audit_issue_relations.py)
