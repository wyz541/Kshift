---
slug: /evidence/close-gate
title: Kshift 关单门禁验证
type: report
status: active
updated: "2026-11-24"
keywords:
  - close gate
  - worktree audit
  - issue relations
  - evidence
description: 记录 Kshift close-issue 门禁、拒绝路径和关闭后审计实现。
---

# Kshift 关单门禁验证

> 结论：本地关闭入口、机器可读记录校验和关闭后审计已实现。缺少记录的关闭会被拒绝，且不会修改 GitHub Issue 状态。

## 实现入口

| 对象 | 路径 |
| --- | --- |
| Close gate | `scripts/close_issue.py` |
| Closed issue audit | `scripts/audit_closed_issues.py` |
| Tests | `scripts/test_close_issue.py` |
| Make targets | `make close-issue`、`make audit-closed-issues` |
| Governance | `docs/governance/close-gate.md` |

## 验证结果

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| Close gate unit tests | `python3 scripts/test_close_issue.py` | 11 passed |
| R0 | `./scripts/check-r0.sh` | passed |
| Missing record rejection | `make close-issue ISSUE=65 DRY_RUN=1` | exit 2；Issue 保持 OPEN |
| Closed audit | `make audit-closed-issues LIMIT=5` | 5 个近期直接关闭的 Issue 被报告为缺少记录 |
| Default dry-run | `make close-issue ISSUE=<N>` | 默认只检查，不关闭 |
| Apply path | `make close-issue ISSUE=<N> APPLY=1` | 仅在记录和审计全部通过后调用 `gh issue close` |

## 关闭记录

Issue 使用 `kshift-close-gate` HTML 注释记录：

```text
<!-- kshift-close-gate: {"schemaVersion":1,"issue":65,"status":"cleaned","worktree":"~/repo/_worktrees/Kshift/issue-65-close-gate","branch":"issue/65-close-gate","generatedArtifacts":["target/"],"evidenceTargets":["PR #XXX","Issue #65"],"checks":{"issueRelations":"PASS","worktreeAudit":"cleanup-candidate","mainClean":true},"approver":"@wyz541","approvedAt":"2026-11-24T16:50:40+08:00"} -->
```

`retained` 必须有 owner、原因和 14 天内复核日期；`not-applicable` 必须写明原因。记录不得包含秘密或数据库凭据。

## 边界

- 网页关闭和直接 `gh issue close` 无法被本地脚本阻止。
- `audit-closed-issues` 负责发现绕过；历史 Issue 不会被自动重开。
- GitHub `issues.closed` 自动重开未启用；它需要额外的权限、并发和人工复核设计。
- 本实现不删除任何 Worktree、branch、构建目录或用户文件。
